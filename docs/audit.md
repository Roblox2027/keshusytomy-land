# Auditoría de fases 0–64 (estado real)

Fecha: 2026-10-01. Actualizada tras la auditoría del vertical slice.

Criterio: una fase es PASS solo si está implementada, integrada,
inicializada y verificada con evidencia. La existencia de un archivo NO
es evidencia. Compilar, pasar tests y que Rojo construya **tampoco**
acreditan funcionamiento: acreditan corrección estática.

---

## 0. Advertencia de estado

**LAUNCH_READY = FALSE**

Las FASES 0 y 1 están `PASS` porque su evidencia es verificable sin
motor (tests, build, estructura del árbol). Las FASES 2–8 están
**implementadas pero BLOCKED**: nadie las ha ejecutado dentro de Roblox
Studio. Declararlas PASS sería falso.

La checklist reproducible para cerrarlas está en
[`docs/studio-certification.md`](studio-certification.md).

---

## 1. Causa del fallo reportado: el personaje cae al vacío

**Causa real: `src/Workspace` no contenía NINGÚN mapa.** Solo había
carpetas vacías con `.gitkeep`. El lugar compilado tenía cero `Part` y
cero `SpawnLocation`.

Roblox coloca al personaje en el `SpawnLocation` más cercano; si no hay
ninguno, aparece en el origen. Sin suelo, cae indefinidamente.

Lo ocultaban dos fallos adicionales:

1. `ServiceRegistry` leía `GameConfig.Performance.WarnThreshold`, pero
   `GameConfig` no expone `Performance` (vive en `PerformanceConfig`).
2. `Logger.Error` usaba `error(...)`. Como se llama en rutas de control,
   cualquier registro de error abortaba el flujo: **el servidor no
   arrancaba**.

Los tres están corregidos y verificados.

---

## 2. Segunda ronda de corrección (`1bab076` y posterior)

La auditoría del vertical slice encontró **14 bugs reales**. Ninguno era
cosmético: todos habrían roto la partida en Studio.

### Críticos (rompían el juego)

| # | Bug | Efecto en el juego |
|---|---|---|
| 1 | `ApplyDamage` hacía `block:Destroy()` y borraba el origen | `RestoreAll` no tenía nada que reparar: **la arena quedaba vacía para siempre** tras la ronda 1 |
| 2 | `ExplosionService` llamaba a `TakeDamage` directo | Sin invulnerabilidad ni atribución de asesino; `XPPerKill` nunca se usó |
| 3 | `CharacterAdded` ponía `Alive` en cada reaparición | Un muerto volvía a la ronda, **cobraba dos veces** y la ronda no terminaba nunca |
| 4 | Recompensas sin idempotencia | `Rewards` visitado dos veces pagaba dos veces |
| 5 | `SuddenDeath` en el diagrama pero inalcanzable | El multiplicador de daño **nunca** se aplicaba |
| 6 | `PlayerService` llamaba a `GetAliveCount`, que no existía | Crash al morir un jugador |
| 7 | `CombatService` sin registrar en `ServerMain` | Las explosiones no hacían daño a nadie |

### Detectados por las pruebas nuevas

| # | Bug | Efecto |
|---|---|---|
| 8 | `FalloffDamage` devolvía `inf` con daño no finito | Vida del jugador corrompida de forma irreversible |
| 9 | `BlockHealth` 60 = daño de una bomba (120 × 0.5) | **Una sola explosión borraba el bloque entero** |

### Detectados en la segunda auditoría

| # | Bug | Efecto |
|---|---|---|
| 10 | `rescueFromVoid` usaba siempre el spawn del **lobby** | Caer al vacío en la arena teletransportaba 500 studs al lobby: el jugador quedaba "vivo" para `GetAliveCount` y **la ronda no terminaba nunca** |
| 11 | `MovePlayer` sin invulnerabilidad | Muerte injusta al entrar en la arena |
| 12 | `TouchTap` global colocaba bomba | **Cualquier toque** colocaba una bomba; injugable en móvil |
| 13 | HUD con cajas de 12 px y texto de 18 | Texto recortado / ilegible |
| 14 | `ResetRoundCounters` existía pero nunca se llamaba | Kills y muertes acumuladas entre rondas |

Los 8 primeros se corrigieron en `1bab076`; los 6 siguientes, en el
commit posterior de esta sesión.

---

## 3. Clasificación por fase

### PASS (evidencia verificable sin motor)

- **FASE 0** (Bootstrap)
- **FASE 1** (Foundation)

### Implementadas pero BLOCKED (requieren Studio)

- **FASE 2** (Player), **3** (Input), **4** (Bomb), **5** (Explosion),
  **6** (Destruction), **7** (Round), **8** (PvP)

El código existe, está integrado, arranca y compila. **No se ha
observado funcionar dentro de Roblox Studio**, así que no son PASS.

### PARTIAL

- **FASE 12** (XP): la curva de progresión y el cálculo de nivel son
  reales y están probados; la persistencia (DataStore) es la FASE 15.

### NOT IMPLEMENTED

9, 10, 11, 13, 14, 15, 16, 17, 18, 20, 21, 22, 23, 24, 27, 28, 29, 30,
31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 45, 46, 48, 49, 50,
52–64.

---

## 4. Servicios

| Servicio | Estado |
| -------- | ------ |
| WorldService | IMPLEMENTADO — BLOCKED (sin Studio) |
| SpawnService | IMPLEMENTADO — BLOCKED (sin Studio) |
| RoundService | IMPLEMENTADO — BLOCKED (sin Studio) |
| PlayerService | IMPLEMENTADO — BLOCKED (sin Studio) |
| CombatService | IMPLEMENTADO — BLOCKED (sin Studio) |
| DestructionService | IMPLEMENTADO — BLOCKED (sin Studio) |
| ExplosionService | IMPLEMENTADO — BLOCKED (sin Studio) |
| BombService | IMPLEMENTADO — BLOCKED (sin Studio) |
| MatchService | IMPLEMENTADO — BLOCKED (sin Studio) |
| 22 servicios restantes | STUB declarado (Init/Destroy vacíos) |

---

## 5. Remotes

Los 8 `RemoteEvent` existen, están validados y limitados por el gateway.
2 tienen handler real (`BombAction.Place`, `PlayerAction`). 6 están
preparados sin handler: la petición se valida y se descarta.

---

## 6. Evidencia verificada en el repositorio

| Comprobación | Resultado |
|---|---|
| `luau.exe tests/RunTests.lua` | **123 pasan, 0 fallan** (8 suites) |
| `luau-compile --null` (9 KLOC) | **EXIT=0** |
| `rojo build` | **OK** |
| `rojo sourcemap` | **OK** |
| Place compilado | 66 Parts, 6 SpawnLocations, 48 bloques, 8 RemoteEvents, 61 ModuleScripts |

---

## 7. Cómo verificar dentro de Studio

```powershell
.\rojo\rojo.exe serve default.project.json --port 34872
```

Studio → `Plugins` → `Rojo` → `Connect` (34872). Después sigue
[`docs/studio-certification.md`](studio-certification.md), que contiene
los 15 tests (S01–S15), la prueba multijugador, la de seguridad y la de
móvil, con comandos exactos y valores esperados.

Resumen del recorrido esperado:

1. Play. El personaje aparece en el lobby, sobre el suelo.
2. La ronda arranca sola: `Waiting → Countdown → RoundStarting → Playing`.
3. En `RoundStarting` el jugador va a la arena (X = 500).
4. Pulsar **F** coloca una bomba; explota a los 3 s.
5. La bomba destruye bloques y hace daño con caída por distancia.
6. Al morir todos, `RoundEnding → Rewards → ReturningToLobby → Waiting`.

---

## 8. Qué falta para ser un juego real

Monstruos, boss, XP persistente (DataStore), inventario, tienda,
portales a otros mundos, matchmaking real, y todo el bloque de
moderación y live-ops. Está detallado en `docs/phases.md`.
---

## 9. AUDITORIA FINAL (cierre de FASES 0-8 y del vertical slice)

### 9.1 Bug CRITICO encontrado: `BombService.lua` estaba empalmado

**Severidad: CRITICA. Habria hecho fallar S06 (bomba) y S01 (arranque).**

`src/ServerScriptService/BombService.lua` salio del commit `b63c5e2` con
trozos de codigo PEGADOS en el sitio equivocado:

- Las definiciones de `spawnBomb`, `Service.GetPlayerBombCount` y
  `Service.TryPlaceBomb` estaban **dentro del bucle de cadena de
  `detonateBomb`**, no en el nivel superior del archivo.
- El final del bucle (`detonateBomb(nextId, nextDepth)`) aparecia
  DESPUES de esas definiciones.
- El archivo terminaba con un `end` huerfano.

**Por que NO lo detectaron ni el compilador ni los tests:**

El empalmento seguia siendo Luau sintacticamente valido, asi que
`luau-compile --null` devolvia **EXIT 0** (comprobado sobre el archivo
roto extraido de `HEAD`). Los tests unitarios tampoco lo veian: solo
ejercitan logica pura.

**Impacto en ejecucion:** `Service.TryPlaceBomb`, `Service.Init`,
`Service.Start`, `Service.Destroy` y `Service.ClearBombs` nunca se
definían en el nivel superior. `ServerMain` los recibia como `nil`,
`BombService` no arrancaba y **ninguna bomba podia colocarse nunca**.
El juego no era jugable.

**Correccion:** se recompuso el archivo. `detonateBomb` vuelve a cerrar
su bucle de cadena en el sitio correcto (`task.delay` -> `detonateBomb`
-> tres `end`), las funciones vuelven a estar en el nivel superior y se
elimina el `end` huerfano. No se cambio ni una linea de logica.

### 9.2 El detector que faltaba

El fallo era invisible para las dos herramientas que se usaban como
puerta de calidad. Se anaden dos, porque cada una cubre un hueco que la
otra no cubre:

| Herramienta | Que cubre | Por que hace falta |
|---|---|---|
| `tests/shared/ServiceStructure.spec.lua` | El DETECTOR, con ejemplos | `luau.exe` no expone `io`: desde la suite no se pueden leer los fuentes de `src/` |
| `tools/verify-structure.js` | Los ARCHIVOS REALES | Node si puede leerlos y devolver un codigo de salida distinto de cero para CI |

La regla es la misma en ambos: toda `function Service.X` debe estar en
profundidad 0, la profundidad total debe ser 0 y el ultimo codigo debe
ser `return Service`.

**Validacion del detector (no es un test decorativo):**

| Escenario | Resultado esperado | Resultado obtenido |
|---|---|---|
| `BombService.lua` roto (de `HEAD`) | FAIL | **FAIL** (decl. en profundidad 4, ultimo codigo `end`) |
| `BombService.lua` corregido | PASS | **PASS** |
| Otros 8 servicios | PASS | **PASS**, sin falsos positivos |

Durante el desarrollo del propio detector aparecieron tres falsos
positivos que hubo que corregir antes de poder confiar en el:

1. Los ancladores `^` / `$` no funcionan dentro de `gmatch` en este
   Luau: un `(^|x)` al principio de linea no casa nunca y el recuento
   salia **0** para todas las palabras clave, dando por sano cualquier
   archivo. Se sustituyeron por relleno con espacios.
2. `for ... do` y `while ... do` en fin de linea no tenian caracter
   detras del `do`, asi que el `do` se contaba como bloque abierto.
3. Las expresiones `if ... then ... else ...` de Luau no llevan `end`.
   Sin descontarlas, `CombatService`, `MatchService` y demas se
   declaraban corruptos.

### 9.3 Comprobaciones de la lista de auditoria

| Punto | Estado | Evidencia |
|---|---|---|
| `refreshLevel` existe antes de `AddRewards` | OK | `PlayerService.lua:196` frente a `:222` |
| `GetAliveCount` existe | OK | `RoundService.lua:86`, cuenta por `Humanoid` |
| `SuddenDeath` alcanzable | OK | `RoundService.lua:306`, con `GetAliveCount() > 1` |
| `CombatService` registrado | OK | `ServerMain.server.lua:60` |
| `MarkRoundRewarded` ANTES de pagar | OK | `MatchService.lua:177` precede a `AddRewards` en `:184` |
| `FalloffDamage` rechaza NaN / Infinity | OK | `CombatMath.lua:81`, filtra distancia, radio y dano |
| `BlockHealth` conserva el valor corregido | OK | `CombatMath.ApplyBlockDamage` nunca baja de 0 |
| `rescueFromVoid` distingue LOBBY / ARENA | OK | `SpawnService.resolveRescueTarget`: arena si `IsPlaying()`, lobby si no |
| `MovePlayer` protege al entrar | OK | `MatchService.lua:117` concede `SpawnProtectionTime` |
| `TouchTap` NO coloca bombas globales | OK | `InputController.lua:185` exige el toque dentro del boton |
| `ResetRoundCounters` al iniciar ronda | OK | `MatchService.OnRoundStateChanged`, rama `RoundStarting` |
| Sin servicios ni remotos duplicados | OK | 9 servicios, 8 canales = 8 RemoteEvents |

### 9.4 Evidencia de esta ronda

| Comprobacion | Resultado |
|---|---|
| `luau.exe tests/RunTests.lua` | **131 pasan, 0 fallan** (9 suites, antes 123 / 8) |
| `node tools/verify-structure.js` | **PASS**, 9 servicios |
| `luau-compile --null` (74 archivos) | **EXIT=0**, 0 errores |
| `rojo build` | **OK** |
| `rojo sourcemap` | **OK** |
| Contenido del build | 66 Parts, 6 SpawnLocations, 28 bloques `Block_*`, 8 RemoteEvents |

**Nota sobre los bloques:** el contrato real es
`Workspace.Worlds.Forest.Blocks` con prefijo `Block_`, y son **28**
bloques en el build actual (la cifra de 48 del informe anterior no se
reproduce; se documenta la real, que es la que manda). Las carpetas
`DestructibleBlocks` / `IndestructibleBlocks` **no existen**: la
distincion es por prefijo de nombre, no por carpeta.

### 9.5 Lo que sigue BLOCKED

Todo lo que necesita el motor de Roblox. Nada de lo anterior lo
sustituye:

- S01-S15 (arranque, spawn, ronda, bomba, mecha, explosion,
  destruccion, dano, muerte, muerte subita, resultados, retorno,
  segunda ronda)
- Multijugador (Test -> Server & Clients, 2 jugadores)
- Seguridad (10 intentos de explotacion desde el cliente)
- Movil / touch

Las pruebas S01-S15 estan escritas y son reproducibles en
[`docs/studio-certification.md`](studio-certification.md). Hasta que se
ejecuten con evidencia real, el vertical slice sigue **BLOCKED** y
**LAUNCH_READY = FALSE**.
