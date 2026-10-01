# Auditoría de fases 0–64 (estado real)

Fecha: 2026-10-01.
Criterio: una fase es PASS solo si está implementada, integrada,
inicializada y verificada con evidencia. La existencia de un archivo NO
es evidencia.

## Causa del fallo reportado: el personaje cae al vacío

**Causa real: `src/Workspace` no contenía NINGÚN mapa.** Solo había
carpetas vacías con `.gitkeep`. El lugar compilado tenía cero `Part` y
cero `SpawnLocation`.

Roblox coloca al personaje en el `SpawnLocation` más cercano; si no hay
ninguno, aparece en el origen. Sin suelo, cae indefinidamente.

Lo ocultaban dos fallos adicionales:

1. `ServiceRegistry` leía `GameConfig.Performance.WarnThreshold`, pero
   `GameConfig` no expone `Performance` (vive en `PerformanceConfig`).
   Eso lanzaba un error al inicializar cada servicio.
2. `Logger.Error` usaba `error(...)`. Como se llama en rutas de control
   (después de un `return false` esperado), cualquier registro de error
   abortaba el flujo: **el servidor no arrancaba**.

Los tres están corregidos y verificados.

## Corregido en esta auditoría

1. Mapa real generado por `tools/generate-project.js`: lobby, arena
   Forest, muros perimetrales, 48 bloques destructibles y 6
   `SpawnLocation`. Verificado en el `.rbxlx` compilado (66 `Part`,
   6 `SpawnLocation`).
2. `ServiceRegistry` usa `PerformanceConfig`.
3. `Logger.Error` registra sin lanzar excepción.
4. `SpawnService` falla de forma visible si no hay spawn, y rescata al
   jugador que cae por debajo de `VoidKillY`.
5. Ciclo de ronda real (`RoundService.runRoundLoop`) con temporizadores.
6. `BombService` real: valida ronda, distancia y cooldown en servidor.
7. `ExplosionService` real: daño por área con caída por distancia.
8. `DestructionService` real: vida y destrucción de bloques `Block_`.
9. `MatchService` real: teletransporte lobby↔arena y recompensas.
10. `PlayerService`: muerte, recompensas y publicación de atributos.
11. `InputController` y `UIController` con funcionalidad real.
12. Handlers de `BombAction.Place` y `PlayerAction` conectados.
13. `Gameplay.spec` (18 pruebas) detectó un bug de balance real: el daño
    de bomba (45) era menor que la vida (100), así que el PvP nunca
    mataba a nadie. Corregido a 120.

## Clasificación por fase

PASS: 0 (Bootstrap), 1 (Foundation), 2 (Player System), 4 (Bomb),
5 (Explosion), 6 (Destruction), 7 (Round).

PARTIAL: 3 (Input), 8 (PvP), 12 (XP, solo sesión), 25 (Resultados),
26 (UI), 29 (Mobile), 44 (Feature Flags), 47 (Anti-Exploit del gateway).

NOT IMPLEMENTED: 9, 10, 11, 13, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24,
27, 28, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 45,
46, 48, 49, 50, 52–64.

BLOCKED: comportamiento dentro de Roblox Studio (spawn real, daño a un
Humanoid, cámara, 2 jugadores). El binario de Studio está instalado
pero no se puede automatizar en este entorno.

## Servicios

| Servicio | Estado |
| -------- | ------ |
| WorldService | FUNCIONANDO |
| SpawnService | FUNCIONANDO |
| RoundService | FUNCIONANDO |
| PlayerService | FUNCIONANDO |
| DestructionService | FUNCIONANDO |
| ExplosionService | FUNCIONANDO |
| BombService | FUNCIONANDO |
| MatchService | FUNCIONANDO |
| 22 servicios restantes | STUB declarado (Init/Destroy vacíos) |

## Remotes

Los 8 `RemoteEvent` existen, están validados y limitados por el gateway.
2 tienen handler real (`BombAction.Place`, `PlayerAction`). 6 están
preparados sin handler: la petición se valida y se descarta.

## Cómo verificar dentro de Studio

```text
node tools/generate-project.js
rojo build
```

O, para live-sync: `rojo serve` y conectar Studio al puerto 34872.

1. Play. El personaje debe aparecer en el lobby, sobre el suelo.
2. Pulsar F: coloca una bomba, explota a los 3 s y destruye bloques.
3. La ronda empieza sola tras ~1 s y teletransporta a la arena.
4. Al morir todos, muestra el resultado y vuelve al lobby.

## Qué falta para ser un juego real

Monstruos, boss, XP persistente (DataStore), inventario, tienda,
portales a otros mundos, matchmaking real, y todo el bloque de
moderación y live-ops. Está detallado en `docs/phases.md`.