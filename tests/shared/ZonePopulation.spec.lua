--!strict
--[[
	ZonePopulation.spec
	Zonas activas, LOD y limites de poblacion (FASES 7, 11, 12 y 13).

	EL CONTRATO QUE SE COMPRUEBA
	---------------------------
	"Mundos grandes sin miles de NPC y sin IA fuera del area del jugador" son la
	misma condicion, y se comprueba con tres garantias:

	  1. Una zona lejana NO repuebla ni ejecuta IA completa. Si lo hiciera, el
	     limite global se gastaria en contenido que nadie ve.
	  2. La poblacion por zona esta ACOTADA en las 99 noches y de noche.
	  3. El exceso se detecta y se devuelve, para que el servicio pueda podar.

	LA HISTERESIS
	-------------
	Se prueba que una zona en el borde NO oscila entre estados. Sin histeresis,
	cada paso del jugador dispara y retira enemigos, y eso se ve como un parpadeo
	de la poblacion que el jugador reporta como "los enemigos aparecen y
	desaparecen solos".
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Zone = require("../../src/ReplicatedStorage/Shared/Libraries/ZoneRules")

local function describeZones()
	Harness.describe("LOD: que hace cada estado", function()
		Harness.it("una zona lejana no ejecuta IA ni se repuebla", function()
			-- Es la garantia central de la fase 7: lo lejano NO cuesta.
			expect.toBe(Zone.HasFullAI(Zone.Lod.Dormant), false)
			expect.toBe(Zone.ShouldPopulate(Zone.Lod.Dormant), false)
			expect.toBe(Zone.CanHostEvent(Zone.Lod.Dormant), false)
		end)

		Harness.it("una zona cercana tampoco se repuebla todavia", function()
			-- `Near` es el estado que hace posible el mapa grande: el jugador ve
			-- que hay contenido alrededor, pero ese contenido no le cuesta.
			expect.toBe(Zone.HasFullAI(Zone.Lod.Near), false)
			expect.toBe(Zone.ShouldPopulate(Zone.Lod.Near), false)
			expect.toBe(Zone.CanHostEvent(Zone.Lod.Near), false)
		end)

		Harness.it("solo la zona activa hace trabajo", function()
			expect.toBe(Zone.HasFullAI(Zone.Lod.Active), true)
			expect.toBe(Zone.ShouldPopulate(Zone.Lod.Active), true)
			expect.toBe(Zone.CanHostEvent(Zone.Lod.Active), true)
		end)

		Harness.it("una distancia no numerica arranca DORMANT, nunca activo", function()
			-- Arrancar DESPIERTO es la opcion peligrosa: llena el servidor de
			-- enemigos que nadie mira. Un `nil` al crear una zona no puede
			-- provocar eso.
			local cases = { nil, "lejos", {} }
			table.insert(cases, 0 / 0)

			for _, value in ipairs(cases) do
				expect.toBe(
					Zone.LodAt(value),
					Zone.Lod.Dormant,
					("LodAt(%s) no arranco dormida"):format(tostring(value))
				)
			end
		end)
	end)

	Harness.describe("Distancias", function()
		Harness.it("el LOD baja a medida que el jugador se aleja", function()
			expect.toBe(Zone.LodAt(0), Zone.Lod.Active)
			expect.toBe(Zone.LodAt(Zone.ActiveDistance), Zone.Lod.Active)
			expect.toBe(Zone.LodAt(Zone.ActiveDistance + 10), Zone.Lod.Near)
			expect.toBe(Zone.LodAt(Zone.DormantDistance), Zone.Lod.Near)
			expect.toBe(Zone.LodAt(Zone.DormantDistance + 10), Zone.Lod.Dormant)
		end)

		Harness.it("la zona lejana esta mas lejos que la cercana", function()
			-- Si los radios se invirtieran, la zona que esta viendo el jugador
			-- seria la unica sin enemigos.
			expect.toBe(
				Zone.ActiveDistance < Zone.DormantDistance,
				true,
				"el radio activo es mayor que el dormido"
			)
		end)

		Harness.it("la histeresis evita el vaiven en el borde", function()
			-- La zona esta justo pasado el umbral de `Near`. Sin histeresis
			-- cambiaria a `Dormant` al siguiente paso, y en el siguiente
			-- volveria a `Near`: un ciclo de spawn/despawn que el jugador ve
			-- como parpadeo de la poblacion.
			local edge = Zone.DormantDistance + 1

			expect.toBe(Zone.LodAt(edge, Zone.Lod.Near), Zone.Lod.Near)
			expect.toBe(Zone.LodAt(edge, Zone.Lod.Active), Zone.Lod.Near)
		end)

		Harness.it("la histeresis no mantiene viva una zona muy lejos", function()
			-- El margen es un margen, no una exencion: a doble del radio, la
			-- zona tiene que dormir aunque viniera de `Near`.
			expect.toBe(
				Zone.LodAt(Zone.DormantDistance * 2, Zone.Lod.Near),
				Zone.Lod.Dormant,
				"una zona lejana sigue viva por la histeresis"
			)
		end)
	end)
Harness.describe("Poblacion por zona", function()
		Harness.it("el minimo nunca supera al maximo", function()
			-- Es la asercion que hace que `Min`/`Max` sean utilizables. Con
			-- `Min > Max` el servicio pediria mas enemigos de los que permite, y
			-- el fallo apareceria como un bucle infinito de spawns.
			local roles = {}
			for role in pairs(Zone.PopByRole) do
				table.insert(roles, role)
			end

			for _, role in ipairs(roles) do
				for night = 1, 99 do
					for _, isNight in ipairs({ false, true }) do
						local pop = Zone.PopulationFor(role, night, isNight)

						expect.toBe(
							pop.Min <= pop.Max,
							true,
							("%s noche %d: min %d > max %d")
								:format(role, night, pop.Min, pop.Max)
						)
						expect.toBe(
							pop.Max <= Zone.MaxPerZone,
							true,
							("%s supera MaxPerZone"):format(role)
						)
					end
				end
			end
		end)

		Harness.it("ningun rol supera el tope por zona en NINGUN caso", function()
			-- Se recorren las 99 noches de noche, que es donde el maximo crece.
			local roles = {}
			for role in pairs(Zone.PopByRole) do
				table.insert(roles, role)
			end

			for _, role in ipairs(roles) do
				for night = 1, 99 do
					local pop = Zone.PopulationFor(role, night, true)

					expect.toBe(
						pop.Max <= Zone.MaxPerZone,
						true,
						("%s noche %d de noche: %d vivos, tope %d")
							:format(role, night, pop.Max, Zone.MaxPerZone)
					)
				end
			end
		end)

		Harness.it("la noche sube el maximo pero NO el minimo", function()
			-- Es la distincion economica: de noche hay mas PRESION, no mas
			-- enemigos garantizados. Subir el minimo llenaria el mapa de NPC
			-- donde no hay nadie.
			for night = 1, 99 do
				local day = Zone.PopulationFor("exploration", night, false)
				local nightPop = Zone.PopulationFor("exploration", night, true)

				expect.toBe(
					nightPop.Min <= day.Min,
					true,
					("noche %d: el minimo subio a %d desde %d")
						:format(night, nightPop.Min, day.Min)
				)
				expect.toBe(
					nightPop.Max >= day.Max,
					true,
					("noche %d: el maximo NO subio (era %d, ahora %d)")
						:format(night, day.Max, nightPop.Max)
				)
			end
		end)

		Harness.it("un rol desconocido usa la poblacion por defecto", function()
			-- El mapa del generador puede traer un rol nuevo. Que caiga en la
			-- tabla por defecto y devuelva algo VALIDO es lo que evita que una
			-- zona nueva quede sin definicion de poblacion.
			local pop = Zone.PopulationFor("rol-inventado", 10)

			expect.toBe(pop.Min > 0, true)
			expect.toBe(pop.Min <= pop.Max, true)
		end)

		Harness.it("la entrada NO tiene enemigos garantizados", function()
			-- La entrada es donde el jugador elige su proximo destino: con
			-- enemigos, el portal deja de leerse como una salida y el jugador
			-- muere delante de el.
			expect.toBe(Zone.PopulationFor("entrance", 50, true).Min, 0)
		end)
	end)

	Harness.describe("Contabilidad global (FASE 12)", function()
		Harness.it("no hay exceso por debajo de los topes", function()
			local result = Zone.Overflow(10, 30, 60)

			expect.toBe(result.World, 0)
			expect.toBe(result.Total, 0)
			expect.toBe(result.Excess, 0)
		end)

		Harness.it("detecta el exceso por mundo y por global por separado", function()
			-- Son problemas DISTINTOS: si el global esta bien pero el mundo no,
			-- podar en otra zona del MISMO mundo lo resuelve igual. Devolver un
			-- unico numero obligaria a decidir donde podar sin saber cual de los
			-- dos limites fallo.
			--
			-- Firma: Overflow(vivosEnMundo, vivosEnServidor, techoMundo, techoGlobal).
			-- 40 en el mundo contra un techo de 30, con 50 en el servidor (techo 60):
			-- solo se pasa el del mundo.
			local overWorld = Zone.Overflow(40, 50, 30, 60)
			expect.toBe(overWorld.World, 10)
			expect.toBe(overWorld.Total, 0)

			-- 20 en cada mundo, 70 en el servidor con techo 60: solo se pasa el
			-- global.
			local overTotal = Zone.Overflow(20, 70, 30, 60)
			expect.toBe(overTotal.World, 0)
			expect.toBe(overTotal.Total, 10)
			expect.toBe(overTotal.Excess, 10)
		end)

		Harness.it("los topes estan en un orden coherente", function()
			-- Zona < mundo < servidor. Si el orden se invirtiese, el limite por
			-- zona seria inalcanzable y el de mundo no acotaria nada.
			local limits = Zone.PopulationLimits

			expect.toBe(limits.MaxPerZone < limits.MaxPerWorld, true, "una zona supera al mundo")
			expect.toBe(limits.MaxPerWorld <= limits.MaxTotal, true, "un mundo supera al servidor")
			expect.toBe(limits.MaxPerPlayer <= limits.MaxTotal, true, "un jugador supera al servidor")
		end)

		Harness.it("el presupuesto recorta el objetivo sin dejarlo negativo", function()
			expect.toBe(Zone.ResolvePopulation("arena", 50, true, 3), 3)
			expect.toBe(Zone.ResolvePopulation("arena", 50, true, 0), 0)
			expect.toBe(Zone.ResolvePopulation("arena", 50, true, -5), 0)

			-- Sin presupuesto, la zona pide lo que le toca por rol.
			expect.toBe(Zone.ResolvePopulation("encounter", 50, true, nil) > 0, true)
		end)
	end)
end

return describeZones