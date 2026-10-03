--!strict
--[[
Cyber
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
    Rewards: {
        XP: number,
        Coins: number,
    },
}

local World: WorldDefinition = {
    Id = "Cyber",
    Name = "Cyber",
    DisplayName = "Cyber Keshusy",
    RequiredLevel = 50,
    Theme = "Cyber",
    Difficulty = 5,
    MusicId = nil,
    MapFolder = "Cyber",
    BossDefinitionId = "CyberCore",
    SpawnRules = { "CyberStalker", "BomberMonster", "CyberStalker", "Guardian" },
    Rewards = {
        XP = 50,
        Coins = 25,
    },
}

return World
