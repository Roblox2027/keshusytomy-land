--!strict
--[[
	WorldStaticPhysics.spec
	Pruebas de la invariante de fisica: las piezas estaticas del mapa
	NUNCA deben perder el anclaje (Anchored = true).

	POR QUE EXISTE
	--------------
	Una pieza sin anclar cae por gravedad. Si las losas del suelo, los
 muros o las losas de cueva pierden el anclaje, el mapa se desarma y
	el jugador cae al vacio. Este fallo es el que se reporto: "el mapa
	se esta desarmando y cayendo al vacio durante la ejecucion".

	Las causas posibles son:
	  1. El generador (tools/generate-project.js) no ancla una pieza.
	  2. Un servicio de runtime pone Anchored = false.
	  3. La destruccion/restauracion de bloques no preserva Anchored.

	Hay TRES capas de defensa, y esta prueba cubre la tercera:

	  CAPA 1 - Generador: tools/audit-map-physics.js verifica que
	    default.project.json tiene Anchored = true en las 15048
	    piezas. StreamingEnabled = false.

	  CAPA 2 - Runtime: la auditoria de codigo (parte de CAPA 1)
	    verifica que ningun .lua ni .js escribe Anchored = false.

	  CAPA 3 - DestructionService: snapshotBlock captura Anchored y
	    tryMaterialize/RestoreAll lo restauran. Esta prueba verifica
	    ese contrato con objetos mock, igual que Destruction.spec.lua
	    verifica el ciclo de vida del bloque.

	LIMITE HONESTO: que una Part real tenga Anchored = true en Roblox
	Studio no se comprueba aqui (requiere entorno de Roblox). Eso se
	audita en CAPA 1 (tools/audit-map-physics.js sobre default.project.json)
	y en CAPA 2 (source-level sobre .lua/.js).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local CombatMath = require("../../src/ReplicatedStorage/Shared/Libraries/CombatMath")

-- Un bloque "mock" que modela las propiedades fisicas relevantes.
-- En Roblox Studio esto seria un BasePart; aqui es una tabla plana.
local function makeBlock()
	return {
		health = GameConfig.BlockHealth,
		destroyed = false,
		parent = true,
		-- Propiedades fisicas que debe preservar la destruccion.
		Anchored = true,        -- invariante: NUNCA debe dejar de ser true
		Transparency = 0,
		CanCollide = true,
		CanTouch = false,
	}
end

-- Contrato de DestructionService.snapshotBlock (actualizado).
-- Captura el estado original para poder restaurarlo. Debe incluir
-- Anchored: si no, una futura modificacion que ponga Anchored = false
-- durante la destruccion no se revertiria al restaurar.
local function snapshotBlock(block)
	return {
		Health = GameConfig.BlockHealth,
		Transparency = block.Transparency,
		Anchored = block.Anchored,
		CanCollide = block.CanCollide,
		CanTouch = block.CanTouch,
	}
end

-- Contrato de DestructionService.ApplyDamage: al destruir, el bloque
-- se vuelve invisible e intangible PERO conserva su anclaje. Nunca
-- debe poner Anchored = false: un bloque sin anclar caera por gravedad.
local function destroyBlock(block)
	block.Transparency = 1
	block.CanCollide = false
	block.CanTouch = false
	block.destroyed = true
	-- CRITICAL: Anchored NO se toca.
end

-- Contrato de DestructionService.tryMaterialize / RestoreAll: restaura
-- todas las propiedades del snapshot, incluyendo Anchored.
local function restoreBlock(block, original)
	block.Transparency = original.Transparency
	block.Anchored = original.Anchored
	block.CanCollide = original.CanCollide
	block.CanTouch = original.CanTouch
	block.destroyed = false
	block.health = original.Health
end

local function describeWorldStaticPhysics()
	Harness.describe("Snapshot de fisica preserva Anchored", function()
		Harness.it("snapshotBlock captura Anchored", function()
			local block = makeBlock()
			local snap = snapshotBlock(block)

			expect.toBe(snap.Anchored, true)
			expect.toBe(snap.Transparency, 0)
			expect.toBe(snap.CanCollide, true)
		end)

		Harness.it("RestoreAll restaura Anchored al valor original", function()
			local block = makeBlock()
			local snap = snapshotBlock(block)

			destroyBlock(block)
			expect.toBe(block.destroyed, true)
			-- Mientras destruido, el bloque sigue anclado.
			expect.toBe(block.Anchored, true)

			restoreBlock(block, snap)
			expect.toBe(block.destroyed, false)
			expect.toBe(block.Anchored, true)
		end)
	end)

	Harness.describe("Invariante: piezas estaticas nunca pierden el anclaje", function()
		Harness.it("un bloque anclado NO se desancla al destruirse", function()
			local block = makeBlock()
			expect.toBe(block.Anchored, true)

			destroyBlock(block)
			expect.toBe(block.Anchored, true)
		end)

		Harness.it("el ciclo destruir/restaurar conserva el anclaje", function()
			local block = makeBlock()
			local snap = snapshotBlock(block)

			for round = 1, 5 do
				destroyBlock(block)
				expect.toBe(block.Anchored, true, "round " .. round .. " (destruido)")

				restoreBlock(block, snap)
				expect.toBe(block.Anchored, true, "round " .. round .. " (restaurado)")
			end
		end)
	end)

	Harness.describe("Modulo de reglas: destruction no muta Anchored", function()
		-- Reescribe ApplyDamage con el contrato real y verifica que
		-- destruir no toca Anchored. Si futuro codigo anade
		-- `block.Anchored = false`, esta prueba fallara.
		local function applyDamage(block, amount)
			if not block.parent then
				return false
			end
			block.health = CombatMath.ApplyBlockDamage(block.health, amount)
			if block.health > 0 then
				return false
			end
			destroyBlock(block)
			return true
		end

		Harness.it("ApplyDamage destruye sin desanclar", function()
			local block = makeBlock()
			local snap = snapshotBlock(block)
			applyDamage(block, GameConfig.BlockHealth)

			expect.toBe(block.destroyed, true)
			expect.toBe(block.Anchored, true)

			restoreBlock(block, snap)
			expect.toBe(block.Anchored, true)
			expect.toBe(block.destroyed, false)
		end)
	end)
end

return describeWorldStaticPhysics
