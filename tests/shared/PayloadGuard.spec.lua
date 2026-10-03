--!strict
--[[
	PayloadGuard.spec
	Pruebas del saneamiento de payloads remotos.

	Cada prueba es un VECTOR DE ATAQUE real de la auditoria de seguridad:
	NaN, infinito, negativo, enorme, tipo equivocado, cadena gigante,
	tabla ciclica, profundidad, clave desconocida y aridad incorrecta.

	La regla que se verifica en TODAS: un rechazo NO devuelve un valor
	sanitizado. Devuelve `nil`/`false`. Si alguna vez devolviera un numero
	"arreglado", el servidor estaria inventando una cantidad que el cliente
	pidio, que es exactamente el exploit que se quiere cerrar.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Guard = require("../../src/ReplicatedStorage/Shared/Libraries/PayloadGuard")

local function describePayloadGuard()
	Harness.describe("PayloadGuard", function()
		---------------------------------------------------------
		-- FINITOS
		---------------------------------------------------------

		Harness.it("acepta numeros finitos normales", function()
			expect.toBe(Guard.IsFiniteNumber(0), true)
			expect.toBe(Guard.IsFiniteNumber(1), true)
			expect.toBe(Guard.IsFiniteNumber(-42.5), true)
			expect.toBe(Guard.IsFiniteNumber(1e15), true)
		end)

		Harness.it("rechaza NaN", function()
			-- 0/0 en Luau da NaN, que NO es igual a si mismo.
			local nan = 0 / 0
			expect.toBe(Guard.IsFiniteNumber(nan), false)
			expect.toBe(Guard.CoerceNumber(nan, 0, 100), nil)
		end)

		Harness.it("rechaza infinito positivo y negativo", function()
			expect.toBe(Guard.IsFiniteNumber(math.huge), false)
			expect.toBe(Guard.IsFiniteNumber(-math.huge), false)
			expect.toBe(Guard.CoerceNumber(math.huge, 0, 100), nil)
			expect.toBe(Guard.CoerceNumber(-math.huge, 0, 100), nil)
		end)

		Harness.it("rechaza valores que no son numero", function()
			expect.toBe(Guard.IsFiniteNumber("10"), false)
			expect.toBe(Guard.IsFiniteNumber(nil), false)
			expect.toBe(Guard.IsFiniteNumber(true), false)
			expect.toBe(Guard.IsFiniteNumber({}), false)
			expect.toBe(Guard.IsFiniteNumber(print), false)
		end)

		Harness.it("CoerceNumber respeta las cotas", function()
			expect.toBe(Guard.CoerceNumber(5, 1, 10), 5)
			-- 0 esta en el borde inferior declarado: fuera.
			expect.toBe(Guard.CoerceNumber(0, 1, 10), nil)
			expect.toBe(Guard.CoerceNumber(11, 1, 10), nil)
			expect.toBe(Guard.CoerceNumber(-1, 0, 10), nil)
			expect.toBe(Guard.CoerceNumber(1e18, 0, 100), nil)
		end)

		Harness.it("CoerceNumber sin cotas solo exige finito", function()
			expect.toBe(Guard.CoerceNumber(-9999), -9999)
			expect.toBe(Guard.CoerceNumber(1e30), 1e30)
		end)

		---------------------------------------------------------
		-- Identificadores
		---------------------------------------------------------

		Harness.it("acepta identificadores normales", function()
			expect.toBe(Guard.IsIdentifier("Bomb"), true)
			expect.toBe(Guard.IsIdentifier("Forest"), true)
			expect.toBe(Guard.IsIdentifier("KESHUSY2026"), true)
		end)

		Harness.it("rechaza identificadores vacios o de tipo erroneo", function()
			expect.toBe(Guard.IsIdentifier(""), false)
			expect.toBe(Guard.IsIdentifier(nil), false)
			expect.toBe(Guard.IsIdentifier(5), false)
			expect.toBe(Guard.IsIdentifier({}), false)
		end)

		Harness.it("rechaza cadenas gigantes", function()
			local huge = string.rep("A", 5000)
			local ok, reason = Guard.IsIdentifier(huge)

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.StringTooLong)
		end)

		Harness.it("rechaza codigos de control en identificadores", function()
			-- Un salto de linea permitiria escribir una linea falsa en el log.
			local ok, reason = Guard.IsIdentifier("Bomb\nAdmin")

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.WrongType)
		end)

		Harness.it("IsShortText admite espacios pero no controles", function()
			expect.toBe(Guard.IsShortText("Nivel insuficiente"), true)
			expect.toBe(Guard.IsShortText(""), true)
			expect.toBe(Guard.IsShortText("a\nb"), false)
			expect.toBe(Guard.IsShortText(7), false)
		end)

		---------------------------------------------------------
		-- Forma de tabla
		---------------------------------------------------------

		Harness.it("acepta tablas planas normales", function()
			expect.toBe(Guard.ValidateTableShape({ ItemId = "Bomb", Amount = 1 }), true)
			expect.toBe(Guard.ValidateTableShape({}), true)
		end)

		Harness.it("rechaza tablas ciclicas sin colgarse", function()
			local cyclic = { Name = "x" }
			cyclic.Self = cyclic

			local ok, reason = Guard.ValidateTableShape(cyclic)

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.TooDeep)
		end)

		Harness.it("rechaza tablas demasiado profundas", function()
			local deep = { a = { b = { c = { d = { e = { f = 1 } } } } } }
			local ok, reason = Guard.ValidateTableShape(deep, 2)

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.TooDeep)
		end)

		Harness.it("rechaza tablas con demasiadas claves", function()
			local wide = {}

			for i = 1, 500 do
				wide["k" .. tostring(i)] = i
			end

			local ok, reason = Guard.ValidateTableShape(wide)

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.TooManyKeys)
		end)

		Harness.it("rechaza valores que son funciones", function()
			local ok, reason = Guard.ValidateTableShape({ Run = print })

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.WrongType)
		end)

		Harness.it("rechaza claves que no son string ni numero", function()
			local payload = {}
			payload[print] = "clave funcion"

			local ok, reason = Guard.ValidateTableShape(payload)

			expect.toBe(ok, false)
			expect.toBe(reason, Guard.Reason.WrongType)
		end)

		Harness.it("no confunde dos tablas gemelas con un ciclo", function()
			-- Dos tablas con el MISMO contenido no son la misma tabla: un
			-- `seen` mal implementado (que nunca se limpia) rechazaria esto
			-- en la segunda llamada y el sistema fallaria al reusar un item.
			local shared = { Amount = 1 }
			expect.toBe(Guard.ValidateTableShape({ a = shared, b = shared }), true)
			expect.toBe(Guard.ValidateTableShape({ a = shared, b = shared }), true)
		end)

		---------------------------------------------------------
		-- Extraccion de campos
		---------------------------------------------------------

		Harness.it("extrae un identificador valido", function()
			local ok, value = Guard.GetIdentifierField({ ItemId = "Bomb" }, "ItemId")

			expect.toBe(ok, true)
			expect.toBe(value, "Bomb")
		end)

		Harness.it("distingue payload ausente de campo ausente", function()
			local okA, _, reasonA = Guard.GetIdentifierField("no soy tabla", "ItemId")
			expect.toBe(okA, false)
			expect.toBe(reasonA, Guard.Reason.NotATable)

			local okB, _, reasonB = Guard.GetIdentifierField({}, "ItemId")
			expect.toBe(okB, false)
			expect.toBe(reasonB, Guard.Reason.UnknownField)
		end)

		Harness.it("extrae un numero acotado valido", function()
			local ok, value = Guard.GetBoundedNumberField({ Amount = 3 }, "Amount", 1, 10)

			expect.toBe(ok, true)
			expect.toBe(value, 3)
		end)

		Harness.it("distingue no-finito de fuera-de-rango en numeros", function()
			local okA, _, reasonA = Guard.GetBoundedNumberField({ Amount = 0 / 0 }, "Amount", 1, 10)
			expect.toBe(okA, false)
			expect.toBe(reasonA, Guard.Reason.NotFinite)

			local okB, _, reasonB = Guard.GetBoundedNumberField({ Amount = 999 }, "Amount", 1, 10)
			expect.toBe(okB, false)
			expect.toBe(reasonB, Guard.Reason.TooLarge)
		end)

		Harness.it("un numero negativo de cantidad se rechaza", function()
			-- El ataque clasico de economia: Amount = -1 para GENERAR saldo.
			local ok, value = Guard.GetBoundedNumberField({ Amount = -1 }, "Amount", 1, 10)

			expect.toBe(ok, false)
			expect.toBe(value, nil)
		end)

		---------------------------------------------------------
		-- Lista blanca y aridad
		---------------------------------------------------------

		Harness.it("acepta solo las claves permitidas", function()
			local allowed = { ItemId = true }

			expect.toBe(Guard.RejectUnknownFields({ ItemId = "Bomb" }, allowed), true)

			local ok, offending = Guard.RejectUnknownFields({ ItemId = "Bomb", Admin = true }, allowed)
			expect.toBe(ok, false)
			expect.toBe(offending, "Admin")
		end)

		Harness.it("un payload que no es tabla no rompe la lista blanca", function()
			expect.toBe(Guard.RejectUnknownFields("texto", { ItemId = true }), true)
			expect.toBe(Guard.RejectUnknownFields(nil, { ItemId = true }), true)
		end)

		Harness.it("valida la aridad exacta de argumentos", function()
			expect.toBe(Guard.ValidateArity(1, 1), true)
			-- Argumento de mas y de menos: ambos rechazados.
			expect.toBe(Guard.ValidateArity(2, 1), false)
			expect.toBe(Guard.ValidateArity(0, 1), false)
			expect.toBe(Guard.ValidateArity(0, 0), true)
		end)
	end)
end

return describePayloadGuard