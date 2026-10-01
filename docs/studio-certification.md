# Certificacion en Roblox Studio — FASES 0–8 y Vertical Slice

Fecha de creacion: 2026-10-01
Commit base: `1bab076` (+ correcciones de la sesion de auditoria)

---

## 0. PRINCIPIO INNEGOCIABLE

**Una prueba solo es PASS si alguien la ejecuto en Roblox Studio y
guardo la evidencia.**

Esto NO cuenta como evidencia de funcionamiento:

- que el codigo compile (`luau-compile`)
- que los tests unitarios pasen (`luau.exe tests/RunTests.lua`)
- que `rojo build` termine sin error
- que el `.rbxlx` contenga las instancias correctas
- que el codigo "parezca correcto" al leerlo

Esas comprobaciones acreditan **correccion estatica y de logica pura**.
El juego real —un `Humanoid` que recibe dano, una `Part` que se oculta,
una camara que responde— solo existe dentro del motor de Roblox.

**Estado actual: TODAS las pruebas de este documento estan en BLOCKED
porque aun no se han ejecutado en Studio.**

---

## 1. ESTADO VERIFICADO HOY (sin Studio)

Estas si tienen evidencia, obtenida en este repositorio:

| Comprobacion | Comando | Resultado |
|---|---|---|
| Tests unitarios | `.\tools\luau\luau.exe tests\RunTests.lua` | **123 pasan, 0 fallan** |
| Compilacion Luau | `luau-compile --null` sobre 9 KLOC | **EXIT=0** |
| Build Rojo | `.\rojo\rojo.exe build` | **OK** |
| Sourcemap | `.\rojo\rojo.exe sourcemap` | **OK** |
| Place compilado | inspeccion del `.rbxlx` | 66 Parts, 6 SpawnLocations, 48 bloques, 8 RemoteEvents, 61 ModuleScripts |

Esto demuestra que el proyecto esta **completo y coherente**, no que
funcione dentro del juego.

---

## 2. PREPARACION (comandos exactos)

Ejecutar desde `D:\DevCache\KeshusyTomy-LanD`. Usar **solo** el Rojo
local; no instalar Rojo globalmente.

```powershell
node tools\generate-project.js
.\rojo\rojo.exe build default.project.json --output KeshusyTomy-LanD.rbxlx
.\rojo\rojo.exe sourcemap default.project.json --output sourcemap.json
```

Para live-sync (recomendado durante la certificacion):

```powershell
.\rojo\rojo.exe serve default.project.json --port 34872
```

Luego en Studio: `Plugins` → `Rojo` → `Connect`, puerto `34872`.
Con `serve` NO hay que recargar: cada cambio del repo aparece al vuelo.

### Arbol que debe existir tras sincronizar

| Ruta | Origen | Verificado |
|---|---|---|
| `Workspace` | generador | presente |
| `Workspace.Lobby` (+ `LobbyFloor`, `LobbyCenter`) | generador | presente |
| `Workspace.SpawnLocations` (6) | generador | 6 |
| `Workspace.Worlds.Forest` | generador | presente |
| `...Forest.ArenaFloor`, `ArenaCenter` | generador | 1 cada uno |
| `...Forest.Blocks` (48 `Block_*`) | generador | 48 |
| `ReplicatedStorage.Remotes` (8) | `Remotes.model.json` | 8 |
| `ReplicatedStorage.Shared` | `src/ReplicatedStorage` | presente |
| `ServerScriptService` | `src/ServerScriptService` | presente |
| `StarterPlayer.StarterPlayerScripts` | `src/StarterPlayer` | presente |
| `StarterGui` | `src/StarterGui` | presente |

**Nota sobre `DestructibleBlocks` / `IndestructibleBlocks`:** el
generador **no** crea carpetas con esos nombres. Los bloques
destruibles viven en `Workspace.Worlds.Forest.Blocks` y se identifican
por el prefijo `Block_`. Los indestructibles son las `Part` del mapa que
**no** empiezan por `Block_` (suelo, muros, marcadores). Si la
certificacion espera carpetas con esos nombres exactos, es una
discrepancia de nomenclatura a resolver, no un fallo: el contrato real
es el prefijo, documentado en `DestructionService.BLOCK_PREFIX`.

---

## 3. REGLA DE RELLENO

`Resultado obtenido` y `Evidencia` se rellenan **despues** de ejecutar.
Si no se ha ejecutado, se deja `PENDIENTE` y el estado es `BLOCKED`.

## 4. CHECKLIST DE CERTIFICACION

### S01 — Arranque del servidor

- **Objetivo:** confirmar que el servidor arranca sin errores.
- **Pasos:**
  1. `rojo serve` + conectar Studio.
  2. Command Bar:
     `print(require(game.ServerScriptService.ServerMain).Registry:GetReport())`
  3. Pulsar **Play** y leer el Output completo.
- **Esperado:** `ServiceRegistry: 9 servicios -> ...` y las 9 lineas
  de `GetReport()` en `Started`. Ninguna en `Failed`.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

Orden de arranque esperado:

```
WorldService, SpawnService, DestructionService, RoundService,
CombatService, PlayerService, ExplosionService, BombService,
MatchService
```

> Si `ExplosionService` aparece en `Failed`, el motivo sera
> `sin CombatService`. Ya fue corregido: si reaparece, revisar el
> wiring de `ServerMain.wireDependencies`.

---

### S02 — Spawn

- **Objetivo:** el personaje aparece sobre suelo, no cae al vacio.
- **Pasos:** Play. En Command Bar:
  `print(game.Players:GetPlayers()[1].Character.HumanoidRootPart.Position)`
- **Esperado:** aparece en el lobby sobre `LobbyFloor` (cara superior
  Y = 0). Los `SpawnLocation` estan en Y = 1.6, cerca del origen.
  Existen `Humanoid` y `HumanoidRootPart`. No cae.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

Referencia: los 6 `SpawnLocation` en `(0,1.6,-24)`, `(24,1.6,0)`,
`(0,1.6,24)`, `(-24,1.6,0)`, `(40,1.6,-40)`, `(-40,1.6,40)`.

---

### S03 — Movimiento y camara

- **Objetivo:** controles basicos sin errores ni teletransportes indebidos.
- **Pasos:** WASD, espacio, raton, caminar hasta el borde del lobby.
- **Esperado:** movimiento normal, camara sigue al personaje, sin
  teletransporte del lobby a la arena por error, sin errores nuevos.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

### S04 — Ciclo de ronda

- **Objetivo:** comprobar la maquina de estados completa.
- **Pasos:** Play y observar el HUD durante ~10 s.
- **Esperado, en este orden exacto:**

  `Waiting` → `Countdown` (5 s) → `RoundStarting` (3 s) → `Playing`

- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

En `RoundStarting` el jugador **debe** ir a la arena (X = 500):

```lua
print(game.Players:GetPlayers()[1].Character.HumanoidRootPart.Position)
```

---

### S05 — Arena

- **Objetivo:** la arena es jugable y completa.
- **Pasos:** llegar a la arena e inspeccionar el mapa.
- **Esperado:**
  - `ArenaFloor` presente (180×180, centro X=500).
  - Muros `ArenaWall_*` **indestructibles** (no empiezan por `Block_`).
  - 48 bloques `Block_*` **destruibles**.
  - Marcadores `ArenaCenter`, `ArenaNorth/South/East/West`.
  - Ninguna zona donde el jugador quede atrapado.
  - Ningun punto tira al vacio.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

### S06 — Colocacion de bomba (input)

- **Objetivo:** el input llega al servidor y valida correctamente.
- **Pasos:**
  1. En la arena, pulsar **F**.
  2. Spam del remoto desde el cliente.
  3. Intentar colocar estando en el **lobby** (fuera de ronda).
- **Esperado:**
  - **F** crea una bomba en `Workspace.Bombs`.
  - El servidor RECHAZA el spam por rate limit y por
    `MaxBombsPerPlayer` (5).
  - En el lobby rechaza con motivo `no hay ronda en curso`.
  - El Output registra el motivo de cada rechazo.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

### S07 — Mecha (fuse)

- **Objetivo:** la bomba espera exactamente `DefaultBombFuseTime`.
- **Pasos:** colocar una bomba y cronometrar hasta la explosion.
- **Esperado:** permanece **3 s**, crece visualmente, luego detona.
  Nunca antes. Al detonar, la `Part` desaparece de `Workspace.Bombs`
  (sin instancias huerfanas).
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

### S08 — Explosion

- **Objetivo:** radio, dano, oclusion, cadena y limpieza.
- **Pasos:**
  1. Bomba en el centro de la arena → radio maximo.
  2. Bomba a ~24 studs → el borde no debe danar.
  3. Bomba tras un muro de bloques → el dano debe REDUCIRSE
     (occlusion por raycast, factor 0.25), no ser identico.
  4. Dos bombas a menos de 12 studs → la segunda detona por **cadena**.
- **Esperado:**
  - Dano maximo en el centro = `DefaultBombDamage` = **120**.
  - Cero exacto en el borde del radio (24).
  - Con muro, el dano baja a ~25%.
  - La cadena se produce y respeta `MaxChainDepth` = 6.
  - El VFX se destruye solo tras ~3 s.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

> El VFX usa `ParticleEmitter` sin textura externa, asi que no depende
> de assets que puedan faltar.

---

### S09 — Destruccion de bloques

- **Objetivo:** los bloques reciben dano y la arena se repara.
- **Pasos:**
  1. Bomba junto a un grupo de bloques.
  2. Verificar la vida tras el impacto.
  3. Esperar al final de ronda (`ReturningToLobby`).
  4. Comprobar que la arena vuelve a estar intacta.
- **Esperado:**
  - **Una** bomba NO borra el bloque: `BlockHealth` = 100 y el dano es
    120 × 0.5 = **60**, asi que hacen falta **2** impactos.
  - Tras 2 impactos: `Transparency = 1`, `CanCollide = false`,
    atributo `IsDestroyed = true`.
  - **Sigue presente en el Workspace** (NO se llama a `Destroy()`).
  - Al volver al lobby, `RestoreAll()` lo restaura.
  - Los muros perimetrales **nunca** se destruyen.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

> Este es el bug que motivo el commit `1bab076`. Si tras la ronda 1 la
> arena aparece VACIA, el bug ha regresado.

```lua
local d = game.Workspace.Worlds.Forest.Blocks
local total, destroyed = 0, 0
for _, b in ipairs(d:GetChildren()) do
  total += 1
  if b:GetAttribute("IsDestroyed") then destroyed += 1 end
end
print(total, destroyed)
```

### S10 — Dano al jugador

- **Objetivo:** el dano lo aplica el servidor y respeta las reglas.
- **Pasos:** con 2 jugadores cerca, colocar una bomba junto a uno y
  observar el dano en el otro.
- **Esperado:**
  - El dano lo aplica **el servidor**, nunca el cliente.
  - Caida lineal por distancia: maximo en el centro, 0 en el borde.
  - Invulnerabilidad respetada: `SpawnProtectionTime` = 2.5 s al
    entrar en la arena.
  - El lobby es **zona segura** (`no hay ronda en curso`).
  - Nunca dano infinito ni duplicado (una explosion, un golpe).
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

### S11 — Muerte y recuento de vivos

- **Objetivo:** la muerte se procesa una sola vez y con atribucion.
- **Pasos:** morir de una bomba en la arena.
- **Esperado:**
  - El `Humanoid` muere.
  - `OnPlayerDied` marca `Dead` y suma `Deaths`.
  - `RoundService.GetAliveCount()` baja.
  - Si no queda ninguno, la ronda pasa a `RoundEnding`.
  - **Sin crash** y **sin recompensa duplicada**.
  - El asesino recibe `XPPerKill` (25) y `CoinsPerKill` (10).
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

> El atributo `LastDamageSource` vive en el `Humanoid`, no en una tabla
> global: se limpia al morir para que un reaparicion no herede el
> asesino anterior.

---

### S12 — Muerte subita (Sudden Death)

- **Objetivo:** comprobar que el estado es REAL y alcanzable.
- **Pasos:** dejar correr la ronda hasta el final con 2+ jugadores.
- **Esperado:**
  - Cuando queden `SuddenDeathTime` = **30 s**, se produce la
    transicion real `Playing` → `SuddenDeath`.
  - El dano se multiplica por `SuddenDeathDamageMultiplier` = **1.5**.
  - `SuddenDeath` → `RoundEnding` al agotarse.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio con 2+ jugadores

> **Con 1 solo jugador este test NO se puede ejecutar**: con
> `GetAliveCount() <= 1` la ronda va directa a `RoundEnding`, por
> diseno. Ver S-MP.

---

### S13 — Resultados y recompensa

- **Objetivo:** la ronda paga una sola vez.
- **Pasos:** completar una ronda.
- **Esperado, en orden:**
  `RoundEnding` (3 s) → `Rewards` (4 s) → `ReturningToLobby` (4 s) → `Waiting`
- **Esperado:**
  - Quien sobrevive recibe `+50 XP` y `+25 monedas`.
  - `RoundResult` muestra el texto de recompensa.
  - `MarkRoundRewarded` se escribe **ANTES** de pagar.
  - `XP` / `Coins` / `Level` suben; el nivel se recalcula con la curva.
  - Visitar `Rewards` dos veces NO paga dos veces.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

### S14 — Regreso al lobby y reaparicion

- **Objetivo:** el ciclo se cierra correctamente.
- **Pasos:** tras `ReturningToLobby`, mirar posicion y estado.
- **Esperado:**
  - El jugador vuelve al lobby (`X` cercano a 0, no 500).
  - Vuelve a `Alive`.
  - Puede esperar la siguiente ronda normalmente.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

### S15 — Segunda ronda (sin estado residual)

- **Objetivo:** confirmar que no queda nada de la ronda anterior.
- **Pasos:** forzar el fin de ronda y observar la ronda 2.
- **Esperado:**
  - `Workspace.Bombs` vacia (0 bombas).
  - Los 48 bloques restaurados.
  - `Kills` / `Deaths` a **0** (se reinician en `RoundStarting`).
  - Sin conexiones duplicadas (una muerte = un `Deaths`).
  - La recompensa de la ronda 1 **no** se repite en la ronda 2.
  - Sin errores nuevos en Output.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

## 5. PRUEBA MULTIJUGADOR (S-MP)

Requerida para S12 y para validar PvP de verdad.

- **Pasos:** Test → *Start Server & Players* → 2 clientes (o mas).
- **Esperado:**
  - Ambos aparecen sobre suelo y se mueven.
  - Ambos reciben el estado de ronda correcto.
  - Uno coloca bomba; el otro recibe la explosion.
  - Al morir uno, `GetAliveCount()` baja y el sobreviviente cobra
    `XPPerKill`.
  - La ronda termina cuando queda uno, y ese gana la recompensa.
  - Las recompensas no se duplican para ninguno.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio con varios clientes

---

## 6. PRUEBA DE SEGURIDAD (S-SEC)

Objetivo: demostrar que el cliente NO es autoridad.

| # | Intento | Respuesta esperada del servidor |
|---|---|---|
| 1 | `FireServer("Place", "texto")` | rechaza: `se esperaba Vector3` |
| 2 | `FireServer("Place", Vector3.new(0/0,0,0))` | rechaza: componente no finito |
| 3 | `FireServer("Place", Vector3.new(999999,0,0))` | rechaza: fuera de la arena |
| 4 | Colocar 30 bombas seguidas | `limite de bombas alcanzado` (5) |
| 5 | Colocar en el lobby | `no hay ronda en curso` |
| 6 | Enviar un dano inventado | no existe tal remoto; se ignora |
| 7 | Enviar `XP` / `Coins` | no existe tal remoto; se ignora |
| 8 | Reclamar recompensa dos veces | `MarkRoundRewarded` lo bloquea |
| 9 | Acción inexistente en un canal | `accion invalida` |
| 10 | Canal no registrado | se descarta |
| 11 | Repositionarse por payload | `fuera de rango` / `fuera de la arena` |

- **Esperado ademas:** ningun crash, ninguna economia corrupta
  (los valores no finitos se filtran en `CombatMath.SafeRewardAmount`).
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere Studio

---

## 7. PRUEBA MOBILE (S-MOB)

- **Objetivo:** verificar touch, botones, camara y HUD en movil.
- **Pasos:** emular un dispositivo tactil en Studio, o probar en un
  dispositivo real. Comprobar: joystick de movimiento, boton **BOMBA**,
  salto, camara, y que el HUD no tapa la accion.
- **Esperado:**
  - El boton `BOMBA` (96×96, esquina inferior derecha) solo existe si
    `UserInputService.TouchEnabled`.
  - Solo el toque **dentro** del boton coloca bomba.
  - Tocar fuera del boton **no** coloca bomba.
- **Resultado obtenido:** `PENDIENTE`
- **Evidencia:** `PENDIENTE`
- **Estado:** `BLOCKED` — requiere emulacion o dispositivo real

Resoluciones a comprobar: 375, 390, 430, 768, 1024.

---

## 8. MATRIZ DE ESTADO

Estado HOY, **sin** evidencia de Studio:

| Area | Estado | Evidencia |
|---|---|---|
| Bootstrap | `PASS` | 123 tests, build, sourcemap |
| Foundation | `PASS` | 123 tests, build, wiring verificado |
| Player | `BLOCKED` | implementado; S02/S11 pendientes |
| Input | `BLOCKED` | implementado; S06/S-MOB pendientes |
| Bomb | `BLOCKED` | implementado; S06/S07 pendientes |
| Explosion | `BLOCKED` | implementado; S08 pendiente |
| Destruction | `BLOCKED` | implementado; S09 pendiente |
| Round | `BLOCKED` | implementado; S04/S12/S15 pendientes |
| PvP | `BLOCKED` | implementado; S-MP pendiente |
| Vertical Slice | `BLOCKED` | pendiente S01–S15 |

**LAUNCH_READY = FALSE**

---

## 9. BUGS YA CORREGIDOS QUE DEBEN VERIFICARSE EN STUDIO

Si alguno reaparece, hay una regresión. Todos se detectaron por analisis
o por pruebas unitarias, **no** por ejecucion en Studio.

| # | Bug | Como se manifestaria en Studio | Cobertura |
|---|---|---|---|
| 1 | `RestoreAll` no reparaba | arena vacia tras la ronda 1 | `Destruction.spec` |
| 2 | Sin autoridad de dano | sin invulnerabilidad ni atribucion | revision |
| 3 | Muerto revivia al reaparecer | cobraba 2 veces, ronda infinita | revision |
| 4 | Recompensas no idempotentes | recompensa duplicada | `CombatMath.spec` |
| 5 | `SuddenDeath` inalcanzable | multiplicador nunca aplicado | `CombatMath.spec` |
| 6 | `GetAliveCount` inexistente | crash al morir | revision |
| 7 | `CombatService` no registrado | explosiones sin dano | revision |
| 8 | `FalloffDamage` devolvia `inf` | vida corrompida | `CombatMath.spec` |
| 9 | `BlockHealth` = dano de 1 bomba | arena borrada de un golpe | `Destruction.spec` |
| 10 | Rescate siempre al lobby | ronda infinita | `CombatMath.spec` |
| 11 | Sin invulnerabilidad al entrar | muerte injusta al entrar | `CombatMath.spec` |
| 12 | `TouchTap` global colocaba bomba | bomba en cualquier toque | S-MOB |
| 13 | HUD de 12 px con texto de 18 | texto recortado | S02/S03 |
| 14 | Contadores sin reiniciar | kills acumuladas entre rondas | S15 |

---

## 10. COMO ACTUALIZAR ESTE DOCUMENTO

1. Ejecutar la prueba en Studio.
2. Pegar el fragmento relevante del **Output** en `Evidencia`.
3. Poner el resultado real en `Resultado obtenido`.
4. Cambiar el `Estado` a `PASS` o `FAIL`.
5. Si es `FAIL`: reproducir, corregir, **añadir test de regresion**,
   reejecutar la suite completa, `rojo build`, y volver a probar.
6. Actualizar la matriz de la seccion 8 y `docs/audit.md`.

**Nunca escribir PASS sin evidencia pegada en este archivo.**
---

##Nota previa importante (auditoria final)

Antes de ejecutar S01-S15, se corrigio un bug CRITICO en
`BombService.lua`: las funciones `TryPlaceBomb`, `GetPlayerBombCount`,
`ClearBombs`, `Init`, `Start` y `Destroy` estaban empalmadas dentro del
bucle de `detonateBomb` y nunca se definian en el nivel superior.

**Consecuencia que se veria en Studio:** sin `Service.Start`,
`BombService` no arrancaba; sin `Service.TryPlaceBomb`, el remoto de
bomba no hacia nada. Es decir, **S06 (bomb input) habria fallado con
cooldown, MaxCount y mecha sin funcionar**, y S01 habria mostrado el
error de servicio.

Si al ejecutar ves que la bomba no aparece, comprueba primero que
`BombService: listo.` aparece en el Output. Sin esa linea, el
registro recibio `nil`.

Comprobacion automatica equivalente, antes de abrir Studio:

```powershell
node tools/verify-structure.js
```

Debe imprimir `RESULTADO: PASS` y salir con codigo 0. Si marca un
servicio, el juego NO arrancara aunque el archivo compile.

### Nota sobre el numero de bloques

El mapa tiene **28 bloques** en `Workspace.Worlds.Forest.Blocks`, con
prefijo `Block_`. No existen carpetas `DestructibleBlocks` ni
`IndestructibleBlocks`: la distincion entre bloque destruible e
indestructible es el prefijo de nombre, y la aplicacion la hace
`DestructionService`.

### Nota sobre S12 (muerte subita)

`SuddenDeath` solo se alcanza si `GetAliveCount() > 1`. Con un unico
jugador, `Playing` pasa directamente a `RoundEnding`. **S12 no se puede
marcar PASS en una sesion de un solo jugador**: hay que ejecutarlo en
`Test -> Server & Clients` con 2 jugadores.
