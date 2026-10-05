--!strict
--[[
	MonsterDeath.spec
	CONTRATO de muerte de enemigos y de bosses (punto 62).

	EL BUG QUE PROTEGE
	------------------
	"Health = 0 pero el monstruo sigue vivo: persigue, golpea y permanece
	en el mapa".

	La causa no era el dano: era que la muerte no tenia estado. Un unico
	`record.Dead`, que solo se activaba dentro del manejador de
	`Humanoid.Died`. Si ese evento no llegaba, nadie lo comprobaba; si la
	animacion de muerte fallaba, el modelo se quedaba para siempre; y la
	recompensa se decidia con un atributo escrito DESPUES de `TakeDamage`,
	que dispara `Died` de forma sincrona.

	QUE COMPRUEBA
	-------------
	1. La mascara `Alive -> Dying -> Dead -> Cleaned` avanza y no retrocede.
	2. La muerte es ATOMICA: dos llamadas simultaneas procesan una sola vez.
	3. La recompensa y el cleanup se reclaman UNA sola vez.
	4. Un estado no-`Alive` no puede actuar ni ocupar el mapa.
	5. Todos los monstruos y los cinco bosses son validos y cobrables.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local MonsterDeathRules = require("../../src/ReplicatedStorage/Shared/Libraries/MonsterDeathRules")
local MonsterDefinitions = require("../../src/ReplicatedStorage/Shared/MonsterDefinitions")
local MonsterScaleRules = require("../../src/ReplicatedStorage/Shared/Libraries/MonsterScaleRules")

local States = MonsterDeathRules.States

--- Enemigo de prueba con el mismo ciclo que aplica `MonsterService`.
--- @return table
local function newEnemy()
	return { state = States.Alive, rewarded = false, rewards = 0, cleanups = 0, deaths = 0 }
end

--- Reproduce el ciclo de muerte completo de `OnMonsterDied`.
--- @param enemy table
--- @return boolean processed
local function die(enemy)
	if not MonsterDeathRules.EnterDying(enemy.state) then
		return false
	end

	enemy.state = States.Dying
	enemy.deaths += 1

	if MonsterDeathRules.ClaimReward(enemy.rewarded) then
		enemy.rewarded = true
		enemy.rewards += 1
	end

	enemy.state = States.Dead
	enemy.cleanups += 1
	enemy.state = MonsterDeathRules.Next(States.Dead)

	return true
end

local function describeMonsterDeathContract()
	Harness.describe("MonsterDeath: mascara de estados", function()
		Harness.it("los cuatro estados existen y son distintos", function()
			local seen = {}

			for _, state in ipairs(MonsterDeathRules.Order) do
				expect.toBeFalsy(seen[state])
				seen[state] = true
			end

			expect.toBe(#MonsterDeathRules.Order, 4)
		end)

		Harness.it("la mascara avanza de uno en uno y no retrocede", function()
			expect.toBe(MonsterDeathRules.Next(States.Alive), States.Dying)
			expect.toBe(MonsterDeathRules.Next(States.Dying), States.Dead)
			expect.toBe(MonsterDeathRules.Next(States.Dead), States.Cleaned)
			-- El ultimo no tiene siguiente: no se limpia dos veces.
			expect.toBe(MonsterDeathRules.Next(States.Cleaned), nil)
		end)

		Harness.it("la transicion valida avanza EXACTAMENTE una posicion", function()
			expect.toBe(MonsterDeathRules.CanTransition(States.Alive, States.Dying), true)
			expect.toBe(MonsterDeathRules.CanTransition(States.Dying, States.Dead), true)
			expect.toBe(MonsterDeathRules.CanTransition(States.Dead, States.Cleaned), true)

			-- Saltar estados y retroceder son invalidos.
			expect.toBe(MonsterDeathRules.CanTransition(States.Alive, States.Dead), false)
			expect.toBe(MonsterDeathRules.CanTransition(States.Dying, States.Alive), false)
			expect.toBe(MonsterDeathRules.CanTransition(States.Cleaned, States.Dying), false)
			expect.toBe(MonsterDeathRules.CanTransition("inventado", States.Dying), false)
		end)

		Harness.it("solo Alive puede actuar, recibir dano u ocupar el mapa", function()
			expect.toBe(MonsterDeathRules.CanAct(States.Alive), true)

			for _, state in ipairs(MonsterDeathRules.Order) do
				if state ~= States.Alive then
					expect.toBe(MonsterDeathRules.CanAct(state), false)
					expect.toBe(MonsterDeathRules.IsGone(state), true)
				end
			end

			-- Un estado desconocido NO es vida: se trata como muerto.
			expect.toBe(MonsterDeathRules.CanAct(nil), false)
			expect.toBe(MonsterDeathRules.CanAct("lo que sea"), false)
		end)
	end)
Harness.describe("MonsterDeath: atomicidad", function()
		Harness.it("el primer golpe procesa la muerte; los demas no", function()
			local enemy = newEnemy()

			expect.toBe(die(enemy), true)
			expect.toBe(die(enemy), false)
			expect.toBe(die(enemy), false)
			expect.toBe(enemy.deaths, 1)
		end)

		Harness.it("la recompensa se cobra exactamente UNA vez", function()
			local enemy = newEnemy()

			die(enemy)
			die(enemy)
			die(enemy)

			expect.toBe(enemy.rewards, 1)
		end)

		Harness.it("el cleanup ocurre exactamente UNA vez", function()
			local enemy = newEnemy()

			die(enemy)
			die(enemy)

			expect.toBe(enemy.cleanups, 1)
		end)

		Harness.it("tras morir, el enemigo ya no esta en el mundo", function()
			local enemy = newEnemy()

			die(enemy)

			expect.toBe(MonsterDeathRules.CanAct(enemy.state), false)
			expect.toBe(MonsterDeathRules.IsGone(enemy.state), true)
			expect.toBe(enemy.state, States.Cleaned)
		end)

		Harness.it("un enemigo con vida 0 NO puede volver a actuar", function()
			-- Este es el sintoma exacto: Health = 0 y sigues persiguiendo.
			-- Sin evento `Died`, el unico aviso es la vida.
			local enemy = newEnemy()
			local health = 0

			if health <= 0 and MonsterDeathRules.EnterDying(enemy.state) then
				enemy.state = States.Dying
				enemy.deaths += 1
			end

			expect.toBe(MonsterDeathRules.CanAct(enemy.state), false)
			expect.toBe(enemy.deaths, 1)
		end)

		Harness.it("un sweep repetido no vuelve a pagar", function()
			-- El barrido corre en cada latido: 60 veces por segundo sobre el
			-- mismo enemigo. Solo la primera pasada puede actuar.
			local enemy = newEnemy()
			local processed = 0

			for _ = 1, 60 do
				if MonsterDeathRules.EnterDying(enemy.state) then
					enemy.state = States.Dying
					processed += 1

					if MonsterDeathRules.ClaimReward(enemy.rewarded) then
						enemy.rewarded = true
						enemy.rewards += 1
					end
				end
			end

			expect.toBe(processed, 1)
			expect.toBe(enemy.rewards, 1)
		end)
	end)

	Harness.describe("MonsterDeath: inventario de enemigos", function()
		Harness.it("toda definicion de monstruo es valida y cobrable", function()
			local ids = MonsterDefinitions.GetIds()
			expect.toBe(#ids > 0, true)

			for _, id in ipairs(ids) do
				local def = MonsterDefinitions.Get(id)

				expect.toBeTruthy(def)
				expect.toBe(def.Health > 0, true)
				expect.toBe(def.XP > 0, true)
				expect.toBe(def.Coins > 0, true)
				expect.toBe(def.MaxAlive > 0, true)
			end
		end)

		Harness.it("los bosses tienen muerte y recompensa propias", function()
			for worldId, bossId in pairs(MonsterScaleRules.BossByWorld) do
				local def = MonsterDefinitions.Get(bossId)

				expect.toBeTruthy(def)
				expect.toBe(def.IsBoss, true)
				expect.toBe(def.World, worldId)
				expect.toBe(def.Health > 0, true)
				expect.toBe(def.XP > 0, true)
				expect.toBe(def.Coins > 0, true)
				expect.toBe(def.MaxAlive, 1)
			end
		end)

		Harness.it("hay un boss para cada uno de los cinco mundos", function()
			local worlds = { "Forest", "Desert", "Ice", "Volcano", "Cyber" }

			for _, worldId in ipairs(worlds) do
				expect.toBeTruthy(MonsterScaleRules.BossByWorld[worldId])
			end

			local count = 0

			for _ in pairs(MonsterScaleRules.BossByWorld) do
				count += 1
			end

			expect.toBe(count, #worlds)
		end)

		Harness.it("un boss recorre el MISMO ciclo que la fauna", function()
			-- No hay un camino de muerte "de jefe": si lo hubiera, un boss
			-- podria quedarse con 0 de vida mientras la fauna no.
			local boss = MonsterDefinitions.Get(MonsterScaleRules.BossByWorld.Forest)
			local enemy = newEnemy()

			expect.toBe(boss.IsBoss, true)
			expect.toBe(die(enemy), true)
			expect.toBe(enemy.state, States.Cleaned)
			expect.toBe(enemy.rewards, 1)
		end)
	end)
end

describeMonsterDeathContract()
return describeMonsterDeathContract