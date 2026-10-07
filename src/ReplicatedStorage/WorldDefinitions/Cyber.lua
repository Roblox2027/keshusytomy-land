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
    -- Mecanicas expandidas de FASE 4. Lista de kinds del catalogo WorldMechanics.
    -- Verificado por `WorldMechanics.Audit` contra MechanicsByWorld.
    Mechanics: { string }?,
    Rewards: {
        XP: number,
        Coins: number,
    },
}

local World: WorldDefinition = {
    Id = "Cyber",
    Name = "Cyber",
    DisplayName = "Cyber Keshusy",
    -- FASE 3 (expansion 99 noches): TODOS los mundos se abren desde el nivel 1.
    --
    -- Antes este valor era el unico mecanismo de dificultad entre mundos y
    -- tambien el bloqueo de entrada: Cyber exigia nivel 50. La expansion separa
    -- las dos cosas y por eso `Difficulty` (abajo) es la que define que tan duro
    -- es el mundo, mientras este campo queda en 1 para todos.
    --
    -- NO se borra el campo: `PortalService` lo lee para PINTAR el cartel del
    -- portal, y la comprobacion `WorldAccess.spec` verifica que ningun mundo
    -- vuelva a cerrarse.
    RequiredLevel = 1,
    Theme = "Cyber",
    Difficulty = 5,
    MusicId = nil,
    MapFolder = "Cyber",
    BossDefinitionId = "CyberCore",
    SpawnRules = { "CyberStalker", "BomberMonster", "CyberStalker", "Guardian" },
    -- FASE 4: terminales con maquina de estados, puertas de seguridad y lasers.
    Mechanics = { "Terminal", "SecurityDoor", "SecurityLasers", "DynamicRoute" },
    Rewards = {
        XP = 50,
        Coins = 25,
    },
}

return World
