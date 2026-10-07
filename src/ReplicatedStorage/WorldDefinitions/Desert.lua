--!strict
--[[
Desert
Definicion de mundo (WorldData). Solo datos: ninguna logica aqui.

DisplayName es el texto que el jugador LEE en el cartel del portal y en
el HUD. Antes los cinco ponian el id crudo ("Ice", "Desert"), de modo que
el cartel mostraba un nombre interno en vez del nombre del mundo.

SpawnRules es la poblacion de monstruos de la arena: la lee
MatchService.BuildMonsterSpawns. Antes era una tabla vacia, asi que el
servicio recurria a una lista fija de monstruos de Forest en cualquier
mundo.

MapFolder es el nombre de la carpeta en Workspace.Worlds, y
BossDefinitionId el boss que espera en la plataforma del norte.
]]

export type WorldDefinition = {
    Id: string,
    Name: string,
    DisplayName: string,
    RequiredLevel: number,
    Theme: string,
    Difficulty: number,
    MusicId: string?,
    MapFolder: string?,
    BossDefinitionId: string?,
    SpawnRules: { string },
    -- Mecanicas expandidas de FASE 4. Lista de kinds del catalogo WorldMechanics.
    -- Verificado por `WorldMechanics.Audit` contra MechanicsByWorld.
    Mechanics: { string }?,
    Rewards: {
        XP: number,
        Coins: number,
    },
}

local World: WorldDefinition = {
    Id = "Desert",
    Name = "Desert",
    DisplayName = "Boom Desert",
    -- FASE 3 (expansion 99 noches): todos los mundos se abren desde nivel 1.
    -- La dificultad real la define `Difficulty`. Ver la nota de `Cyber.lua`.
    RequiredLevel = 1,
    Theme = "Desert",
    Difficulty = 2,
    MusicId = nil,
    MapFolder = "Desert",
    BossDefinitionId = "DesertSandBeast",
    SpawnRules = { "Hunter", "Hunter", "Guardian", "Slime" },
    -- FASE 4: tormenta de arena con fases, tesoros enterrados y oasis seguros.
    Mechanics = { "TemporalEvent", "BuriedTreasure", "Oasis" },
    Rewards = {
        XP = 20,
        Coins = 10,
    },
}

return World
