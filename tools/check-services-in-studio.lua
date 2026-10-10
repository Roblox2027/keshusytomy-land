local sss = game:GetService("ServerScriptService")
local results = {}

local services = sss:FindFirstChild("Services")
if services then
    table.insert(results, "Services folder found, children: " .. #services:GetChildren())
    local expected = {"MatchService", "CombatService", "PortalService", "SpawnService", "WorldMechanicsService", "CoreService", "PlayerService"}
    local found = {}
    for _, child in ipairs(services:GetChildren()) do
        found[child.Name] = true
        table.insert(results, "  " .. child.Name .. " (" .. child.ClassName .. ")")
    end
    for _, name in ipairs(expected) do
        if not found[name] then
            table.insert(results, "  MISSING: " .. name)
        end
    end
else
    table.insert(results, "Services folder MISSING")
end

-- Check Systems
local systems = sss:FindFirstChild("Systems")
if systems then
    table.insert(results, "Systems folder found, children: " .. #systems:GetChildren())
    for _, child in ipairs(systems:GetChildren()) do
        table.insert(results, "  " .. child.Name .. " (" .. child.ClassName .. ")")
    end
end

-- Check ServerMain
local serverMain = sss:FindFirstChild("ServerMain")
if serverMain and serverMain:IsA("LocalScript") then
    table.insert(results, "ServerMain is LocalScript, should be Script")
end

return results
