# NEXT TASK
Phase 2 Systems Audit COMPLETE - EventService y MiniBossService cableados (estaban construidos pero muertos en runtime); `npm run verify` exit 0; `verify:wiring` PASS (28 servicios / 19 conexiones / 45 llamadas).

Next: **Fase 3 - Acceso mundos**:
1. Auditar `WorldAccessRules` + `PortalService.HandleEnter` + `WorldService` contra `tests/shared/WorldAccess.spec.lua`.
2. Comprobar el flujo Lobby -> Portal -> mundo -> regreso con las reglas de acceso (bloqueo por nivel/estado).
3. Tras cada cambio: `npm run verify` -> `rojo:build` -> MCP/Studio/Play Test si se desbloquean -> regression.

Pendientes registrados (NO olvidar al llegar a su fase):
- **Fase 31-37 (Hordas)**: `HordeService.StartHorde` y `HandleMonsterDeath` sin llamantes; no hay spawn de NPC ni bucle de kills - el sistema solo caduca hordas. No cablear a medias: construir el bucle completo en su fase.
- **Fase 58-59 (HUD)**: `EventService` escribe atributos `EventActive/EventLabel/EventRemaining` pero ningun cliente los lee; anadir banner de evento en HUD.
- **9 stubs** (~810-835B: Analytics, Announcement, Badge, Moderation, Monetization, Report, Teleport, Party, Matchmaking) sin registrar por diseño; registrar cuando su fase los implemente.

Desbloqueos (usuario):
- MCP/Studio: activar el plugin `@chrrxs/robloxstudio-mcp` en Studio (puerto 58741). Verificar: `npm run mcp:list` y `npm run runtime:scan`.
- Git push: `gh auth login` o ventana GCM o clave SSH. Luego `git push origin main` (commits locales `b7299b0` + Fase 2 pendientes de push).

