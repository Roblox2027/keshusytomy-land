--!strict
--[[
	BrainrotBehaviorRules.spec
	Tests para la IA diferenciada por arquetipo (FASE 9.3).

	Verifica:
	  - Clasificacion correcta de cada especie brainrot por su arquetipo.
	  - Prioridad de clasificacion (Tech/Heavy ganan sobre Hunter).
	  - Robustez ante definiciones invalidas (siempre devuelve Standard).
	  - Los multiplicadores estan acotados al rango seguro.
	  - Los rangos efectivos modulan deteccion/agro segun arquetipo.
	  - Audit sobre las especies reales no encuentra problemas.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/BrainrotBehaviorRules")
local BrainrotRules = require("../../src/ReplicatedStorage/Shared/Libraries/BrainrotRules")
local Monsters = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")

return function()
	Harness.describe("Clasificacion por arquetipo", function()
		Harness.it("un volador se clasifica como Flyer", function()
			expect.toBe(Rules.Classify(Monsters.Get("Bambino")), Rules.Archetype.Flyer)
		end)

		Harness.it("un tecnologico se clasifica como Tech", function()
			expect.toBe(Rules.Classify(Monsters.Get("Glitchino")), Rules.Archetype.Tech)
		end)

		Harness.it("un virus se clasifica como Tech (misma familia)", function()
			expect.toBe(Rules.Classify(Monsters.Get("Virusini")), Rules.Archetype.Tech)
		end)

		Harness.it("un pesado se clasifica como Heavy", function()
			expect.toBe(Rules.Classify(Monsters.Get("Macarronni")), Rules.Archetype.Heavy)
			expect.toBe(Rules.Classify(Monsters.Get("Magmatico")), Rules.Archetype.Heavy)
		end)

		Harness.it("un espectral se clasifica como Spectral", function()
			expect.toBe(Rules.Classify(Monsters.Get("Fantasmitti")), Rules.Archetype.Spectral)
		end)

		Harness.it("un cazador se clasifica como Hunter", function()
			expect.toBe(Rules.Classify(Monsters.Get("Pixeloni")), Rules.Archetype.Hunter)
			expect.toBe(Rules.Classify(Monsters.Get("Sandwichini")), Rules.Archetype.Hunter)
		end)
	end)

	Harness.describe("Prioridad de clasificacion", function()
		Harness.it("Tech gana sobre Hunter cuando coexisten rasgos", function()
			-- Un robot cazador seria Tech, no Hunter: la prioridad lo decide.
			local def = { IsTech = true, IsHunter = true }
			expect.toBe(Rules.Classify(def), Rules.Archetype.Tech)
		end)

		Harness.it("Heavy gana sobre Hunter", function()
			local def = { IsHeavy = true, IsHunter = true }
			expect.toBe(Rules.Classify(def), Rules.Archetype.Heavy)
		end)

		Harness.it("Spectral gana sobre Flyer", function()
			local def = { IsSpectral = true, IsFlyer = true }
			expect.toBe(Rules.Classify(def), Rules.Archetype.Spectral)
		end)
	end)

	Harness.describe("Robustez", function()
		Harness.it("una definicion invalida devuelve Standard", function()
			expect.toBe(Rules.Classify(nil), Rules.Archetype.Standard)
			expect.toBe(Rules.Classify(42), Rules.Archetype.Standard)
			expect.toBe(Rules.Classify({}), Rules.Archetype.Standard)
		end)

		Harness.it("un rasgo que no es exactamente true no clasifica", function()
			-- `IsFlyer = "si"` no debe contar: la frontera es `== true`.
			expect.toBe(Rules.Classify({ IsFlyer = "si" }), Rules.Archetype.Standard)
		end)
	end)

	Harness.describe("Perfiles y multiplicadores", function()
		Harness.it("todos los multiplicadores estan acotados", function()
			for _, archetype in pairs(Rules.Archetype) do
				local profile = Rules.GetProfile(archetype)
				expect.toBe(profile.DetectionMult >= Rules.MIN_MULT, true)
				expect.toBe(profile.DetectionMult <= Rules.MAX_MULT, true)
				expect.toBe(profile.AggroMult >= Rules.MIN_MULT, true)
				expect.toBe(profile.AggroMult <= Rules.MAX_MULT, true)
				expect.toBe(profile.PatrolRadiusMult >= Rules.MIN_MULT, true)
				expect.toBe(profile.PatrolRadiusMult <= Rules.MAX_MULT, true)
			end
		end)

		Harness.it("un volador ve mas lejos que la base", function()
			expect.toBe(Rules.GetProfile(Rules.Archetype.Flyer).DetectionMult > 1, true)
		end)

		Harness.it("un pesado ve menos que la base", function()
			expect.toBe(Rules.GetProfile(Rules.Archetype.Heavy).DetectionMult < 1, true)
		end)
	end)

	Harness.describe("Rangos efectivos", function()
		Harness.it("EffectiveDetectionRange modula segun arquetipo", function()
			local base = 100
			local flyer = Rules.EffectiveDetectionRange({ DetectionRange = base, IsFlyer = true })
			local heavy = Rules.EffectiveDetectionRange({ DetectionRange = base, IsHeavy = true })
			expect.toBe(flyer > base, true)
			expect.toBe(heavy < base, true)
		end)

		Harness.it("Standard deja el rango intacto", function()
			expect.toBe(Rules.EffectiveDetectionRange({ DetectionRange = 50 }), 50)
		end)

		Harness.it("es robusto ante rangos invalidos", function()
			expect.toBe(Rules.EffectiveDetectionRange(nil), 0)
			expect.toBe(Rules.EffectiveDetectionRange({}), 0)
			expect.toBe(Rules.EffectiveDetectionRange({ DetectionRange = "x" }), 0)
		end)

		Harness.it("EffectiveAggroRadius modula segun arquetipo", function()
			local tech = Rules.EffectiveAggroRadius({ AggroRadius = 100, IsTech = true })
			expect.toBe(tech > 100, true)
			expect.toBe(Rules.EffectiveAggroRadius({ AggroRadius = 100 }), 100)
		end)
	end)

	Harness.describe("Audit", function()
		Harness.it("no encuentra problemas con las especies reales", function()
			local problems = Rules.Audit(BrainrotRules, Monsters)
			expect.toBe(#problems, 0)
		end)

		Harness.it("las especies con rasgos de percepcion se diferencian", function()
			-- FASE 9.3: estas especies declaran rasgos de PERCEPCION/MOVIMIENTO
			-- (volar, ser etéreo, pesado, sensor, cazador) y por tanto DEBEN
			-- salir de Standard. El resto (Locotto con LeavesNest, Peperoni con
			-- Burns, Bombino con IsExplosive...) tiene rasgos de EFECTO en
			-- combate, no de percepcion: quedan en Standard a proposito, y su
			-- diferencia se siente al morir/golpear, no al detectar.
			local diferenciadas = {
				Bambino = Rules.Archetype.Flyer,
				Fantasmitti = Rules.Archetype.Spectral,
				Macarronni = Rules.Archetype.Heavy,
				Magmatico = Rules.Archetype.Heavy,
				Glitchino = Rules.Archetype.Tech,
				Virusini = Rules.Archetype.Tech,
				Pixeloni = Rules.Archetype.Hunter,
				Sandwichini = Rules.Archetype.Hunter,
			}
			for id, expected in pairs(diferenciadas) do
				local def = Monsters.Get(id)
				expect.toBeTruthy(def)
				expect.toBe(Rules.Classify(def), expected)
			end
		end)

		Harness.it("una especie de solo-efecto permanece en Standard", function()
			-- Peperoni (Burns/Fireblast) y Locotto (LeavesNest) no tienen
			-- rasgos de percepcion: Standard es lo correcto, no un fallo.
			expect.toBe(Rules.Classify(Monsters.Get("Peperoni")), Rules.Archetype.Standard)
			expect.toBe(Rules.Classify(Monsters.Get("Locotto")), Rules.Archetype.Standard)
		end)
	end)
end
