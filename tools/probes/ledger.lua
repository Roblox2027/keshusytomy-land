-- Traza del ledger: que se concedio exactamente y por que motivo.
local Services = game.ServerScriptService.Services
local Players = game:GetService("Players")

local Economy = require(Services.EconomyService)
local Progression = require(Services.ProgressionService)

local player = Players:GetPlayers()[1]
if not player then
	return "SIN JUGADOR"
end

local out = {}
local history = Economy.GetTransactionHistory(player, 100)

table.insert(out, "monedas_totales=" .. tostring(Economy.GetBalance(player, "Coins")))
table.insert(out, "nivel=" .. tostring(Progression.GetLevel(player)))
table.insert(out, "--- LEDGER (mas reciente primero) ---")

for _, entry in ipairs(history) do
	table.insert(out, ("%s %s %d -> %d (%s / %s) [%s]"):format(
		entry.timestamp and os.date("%H:%M:%S", entry.timestamp) or "?",
		entry.currency,
		entry.balanceBefore,
		entry.balanceAfter,
		entry.Direction,
		entry.amount,
		tostring(entry.reason)
	))
end

return table.concat(out, "\n")