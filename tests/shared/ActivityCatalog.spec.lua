--!strict
--[[
	ActivityCatalog.spec
	El catalogo es DATOS + un indice normalizado. Estas pruebas verifican que
	el indice cuadra con las reglas (ids normalizados), que `ForWorld`
	separa por mundo y que `Validate` deja sano al catalogo real.

	Como el catalogo es un modulo con estado, `Configure` corre PRIMERO: los
	demás tests confían en el indice ya construido.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local ActivitiesRules = require("../../src/ReplicatedStorage/Shared/Libraries/ActivitiesRules")
local ActivityCatalog = require("../../src/ReplicatedStorage/Shared/Config/ActivityCatalog")

local KNOWN_WORLDS = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

local function describeActivityCatalog()
	Harness.describe("ActivityCatalog", function()
		-----------------------------------------------------------------
		-- CONFIGURACION E INICIALIZACION PEREZOSA
		-----------------------------------------------------------------

		Harness.it("Configure inicia el indice y expone actividades", function()
			ActivityCatalog.Configure(ActivitiesRules)

			local all = ActivityCatalog.GetAll()
			expect.toBe(type(all), "table")
			-- El catalogo real no esta vacio.
			expect.toBe(next(all) == nil, false)
		end)

		Harness.it("Validate sin rules inyecto avisa explicitamente", function()
			local problems = ActivityCatalog.Validate(nil, KNOWN_WORLDS)
			expect.toBe(#problems > 0, true)
		end)

		-----------------------------------------------------------------
		-- INDICE POR ID NORMALIZADO
		-----------------------------------------------------------------

		Harness.it("Get resuelve el id sin importar mayusculas ni separadores", function()
			local def = ActivityCatalog.Get("HUNT_FOREST_3")
			expect.toBe(type(def), "table")
			expect.toBe(def.Type, "Hunt")

			-- Las mismas actividades, escritas de otras formas, son la misma.
			expect.toBe(ActivityCatalog.Get("hunt-forest-3"), def)
			expect.toBe(ActivityCatalog.Get("  Hunt Forest 3  "), def)
		end)

		-----------------------------------------------------------------
		-- POR MUNDO
		-----------------------------------------------------------------

		Harness.it("ForWorld devuelve solo las del mundo pedido", function()
			local forest = ActivityCatalog.ForWorld("Forest")
			expect.toBe(type(forest), "table")
			expect.toBe(next(forest) == nil, false)

			for id, def in pairs(forest) do
				expect.toBe(def.World, "Forest")
				expect.toBe(id, ActivitiesRules.NormalizeId(def.Id))
			end

			-- Un mundo desconocido no devuelve nada, pero no rompe.
			expect.toBe(next(ActivityCatalog.ForWorld("Nowhere") or {}), nil)
		end)

		Harness.it("cada mundo conocido tiene al menos una actividad", function()
			-- La oferta diaria necesita actividades para girar. Un mundo
			-- sin actividades produce una oferta vacia, y el jugador de ese
			-- mundo se quedaria sin nada que hacer.
			for _, worldId in ipairs(KNOWN_WORLDS) do
				-- `next(...) == nil` es false cuando el mundo tiene actividades.
				expect.toBe(next(ActivityCatalog.ForWorld(worldId) or {}) == nil, false)
			end
		end)

		-----------------------------------------------------------------
		-- LISTA ESTABLE
		-----------------------------------------------------------------

		Harness.it("List devuelve un array estable ordenado por Id", function()
			local list = ActivityCatalog.List("Forest")
			expect.toBe(#list > 0, true)

			for index = 2, #list do
				expect.toBe(tostring(list[index - 1].Id) < tostring(list[index].Id), true)
			end
		end)

		-----------------------------------------------------------------
		-- AUDITORIA
		-----------------------------------------------------------------

		Harness.it("Validate deja sano el catalogo real contra mundos conocidos", function()
			local problems = ActivityCatalog.Validate(ActivitiesRules, KNOWN_WORLDS)
			expect.toBe(#problems, 0)
		end)
	end)
end

return describeActivityCatalog
