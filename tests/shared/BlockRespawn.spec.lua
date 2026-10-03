--!strict
--[[
	BlockRespawn.spec
	Pruebas de la REAPARICION de bloques destruibles.

	POR QUE EXISTE
	--------------
	El bloque de mayor riesgo del sistema no es la destruccion (esa ya
	estaba cubierta por `Destruction.spec`) sino lo que pasa DESPUES: un
	temporizador por destruccion que puede duplicar bloques, resucitar
	bloques de un mundo apagado o resucitar un bloque ya reparado.

	Como `BlockRespawnRules` es logica pura, estas pruebas ejecutan el
	codigo REAL, no una copia: el mismo modulo que carga
	`DestructionService` en el servidor.

	LA PRUEBA DE 100 DESTRUCCIONES
	-----------------------------
	Se destruyen 100 bloques, se_programan 100 respawns y se ejecutan los
	100. Lo que se comprueba al final es exactamente lo que se pedia:
	0 duplicados, 0 bloques permanentemente perdidos y 0 estados
	corruptos. Si el sistema tuviera unacondition de carrera, 100
	repeticiones la hacen visible; con 5 no.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Respawn = require("../../src/ReplicatedStorage/Shared/Libraries/BlockRespawnRules")

-- Rango de respawn del bloque de pruebas. Los mismos numeros que propone
-- el diseno (8..25 s) para que la prueba mida el sistema real.
local RESPAWN_MIN = 8
local RESPAWN_MAX = 25

--- Generador determinista y DISTRIBUIDO.
---
--- No se usa `math.random` porque las pruebas tienen que ser
--- reproducibles: un fallo que sale una vez de cada diez no sirve para
--- nada.
---
--- El paso se aplica ESCALADO por la razon aurea, y no tal cual. Un paso
--- ENTERO sobre un rango estrecho (8..25 son 17 valores) recorre el rango
--- en 17 llamadas y 100 bloques solo producirian 17 esperas distintas: el
--- sistema seria correcto, pero la prueba no podria distinguir "repartido"
--- de "repetido". Con la escala, dos bloques seguidos casi nunca coinciden
--- y el ciclo es mucho mas largo que el numero de bloques de la prueba.
---
--- La razon aurea (0.618...) se usa porque reparte de forma uniforme, sin
--- caer en clusters: dos bloques seguidos casi nunca reciben la misma espera
--- y el ciclo es mucho mas largo que el numero de bloques de la prueba.
--- @param step number avance por llamada, escalado internamente
--- @return fun(min: number, max: number): number
local PHI_STEP = 0.6180339887

local function makeRoll(step: number)
	local calls = 0

	local roll = function(min: number, max: number): number
		calls += 1
		local span = max - min

		if span <= 0 then
			return min
		end

		-- El ciclo cubre todo el rango sin repetitiones evidente.
		return min + ((calls - 1) * step * PHI_STEP) % span
	end

	return roll
end

--- Crea un registro activo en el mundo indicado.
--- @param key string
--- @param worldId string?
--- @return any
local function newRecord(key: string, worldId: string?): any
	return Respawn.NewRecord(key, worldId or "Forest")
end

local function describeBlockRespawn()
	Harness.describe("BlockRespawnRules: estado y transiciones", function()
		Harness.it("un bloque nuevo empieza ACTIVE y sin generacion", function()
			local record = newRecord("Block_A")

			expect.toBe(record.State, Respawn.State.Active)
			expect.toBe(record.Generation, 0)
			expect.toBe(record.ReadyAt, 0)
			expect.toBe(record.Delay, 0)
		end)

		Harness.it("destruir pasa a DESTROYED y programa el respawn", function()
			local roll = makeRoll(3)
			local record = newRecord("Block_A")

			local scheduled, delay = Respawn.Destroy(record, roll, 100, RESPAWN_MIN, RESPAWN_MAX)

			expect.toBe(scheduled, true)
			expect.toBe(record.State, Respawn.State.Destroyed)
			expect.toBe(record.Generation, 1)
			expect.toBe(delay >= RESPAWN_MIN and delay <= RESPAWN_MAX, true)
			expect.toBe(record.ReadyAt, 100 + delay)
		end)

		Harness.it("destruir un bloque YA destruido no reprograma nada", function()
			-- Esta es la defensa contra el doble temporizador: si una
			-- segunda explosion llega antes del respawn, la espera original
			-- se conserva intacta.
			local roll = makeRoll(3)
			local record = newRecord("Block_A")

			Respawn.Destroy(record, roll, 100, RESPAWN_MIN, RESPAWN_MAX)
			local readyAt = record.ReadyAt

			local scheduled, delay = Respawn.Destroy(record, roll, 101, RESPAWN_MIN, RESPAWN_MAX)

			expect.toBe(scheduled, false)
			expect.toBe(delay, 0)
			expect.toBe(record.ReadyAt, readyAt)
			expect.toBe(record.Generation, 1)
		end)

		Harness.it("el plazo solo vence cuando toca, ni antes ni despues", function()
			local roll = makeRoll(3)
			local record = newRecord("Block_A")
			Respawn.Destroy(record, roll, 0, RESPAWN_MIN, RESPAWN_MAX)

			expect.toBe(Respawn.IsReady(record, record.ReadyAt - 0.01), false)
			expect.toBe(Respawn.IsReady(record, record.ReadyAt), true)
			expect.toBe(Respawn.IsReady(record, record.ReadyAt + 10), true)
		end)

		Harness.it("un bloque ACTIVO nunca aparece como listo para respawnear", function()
			-- Sin esto, `IsReady` sobre un bloque vivo haria que un
			-- temporizador de una ronda anterior lo "resucitara".
			local record = newRecord("Block_A")

			expect.toBe(Respawn.IsReady(record, 99999), false)
		end)
	end)

	Harness.describe("BlockRespawnRules: las validaciones del respawn", function()
		--- Prepara un bloque destruido cuyo plazo ya vencio.
		--- @return any record
		--- @return number generation generacion esperada
		local function readyRecord()
			local roll = makeRoll(3)
			local record = newRecord("Block_A")
			Respawn.Destroy(record, roll, 0, RESPAWN_MIN, RESPAWN_MAX)
			return record, record.Generation
		end

		--- @param record any
		--- @param generation number
		--- @return boolean
		local function allowed(record: any, generation: number): boolean
			local ok = Respawn.CanRespawn(record, record.ReadyAt + 0.5, {
				generation = generation,
				worldActive = true,
			})
			return ok
		end

		Harness.it("con un mundo activo y sin obstaculos, el respawn se permite", function()
			local record, generation = readyRecord()

			local ok, reason = Respawn.CanRespawn(record, record.ReadyAt + 0.5, {
				generation = generation,
				worldActive = true,
			})

			expect.toBe(ok, true)
			expect.toBe(reason, nil)
		end)

		Harness.it("NO respawnea en un mundo apagado", function()
			-- El temporizador sobrevive al fin de ronda. Sin esta
			-- comprobacion, el bloque aparece en un mapa ya vacio.
			local record, generation = readyRecord()

			local ok, reason = Respawn.CanRespawn(record, record.ReadyAt + 0.5, {
				generation = generation,
				worldActive = false,
			})

			expect.toBe(ok, false)
			expect.toBe(reason, "mundo inactivo")
		end)

		Harness.it("NO respawnea con una generacion obsoleta", function()
			-- El timer de una destruccion anterior: vencido el plazo, sigue
			-- en la cola, pero su token ya no es valido.
			local record, generation = readyRecord()

			expect.toBe(allowed(record, generation - 1), false)
			expect.toBe(allowed(record, generation), true)
		end)

		Harness.it("NO respawnea si ya existe una copia activa", function()
			-- La defensa DIRECTA contra cuatro copias del mismo bloque.
			local record, generation = readyRecord()

			local ok, reason = Respawn.CanRespawn(record, record.ReadyAt + 0.5, {
				generation = generation,
				worldActive = true,
				hasActiveCopy = true,
			})

			expect.toBe(ok, false)
			expect.toBe(reason, "ya existe una copia activa")
		end)

		Harness.it("NO respawnea con una entidad incompatible en la posicion", function()
			local record, generation = readyRecord()

			local ok, reason = Respawn.CanRespawn(record, record.ReadyAt + 0.5, {
				generation = generation,
				worldActive = true,
				hasBlockingEntity = true,
			})

			expect.toBe(ok, false)
			expect.toBe(reason, "hay una entidad en la posicion")
		end)

		Harness.it("NO respawnea un bloque que ya fue reparado", function()
			local record, generation = readyRecord()
			Respawn.Restore(record)

			local ok, reason = Respawn.CanRespawn(record, 99999, {
				generation = generation,
				worldActive = true,
			})

			expect.toBe(ok, false)
			expect.toBe(reason, "estado no destruido")
		end)

		Harness.it("un bloque bloqueado por fin de ronda no respawnea", function()
			local record, generation = readyRecord()
			Respawn.Lock(record)

			expect.toBe(allowed(record, generation), false)
		end)

		Harness.it("Restore deja el bloque como estaba y cancela el respawn", function()
			local record = newRecord("Block_A")
			Respawn.Destroy(record, makeRoll(3), 0, RESPAWN_MIN, RESPAWN_MAX)

			expect.toBe(Respawn.Restore(record), true)
			expect.toBe(record.State, Respawn.State.Active)
			expect.toBe(record.ReadyAt, 0)
			expect.toBe(record.Delay, 0)
			-- Un segundo Restore no hace nada: ya estaba en pie.
			expect.toBe(Respawn.Restore(record), false)
		end)
	end)

	Harness.describe("BlockRespawnRules: idempotencia", function()
		Harness.it("BeginRespawn solo puede ganar UNA vez", function()
			-- Dos tareas que pasan la comprobacion en el mismo frame: solo
			-- la primera puede fabricar el bloque.
			local record = newRecord("Block_A")
			Respawn.Destroy(record, makeRoll(3), 0, RESPAWN_MIN, RESPAWN_MAX)

			expect.toBe(Respawn.BeginRespawn(record), true)
			expect.toBe(record.State, Respawn.State.Respawning)
			expect.toBe(Respawn.BeginRespawn(record), false)
			expect.toBe(Respawn.BeginRespawn(record), false)
		end)

		Harness.it("FinishRespawn solo es valido desde RESPAWNING", function()
			local record = newRecord("Block_A")

			-- Un bloque que nunca se destruyo no se puede "terminar de
			-- respawnear": seria materializarlo desde la nada.
			expect.toBe(Respawn.FinishRespawn(record), false)

			Respawn.Destroy(record, makeRoll(3), 0, RESPAWN_MIN, RESPAWN_MAX)
			Respawn.BeginRespawn(record)

			expect.toBe(Respawn.FinishRespawn(record), true)
			expect.toBe(record.State, Respawn.State.Active)
			expect.toBe(record.ReadyAt, 0)
			expect.toBe(Respawn.FinishRespawn(record), false)
		end)

		Harness.it("el ciclo completo se repite sin acumular estado", function()
			local record = newRecord("Block_A")
			local roll = makeRoll(3)

			for cycle = 1, 25 do
				Respawn.Destroy(record, roll, 0, RESPAWN_MIN, RESPAWN_MAX)
				expect.toBe(record.State, Respawn.State.Destroyed)
				expect.toBe(record.Generation, cycle)

				Respawn.BeginRespawn(record)
				Respawn.FinishRespawn(record)
				expect.toBe(record.State, Respawn.State.Active)
			end

			expect.toBe(record.Generation, 25)
		end)

		Harness.it("diez tareas simultaneas producen UN solo respawn", function()
			-- Se simula la condicion de carrera: diez tareas que comprueban
			-- y actaan en el mismo instante sobre el MISMO bloque.
			local record = newRecord("Block_A")
			Respawn.Destroy(record, makeRoll(3), 0, RESPAWN_MIN, RESPAWN_MAX)

			local materialized = 0

			for _ = 1, 10 do
				local ok = Respawn.CanRespawn(record, record.ReadyAt + 0.5, {
					generation = record.Generation,
					worldActive = true,
				})

				if ok and Respawn.BeginRespawn(record) then
					materialized += 1
				end
			end

			expect.toBe(materialized, 1)
		end)
	end)

	Harness.describe("BlockRespawnRules: el azar y el rango", function()
		Harness.it("la espera siempre cae dentro del rango configurado", function()
			local roll = makeRoll(2.5)

			for _ = 1, 500 do
				local delay = Respawn.RollDelay(roll, RESPAWN_MIN, RESPAWN_MAX)
				expect.toBe(delay >= RESPAWN_MIN and delay <= RESPAWN_MAX, true)
			end
		end)

		Harness.it("un rango invertido produce la misma espera, no un error", function()
			-- El llamante puede escribir el rango en cualquier orden. Con
			-- `max < min` sin corregir, la espera seria negativa y
			-- `task.delay` reventaria el hilo entero.
			local roll = makeRoll(3)
			local delay = Respawn.RollDelay(roll, RESPAWN_MAX, RESPAWN_MIN)

			expect.toBe(delay >= RESPAWN_MIN and delay <= RESPAWN_MAX, true)
		end)

		Harness.it("un rango degenerado devuelve un valor valido", function()
			local roll = makeRoll(3)

			expect.toBe(Respawn.RollDelay(roll, 10, 10), 10)
			expect.toBe(Respawn.RollDelay(roll, 0, 0), 0)
		end)

		Harness.it("una espera negativa se acota a cero", function()
			local roll = makeRoll(3)
			local delay = Respawn.RollDelay(roll, -5, -1)

			expect.toBe(delay, 0)
		end)

		Harness.it("un generador desbordado NO puede alargar la espera", function()
			-- Si `roll` devuelve 9999 con un rango de 8..25, el bloque
			-- reapareceria "tarde" y el limite configurado no se cumpliria.
			local badRoll = function(_min: number, _max: number): number
				return 9999
			end

			expect.toBe(Respawn.RollDelay(badRoll, RESPAWN_MIN, RESPAWN_MAX), RESPAWN_MAX)
		end)

		Harness.it("100 bloques reciben esperas REPARTIDAS, no las mismas", function()
			-- El requisito es explicito: "no todos deben reaparecer juntos".
			local roll = makeRoll(3)
			local records = {}

			for index = 1, 100 do
				local record = newRecord(("Block_%d"):format(index))
				Respawn.Destroy(record, roll, 0, RESPAWN_MIN, RESPAWN_MAX)
				table.insert(records, record)
			end

			local distinct = {}

			for _, record in ipairs(records) do
				distinct[record.Delay] = true
			end

			local unique = 0

			for _ in pairs(distinct) do
				unique += 1
			end

			-- Si las 100 esperas fueran identicas, `unique` seria 1 y la
			-- arena reapareceria entera de golpe al mismo segundo.
			expect.toBe(unique > 50, true)
		end)
	end)

	Harness.describe("BlockRespawnRules: 100 destrucciones simuladas", function()
		-- Es la prueba que exige el diseno: 100 destrucciones seguidas y
		-- comprobacion de que NO queda ni un duplicado, ni un bloque
		-- perdido para siempre, ni un estado corrupto.
		--
		-- Se ejecuta una COLA ORDENADA POR INSTANTE en vez de `task.wait`:
		-- el servicio real usa `task.delay`, que aqui no existe. La cola es
		-- la misma idea y permite avanzar el tiempo de forma instantanea y
		-- determinista, sin esperas de reloj.
		--
		--- @param roll fun(min: number, max: number): number
		--- @param count number numero de bloques
		--- @return { [string]: any } bloques
		--- @return { { at: number, record: any, generation: number } } cola de respawn
		local function simulate(count: number, roll: (number, number) -> number)
			local blocks = {}
			local queue = {}

			for index = 1, count do
				local record = newRecord(("Block_%d"):format(index))
				blocks[tostring(index)] = record
				Respawn.Destroy(record, roll, 0, RESPAWN_MIN, RESPAWN_MAX)
				table.insert(queue, {
					at = record.ReadyAt,
					record = record,
					generation = record.Generation,
				})
			end

			return blocks, queue
		end

		--- Ejecuta la cola como lo haria el servicio.
		--- @param queue { { at: number, record: any, generation: number } }
		--- @param worldActive boolean
		--- @return number materialized bloques realmente resucitados
		local function runQueue(queue: { { at: number, record: any, generation: number } }, worldActive: boolean): number
			local materialized = 0

			for _, job in ipairs(queue) do
				local record = job.record
				local ok = Respawn.CanRespawn(record, job.at, {
					generation = job.generation,
					worldActive = worldActive,
				})

				if ok and Respawn.BeginRespawn(record) then
					Respawn.FinishRespawn(record)
					materialized += 1
				end
			end

			return materialized
		end

		Harness.it("0 duplicados tras 100 destrucciones y sus respawns", function()
			local roll = makeRoll(3)
			local blocks, queue = simulate(100, roll)

			expect.toBe(runQueue(queue, true), 100)
			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Destroyed), 0)
			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Respawning), 0)
			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Active), 100)
			expect.toBe(#Respawn.FindDuplicateKeys(blocks), 0)
		end)

		Harness.it("0 bloques permanentemente perdidos", function()
			-- Cada bloque destruido debe volver a `Active`. Un bloque que
			-- se queda en `Destroyed` para siempre es un hueco permanente
			-- en el mapa.
			local roll = makeRoll(3)
			local blocks, queue = simulate(100, roll)

			runQueue(queue, true)

			for _, record in pairs(blocks) do
				expect.toBe(record.State, Respawn.State.Active)
				expect.toBe(record.ReadyAt, 0)
				expect.toBe(record.Delay, 0)
			end
		end)

		Harness.it("cada bloque reaparece EN SU PROPIO instante, ni antes ni tarde", function()
			-- La propiedad que importa no es el ORDEN de la cola (los
			-- temporizadores son independientes y no se ordenan entre si),
			-- sino que el instante de reaparicion de cada bloque sea
			-- exactamente el que se le sorteo. Un bloque que reaparece
			-- antes de su plazo rompe la cuenta atras, y uno que aparece
			-- tarde hace que el jugador espere de mas.
			local roll = makeRoll(3)
			local blocks, queue = simulate(100, roll)

			local early = 0
			local late = 0

			for _, job in ipairs(queue) do
				local record = job.record

				-- Un instante ANTES del plazo debe ser rechazado.
				if Respawn.CanRespawn(record, job.at - 0.001, {
					generation = job.generation,
					worldActive = true,
				}) then
					early += 1
				end

				-- Y en el instante exacto, aceptado.
				local ok = Respawn.CanRespawn(record, job.at, {
					generation = job.generation,
					worldActive = true,
				})

				if not ok then
					late += 1
				end

				if ok then
					Respawn.BeginRespawn(record)
					Respawn.FinishRespawn(record)
				end
			end

			expect.toBe(early, 0)
			expect.toBe(late, 0)
			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Active), 100)
		end)

		Harness.it("los 100 bloques NO vuelven en el mismo instante", function()
			-- La prueba de que el azar es real y no decorativo: si toda la
			-- arena volviera en el mismo segundo, `worst` seria 100.
			local roll = makeRoll(3)
			local _blocks, queue = simulate(100, roll)

			local perInstant = {}

			for _, job in ipairs(queue) do
				-- Se agrupa por segundo entero: dos bloques que vencen en
				-- 12.1 y 12.9 se leen como el mismo segundo para el
				-- jugador, y esa es la medida que importa.
				local second = math.floor(job.at)
				perInstant[second] = (perInstant[second] or 0) + 1
			end

			local worst = 0

			for _, count in pairs(perInstant) do
				if count > worst then
					worst = count
				end
			end

			expect.toBe(worst < 100, true)
		end)

		Harness.it("repetir el ciclo 5 veces NO degrada el mapa", function()
			-- 5 rondas de 100 explosiones. Al final, los mismos 100 bloques
			-- en pie, sin duplicados y con la generacion coherente.
			local roll = makeRoll(3)
			local blocks = {}
			local generations = {}

			for index = 1, 100 do
				blocks[tostring(index)] = newRecord(("Block_%d"):format(index))
				generations[index] = 0
			end

			for _round = 1, 5 do
				local queue = {}

				for index = 1, 100 do
					local record = blocks[tostring(index)]
					Respawn.Destroy(record, roll, 0, RESPAWN_MIN, RESPAWN_MAX)
					generations[index] = record.Generation
					table.insert(queue, {
						at = record.ReadyAt,
						record = record,
						generation = record.Generation,
					})
				end

				expect.toBe(runQueue(queue, true), 100)
			end

			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Active), 100)
			expect.toBe(#Respawn.FindDuplicateKeys(blocks), 0)

			for index = 1, 100 do
				expect.toBe(generations[index], 5)
			end
		end)

		Harness.it("un mundo apagado NO pierde bloques ni crea duplicados", function()
			-- Caso de fin de ronda: los timers vencen con el mundo apagado y
			-- se rechazan. Al volver a jugar, `Restore` los devuelve todos.
			local roll = makeRoll(3)
			local blocks, queue = simulate(100, roll)

			expect.toBe(runQueue(queue, false), 0)
			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Destroyed), 100)
			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Active), 0)

			for _, record in pairs(blocks) do
				Respawn.Restore(record)
			end

			expect.toBe(Respawn.CountInState(blocks, Respawn.State.Active), 100)
			expect.toBe(#Respawn.FindDuplicateKeys(blocks), 0)
		end)

		Harness.it("un timer duplicado NO genera un segundo bloque", function()
			-- Dos timers para el MISMO bloque, como pasaria si dos
			-- explosiones destruyeran el bloque a la vez. Solo uno gana.
			local record = newRecord("Block_1")
			Respawn.Destroy(record, makeRoll(3), 0, RESPAWN_MIN, RESPAWN_MAX)

			local generation = record.Generation
			local at = record.ReadyAt
			local materialized = 0

			for _ = 1, 2 do
				local ok = Respawn.CanRespawn(record, at, {
					generation = generation,
					worldActive = true,
				})

				if ok and Respawn.BeginRespawn(record) then
					Respawn.FinishRespawn(record)
					materialized += 1
				end
			end

			expect.toBe(materialized, 1)
		end)

		Harness.it("el detector de duplicados ve una clave repetida", function()
			-- El detector tiene que ser capaz de FALLAR cuando hay
			-- duplicados: una comprobacion que nunca puede fallar no
			-- comprueba nada.
			local records = {
				a = newRecord("Block_A"),
				b = newRecord("Block_A"),
				c = newRecord("Block_C"),
			}

			local duplicates = Respawn.FindDuplicateKeys(records)

			expect.toBe(#duplicates, 1)
			expect.toBe(duplicates[1], "Block_A")
		end)
	end)
end

return describeBlockRespawn