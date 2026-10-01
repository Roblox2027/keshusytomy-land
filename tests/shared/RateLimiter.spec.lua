--!strict
--[[
	RateLimiter.spec
	Pruebas del limite de frecuencia.

	El reloj es inyectado y controlado manualmente: las pruebas son
	deterministas y no dependen del tiempo real.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local RateLimiter = require("../../src/ReplicatedStorage/Shared/Libraries/RateLimiter")

local function makeLimiter(capacity: number, refillPerSecond: number)
	local clock = { time = 0 }
	local limiter = RateLimiter.new({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		clock = function(): number
			return clock.time
		end,
	})
	return limiter, clock
end

local function describeRateLimiter()
	Harness.describe("RateLimiter", function()
		Harness.it("permite consumir hasta la capacidad inicial", function()
			local limiter = makeLimiter(3, 1)

			expect.toBe(limiter:TryConsume("a"), true)
			expect.toBe(limiter:TryConsume("a"), true)
			expect.toBe(limiter:TryConsume("a"), true)
			-- Cuarto intento sin tiempo transcurrido: rechazado.
			expect.toBe(limiter:TryConsume("a"), false)
		end)

		Harness.it("las claves son independientes entre si", function()
			local limiter = makeLimiter(1, 1)

			expect.toBe(limiter:TryConsume("jugadorA"), true)
			-- Agoto A, pero B tiene su propio bucket.
			expect.toBe(limiter:TryConsume("jugadorA"), false)
			expect.toBe(limiter:TryConsume("jugadorB"), true)
		end)

		Harness.it("refrena el spam sostenido", function()
			local limiter = makeLimiter(2, 2)

			-- Rafaga inicial permitida.
			expect.toBe(limiter:TryConsume("a"), true)
			expect.toBe(limiter:TryConsume("a"), true)

			-- 100 intentos en el mismo instante: ninguno pasa.
			local allowed = 0
			for _ = 1, 100 do
				if limiter:TryConsume("a") then
					allowed += 1
				end
			end
			expect.toBe(allowed, 0)
		end)

		Harness.it("regenera tokens con el tiempo transcurrido", function()
			local limiter, clock = makeLimiter(2, 2)

			limiter:TryConsume("a")
			limiter:TryConsume("a")
			expect.toBe(limiter:TryConsume("a"), false)

			-- 0.5s * 2 tokens/s = 1 token recuperado.
			clock.time = 0.5
			expect.toBe(limiter:TryConsume("a"), true)
		end)

		Harness.it("nunca supera la capacidad al regenerar", function()
			local limiter, clock = makeLimiter(2, 10)

			limiter:TryConsume("a")
			-- Mucho tiempo pasado: se tope en la capacidad, no de mas.
			clock.time = 100
			expect.toBeClose(limiter:GetTokens("a"), 2, 1e-6)

			expect.toBe(limiter:TryConsume("a"), true)
			expect.toBe(limiter:TryConsume("a"), true)
			expect.toBe(limiter:TryConsume("a"), false)
		end)

		Harness.it("acepta un coste mayor que uno", function()
			local limiter = makeLimiter(10, 1)

			expect.toBe(limiter:TryConsume("a", 4), true)
			expect.toBeClose(limiter:GetTokens("a"), 6, 1e-6)
			expect.toBe(limiter:TryConsume("a", 7), false)
			expect.toBe(limiter:TryConsume("a", 6), true)
		end)

		Harness.it("un coste no positivo no consume", function()
			local limiter = makeLimiter(2, 1)
			expect.toBe(limiter:TryConsume("a", 0), true)
			expect.toBeClose(limiter:GetTokens("a"), 2, 1e-6)
		end)

		Harness.it("Reset restituye el bucket de una clave", function()
			local limiter = makeLimiter(1, 1)

			limiter:TryConsume("a")
			expect.toBe(limiter:TryConsume("a"), false)

			limiter:Reset("a")

			expect.toBe(limiter:TryConsume("a"), true)
		end)

		Harness.it("Clear elimina todas las claves", function()
			local limiter = makeLimiter(1, 1)
			limiter:TryConsume("a")
			limiter:TryConsume("b")

			limiter:Clear()

			expect.toBeClose(limiter:GetTokens("a"), 1, 1e-6)
			expect.toBeClose(limiter:GetTokens("b"), 1, 1e-6)
		end)

		Harness.it("rechaza configuraciones invalidas", function()
			local threwA = expect.toThrow(function()
				RateLimiter.new({ capacity = 0, refillPerSecond = 1 })
			end)
			expect.toBe(threwA, true)

			local threwB = expect.toThrow(function()
				RateLimiter.new({ capacity = 1, refillPerSecond = 0 })
			end)
			expect.toBe(threwB, true)
		end)
	end)
end

return describeRateLimiter