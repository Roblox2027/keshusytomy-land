-- code-double-grant.lua
-- Comprueba en el RUNTIME REAL la garantia central del canje de codigos:
-- el mismo codigo nunca se paga dos veces.
--
-- Hace `require` del ModuleScript que Studio tiene cargado. No lee el
-- repositorio: si el modulo no estuviera desplegado, lo dice.
local out = {}
local function line(s) out[#out + 1] = tostring(s) end

local libs = game:GetService("ReplicatedStorage").Shared.Libraries
local module = libs:FindFirstChild("CodeRules")

if not module then
	return "FALLO: CodeRules no existe en el runtime de Studio."
end

local ok, Rules = pcall(require, module)

if not ok or type(Rules) ~= "table" then
	return "FALLO: no se pudo cargar CodeRules: " .. tostring(Rules)
end

line("CodeRules cargado desde el runtime real.")

local passed, failed = 0, 0
local function check(name, got, want)
	local good = (got == want)
	passed += if good then 1 else 0
	failed += if good then 0 else 1
	line((good and "  PASA  " or "  FALLA ") .. name .. "  -> " .. tostring(got))
end

local definitions = {
	keshusy2026 = {
		Code = "KESHUSY2026",
		Rewards = { Coins = 100, Gems = 5 },
		MaxRedemptions = 3,
	},
}

-- El estado del perfil y el contador global son objetos DISTINTOS: asi es
-- como los usa el servicio y como los separo las pruebas.
local function newProfile()
	return { Redemptions = {}, RedemptionCounts = {} }
end

local global = { RedeemedCodes = {} }

-- 1. Primer canje: concede.
local profile = newProfile()
local accepted, _, rewards = Rules.Redeem(profile, global, 555, "KESHUSY2026", 0, definitions)
check("primer canje aceptado", accepted, true)
check("recompensa de monedas", rewards and rewards.Coins, 100)
check("recompensa de gemas", rewards and rewards.Gems, 5)

-- 2. El MISMO jugador repite 50 veces: una sola recompensa.
local granted = 1
for _ = 1, 50 do
	local okAgain, _, reward = Rules.Redeem(profile, global, 555, "KESHUSY2026", 0, definitions)
	if okAgain and reward then
		granted += 1
	end
end
check("50 repeticiones conceden una sola vez mas", granted, 1)
check("contador global tras repetir", global.RedeemedCodes.keshusy2026, 1)

-- 3. Variantes de escritura del mismo codigo.
local _, variantReason = Rules.Redeem(profile, global, 555, " keshusy-2026 ", 0, definitions)
check("variante de escritura rechazada", variantReason, "already_used")

-- 4. Otros jugadores hasta agotar el limite global (3 usos).
check("segundo jugador", Rules.Redeem(newProfile(), global, 556, "KESHUSY2026", 0, definitions), true)
check("tercer jugador", Rules.Redeem(newProfile(), global, 557, "KESHUSY2026", 0, definitions), true)

local fourth, exhausted = Rules.Redeem(newProfile(), global, 558, "KESHUSY2026", 0, definitions)
check("cuarto jugador rechazado", fourth, false)
check("motivo: agotado", exhausted, "exhausted")
check("contador global final", global.RedeemedCodes.keshusy2026, 3)

-- 5. Un codigo que el jugador NO ha usado da un motivo DISTINTO al de
--    "agotado": el diagnostico correcto importa para la UX.
local fresh, unknown = Rules.Redeem(newProfile(), global, 999, "NOEXISTE", 0, definitions)
check("codigo inexistente rechazado", fresh, false)
check("motivo: desconocido", unknown, "unknown")

-- 6. Caducado.
local expiring = {
	expirado = { Code = "EXPIRADO", Rewards = { Coins = 10 }, ExpiresAt = 100 },
}
local g = { RedeemedCodes = {} }
local _, expiredReason = Rules.Redeem(newProfile(), g, 1, "EXPIRADO", 500, expiring)
check("codigo caducado rechazado", expiredReason, "expired")

line(("\nRESUMEN: %d pasaron, %d fallaron"):format(passed, failed))
return table.concat(out, "\n")