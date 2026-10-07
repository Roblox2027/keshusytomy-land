--!strict
--[[
	WorldAccess.spec
	FASE 3: los cinco mundos se abren desde el nivel 1.

	POR QUE ESTA SEPARADA DE CUALQUIER TEST DE PORTAL
	------------------------------------------------
	El bloqueo por nivel vivia en DOS sitios a la vez: el comparador de
	`PortalService` y el campo `RequiredLevel` de cada `WorldDefinition`. Una
	prueba que solo mirara el portal pasaria si el servicio dejara de comparar,
	incluso con un `RequiredLevel = 50` esperando en la definicion.

	Esta prueba mira AMBAS cosas:
	  - las reglas puras (`WorldAccessRules`),
	  - las definiciones reales que carga el servidor.

	Y comprueba que las dos digan lo mismo. Esa coherencia es el contrato: si
	alguien reinstala un nivel 50 en Cyber, `Audit` lo delata aqui en vez de en
	un playtest.

	QUE NO SE COMPRUEBA AQUI
	------------------------
	Que el teleport ocurra de verdad. Eso necesita un jugador conectado y es lo
	que certifica `npm run test:portal` y el playtest. Aqui se comprueba la
	DECISION, que es la parte que se puede romper en silencio.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")

-- Las definiciones REALES, leidas de los archivos que carga el servidor.
-- Se leen por `require` y no se re-declaran: una copia en el test seria una
-- tabla mas que puede decir lo que quiera mientras el juego hace otra cosa.
local Forest = require("../../src/ReplicatedStorage/WorldDefinitions/Forest")
local Desert = require("../../src/ReplicatedStorage/WorldDefinitions/Desert")
local Ice = require("../../src/ReplicatedStorage/WorldDefinitions/Ice")
local Volcano = require("../../src/ReplicatedStorage/WorldDefinitions/Volcano")
local Cyber = require("../../src/ReplicatedStorage/WorldDefinitions/Cyber")

local DECLARED = {
	Forest = Forest,
	Desert = Desert,
	Ice = Ice,
	Volcano = Volcano,
	Cyber = Cyber,
}

local function describeWorldAccess()
	Harness.describe("Catalogo de mundos", function()
		Harness.it("declara exactamente los cinco mundos", function()
			expect.toBe(#Access.GetWorldIds(), 5)
		end)

		Harness.it("la dificultad de cada mundo es 1..5 y esta ordenada", function()
			local previous = 0

			for _, id in ipairs(Access.GetWorldIds()) do
				local d = Access.GetDifficulty(id)

				expect.toBe(
					d >= 1 and d <= 5,
					true,
					("%s tiene dificultad %s"):format(id, tostring(d))
				)
				expect.toBe(
					d > previous,
					true,
					("%s (%d) no es mas dificil que el anterior (%d)")
						:format(id, d, previous)
				)

				previous = d
			end
		end)

		Harness.it("la dificultad coincide con lo que el enunciado pide", function()
			-- Forest 1, Desert 2, Ice 3, Volcano 4, Cyber 5. No es una prueba
			-- de estilo: es la especificacion de la fase 4, escrita.
			expect.toBe(Access.GetDifficulty("Forest"), 1)
			expect.toBe(Access.GetDifficulty("Desert"), 2)
			expect.toBe(Access.GetDifficulty("Ice"), 3)
			expect.toBe(Access.GetDifficulty("Volcano"), 4)
			expect.toBe(Access.GetDifficulty("Cyber"), 5)
		end)
	end)

	Harness.describe("Fase 3: entrada sin bloqueo por nivel", function()
		Harness.it("los cinco mundos admiten a un jugador de nivel 1", function()
			for _, id in ipairs(Access.GetWorldIds()) do
				local allowed, reason = Access.CanEnter(id, function()
					return true
				end)

				expect.toBe(allowed, true, ("%s no admite nivel 1 (%s)")
					:format(id, tostring(reason)))
			end
		end)

		Harness.it("ningun mundo exige mas de nivel 1", function()
			for _, id in ipairs(Access.GetWorldIds()) do
				expect.toBe(
					Access.GetRequiredLevel(id) <= 1,
					true,
					("%s exige nivel %d"):format(id, Access.GetRequiredLevel(id))
				)
			end
		end)

		Harness.it("las definiciones reales ya no exigen nivel", function()
			-- Esta es la prueba que mas habria dolido no tener. El servicio
			-- puede haber dejado de COMPARAR el nivel y aun asi la definicion
			-- seguir pidiendo 50: el cartel del portal y cualquier comprobacion
			-- futura seguirian mintiendo.
			for _, id in ipairs(Access.GetWorldIds()) do
				expect.toBe(
					DECLARED[id].RequiredLevel,
					1,
					("%s declara RequiredLevel = %s")
						:format(id, tostring(DECLARED[id].RequiredLevel))
				)
			end
		end)

		Harness.it("un mundo inexistente sigue sin admittingse", function()
			-- Quitar el filtro de nivel no puede convertirse en puerta abierta
			-- de par en par: esto es lo que hace seguro el teleporte.
			local allowed, reason = Access.CanEnter("NoExiste", function()
				return true
			end)

			expect.toBe(allowed, false)
			expect.toBe(type(reason), "string")

			local nilOk = Access.CanEnter(nil, function()
				return true
			end)
			expect.toBe(nilOk, false)

			local numberOk = Access.CanEnter(42, function()
				return true
			end)
			expect.toBe(numberOk, false)
		end)

		Harness.it("un mundo conocido pero no disponible se rechaza", function()
			-- El servidor puede deshabilitar un mundo por `FeatureConfig` sin
			-- quitarlo del catalogo. Esa distincion es la que permite apagar
			-- un mundo sin tocar los portales.
			local allowed, reason = Access.CanEnter("Cyber", function()
				return false
			end)

			expect.toBe(allowed, false)
			expect.toContain(tostring(reason), "no disponible")
		end)
	end)

	Harness.describe("Coherencia entre reglas y definiciones", function()
		Harness.it("Audit no reporta ninguno", function()
			local problems = Access.Audit(DECLARED)
			expect.toBe(#problems, 0, table.concat(problems, "; "))
		end)

		Harness.it("la dificultad de las reglas es la de las definiciones", function()
			for _, id in ipairs(Access.GetWorldIds()) do
				expect.toBe(
					Access.GetDifficulty(id),
					DECLARED[id].Difficulty,
					("%s: reglas %d, definicion %d"):format(
						id,
						Access.GetDifficulty(id),
						DECLARED[id].Difficulty
					)
				)
			end
		end)

		Harness.it("el nombre legible es el de la definicion del mundo", function()
			-- FASE 3 (auditoria): las reglas decian "Frost Peaks"/"Ember
			-- Ridge" mientras el cartel del portal pintaba "Frozen Tomy"/
			-- "Volcano Rage". Dos nombres para un mismo mundo es una
			-- division de identidad que el jugador nota en el mapa.
			for _, id in ipairs(Access.GetWorldIds()) do
				expect.toBe(
					Access.GetDisplayName(id),
					DECLARED[id].DisplayName,
					("%s: reglas '%s', definicion '%s'"):format(
						id,
						Access.GetDisplayName(id),
						DECLARED[id].DisplayName
					)
				)
			end
		end)
	end)
end

return describeWorldAccess