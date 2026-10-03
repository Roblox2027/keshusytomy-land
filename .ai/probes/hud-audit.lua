-- hud-audit.lua (servidor): no ve la GUI del cliente. Solo publica el estado de
-- los ATRIBUTOS que el HUD refleja, para separar "el servidor no publica" de
-- "el HUD no pinta".
local Players = game:GetService("Players")
local out = {}
local p = Players:GetPlayers()[1]
if not p then return "no hay jugador" end
local watch = {
	"World", "Level", "XP", "Coins", "Gems", "Bombs", "CoreState", "CoreCharge",
	"RoundState", "RoundNumber", "RoundTimeRemaining", "AliveCount",
	"QuestCount", "QuestStreak", "QuestCompleted", "BossName",
	"InventoryCount", "EquippedCount",
}
for _, k in ipairs(watch) do
	local v = p:GetAttribute(k)
	if v ~= nil then out[#out+1] = k .. " = " .. tostring(v) end
end
table.sort(out)
return table.concat(out, "\n")