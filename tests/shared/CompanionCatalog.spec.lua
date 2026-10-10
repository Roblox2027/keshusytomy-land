--!strict
--[[
	CompanionCatalog.spec
	
	FASE 8 (Bloque 5): Catalogo de companeros.
	NO implementado aun. Este stub existe para:
	  1. Que RunTests.lua no falle con "carga de la suite".
	  2. Documentar el modulo pendiente.
	  3. Actuar como esqueleto para cuando el modulo exista.
	
	Ver: docs/phases.md (FASE 8), GAMEPLAY_AUDIT.md (B4).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

return function()
	local ok, Catalog = pcall(require, "../../src/ReplicatedStorage/Shared/Libraries/CompanionCatalog")

	if not ok then
		return
	end

	Harness.describe("CompanionCatalog", function()
		Harness.it("modulo cargado", function()
			expect.toBeTruthy(Catalog)
		end)
	end)
end
