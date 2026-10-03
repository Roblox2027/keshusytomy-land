local services = game:GetService("ServerScriptService").Services
local shared = game:GetService("ReplicatedStorage").Shared
local visualKit = require(shared.Libraries.VisualKit)
local monsterDefinitions = require(shared:WaitForChild("MonsterDefinitions"))

local out = {}
out.ids = table.concat(monsterDefinitions.GetIds(), ",")

local def = monsterDefinitions.Get("Slime")
out.hasDef = def ~= nil

if def then
	local model = visualKit.BuildMonster(def)
	out.model = model ~= nil

	if model then
		out.primary = tostring(model.PrimaryPart and model.PrimaryPart.Name or "NINGUNO")
		out.children = {}

		for _, child in ipairs(model:GetChildren()) do
			table.insert(out.children, child.Name .. " [" .. child.ClassName .. "]")
		end

		model:Destroy()
	end
end

local monsterService = require(services:WaitForChild("MonsterService"))
local folder = monsterService.GetFolder()
out.folder = folder:GetFullName() .. " hijos=" .. tostring(#folder:GetChildren())
out.limit = monsterService.GetAliveCount()

return out