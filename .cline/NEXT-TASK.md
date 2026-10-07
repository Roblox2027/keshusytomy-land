# NEXT TASK

## Mision: MASTER MISSION V2 — Expansion total de gameplay

## Estado real
- FASE 0 (continuidad): PASS. Git limpio, HEAD=origin/main=`ed18f24`, verify en PASS (salvo analyze.js baseline).
- FASE 1 (auditoria): PASS. `GAMEPLAY_AUDIT.md` publicado con 16 hallazgos priorizados.

## Siguiente: BLOQUE 1 — MUNDO VIVO

1. **A2 — Eventos con cuerpo** (mision FASE 4/5):
   - `EventService` ya abre/cierra eventos; falta el cuerpo: spawns de enemigos del evento, zona marcada, objetivo, contador, UI de anuncio, cleanup garantizado.
   - 4-6 eventos por mundo + evento mundial `WORLD_INVASION` con objetivo compartido.
   - Anti-spam: respetar `EventRules.MaxActivePerWorld`/`MaxActiveTotal` y cooldowns.
2. **A3 — Mecanica por mundo** (mision FASE 3):
   - `HazardService` server-side con zonas etiquetadas desde el generador `tools/worlds.js`.
   - Forest: emboscadas/zonas ocultas. Desert: arenas movedizas (slow) + tesoros. Ice: friccion baja + hielo rompible. Volcano: lava DOT + erupcion telegrafiada. Cyber: laseres con patron + terminales.
3. **B6 — Noche con dientes** (mision FASE 38, AMBIENTAL):
   - Lighting por fase via VisualService, spawns nocturnos, secretos nocturnos. SIN progreso por noches.

## Reglas vigentes
- NO redisenar Brainrot (visual). Problemas visuales -> `BRAINROT_VISUAL_FOLLOWUP`.
- NO inventar IDs de audio.
- Server-authoritative en todo lo que mueva dano/moneda/drops/recompensas.
- Respetar `PerformanceConfig` (caps, pooling, concurrencia).
- Antes de cada commit: `git diff --check`; despues: push real a `origin/main`.
- Verificacion por bloque: `npm test`, `npm run verify`, `npm run rojo:build` + tests nuevos del bloque.
