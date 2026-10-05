-- ensure-modules.lua
-- Crea en Studio los ModuleScript que el SOURCE declara y Studio NO tiene.
--
-- POR QUE EXISTE
-- --------------
-- `tools/sync-scripts.js` solo REESCRIBE el fuente de instancias que ya
-- existen (`set_script_source`). No sabe crear nada. Con el plugin de Rojo
-- desconectado, un modulo NUEVO del repositorio se quedaba en el source:
--
--   ReplicatedStorage.Shared.Libraries.AudioRules
--   ReplicatedStorage.Shared.Libraries.BlockRespawnRules
--   ReplicatedStorage.Shared.Libraries.BombButtonRules
--   ReplicatedStorage.Shared.Libraries.MonsterScaleRules
--   ReplicatedStorage.Shared.Libraries.VisualKit
--   ServerScriptService.Services.PowerupService
--
-- y `sync-scripts` acababa en FAIL con "no se pudo leer el fuente real en
-- Studio". El source era correcto y Studio no tenia ni la forma ni el fuente.
--
-- QUE HACE
-- --------
-- 1. Crea los contenedores intermedios que falten (Folders).
-- 2. Crea el ModuleScript vacio si no existe.
-- 3. NO escribe fuente: de eso se encarga `sync-scripts.js`, que ademas
--    verifica el hash contra el disco. Aqui solo se arregla la FORMA.
--
-- Es idempotente: si ya existe, no toca nada.

local targets = {
	{ path = { "ReplicatedStorage", "Shared", "Libraries", "AudioRules" } },
	{ path = { "ReplicatedStorage", "Shared", "Libraries", "BlockRespawnRules" } },
	{ path = { "ReplicatedStorage", "Shared", "Libraries", "BombButtonRules" } },
	-- `HudLayout` entra aqui por el MISMO motivo que los demas: es un modulo
	-- NUEVO del source y Studio no puede crearlo solo. Sin esta linea,
	-- `sync-scripts` acaba en FAIL con "no se pudo leer el fuente real" y el
	-- HUD se queda sin su tabla de zonas en tiempo de ejecucion.
	{ path = { "ReplicatedStorage", "Shared", "Libraries", "HudLayout" } },
	{ path = { "ReplicatedStorage", "Shared", "Libraries", "MonsterScaleRules" } },
	{ path = { "ReplicatedStorage", "Shared", "Libraries", "VisualKit" } },
	{ path = { "ServerScriptService", "Services", "PowerupService" } },
}

local created = {}
local existed = {}

for _, target in ipairs(targets) do
	local parent = game
	local built = {}

	for index = 1, #target.path - 1 do
		local name = target.path[index]
		local existing = parent:FindFirstChild(name)
		if not existing then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = parent
			table.insert(created, table.concat(target.path, ".") .. " (carpeta " .. name .. ")")
			existing = folder
		end
		parent = existing
		table.insert(built, name)
	end

	local name = target.path[#target.path]
	local module = parent:FindFirstChild(name)
	if module then
		table.insert(existed, table.concat(target.path, "."))
	else
		local created2 = Instance.new("ModuleScript")
		created2.Name = name
		created2.Source = "--!strict\n-- placeholder: `sync-scripts.js` escribe el fuente real.\nreturn {}\n"
		created2.Parent = parent
		table.insert(created, table.concat(target.path, "."))
	end
end

return string.format("creados: %d | ya existian: %d | %s", #created, #existed, table.concat(created, ", "))