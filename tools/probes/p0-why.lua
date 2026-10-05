-- p0-why.lua (SERVIDOR)
-- Por que el filtro de red dice `state_violation` si la ronda esta en
-- `Playing`.
--
-- Comprueba el VALOR EXACTO que `ServerMain` pasa como `serverState`, no el
-- estado que devuelve `RoundService` por su cuenta: el filtro no ve el estado,
-- ve lo que el servidor le entrega. Si los dos no coinciden, el culpable es
-- el que ENTREGA, no el que comprueba.

local Players = game:GetService("Players")
local Round = require(game.ServerScriptService.Services.RoundService)
local Bomb = require(game.ServerScriptService.Services.BombService)
local Rules = require(game.ReplicatedStorage.Shared.Libraries.AntiExploitRules)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

local player = Players:GetPlayers()[1]
if not player then return "sin jugador" end

local estado = Round.GetState()
say("RoundService.GetState() = %s", tostring(estado))
say("RoundService.IsPlaying() = %s", tostring(Round.IsPlaying()))
say("Mundo del jugador = %s", tostring(player:GetAttribute("World")))

local spec = Rules.Channels.BombAction.Place
say("")
say("spec.state = %s", tostring(spec.state))
say("spec.allowedStates = %s", tostring(spec.allowedStates))

if spec.allowedStates then
	for _, e in ipairs(spec.allowedStates) do
		say("  permitido? %s == %s -> %s", tostring(e), tostring(estado), tostring(e == estado))
	end
end

-- La MISMA llamada que hace ServerMain, con el MISMO contexto.
local function revisar(serverState)
	return Rules.Check("BombAction", "Place", {
		serverState = serverState,
		distance = 5,
		maxDistance = GameConfig.BombPlacementRange,
	})
end

say("")
say("Check con serverState=%s -> %s", tostring(estado), tostring((revisar(estado))))
say("Check con serverState=nil  -> %s", tostring((revisar(nil))))

local ok, motivo = revisar(nil)
say("  motivo = %s", tostring(motivo))

-- Si `nil` es lo que recibe el filtro, el culpable es ServerMain: `roundService`
-- no esta disponible en ese cierre y `and` se come el valor.
say("")
say("Conclusion: %s", (revisar(nil) == false)
	and "el filtro esta recibiendo serverState = nil"
	or "el estado si llega bien; el rechazo es por otra comprobacion")

return table.concat(out, "\n")
