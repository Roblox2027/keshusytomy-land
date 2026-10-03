--!strict
--[[
	QuestCatalog.spec
	El contenido de las misiones.

	QUE COMPRUEBA Y POR QUE IMPORTA
	-------------------------------
	Una definicion de mision puede ser sintacticamente correcta y aun asi
	estar MUERTA: si su `Metric` no existe en `QuestCatalog.Metric`, la
	mision no va a progresar nunca, y el unico sintoma es "la mision no
	avanza". Eso no lo detecta ni el jugador ni un test de progreso, asi
	que se comprueba aqui, sobre el catalogo real.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local QuestRules = require("../../src/ReplicatedStorage/Shared/Libraries/QuestRules")
local QuestCatalog = require("../../src/ReplicatedStorage/Shared/Config/QuestCatalog")

local INJECT_RULES = require("../../src/ReplicatedStorage/Shared/Libraries/QuestRules")

-- El indice se construye con las reglas INYECTADAS, no con un `require`
-- interno. Es la misma razon por la que `RemoteSchema` y `ProfileSchema`
-- reciben sus dependencias: en el interprete de pruebas `script` no existe,
-- y `script.Parent` se evaluaria antes de poder proteger la llamada.
QuestCatalog.Configure(INJECT_RULES)

local function describeQuestCatalog()
	Harness.describe("QuestCatalog", function()
		---------------------------------------------------------
		-- CATALOGO
		---------------------------------------------------------

		Harness.it("el catalogo NO tiene problemas", function()
			-- La comprobacion que mas protege: valida definicion, clave
			-- normalizada y metrica conocida de TODAS las misiones.
			local problems = QuestCatalog.Validate(QuestRules)
			expect.toBe(#problems, 0)
		end)

		Harness.it("cada clave es la forma normalizada de su id", function()
			for key, definition in pairs(QuestCatalog.GetAll()) do
				expect.toBe(QuestRules.NormalizeId(definition.Id), key)
			end
		end)

		Harness.it("toda mision declara una metrica que el servidor conoce", function()
			-- Una metrica desconocida es una mision muerta: existe en el
			-- catalogo, se la ve en la UI, y no avanza nunca.
			local known = {}

			for _, metric in pairs(QuestCatalog.Metric) do
				known[metric] = true
			end

			for _, definition in ipairs(QuestCatalog.List()) do
				expect.toBe(known[definition.Metric], true)
			end
		end)

		Harness.it("toda mision tiene objetivo positivo y recompensa valida", function()
			for _, definition in ipairs(QuestCatalog.List()) do
				expect.toBe(QuestRules.IsDefinitionValid(definition), true)
			end
		end)

		Harness.it("toda mision tiene texto para el jugador", function()
			-- Una mision sin `Title` aparece como una fila vacia, que es
			-- contenido a medio hacer, no un error de codigo.
			for _, definition in ipairs(QuestCatalog.List()) do
				expect.toBe(type(definition.Title), "string")
				expect.toBe(#definition.Title > 0, true)
				expect.toBe(type(definition.Description), "string")
			end
		end)
---------------------------------------------------------
		-- TIPOS
		---------------------------------------------------------

		Harness.it("existen los tipos que el catalogo declara", function()
			-- Un tipo usado que no este en `QuestType` haria que el
			-- historial por tipo (`Completed`) se guardara bajo una clave
			-- que ninguna consulta lee.
			local declared = {}

			for _, questType in pairs(QuestCatalog.QuestType) do
				declared[questType] = true
			end

			for _, definition in ipairs(QuestCatalog.List()) do
				expect.toBe(declared[definition.Type], true)
			end
		end)

		Harness.it("hay misiones de mundo, logro y daily", function()
			-- Es el minimo de la spec 26/28: sin daily no hay oferta
			-- rotativa, y sin logros no hay sistema de logros internos.
			local world = QuestCatalog.GetByType(QuestCatalog.QuestType.World)
			local achievement = QuestCatalog.GetByType(QuestCatalog.QuestType.Achievement)
			local daily = QuestCatalog.GetDaily()

			local worldCount, achievementCount, dailyCount = 0, 0, 0

			for _ in pairs(world) do
				worldCount += 1
			end
			for _ in pairs(achievement) do
				achievementCount += 1
			end
			for _ in pairs(daily) do
				dailyCount += 1
			end

			expect.toBe(worldCount > 0, true)
			expect.toBe(achievementCount > 0, true)
			expect.toBe(dailyCount >= 3, true)
		end)

		---------------------------------------------------------
		-- CONSULTAS
		---------------------------------------------------------

		Harness.it("una mision se busca por su id normalizado", function()
			-- El camino que sigue el servidor: el id del catalogo, ya
			-- normalizado, tiene que devolver la definicion.
			for key, definition in pairs(QuestCatalog.GetAll()) do
				expect.toBe(QuestCatalog.Get(key), definition)
			end
		end)

		Harness.it("buscar una mision inexistente devuelve nil", function()
			expect.toBe(QuestCatalog.Get("no_existe"), nil)
			expect.toBe(QuestCatalog.Get(""), nil)
			expect.toBe(QuestCatalog.Get(nil), nil)
		end)

		Harness.it("la lista es estable y ordenada entre lecturas", function()
			-- Sin orden estable, la UI reordenaria las misiones en cada
			-- lectura y el jugador veria la lista saltando.
			local first = QuestCatalog.List()
			local second = QuestCatalog.List()

			expect.toBe(#first, #second)
			expect.toBe(#first > 0, true)

			for index, definition in ipairs(first) do
				expect.toBe(definition.Id, second[index].Id)
			end
		end)

		Harness.it("filtrar por tipo no incluye misiones de otros tipos", function()
			local daily = QuestCatalog.List(QuestCatalog.QuestType.Daily)

			expect.toBe(#daily > 0, true)

			for _, definition in ipairs(daily) do
				expect.toBe(definition.Type, QuestCatalog.QuestType.Daily)
			end
		end)

		Harness.it("un tipo inexistente devuelve una lista vacia, no un error", function()
			expect.toBe(#QuestCatalog.List("Weekend"), 0)
			local unknown = QuestCatalog.GetByType("Weekend")
			expect.toBe(type(unknown), "table")
		end)
---------------------------------------------------------
		-- PROGRESION REAL DESDE EL CATALOGO
		---------------------------------------------------------

		Harness.it("una mision del catalogo progresa y se reclama de verdad", function()
			-- Prueba de extremo a extremo sobre el catalogo REAL, no sobre
			-- una definicion inventada: es la unica forma de comprobar que
			-- el indice y la clave normalizada son el mismo camino.
			local definition = QuestCatalog.Get("WORLD_DESTROY_30")
			expect.toBe(type(definition), "table")

			local state = QuestRules.NewState(1)

			local progress = QuestRules.Advance(state, definition, 20, 0)
			expect.toBe(progress, 20)
			expect.toBe(QuestRules.IsComplete(state, "WORLD_DESTROY_30"), false)

			-- Incompleta: no se puede reclamar.
			expect.toBe(QuestRules.Claim(state, "WORLD_DESTROY_30", QuestCatalog.GetAll()), false)

			QuestRules.Advance(state, definition, 10, 0)
			expect.toBe(QuestRules.IsComplete(state, "WORLD_DESTROY_30"), true)

			local accepted, _, rewards = QuestRules.Claim(state, "WORLD_DESTROY_30", QuestCatalog.GetAll())
			expect.toBe(accepted, true)
			expect.toBe(rewards.Coins, definition.Rewards.Coins)

			-- Y el segundo reclamo no paga.
			expect.toBe(QuestRules.Claim(state, "WORLD_DESTROY_30", QuestCatalog.GetAll()), false)
		end)
	end)
end

return describeQuestCatalog