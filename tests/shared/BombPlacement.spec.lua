--!strict
--[[
	BombPlacement.spec
	CONTRATO de colocacion de bombas (punto 62 de la auditoria global).

	EL BUG QUE PROTEGE
	------------------
	La bomba se colocaba en algunas posiciones del mapa y en otras no. La
	causa: los limites de bomba se derivaban de UNA sola pieza,
	`ArenaFloor`, que desde la conversion a mundos con zonas y rutas es solo
	el suelo de la ZONA DE ARENA. Todo lo demas (spawn, entrada, senderos,
	zona del jefe) caia fuera y se rechazaba con `OUTSIDE_ARENA`.

	QUE COMPRUEBA
	-------------
	1. El area jugable es la UNION del suelo, no el rectangulo de una pieza.
	2. El margen coincide con el limite logico del mundo (misma frontera).
	3. Solo se rechaza por tres razones reales: numero, area y rango.
	4. Sin limites conocidos se acepta, pero el rango sigue mandando.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local BombPlacementRules = require("../../src/ReplicatedStorage/Shared/Libraries/BombPlacementRules")
local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local WorldBoundsRules = require("../../src/ReplicatedStorage/Shared/Libraries/WorldBoundsRules")

--- Tres zonas separadas con la forma de las de `worlds.js`.
---
--- La separacion es deliberada: una sola caja daria un area continua y el
--- contrato pasaria aunque el servicio volviera a mirar una sola pieza.
--- @return { { minX: number, maxX: number, minZ: number, maxZ: number } }
local function sampleBoxes()
	return {
		BombPlacementRules.BoxFromXZ(0, 180, 100, 100, 6),
		BombPlacementRules.BoxFromXZ(0, -110, 140, 96, 6),
		BombPlacementRules.BoxFromXZ(-160, 40, 120, 90, 6),
	}
end

--- Area jugable de ejemplo, ya con margen.
---
--- El `assert` no es decorativo: `Union` devuelve `nil` con la lista vacia,
--- y sin el el aviso del analizador seria "Bounds? could be nil" en cada
--- prueba de abajo, que es ruido que esconde el fallo de verdad.
--- @return { minX: number, maxX: number, minZ: number, maxZ: number }
local function sampleBounds()
	local union = BombPlacementRules.Union(sampleBoxes())
	assert(union, "sampleBoxes tiene que producir al menos una caja")

	return BombPlacementRules.Expand(union)
end

--- Peticion de colocacion. `bounds = false` simula un mundo sin limites
--- declarados; `playerX/playerZ` permiten separar al jugador del punto.
-- Los tres ultimos parametros son OPCIONALES y Luau no admite `= nil` en la
-- firma, asi que se toma la tabla de una sola vez y se leen por nombre.
-- @param x any
--- @param y any
--- @param z any
--- @param bounds any?
--- @param playerX number?
--- @param playerZ number?
--- @return any
local function request(x, y, z, ...)
	local extra = { ... }
	local bounds = extra[1]
	local playerX = extra[2]
	local playerZ = extra[3]
	-- El jugador esta EN el punto salvo que la prueba diga otra cosa. El
	-- `cast` es lo que lo deja bien tipado: sin el, `playerX or x` con
	-- `x: any` acaba en `(unknown & ~(false?)) | number`, que es un tipo
	-- imposible y un aviso que no describe ningun fallo real.
	local fromX = if playerX ~= nil then playerX else (x :: number)
	local fromZ = if playerZ ~= nil then playerZ else (z :: number)

	return {
		position = { x = x, y = y, z = z },
		playerX = fromX,
		playerY = 0,
		playerZ = fromZ,
		bounds = bounds == nil and sampleBounds() or bounds,
		maxRange = GameConfig.BombPlacementRange,
	}
end

local function describeBombPlacementContract()
	Harness.describe("BombPlacement: area jugable", function()
		Harness.it("la union cubre TODAS las zonas, no solo una", function()
			local bounds = BombPlacementRules.Union(sampleBoxes())
			assert(bounds, "la union de tres zonas no puede ser nil")

			-- Norte (z=180) es el spawn; sur (z=-110) es la arena;
			-- oeste (x=-160) es una zona de exploracion.
			expect.toBeTruthy(180 >= bounds.minZ and 180 <= bounds.maxZ)
			expect.toBeTruthy(-110 >= bounds.minZ and -110 <= bounds.maxZ)
			expect.toBeTruthy(-160 >= bounds.minX and -160 <= bounds.maxX)
		end)

		Harness.it("una lista vacia no produce un rectangulo de cero", function()
			expect.toBe(BombPlacementRules.Union({}), nil)
			expect.toBe(BombPlacementRules.Union(nil), nil)
		end)

		Harness.it("el margen coincide con el del limite logico del mundo", function()
			-- Si divergen, la bomba y el jugador tienen fronteras distintas.
			expect.toBe(BombPlacementRules.Margin, WorldBoundsRules.Margin)
		end)

		Harness.it("el margen hace que el borde sea holgado, no una linea", function()
			local union = BombPlacementRules.Union(sampleBoxes())
			assert(union, "la union de tres zonas no puede ser nil")

			local bounds = BombPlacementRules.Expand(union)

			expect.toBe(bounds.minX < union.minX, true)
			expect.toBe(bounds.maxX > union.maxX, true)
			expect.toBe(bounds.minZ < union.minZ, true)
			expect.toBe(bounds.maxZ > union.maxZ, true)
		end)
Harness.it("el area jugable es un AREA, no un punto", function()
			-- Menos de 100 studs de lado significaria que el limite se ha
			-- encogido otra vez a una sola pieza pequena.
			expect.toBe(BombPlacementRules.Span(sampleBounds()) >= 100, true)
		end)
	end)

	Harness.describe("BombPlacement: decision", function()
		local bounds = sampleBounds()

		Harness.it("acepta una posicion valida dentro del area jugable", function()
			local accepted, reason = BombPlacementRules.Evaluate(request(0, 70, 180))

			expect.toBe(accepted, true)
			expect.toBe(reason, nil)
		end)

		Harness.it("acepta el punto exacto de una esquina del area", function()
			local accepted = BombPlacementRules.Evaluate(request(bounds.minX, 70, bounds.minZ))

			expect.toBe(accepted, true)
		end)

		Harness.it("rechaza fuera del area jugable", function()
			local accepted, reason = BombPlacementRules.Evaluate(
				request(bounds.maxX + 500, 70, bounds.maxZ + 500)
			)

			expect.toBe(accepted, false)
			expect.toBe(reason, BombPlacementRules.Reject.OUTSIDE_ARENA)
		end)

		Harness.it("rechaza una posicion que no es un numero", function()
			local accepted, reason = BombPlacementRules.Evaluate(request("hola", 70, 180))

			expect.toBe(accepted, false)
			expect.toBe(reason, BombPlacementRules.Reject.INVALID_POSITION)
		end)

		Harness.it("rechaza NaN e infinito", function()
			expect.toBe(BombPlacementRules.Evaluate(request(0 / 0, 70, 180)), false)
			expect.toBe(BombPlacementRules.Evaluate(request(math.huge, 70, 180)), false)
			expect.toBe(BombPlacementRules.Evaluate(request(-math.huge, 70, 180)), false)
		end)

		Harness.it("rechaza una posicion sin componentes", function()
			-- El caso real del payload manipulado: `position.x == nil`.
			local accepted, reason = BombPlacementRules.Evaluate(request(nil, 70, 180))

			expect.toBe(accepted, false)
			expect.toBe(reason, BombPlacementRules.Reject.INVALID_POSITION)
		end)

		Harness.it("rechaza mas alla del rango de colocacion", function()
			local accepted, reason = BombPlacementRules.Evaluate(
				request(0, 70, 180 - GameConfig.BombPlacementRange - 1, nil, 0, 180)
			)

			expect.toBe(accepted, false)
			expect.toBe(reason, BombPlacementRules.Reject.OUT_OF_RANGE)
		end)

		Harness.it("el rango se mide en el plano, no con la altura", function()
			-- Mismo suelo, muy por debajo: misma distancia horizontal.
			local accepted = BombPlacementRules.Evaluate(request(0, 70 - 500, 180))

			expect.toBe(accepted, true)
		end)

		Harness.it("sin limites se acepta, pero el rango sigue mandando", function()
			local far = GameConfig.BombPlacementRange + 10

			local near = BombPlacementRules.Evaluate(request(0, 0, 0, false))
			local farAway = BombPlacementRules.Evaluate(request(far, 0, 0, false, 0, 0))

			expect.toBe(near, true)
			expect.toBe(farAway, false)
		end)

		Harness.it("el primer motivo que falla es el que se devuelve", function()
			-- Fuera de rango Y fuera del area: manda el area.
			local accepted, reason = BombPlacementRules.Evaluate(
				request(bounds.maxX + 500, 70, bounds.minZ - 500)
			)

			expect.toBe(accepted, false)
			expect.toBe(reason, BombPlacementRules.Reject.OUTSIDE_ARENA)
		end)
	end)

	Harness.describe("BombPlacement: separacion y asiento", function()
		Harness.it("una bomba sobre el jugador se separa, no se rechaza", function()
			local x, z = BombPlacementRules.SeparateFromPlayer(0, 0, 0, 0, 6, 1, 0)

			expect.toBeClose(x, 6, 1e-6)
			expect.toBeClose(z, 0, 1e-6)
		end)

		Harness.it("una bomba ya lejos NO se mueve", function()
			local x, z = BombPlacementRules.SeparateFromPlayer(0, 0, 10, 0, 6, 1, 0)

			expect.toBe(x, 10)
			expect.toBe(z, 0)
		end)

		Harness.it("la separacion usa la mira si el punto coincide", function()
			local x, z = BombPlacementRules.SeparateFromPlayer(0, 0, 0, 0, 6, 0, 1)

			expect.toBeClose(x, 0, 1e-6)
			expect.toBeClose(z, 6, 1e-6)
		end)

		Harness.it("la bomba se asienta SOBRE el suelo, no dentro", function()
			expect.toBe(BombPlacementRules.SettleHeight(70, 1.6), 71.6)
		end)
	end)
end

describeBombPlacementContract()
return describeBombPlacementContract
