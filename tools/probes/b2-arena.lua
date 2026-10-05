-- b2-arena.lua (SERVIDOR)
-- BLOQUE 2 (diagnostico): por que el ciclo de ronda no encuentra "Arena".
-- SIN ESPERAS.
local Match = require(game.ServerScriptService.Services.MatchService)
local World = require(game.ServerScriptService.Services.WorldService)

local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

local claves = {}
for k in pairs(Match._destinations) do table.insert(claves, k) end
table.sort(claves)
say("destinos = %s", table.concat(claves, ", "))
say("_defaultArenaKey = %s", tostring(Match._defaultArenaKey))

local ids = World.GetWorldIds()
say("WorldService ids = %s", table.concat(ids, ", "))
say("GetDefaultWorldId = %s", tostring(World.GetDefaultWorldId()))

local names = {}
local worlds = workspace:FindFirstChild("Worlds")
if worlds then
	for _, c in ipairs(worlds:GetChildren()) do table.insert(names, c.Name) end
end
table.sort(names)
say("workspace.Worlds = %s", table.concat(names, ", "))

-- El alias depende de que el marcador ArenaCenter exista en la carpeta del mundo.
if worlds then
	for _, name in ipairs(names) do
		local f = worlds:FindFirstChild(name)
		say("  %s -> ArenaCenter = %s", name, tostring(f and f:FindFirstChild("ArenaCenter")))
	end
end

return table.concat(out, "\n")