# NEXT TASK

## Mision: MASTER MISSION V2 — Expansion total de gameplay

## Estado real
- FASE 0+1: PASS (commit `09007f3`, `GAMEPLAY_AUDIT.md`).
- BLOQUE 1 (Mundo vivo): PASS local. Eventos con cuerpo, hazards por mundo, luz de noche. 919/919 tests, wiring/estructura/build PASS.

## Siguiente: BLOQUE 2 — COMBATE

1. **A1 — Combate V2** (mision FASE 8/9/32):
   - Ataque rapido cuerpo a cuerpo (hitbox corta, cooldown ~0.5s), dash con i-frames breves (~0.3s), habilidad con cooldown (~8s).
   - TODO server-authoritative: nuevo canal de remoto via `RemoteGateway`/`RemoteAction`, validacion de cooldown y alcance en servidor, dano via `CombatService.ApplyDamage`.
   - Combos ligeros: 3er golpe consecutivo = golpe especial (bonus de dano), ventana de combo acotada (sin spam infinito).
   - Input: `InputController` (tecla + boton tactil si la arquitectura lo permite).
   - Cliente: animacion/VFX/sonido de telegraph via `EffectsController`/`AudioController` (SIN inventar IDs de audio).
2. **B1 — Boss ritual** (mision FASE 10):
   - `MonsterService.BOSS_PHASES` ya cambia multiplicadores; falta: telegraph de area (indicador visible + ventana de reaccion), adds en fase 2, debilidad en fase 3, intro (camara/texto), recompensa especial.
   - 3 fases que cambian de verdad el combate; sin romper `test:powerup-boss`.

## Reglas vigentes
- NO redisenar Brainrot (visual). Problemas visuales -> `BRAINROT_VISUAL_FOLLOWUP`.
- NO inventar IDs de audio.
- Server-authoritative en dano/moneda/drops/recompensas; rate limit via RemoteGateway.
- Respetar `PerformanceConfig` (caps, pooling, concurrencia).
- Antes de cada commit: `git diff --check`; despues: push real a `origin/main`.
- Verificacion por bloque: `npm test`, verify:structure, verify:wiring, rojo build + tests nuevos.
