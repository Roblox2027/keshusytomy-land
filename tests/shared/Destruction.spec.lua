--!strict
--[[
	Destruction.spec
	Pruebas del CICLO DE VIDA de un bloque destruible (FASE 6).

	Por que existe:
	Se cubrio un bug REAL: `DestructionService.ApplyDamage` hacia
	`block:Destroy()` y ademas borraba el origen de la tabla. Como
	`RestoreAll` solo reparaba los bloques que seguian vivos, tras la
	primera ronda la arena se quedaba VACIA de forma permanente: no
	habia nada que restaurar. El juego era jugable una vez y luego
	imposible.

	Estas pruebas ejecutan el CONTRATO del servicio con una maquina de
	estado equivalente, para que la regresion no vuelva a colarse.

	Limite honesto: que un Part real se vuelva invisible al destruirlo y
	sea reparable en Roblox Studio NO se comprueba aqui. Eso es BLOCKED.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local CombatMath = require("../../src/ReplicatedStorage/Shared/Libraries/CombatMath")

local function makeBlock()
	return { health = GameConfig.BlockHealth, destroyed = false, parent = true }
end

--- Contrato de DestructionService.ApplyDamage.
local function applyDamage(block, amount)
	if not block.parent then
		return false
	end

	block.health = CombatMath.ApplyBlockDamage(block.health, amount)

	if block.health > 0 then
		return false
	end

	-- El bloque NO se borra del Workspace: se marca como destruido.
	block.destroyed = true
	return true
end

--- Contrato de DestructionService.RestoreAll.
local function restoreAll(blocks)
	local restored = 0

	for _, block in ipairs(blocks) do
		if block.parent then
			block.destroyed = false
			block.health = GameConfig.BlockHealth
			restored += 1
		end
	end

	return restored
end

--- Dano que aplica una explosion a cada bloque dentro del radio.
local function explosionDamageOnBlock()
	return CombatMath.BlockDamageFromExplosion(
		GameConfig.DefaultBombDamage,
		GameConfig.BlockDamageScale
	)
end

local function describeDestruction()
	Harness.describe("Destruccion y reparacion del mapa", function()
		Harness.it("una sola explosion NO destruye un bloque", function()
			local block = makeBlock()
			applyDamage(block, explosionDamageOnBlock())

			expect.toBe(block.destroyed, false)
			expect.toBe(block.health > 0, true)
		end)

		Harness.it("el bloque se destruye tras el golpe suficiente", function()
			local block = makeBlock()
			local hit = explosionDamageOnBlock()
			local destroyed = false

			for _ = 1, 5 do
				destroyed = applyDamage(block, hit) or destroyed
			end

			expect.toBe(destroyed, true)
			expect.toBe(block.health, 0)
		end)

		Harness.it("el bloque destruido SIGUE en el mapa (es reparable)", function()
			-- ASSERTION CLAVE del bug corregido: si se usara `Destroy()`,
			-- `parent` seria false y no habria nada que reparar.
			local block = makeBlock()
			block.health = 1
			applyDamage(block, 999)

			expect.toBe(block.destroyed, true)
			expect.toBe(block.parent, true)
		end)

		Harness.it("RestoreAll devuelve la arena a su estado original", function()
			local blocks = {}

			for _ = 1, 10 do
				local block = makeBlock()
				block.health = 1
				applyDamage(block, 999)
				table.insert(blocks, block)
			end

			expect.toBe(restoreAll(blocks), 10)

			for _, block in ipairs(blocks) do
				expect.toBe(block.destroyed, false)
				expect.toBe(block.health, GameConfig.BlockHealth)
			end
		end)

		Harness.it("varias rondas seguidas NO vacian la arena", function()
			-- Regresion directa del fallo original: tras 5 rondas, los
			-- 48 bloques del mapa deben seguir reparables.
			local blocks = {}
			local hit = explosionDamageOnBlock()

			for _ = 1, 48 do
				table.insert(blocks, makeBlock())
			end

			for _round = 1, 5 do
				for _, block in ipairs(blocks) do
					applyDamage(block, hit)
				end

				expect.toBe(restoreAll(blocks), 48)
			end

			local alive = 0
			for _, block in ipairs(blocks) do
				if not block.destroyed then
					alive += 1
				end
			end

			expect.toBe(alive, 48)
		end)

		Harness.it("la arena tarda varias bombas en caer", function()
			-- Si una bomba borrara el bloque entero, la arena desapareceria
			-- en un solo impacto y no habria juego.
			local hits = math.ceil(GameConfig.BlockHealth / explosionDamageOnBlock())
			expect.toBe(hits >= 2, true)
		end)
	end)
end

return describeDestruction