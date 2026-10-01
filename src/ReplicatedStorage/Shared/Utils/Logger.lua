--!strict
--[[
	Logger
	Logger centralizado del proyecto.

	Seguridad: nunca registres tokens, claves, credenciales,
	identificadores de DataStore ni datos personales.
	Este modulo no acepta ningun valor de configuracion sensible.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(SHARED:WaitForChild("Config"):WaitForChild("GameConfig"))

local PREFIX = "[KeshusyTomy-LanD]"

local Logger = {}

local function format(...)
	local parts = {}
	local n = select("#", ...)
	for i = 1, n do
		local value = select(i, ...)
		parts[i] = tostring(value)
	end
	return table.concat(parts, " ")
end

local function debugEnabled(): boolean
	return GameConfig.DebugMode == true
end

function Logger.Info(...)
	print(("%s INFO: %s"):format(PREFIX, format(...)))
end

function Logger.Warn(...)
	warn(("%s WARN: %s"):format(PREFIX, format(...)))
end

-- ERROR NUNCA lanza una excepcion.
--
-- Regla: un log no debe cambiar el flujo del programa. Antes esta
-- funcion usaba `error(...)`, de modo que CUALQUIER registro de error
-- abortaba la funcion que lo emitia. Por ejemplo, `Registry:_ResolveOrder`
-- registra un error y despues hace `return false`: con `error(...)` la
-- excepcion escapaba de `Registry:Start()` y el servidor no arrancaba.
--
-- La severidad se marca en la salida de Studio. El fallo se propaga
-- mediante el valor de retorno de cada funcion, nunca con una
-- excepcion no controlada.
function Logger.Error(...)
	warn(("%s ERROR: %s"):format(PREFIX, format(...)))
end

function Logger.Debug(...)
	if not debugEnabled() then
		return
	end
	print(("%s DEBUG: %s"):format(PREFIX, format(...)))
end

function Logger.GetGameName(): string
	return GameConfig.GameName
end

function Logger.GetGameVersion(): string
	return GameConfig.GameVersion
end

return Logger
