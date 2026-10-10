local vk = game.ReplicatedStorage.Shared.Libraries.VisualKit
local ok, result = pcall(require, vk)
if not ok then
    return "require failed: " .. tostring(result)
end
return {
    resultType = typeof(result),
    hasBuildMonster = (typeof(result) == "table" and result.BuildMonster) ~= nil,
    isNil = (result == nil),
    keys = (function()
        local k = {}
        if type(result) == "table" then
            for key, val in pairs(result) do
                if type(val) == "function" then
                    table.insert(k, tostring(key))
                end
            end
        end
        table.sort(k)
        return k
    end)(),
}
