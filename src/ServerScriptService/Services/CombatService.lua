--!strict
--[[
	CombatService
	Autoridad UNICA de dano en el servidor (FASE 8).

	Por que existe:
	Antes, `ExplosionService` llamaba a `humanoid:TakeDamage` directamente.
	Eso rompia tres reglas del proyecto:

	1. No habia INVULNERABILIDAD: una bomba explotando en el instante del
	   teletransporte mataba a un jugador que aun no se orientaba.
	2. No habia ATRIBUCION: nadie sabia QUIEN habia matado a quien, asi
	   que `XPPerKill` y `CoinsPerKill` no se usaban nunca.
	3. No habia un unico punto de control: cada sistema de dano anadiria
	   sus propias reglas y divergirian entre si.

	Regla: NADIE llama a `TakeDamage` directamente. Todo el dano pasa por
	`Service.ApplyDamage`, que decide si es legal, a quien se aplica y
	quien lo causo. El cliente nunca envia dano.

	Cadena de una muerte:
		ExplosionService
		  -> CombatService.ApplyDamage(victima, dano, sourceUserId)
		    -> validaciones (ronda, invulnerabilidad, vida)
		    -> humanoid:TakeDamage
		Humanoid.Died
		  -> CombatService.OnHumanoidDied
		    -> atribucion al asesino
		    -> PlayerService.OnPlayerDied (estado y ronda)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local GameConstants = require(SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"))
local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local CombatRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local RoundState = GameConstants.RoundState

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por ServerMain.
Service._roundService = nil
Service._playerService = nil

-- MonsterService: quien aplica el dano del combate cuerpo a cuerpo
-- sobre SU registro (mision V2, FASE 8). Opcional: sin el, el melee
-- no tiene victimas y se rechaza limpio.
Service._monsterService = nil

-- Cooldowns y combos del combate V2, por userId. La cadena vive AQUI
-- y nunca la manda el cliente: un cliente que pudiera mandar su paso
-- de combo pediria el especial en cada golpe.
Service._cooldowns = {}
Service._combos = {}

-- UserId -> momento (os.clock) hasta el que es invulnerable.
Service._invulnerableUntil = {}
-- Conexiones de `Died` del personaje actual de cada jugador.
-- Se sustituyen en cada reaparicion y se sueltan al salir: sin esto,
-- un jugador que reaparece acumula conexiones y su muerte se procesa
-- varias veces.
Service._deathConnections = {}
-- Estadisticas (diagnostico / anti-exploit).
Service._damageEvents = 0
Service._blockedDamage = 0
Service._kills = {}

local MaidRef = nil

--- Inyecta las dependencias del servicio.
--- @param roundService any
--- @param playerService any
--- @param monsterService any? (mision V2: victimas del cuerpo a cuerpo)
function Service.SetDependencies(roundService: any, playerService: any, monsterService: any?)
	Service._roundService = roundService
	Service._playerService = playerService
	Service._monsterService = monsterService
end

--- Jugador al que pertenece un Humanoid, o nil.
--- @param humanoid Humanoid?
--- @return Player?
local function playerFromHumanoid(humanoid: Humanoid?): Player?
	if not humanoid then
		return nil
	end

	local character = humanoid.Parent
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

--- Marca al jugador como invulnerable durante unos segundos.
---
--- Se aplica al entrar en la arena y al reaparecer. Sin esto, la
--- primera bomba de la ronda mata a un jugador que acaba de aparecer.
--- @param player Player
--- @param seconds number?
function Service.GrantInvulnerability(player: Player, seconds: number?)
	local duration = seconds or GameConfig.SpawnProtectionTime
	Service._invulnerableUntil[player.UserId] = os.clock() + duration
	player:SetAttribute("IsInvulnerable", true)
end

--- Indica si el jugador es invulnerable ahora mismo.
---
--- El atributo se sincroniza con el reloj del servidor para que el
--- cliente pueda MOSTRAR el estado, sin decidir nada.
--- @param userId number
--- @return boolean
function Service.IsInvulnerable(userId: number): boolean
	local untilTime = Service._invulnerableUntil[userId]

	if not untilTime then
		return false
	end

	if os.clock() < untilTime then
		return true
	end

	-- La ventana ya paso: se limpia para no retener la entrada.
	Service._invulnerableUntil[userId] = nil

	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("IsInvulnerable", false)
	end

	return false
end

--- Multiplicador de dano segun el estado de la ronda.
---
--- En muerte subita el dano sube: es lo que da consecuencias reales
--- al estado en lugar de dejarlo decorativo.
--- @return number
function Service.GetDamageMultiplier(): number
	if not Service._roundService then
		return 1
	end

	if Service._roundService.GetState() == RoundState.SuddenDeath then
		return GameConfig.SuddenDeathDamageMultiplier
	end

	return 1
end

--- Aplica dano a un jugador respetando las reglas de combate.
---
--- @param targetHumanoid Humanoid
--- @param amount number dano ya calculado por distancia
--- @param sourceUserId number? quien lo causo (para atribucion)
--- @return boolean applied false si se rechazo
--- @return string? reason motivo del rechazo
function Service.ApplyDamage(
	targetHumanoid: Humanoid,
	amount: number,
	sourceUserId: number?
): (boolean, string?)
	if not CombatMath.IsFiniteNumber(amount) or amount <= 0 then
		Service._blockedDamage += 1
		return false, "dano invalido"
	end

	if targetHumanoid.Health <= 0 then
		return false, "ya esta muerto"
	end

	local targetPlayer = playerFromHumanoid(targetHumanoid)

	if not targetPlayer then
		return false, "sin jugador"
	end

	-- Invulnerabilidad primero: sin ella, una bomba en el instante del
	-- spawn mataria de forma injusta.
	if Service.IsInvulnerable(targetPlayer.UserId) then
		Service._blockedDamage += 1
		return false, "invulnerable"
	end

	-- Solo se hace dano con ronda en curso. El lobby es zona segura:
	-- sin esta regla se podrian colocar bombas en el lobby para matar a
	-- quien esta en un menu.
	if Service._roundService and not Service._roundService.IsPlaying() then
		Service._blockedDamage += 1
		return false, "no hay ronda en curso"
	end

	local finalDamage = CombatMath.ApplyOcclusion(
		true,
		CombatMath.FalloffDamage(0, 1, amount, Service.GetDamageMultiplier())
	)

	if finalDamage <= 0 then
		return false, "dano anulado"
	end

	Service._damageEvents += 1
	targetHumanoid:TakeDamage(finalDamage)

	-- Atribucion: vive en el Humanoid, no en una tabla global, porque
	-- muere con su personaje y no puede quedar obsoleta.
	if sourceUserId and sourceUserId ~= targetPlayer.UserId then
		targetHumanoid:SetAttribute("LastDamageSource", sourceUserId)
	end

	Logger.Debug(("%s recibe %.0f de dano"):format(targetPlayer.Name, finalDamage))
	return true, nil
end

--- Procesa la muerte de un personaje.
---
--- Es el unico sitio donde se decide que pasa cuando alguien muere:
--- atribuye el asesino y avisa a PlayerService.
--- @param humanoid Humanoid
function Service.OnHumanoidDied(humanoid: Humanoid)
	local victim = playerFromHumanoid(humanoid)

	if not victim then
		return
	end

	local killerId = humanoid:GetAttribute("LastDamageSource")
	local killer = if type(killerId) == "number" then Players:GetPlayerByUserId(killerId) else nil

	-- Se limpia el atributo: reutilizar el Humanoid no debe heredar el
	-- asesino de una muerte anterior.
	humanoid:SetAttribute("LastDamageSource", nil)

	-- Autociudad-muerte: uno no se premia a si mismo.
	if killer and killer.UserId == victim.UserId then
		killer = nil
	end

	if killer then
		Service._kills[killer.UserId] = (Service._kills[killer.UserId] or 0) + 1
	end

	if Service._playerService then
		Service._playerService.OnPlayerDied(victim, killer)
	end
end

--- Conecta el ciclo de muerte del personaje actual de un jugador.
---
--- Sustituye SIEMPRE la conexion anterior de ese jugador: sin esto,
--- cada reaparicion deja la conexion vieja viva y la muerte se
--- procesa varias veces.
--- @param player Player
--- @return Humanoid?
local function bindHumanoid(player: Player): Humanoid?
	local character = player.Character

	if not character then
		return nil
	end

	local humanoidInstance = character:WaitForChild("Humanoid", 10)

	if not humanoidInstance or not humanoidInstance:IsA("Humanoid") then
		Logger.Error(("%s: el personaje no tiene Humanoid"):format(player.Name))
		return nil
	end

	for _, connection in ipairs(Service._deathConnections[player.UserId] or {}) do
		connection:Disconnect()
	end

	local connection = humanoidInstance.Died:Connect(function()
		Service.OnHumanoidDied(humanoidInstance)
	end)

	Service._deathConnections[player.UserId] = { connection }
	return humanoidInstance
end

--- Prepara un personaje para el combate. Lo invoca PlayerService.
--- @param player Player
--- @return boolean success
function Service.BindCharacter(player: Player): boolean
	return bindHumanoid(player) ~= nil
end

--- Limpia el estado de combate de un jugador que sale.
--- @param userId number
function Service.ClearPlayer(userId: number)
	Service._invulnerableUntil[userId] = nil
	Service._cooldowns[userId] = nil
	Service._combos[userId] = nil

	for _, connection in ipairs(Service._deathConnections[userId] or {}) do
		connection:Disconnect()
	end

	Service._deathConnections[userId] = nil
end

-- ---------------------------------------------------------------------------
-- COMBATE V2: ataque rapido, dash y habilidad (MASTER MISSION V2 - FASE 8)
-- ---------------------------------------------------------------------------

--- Comprobaciones comunes a las tres acciones: jugador vivo, ronda en
--- curso y cooldown cumplido. Devuelve el humanoid y la raiz listos.
--- @param player Player
--- @param action string clave del cooldown ("Melee"/"Dash"/"Ability")
--- @param cooldown number
--- @return Humanoid? humanoid
--- @return BasePart? root
local function readyFor(player: Player, action: string, cooldown: number): (Humanoid?, BasePart?)
	-- La ronda tiene que estar en curso: el lobby es zona segura, y un
	-- golpe en el lobby es exactamente el "bomba en el menu" que la
	-- misma regla impide en `ApplyDamage`.
	if Service._roundService and not Service._roundService.IsPlaying() then
		return nil, nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil, nil
	end

	local now = os.clock()
	local cooldowns = Service._cooldowns[player.UserId]

	if not cooldowns then
		cooldowns = {}
		Service._cooldowns[player.UserId] = cooldowns
	end

	if not CombatRules.IsReady(cooldowns[action], cooldown, now) then
		return nil, nil
	end

	cooldowns[action] = now
	return humanoid, root
end

--- Ataque rapido cuerpo a cuerpo.
---
--- El cliente NO manda objetivo ni dano: el servidor golpea a lo que
--- este delante segun `CombatRules.InArc`, y la cadena de combo vive en
--- `_combos`. Un cliente que mandara el paso de combo pediria el
--- especial en cada golpe.
--- @param player Player
--- @return boolean swung el golpe salio (haya o no victimas)
function Service.TryMelee(player: Player): boolean
	local _, root = readyFor(player, "Melee", CombatRules.Melee.Cooldown)

	if not root then
		return false
	end

	local monsters = Service._monsterService

	if not monsters or not monsters.DamageInArc then
		return false
	end

	local now = os.clock()
	local combo = Service._combos[player.UserId]

	if not combo then
		combo = { Count = 0, LastAt = 0 }
		Service._combos[player.UserId] = combo
	end

	local step = CombatRules.ComboStep(combo.Count, combo.LastAt, now)
	combo.Count = step
	combo.LastAt = now

	local damage = CombatRules.DamageFor(step)
	local look = root.CFrame.LookVector

	monsters.DamageInArc(
		root.Position,
		look,
		CombatRules.Melee.Range,
		CombatRules.Melee.MinDot,
		damage,
		player.UserId
	)

	-- El paso de combo se publica para que el cliente pueda MOSTRAR el
	-- especial (distinto color/sonido). Lo decide el servidor.
	player:SetAttribute("ComboStep", step)

	return true
end

--- Dash: impulso hacia donde mira el jugador, con invulnerabilidad
--- breve. La esquiva de verdad del combate V2.
--- @param player Player
--- @return boolean dashed
function Service.TryDash(player: Player): boolean
	local _, root = readyFor(player, "Dash", CombatRules.Dash.Cooldown)

	if not root then
		return false
	end

	-- Impulso por MASA: un personaje pesado y uno ligero se mueven lo
	-- mismo, que es lo que el jugador espera de SU dash.
	local direction = root.CFrame.LookVector
	local impulse = direction * CombatRules.Dash.Impulse * root.AssemblyMass

	root:ApplyImpulse(impulse)
	Service.GrantInvulnerability(player, CombatRules.Dash.InvulnerabilitySeconds)

	player:SetAttribute("DashAt", os.clock())

	return true
end

--- Habilidad: golpe en area alrededor del jugador, cooldown largo.
--- @param player Player
--- @return boolean cast
function Service.TryAbility(player: Player): boolean
	local _, root = readyFor(player, "Ability", CombatRules.Ability.Cooldown)

	if not root then
		return false
	end

	local monsters = Service._monsterService

	if not monsters or not monsters.DamageInArc then
		return false
	end

	-- MinDot -1: el area es circular, no hay direccion que apuntar.
	monsters.DamageInArc(
		root.Position,
		Vector3.new(0, 0, 1),
		CombatRules.Ability.Range,
		CombatRules.Ability.MinDot,
		CombatRules.Ability.Damage,
		player.UserId
	)

	player:SetAttribute("AbilityAt", os.clock())

	return true
end

--- Estadisticas de combate (diagnostico).
--- @return { damageEvents: number, blockedDamage: number, kills: number }
function Service.GetReport()
	local kills = 0
	for _ in pairs(Service._kills) do
		kills += 1
	end

	return {
		damageEvents = Service._damageEvents,
		blockedDamage = Service._blockedDamage,
		kills = kills,
	}
end

function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	MaidRef = maid
	Service._invulnerableUntil = {}
	Service._deathConnections = {}
	Service._cooldowns = {}
	Service._combos = {}
	Service._damageEvents = 0
	Service._blockedDamage = 0
	Service._kills = {}

	if MaidRef then
		MaidRef:Connect(Players.PlayerRemoving, function(player: Player)
			Service.ClearPlayer(player.UserId)
		end)
	end

	Service.IsInitialized = true
	Logger.Info("CombatService listo (autoridad unica de dano).")
	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("CombatService: Start sin Init")
		return false
	end

	if not Service._roundService then
		Logger.Warn("CombatService: sin RoundService; el dano no dependera del estado de ronda.")
	end

	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	for _, connections in pairs(Service._deathConnections) do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end

	Service._deathConnections = {}
	Service._invulnerableUntil = {}
	Service._kills = {}
	Service._roundService = nil
	Service._playerService = nil
	MaidRef = nil
	Service.IsInitialized = false

	return true
end

return Service
