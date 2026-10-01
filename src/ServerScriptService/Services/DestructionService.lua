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
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false

--- Prefijo de nombre que marca un bloque como destruible.
Service.BLOCK_PREFIX = "Block_"

-- Bloque -> vida restante.
Service._blocks = {}
-- Posicion original de cada bloque, para poder repararlo.
Service._origins = {}

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
--- @param block BasePart
--- @param amount number
--- @return boolean destroyed true si este golpe lo destruyo
function Service.ApplyDamage(block: BasePart, amount: number): boolean
	if not Service.IsDestructibleBlock(block) or not block.Parent then
		return false
	end

	-- Un bloque sin registro (por ejemplo, creado despues del arranque)
	-- se registra aqui con su vida inicial.
	local health = Service._blocks[block]
	if health == nil then
		health = GameConfig.BlockHealth
		Service._origins[block] = block.Position
	end

	health -= amount
	Service._blocks[block] = health

	if health > 0 then
		return false
	end

	Service._blocks[block] = nil
	Service._origins[block] = nil
	block:Destroy()

	return true
end

--- Devuelve todos los bloques destruidos a su sitio y su vida completa.
--- @return number restored
function Service.RestoreAll(): number
	local restored = 0

	for block, origin in pairs(Service._origins) do
		if block.Parent then
			block.Position = origin
			block.Transparency = 0
			Service._blocks[block] = GameConfig.BlockHealth
			restored += 1
		else
			Service._origins[block] = nil
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

function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._blocks = {}
	Service._origins = {}

	local total = Service.CollectBlocks()
	Logger.Info(("DestructionService: %d bloques destructibles en el mapa"):format(total))

	if total == 0 then
		-- No es un error fatal: la arena puede no tener bloques todavia.
		-- Se avisa para que el fallo sea visible y no silencioso.
		Logger.Warn("DestructionService: el mapa no tiene bloques 'Block_'; la destruccion no tendra efecto.")
		return true
	end

	-- Registrar vida y posicion de cada bloque. Se recorre el mapa en
	-- lugar de usar el generador para que el servicio funcione con
	-- cualquier mapa que cumpla el prefijo.
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if Service.IsDestructibleBlock(instance) then
			local block = instance :: BasePart
			Service._blocks[block] = GameConfig.BlockHealth
			Service._origins[block] = block.Position
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
	Service._origins = {}
	return true
end

return Service