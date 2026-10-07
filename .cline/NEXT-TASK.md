# NEXT TASK — FASE 1 RE-AUDIT PASS (2026-10-07)

## 1. Commit por bloque + push (CRITICAL proceso, antes de V2)
- Arbol sucio con Bloques 1-5; `git diff --check`, commit separados, push a origin/main.

## 2. Sincerar STATE (CRITICAL)
- HEAD real `06727a7`; corregir commit/head/origin fantasmas.

## 3. Siguiente iteracion V2 (orden auditado)
1. Panel World Completion. 2. Cadenas de misiones. 3. Cofres fisicos. 4. Ritual boss completo. 5. Secundario por mundo. 6. Party real. 7. Audio real (externo).

## Reglas: no rediseñar Brainrot visual; no inventar IDs audio; server-authoritative; PerformanceConfig.

## Estado real
- FASE 0+1: PASS (auditoria `GAMEPLAY_AUDIT.md`).
- BLOQUES 1-5: implementados, verificados localmente (973/973 tests, wiring/estructura/build PASS) y VALIDADOS EN RUNTIME REAL (playtest Studio con sondas funcionales: eventos con cuerpo, hazards, combate con gate, servicios V2 inicializados).
- `GAMEPLAY_AUDIT.md` actualizado con estado de resolucion por hallazgo.

## Siguiente iteracion (pendientes reales, por prioridad)

1. **Panel World Completion** (FASE 44): los datos ya se publican por atributos (SecretsFound, BestiaryCount/Total, AchievementsCount); falta el panel en `tools/hud.js` + su test de contrato.
2. **Cadenas de misiones** (FASE 41): `QuestRules` no soporta prerrequisitos; ampliar con `RequiresQuestId` y quests encadenadas por mundo.
3. **Cofres fisicos** (FASE 24): categorias, apertura con animacion/sonido/VFX y drop via `LootRules`.
4. **Companeros Brainrot** (FASE 22): evaluar sobre el bestiario; NUNCA auto-play. Disenios visuales intactos (restriccion absoluta).
5. **Player home / vehiculos / NPC dinamicos / reputacion** (FASES 30/31/39/42): evaluar una por una.
6. **Party/Matchmaking** (FASES 19/20): los stubs siguen sin implementar.

## Reglas vigentes
- NO redisenar Brainrot (visual). Problemas visuales -> `BRAINROT_VISUAL_FOLLOWUP`.
- NO inventar IDs de audio.
- Server-authoritative en dano/moneda/drops/recompensas; rate limit via RemoteGateway.
- Respetar `PerformanceConfig` (caps, pooling, concurrencia).
- Antes de cada commit: `git diff --check`; despues: push real a `origin/main`.
- Verificacion por bloque: suite Luau + verify:structure + verify:wiring + rojo build + tests nuevos; y sonda runtime en Studio cuando la sesion este disponible.
