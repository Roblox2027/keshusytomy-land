--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local SecretRules = require(SHARED:WaitForChild("Libraries"):WaitForChild("SecretRules"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false
Service._profileService = nil :: any
Service._economyService = nil :: any
Service._questService = nil :: any
Service._maid = nil :: any

function Service.SetDependencies(profileService: any, economyService: any, questService: any?)
	Service._profileService = profileService
	Service._economyService = economyService
	Service._questService = questService
end

local function handleTriggered(prompt: any, player: Player)
	local worldId, zoneId = SecretRules.ParsePromptName(prompt.Name)
	local secretId = SecretRules.SecretId(worldId, zoneId)
	if not secretId or player:GetAttribute("World") ~= worldId then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local host = prompt.Parent
	if
		not root
		or not root:IsA("BasePart")
		or not humanoid
		or humanoid.Health <= 0
		or not host
		or not host:IsA("BasePart")
	then
		return
	end

	local allowedDistance = math.min(prompt.MaxActivationDistance, 12) + 2
	if (root.Position - host.Position).Magnitude > allowedDistance then
		return
	end
	if not Service._profileService.HasProfile(player) then
		return
	end

	local profile = Service._profileService.GetProfile(player)
	if type(profile) ~= "table" then
		return
	end
	if type(profile.Secrets) ~= "table" then
		profile.Secrets = SecretRules.NewState()
	end

	local alreadyFound = type(profile.Secrets.Discovered) == "table"
		and profile.Secrets.Discovered[secretId] == true
	if alreadyFound then
		return
	end

	local requestId = SecretRules.RewardRequestId(player.UserId, secretId)
	if not requestId then
		return
	end

	local granted = Service._economyService.GrantCurrency(
		player,
		"Coins",
		GameConfig.CoinsPerKill,
		"secreto_descubierto",
		"secret_service",
		{ WorldId = worldId, ZoneId = zoneId },
		requestId
	)
	if not granted then
		return
	end

	local discovered, count = SecretRules.Discover(profile.Secrets, secretId)
	if not discovered then
		return
	end

	Service._profileService.MarkDirty(player)
	player:SetAttribute("SecretsFound", count)
	if Service._questService and Service._questService.RecordMetric then
		Service._questService.RecordMetric(player, "SecretDiscovered", 1)
	end
	Logger.Info(("SecretService: %s descubrio %s/%s"):format(player.Name, worldId, zoneId))
end

local function attach(instance: Instance)
	if not instance:IsA("ProximityPrompt") or not Service._maid then
		return
	end
	local prompt = instance :: any
	local worldId = SecretRules.ParsePromptName(prompt.Name)
	if not worldId then
		return
	end
	Service._maid:Connect(prompt.Triggered, function(player: Player)
		handleTriggered(prompt, player)
	end)
end

function Service.Init(maid: any?): boolean
	Service.IsInitialized = true
	Service._maid = maid
	return true
end

function Service.Start(maid: any?): boolean
	if not Service._profileService or not Service._economyService then
		Logger.Error("SecretService: faltan ProfileService/EconomyService.")
		return false
	end

	Service._maid = maid or Service._maid
	local worlds = Workspace:FindFirstChild("Worlds")
	if not worlds then
		Logger.Error("SecretService: Workspace.Worlds no existe.")
		return false
	end

	for _, instance in ipairs(worlds:GetDescendants()) do
		attach(instance)
	end
	if Service._maid then
		Service._maid:Connect(worlds.DescendantAdded, attach)
	end
	Logger.Info("SecretService listo.")
	return true
end

function Service.Destroy(): boolean
	Service.IsInitialized = false
	Service._profileService = nil
	Service._economyService = nil
	Service._questService = nil
	Service._maid = nil
	return true
end

return Service
