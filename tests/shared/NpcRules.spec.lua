--!strict
--[[
	NpcRules.spec
	
	FASE 8 (Bloque 5): Reglas de NPCs.
	NO implementado aun. Este stub existe para:
	  1. Que RunTests.lua no falle con "carga de la suite".
	  2. Documentar el modulo pendiente.
	  3. Actuar como esqueleto para cuando el modulo exista.
	
	Ver: docs/phases.md (FASE 8), GAMEPLAY_AUDIT.md (C6).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

return function()
	local ok, Rules = pcall(require, "../../src/ReplicatedStorage/Shared/Libraries/NpcRules")

	if not ok then
		return
	end

	Harness.describe("NpcRules", function()
		Harness.it("modulo cargado", function()
			expect.toBeTruthy(Rules)
		end)
	end)
end
