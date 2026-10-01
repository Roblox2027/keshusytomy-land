--!strict
--[[
	DestructionService
	Gestiona la vida y la destruccion de los bloques del mapa.

	Un bloque es destruible si su nombre empieza por `Block_`. Ese
	prefijo es el CONTRATO con `tools/generate-project.js`, que genera
	el mapa: si el prefijo cambia, hay que cambiarlo aqui tambien.

	El servicio NO decide quien recibe el dano: eso lo hace
	ExplosionService, que llama a `ApplyDamage` sobre lo que esta dentro
	del radio. Aqui solo se aplica dano, se destruye y se repara.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local CombatMath = require(SHARED:WaitForChild("Libraries"):WaitForChild("CombatMath"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

--- Prefijo de nombre que marca un bloque como destruible.
Service.BLOCK_PREFIX = "Block_"

-- Bloque -> vida restante.
Service._blocks = {}
-- Bloque -> estado original (vida, transparencia, colision, material).
--
-- POR QUE EXISTE ESTA TABLA Y NO UNA DE "POSICIONES":
-- La version anterior hacia `block:Destroy()` al destruirlo y borraba
-- su origen. `RestoreAll` solo restauraba los bloques que seguian
-- vivos, asi que tras la primera ronda la arena se quedaba VACIA para
-- siempre: no habia nada que restaurar. El bloque ahora se SECRETA
-- (transparente y sin colision) en lugar de destruirse, y esta tabla
-- conserva su estado original para poder repararlo.
Service._originals = {}

--- Estado original de un bloque, para restaurarlo.
--- @param block BasePart
--- @return { Health: number, Transparency: number, CanCollide: boolean, CanTouch: boolean }
local function snapshotBlock(block: BasePart)
	return {
		Health = GameConfig.BlockHealth,
		Transparency = block.Transparency,
		CanCollide = block.CanCollide,
		CanTouch = block.CanTouch,
	}
end

--- Indica si una instancia es un bloque destruible del mapa.
--- @param instance Instance?
--- @return boolean
function Service.IsDestructibleBlock(instance: Instance?): boolean
	if not instance or not instance:IsA("BasePart") then
		return false
	end

	return string.sub(instance.Name, 1, #Service.BLOCK_PREFIX) == Service.BLOCK_PREFIX
end

--- Localiza todos los bloques destruibles del Workspace.
--- @return number total
function Service.CollectBlocks(): number
	local total = 0

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if Service.IsDestructibleBlock(instance) then
			total += 1
		end
	end

	return total
end

--- Vida actual de un bloque. 0 si ya fue destruido o no es bloque.
--- @param block BasePart
--- @return number
function Service.GetBlockHealth(block: BasePart): number
	return Service._blocks[block] or 0
end

--- Aplica dano a un bloque y lo destruye si llega a 0.
---
--- Al destruirse NO se llama a `Destroy()`: el bloque se oculta y deja
--- de colisionar. Se conserva en el Workspace para que la ronda
--- siguiente pueda repararlo. Destruirlo de verdad hacia que la arena
--- se quedase vacia tras la primera ronda.
--- @param block BasePart
--- @param amount number
--- @return boolean destroyed true si este golpe lo destruyo
function Service.ApplyDamage(block: BasePart, amount: number): boolean
	if not Service.IsDestructibleBlock(block) or not block.Parent then
		return false
	end

	-- Un bloque sin registro (creado despues del arranque) se registra
	-- aqui con su estado original.
	local health = Service._blocks[block]
	if health == nil then
		health = GameConfig.BlockHealth
		Service._originals[block] = snapshotBlock(block)
	end

	health = CombatMath.ApplyBlockDamage(health, amount)
	Service._blocks[block] = health

	if health > 0 then
		return false
	end

	-- Destruido: invisible e intangible, pero presente en el mapa.
	block.Transparency = 1
	block.CanCollide = false
	block.CanTouch = false
	block:SetAttribute("IsDestroyed", true)

	Logger.Debug(("bloque destruido: %s"):format(block.Name))
	return true
end

--- Devuelve todos los bloques a su estado original.
--- @return number restored
function Service.RestoreAll(): number
	local restored = 0

	for block, original in pairs(Service._originals) do
		-- Un bloque que ya no existe (borrado desde el editor o por
		-- StreamingEnabled) se descarta de la tabla para no retener una
		-- referencia muerta durante toda la partida.
		if block.Parent then
			block.Transparency = original.Transparency
			block.CanCollide = original.CanCollide
			block.CanTouch = original.CanTouch
			block:SetAttribute("IsDestroyed", false)

			Service._blocks[block] = original.Health
			restored += 1
		else
			Service._originals[block] = nil
			Service._blocks[block] = nil
		end
	end

	return restored
end

--- Cantidad de bloques todavia en pie.
--- @return number
function Service.GetAliveBlockCount(): number
	local count = 0
	for _ in pairs(Service._blocks) do
		count += 1
	end
	return count
end

--- Cantidad de bloques destruidos y pendientes de reparar.
--- @return number
function Service.GetDestroyedBlockCount(): number
	local destroyed = 0

	for block, health in pairs(Service._blocks) do
		if health <= 0 and block.Parent then
			destroyed += 1
		end
	end

	return destroyed
end

function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._blocks = {}
	Service._originals = {}

	local total = Service.CollectBlocks()
	Logger.Info(("DestructionService: %d bloques destructibles en el mapa"):format(total))

	if total == 0 then
		-- No es un error fatal: la arena puede no tener bloques todavia.
		-- Se avisa para que el fallo sea visible y no silencioso.
		Logger.Warn("DestructionService: el mapa no tiene bloques 'Block_'; la destruccion no tendra efecto.")
		Service.IsInitialized = true
		return true
	end

	-- Registrar vida y estado original de cada bloque. Se recorre el mapa
	-- en lugar de usar el generador para que el servicio funcione con
	-- cualquier mapa que cumpla el prefijo.
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if Service.IsDestructibleBlock(instance) then
			local block = instance :: BasePart
			Service._blocks[block] = GameConfig.BlockHealth
			Service._originals[block] = snapshotBlock(block)
			block:SetAttribute("IsDestroyed", false)
		end
	end

	Service.IsInitialized = true
	Logger.Info(("DestructionService: %d bloques registrados"):format(Service.GetAliveBlockCount()))

	return true
end

function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("DestructionService: Start sin Init")
		return false
	end

	return true
end

function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._blocks = {}
	Service._originals = {}
	return true
end

return Service