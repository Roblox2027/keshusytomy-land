--!strict
--[[
	TestDriverLogic.spec
	Pruebas del reproductor de pruebas del cliente.

	POR QUE EXISTEN
	---------------
	El reproductor es la pieza que convierte "el servidor puede hacer
	cosas" en "el JUGADOR puede hacer cosas". Si el reproductor aceptara
	una instruccion inventada, o se disparara en bucle, la prueba que
	reporta estaria midiendo una cadena que el jugador nunca recorre,
	y el PASS seria falso.

	Estos casos son los que defienden esa honestidad:

	1. Una instruccion desconocida NO se ejecuta.
	2. Una instruccion repetida NO se ejecuta (respeta el intervalo).
	3. El reproductor no puede pedir algo que no sea intencion de jugador.

	Limite honesto: que el camino completo
	InputController -> Remote -> Gateway -> BombService funcione solo se
	comprueba en Roblox Studio con el reproductor encendido. Eso queda
	BLOCKED, no PASS.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local TestDriverLogic = require("../../src/ReplicatedStorage/Shared/Libraries/TestDriverLogic")

local function describeTestDriverLogic()
	Harness.describe("Instrucciones soportadas", function()
		Harness.it("declara las tres intenciones de jugador", function()
			local actions = TestDriverLogic.SupportedActions()

			expect.toBe(#actions, 3)
			expect.toContain(table.concat(actions, ","), "PlaceBomb")
			expect.toContain(table.concat(actions, ","), "EnterPortal")
			expect.toContain(table.concat(actions, ","), "RequestState")
		end)

		Harness.it("NO incluye ninguna llamada directa a un servicio", function()
			-- ESTA es la prueba que sostiene el valor de toda la seccion 5.
			--
			-- Un reproductor que pudiera pedir "PlaceBombDirecto" o
			-- "CallService" seria un atajo: probaria el servidor, no el
			-- camino del jugador. Se comprueba que la lista de
			-- instrucciones NO contiene ninguna forma de saltarse el
			-- InputController ni el remoto.
			local actions = TestDriverLogic.SupportedActions()
			local joined = table.concat(actions, ",")

			expect.toBe(joined:find("Service"), nil)
			expect.toBe(joined:find("Direct"), nil)
			expect.toBe(joined:find("FireServer"), nil)
		end)

		Harness.it("rechaza una instruccion desconocida", function()
			local action, reason = TestDriverLogic.Parse("DropDatabase")

			expect.toBe(action, nil)
			expect.toContain(reason or "", "desconocida")
		end)

		Harness.it("rechaza un valor que no es texto", function()
			local action, reason = TestDriverLogic.Parse(42)

			expect.toBe(action, nil)
			expect.toContain(reason or "", "texto")
		end)

		Harness.it("rechaza una instruccion vacia", function()
			expect.toBe(TestDriverLogic.Parse(""), nil)
		end)
	end)

	Harness.describe("Frecuencia", function()
		Harness.it("permite la primera ejecucion", function()
			local allowed = TestDriverLogic.CanRun("PlaceBomb", nil, 100, 1.5)

			expect.toBe(allowed, true)
		end)

		Harness.it("RECHAZA una repeticion inmediata", function()
			-- Sin esto el reproductor podria hacer 20 peticiones por
			-- segundo y "aprobar" una cadena que el servidor rechazaria
			-- siempre por cooldown. El PASS seria mentira.
			local allowed, reason = TestDriverLogic.CanRun("PlaceBomb", 100, 100.5, 1.5)

			expect.toBe(allowed, false)
			expect.toContain(reason or "", "espera")
		end)

		Harness.it("permite de nuevo cuando paso el intervalo", function()
			expect.toBe(TestDriverLogic.CanRun("PlaceBomb", 100, 101.6, 1.5), true)
		end)

		Harness.it("el limite del intervalo es inclusivo", function()
			-- Justo al cumplirse el intervalo ya se acepta: si fuera
			-- exclusivo, la prueba fallaria de forma intermitente
			-- segun como caiga el reloj.
			expect.toBe(TestDriverLogic.CanRun("PlaceBomb", 100, 101.5, 1.5), true)
		end)

		Harness.it("un reloj que retrocede NO se acepta", function()
			local allowed, reason = TestDriverLogic.CanRun("PlaceBomb", 100, 50, 1.5)

			expect.toBe(allowed, false)
			expect.toContain(reason or "", "retrocedio")
		end)

		Harness.it("una instruccion no soportada no se ejecuta ni con intervalo 0", function()
			expect.toBe(TestDriverLogic.CanRun("DropDatabase", nil, 100, 0), false)
		end)
	end)

	Harness.describe("Codificacion", function()
		Harness.it("un portal codifica accion y destino", function()
			expect.toBe(TestDriverLogic.Encode("EnterPortal", "Forest"), "EnterPortal|Forest")
		end)

		Harness.it("una bomba no lleva destino", function()
			expect.toBe(TestDriverLogic.Encode("PlaceBomb"), "PlaceBomb")
			expect.toBe(TestDriverLogic.Encode("PlaceBomb", ""), "PlaceBomb")
		end)

		Harness.it("decodifica accion y destino", function()
			local action, worldId, reason = TestDriverLogic.Decode("EnterPortal|Forest")

			expect.toBe(action, "EnterPortal")
			expect.toBe(worldId, "Forest")
			expect.toBe(reason, nil)
		end)

		Harness.it("decodifica una accion sin destino", function()
			local action, worldId = TestDriverLogic.Decode("PlaceBomb")

			expect.toBe(action, "PlaceBomb")
			expect.toBe(worldId, nil)
		end)

		Harness.it("un texto no textual se rechaza al decodificar", function()
			local action, worldId, reason = TestDriverLogic.Decode(nil)

			expect.toBe(action, nil)
			expect.toBe(worldId, nil)
			expect.toContain(reason or "", "texto")
		end)

		Harness.it("una accion con separador pero destino vacio se rechaza", function()
			-- "EnterPortal|" no es un portal: sin destino el reproductor
			-- no debe ni intentar leerlo.
			expect.toBe(TestDriverLogic.Decode("EnterPortal|"), nil)
		end)

		Harness.it("ida y vuelta conserva accion y destino", function()
			local action, worldId = TestDriverLogic.Decode(
				TestDriverLogic.Encode("EnterPortal", "Desert")
			)

			expect.toBe(action, "EnterPortal")
			expect.toBe(worldId, "Desert")
		end)
	end)
end

return describeTestDriverLogic