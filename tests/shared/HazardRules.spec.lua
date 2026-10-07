--!strict
--[[
	HazardRules.spec
	Mecanica caracteristica de cada mundo (MASTER MISSION V2 - FASE 3).

	Lo que se certifica aqui es el CATALOGO y la aritmetica: que cada mundo
	tiene un peligro, que el laser tiene telegraph real (on/off), que la
	arena movediza frena sin inmovilizar y que la emboscada tiene cooldown.
	Las partes, el hilo y la lectura de posiciones los prueba el playtest.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Hazard = require("../../src/ReplicatedStorage/Shared/Libraries/HazardRules")
local Access = require("../../src/ReplicatedStorage/Shared/Libraries/WorldAccessRules")
local Monsters = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

local function describeHazards()
	Harness.describe("Catalogo por mundo", function()
		Harness.it("todo mundo jugable tiene peligro propio", function()
			-- La promesa de la FASE 3 es que cada mundo se JUEGA distinto:
			-- un mundo sin peligro es un mundo que solo cambia de color.
			for _, worldId in ipairs(Access.GetWorldIds()) do
				local hazard = Hazard.ForWorld(worldId)

				expect.toBe(hazard ~= nil, true, ("%s sin mecanica"):format(worldId))
				expect.toBe(type(hazard.Radius), "number", ("%s sin radio"):format(worldId))
				expect.toBe(hazard.Radius > 0, true, ("%s con radio 0"):format(worldId))
			end
		end)

		Harness.it("ningun mundo repite mecanica", function()
			-- Dos mundos con el mismo peligro son dos mundos que se sienten
			-- igual: exactamente lo que esta mision viene a eliminar.
			local seen = {}

			for _, worldId in ipairs(Hazard.GetWorldIds()) do
				local kind = Hazard.ForWorld(worldId).Kind

				expect.toBe(seen[kind] == nil, true, ("mecanica repetida: %s"):format(kind))
				seen[kind] = true
			end
		end)

		Harness.it("los enemigos de las emboscadas existen", function()
			-- Un spawn inventado es una emboscada que se anuncia y no pone
			-- nada en el mapa: el peor fallo, porque parece configurado.
			for _, worldId in ipairs(Hazard.GetWorldIds()) do
				local hazard = Hazard.ForWorld(worldId)

				if hazard.Kind == Hazard.Kind.Ambush then
					for _, spawnId in ipairs(hazard.Spawns) do
						expect.toBe(
							Monsters.Get(spawnId) ~= nil,
							true,
							("%s: enemigo inexistente '%s'"):format(worldId, tostring(spawnId))
						)
					end
				end
			end
		end)
	end)

	Harness.describe("Laser telegrafiado", function()
		Harness.it("alterna encendido y apagado con el reloj", function()
			local laser = Hazard.ForWorld("Cyber")
			local cycle = laser.OnTime + laser.OffTime

			expect.toBe(laser.Kind, "Laser")
			expect.toBe(Hazard.IsLaserOn(laser, 0), true)
			expect.toBe(Hazard.IsLaserOn(laser, laser.OnTime - 0.1), true)
			expect.toBe(Hazard.IsLaserOn(laser, laser.OnTime + 0.1), false)
			expect.toBe(Hazard.IsLaserOn(laser, cycle + 0.1), true)
		end)

		Harness.it("apagado no hace dano", function()
			local laser = Hazard.ForWorld("Cyber")
			local off = laser.OnTime + 0.1

			expect.toBe(Hazard.DamagePerTick(laser, off, Hazard.TickSeconds), 0)
			expect.toBe(Hazard.DamagePerTick(laser, 0, Hazard.TickSeconds) > 0, true)
		end)

		Harness.it("la ventana apagada existe de verdad", function()
			-- Un laser con OffTime 0 no es un telegraph: es un muro de dano.
			local laser = Hazard.ForWorld("Cyber")

			expect.toBe(laser.OffTime >= 2, true, "el laser no deja ventana de cruce")
		end)
	end)

	Harness.describe("Lava", function()
		Harness.it("el dano es proporcional al paso", function()
			local lava = Hazard.ForWorld("Volcano")

			expect.toBe(
				Hazard.DamagePerTick(lava, 0, 1),
				lava.DamagePerSecond,
				"el dano por segundo no cuadra"
			)
			expect.toBe(
				Hazard.DamagePerTick(lava, 0, Hazard.TickSeconds) < lava.DamagePerSecond,
				true,
				"el paso corto deberia danar menos"
			)
		end)

		Harness.it("castiga quedarse, no cruzar", function()
			-- Con 100 de vida y el tick a 0.5 s, cruzar (unos 2 s dentro) no
			-- puede costar mas de una quinta parte de la vida.
			local lava = Hazard.ForWorld("Volcano")

			expect.toBe(lava.DamagePerSecond * 2 <= 20, true, "la lava mata por cruzarla")
		end)
	end)

	Harness.describe("Arena movediza", function()
		Harness.it("frena sin inmovilizar", function()
			-- Inmovilizar sin aviso es frustracion, no mecanica: el suelo
			-- que traga tiene que dejar arrastrarse hacia fuera.
			local quicksand = Hazard.ForWorld("Desert")
			local slowed = Hazard.SlowedWalkSpeed(quicksand)

			expect.toBe(slowed < Hazard.DefaultWalkSpeed, true, "no frena")
			expect.toBe(slowed >= 4, true, "inmoviliza")
		end)

		Harness.it("un peligro que no es arena devuelve la velocidad base", function()
			expect.toBe(Hazard.SlowedWalkSpeed(Hazard.ForWorld("Volcano")), Hazard.DefaultWalkSpeed)
			expect.toBe(Hazard.SlowedWalkSpeed(nil), Hazard.DefaultWalkSpeed)
		end)
	end)

	Harness.describe("Emboscada", function()
		Harness.it("respeta el cooldown", function()
			expect.toBe(Hazard.CanAmbush(nil, 90, 100), true)
			expect.toBe(Hazard.CanAmbush(100, 90, 150), false)
			expect.toBe(Hazard.CanAmbush(100, 90, 200), true)
		end)

		Harness.it("genera pocos enemigos por disparo", function()
			-- Una emboscada de diez enemigos no es sorpresa: es un muro.
			local ambush = Hazard.ForWorld("Forest")

			expect.toBe(ambush.Count <= 4, true, "la emboscada genera de mas")
		end)
	end)

	Harness.describe("Limites", function()
		Harness.it("el numero de zonas por mundo esta acotado", function()
			expect.toBe(Hazard.MaxZonesPerWorld <= 8, true)
			expect.toBe(Hazard.MaxZonesPerWorld >= 2, true)
		end)

		Harness.it("el ritmo del servicio es razonable", function()
			-- Un tick de 0.05 s seria un Heartbeat disfrazado: sesenta
			-- comprobaciones por frame sin necesidad.
			expect.toBe(Hazard.TickSeconds >= 0.25, true)
			expect.toBe(Hazard.TickSeconds <= 1, true)
		end)
	end)
end

return describeHazards
