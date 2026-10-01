--!strict
--[[
    Volcano
    Definicion de mundo (WorldData). Solo datos: ninguna logica aqui.
    El mapa, los monstruos y el boss se construyen en fases posteriores.
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
    Id = "Volcano",
    Name = "Volcano",
    DisplayName = "Volcano",
    RequiredLevel = 35,
    Theme = "Volcano",
    Difficulty = 4,
    MusicId = nil,
    MapFolder = nil,
    BossDefinitionId = nil,
    SpawnRules = {
        -- FASE 16 : reglas concretas de spawn por zona.
    },
    Rewards = {
        XP = 40,
        Coins = 20,
    },
}

return World
