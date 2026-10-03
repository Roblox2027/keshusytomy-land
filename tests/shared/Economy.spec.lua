--!strict
--[[
	Economy.spec
	Pruebas de la economia de monedas y de su libro mayor (ledger).

	Por que estas pruebas atacan el codigo:
	Una economia server-authoritative se rompe por tres motivos, y los tres
	son silenciosos: el saldo se duplica, el saldo queda negativo, o una
	compra repetida se cobra dos veces. Nada de eso se ve mirando el
	codigo; solo se ve comprobando que NO ocurre.

	Alcance honesto:
	Estas pruebas cubren la ARITMETICA y las validaciones, que es logica
	 pura ejecutable sin motor. NO cubren:
	  - que el DataStore guarde de verdad (eso es `Data` / runtime)
	  - que un jugador real reciba la recompensa (eso es PLAY)
	Por eso son un requisito, no una certificacion de persistencia.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local EconomyRules = require("../../src/ReplicatedStorage/Shared/Libraries/EconomyRules")

-- Estado nuevo con saldo controlado.
local function stateWithCoins(balance)
	local state = EconomyRules.NewState(1)
	EconomyRules.AddCurrency(state, "Coins", balance, "saldo_inicial", "test")
	return state
end

return function()
	Harness.describe("Economy: validacion de entrada", function()
		Harness.it("acepta solo las monedas declaradas", function()
			expect.toBe(EconomyRules.IsValidCurrency("Coins"), true)
			expect.toBe(EconomyRules.IsValidCurrency("Gems"), true)
			expect.toBe(EconomyRules.IsValidCurrency("Bitcoin"), false)
			expect.toBe(EconomyRules.IsValidCurrency("coins"), false)
			expect.toBe(EconomyRules.IsValidCurrency(nil), false)
			expect.toBe(EconomyRules.IsValidCurrency(42), false)
		end)

		Harness.it("rechaza cero, negativos, NaN e infinito", function()
			local zero = EconomyRules.SanitizeAmount(0)
			expect.toBe(zero, nil)

			local negative = EconomyRules.SanitizeAmount(-5)
			expect.toBe(negative, nil)

			-- El caso clasico: NaN no es > 0 ni < 0, asi que un filtro
			-- ingenuo lo deja pasar.
			local nan = EconomyRules.SanitizeAmount(0 / 0)
			expect.toBe(nan, nil)

			local infinite = EconomyRules.SanitizeAmount(math.huge)
			expect.toBe(infinite, nil)

			local negativeInfinite = EconomyRules.SanitizeAmount(-math.huge)
			expect.toBe(negativeInfinite, nil)
		end)

		Harness.it("rechaza fracciones por debajo de 1", function()
			expect.toBe(EconomyRules.SanitizeAmount(0.4), nil)
			-- Un entero valido se conserva.
			expect.toBe(EconomyRules.SanitizeAmount(10), 10)
			expect.toBe(EconomyRules.SanitizeAmount(10.9), 10)
		end)

		Harness.it("una moneda invalida no modifica el saldo", function()
			local state = stateWithCoins(100)
			local ok = EconomyRules.AddCurrency(state, "Bitcoin", 50, "hack", "test")
			expect.toBe(ok, false)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 100)
		end)
	end)

	Harness.describe("Economy: conceder y retirar", function()
		Harness.it("anade y resta de verdad", function()
			local state = EconomyRules.NewState(1)

			local added = EconomyRules.AddCurrency(state, "Coins", 100, "prueba", "test")
			expect.toBe(added, true)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 100)

			local removed = EconomyRules.RemoveCurrency(state, "Coins", 30, "prueba", "test")
			expect.toBe(removed, true)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 70)
		end)

		Harness.it("no deja que el saldo sea negativo", function()
			local state = stateWithCoins(50)

			local ok = EconomyRules.RemoveCurrency(state, "Coins", 80, "gasto", "test")
			expect.toBe(ok, false)
			-- Lo que NO puede pasar: que el saldo cambie a -30.
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 50)
		end)

		Harness.it("permite gastar EXACTAMENTE el saldo", function()
			-- El borde importa: si `>=` fuera `>`, un jugador con el saldo
			-- exacto no podria gastar y la tienda pareceria rota.
			local state = stateWithCoins(50)
			local ok = EconomyRules.RemoveCurrency(state, "Coins", 50, "gasto", "test")
			expect.toBe(ok, true)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 0)
		end)

		Harness.it("CanAfford es una consulta, no un cobro", function()
			local state = stateWithCoins(50)
			expect.toBe(EconomyRules.CanAfford(state, "Coins", 50), true)
			expect.toBe(EconomyRules.CanAfford(state, "Coins", 51), false)
			-- Preguntar no descuenta: por eso vuelve a haber 50 y no 0.
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 50)
		end)

		Harness.it("capa el saldo en vez de desbordarlo", function()
			-- A mitad de camino hacia el tope: concede lo que cabe y descarta
			-- el resto. Perder la recompensa entera seria peor.
			local state = EconomyRules.NewState(1)
			EconomyRules.AddCurrency(state, "Coins", EconomyRules.MaxBalance - 100, "llenado", "test")

			local ok = EconomyRules.AddCurrency(state, "Coins", 500, "exceso", "test")
			expect.toBe(ok, true)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), EconomyRules.MaxBalance)
		end)

		Harness.it("ya en el tope no concede y no desborda", function()
			-- Con cero hueco no hay nada que capping: se rechaza. Lo que no
			-- puede pasar NUNCA es que el saldo pase de `MaxBalance`.
			local state = EconomyRules.NewState(1)
			EconomyRules.AddCurrency(state, "Coins", EconomyRules.MaxBalance, "llenado", "test")

			local ok = EconomyRules.AddCurrency(state, "Coins", 1000, "mas", "test")
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), EconomyRules.MaxBalance)
			expect.toBe(EconomyRules.GetBalance(state, "Coins") <= EconomyRules.MaxBalance, true)
		end)
	end)

	Harness.describe("Economy: libro mayor (ledger)", function()
		Harness.it("cada movimiento deja una entrada completa", function()
			local state = stateWithCoins(100)
			EconomyRules.RemoveCurrency(state, "Coins", 40, "compra", "shop", { itemId = "Hat_Keshusy" })

			local history = EconomyRules.GetTransactionHistory(state)
			local latest = history[1]

			expect.toBe(latest.currency, "Coins")
			expect.toBe(latest.amount, 40)
			expect.toBe(latest.Direction, "Remove")
			expect.toBe(latest.balanceBefore, 100)
			expect.toBe(latest.balanceAfter, 60)
			expect.toBe(latest.reason, "compra")
			expect.toBe(latest.source, "shop")
			expect.toBe(latest.transactionId ~= nil, true)
			expect.toBe(type(latest.timestamp), "number")
		end)

		Harness.it("el ledger encadena: before = after anterior", function()
			-- Si esto falla, alguien escribio en el saldo por fuera de la
			-- economia y el ledger ya no sirve para nada.
			local state = EconomyRules.NewState(1)
			EconomyRules.AddCurrency(state, "Coins", 100, "a", "test")
			EconomyRules.RemoveCurrency(state, "Coins", 30, "b", "test")
			EconomyRules.AddCurrency(state, "Coins", 10, "c", "test")

			expect.toBe(#EconomyRules.Audit(state), 0)
		end)

		Harness.it("devuelve el historial del mas reciente al mas antiguo", function()
			local state = EconomyRules.NewState(1)
			EconomyRules.AddCurrency(state, "Coins", 10, "primera", "test")
			EconomyRules.AddCurrency(state, "Coins", 20, "segunda", "test")

			local history = EconomyRules.GetTransactionHistory(state)
			expect.toBe(history[1].reason, "segunda")
			expect.toBe(history[2].reason, "primera")
		end)

		Harness.it("el historial respeta el limite pedido", function()
			local state = EconomyRules.NewState(1)
			for index = 1, 10 do
				EconomyRules.AddCurrency(state, "Coins", 1, ("m" .. index), "test")
			end

			expect.toBe(#EconomyRules.GetTransactionHistory(state, 3), 3)
			expect.toBe(#EconomyRules.GetTransactionHistory(state, 100), 10)
		end)
	end)

	Harness.describe("Economy: idempotencia (el fallo mas caro)", function()
		Harness.it("la misma peticion NO cobra dos veces", function()
			-- Este es el defecto que mas dinero cuesta: si el cliente
			-- reintenta la compra, el jugador paga dos veces.
			local state = stateWithCoins(100)

			local first = EconomyRules.RemoveCurrency(state, "Coins", 30, "compra", "shop", nil, "req-1")
			local second = EconomyRules.RemoveCurrency(state, "Coins", 30, "compra", "shop", nil, "req-1")

			expect.toBe(first, true)
			expect.toBe(second, true)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 70)
			expect.toBe(EconomyRules.GetTransactionCount(state), 2)
		end)

		Harness.it("la peticion repetida devuelve el MISMO resultado", function()
			local state = stateWithCoins(100)
			local _, firstTransaction = EconomyRules.RemoveCurrency(state, "Coins", 30, "compra", "shop", nil, "req-2")
			local _, secondTransaction = EconomyRules.RemoveCurrency(state, "Coins", 30, "compra", "shop", nil, "req-2")

			expect.toBe(secondTransaction.transactionId, firstTransaction.transactionId)
		end)

		Harness.it("una recompensa duplicada NO duplica monedas", function()
			local state = stateWithCoins(0)

			EconomyRules.Grant(state, "Coins", 25, "recompensa_ronda", "round", nil, "round-7")
			EconomyRules.Grant(state, "Coins", 25, "recompensa_ronda", "round", nil, "round-7")

			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 25)
		end)

		Harness.it("peticiones DISTINTAS si se cobran dos veces", function()
			-- El control anterior no puede ser "cobra siempre una vez".
			local state = stateWithCoins(100)
			EconomyRules.RemoveCurrency(state, "Coins", 10, "compra", "shop", nil, "req-a")
			EconomyRules.RemoveCurrency(state, "Coins", 10, "compra", "shop", nil, "req-b")
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 80)
		end)
	end)

	Harness.describe("Economy: auditoria", function()
		Harness.it("una economia sana no reporta anomalias", function()
			local state = EconomyRules.NewState(1)
			EconomyRules.AddCurrency(state, "Coins", 500, "inicial", "test")
			EconomyRules.RemoveCurrency(state, "Coins", 120, "tienda", "shop")
			expect.toBe(#EconomyRules.Audit(state), 0)
		end)

		Harness.it("detecta un saldo negativo escrito por fuera", function()
			-- Se escribe a mano, saltandose la economia: es exactamente lo
			-- que haria un perfil inyectado o un bug.
			local state = stateWithCoins(50)
			state.Balances.Coins = -10

			expect.toBe(#EconomyRules.Audit(state) > 0, true)
		end)

		Harness.it("detecta un saldo que no encadena con el ledger", function()
			local state = stateWithCoins(100)
			EconomyRules.RemoveCurrency(state, "Coins", 30, "tienda", "shop")
			-- Alguien gasto 30 mas sin pasar por la economia.
			state.Balances.Coins = 10

			expect.toBe(#EconomyRules.FindBalanceMismatch(state) > 0, true)
		end)

		Harness.it("detecta un NaN en el saldo", function()
			local state = stateWithCoins(50)
			state.Balances.Gems = 0 / 0
			expect.toBe(#EconomyRules.FindNegativeBalances(state) > 0, true)
		end)
	end)

	Harness.describe("Economy: transferencias", function()
		Harness.it("mueve saldo entre dos jugadores", function()
			local from = stateWithCoins(100)
			local to = EconomyRules.NewState(2)

			local ok = EconomyRules.Transfer(from, to, "Coins", 30, "regalo", "social")
			expect.toBe(ok, true)
			expect.toBe(EconomyRules.GetBalance(from, "Coins"), 70)
			expect.toBe(EconomyRules.GetBalance(to, "Coins"), 30)
		end)

		Harness.it("no mueve nada si el origen no puede pagar", function()
			local from = stateWithCoins(10)
			local to = EconomyRules.NewState(2)

			local ok = EconomyRules.Transfer(from, to, "Coins", 50, "regalo", "social")
			expect.toBe(ok, false)
			-- Lo que importa: no se creo saldo en el destino.
			expect.toBe(EconomyRules.GetBalance(from, "Coins"), 10)
			expect.toBe(EconomyRules.GetBalance(to, "Coins"), 0)
		end)

		Harness.it("rechacia transferir a uno mismo", function()
			local state = stateWithCoins(100)
			local ok = EconomyRules.Transfer(state, state, "Coins", 30, "regalo", "social")
			expect.toBe(ok, false)
			expect.toBe(EconomyRules.GetBalance(state, "Coins"), 100)
		end)

		Harness.it("el reintento de una transferencia no cobra dos veces", function()
			local from = stateWithCoins(100)
			local to = EconomyRules.NewState(2)

			EconomyRules.Transfer(from, to, "Coins", 30, "regalo", "social", "gift-1")
			EconomyRules.Transfer(from, to, "Coins", 30, "regalo", "social", "gift-1")

			expect.toBe(EconomyRules.GetBalance(from, "Coins"), 70)
			expect.toBe(EconomyRules.GetBalance(to, "Coins"), 30)
		end)
	end)
end