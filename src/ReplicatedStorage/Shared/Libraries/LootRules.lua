--!strict
--[[
	LootRules
	RECOMPENSAS DINAMICAS: drops de materiales por fuente (mision V2, FASE 23/25).

	POR QUE EXISTE
	--------------
	Hasta aqui casi todo pagaba monedas: secretos, misiones, kills y eventos
	iban al mismo bolsillo, y no habia NADA que desear en una tirada. Esta
	tabla da a cada fuente su propio botin:

	  - Monstruo normal:  material de SU mundo, a veces.
	  - Mini-boss:        material de su mundo, siempre; a veces doble.
	  - Boss:             materiales raros y una gema. El boss tiene que
	                      soltar algo que ningun slime puede soltar.

	QUE VIVE AQUI
	-------------
	La tabla y la tirada. `Roll` recibe los numeros aleatorios INYECTADOS
	(como `EventRules.Roll`): la distribucion entera se puede recorrer en
	pruebas sin depender de que el azar coopere. El servicio (`LootService`)
	aporta el `math.random` y la entrega al inventario.

	LA REGLA ANTI-DUPLICACION
	-------------------------
	La tirada no conoce al jugador: devuelve QUE cae. Quien lo entrega es
	`InventoryService.AddItem`, con su ledger y su tope de stack. Nada aqui
	puede crear items de la nada por otro camino.
]]

local Rules = {}

-- ---------------------------------------------------------------------------
-- MATERIAL POR MUNDO
-- ---------------------------------------------------------------------------
--
-- El material que suelta una criatura es el de SU mundo: farmear esencias
-- de hoja obliga a ir al bosque, y eso es lo que hace que un mundo
-- completado siga teniendo una razon para volver.

Rules.MaterialForWorld = {
	Forest = "Mat_LeafEssence",
	Desert = "Mat_SandCrystal",
	Ice = "Mat_FrostShard",
	Volcano = "Mat_EmberCore",
	Cyber = "Mat_CircuitChip",
}

-- ---------------------------------------------------------------------------
-- TABLA DE DROPS
-- ---------------------------------------------------------------------------
--
-- `Chance` es la probabilidad de que CAIGA algo. El resto es cuanto y de
-- que rareza se siente.

Rules.Monster = {
	-- Un kill normal suelta material el 15 % de las veces. Menos seria
	-- invisible; mas lo convertiria en la recompensa real y la moneda en
	-- decoracion.
	Chance = 0.15,
	MinAmount = 1,
	MaxAmount = 2,
}

Rules.MiniBoss = {
	-- El mini-boss SIEMPRE suelta: es la promesa de "este bicho vale la
	-- pena". La cantidad sube con el tier.
	BaseAmount = 2,
	-- Probabilidad de tirada DOBLE (el "drop gordo" del mini-boss).
	DoubleChance = 0.25,
}

Rules.Boss = {
	-- El boss suelta siempre, y raro: es el unico camino FIABLE de
	-- conseguir los materiales raros del mundo.
	Amount = 4,
	-- Y una gema: la unica fuente GRATUITA de gemas del juego hasta ahora
	-- eran los eventos raros; el boss se suma como fuente de habilidad,
	-- no de azar.
	Gems = 2,
}

-- ---------------------------------------------------------------------------
-- TIRADAS (puras: el azar llega inyectado)
-- ---------------------------------------------------------------------------

--- Drop de un monstruo normal.
--- @param worldId any
--- @param roll number 0..1 tirada de "cae o no cae"
--- @param amountRoll number 0..1 tirada de cantidad
--- @return string? itemId
--- @return number amount
function Rules.RollMonsterDrop(worldId: any, roll: any, amountRoll: any): (string?, number)
	local itemId = Rules.MaterialForWorld[worldId]

	if not itemId then
		return nil, 0
	end

	local r = tonumber(roll)

	if not r or r ~= r or r >= Rules.Monster.Chance then
		return nil, 0
	end

	local span = Rules.Monster.MaxAmount - Rules.Monster.MinAmount + 1
	local amount = Rules.Monster.MinAmount
		+ math.floor(math.clamp(tonumber(amountRoll) or 0, 0, 0.999999) * span)

	return itemId, amount
end

--- Drop de un mini-boss: siempre, y a veces doble.
--- @param worldId any
--- @param doubleRoll number 0..1
--- @return string? itemId
--- @return number amount
function Rules.RollMiniBossDrop(worldId: any, doubleRoll: any): (string?, number)
	local itemId = Rules.MaterialForWorld[worldId]

	if not itemId then
		return nil, 0
	end

	local amount = Rules.MiniBoss.BaseAmount
	local r = tonumber(doubleRoll)

	if r and r == r and r < Rules.MiniBoss.DoubleChance then
		amount *= 2
	end

	return itemId, amount
end

--- Drop de un boss: fijo y raro. No hay tirada: matar al boss SIEMPRE
--- tiene que sentirse a premio gordo.
--- @param worldId any
--- @return string? itemId
--- @return number amount
--- @return number gems
function Rules.RollBossDrop(worldId: any): (string?, number, number)
	local itemId = Rules.MaterialForWorld[worldId]

	if not itemId then
		return nil, 0, Rules.Boss.Gems
	end

	return itemId, Rules.Boss.Amount, Rules.Boss.Gems
end

--- Lista de materiales que el juego puede soltar (diagnostico y pruebas).
--- @return { string }
function Rules.GetMaterialIds(): { string }
	local out = {}

	for _, itemId in pairs(Rules.MaterialForWorld) do
		table.insert(out, itemId)
	end

	table.sort(out)
	return out
end

return Rules
