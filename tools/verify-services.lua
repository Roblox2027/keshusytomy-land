local function tryRequire(name, path)
    local ok, result = pcall(function()
        return require(path)
    end)
    if ok then
        return name .. ": OK"
    else
        return name .. ": FAIL - " .. tostring(result)
    end
end

local Shared = game.ReplicatedStorage.Shared
local Libraries = Shared.Libraries
local Config = Shared.Config
local Utils = Shared.Utils

return {
    tryRequire("VisualKit", Libraries.VisualKit),
    tryRequire("CombatMath", Libraries.CombatMath),
    tryRequire("MonsterService", game.ServerScriptService.Services.MonsterService),
    tryRequire("BrainrotService", game.ServerScriptService.Services.BrainrotService),
    tryRequire("DestructionService", game.ServerScriptService.Services.DestructionService),
    tryRequire("BombService", game.ServerScriptService.Services.BombService),
    tryRequire("ExplosionService", game.ServerScriptService.Services.ExplosionService),
}
