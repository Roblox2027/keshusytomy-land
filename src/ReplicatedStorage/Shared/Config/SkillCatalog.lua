--!strict
--[[
	SkillCatalog
	Catálogo de HABILIDADES que se desbloquean al abrir cofres.

	POR QUE EXISTE
	--------------
	Hasta ahora el juego tiene "habilidad" como un ataque de combate con
	cooldown (CombatRules.Ability). No hay habilidades pasivas que mejoren
	al jugador de forma duradera: nada que eleve daño, velocidad, vida
	útil o capacidad de bombas más allá de los stats del equipo.

	Los cofres son el vehículo para ENTREGAR estas habilidades: el jugador
	los encuentra explorando el mundo, los abre y gana una habilidad
	permanente (o un upgrade) que persiste entre sesiones.

	LA CLASIFICACIÓN
	------------------
	Cada habilidad tiene:
	  - Id:           identificador único (usado como item en el inventario)
	  - Name:         nombre legible
	  - Description:  texto de la UI
	  - Rarity:       Common/Rare/Epic/Legacy (qué tan dura de encontrar)
	  - World:        mundo de origen (afecta la tabla de drop de cofres)
	  - Category:     grupo al que pertenece (para la colección de habilidades)
	  - Tier:         nivel dentro de la categoría (1 = básico, 3 = máximo)
	  - Effect:       tabla con los mods que aplica (server-authoritative)

	LAS CATEGORÍAS DE HABILIDAD
	---------------------------
	  1. Bomba      — capacidad / daño / radio de explosión
	  2. Movimiento — velocidad base, dash, esquiva
	  3. Combate    — daño cuerpo a cuerpo, cooldown de habilidad
	  4. Supervivencia — vida máxima, regeneración, resistencias
	  5. Utilidad   — drops, XP, visión nocturna, puntos de hallazgo

	LA REGLA DE STACKING
	--------------------
	Una habilidad de Tierra 1 y otra de Tierra 3 de la misma categoría
	NO se acumulan: el jugador debe elegir. Pero habilidades de categorías
	DISTINTAS sí se combinan. La validación de esto está en
	`ChestRules.Audit`, no aquí.

	Este módulo es DATOS PUROS. Se carga con el intérprete standalone
	igual que `MonsterDefinitions`: no usa Color3, ni Enum, ni servicios.
]]

local Categories = {
	Bomb = "Bomb",
	Movement = "Movement",
	Combat = "Combat",
	Survival = "Survival",
	Utility = "Utility",
}

local Rarity = {
	Common = "Common",
	Rare = "Rare",
	Epic = "Epic",
	Legacy = "Legacy",
}

-- ---------------------------------------------------------------------------
-- CATÁLOGO
-- ---------------------------------------------------------------------------

local Catalog = {
	-- === BOMBA ===========================================================
	--
	-- Tier 1: capacidad básica.
	Skill_BombCapacity1 = {
		Id = "Skill_BombCapacity1",
		Name = "Cargador Extraño",
		Description = " Capacidad de bomba +1.",
		Rarity = Rarity.Common,
		World = "Forest",
		Category = Categories.Bomb,
		Tier = 1,
		Effect = { BombCapacity = 1 },
	},

	Skill_BombCapacity2 = {
		Id = "Skill_BombCapacity2",
		Name = "Cinturón de Cargadores",
		Description = "Capacidad de bomba +2.",
		Rarity = Rarity.Rare,
		World = "Desert",
		Category = Categories.Bomb,
		Tier = 2,
		Effect = { BombCapacity = 2 },
	},

	Skill_BombDamage1 = {
		Id = "Skill_BombDamage1",
		Name = "Cargamento Potente",
		Description = "Daño de explosión +15%.",
		Rarity = Rarity.Common,
		World = "Volcano",
		Category = Categories.Bomb,
		Tier = 1,
		Effect = { BombDamageMult = 0.15 },
	},

	Skill_BombRadius1 = {
		Id = "Skill_BombRadius1",
		Name = "Carga Amplia",
		Description = "Radio de explosión +20%.",
		Rarity = Rarity.Rare,
		World = "Ice",
		Category = Categories.Bomb,
		Tier = 1,
		Effect = { BombRadiusMult = 0.20 },
	},

	-- === MOVIMIENTO ======================================================

	Skill_Speed1 = {
		Id = "Skill_Speed1",
		Name = "Pisadas Ligeras",
		Description = " Velocidad de movimiento +10%.",
		Rarity = Rarity.Common,
		World = "Forest",
		Category = Categories.Movement,
		Tier = 1,
		Effect = { WalkSpeedMult = 0.10 },
	},

	Skill_Speed2 = {
		Id = "Skill_Speed2",
		Name = "Reflejos Afilados",
		Description = "Velocidad de movimiento +20%.",
		Rarity = Rarity.Epic,
		World = "Cyber",
		Category = Categories.Movement,
		Tier = 2,
		Effect = { WalkSpeedMult = 0.20 },
	},

	Skill_DashCooldown1 = {
		Id = "Skill_DashCooldown1",
		Name = "Esquivas Rápidas",
		Description = "Cooldown de esquiva reducido en 15%.",
		Rarity = Rarity.Rare,
		World = "Ice",
		Category = Categories.Movement,
		Tier = 1,
		Effect = { DashCooldownMult = 0.85 },
	},

	-- === COMBATE =========================================================

	Skill_MeleeDamage1 = {
		Id = "Skill_MeleeDamage1",
		Name = "Puño de Hierro",
		Description = "Daño cuerpo a cuerpo +20%.",
		Rarity = Rarity.Common,
		World = "Volcano",
		Category = Categories.Combat,
		Tier = 1,
		Effect = { MeleeDamageMult = 0.20 },
	},

	Skill_AbilityCooldown1 = {
		Id = "Skill_AbilityCooldown1",
		Name = "Reservas de Energía",
		Description = "Cooldown de habilidad reducido en 20%.",
		Rarity = Rarity.Rare,
		World = "Cyber",
		Category = Categories.Combat,
		Tier = 1,
		Effect = { AbilityCooldownMult = 0.80 },
	},

	-- === SUPERVIVENCIA ===================================================

	Skill_MaxHealth1 = {
		Id = "Skill_MaxHealth1",
		Name = "Constitución de Acero",
		Description = "Vida máxima +25.",
		Rarity = Rarity.Common,
		World = "Desert",
		Category = Categories.Survival,
		Tier = 1,
		Effect = { MaxHealthBonus = 25 },
	},

	Skill_MaxHealth2 = {
		Id = "Skill_MaxHealth2",
		Name = "Núcleo de Titanio",
		Description = "Vida máxima +50.",
		Rarity = Rarity.Epic,
		World = "Cyber",
		Category = Categories.Survival,
		Tier = 2,
		Effect = { MaxHealthBonus = 50 },
	},

	Skill_FireResist1 = {
		Id = "Skill_FireResist1",
		Name = "Piel de Obsidiana",
		Description = "Reducción de daño por quemadura.",
		Rarity = Rarity.Rare,
		World = "Volcano",
		Category = Categories.Survival,
		Tier = 1,
		Effect = { BurnResist = true },
	},

	Skill_ColdResist1 = {
		Id = "Skill_ColdResist1",
		Name = "Manto de Fuego",
		Description = "Reducción de daño por ralentí.",
		Rarity = Rarity.Rare,
		World = "Ice",
		Category = Categories.Survival,
		Tier = 1,
		Effect = { SlowResist = true },
	},

	-- === UTILIDAD ========================================================

	Skill_XPBonus1 = {
		Id = "Skill_XPBonus1",
		Name = "Explorador Curioso",
		Description = " XP ganada +10%.",
		Rarity = Rarity.Common,
		World = "Forest",
		Category = Categories.Utility,
		Tier = 1,
		Effect = { XPMult = 0.10 },
	},

	Skill_XPBonus2 = {
		Id = "Skill_XPBonus2",
		Name = "Sabiduría de los Ancestros",
		Description = "XP ganada +25%.",
		Rarity = Rarity.Epic,
		World = "Desert",
		Category = Categories.Utility,
		Tier = 2,
		Effect = { XPMult = 0.25 },
	},

	Skill_LootFind1 = {
		Id = "Skill_LootFind1",
		Name = "Ojo de Cuevas",
		Description = "Probabilidad de drop +15%.",
		Rarity = Rarity.Rare,
		World = "Ice",
		Category = Categories.Utility,
		Tier = 1,
		Effect = { LootChanceMult = 0.15 },
	},

	Skill_NightVision1 = {
		Id = "Skill_NightVision1",
		Name = "Visión en la Oscuridad",
		Description = " Mejora la visión nocturna.",
		Rarity = Rarity.Epic,
		World = "Volcano",
		Category = Categories.Utility,
		Tier = 1,
		Effect = { NightVision = true },
	},

	-- === LEGACY (raro, multi-categoría o efecto único) ===================

	Skill_BombCapacity3 = {
		Id = "Skill_BombCapacity3",
		Name = "Cinturón de Guerra",
		Description = "Capacidad de bomba +3 (máximo).",
		Rarity = Rarity.Legacy,
		World = "Cyber",
		Category = Categories.Bomb,
		Tier = 3,
		Effect = { BombCapacity = 3 },
	},

	Skill_Speed3 = {
		Id = "Skill_Speed3",
		Name = "Ráfaga de Viento",
		Description = "Velocidad de movimiento +35% (máximo).",
		Rarity = Rarity.Legacy,
		World = "Ice",
		Category = Categories.Movement,
		Tier = 3,
		Effect = { WalkSpeedMult = 0.35 },
	},

	Skill_ComboExtend = {
		Id = "Skill_ComboExtend",
		Name = "Ritmo de Combate",
		Description = "Ventana de combo +1 golpe.",
		Rarity = Rarity.Legacy,
		World = "Volcano",
		Category = Categories.Combat,
		Tier = 1,
		Effect = { ComboWindowExtra = 1 },
	},

	Skill_TreasureHunter = {
		Id = "Skill_TreasureHunter",
		Name = "Ojo del Cazador",
		Description = "Los cofres tienen +25% de probabilidad de dropear Rare o superior.",
		Rarity = Rarity.Legacy,
		World = "Forest",
		Category = Categories.Utility,
		Tier = 2,
		Effect = { ChestRarityBoost = 0.25 },
	},
}

-- ---------------------------------------------------------------------------
-- INDEX POR ID (construido una vez)
-- ---------------------------------------------------------------------------

local ById = {}
for _, skill in pairs(Catalog) do
	ById[skill.Id] = skill
end

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Devuelve una habilidad por su Id.
--- @param id string
--- @return { [string]: any }?
function Catalog.Get(id: string): { [string]: any }?
	return ById[id]
end

--- Indica si una habilidad existe.
--- @param id any
--- @return boolean
function Catalog.Has(id: any): boolean
	return typeof(id) == "string" and ById[id] ~= nil
end

--- Todos los IDs de habilidades, en orden estable.
--- @return { string }
function Catalog.GetAllIds(): { string }
	local ids = {}
	for id in pairs(ById) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

--- Habilidades de una categoría específica.
--- @param category string
--- @return { { [string]: any } }
function Catalog.GetByCategory(category: string): { { [string]: any } }
	local result = {}
	for _, skill in pairs(ById) do
		if skill.Category == category then
			table.insert(result, skill)
		end
	end
	return result
end

--- Habilidades de un mundo específico.
--- @param worldId string
--- @return { { [string]: any } }
function Catalog.GetByWorld(worldId: string): { { [string]: any } }
	local result = {}
	for _, skill in pairs(ById) do
		if skill.World == worldId then
			table.insert(result, skill)
		end
	end
	return result
end

--- Habilidades de un tier dentro de una categoría.
--- @param category string
--- @param tier number
--- @return { { [string]: any } }
function Catalog.GetByTier(category: string, tier: number): { { [string]: any } }
	local result = {}
	for _, skill in pairs(ById) do
		if skill.Category == category and skill.Tier == tier then
			table.insert(result, skill)
		end
	end
	return result
end

--- Categorías disponibles.
Catalog.Categories = Categories
--- Rarezas disponibles.
Catalog.Rarity = Rarity

return Catalog
