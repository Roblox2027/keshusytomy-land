--!strict
--[[
	StateMachine.spec
	Pruebas de la maquina de estados (base de ronda y estados de servidor).
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local StateMachine = require("../../src/ReplicatedStorage/Shared/Libraries/StateMachine")

-- Diagrama equivalente al de la ronda en la FASE 7.
local function makeRoundMachine()
	return StateMachine.new({
		initial = "Waiting",
		transitions = {
			Waiting = { "Countdown" },
			Countdown = { "RoundStarting", "Waiting" },
			RoundStarting = { "Playing" },
			Playing = { "SuddenDeath", "RoundEnding" },
			SuddenDeath = { "RoundEnding" },
			RoundEnding = { "Rewards" },
			Rewards = { "ReturningToLobby", "Waiting" },
			ReturningToLobby = { "Waiting" },
		},
		terminal = {},
	})
end

local function describeStateMachine()
	Harness.describe("StateMachine", function()
		Harness.it("arranca en el estado inicial", function()
			local machine = makeRoundMachine()
			expect.toBe(machine:Get(), "Waiting")
			expect.toBe(machine:IsRunning(), true)
		end)

		Harness.it("permite transiciones declaradas", function()
			local machine = makeRoundMachine()
			expect.toBe(machine:Transition("Countdown"), true)
			expect.toBe(machine:Get(), "Countdown")
		end)

		Harness.it("rechaza transiciones no declaradas", function()
			local machine = makeRoundMachine()

			-- Waiting -> Playing no existe en el diagrama.
			expect.toBe(machine:CanTransition("Playing"), false)
			expect.toBe(machine:Transition("Playing"), false)
			expect.toBe(machine:Get(), "Waiting")
		end)

		Harness.it("registra el historial de estados", function()
			local machine = makeRoundMachine()
			machine:Transition("Countdown")
			machine:Transition("RoundStarting")
			machine:Transition("Playing")

			local history = machine:GetHistory()
			expect.toBe(#history, 4)
			expect.toBe(history[1], "Waiting")
			expect.toBe(history[4], "Playing")
		end)

		Harness.it("los hooks se ejecutan con el estado origen y destino", function()
			local machine = makeRoundMachine()
			local capturedFrom, capturedTo

			machine:OnTransition(function(from, to)
				capturedFrom = from
				capturedTo = to
			end)

			machine:Transition("Countdown")
			expect.toBe(capturedFrom, "Waiting")
			expect.toBe(capturedTo, "Countdown")
		end)

		Harness.it("los hooks se pueden desregistrar", function()
			local machine = makeRoundMachine()
			local calls = 0
			local unregister = machine:OnTransition(function()
				calls += 1
			end)

			machine:Transition("Countdown")
			expect.toBe(calls, 1)

			unregister()
			machine:Transition("RoundStarting")
			expect.toBe(calls, 1)
		end)

		Harness.it("un estado terminal no admite salida", function()
			local machine = StateMachine.new({
				initial = "Finished",
				transitions = { Finished = { "Waiting" } },
				terminal = { "Finished" },
			})

			expect.toBe(machine:CanTransition("Waiting"), false)
			expect.toBe(machine:Transition("Waiting"), false)
		end)

		Harness.it("Stop detiene la maquina", function()
			local machine = makeRoundMachine()
			machine:Stop()

			expect.toBe(machine:IsRunning(), false)
			expect.toBe(machine:Transition("Countdown"), false)
		end)

		Harness.it("Reset vuelve al estado inicial y limpia el historial", function()
			local machine = makeRoundMachine()
			machine:Transition("Countdown")
			machine:Transition("RoundStarting")

			machine:Reset()

			expect.toBe(machine:Get(), "Waiting")
			expect.toBe(#machine:GetHistory(), 1)
		end)

		Harness.it("rechaza un estado inicial no declarado", function()
			local threw = expect.toThrow(function()
				StateMachine.new({
					initial = "Inexistente",
					transitions = { Waiting = { "Playing" } },
				})
			end)
			expect.toBe(threw, true)
		end)

		Harness.it("un ciclo completo de ronda es alcanzable", function()
			local machine = makeRoundMachine()
			local sequence = {
				"Countdown",
				"RoundStarting",
				"Playing",
				"SuddenDeath",
				"RoundEnding",
				"Rewards",
				"ReturningToLobby",
				"Waiting",
			}

			for _, state in sequence do
				expect.toBe(machine:Transition(state), true)
				expect.toBe(machine:Get(), state)
			end
		end)

		Harness.it("volver a esperar cancela el countdown", function()
			-- Regla de ronda: si se cancela, la ronda vuelve a Waiting.
			local machine = makeRoundMachine()
			machine:Transition("Countdown")

			expect.toBe(machine:Transition("Waiting"), true)
			expect.toBe(machine:Get(), "Waiting")
		end)

		Harness.it("no se puede saltar de Waiting a Playing", function()
			-- Evita estados intermedios rotos (un bug clasico de
			-- maquinas de estado escritas con if sueltos).
			local machine = makeRoundMachine()
			expect.toBe(machine:Transition("Playing"), false)
			expect.toBe(machine:Get(), "Waiting")
		end)

		Harness.it("no se puede volver de Playing a RoundStarting", function()
			local machine = makeRoundMachine()
			machine:Transition("Countdown")
			machine:Transition("RoundStarting")
			machine:Transition("Playing")

			expect.toBe(machine:Transition("RoundStarting"), false)
			expect.toBe(machine:Get(), "Playing")
		end)
	end)
end

return describeStateMachine