# QA
## Status (Fase 1 - 2026-10-07)
- Tests: PASS (npm test 892 pasaron / 0 fallaron; suites 47/47)
- Verify: PASS (`npm run verify` exit 0 completo: structure, wiring, worlds, contract, navigation, spawn, world-edge, monster-access 49/49, bomb-grid, powerup-boss 9 powerups/5 bosses, rojo:build, env, context)
- Rojo: PASS (Rojo 7.7.0 -> `.ai/runtime/latest.rbxlx`)
- Generator: PASS idempotente (2 ejecuciones `node tools/generate-project.js`: SHA256 `553A3027...BAC8` / `806C0F5E...30FA` identicos; git status sin cambios entre runs; escribe solo default.project.json + tools/sync-lighting.lua)
- MCP: BLOCKED (ver BLOCKED.md; detectado con herramientas reales `studio-mcp.js` y `runtime-scan.js`, no asumido)
- Studio: BLOCKED (proceso abierto PID 29564, plugin MCP no responde; NO ejecutado ni inspeccionado)
- Play Test: BLOCKED (sin MCP/Studio dirigible; NO ejecutado)
- MAP/Datamodel visual: NO VALIDADO (no confundir con verify: la validacion de codigo y la visual son distintas)
- analyze.js (typecheck): FAIL preexistente (documentado en .ai/AI_CONTEXT.md y verify:env; 521 incidencias previas a este bootstrap)

## Status (Fase 2 - 2026-10-07)
- Verify: PASS exit 0 tras cablear EventService + MiniBossService (structure, wiring, 892 tests, worlds, contract, navigation, spawn, world-edge, monster-access 49/49, bomb-grid, powerup-boss, rojo:build, env, context)
- verify:wiring: PASS (28 servicios en SERVICES, 19 conexiones, 45 llamadas entre servicios; metodos cableados existen en sus servicios)
- Cobertura de servicios: 28 registrados / 9 stubs sin registrar por diseño / 0 duplicados `*Service2`
- Cableado nuevo: EventService (antes 0 referencias externas) y MiniBossService (antes SetMiniBossService sin invocar) - P0s de integracion reparados
- MCP: BLOCKED / Studio: BLOCKED / Play Test: BLOCKED / MAP visual: NO VALIDADO (ver BLOCKED.md)
- Git push: BLOCKED (commits locales b7299b0 + Fase 2 pendientes de push por credenciales GitHub)