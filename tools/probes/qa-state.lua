-- qa-state.lua
-- Fotografia del estado de la ronda: bloques, bombas, explosiones y VFX.
local Bomb = require(game.ServerScriptService.Services.BombService)
local Explosion = require(game.ServerScriptService.Services.ExplosionService)
local Destruction = require(game.ServerScriptService.Services.DestructionService)
local Round = require(game.ServerScriptService.Services.RoundService)

local folder = workspace:FindFirstChild("ExplosionVfx")
local vfx = 0
if folder then
	for _ in pairs(folder:GetChildren()) do
		vfx += 1
	end
end

local bombsFolder = workspace:FindFirstChild("Bombs")
local bombParts = 0
if bombsFolder then
	for _ in pairs(bombsFolder:GetDescendants()) do
		bombParts += 1
	end
end

return string.format(
	"ronda=%s (jugando=%s) | bombas activas=%d partes en Workspace.Bombs=%d | explosiones=%d | VFX=%d | bloques vivos=%d destruidos=%d | duplicados=[%s]",
	tostring(Round.GetState()),
	tostring(Round.IsPlaying()),
	Bomb.GetActiveBombCount(),
	bombParts,
	Explosion.GetExplosionCount(),
	vfx,
	Destruction.GetAliveBlockCount(),
	Destruction.GetDestroyedBlockCount(),
	table.concat(Destruction.AuditDuplicates(), " | ")
)