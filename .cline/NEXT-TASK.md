# NEXT TASK — FASE 3 COMPLETED (2026-10-07)

## PROXIMA FASE: FASE 4 — Expansión y refuerzo de gameplay V2

## Estado de FASE 3 (completada)
- Implementada, verificada localmente (1014/1014 PASS, verify:structure/wiring PASS, rojo:build PASS) y playtesteada en Studio/MCP (CONECTADO).
- BUG FIX: material rewards (Mat_*) ahora se entregan via InventoryService.AddItem en lugar de GrantCurrency.
- Playtest resultados: Offer/Interact/Claim/RecordMetric/duplicates/rejections/concurrency todos PASS.
- Estado git: arbol DIRTY (pendiente commit + push de FASE 3).
- Studio/MCP: CONECTADO y playtesteado.

## Estado de FASE 2 (completada)
- HEAD real `6545120` = origin/main. (`41a2a94` = FASE 1 RE-AUDIT; source idéntico
  a 6545120. `6545120` = commit de continuidad FASE 2 COMPLETED y último estado
  verificado con 973/973 PASS. El HEAD actual tras el commit de corrección que
  contiene este archivo es sucesor de 6545120; STATE.json lo referencia por
  convención de no-autorreferencia.)
- Bloques 1-4 estaban ya commited en `06727a7`. Bloque 5 (PuzzleService) estaba sin commit.
- FASE 2: commited Bloque 5 (`7941e83`) + FASE 1 RE-AUDIT docs (`41a2a94`) y
  continuidad FASE 2 (`6545120`), push a origin/main, sincerado STATE.json a
  HEAD `6545120`, arbol LIMPIO.
- Las modificaciones V2 existentes en el arbol fueron consolidadas antes de continuar.
- Verificaciones: npm test PASS (973/973), npm run verify PASS (exit 0), analyze.js FAIL baseline (documentado).
- Brainrot visual intacto. AUDIO ASSETS BLOCKED_EXTERNAL (sin IDs reales).

## Reglas vigentes
- NO redisenar Brainrot (visual). Problemas visuales -> `BRAINROT_VISUAL_FOLLOWUP`.
- NO inventar IDs de audio.
- Server-authoritative en dano/moneda/drops/recompensas; rate limit via RemoteGateway.
- Respetar `PerformanceConfig` (caps, pooling, concurrencia).
- Antes de cada commit: `git diff --check`; despues: push real a `origin/main`.
- Verificacion por bloque: suite Luau + verify:structure + verify:wiring + rojo build + tests nuevos; y sonda runtime en Studio cuando la sesion este disponible.

## Estado real
- FASE 0-3: PASS. Bloques 1-5 commited y push a origin/main. FASE 3 implementada + playtesteada. Studio/MCP CONECTADO y playtesteado.
- Entorno (verify:env, esta sesion): Studio/MCP CONECTADO; analyze.js FAIL baseline preexistente; rojo build PASS; npm test 1014/1014 PASS; npm run verify PASS.
- `GAMEPLAY_AUDIT.md` actualizado con estado de resolucion por hallazgo.

## Siguiente iteracion (FASE 3, pendientes reales, por prioridad)

1. **Panel World Completion** (FASE 44): los datos ya se publican por atributos; falta el panel en UI + test de contrato.
2. **Cadenas de misiones** (FASE 41): `QuestRules` no soporta prerrequisitos; ampliar con `RequiresQuestId`.
3. **Cofres fisicos** (FASE 24): categorias, apertura con animacion/sonido/VFX y drop via `LootRules`.
4. **Companeros Brainrot** (FASE 22): evaluar sobre el bestiario; NUNCA auto-play. Disenios visuales intactos.
5. **Player home / vehiculos / NPC dinamicos / reputacion** (FASES 30/31/39/42).
6. **Party/Matchmaking** (FASES 19/20): stubs.
7. **Audio real** (externo): subir IDs reales al Creator Dashboard.
8. **FASE 3 follow-up**: inyectar puntos de Discovery/Rescue/Mechanic (RegisterPoints) desde loader de mundo; forward de Destruction/Secret/Event a RecordMetric.

## Orden de ataque propuesto (FASE 4 en adelante)
1. Commit+push FASE 3 (Activities + bugfix material rewards).
2. Panel World Completion + cadenas de misiones + cofres fisicos.
3. Ritual boss completo.
4. Secundario por mundo (2.º secreto, coleccionables, eventos propios).
5. Party real sin bloquear solitario.
6. Audio real (externo).
