-- p0-server-state.lua
-- Estado REAL del servidor en la sesion de Play: ronda, bombas, bloques.
-- No modifica nada. Solo mide.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function safe(name)
	local ok, mod = pcall(require, game.ServerScriptService.Services:FindFirstChild(name))
	if not ok then
		return nil, tostring(mod)
	end
	return mod, nil
end

local Round = select(1, safe("RoundService"))
local Bomb = select(1, safe("BombService"))
local Destruction = select(1, safe("DestructionService"))
local Explosion = select(1, safe("ExplosionService"))

local bombsFolder = Workspace:FindFirstChild("Bombs")
local bombChildren = 0
if bombsFolder then
	bombChildren = #bombsFolder:GetChildren()
end

local out = {
	players = #Players:GetPlayers(),
	roundState = Round and Round.GetState() or "?",
	isPlaying = Round and Round.IsPlaying() or false,
	activeBombs = Bomb and Bomb.GetActiveBombCount() or -1,
	workspaceBombsFolder = bombsFolder ~= nil,
	workspaceBombCount = bombChildren,
	aliveBlocks = Destruction and Destruction.GetAliveBlockCount() or -1,
	destroyedBlocks = Destruction and Destruction.GetDestroyedBlockCount() or -1,
	explosions = Explosion and Explosion.GetExplosionCount() or -1,
}

local worlds = {}
for _, p in ipairs(Players:GetPlayers()) do
	table.insert(
		worlds,
		string.format(
			"%s World=%s Bombs=%s HP=%s",
			p.Name,
			tostring(p:GetAttribute("World")),
			tostring(p:GetAttribute("Bombs")),
			tostring(p.Character and p.Character:FindFirstChildOfClass("Humanoid") and p.Character:FindFirstChildOfClass("Humanoid").Health)
		)
	)
end
out.playerDetail = table.concat(worlds, " | ")

return out