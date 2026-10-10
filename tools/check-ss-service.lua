local sss = game:GetService("ServerScriptService")
local results = {}
table.insert(results, "ServerScriptService children: " .. #sss:GetChildren())
for _, child in ipairs(sss:GetChildren()) do
    table.insert(results, "  " .. child.Name .. " (" .. child.ClassName .. ")")
end
return results
