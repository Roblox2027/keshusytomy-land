--!strict
--[[
	RemoteSchema.spec
	Pruebas de validacion de entradas NO CONFIABLES.

	Este archivo es la primera linea de defensa anti-exploit: define
	que formas de payload acepta el servidor. Las pruebas atacan el
	esquema como lo haria un cliente hostil.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local RemoteSchemaLib = require("../../src/ReplicatedStorage/Shared/Libraries/RemoteSchema")
local GameConstants = require("../../src/ReplicatedStorage/Shared/Constants/GameConstants")

-- El esquema se construye inyectando el mapa de canales.
local RemoteSchema = RemoteSchemaLib.new(GameConstants.RemoteAction)
local PayloadType = RemoteSchemaLib.PayloadType
local BombChannel = GameConstants.RemoteAction.Bomb
local PartyChannel = GameConstants.RemoteAction.Party

local function describeRemoteSchema()
	Harness.describe("RemoteSchema", function()
		Harness.it("todo canal declarado tiene al menos una accion", function()
			local actions = RemoteSchema:GetActions(BombChannel)
			expect.toBe(next(actions) ~= nil, true)
		end)

		Harness.it("reconoce canales validos e invalidos", function()
			expect.toBe(RemoteSchema:HasChannel(BombChannel), true)
			expect.toBe(RemoteSchema:HasChannel("CanalInexistente"), false)
		end)

		Harness.it("reconoce acciones permitidas y no permitidas", function()
			expect.toBe(RemoteSchema:HasAction(BombChannel, "Place"), true)
			-- Accion no declarada: un cliente no puede inventarla.
			expect.toBe(RemoteSchema:HasAction(BombChannel, "Explode"), false)
		end)

		Harness.it("rechaza payload en una accion que no admite datos", function()
			local valid = RemoteSchemaLib.ValidatePayload(PayloadType.None, nil)
			expect.toBe(valid, true)

			local invalid, reason = RemoteSchemaLib.ValidatePayload(PayloadType.None, "dato")
			expect.toBe(invalid, false)
			expect.toContain(tostring(reason), "no se esperaba payload")
		end)

		Harness.it("exige booleanos reales", function()
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Boolean, true)), true)
			-- "true" como texto es el truco clasico.
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Boolean, "true")), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Boolean, 1)), false)
		end)

		Harness.it("rechaza numeros no finitos y NaN", function()
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Number, 10)), true)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Number, 0 / 0)), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Number, math.huge)), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Number, -math.huge)), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Number, "10")), false)
		end)

		Harness.it("rechaza cadenas vacias, largas o con caracteres raros", function()
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, "Item_01")), true)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, "forest-fragment")), true)

			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, "")), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, string.rep("a", 65))), false)
			-- Inyeccion de codigo / saltos de linea.
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, "item\nprint(1)")), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, "item'; DROP --")), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.String, 42)), false)
		end)

		Harness.it("acepta posiciones normales y rechaza posiciones imposibles", function()
			-- El rango se valida sobre los componentes: asi la prueba
			-- es real incluso fuera del motor de Roblox.
			expect.toBe((RemoteSchemaLib.ValidateVectorComponents(10, 2, -4, 11)), true)
			expect.toBe((RemoteSchemaLib.ValidateVectorComponents(0, 0, 0, 0)), true)

			-- Teleport a 1e9 studs: intento de exploit.
			local farX, reasonFar = RemoteSchemaLib.ValidateVectorComponents(1e9, 0, 0, 1e9)
			expect.toBe(farX, false)
			expect.toContain(tostring(reasonFar), "rango")

			-- NaN rompe la fisica del servidor: se rechaza.
			local nanValid, reasonNan = RemoteSchemaLib.ValidateVectorComponents(0 / 0, 0, 0, 0)
			expect.toBe(nanValid, false)
			expect.toContain(tostring(reasonNan), "finito")

			-- Infinito tambien.
			expect.toBe((RemoteSchemaLib.ValidateVectorComponents(0, 0, 0, math.huge)), false)
		end)

		Harness.it("un Vector3 de tipo correcto pasa la forma", function()
			-- El tipo Vector3 solo existe en el motor de Roblox; fuera de
			-- el se comprueba que un valor NO-Vector3 se rechaza.
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Vector3, { 1, 2, 3 })), false)
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Vector3, "10,2,4")), false)
		end)

		Harness.it("rechaza tablas gigantes (DoS de memoria)", function()
			local small = {}
			expect.toBe((RemoteSchemaLib.ValidatePayload(PayloadType.Table, small)), true)

			local huge = {}
			for index = 1, 100 do
				huge[index] = index
			end
			local valid, reason = RemoteSchemaLib.ValidatePayload(PayloadType.Table, huge)
			expect.toBe(valid, false)
			expect.toContain(tostring(reason), "demasiado grande")
		end)

		Harness.it("rechaza un tipo de esquema desconocido", function()
			local valid = RemoteSchemaLib.ValidatePayload("Inventado", 1)
			expect.toBe(valid, false)
		end)

		Harness.it("GetPayloadType refleja el esquema", function()
			expect.toBe(RemoteSchema:GetPayloadType(BombChannel, "Place"), PayloadType.Vector3)
			expect.toBe(RemoteSchema:GetPayloadType(PartyChannel, "Invite"), PayloadType.Number)
			expect.toBe(RemoteSchema:GetPayloadType(BombChannel, "Inventada"), nil)
		end)
	end)
end

return describeRemoteSchema