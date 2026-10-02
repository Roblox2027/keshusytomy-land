--!strict
--[[
	AudioPool.spec
	Pruebas del PRESTAMO de sonidos, la parte que mas recursos consume.

	POR QUE SE PRUEBA `AudioPool` Y NO EL CONTROLLER
	------------------------------------------------
	`AudioController` necesita `SoundService` e `Instance.new`, que el
	interprete `luau.exe` no tiene: `_G` es de solo lectura y no se puede
	inyectar un doble ahi. Ademas, el `ControllerRegistry` lo carga solo en
	el cliente, asi que ni siquiera llega al servidor.

	La solucion NO es reescribir el controlador en la prueba (eso probaria
	una copia, no el codigo real), sino extraer la parte que tiene una
	relacion con el rendimiento a un modulo PURO. Es la misma separacion
	que ya usa el proyecto con `CoreRules` y `CombatMath`: la regla se
	prueba sin motor, y el servicio solo la aplica.

	EL FALLO QUE EVITA
	------------------
	Sin tope, una cadena de explosiones abre un `Sound` por detonacion. Con
	`MaxExplosionsPerSecond = 30`, el cliente llega a manejar cientos de
	sonidos simultaneos y se atasca. Aqui el numero de ranuras esta
	ACOTADO por construccion y `Take` devuelve siempre un indice valido.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local AudioPool = require("../../src/ReplicatedStorage/Shared/Libraries/AudioPool")
local AudioConfig = require("../../src/ReplicatedStorage/Shared/Config/AudioConfig")

local function describeAudioPool()
	Harness.describe("AudioPool", function()
		Harness.it("crea un conjunto con el tamaño pedido", function()
			local pool = AudioPool.new(8)
			expect.toBe(pool.size, 8)
			expect.toBe(pool.index, 0)
			expect.toBe(pool.stats.Requested, 0)
			expect.toBe(pool.stats.Played, 0)
		end)

		Harness.it("un tamaño de cero o negativo se acota a una ranura", function()
			-- Con cero ranuras `Take` no tendria nada que devolver y el
			-- controller tendria que comprobar `nil` en cada llamada.
			expect.toBe(AudioPool.new(0).size, 1)
			expect.toBe(AudioPool.new(-5).size, 1)
		end)

		Harness.it("reparte las ranuras en orden y vuelve al principio", function()
			local pool = AudioPool.new(3)

			local first = AudioPool.Take(pool)
			local second = AudioPool.Take(pool)
			local third = AudioPool.Take(pool)
			local fourth = AudioPool.Take(pool)

			expect.toBe(first, 1)
			expect.toBe(second, 2)
			expect.toBe(third, 3)
			-- Circular: tras la tercera vuelve a la primera. Asi el
			-- sonido mas antiguo es el primero en reciclarse.
			expect.toBe(fourth, 1)
		end)

		Harness.it("NUNCA devuelve un indice fuera del conjunto", function()
			-- Esta es la propiedad que protege al cliente: por muchas
			-- detonaciones que haya, el indice siempre cae dentro.
			local pool = AudioPool.new(4)
			local size = pool.size

			for _ = 1, 10000 do
				local index = AudioPool.Take(pool)
				expect.toBe(index >= 1 and index <= size, true)
			end
		end)

		Harness.it("distingue la primera prestacion de las recicladas", function()
			local pool = AudioPool.new(2)

			-- La primera vez el conjunto esta libre: no se recicla nada.
			local _, recycledFirst = AudioPool.Take(pool)
			expect.toBe(recycledFirst, false)

			-- A partir de la segunda, toda prestacion recicla la ranura
			-- que ya estaba ocupada.
			local _, recycledSecond = AudioPool.Take(pool)
			expect.toBe(recycledSecond, true)
		end)

		Harness.it("cuenta peticiones, reproducciones y reciclajes", function()
			local pool = AudioPool.new(2)

			for _ = 1, 5 do
				AudioPool.Take(pool)
			end
			AudioPool.MarkPlayed(pool)
			AudioPool.MarkPlayed(pool)

			expect.toBe(pool.stats.Requested, 5)
			expect.toBe(pool.stats.Played, 2)
			-- 5 prestaciones, la primera libre y 4 recicladas.
			expect.toBe(pool.stats.Recycled, 4)
		end)

		Harness.it("Reset devuelve el conjunto a cero", function()
			local pool = AudioPool.new(3)

			for _ = 1, 10 do
				AudioPool.Take(pool)
			end
			AudioPool.Reset(pool)

			expect.toBe(pool.index, 0)
			expect.toBe(pool.stats.Requested, 0)
			expect.toBe(pool.stats.Played, 0)
			expect.toBe(pool.stats.Recycled, 0)
			-- Tras reiniciar, la siguiente prestacion es la primera
			-- ranura y no se marca como reciclada.
			local index, recycled = AudioPool.Take(pool)
			expect.toBe(index, 1)
			expect.toBe(recycled, false)
		end)

		Harness.it("el tamaño viene de la configuracion y esta acotado", function()
			-- El tope del pool sale de `AudioConfig`, y la suite de
			-- `GameConfig` comprueba que ese numero es utilizable. Aqui
			-- se comprueba que el modulo y la configuracion no se
			-- contradicen.
			local pool = AudioPool.new(AudioConfig.MaxConcurrentSfx)
			expect.toBe(pool.size, AudioConfig.MaxConcurrentSfx)
			expect.toBe(pool.size >= 1, true)
		end)

		Harness.it("dos LendingControls independientes no se pisan", function()
			-- Si el cursor fuera estado de modulo en vez de estado del
			-- conjunto, dosAPLICACIONES de audio compartirian ranuras.
			local first = AudioPool.new(2)
			local second = AudioPool.new(2)

			expect.toBe(AudioPool.Take(first), 1)
			expect.toBe(AudioPool.Take(second), 1)
			expect.toBe(first.stats.Requested, 1)
			expect.toBe(second.stats.Requested, 1)
		end)
	end)
end

return describeAudioPool
