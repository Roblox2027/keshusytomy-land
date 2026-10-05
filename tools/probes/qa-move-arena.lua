-- qa-move-arena.lua
-- Mete al jugador en una arena para que la ronda pueda arrancar.
local Match = require(game.ServerScriptService.Services.MatchService)
local Players = game:GetService("Players")

local p = Players:GetPlayers()[1]
if not p then return "sin jugadores" end

local keys = {}
for key in pairs(Match._destinations or {}) do
	table.insert(keys, key)
end
table.sort(keys)

local moved = Match.MovePlayer(p, "Arena_Forest")

return string.format(
	"destinos: %s | MovePlayer(Arena_Forest)=%s | World=%s",
	table.concat(keys, ","),
	tostring(moved),
	tostring(p:GetAttribute("World"))
)