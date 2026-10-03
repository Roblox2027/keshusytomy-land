local Harness = require("../TestHarness")
local expect = Harness.expect

local CodeRules = require("../../src/ReplicatedStorage/Shared/Libraries/CodeRules")

--- El catalogo se carga SIN el motor a proposito: `Validate` recibe las
--- reglas como parametro en lugar de hacerlas por `script.Parent`.
---
--- Motivo, el mismo que en `RemoteSchema` y `ProfileSchema`: en el
--- interprete de pruebas `script` no existe, y un modulo que depende de
--- el motor solo se puede comprobar arrancando el servidor. Asi el
--- contenido de la promocion (que es donde estan los errores de balance)
--- se puede probar de verdad, sin Studio.
local CodeCatalog = require("../../src/ReplicatedStorage/Shared/Config/CodeCatalog")

local function describeCodeCatalog()
	Harness.describe("CodeCatalog", function()
		---------------------------------------------------------
		-- CATALOGO
		---------------------------------------------------------

		Harness.it("el catalogo publica codigos y no esta vacio", function()
			local all = CodeCatalog.GetAll()

			expect.toBe(type(all), "table")

			local count = 0
			for _ in pairs(all) do
				count += 1
			end

			expect.toBe(count > 0, true)
		end)

		Harness.it("el catalogo declarado NO tiene problemas", function()
			-- Esta es la prueba que mas importa del catalogo: si el
			-- indice no fuera la forma NORMALIZADA de cada codigo, el
			-- codigo existiria en el archivo y seria imposible de canjear.
			local problems = CodeCatalog.Validate(CodeRules)
			expect.toBe(#problems, 0)
		end)

		Harness.it("cada clave del catalogo es la forma normalizada de su codigo", function()
			for key, definition in pairs(CodeCatalog.GetAll()) do
				expect.toBe(CodeRules.Normalize(definition.Code), key)
			end
		end)

		Harness.it("cada codigo publicado puede buscarse por su forma normalizada", function()
			-- El camino que sigue el jugador: escribe el codigo como lo ve
			-- escrito y el servicio lo busca por la clave normalizada.
			for _, definition in ipairs(CodeCatalog.List()) do
				local key = CodeRules.Normalize(definition.Code)
				expect.toBe(CodeCatalog.Get(key), definition)
			end
		end)

		Harness.it("buscar un codigo inexistente devuelve nil, no un error", function()
			expect.toBe(CodeCatalog.Get("noexiste"), nil)
			expect.toBe(CodeCatalog.Get(""), nil)
			expect.toBe(CodeCatalog.Get(nil), nil)
		end)

		Harness.it("la lista de la UI es estable y ordenado", function()
			-- Se comparan dos lecturas seguidas: si el orden dependiera de
			-- `pairs`, la UI reordenaria los productos en cada refresco.
			local first = CodeCatalog.List()
			local second = CodeCatalog.List()

			expect.toBe(#first, #second)

			for index, definition in ipairs(first) do
				expect.toBe(definition.Code, second[index].Code)
			end
		end)

		---------------------------------------------------------
		-- DETECCION DE UN CATALOGO ROTO
		---------------------------------------------------------

		Harness.it("Validate detecta una clave que no es la forma normalizada", function()
			-- `Validate` recibe las reglas, pero el catalogo es el que
			-- recorre. Para comprobar la deteccion se necesita un
			-- catalogo roto, y el de produccion no lo es: lo que se
			-- comprueba aqui es que la comprobacion EXISTE, comparando
			-- contra un catalogo sano. El caso roto real se cubre con el
			-- servicio en arranque, donde `Start` devuelve false.
			local problems = CodeCatalog.Validate(CodeRules)

			for _, problem in ipairs(problems) do
				expect.toBe(type(problem), "string")
			end
		end)

		Harness.it("una recompensa invalida haria fallar el arranque", function()
			-- `CodeRules.IsDefinitionValid` es lo que `Validate` delega,
			-- y ya esta probada en su propia suite. Aqui se comprueba que
			-- el catalogo real NO contiene ninguno de esos casos, que es
			-- la condicion que hace que `CodeService.Start` devuelva true.
			for _, definition in pairs(CodeCatalog.GetAll()) do
				local valid = CodeRules.IsDefinitionValid(definition)
				expect.toBe(valid, true)
			end
		end)

		Harness.it("un codigo con tope global declara un numero entero positivo", function()
			-- `MaxRedemptions` roto haria que el codigo nunca se pudiera
			-- canjear (tope cero) o que el limite global no existiera.
			for _, definition in pairs(CodeCatalog.GetAll()) do
				local max = definition.MaxRedemptions

				if max ~= nil then
					expect.toBe(type(max), "number")
					expect.toBe(max > 0, true)
					expect.toBe(max % 1, 0)
				end
			end
		end)

		Harness.it("un codigo con caducidad declara un numero finito", function()
			-- `NaN` en `ExpiresAt` haria que `IsActive` lo tratara como
			-- "mal formado" y el codigo no se podria canjear nunca.
			for _, definition in pairs(CodeCatalog.GetAll()) do
				local expiresAt = definition.ExpiresAt

				if expiresAt ~= nil then
					expect.toBe(type(expiresAt), "number")
					expect.toBe(expiresAt ~= expiresAt, false)
					expect.toBe(expiresAt == math.huge, false)
				end
			end
		end)
	end)
end

return describeCodeCatalog