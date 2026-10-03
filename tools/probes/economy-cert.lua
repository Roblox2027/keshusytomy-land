-- Probe de certificacion de la columna economica en el servidor REAL.
--
-- POR QUE ES UN PROBE Y NO UN TEST
-- -------------------------------
-- La suite de `tests/` corre con `luau.exe`, sin motor: comprueba la
-- ARITMETICA. Esto comprueba lo que la aritmetica no puede: que un
-- jugador de verdad tenga perfil, que la economia este conectada al
-- perfil, y que una compra recorra la cadena entera.
--
-- NO modifica el balance ni da recompensas massive: concede 1.000 coins
-- para poder probar la tienda y los registra con un `requestId` propio, de
-- modo que la prueba sea repetible y no contamine el ledger como una
-- recompensa real.
local Services = game.ServerScriptService.Services
local Players = game:GetService("Players")

local Economy = require(Services.EconomyService)
local Inventory = require(Services.InventoryService)
local Progression = require(Services.ProgressionService)
local Profile = require(Services.ProfileService)
local Shop = require(Services.ShopService)

local player = Players:GetPlayers()[1]
if not player then
	return "SIN JUGADOR"
end

local out = {}
local function say(line)
	table.insert(out, line)
end

say("jugador=" .. player.Name .. " userId=" .. tostring(player.UserId))
say("perfil_cargado=" .. tostring(Profile.HasProfile(player)))

-- --- 1. Estado inicial -------------------------------------------------
say("nivel=" .. tostring(Progression.GetLevel(player)))
say("xp=" .. tostring(Progression.GetXP(player)))
say("coins=" .. tostring(Economy.GetBalance(player, "Coins")))
say("gems=" .. tostring(Economy.GetBalance(player, "Gems")))
say("items=" .. tostring(#Shop.GetOwnedItems(player)))

-- --- 2. Conceder saldo y comprobar que el perfil lo refleja -----------
local granted = Economy.GrantCurrency(player, "Coins", 1000, "probe_certificacion", "probe", nil, "probe-grant-1")
say("grant_ok=" .. tostring(granted))
say("coins_tras_grant=" .. tostring(Economy.GetBalance(player, "Coins")))
say("atributo_coins=" .. tostring(player:GetAttribute("Coins")))

-- --- 3. IDEMPOTENCIA de la recompensa -------------------------------
local duplicate = Economy.GrantCurrency(player, "Coins", 1000, "probe_certificacion", "probe", nil, "probe-grant-1")
say("grant_repetido_ok=" .. tostring(duplicate))
say("coins_tras_repetido=" .. tostring(Economy.GetBalance(player, "Coins")))

-- --- 4. Compra real en la tienda -------------------------------------
local catalogSize = #Shop.GetCatalog()
say("catalogo_items=" .. tostring(catalogSize))

local outcome, rejection, receipt = Shop.Purchase(player, "Hat_Keshusy", "probe-purchase-1")
say("compra_outcome=" .. tostring(outcome))
say("compra_rechazo=" .. tostring(rejection))
if receipt then
	say("compra_precio=" .. tostring(receipt.price))
	say("compra_moneda=" .. tostring(receipt.currency))
end
say("coins_tras_compra=" .. tostring(Economy.GetBalance(player, "Coins")))
say("items_tras_compra=" .. tostring(#Shop.GetOwnedItems(player)))
say("posee_sombrero=" .. tostring(Inventory.HasItem(player, "Hat_Keshusy")))

-- --- 5. Reintento de la MISMA compra (id distinto, mismo item) --------
local second, secondRejection = Shop.Purchase(player, "Hat_Keshusy", "probe-purchase-2")
say("segunda_compra_outcome=" .. tostring(second))
say("segunda_compra_rechazo=" .. tostring(secondRejection))
say("coins_tras_segunda=" .. tostring(Economy.GetBalance(player, "Coins")))

-- --- 6. Intento de equipar un item que NO se posee -------------------
local equipGhost = Inventory.EquipItem(player, "Cape_Flame")
say("equipar_no_poseido_ok=" .. tostring(equipGhost))

-- --- 7. Intento de usar un item inexistente --------------------------
local useGhost, _, useReason = Inventory.UseItem(player, "Item_Inventado_XYZ")
say("usar_inexistente_ok=" .. tostring(useGhost))
say("usar_inexistente_motivo=" .. tostring(useReason))

-- --- 8. Equipar lo que SI tiene --------------------------------------
local equipReal = Inventory.EquipItem(player, "Hat_Keshusy")
say("equipar_ok=" .. tostring(equipReal))
say("equipado_head=" .. tostring((Inventory.GetEquipped(player) or {}).Head))

-- --- 9. XP y subida de nivel -----------------------------------------
local before = Progression.GetLevel(player)
local okXp, xpResult = Progression.AddXP(player, 500, "probe")
say("xp_ok=" .. tostring(okXp))
if xpResult then
	say("niveles_ganados=" .. tostring(xpResult.levelsGained))
end
say("nivel_antes=" .. tostring(before) .. " nivel_despues=" .. tostring(Progression.GetLevel(player)))
say("coins_tras_subir=" .. tostring(Economy.GetBalance(player, "Coins")))

-- --- 10. Auditorias: deben salir vacias ------------------------------
say("auditoria_economia=" .. tostring(#Economy.AuditPlayer(player)))
say("auditoria_inventario=" .. tostring(#Inventory.AuditPlayer(player)))
say("auditoria_progresion=" .. tostring(#Progression.AuditPlayer(player)))

return table.concat(out, "\n")