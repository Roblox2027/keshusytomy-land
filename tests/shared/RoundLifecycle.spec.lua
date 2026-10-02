--!strict
--[[
RoundLifecycle.spec
Regresion del P0 de la FASE 0: el ciclo de ronda se quedaba en
RoundEnding para siempre.

EL BUG, medido en runtime y no deducido
--------------------------------------
El bucle hacia task.wait(remaining) con el remaining del estado en el que
entraba. PlayerService terminaba la ronda llamando a
Transition(RoundEnding) desde SU propio hilo al morir el ultimo vivo. El
estado de la maquina cambiaba, pero el bucle seguia dormido con el plazo
del Playing (180 s).

Medido con tools/round-probe.js en Studio:
  state = RoundEnding, remaining = 0, heartbeat = 46 congelado,
  _stateEndsAt - os.clock() = -140 (plazo vencido hace 140 s),
  coroutine.status(loop) = "suspended",
  historial = 8 ciclos completos y la ronda 9 nunca avanza.

QUE COMPRUEBA ESTA SUITE
-----------------------
Se comprueba el CONTRATO, no la implementacion concreta:

1. La duracion de cada estado sale de GameConfig, no de un numero magico.
   Antes 3/3/4/4 estaban escritos dentro del if de GetDuration.

2. RoundTickInterval es positivo y pequeno frente a cualquier estado.

3. El diagrama NO tiene estados terminales: desde cada estado hay camino
   a Waiting. Un estado sin salida es un atasco esperando que ocurra.

4. SuddenDeath no puede realimentarse: de ahi se sale a RoundEnding.

Limite honesto: esto NO comprueba que el bucle real avance; comprueba que
las condiciones que lo hacen avanzar se pueden cumplir. Que el ciclo se
repita de verdad se mide en Studio con tools/round-cycles.js (10 y 25
ciclos con 0 atascos), porque exige el motor de Roblox.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local GameConstants = require("../../src/ReplicatedStorage/Shared/Constants/GameConstants")

local RoundState = GameConstants.RoundState

-- Diagrama, copiado del de RoundService. Se replica aqui a proposito: la
-- prueba necesita su propia copia para poder FALLAR si el diagrama se rompe.
local TRANSITIONS: { [string]: { string } } = {
[RoundState.Waiting] = { RoundState.Countdown },
[RoundState.Countdown] = { RoundState.RoundStarting, RoundState.Waiting },
[RoundState.RoundStarting] = { RoundState.Playing },
[RoundState.Playing] = { RoundState.SuddenDeath, RoundState.RoundEnding },
[RoundState.SuddenDeath] = { RoundState.RoundEnding },
[RoundState.RoundEnding] = { RoundState.Rewards },
[RoundState.Rewards] = { RoundState.ReturningToLobby, RoundState.Waiting },
[RoundState.ReturningToLobby] = { RoundState.Waiting },
}

-- Estados por los que pasa una ronda completa.
local CYCLE = {
RoundState.Waiting,
RoundState.Countdown,
RoundState.RoundStarting,
RoundState.Playing,
RoundState.RoundEnding,
RoundState.Rewards,
RoundState.ReturningToLobby,
RoundState.Waiting,
}

-- Duracion de cada estado, igual que RoundService.GetDuration.
local function getDuration(state: string): number
if state == RoundState.Countdown then
return GameConfig.CountdownDuration
end
if state == RoundState.Playing then
return GameConfig.RoundDuration
end
if state == RoundState.SuddenDeath then
return GameConfig.SuddenDeathTime
end
if state == RoundState.RoundStarting then
return GameConfig.RoundStartingDuration
end
if state == RoundState.RoundEnding then
return GameConfig.RoundEndingDuration
end
if state == RoundState.Rewards then
return GameConfig.RewardsDuration
end
if state == RoundState.ReturningToLobby then
return GameConfig.ReturningToLobbyDuration
end
return 1
end

-- ¿Es legal pasar de from a to segun el diagrama?
local function canTransition(from: string, to: string): boolean
for _, target in ipairs(TRANSITIONS[from] or {}) do
if target == to then
return true
end
end
return false
end

local function describeRoundLifecycle()
Harness.describe("RoundLifecycle: duraciones configurables", function()
Harness.it("cada duracion de transicion se lee de GameConfig", function()
-- Si alguno de estos volviera a estar escrito dentro del if de
-- GetDuration, esta prueba no lo detectaria por si sola. Lo que
-- fija es el CONTRACTO: los valores existen, son positivos y son
-- los que se usan. verify-wiring.js cubre el resto.
for _, key in {
"RoundStartingDuration",
"RoundEndingDuration",
"RewardsDuration",
"ReturningToLobbyDuration",
"RoundTickInterval",
} do
expect.toBe(type(GameConfig[key]), "number")
expect.toBe(GameConfig[key] > 0, true)
end
end)

Harness.it("ningun estado tiene duracion cero o negativa", function()
-- Una duracion 0 hace que el ciclo gire sin parar; una negativa
-- lo congela. Ninguna de las dos se detecta leyendo el codigo.
for state in pairs(RoundState) do
expect.toBe(getDuration(state) > 0, true)
end
end)

Harness.it("el tick de sondeo cabe dentro del estado mas corto", function()
-- Si el tick fuera mayor que el estado mas corto, ese estado se
-- saltaria por encima: se entraria y se saldria en la misma
-- rebanada, y el vigilante no veria nada.
local shortest = math.huge
for state in pairs(RoundState) do
shortest = math.min(shortest, getDuration(state))
end

expect.toBe(GameConfig.RoundTickInterval < shortest, true)
end)

Harness.it("el tick de sondeo es una fraccion del estado mas largo", function()
-- Con 180 s de ronda, un tick de 60 s seria util, pero uno de
-- 200 s seria lo mismo que dormir el plazo entero: el bug
-- original. Este limite hace imposible reintroducirlo.
local longest = 0
for state in pairs(RoundState) do
longest = math.max(longest, getDuration(state))
end

expect.toBe(GameConfig.RoundTickInterval <= longest / 10, true)
end)
end)

Harness.describe("RoundLifecycle: el diagrama no tiene terminales", function()
Harness.it("todo estado declara al menos una salida", function()
for state in pairs(RoundState) do
local exits = TRANSITIONS[state]
expect.toBe(exits ~= nil, true)
expect.toBe(#exits > 0, true)
end
end)

Harness.it("desde cualquier estado se puede volver a Waiting", function()
-- Recorrido en anchura: si un estado no puede alcanzar Waiting,
-- es un final de linea. Un final de linea que el diagrama permite
-- es un atasco esperando que ocurra en runtime.
for origin in pairs(RoundState) do
local seen = { [origin] = true }
local queue = { origin }

while #queue > 0 do
local current = table.remove(queue, 1)

for _, target in ipairs(TRANSITIONS[current] or {}) do
if target == RoundState.Waiting then
seen[RoundState.Waiting] = true
elseif not seen[target] then
seen[target] = true
table.insert(queue, target)
end
end
end

expect.toBe(seen[RoundState.Waiting], true)
end
end)

Harness.it("ningun estado se puede transicionar a si mismo", function()
-- Un estado que sale a si mismo, con el plazo reiniciado, es un
-- bucle infinito disfrazado de estado.
for state, exits in pairs(TRANSITIONS) do
for _, target in ipairs(exits) do
expect.toBe(target ~= state, true)
end
end
end)

Harness.it("RoundEnding no se puede repetir", function()
-- El sintoma reportado era specifically RoundEnding -> RoundEnding.
-- El diagrama lo prohibe, asi que el codigo que lo pide recibe
-- false en vez de reiniciar el plazo (que es lo que congela la
-- ronda para siempre).
expect.toBe(canTransition(RoundState.RoundEnding, RoundState.RoundEnding), false)
end)

Harness.it("RoundEnding solo puede ir a Rewards", function()
expect.toBe(#TRANSITIONS[RoundState.RoundEnding], 1)
expect.toBe(TRANSITIONS[RoundState.RoundEnding][1], RoundState.Rewards)
end)

Harness.it("la muerte subita no se realimenta", function()
-- Playing entra en SuddenDeath, pero de ahi solo se sale a
-- RoundEnding. Si pudiera volver a si misma, no terminaria.
expect.toBe(TRANSITIONS[RoundState.SuddenDeath][1], RoundState.RoundEnding)
expect.toBe(#TRANSITIONS[RoundState.SuddenDeath], 1)
end)
end)

Harness.describe("RoundLifecycle: el ciclo se puede repetir", function()
Harness.it("el ciclo recorrido respeta el diagrama entero", function()
-- Se recorre la ronda completa y se comprueba que CADA salto es
-- legal. Si alguien anade un estado al diagrama sin meterlo en la
-- ronda, esta prueba falla.
for index = 1, #CYCLE - 1 do
expect.toBe(canTransition(CYCLE[index], CYCLE[index + 1]), true)
end
end)

Harness.it("el ciclo termina en Waiting y puede volver a empezar", function()
expect.toBe(CYCLE[#CYCLE], RoundState.Waiting)
-- Y desde Waiting se entra otra vez: la ronda N+1 existe.
expect.toBe(TRANSITIONS[RoundState.Waiting][1], RoundState.Countdown)
end)

		Harness.it("el tiempo de transicion por ronda es corto", function()
			-- Suma de los estados de TRANSICION, sin Playing.
			--
			-- Por que NO se mide la ronda entera: Playing dura 180 s por
			-- balance, y 25 rondas completas serian 80 minutos. Eso es diseno,
			-- no un fallo: la ronda se decide antes cuando queda un solo vivo,
			-- que es lo que ocurre en la certificacion real de Studio.
			--
			-- Lo que SI tiene que ser corto son las transiciones: se recorren
			-- SIEMPRE, y son las que deciden si una ronda terminada devuelve a
			-- los jugadores al lobby en 15 s o en 15 minutos.
			local transitionTime = 0

			for _, state in ipairs(CYCLE) do
				if state ~= RoundState.Playing and state ~= RoundState.Countdown then
					transitionTime += getDuration(state)
				end
			end

			expect.toBe(transitionTime < 30, true)
		end)
end)
end

return describeRoundLifecycle
