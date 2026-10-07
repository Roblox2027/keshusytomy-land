--!strict
--[[
	LootService
	RECOMPENSAS DINAMICAS: entrega de drops (MASTER MISSION V2 - FASE 23/25).

	QUE HACE Y QUE DELEGA
	---------------------
	NO calcula tiradas: la tabla y las probabilidades son de `LootRules`
	(puro, probado). Este servicio aporta lo que el motor: el `math.random`,
	la entrega al inventario y el aviso al jugador.

	QUIEN LO LLAMA
	--------------
	`MonsterService.OnMonsterDied` lo notifica como observador opcional
	(el mismo patron que `MiniBossService`): con el, los enemigos sueltan
	materiales; sin el, los enemigos mueren y pagan igual, y lo unico que
	falta es el drop.

	LA REGLA DE AUTORIDAD
	---------------------
	El drop ENTRA por `InventoryService.AddItem` y las gemas por
	`EconomyService.GrantCurrency`: las dos unicas vias, con ledger e
	idempotencia. Este servicio no escribe en el perfil por su cuenta.

	RENDIMIENTO
	-----------
	Un drop es como mucho una escritura por muerte, y solo cuando la
	tirada da algo. No hay hilos ni sondeos.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local UTILS = SHARED:WaitForChild("Utils")

local LootRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("LootRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

-- Servicios inyectados por `ServerMain`.
Service._inventoryService = nil
Service._economyService = nil

-- Diagnostico.
Service._dropsGranted = 0

-- ---------------------------------------------------------------------------
-- INYECCION
-- ---------------------------------------------------------------------------

--- @param inventoryService any?
--- @param economyService any?
function Service.SetDependencies(inventoryService: any?, economyService: any?)
	Service._inventoryService = inventoryService
	Service._economyService = economyService
end

-- ---------------------------------------------------------------------------
-- ENTREGA
-- ---------------------------------------------------------------------------

--- Publica el drop como atributo para que el HUD lo anuncie.
---
--- Es un atributo Efimero (texto + reloj): el HUD lo muestra y el
--- siguiente drop lo sobrescribe. No hay acumulacion de estado.
--- @param player Player
--- @param itemId string
--- @param amount number
local function publishDrop(player: Player, itemId: string, amount: number)
	player:SetAttribute("LootDrop", ("%dx %s"):format(amount, itemId))
	player:SetAttribute("LootDropAt", os.clock())
end

--- Entrega UNA tirada al jugador, si cayo algo.
--- @param player any
--- @param itemId string?
--- @param amount number
--- @param source string
function Service.Grant(player: any, itemId: string?, amount: number, source: string)
	if not itemId or amount <= 0 then
		return
	end

	if type(player) ~= "userdata" and typeof and typeof(player) ~= "Instance" then
		return
	end

	local inventory = Service._inventoryService

	if not inventory or not inventory.AddItem then
		return
	end

	local ok = inventory.AddItem(player, itemId, amount, source, nil)

	if ok then
		Service._dropsGranted += 1
		publishDrop(player, itemId, amount)
	end
end

-- ---------------------------------------------------------------------------
-- OBSERVADORES
-- ---------------------------------------------------------------------------

--- Muerte de un monstruo: la tirada depende del TIPO.
---
--- `record` es el registro de `MonsterService`: lleva `Def` (con `IsBoss`
--- y el tier de mini-boss si lo tiene) y `WorldId`. La decision de QUE
--- tabla tirar sale de ahi, nunca del cliente.
--- @param killer any jugador que mato (nil = muerte sin dueno)
--- @param record any registro del monstruo
function Service.OnMonsterKilled(killer: any, record: any)
	if not killer or type(record) ~= "table" or type(record.Def) ~= "table" then
		return
	end

	local worldId = record.WorldId
	local def = record.Def

	if def.IsBoss then
		local itemId, amount, gems = LootRules.RollBossDrop(worldId)
		Service.Grant(killer, itemId, amount, "BossDefeated")

		-- Las gemas del boss entran por la via UNICA de monedas.
		local economy = Service._economyService

		if gems > 0 and economy and economy.GrantCurrency then
			pcall(economy.GrantCurrency, killer, "Gems", gems, "BossDerrotado", "LootService")
		end

		return
	end

	-- El mini-boss NO pasa por aqui: `MiniBossService` es quien sabe
	-- que el cadaver era suyo (y de que tier), y lo notifica por
	-- `OnMiniBossDefeated`. Leerlo de banderas del registro crearia
	-- dos verdades sobre la misma muerte.
	local itemId, amount = LootRules.RollMonsterDrop(worldId, math.random(), math.random())
	Service.Grant(killer, itemId, amount, "MonsterKilled")
end

--- Mini-boss derrotado: siempre suelta, y a veces doble.
--- @param killer any
--- @param worldId any
function Service.OnMiniBossDefeated(killer: any, worldId: any)
	if not killer then
		return
	end

	local itemId, amount = LootRules.RollMiniBossDrop(worldId, math.random())
	Service.Grant(killer, itemId, amount, "MiniBossDefeated")
end

-- ---------------------------------------------------------------------------
-- CICLO DE VIDA DEL SERVICIO
-- ---------------------------------------------------------------------------

--- Inicializacion. Idempotente.
--- @param _maid any?
--- @return boolean success
function Service.Init(_maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._dropsGranted = 0
	Service.IsInitialized = true
	return true
end

--- Arranque. No hay hilos: el servicio responde a muertes.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("LootService: Start sin Init")
		return false
	end

	Logger.Info("LootService: listo (drops por mundo, miniboss y boss).")
	return true
end

--- Apagado. Idempotente.
--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	return true
end

return Service
