# NEXT TASK
Phase 1 Generator COMPLETE - `npm run verify` exit 0, idempotencia probada (2 ejecuciones de `node tools/generate-project.js` con SHA256 identicos y `git status` sin cambios entre runs).

Next: **Fase 2 - Sistemas existentes**:
1. Inventario de los 37 servicios de `src/ServerScriptService/Services/` y 12 controllers (YA existentes; NO crear `*Service2`).
2. Auditar que cada sistema del Master Script (Bomb/Monster/Quest/Powerup/Boss/World/Night/Economy/Destruction/Navigation/Horde/MiniBoss/Event) tenga dueño unico y este cableado en `ServerMain.server.lua`.
3. Extender los existentes; anyadir tests solo si cubren huecos reales.
4. Tras cada cambio estructural: Generator (si aplica) -> `rojo:build` -> MCP/Studio/Play Test si estan desbloqueados -> `npm run verify` -> regression.

Desbloqueo MCP/Studio (para fases de validacion visual):
- Abrir Roblox Studio con el plugin `@chrrxs/robloxstudio-mcp` ACTIVO (debe escuchar en `127.0.0.1:58741`).
- Verificar con `npm run mcp:list` y `npm run runtime:scan` (hoy: BLOCKED en ambos).
- Solo entonces registrar MCP/Studio/Play Test como PASS - nunca antes.
