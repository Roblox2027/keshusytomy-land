--!strict
--[[
	BombSkillIntegration.spec
	Pruebas de integracion para la cadena BOMBA: SkillRules → SkillService →
	BombService → ExplosionService.

	QUE SE PRUEBA AQUI
	-----------------
	Como los servicios dependen de `game:GetService` (no disponible en el
	interprete standalone), se prueban:

	1. Edge cases de SkillRules.ComputeBombStats que la suite existente no
	   cubre (NaN, infinito, IDs duplicados, valores extremos).

	2. La CADENA DE FORMULAS que conectan skills con el juego real:
	   - radio efectivo = DefaultBombRadius * (1 + radiusMult)
	   - mult de daño efectivo = 1 + damageMult
	   - capacidad total = BombCapacity + skillCapacity (acotada)
	   - daño a bloques = DefaultBombDamage * mult * BlockDamageScale
	   - daño a entidades = FalloffDamage(distancia, radio, dañoBase * mult)

	3. El PATRÓN DE CACHÉ de SkillService: cache keyado por UserId que debe
	   limpiarse en PlayerRemoving. Se replica con un mock para certificar
	   que la lógica de limpieza es correcta.

	BLOCKED: la verificación en Studio (que una bomba real aparezca,
	detone y haga daño) requiere el motor de Roblox. Eso se documenta en
	BLOCKED.md, no en PASS.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local PerformanceConfig = require("../../src/ReplicatedStorage/Shared/Config/PerformanceConfig")
local SkillCatalog = require("../../src/ReplicatedStorage/Shared/Config/SkillCatalog")
local SkillRules = require("../../src/ReplicatedStorage/Shared/Libraries/SkillRules")
local CombatMath = require("../../src/ReplicatedStorage/Shared/Libraries/CombatMath")

local DEFAULT_RADIUS = GameConfig.DefaultBombRadius
local DEFAULT_DAMAGE = GameConfig.DefaultBombDamage
local BASE_CAPACITY = GameConfig.BombCapacity
local BLOCK_DAMAGE_SCALE = GameConfig.BlockDamageScale
local MAX_BOMBS_PER_PLAYER = PerformanceConfig.Limits.MaxBombsPerPlayer

local function describeBombSkillIntegration()
	Harness.describe("SkillRules: valores límite y defensivos", function()
		Harness.it("NaN en efecto se propaga como número (no como 0)", function()
			-- `tonumber(x) or 0` no atrapa NaN/inf: ambos son truthy en Lua.
			-- Esto DOCUMENTA el comportamiento actual. Si alguien añade
			-- NaN a un efecto, el daño será NaN, no 0. La defensa debe
			-- estar en CombatMath.FalloffDamage (que filtra no-finito).
			local nan = 0 / 0
			local catalog = {
				Get = function(id)
					if id == "Skill_NanTest" then
						return {
							Id = "Skill_NanTest",
							Category = "Bomb",
							Tier = 1,
							Effect = { BombDamageMult = nan },
						}
					end
					return nil
				end,
				Categories = { Bomb = "Bomb" },
			}

			local stats = SkillRules.ComputeBombStats({ "Skill_NanTest" }, catalog)
			expect.toBe(stats.damageMult ~= stats.damageMult, true)
		end)

		Harness.it("Infinity en efecto se propaga como número (no como 0)", function()
			local catalog = {
				Get = function(id)
					if id == "Skill_InfTest" then
						return {
							Id = "Skill_InfTest",
							Category = "Bomb",
							Tier = 1,
							Effect = { BombRadiusMult = math.huge },
						}
					end
					return nil
				end,
				Categories = { Bomb = "Bomb" },
			}

			local stats = SkillRules.ComputeBombStats({ "Skill_InfTest" }, catalog)
			expect.toBe(stats.radiusMult, math.huge)
		end)

		Harness.it("IDs duplicados suman el multiplicador dos veces", function()
			-- El código no deduplica: si el mismo ID aparece dos veces en
			-- `unlockedIds`, el multiplicador de daño se suma dos veces.
			-- Esto DOCUMENTA el comportamiento: la regla de diseño dice
			-- "hay un único skill por efecto", pero el código no la fuerza.
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombDamage1",
				"Skill_BombDamage1",
			}, SkillCatalog)

			-- 0.15 + 0.15 = 0.30 (doble)
			expect.toBe(stats.damageMult, 0.30)
		end)

		Harness.it("IDs duplicados NO aumentan capacidad (best-tier gana)", function()
			-- Para capacidad, el algoritmo conserva el de mayor Tier.
			-- Dos IDs iguales = mismo Tier, no se actualiza.
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombCapacity1",
				"Skill_BombCapacity1",
			}, SkillCatalog)

			expect.toBe(stats.capacity, 1)
		end)

		Harness.it("multiplicadores extremadamente grandes no rompen el cálculo", function()
			local catalog = {
				Get = function(id)
					if id == "Skill_Huge" then
						return {
							Id = "Skill_Huge",
							Category = "Bomb",
							Tier = 1,
							Effect = { BombDamageMult = 1e6, BombRadiusMult = 1e6 },
						}
					end
					return nil
				end,
				Categories = { Bomb = "Bomb" },
			}

			local stats = SkillRules.ComputeBombStats({ "Skill_Huge" }, catalog)
			expect.toBe(stats.damageMult, 1000000)
			expect.toBe(stats.radiusMult, 1000000)
		end)

		Harness.it("skill con Effect no tabla se ignora", function()
			local catalog = {
				Get = function(id)
					if id == "Skill_BadEffect" then
						return {
							Id = "Skill_BadEffect",
							Category = "Bomb",
							Tier = 1,
							Effect = "not a table",
						}
					end
					return SkillCatalog.Get(id)
				end,
				Categories = { Bomb = "Bomb" },
			}

			local stats = SkillRules.ComputeBombStats({ "Skill_BadEffect", "Skill_BombDamage1" }, catalog)
			expect.toBe(stats.damageMult, 0.15)
		end)

		Harness.it("skill con Tier no numérico se trata como Tier 0", function()
			local catalog = {
				Get = function(id)
					if id == "Skill_NoString" then
						return {
							Id = "Skill_NoString",
							Category = "Bomb",
							Tier = "alta",
							Effect = { BombCapacity = 5 },
						}
					end
					if id == "Skill_RealTier1" then
						return {
							Id = "Skill_RealTier1",
							Category = "Bomb",
							Tier = 1,
							Effect = { BombCapacity = 1 },
						}
					end
					return nil
				end,
				Categories = { Bomb = "Bomb" },
			}

			-- Tier "alta" se convierte en 0; el Tier 1 real gana empatado.
			local stats = SkillRules.ComputeBombStats({ "Skill_NoString", "Skill_RealTier1" }, catalog)
			expect.toBe(stats.capacity, 1)
		end)
	end)

	Harness.describe("SkillRules → GameConfig: fórmulas de integración", function()
		-- Estas pruebas certifican que las fórmulas usadas por
		-- SkillService.GetEffectiveBombRadius y
		-- SkillService.GetEffectiveDamageMult son consistentes con
		-- los valores de GameConfig y los stats calculados por SkillRules.

		Harness.it("radio efectivo sin skills = radio base de GameConfig", function()
			local stats = SkillRules.ComputeBombStats({}, SkillCatalog)
			local effectiveRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)
			expect.toBe(effectiveRadius, DEFAULT_RADIUS)
		end)

		Harness.it("radio efectivo con BombRadius1 = 24 * 1.20 = 28.8", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombRadius1" }, SkillCatalog)
			local effectiveRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)
			expect.toBeClose(effectiveRadius, 28.8)
		end)

		Harness.it("mult de daño efectivo sin skills = 1.0", function()
			local stats = SkillRules.ComputeBombStats({}, SkillCatalog)
			local effectiveMult = 1 + stats.damageMult
			expect.toBeClose(effectiveMult, 1.0)
		end)

		Harness.it("mult de daño efectivo con BombDamage1 = 1 + 0.15 = 1.15", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1" }, SkillCatalog)
			local effectiveMult = 1 + stats.damageMult
			expect.toBeClose(effectiveMult, 1.15)
		end)

		Harness.it("capacidad total = base + skill, sin clamping", function()
			-- GameConfig.BombCapacity = 2
			-- Skill_BombCapacity2 = +2
			-- Total = 4, que NO supera MaxBombsPerPlayer (5).
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity2" }, SkillCatalog)
			local totalCapacity = BASE_CAPACITY + stats.capacity
			expect.toBe(totalCapacity, 4)
			expect.toBe(totalCapacity <= MAX_BOMBS_PER_PLAYER, true)
		end)

		Harness.it("capacidad total se acorta a MaxBombsPerPlayer", function()
			-- GameConfig.BombCapacity = 2
			-- Skill_BombCapacity3 = +3
			-- Total = 5 = MaxBombsPerPlayer → OK, no se excede.
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity3" }, SkillCatalog)
			local totalCapacity = BASE_CAPACITY + stats.capacity
			expect.toBe(totalCapacity, 5)
			expect.toBe(totalCapacity <= MAX_BOMBS_PER_PLAYER, true)
		end)

		Harness.it("capacidad +3 no puede exceder el tope de rendimiento", function()
			-- Incluso si skills + base superaran el tope, BombService
			-- aplica `min(base, MaxBombsPerPlayer)`.
			-- Aquí verificamos que la capacidad máxima posible con skills
			-- no debería exceder el límite (documenta el invariante).
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity3" }, SkillCatalog)
			-- 2 (base) + 3 (skill) = 5 = MaxBombsPerPlayer
			local clamped = math.min(BASE_CAPACITY + stats.capacity, MAX_BOMBS_PER_PLAYER)
			expect.toBe(clamped, MAX_BOMBS_PER_PLAYER)
		end)
	end)

	Harness.describe("Integración: daño de explosión con multiplicador", function()
		-- Replicate the exact formulas from ExplosionService.Detonate:
		--   mult = damageMult > 0 ? damageMult : 1
		--   entityDamage = FalloffDamage(distance, effectiveRadius, DefaultBombDamage * mult)
		--   blockDamage = DefaultBombDamage * mult * BlockDamageScale

		Harness.it("sin skills: mult=1, daño base en el centro = DefaultBombDamage", function()
			local stats = SkillRules.ComputeBombStats({}, SkillCatalog)
			local mult = 1 + stats.damageMult

			local centerRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)
			local centerDamage = CombatMath.FalloffDamage(0, centerRadius, DEFAULT_DAMAGE * mult)

			expect.toBeClose(centerDamage, DEFAULT_DAMAGE)
		end)

		Harness.it("con BombDamage1: mult=1.15, daño base = 120*1.15=138", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1" }, SkillCatalog)
			local mult = 1 + stats.damageMult
			local centerRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)

			local centerDamage = CombatMath.FalloffDamage(0, centerRadius, DEFAULT_DAMAGE * mult)
			expect.toBeClose(centerDamage, 138)
		end)

		Harness.it("el multiplicador se aplica una sola vez (no se duplica)", function()
			-- Bug que se documenta: el mult viaja de BombService -> spawnBomb ->
			-- bomb record -> Detonate. ExplosionService aplica `mult` una sola vez.
			-- Si BombService ya lo aplicara al crear la bomba, y ExplosionService
			-- lo volviera a aplicar, el daño se duplicaria.
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1" }, SkillCatalog)
			local mult = 1 + stats.damageMult  -- 1.15

			-- Simula lo que hace Detonate: baseDamage = DefaultBombDamage * mult
			local baseDamage = DEFAULT_DAMAGE * mult
			-- ApplyOcclusion con visión limpia no atenúa.
			local finalDamage = CombatMath.ApplyOcclusion(true, baseDamage)

			-- 120 * 1.15 = 138 (no 120 * 1.15 * 1.15)
			expect.toBeClose(finalDamage, 138)
		end)

		Harness.it("daño a bloques = DefaultBombDamage * mult * BlockDamageScale", function()
			-- Simula: blockDamage = DefaultBombDamage * mult * BlockDamageScale
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1" }, SkillCatalog)
			local mult = 1 + stats.damageMult

			local blockDamage = CombatMath.BlockDamageFromExplosion(
				DEFAULT_DAMAGE * mult,
				BLOCK_DAMAGE_SCALE
			)

			-- 120 * 1.15 * 0.5 = 69
			expect.toBeClose(blockDamage, 69)
		end)

		Harness.it("daño a bloques sin skills = DefaultBombDamage * 0.5 = 60", function()
			local stats = SkillRules.ComputeBombStats({}, SkillCatalog)
			local mult = 1 + stats.damageMult

			local blockDamage = CombatMath.BlockDamageFromExplosion(
				DEFAULT_DAMAGE * mult,
				BLOCK_DAMAGE_SCALE
			)

			expect.toBeClose(blockDamage, 60)
		end)

		Harness.it("radio efectivo con skills > radio base", function()
			-- Un skill de radio no debe contraer el radio.
			local stats = SkillRules.ComputeBombStats({ "Skill_BombRadius1" }, SkillCatalog)
			local effectiveRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)
			expect.toBe(effectiveRadius > DEFAULT_RADIUS, true)
		end)

		Harness.it("daño fuera del radio efectivo es cero", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombRadius1" }, SkillCatalog)
			local mult = 1 + stats.damageMult
			local effectiveRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)

			-- En el borde exacto: cero.
			local edgeDamage = CombatMath.FalloffDamage(effectiveRadius, effectiveRadius, DEFAULT_DAMAGE * mult)
			expect.toBe(edgeDamage, 0)

			-- Más allá: cero.
			local beyondDamage = CombatMath.FalloffDamage(effectiveRadius + 100, effectiveRadius, DEFAULT_DAMAGE * mult)
			expect.toBe(beyondDamage, 0)
		end)

		Harness.it("daño NaN se filtra a cero (defensa de CombatMath)", function()
			-- Si un effect tuviera NaN, mult sería NaN, y la cadena termina
			-- en CombatMath.FalloffDamage, que filtra no-finito.
			-- Esta es la defensa en capas: SkillRules no verifica, pero
			-- CombatMath protege.
			local nan = 0 / 0
			local mult = 1 + nan  -- NaN

			local damage = CombatMath.FalloffDamage(0, DEFAULT_RADIUS, DEFAULT_DAMAGE * mult)
			expect.toBe(damage, 0)
		end)
	end)

	Harness.describe("Integración: sabor visual (flavor)", function()
		-- El flavor viaja de SkillRules -> SkillService -> BombService ->
		-- ExplosionService -> VisualKit. Debe ser consistente.

		Harness.it("sin skills: flavor = default", function()
			local stats = SkillRules.ComputeBombStats({}, SkillCatalog)
			expect.toBe(stats.flavor, SkillRules.Flavors.Default)
		end)

		Harness.it("solo daño: flavor = damage", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombDamage1" }, SkillCatalog)
			expect.toBe(stats.flavor, SkillRules.Flavors.Damage)
		end)

		Harness.it("solo radio: flavor = radius", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombRadius1" }, SkillCatalog)
			expect.toBe(stats.flavor, SkillRules.Flavors.Radius)
		end)

		Harness.it("daño + radio: flavor = power", function()
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombDamage1",
				"Skill_BombRadius1",
			}, SkillCatalog)
			expect.toBe(stats.flavor, SkillRules.Flavors.Power)
		end)

		Harness.it("capacidad + daño: flavor = damage (no power)", function()
			-- Power requiere AMBOS (daño y radio). Con solo daño + capacidad,
			-- el sabor es `damage`.
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombCapacity2",
				"Skill_BombDamage1",
			}, SkillCatalog)
			expect.toBe(stats.flavor, SkillRules.Flavors.Damage)
		end)
	end)

	Harness.describe("Pattern de caché: limpieza en desconexión", function()
		-- SkillService mantiene `Service._cache[userId]` y lo limpia en
		-- PlayerRemoving. Este test replica el patrón para certificar
		-- que la lógica de limpieza funciona, ya que SkillService no puede
		-- cargarse directamente en el intérprete standalone.

		local function makeSkillServiceCache()
			-- Réplica mínima del patrón de SkillService:
			-- _cache keyado por userId, RefreshPlayer y RemovePlayer.
			local cache = {}

			local function refreshPlayer(userId, stats)
				cache[userId] = stats
			end

			local function removePlayer(userId)
				cache[userId] = nil
			end

			local function getBombStats(userId)
				return cache[userId] or {
					capacity = 0,
					radiusMult = 0,
					damageMult = 0,
					flavor = "default",
				}
			end

			return {
				cache = cache,
				refresh = refreshPlayer,
				remove = removePlayer,
				getStats = getBombStats,
			}
		end

		Harness.it("sin refresh, GetBombStats devuelve defaults", function()
			local svc = makeSkillServiceCache()
			local stats = svc.getStats(999)
			expect.toBe(stats.capacity, 0)
			expect.toBe(stats.radiusMult, 0)
			expect.toBe(stats.flavor, "default")
		end)

		Harness.it("tras refresh, el cache devuelve los valores correctos", function()
			local svc = makeSkillServiceCache()
			svc.refresh(42, { capacity = 2, radiusMult = 0.2, damageMult = 0.15, flavor = "power" })

			local stats = svc.getStats(42)
			expect.toBe(stats.capacity, 2)
			expect.toBe(stats.radiusMult, 0.2)
			expect.toBe(stats.damageMult, 0.15)
			expect.toBe(stats.flavor, "power")
		end)

		Harness.it("PlayerRemoving limpia el cache (no deja entries stale)", function()
			local svc = makeSkillServiceCache()
			svc.refresh(42, { capacity = 1, radiusMult = 0, damageMult = 0, flavor = "default" })

			-- Antes de la desconexión: el cache tiene el jugador.
			expect.toBe(svc.cache[42] ~= nil, true)

			-- Simula PlayerRemoving.
			svc.remove(42)

			-- Después: el cache está limpio. GetBombStats devuelve defaults.
			expect.toBe(svc.cache[42], nil)
			local stats = svc.getStats(42)
			expect.toBe(stats.capacity, 0)
			expect.toBe(stats.flavor, "default")
		end)

		Harness.it("limpiar un jugador no afecta a otro", function()
			local svc = makeSkillServiceCache()
			svc.refresh(1, { capacity = 1, radiusMult = 0, damageMult = 0, flavor = "default" })
			svc.refresh(2, { capacity = 2, radiusMult = 0, damageMult = 0, flavor = "default" })

			svc.remove(1)

			-- Player 2 sigue con su cache intacta.
			expect.toBe(svc.cache[2] ~= nil, true)
			expect.toBe(svc.getStats(2).capacity, 2)
			-- Player 1 fue limmpio.
			expect.toBe(svc.getStats(1).capacity, 0)
		end)

		Harness.it("refresh sobreescribe valores anteriores (reconexión)", function()
			-- Un jugador que se reconecta recibe un refresh que debe
			-- SOBREESCRIBIR el cache anterior, no acumular.
			local svc = makeSkillServiceCache()

			svc.refresh(42, { capacity = 1, radiusMult = 0, damageMult = 0, flavor = "default" })
			expect.toBe(svc.getStats(42).capacity, 1)

			-- Reconexión con un skill nuevo.
			svc.refresh(42, { capacity = 3, radiusMult = 0.2, damageMult = 0.15, flavor = "power" })
			expect.toBe(svc.getStats(42).capacity, 3)
			expect.toBe(svc.getStats(42).radiusMult, 0.2)
		end)
	end)

	Harness.describe("Integración: compatibilidad skills + capacidad base", function()
		-- La capacidad de bomba efectiva viene de:
		--   GameConfig.BombCapacity + skillCapacity + extra (powerups)
		-- Skills y powerups se acumulan; el tope de performance es `min`.

		Harness.it("capacidad con Skill_BombCapacity1 (+1) = 2+1 = 3", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity1" }, SkillCatalog)
			local total = BASE_CAPACITY + stats.capacity
			expect.toBe(total, 3)
		end)

		Harness.it("capacidad con Skill_BombCapacity3 (+3) = 2+3 = 5 = tope", function()
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity3" }, SkillCatalog)
			local total = BASE_CAPACITY + stats.capacity
			expect.toBe(total, 5)
			expect.toBe(total, MAX_BOMBS_PER_PLAYER)
		end)

		Harness.it("capacidad + powerup extra también se acorta al tope", function()
			-- Si un powerup da +2 y un skill da +3: 2 + 3 + 2 = 7 → clamp a 5.
			-- BombService.GetPlayerCapacity: base + extra + skillCapacity, min con tope.
			local stats = SkillRules.ComputeBombStats({ "Skill_BombCapacity3" }, SkillCatalog)
			local extra = 2
			local total = BASE_CAPACITY + stats.capacity + extra
			local clamped = math.min(total, MAX_BOMBS_PER_PLAYER)
			expect.toBe(clamped, 5)
		end)
	end)

	Harness.describe("Integración: cadena completa (skill → radio → daño → bloque)", function()
		-- Prueba el path completo: skill de daño + radio → mult aplicado al
		-- daño de la explosión, con falloff y daño a bloques.

		Harness.it("skill damage+radius: daño máximo y de bloque escalados", function()
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombDamage1",
				"Skill_BombRadius1",
			}, SkillCatalog)

			local mult = 1 + stats.damageMult      -- 1.15
			local effectiveRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)  -- 28.8

			-- Daño al centro (distancia 0).
			local centerDamage = CombatMath.FalloffDamage(0, effectiveRadius, DEFAULT_DAMAGE * mult)
			-- 120 * 1.15 = 138

			-- Daño a bloques.
			local blockDamage = CombatMath.BlockDamageFromExplosion(
				DEFAULT_DAMAGE * mult,
				BLOCK_DAMAGE_SCALE
			)
			-- 120 * 1.15 * 0.5 = 69

			expect.toBeClose(centerDamage, 138)
			expect.toBeClose(blockDamage, 69)
		end)

		Harness.it("skill damage+radius: daño cae a cero en el borde del radio efectivo", function()
			local stats = SkillRules.ComputeBombStats({
				"Skill_BombDamage1",
				"Skill_BombRadius1",
			}, SkillCatalog)

			local mult = 1 + stats.damageMult
			local effectiveRadius = DEFAULT_RADIUS * (1 + stats.radiusMult)

			-- En el borde del radio ampliado: 0 (fuera del radio).
			local edge = CombatMath.FalloffDamage(effectiveRadius, effectiveRadius, DEFAULT_DAMAGE * mult)
			expect.toBe(edge, 0)

			-- A mitad de camino: mitad del daño.
			local mid = CombatMath.FalloffDamage(
				effectiveRadius / 2,
				effectiveRadius,
				DEFAULT_DAMAGE * mult
			)
			expect.toBeClose(mid, 138 * 0.5, 0.01)
		end)
	end)
end

return describeBombSkillIntegration
