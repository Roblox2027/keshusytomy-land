-- Diagnostico de por que el perfil no se cargo.
local Services = game.ServerScriptService.Services
local Players = game:GetService("Players")

local out = {}
local function say(l)
	table.insert(out, l)
end

-- `ServerMain` es un Script, no un ModuleScript: NO se puede requerir.
-- Por eso no se consulta su estado aqui; lo que importa es si el perfil
-- llego a cargarse, y eso se ve en `ProfileService`.

local player = Players:GetPlayers()[1]
say("jugadores=" .. tostring(#Players:GetPlayers()))
if player then
	say("jugador=" .. player.Name)
end

local DataService = require(Services.DataService)
say("dataStore_abierto=" .. tostring(DataService._dataStore ~= nil))
local stats = DataService.GetStats()
say("stats_cargas=" .. tostring(stats.loads))
say("stats_persistentes=" .. tostring(stats.persistent))

local Profile = require(Services.ProfileService)
say("perfiles_en_memoria=" .. tostring(Profile.GetLoadedCount()))
say("dataService_inyectado=" .. tostring(Profile._dataService ~= nil))
say("perfil_directo=" .. tostring(Profile.GetProgressionState(player)))

-- Intento de carga explicita, para separar "no se llamo" de "falla al cargar".
if player then
	local ok, err = Profile.LoadProfile(player)
	say("carga_explicita_ok=" .. tostring(ok))
	say("carga_explicita_err=" .. tostring(err))
	say("perfiles_tras_carga=" .. tostring(Profile.GetLoadedCount()))
end

return table.concat(out, "\n")