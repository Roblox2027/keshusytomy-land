--!strict
--[[
	MiniBossRules
	MINI-BOSSES por mundo (FASE 15).

	LA DIFERENCIA CON UN BOSS
	------------------------
	Un mini-boss NO es un boss con menos vida. Un boss es el cierre de un mundo:
	uno solo, en su arena, con barra propia. Un mini-boss es contenido REPETIBLE:
	aparece varias veces por noche, en zonas distintas, y se puede volver a
	intentar.

	De ahi salen las tres diferencias de este modulo:

	  1. Tiene ENFRIAMIENTO. Sin el, un mini-boss con suficiente vida se queda
	     vivo y aparece cada pocos segundos: la zona deja de ser un lugar y pasa
	     a ser una sala de espera.
	  2. Es MENOR que un boss, para que el jugador sepa de un vistazo cual de
	     los dos tiene delante sin tener que leer la barra.
	  3. Su recompensa es MENOR que la del boss, por la misma razon: si pagara
	     igual, el jugador buscaria mini-bosses y evitaria el cierre del mundo,
     que es justo lo contrario de lo que el mundo debe proteger.

	NINGUNO REEMPLAZA AL BOSS PRINCIPAL
	----------------------------------
	Los ids de `MonsterDefinitions` (`ForestGrooty` y compañía) no aparecen en
	este archivo, y `Audit` lo comprueba. Es la garantia de que la expansion no
	ha desplazado el contenido ya certificado.
]]

local Rules = {}

Rules.Tier = {
	Common = "Common",
	Elite = "Elite",
	Rare = "Rare",
}

-- ---------------------------------------------------------------------------
-- CATALOGO
-- ---------------------------------------------------------------------------

Rules.ByWorld = {
	Forest = {
		-- Los `Zone` son IDS REALES de zona del generador
		-- (`tools/worlds.js`): `GetForZone` solo casa con el id
		-- que existe en el mapa. Antes decian "Hollow", "Grove" y
		-- "Rocks", que NO son zonas de Forest, y el mini-boss
		-- nunca aparecia porque la consulta no encontraba nada.
		{ Id = "ForestTronk", Name = "Tronco Guardián", Tier = Rules.Tier.Common, Zone = "BogHollow", Health = 320, Scale = 2.0 },
		{ Id = "ForestArana", Name = "Araña de Ramas", Tier = Rules.Tier.Elite, Zone = "DenseGrove", Health = 420, Scale = 2.1 },
		{ Id = "ForestAcechador", Name = "Acechador del Claro", Tier = Rules.Tier.Rare, Zone = "RockyRidge", Health = 560, Scale = 2.2 },
	},
	Desert = {
		{ Id = "DesertEscorpion", Name = "Escorpión de las Dunas", Tier = Rules.Tier.Common, Zone = "Oasis", Health = 380, Scale = 2.05 },
		{ Id = "DesertMomia", Name = "Momia del Templo", Tier = Rules.Tier.Elite, Zone = "Ruins", Health = 500, Scale = 2.2 },
		{ Id = "DesertColmillo", Name = "Colmillo de Arena", Tier = Rules.Tier.Rare, Zone = "Canyon", Health = 640, Scale = 2.3 },
	},
	Ice = {
		{ Id = "IceGolem", Name = "Gólem de Hielo", Tier = Rules.Tier.Common, Zone = "Lake", Health = 440, Scale = 2.15 },
		{ Id = "IceLobo", Name = "Lobo Glacial", Tier = Rules.Tier.Elite, Zone = "Narrows", Health = 520, Scale = 2.0 },
		{ Id = "IceSpecter", Name = "Espectro del Glaciar", Tier = Rules.Tier.Rare, Zone = "Crevasse", Health = 700, Scale = 2.25 },
	},
	Volcano = {
		{ Id = "VolcanoSlag", Name = "Escoria Ardiente", Tier = Rules.Tier.Common, Zone = "Vents", Health = 520, Scale = 2.1 },
		{ Id = "VolcanoAshen", Name = "Ashen", Tier = Rules.Tier.Elite, Zone = "Platforms", Health = 640, Scale = 2.2 },
		{ Id = "VolcanoObsidian", Name = "Guardián de Obsidiana", Tier = Rules.Tier.Rare, Zone = "Fissure", Health = 820, Scale = 2.4 },
	},
	Cyber = {
		{ Id = "CyberDrone", Name = "Dron Centinela", Tier = Rules.Tier.Common, Zone = "ServerHall", Health = 620, Scale = 2.1 },
		{ Id = "CyberEnforcer", Name = "Reforzer", Tier = Rules.Tier.Elite, Zone = "Conduit", Health = 760, Scale = 2.25 },
		{ Id = "CyberWarden", Name = "Warden del Reactor", Tier = Rules.Tier.Rare, Zone = "Reactor", Health = 980, Scale = 2.4 },
	},
}

--- Minibosses de un mundo.
--- @param worldId any
--- @return { any }
function Rules.GetForWorld(worldId: any): { any }
	if type(worldId) ~= "string" then
		return {}
	end

	-- Igual que en `EventRules.GetForWorld`: un mundo que no existe en el
	-- catalogo devuelve lista vacia. Un `worldId` inventado no puede fabricar
	-- mini-bosses.
	return Rules.ByWorld[worldId :: string] or {}
end

--- Un mini-boss por id.
--- @param id any
--- @return any?
function Rules.Get(id: any): any?
	if type(id) ~= "string" then
		return nil
	end

	for _, list in pairs(Rules.ByWorld) do
		for _, mini in ipairs(list) do
			if mini.Id == id then
				return mini
			end
		end
	end

	return nil
end

--- Un mini-boss por zona.
---
--- Es la consulta que usa el generador de spawns: "esta zona tiene un
--- mini-boss propio". Una zona sin mini-boss devuelve `nil`, y el servicio
--- simplemente no invoca a nadie.
--- @param worldId any
--- @param zoneId any
--- @return any?
function Rules.GetForZone(worldId: any, zoneId: any): any?
	if type(zoneId) ~= "string" then
		return nil
	end

	for _, mini in ipairs(Rules.GetForWorld(worldId)) do
		if mini.Zone == zoneId then
			return mini
		end
	end

	return nil
end

-- ---------------------------------------------------------------------------
-- ENFRIAMIENTO (lo que distingue a un mini-boss de un guardian permanente)
-- ---------------------------------------------------------------------------

--- Segundos que un mini-boss espera antes de volver a aparecer en su zona.
---
--- Es la garantia de que la zona es un LUGAR y no una sala de espera. Con 90 s
--- un jugador que llega a la zona encuentra al mini-boss, lo derrota y puede
--- seguir explorando; sin enfriamiento, volveria a encontrarlo en el mismo
--- sitio al primer paso, indefinidamente.
Rules.CooldownSeconds = 90

--- Enfriamiento del tier `Rare`, que es el que mas tienta repetir.
---
--- Es MAYOR porque es el mas rentable: con el mismo enfriamiento que un
--- mini-boss comun, el raro seria estrictamente mejor y el resto del contenido
--- del mundo dejaria de usarse.
Rules.RareCooldownSeconds = 150

--- Segundos de enfriamiento de un mini-boss segun su tier.
--- @param mini any
--- @return number
function Rules.CooldownFor(mini: any): number
	if mini and mini.Tier == Rules.Tier.Rare then
		return Rules.RareCooldownSeconds
	end

	return Rules.CooldownSeconds
end

--- Fases de un mini-boss.
---
--- Son TRES, igual que las del boss principal pero con menos castigo. La razon
--- de que el mini-boss tenga fases y no sea solo "mas vida" es la misma que
--- para el boss: el jugador tiene que PERCIBIR que la situacion cambio, y eso
--- no se comunica con una barra que baja mas despacio.
Rules.Phases = {
	{ At = 1.0, Damage = 1.0, Speed = 1.0, Name = "" },
	{ At = 0.6, Damage = 1.2, Speed = 1.1, Name = "FURIA" },
	{ At = 0.3, Damage = 1.4, Speed = 1.2, Name = "FURIA" },
}

--- Indice de fase para una fraccion de vida (1..3).
--- @param ratio number 0..1
--- @return number
function Rules.PhaseFor(ratio: number): number
	local index = 1

	for i, phase in ipairs(Rules.Phases) do
		if ratio <= phase.At then
			index = i
		end
	end

	return index
end

--- Probabilidad de que aparezca un mini-boss en una tirada de noche.
---
--- Es ALTA para el comun y BAJA para el raro. Un rare que sale tanto como el
--- comun deja de ser una sorpresa, que es la unica razon por la que tiene
--- ese tier.
Rules.RollChance = {
	Common = 0.35,
	Elite = 0.18,
	Rare = 0.09,
}

--- Decide si un mini-boss aparece, dado un numero en 0..1.
--- Recompensa de un mini-boss.
---
--- Es deliberadamente MENOR que la del boss principal. Se declara el tope
--- superior (`MaxXP`) para que esa comparacion sea COMPROBABLE: si alguien
--- sube estas cifras hasta que un mini-boss paga mas que su boss, esta funcion
--- deja de cumplir su promesa y `MiniBoss.spec` lo dice.
Rules.RewardBase = { XP = 140, Coins = 90 }

--- Tope duro del XP de un mini-boss.
---
--- Existe porque la recompensa se multiplica por noche, tier Y dificultad, y
--- ese producto sin tope produce el numero con el que la economia se rompe.
Rules.MaxXP = 900

--- Recompensa de derrotar un mini-boss, escalada por noche y tier.
--- @param mini any
--- @param night any
--- @param rewardScale any?
--- @return { XP: number, Coins: number, Gems: number }
function Rules.RewardFor(mini: any, night: any, rewardScale: any?): { XP: number, Coins: number, Gems: number }
	local n = tonumber(night)

	if not n or n ~= n then
		n = 1
	end

	n = math.clamp(n, 1, 99)

	local scale = tonumber(rewardScale)
	if not scale or scale ~= scale or scale < 1 then
		scale = 1
	end

	local nightBonus = 1 + (n - 1) / 98 * 0.9

	-- El tier paga un PLUS FIJO, no un porcentaje: el `Rare` tiene que sentirse
	-- claramente mejor sin que `Common` deje de tener sentido.
	local tierBonus = 1
	if mini and mini.Tier == Rules.Tier.Rare then
		tierBonus = 1.6
	elseif mini and mini.Tier == Rules.Tier.Elite then
		tierBonus = 1.3
	end

	local factor = math.min(scale, 3) * nightBonus * tierBonus

	return {
		XP = math.min(Rules.MaxXP, math.floor(Rules.RewardBase.XP * factor)),
		Coins = math.floor(Rules.RewardBase.Coins * factor),
		Gems = if n >= 40 then 1 else 0,
	}
end

-- ---------------------------------------------------------------------------
-- AUDITORIA CONTRA LOS BOSSES PRINCIPALES
-- ---------------------------------------------------------------------------

--- Ids de los bosses PRINCIPALES, que la expansion no puede reemplazar.
---
--- Se declaran aqui como una COPIA a proposito. `MonsterDefinitions` se carga
--- con stubs de color fuera de Roblox, y depender de el haria que esta
--- auditoria solo pudiese correr dentro del motor. La copia se verifica
--- contra las definiciones reales en `MiniBoss.spec`.
Rules.BossIds = {
	ForestGrooty = true,
	DesertSandBeast = true,
	IceFrostKing = true,
	VolcanoMagmaLord = true,
	CyberCore = true,
}

--- Comprueba que ningun mini-boss reemplaza a un boss principal.
---
--- Esta auditoria es la que hace que la fase 16 ("conservar los bosses") sea una
--- GARANTIA y no una intencion. Si alguien declarase un mini-boss con el id de
--- Grooty, el servicio tendria dos caminos de spawn para el mismo enemigo y
--- uno de ellos ganaria.
--- @return { string } problemas lista vacia = todo cuadra
function Rules.Audit(): { string }
	local problems: { string } = {}

	for worldId, list in pairs(Rules.ByWorld) do
		if #list < 2 then
			table.insert(problems, ("%s: solo %d mini-bosses"):format(worldId, #list))
		end

		local zones: { [string]: boolean } = {}

		for _, mini in ipairs(list) do
			if Rules.BossIds[mini.Id] then
				table.insert(problems, ("%s: '%s' es un boss principal, no un mini-boss")
					:format(worldId, mini.Id))
			end

			if mini.Health <= 0 then
				table.insert(problems, ("%s: '%s' tiene vida %s")
					:format(worldId, mini.Id, tostring(mini.Health)))
			end

			-- Dos mini-bosses en la misma zona se pisan: uno nunca aparece, y el
			-- jugador ve una zona "vacia" sin saber por que.
			if zones[mini.Zone] then
				table.insert(problems, ("%s: dos mini-bosses en la zona '%s'")
					:format(worldId, tostring(mini.Zone)))
			end
			zones[mini.Zone] = true

			-- Un mini-boss mas grande que el boss rompe la lectura visual: el
			-- jugador veria algo enorme y pensaria que es el cierre del mundo.
			if mini.Scale >= 2.6 then
				table.insert(problems, ("%s: '%s' escala %.2f, mayor que un boss")
					:format(worldId, mini.Id, mini.Scale))
			end
		end
	end

	return problems
end

--- Decide si un mini-boss aparece, dado un numero en 0..1.
---
--- Como en `EventRules.Roll`, la FUNCION es pura y el azar lo pone quien llama.
--- @param mini any
--- @param roll number 0..1
--- @return boolean
function Rules.ShouldSpawn(mini: any, roll: number): boolean
	if type(roll) ~= "number" or roll ~= roll then
		return false
	end

	local chance = Rules.RollChance[(mini and mini.Tier) or Rules.Tier.Common] or 0.2

	return math.clamp(roll, 0, 0.999999) < chance
end

return Rules
