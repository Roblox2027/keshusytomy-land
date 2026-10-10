local bs = require(game.ServerScriptService.Services.BrainrotService)
local ms = require(game.ServerScriptService.Services.MonsterService)
return {
    same_module = (bs._monsterService == ms),
    monster_spawn_type = typeof(bs._monsterService.Spawn),
    monster_buildMonster = typeof(bs._monsterService.VisualKit),
}
