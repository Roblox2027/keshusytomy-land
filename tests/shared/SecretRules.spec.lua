local Harness = require("../TestHarness")
local expect = Harness.expect
local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/SecretRules")

local function describeSecrets()
	Harness.describe("SecretRules", function()
		Harness.it("accepts only known worlds and safe zone ids", function()
			expect.toBe(Rules.SecretId("Forest", "Catacomb"), "Forest:Catacomb")
			expect.toBe(Rules.SecretId("Unknown", "Cache"), nil)
			expect.toBe(Rules.SecretId("Ice", "../Cache"), nil)
		end)

		Harness.it("parses generated prompt names with an exact world ID", function()
			local worldId, zoneId = Rules.ParsePromptName("SecretPrompt_Volcano_EmberShrine")
			expect.toBe(worldId, "Volcano")
			expect.toBe(zoneId, "EmberShrine")
			local invalidWorld = Rules.ParsePromptName("SecretPrompt_Other_Archive")
			expect.toBe(invalidWorld, nil)
		end)

		Harness.it("discovery is unique and produces a stable reward request ID", function()
			local state = Rules.NewState()
			local first, count = Rules.Discover(state, "Cyber:Archive")
			expect.toBe(first, true)
			expect.toBe(count, 1)
			local duplicate, duplicateCount = Rules.Discover(state, "Cyber:Archive")
			expect.toBe(duplicate, false)
			expect.toBe(duplicateCount, 1)
			expect.toBe(Rules.RewardRequestId(42, "Cyber:Archive"), "secret:42:Cyber:Archive")
		end)
	end)
end

return describeSecrets
