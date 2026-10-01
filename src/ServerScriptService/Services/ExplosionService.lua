--!strict
--[[
	ExplosionService
	Resolucion de dano por area de una explosion.

	Es la UNICA fuente de dano por explosion en el servidor. El cliente
	nunca aplica dano: solo pide colocar una bomba, y el resto lo decide
	este servicio.

	Cadena de una explosion:
		1. Recoger partes dentro del radio.
		2. Dano a Humanoids, con caida lineal segun la distancia.
		3. Dano a bloques destructibles, delegando en DestructionService.

	Regla de seguridad: el RADIO NUNCA se toma del cliente. Viene de
	GameConfig y la peticion del cliente solo indica la posicion.
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

-- DestructionService se inyecta para no crear una dependencia circular
-- entre servicios: el registro lo pasa al arrancar.
Service._destruction = nil

--- Inyecta el servicio de destruccion.
--- @param destructionService any
function Service.SetDestructionService(destructionService: any)
	Service._destruction = destructionService
end

--- Cantidad de explosiones procesadas (diagnostico).
Service._explosionCount = 0

--- Cantidad de explosiones procesadas.
--- @return number
function Service.GetExplosionCount(): number
	return Service._explosionCount
end

--- Partes dentro del radio de la explosion.
---
--- `GetPartBoundsInRadius` respeta las colisiones, asi que un muro
--- entre la bomba y un jugador lo protege. Es la razon de usarlo en
-- lugar de comparar distancias a mano.
--- @param center Vector3
--- @param radius number
--- @return { BasePart }
local function getPartsInRadius(center: Vector3, radius: number): { BasePart }
	local query = OverlapParams.new()
	query.FilterType = Enum.RaycastFilterType.Include
	query.FilterDescendantsInstances = { Workspace }
	query.RespectCanCollide = true

	local parts = {}

	for _, instance in ipairs(Workspace:GetPartBoundsInRadius(center, radius, query)) do
		table.insert(parts, instance :: BasePart)
	end

	return parts
end

--- Dano por distancia: maximo en el centro, cero en el borde.
--- @param distance number
--- @param radius number
--- @return number damage
function Service.ComputeDamage(distance: number, radius: number): number
	if radius <= 0 then
		return 0
	end

	local falloff = 1 - math.clamp(distance / radius, 0, 1)
	return GameConfig.DefaultBombDamage * falloff
end

--- Resuelve una explosion en el servidor.
--- @param center Vector3
--- @param radius number
--- @return number affected partes afectadas
function Service.Detonate(center: Vector3, radius: number): number
	-- Un radio no positivo o una posicion no finita indicaria un bug o
	-- un intento de exploit: se ignora sin propagar el error.
	if radius <= 0 or center.X ~= center.X or center.Y ~= center.Y or center.Z ~= center.Z then
		Logger.Warn(("explosion ignorada: centro=%s radio=%s"):format(tostring(center), tostring(radius)))
		return 0
	end

	Service._explosionCount += 1

	local affected = 0
	-- Humanoids ya tocados: un personaje con varias partes dentro del
	-- radio solo debe recibir dano una vez.
	local damagedHumanoids = {}

	for _, part in ipairs(getPartsInRadius(center, radius)) do
		local ancestor = part.Parent

		if ancestor then
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")

			if humanoid and not damagedHumanoids[humanoid] then
				damagedHumanoids[humanoid] = true

				local character = humanoid.Parent
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local distance = if rootPart then (rootPart.Position - center).Magnitude else 0
				local damage = Service.ComputeDamage(distance, radius)

				if damage > 0 then
					humanoid:TakeDamage(damage)
					affected += 1
					Logger.Debug(("explosion: %.0f de dano a %s"):format(damage, humanoid.Name))
				end
			end
		end

		if Service._destruction and Service._destruction.ApplyDamage(part, GameConfig.BlockHealth) then
			affected += 1
		end
	end

	Logger.Debug(("explosion resuelta: %d afectadas (radio %.1f)"):format(affected, radius))

	return affected
end

--- Inicializacion del servicio. Idempotente.
--- @param maid any?
--- @return boolean success
function Service.Init(maid: any?): boolean
	if Service.IsInitialized then
		return true
	end

	Service._explosionCount = 0
	Service.IsInitialized = true

	return true
end

--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		Logger.Error("ExplosionService: Start sin Init")
		return false
	end

	if not Service._destruction then
		Logger.Warn("ExplosionService: sin DestructionService; los bloques no se destruiran.")
	end

	return true
end

--- @return boolean success
function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._destruction = nil
	Service._explosionCount = 0
	return true
end

return Service
