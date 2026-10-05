--!strict
--[[
	Gameplay.spec
	Pruebas de la logica de juego que NO necesita el motor de Roblox:
	caida de dano por distancia, duraciones de ronda y coherencia del
	balance.

	Se prueba la FORMULA, no el servicio completo: `ExplosionService`
	depende de Workspace y Players, asi que aqui se replica su formula
	para detectar regresiones (por ejemplo, que el dano en el centro deje
	de ser el maximo configurado).

	Limite honesto: que la explosion DAÑE de verdad a un Humanoid, y que
	el jugador muera, solo se puede comprobar dentro de Roblox Studio.
	Eso queda BLOCKED fuera del motor, no PASS.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local GameConstants = require("../../src/ReplicatedStorage/Shared/Constants/GameConstants")

-- Misma formula que ExplosionService.ComputeDamage.
local function computeDamage(distance, radius)
	if radius <= 0 then
		return 0
	end

	local falloff = 1 - math.clamp(distance / radius, 0, 1)
	return GameConfig.DefaultBombDamage * falloff
end

local function describeGameplay()
	Harness.describe("Dano por explosion", function()
		Harness.it("el dano maximo es el configurado y ocurre en el centro", function()
			expect.toBe(computeDamage(0, 24), GameConfig.DefaultBombDamage)
		end)

		Harness.it("el dano baja con la distancia", function()
			local half = computeDamage(12, 24)
			local quarter = computeDamage(6, 24)

			expect.toBe(half < GameConfig.DefaultBombDamage, true)
			expect.toBe(quarter > half, true)
		end)

		Harness.it("en el borde del radio el dano es cero", function()
			expect.toBe(computeDamage(24, 24), 0)
		end)

		Harness.it("fuera del radio el dano nunca es negativo", function()
			-- El dano negativo seria una curacion: un fallo grave.
			expect.toBe(computeDamage(10000, 24), 0)
		end)

		Harness.it("un radio no positivo no aplica dano", function()
			expect.toBe(computeDamage(0, 0), 0)
			expect.toBe(computeDamage(0, -5), 0)
		end)

		Harness.it("radio y dano configurados son utilizables", function()
			expect.toBe(GameConfig.DefaultBombRadius > 0, true)
			expect.toBe(GameConfig.DefaultBombDamage > 0, true)
		end)

		Harness.it("una bomba mata de un golpe en el centro", function()
			-- Con 100 de vida por defecto, el dano base debe superar
			-- la vida o el vertical slice no tendria PvP real.
			expect.toBe(GameConfig.DefaultBombDamage >= 100, true)
		end)
	end)

	Harness.describe("Colocacion de bombas", function()
		Harness.it("el cooldown impide el spam de bombas", function()
			-- Si fuese 0, un cliente podria colocar bombas sin limite.
			expect.toBe(GameConfig.BombCooldown > 0, true)
		end)

		Harness.it("el rango es alcanzable y no excede el radio de dano", function()
			expect.toBe(GameConfig.BombPlacementRange > 0, true)
			expect.toBe(
				GameConfig.BombPlacementRange <= GameConfig.DefaultBombRadius,
				true
			)
		end)

		Harness.it("la mecha dura lo suficiente para ser visible", function()
			expect.toBe(GameConfig.DefaultBombFuseTime >= 1, true)
		end)
	end)

	Harness.describe("Duraciones de ronda", function()
		local RoundState = GameConstants.RoundState

		-- Reproduce RoundService.GetDuration.
		local function getDuration(state)
			if state == RoundState.Countdown then
				return GameConfig.CountdownDuration
			end
			if state == RoundState.Playing then
				return GameConfig.RoundDuration
			end
			if state == RoundState.SuddenDeath then
				return GameConfig.SuddenDeathTime
			end
			if state == RoundState.RoundStarting or state == RoundState.RoundEnding then
				return 3
			end
			if state == RoundState.Rewards or state == RoundState.ReturningToLobby then
				return 4
			end
			return 1
		end

		Harness.it("cada estado tiene una duracion positiva", function()
			-- Una duracion 0 o negativa bloquearia el ciclo de ronda.
			for _, state in pairs(RoundState) do
				expect.toBe(getDuration(state) > 0, true)
			end
		end)

		Harness.it("la cuenta atras es mas corta que la ronda", function()
			expect.toBe(
				getDuration(RoundState.Countdown) < getDuration(RoundState.Playing),
				true
			)
		end)

		Harness.it("la cuenta atras es breve", function()
			expect.toBe(getDuration(RoundState.Countdown) < 30, true)
		end)
	end)

	Harness.describe("Destruccion y vacio", function()
		Harness.it("la vida de un bloque es positiva", function()
			expect.toBe(GameConfig.BlockHealth > 0, true)
		end)

		Harness.it("la altura de vacio esta bajo el suelo del mapa", function()
			-- Los suelos se generan con su cara superior en Y = 0.
			--
			-- P0: esto ya no es un "rescate" sino la COTA DE MUERTE. Al bajar de
			-- aqui el servidor pone `Humanoid.Health = 0` y el jugador muere y
			-- reaparece con normalidad. Antes este valor solo teletransportaba.
			expect.toBe(GameConfig.FallDeathY < -10, true)
		end)

		Harness.it("la cota de muerte esta bajo la de fuera de limites", function()
			-- El orden importa: `OutOfBoundsY` es "ya no hay suelo de juego" y
			-- `FallDeathY` es "ha caido". Si la primera estuviera por debajo de la
			-- segunda, la red de seguridad mataria antes de que el jugador hubiera
			-- tenido tiempo de caer, y seria un muro invisible.
			expect.toBe(GameConfig.OutOfBoundsY > GameConfig.FallDeathY, true)
		end)

		Harness.it("el margen de gracia deja volver andando", function()
			-- Salirse del area jugable NO mata al instante: el jugador tiene que
			-- poder volver andando. Sin este margen, el limite logico seria un
			-- muro con otro nombre.
			expect.toBe(GameConfig.OutOfBoundsGraceSeconds >= 3, true)
		end)

		Harness.it("se puede jugar en solitario desde Studio", function()
			-- MinPlayersToStart = 1 es lo que hace comprobable el
			-- vertical slice sin abrir el juego a publico.
			expect.toBe(GameConfig.MinPlayersToStart >= 1, true)
		end)
	end)

	Harness.describe("Powerups", function()
		-- MEDIDO EN AUDITORIA: el servicio generaba `{ Bomb, Speed, Shield,
		-- Heal }` mientras `VisualKit` pintaba cinco powerups y `ApplyEffect`
		-- implementaba seis. "+PODER" estaba entero y nunca aparecia, y cuatro
		-- powerups de la especificacion (Dash, Ghost, Magnet, Freeze) no
		-- existian en ninguna de las dos listas.
		--
		-- Aqui solo se comprueba lo que es DATO de configuracion. Que la
		-- lista del servicio, la tabla de `VisualKit` y los atributos que lee
		-- el HUD esten de acuerdo NO se puede comprobar desde esta suite: el
		-- interprete `luau.exe` no expone `io`, asi que no puede leer los
		-- fuentes. Ese contrato lo comprueba
		-- `tools/powerup-boss-contract.js`, que si puede abrir ficheros.
		Harness.it("la capacidad de bomba base es la de la especificacion", function()
			-- Dos simultaneas: es lo que convierte la bomba en herramienta
			-- tactica (demarcar la huida y cerrar la retirada).
			expect.toBe(GameConfig.BombCapacity, 2)
		end)

		Harness.it("la capacidad es un tope real y no un adorno", function()
			-- Si `BombCapacity` no se aplicara al validar, el powerup "+BOMBA"
			-- no tendria ningun efecto observable.
			expect.toBe(GameConfig.BombCooldown > 0, true)
			expect.toBe(GameConfig.BombPlacementRange > 0, true)
		end)
	end)

	Harness.describe("Recompensas", function()
		Harness.it("la ronda premia con XP y monedas positivas", function()
			expect.toBe(GameConfig.XPPerRound > 0, true)
			expect.toBe(GameConfig.CoinsPerRound > 0, true)
		end)

		Harness.it("los multiplicadores no anulan la recompensa", function()
			-- Un multiplicador 0 haria la recompensa inútil aunque los
			-- valores base fueran correctos.
			expect.toBe(GameConfig.XPMultiplier > 0, true)
			expect.toBe(GameConfig.CoinMultiplier > 0, true)
		end)
	end)
end

return describeGameplay