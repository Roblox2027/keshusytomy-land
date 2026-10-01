# Vertical Slice

Primera meta funcional. No se construye ningun sistema secundario hasta
que este flujo funcione de punta a punta en Roblox Studio.

Estado: **PARTIAL**. Todo el flujo de codigo existe y esta integrado
(servidor valida, no el cliente). Falta la verificacion dentro de
Roblox Studio, que queda BLOCKED en este entorno.

```text
LOBBY
 |
FOREST
 |
PLAYER
 |
MOVEMENT
 |
BOMB            OK  - servidor valida distancia, cooldown y ronda
 |
EXPLOSION       OK  - dano por area con caida por distancia
 |
DESTRUCTIBLE    OK  - 48 bloques, se destruyen con dano del servidor
   BLOCK
 |
MONSTER         NO IMPLEMENTED
 |
DAMAGE          OK  - solo contra Humanoid; no hay monstruos
 |
PVP             OK  - una bomba en el centro mata de un golpe
 |
DEATH           OK  - Humanoid.Died, resuelve el servidor
 |
XP              PARCIAL - solo en sesion; sin DataStore
 |
REWARD          OK  - la calcula el servidor
 |
RESULTS         PARCIAL - texto en el HUD, sin pantalla completa
 |
LOBBY           OK  - teletransporte automatico
```

## Criterios de aceptacion

1. El jugador aparece en el lobby sin errores en consola.
2. Puede entrar a Forest desde un portal validado por el servidor
   (nivel minimo comprobado en servidor, no en cliente).
3. Se mueve con teclado, gamepad, touch y tablet.
4. Coloca una bomba: el servidor valida distancia, cooldown y estado de ronda.
5. La bomba explode en el tiempo del servidor y aplica dano por area.
6. Los bloques destructibles desaparecen solo con dano del servidor.
7. Los monstruos aparecen, se mueven y reciben dano.
8. El PvP causa muerte, y la muerte la resuelve el servidor.
9. La muerte otorga XP y recompensa solo si la calcula el servidor.
10. Se muestra la pantalla de resultados y se devuelve al lobby.

Los criterios 1, 4, 5, 6, 8, 9 y 10 tienen codigo implementado y
verificado por pruebas. Los criterios 2 y 7 NO estan implementados.
Los criterios 3 y 10 dependen del motor y siguen BLOCKED.

Cada paso se prueba en Studio antes de pasar al siguiente.

## Causa del fallo reportado: el personaje cae al vacío

**Causa real: `src/Workspace` no contenía NINGÚN mapa.** Solo había
carpetas vacías con `.gitkeep`. El lugar compilado tenía cero `Part` y
cero `SpawnLocation`.

Roblox coloca al personaje en el `SpawnLocation` más cercano; si no hay
ninguno, aparece en el origen. Sin suelo, cae indefinidamente.

A esto se sumaba un segundo fallo que lo ocultaba: `ServiceRegistry`
leía `GameConfig.Performance.WarnThreshold`, y `GameConfig` no expone
`Performance` (vive en `PerformanceConfig`). Eso lanzaba un error en el
arranque de cada servicio, así que aunque hubiera habido mapa, el
servidor tampoco habría iniciado bien.

Un tercer fallo: `Logger.Error` usaba `error(...)`. Como `Logger.Error`
se llama en rutas de control (por ejemplo tras un `return false`
esperado), cualquier registro de error abortaba el flujo. El servidor
no arrancaba.

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
13. `Gameplay.spec` (18 pruebas) y corrección de un bug de balance
    real: el daño de bomba (45) era menor que la vida (100), así que
    el PvP nunca mataba a nadie.

## Clasificación por fase

PASS: 0 (Bootstrap), 1 (Foundation), 2 (Player System), 4 (Bomb),
5 (Explosion), 6 (Destruction), 7 (Round), 12 parcial (XP de sesión),
25 parcial (resultadoshown, sin pantalla de resultados completa).

PARTIAL: 8 (PvP), 3 (Input), 26 (UI), 26/29 (HUD sin touchscreen
completo), 44 (Feature Flags), 47 (anti-exploit del gateway).

NOT IMPLEMENTED: 9, 10, 11, 13, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24,
27, 28, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 45,
46, 48, 49, 50, 52–64.

BLOCKED: comportamiento dentro de Roblox Studio (spawn real, daño a un
Humanoid, camara, 2 jugadores). El binario de Studio está instalado
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
preparados sin handler: una petición se valida y se descarta.

## Cómo verificar dentro de Studio

```text
rojo serve
```

1. Abrir Studio y conectar al puerto 34872.
2. `rojo build` primero si se abre el `.rbxlx` directamente.
3. Play. El personaje debe aparecer en el lobby, sobre el suelo.
4. Pulsar F: coloca una bomba, explota a los 3 s y destruye bloques.
5. La ronda empieza sola tras ~1 s y teletransporta a la arena.
6. Al morir todos, muestra el resultado y vuelve al lobby.

## Qué falta para ser un juego real

Monstruos, boss, XP persistente (DataStore), inventario, tienda,
portales a otros mundos, matchmaking real, y todo el bloque de
moderación/live-ops. Está detallado en `docs/phases.md`.

```text
LOBBY
 ↓
FOREST
 ↓
PLAYER
 ↓
MOVEMENT
 ↓
BOMB
 ↓
EXPLOSION
 ↓
DESTRUCTIBLE BLOCK
 ↓
MONSTER
 ↓
DAMAGE
 ↓
PVP
 ↓
DEATH
 ↓
XP
 ↓
REWARD
 ↓
RESULTS
 ↓
LOBBY
```

## Criterios de aceptacion

1. El jugador aparece en el lobby sin errores en consola.
2. Puede entrar a Forest desde un portal validado por el servidor
   (nivel minimo comprobado en servidor, no en cliente).
3. Se mueve con teclado, gamepad, touch y tablet.
4. Coloca una bomba: el servidor valida distancia, cooldown y estado de ronda.
5. La bomba explode en el tiempo del servidor y aplica dano por area.
6. Los bloques destructibles desaparecen solo con dano del servidor.
7. Los monstruos aparecen, se mueven y reciben dano.
8. El PvP causa muerte, y la muerte la resuelve el servidor.
9. La muerte otorga XP y recompensa solo si la calculates el servidor.
10. Se muestra la pantalla de resultados y se devuelve al lobby.

Cada paso se prueba en Studio antes de pasar al siguiente.
