--!strict
--[[
	GameConfig.spec
	Pruebas de integridad de la configuracion.

	Un valor de configuracion invalido (limite 0, duracion negativa,
	flag inexistente) provocaria fallos difiles de diagnosticar mas
	adelante. Aqui se falla temprano.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

-- GameConfig es un modulo sin dependencias: se carga directamente.
local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local PerformanceConfig = require("../../src/ReplicatedStorage/Shared/Config/PerformanceConfig")
local FeatureConfig = require("../../src/ReplicatedStorage/Shared/Config/FeatureConfig")

local function isPositiveNumber(value: any): boolean
	return type(value) == "number" and value > 0
end

local function describeGameConfig()
	Harness.describe("GameConfig", function()
		Harness.it("tiene identidad y version", function()
			expect.toBe(GameConfig.GameName, "KeshusyTomy-LanD")
			expect.toBe(type(GameConfig.GameVersion), "string")
			expect.toContain(GameConfig.GameVersion, ".")
			expect.toBe(type(GameConfig.DataVersion), "number")
		end)

		Harness.it("las duraciones de ronda son positivas", function()
			expect.toBe(isPositiveNumber(GameConfig.RoundDuration), true)
			expect.toBe(isPositiveNumber(GameConfig.CountdownDuration), true)
			expect.toBe(isPositiveNumber(GameConfig.SuddenDeathTime), true)
		end)

		Harness.it("el juego es multipropÃƒÂ³sito: duraciones utilizables", function()
			expect.toBe(GameConfig.RoundDuration > GameConfig.CountdownDuration, true)
		end)

		Harness.it("las configuraciones de dominio son modulos separados", function()
			-- Cada dominio tiene su propio archivo: no se concentra
			-- toda la configuracion en un unico modulo gigante.
			expect.toBe(type(PerformanceConfig.Limits), "table")
			expect.toBe(type(FeatureConfig.ENABLE_FOREST), "boolean")
			expect.toBe(GameConfig.Performance, nil)
		end)
	end)

	Harness.describe("PerformanceConfig", function()
		Harness.it("todos los limites son enteros positivos", function()
			for name, value in PerformanceConfig.Limits do
				expect.toBe(isPositiveNumber(value), true)
				expect.toBe(value == math.floor(value), true)
				if not isPositiveNumber(value) then
					error(("limite invalido: %s = %s"):format(name, tostring(value)))
				end
			end
		end)

		Harness.it("hay presupuesto para cada categoria del documento", function()
			local limits = PerformanceConfig.Limits
			for _, key in {
				"MaxPlayers",
				"MaxMonsters",
				"MaxBombs",
				"MaxExplosions",
				"MaxProjectiles",
				"MaxVFX",
				"MaxParticles",
				"MaxTempInstances",
			} do
				expect.toBe(isPositiveNumber(limits[key]), true)
			end
		end)

		Harness.it("los limites por jugador son mas bajos que los globales", function()
			local limits = PerformanceConfig.Limits
			expect.toBe(limits.MaxBombsPerPlayer < limits.MaxBombs, true)
			expect.toBe(limits.MaxProjectilesPerPlayer < limits.MaxProjectiles, true)
			expect.toBe(limits.MaxMonstersPerPlayer < limits.MaxMonsters, true)
		end)

		Harness.it("los intervalos de muestreo son positivos", function()
			expect.toBe(isPositiveNumber(PerformanceConfig.MetricsSampleInterval), true)
			expect.toBe(isPositiveNumber(PerformanceConfig.MonitorInterval), true)
			expect.toBe(isPositiveNumber(PerformanceConfig.AutoSaveInterval), true)
			expect.toBe(isPositiveNumber(PerformanceConfig.IdleCheckInterval), true)
		end)
	end)

	Harness.describe("FeatureConfig", function()
		Harness.it("declara los interruptores de mundo y modo del documento", function()
			for _, flag in {
				"ENABLE_FOREST",
				"ENABLE_DESERT",
				"ENABLE_ICE",
				"ENABLE_VOLCANO",
				"ENABLE_CYBER",
				"ENABLE_RANKED",
				"ENABLE_BOSS_RUSH",
				"ENABLE_EVENTS",
				"ENABLE_NEW_SHOP",
			} do
				expect.toBe(type(FeatureConfig[flag]), "boolean")
			end
		end)

		Harness.it("la monetizacion esta apagada en desarrollo", function()
			-- Regla de seguridad: no se procesan compras reales en dev.
			expect.toBe(FeatureConfig.ENABLE_MONETIZATION, false)
		end)

		Harness.it("Forest es el unico mundo habilitado inicialmente", function()
			expect.toBe(FeatureConfig.ENABLE_FOREST, true)
			expect.toBe(FeatureConfig.ENABLE_DESERT, false)
			expect.toBe(FeatureConfig.ENABLE_ICE, false)
			expect.toBe(FeatureConfig.ENABLE_VOLCANO, false)
			expect.toBe(FeatureConfig.ENABLE_CYBER, false)
		end)
	end)
end

return describeGameConfig