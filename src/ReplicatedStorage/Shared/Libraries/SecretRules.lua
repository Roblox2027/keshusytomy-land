--!strict

local Rules = {}

Rules.WorldIds = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

local KNOWN_WORLDS = {
	Forest = true,
	Desert = true,
	Ice = true,
	Volcano = true,
	Cyber = true,
}

function Rules.SecretId(worldId: any, zoneId: any): string?
	if
		type(worldId) ~= "string"
		or not KNOWN_WORLDS[worldId]
		or type(zoneId) ~= "string"
		or not string.match(zoneId, "^[%w]+$")
	then
		return nil
	end
	return worldId .. ":" .. zoneId
end

function Rules.ParsePromptName(promptName: any): (string?, string?)
	if type(promptName) ~= "string" then
		return nil, nil
	end
	for _, worldId in ipairs(Rules.WorldIds) do
		local zoneId = string.match(promptName, "^SecretPrompt_" .. worldId .. "_([%w]+)$")
		if zoneId then
			return worldId, zoneId
		end
	end
	return nil, nil
end

function Rules.NewState(): { Discovered: { [string]: boolean } }
	return { Discovered = {} }
end

function Rules.Count(state: any): number
	if type(state) ~= "table" or type(state.Discovered) ~= "table" then
		return 0
	end
	local count = 0
	for _, discovered in pairs(state.Discovered) do
		if discovered == true then
			count += 1
		end
	end
	return count
end

function Rules.Discover(state: any, secretId: any): (boolean, number)
	if type(state) ~= "table" or type(secretId) ~= "string" or secretId == "" then
		return false, Rules.Count(state)
	end
	if type(state.Discovered) ~= "table" then
		state.Discovered = {}
	end
	if state.Discovered[secretId] == true then
		return false, Rules.Count(state)
	end
	state.Discovered[secretId] = true
	return true, Rules.Count(state)
end

function Rules.RewardRequestId(userId: any, secretId: any): string?
	if type(userId) ~= "number" or userId <= 0 or type(secretId) ~= "string" or secretId == "" then
		return nil
	end
	return ("secret:%d:%s"):format(userId, secretId)
end

return Rules
