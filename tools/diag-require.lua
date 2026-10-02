-- diag-require.lua
-- Diagnostico: por que `require` de los servicios devuelve nil.
local Services = game:GetService("ServerScriptService"):WaitForChild("Services")
local out = {}

local function add(s) table.insert(out, s) end

for _, name in ipairs({ "WorldService", "SpawnService", "BombService", "CombatService" }) do
	local mod = Services:FindFirstChild(name)
	if not mod then
		add(name .. ": NO EXISTE la instancia")
		continue
	end
	add(name .. ": ClassName=" .. mod.ClassName)

	local ok, result = pcall(function()
		return require(mod)
	end)

	add(string.format("  pcall(require) ok=%s type=%s", tostring(ok), type(result)))
	if not ok then
		add("  ERROR: " .. tostring(result))
	elseif type(result) == "table" then
		local keys = {}
		for k in result do table.insert(keys, tostring(k)) end
		table.sort(keys)
		add("  claves: " .. table.concat(keys, ", "))
	end
end

return table.concat(out, "\n")
