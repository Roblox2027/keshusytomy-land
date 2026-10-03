local libs = game:GetService("ReplicatedStorage").Shared.Libraries
if not libs:FindFirstChild("VisualKit") then
	local m = Instance.new("ModuleScript")
	m.Name = "VisualKit"
	m.Source = ""
	m.Parent = libs
end
local services = game:GetService("ServerScriptService").Services
if not services:FindFirstChild("PowerupService") then
	local m = Instance.new("ModuleScript")
	m.Name = "PowerupService"
	m.Source = ""
	m.Parent = services
end
return {
	visualKit = libs:FindFirstChild("VisualKit") ~= nil,
	powerup = services:FindFirstChild("PowerupService") ~= nil,
}