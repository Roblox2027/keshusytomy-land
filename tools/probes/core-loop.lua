-- Estado del ciclo de ronda: comprueba que la columna economica NO ha
-- roto el bucle que ya estaba certificado.
--
-- Solo se consultan metodos que EXISTEN de verdad. Cada API que se invoca
-- aqui esta verificada contra el source, porque llamar a un metodo
-- inexistente aborta todo el probe con "Requested module experienced an
-- error while loading" y no distingue "el nucleo fallo" de "la sonda
-- pregunto mal".
local Services = game.ServerScriptService.Services
local Round = require(Services.RoundService)
local Monster = require(Services.MonsterService)

local out = {}
local function say(l)
	table.insert(out, l)
end

say("ronda_estado=" .. tostring(Round.GetState()))
say("ronda_numero=" .. tostring(Round.GetRoundNumber()))
say("jugando=" .. tostring(Round.IsPlaying()))
say("vivos=" .. tostring(Round.GetAliveCount()))
say("monstruos_vivos=" .. tostring(Monster.GetAliveCount()))

return table.concat(out, "\n")