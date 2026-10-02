# Auditoría de integración (runtime real)

Auditoría integral de `KeshusyTomy-LanD` sobre el commit `ec77729`
("fix: repair spliced BombService and add structural regression gate").

## Por qué hizo falta

En `ec77729` el proyecto pasaba todo lo automatizable fuera del motor:

| Comprobación | Resultado |
|---|---|
| `luau.exe tests/RunTests.lua` | 131 passed / 0 failed |
| `luau-compile` sobre los `.lua` de `src/` | exit 0 en todos |
| `rojo build` | Built project |
| `rojo sourcemap` | Created sourcemap |
| `tools/verify-structure.js` | PASS |

Y aun así, al pulsar **Play** en Roblox Studio **no pasaba nada**: el juego
arrancaba sin errores visibles y no hacía nada.

La razón es que ninguna de esas cinco comprobaciones observa el **ciclo de
vida en runtime**. Compilar dice que el código es válido; no dice que
`MatchService.Start` se ejecute después de que `RoundService` exista. Los
131 tests probaban lógica pura (fórmulas de daño, `Maid`, `RateLimiter`,
`RemoteSchema`, estructura de archivos). Ninguno arrancaba el servidor.

## Causa raíz

`ServerMain.Start` hacía, en este orden:

```lua
local started = ServerMain.Registry:Start()   -- Init + Start, en un paso
playerService = ...Registry:Get("PlayerService")
bombService   = ...Registry:Get("BombService")
wireDependencies(ServerMain.Registry)         -- cableado DESPUÉS
```

Dos propiedades del registro lo hacían imposible:

1. `Registry:Get` solo devolvía la instancia si el servicio había pasado por
   `Start`, y `entry.Instance` se asignaba **dentro** de la fase de `Start`.
2. `Registry:Start` ejecutaba `Init` de todos y acto seguido `Start` de
   todos, sin ningún hueco entre medias.

De ahí se seguía esta cadena, que es exactamente "no funciona nada":

- `MatchService.Start` se ejecutaba con `Service._roundService == nil`, así
  que su guarda `if not Service._roundService then return false end` **se
  disparaba y devolvía `false` antes de llegar a la línea de suscripción**.
- Por tanto `Service._roundService.OnStateChanged(...)` **nunca se
  ejecutaba**. Nadie escuchaba los cambios de ronda.
- Nadie se teletransportaba a `Arena`; todos se quedaban en el lobby.
- `BombService.TryPlaceBomb` valida `IsInsideArena(position)`. El jugador en
  el lobby está fuera de `ArenaFloor`, así que **toda** petición de bomba se
  rechazaba con `"fuera de la arena"`.
- Ni la ronda, ni las bombas, ni las explosiones, ni el combate.

El fallo era de **integración**, no de lógica: cada pieza era correcta y
estaba probada, pero ninguna estaba conectada a las demás.

### Bugs secundarios encontrados en la misma pasada

- **Estado compartido en los registros.** `ServiceRegistry.new()` y
  `ControllerRegistry.new()` devolvían `setmetatable({}, Class)`. Como
  `self._entries` se resuelve por `__index` hasta la tabla de clase,
  escribir en `self._entries` **mutaba una tabla compartida por todos los
  registros**. Con un solo registro no se notaba.
- **`_InitService` marcaba `Initialized` antes de llamar a `Init`.** Un
  `Init` que lanzase una excepción dejaba el servicio marcado como bueno y
  la fase de `Start` lo ejecutaba igualmente.
- **`wireDependencies` no reportaba nada.** Cada `if ... then` se saltaba
  en silencio ante una dependencia `nil`.
- **`MatchService.Start` no comprobaba su suscripción.**
- **Avisos degradados donde tocaba error.** `BombService.Start` y
  `CombatService.Start` avisaban con `Warn` de la falta de `RoundService` /
  `ExplosionService` / `CombatService`. Eso es exactamente el fallo que deja
  el juego inservible, y salía en amarillo.
## Correcciones aplicadas

### 1. Ciclo de vida en tres fases (`ServiceRegistry`)

`Registry:Start` se dividió en:

```lua
local initialized = registry:InitAll()
ServerMain.WiringReport = wireDependencies(registry)
local started = registry:StartAll()
```

- `InitAll` resuelve el orden topológico y ejecuta todos los `Init`.
- `entry.Instance` se publica **al superar `Init`**, no en `Start`. Ese es
  el cambio que hace posible cablear entre medias.
- `StartAll` arranca los ya inicializados.
- `Registry:Start` se conserva como atajo `InitAll` + `StartAll`.
- `entry.State` pasa a `Registered` antes de llamar a `Init` y solo se marca
  `Initialized` si `Init` devuelve `true`.

### 2. Cableado con informe (`ServerMain`)

`wireDependencies` recorre ahora una tabla explícita de conexiones y, por
cada una, comprueba que el consumidor y **todas** sus dependencias existen.
Cada salto se registra como `[WIRING OK]` o `[WIRING FAIL]`, y el informe se
imprime siempre. Ya no hay un `if` que se salte en silencio.

### 3. Estado propio por instancia

`ServiceRegistry.new()` y `ControllerRegistry.new()` crean sus propias
tablas `_entries`, `_order` y `_state` / `_isRunning`.

### 4. Verificación de la suscripción (`MatchService`)

Después de `OnStateChanged(...)`, `MatchService.Start` consulta
`RoundService.GetListenerCount()` (método nuevo, lectura pura) y falla con
un error explícito si la suscripción no quedó registrada. Con el bug
original esto da 0 y el arranque lo delata en el Output.

### 5. Diagnóstico de arranque

`ServerMain.GetBootReport()` imprime `[BOOT]` con el estado real de cada
servicio y marca `[BOOT FAIL] <servicio> no arranco` para cualquiera de los
nueve servicios críticos. `ClientMain` hace lo propio con
`[BOOT] CLIENT_STARTED`, `CONTROLLERS_REGISTERED` y `CONTROLLERS_STARTED`,
y ahora **falla** si no se registró ningún controller (antes devolvía `true`
con el mensaje `no hay controllers todavia`).

### 6. Traza de bombas bajo `DEBUG`

`BombService` registra `[BOMB] request`, `[BOMB] validation fallo: ...`,
`[BOMB] created`, `[BOMB] fuse` y `[BOMB] detonate`, todo con
`Logger.Debug`, es decir **solo si `GameConfig.DebugMode` es `true`** (ya lo
es). No hay spam permanente.

## Mapa del proyecto

### Servicios registrados en `ServerMain`

Orden topológico resuelto (dependencias primero):

```
WorldService
  -> SpawnService, DestructionService, RoundService
  -> CombatService
  -> PlayerService
  -> ExplosionService
  -> BombService
  -> MatchService
```

### Controllers del cliente

Cargados por `ControllerRegistry:RegisterAll()` en orden alfabético:

| Controller | Estado | Notas |
|---|---|---|
| AudioController | stub (`IsActive = true`) | Placeholder declarado. |
| BombController | stub | Placeholder declarado. |
| CameraController | stub | Placeholder declarado. |
| EffectsController | stub | Placeholder declarado. |
| InventoryController | stub | Placeholder declarado. |
| InputController | **implementado** | Tecla `F`, `ButtonR2` y botón táctil. |
| MobileController | stub | Placeholder declarado. |
| PartyController | stub | Placeholder declarado. |
| PortalController | stub | Placeholder declarado. |
| ShopController | stub | Placeholder declarado. |
| UIController | **implementado** | HUD por atributos del servidor. |

`InputController` y `UIController` son los únicos con lógica real. Los stubs
devuelven `true`, así que no pueden tumbar el arranque.

`InputController` ya respeta el requisito de no usar `TouchTap` de forma
global: el toque solo cuenta si cae dentro de `bombButton`
(`AbsolutePosition` / `AbsoluteSize`), y `gameProcessed` descarta los toques
consumidos por la UI. El botón se crea solo si
`UserInputService.TouchEnabled`.

### Remotes: modelo fuente vs RBXLX generado vs código que los busca

Verificado **sobre el `.rbxlx` construido**, no solo sobre el JSON:

| Remote | Source | RBXLX | Servidor | Cliente | Match |
|---|---|---|---|---|---|
| PlayerAction | `Remotes.model.json` | `ReplicatedStorage/Remotes/PlayerAction` [RemoteEvent] | `RemoteGateway` (`RequestState`, `SetReady`) | — | OK |
| BombAction | ídem | `.../BombAction` [RemoteEvent] | `BombService.TryPlaceBomb` | `InputController` → `FireServer("Place", Vector3)` | OK |
| ShopAction | ídem | `.../ShopAction` [RemoteEvent] | sin handler (fase 32) | — | OK (inactivo) |
| InventoryAction | ídem | `.../InventoryAction` [RemoteEvent] | sin handler (fase 14) | — | OK (inactivo) |
| QuestAction | ídem | `.../QuestAction` [RemoteEvent] | sin handler (fase 35) | — | OK (inactivo) |
| PortalAction | ídem | `.../PortalAction` [RemoteEvent] | sin handler (fase 18) | — | OK (inactivo) |
| PartyAction | ídem | `.../PartyAction` [RemoteEvent] | sin handler (fase 21) | — | OK (inactivo) |
| SettingsAction | ídem | `.../SettingsAction` [RemoteEvent] | sin handler (fase 31) | — | OK (inactivo) |

El `.rbxlx` tiene **170 instancias** y los 8 `RemoteEvent` están en
`ReplicatedStorage/Remotes`, que es donde los busca el código. Sin mismatches.

### Workspace real (leído del `.rbxlx`)

```
Workspace
├── Environment                       [Folder]   (vacío)
├── Lobby                             [Folder]
│   ├── LobbyCenter                   [Part]    Anchored, CanCollide=false
│   ├── LobbyFloor                    [Part]    Anchored, CanCollide=true
│   ├── LobbyNorth / LobbySouth       [Part]
│   └── LobbyWall_E / _N / _S / _W    [Part]
├── SpawnLocations                    [Folder]
│   └── LobbySpawn1 .. LobbySpawn6    [SpawnLocation]
│                                        Anchored=true, CanCollide=true,
│                                        CanTouch=false, Enabled=true,
│                                        Neutral=true, Duration=0
└── Worlds                            [Folder]
    └── Forest                        [Folder]
        ├── ArenaCenter               [Part]    CanCollide=false
        ├── ArenaFloor                [Part]    CanCollide=true
        ├── ArenaEast                 [Part]
        ├── Blocks/                   [Folder]  Block_1 .. Block_46
        ├── CentralStructure/         [Folder]  Block_47, Block_48
        └── ...                       [Part]
```

Los marcadores que el código busca existen todos:

- `MatchService` necesita `Workspace.Lobby.LobbyCenter` y
  `Workspace.Worlds.Forest.ArenaCenter` → **presentes**. Sin ellos
  `MatchService.Init` devuelve `false` y el juego no arranca.
- `BombService.detectArenaBounds` necesita `ArenaFloor` → **presente**.
- `DestructionService` registra 46 bloques `Block_`.
- `SpawnService.CollectSpawnLocations` encuentra 6 `SpawnLocation`.

`src/Workspace/**` solo tiene `.gitkeep`: el mapa real lo genera
`tools/generate-project.js` y vive en `default.project.json`.

## Flujos cliente → servidor

| Acción | Cliente | Remote | Servidor | Servicio | Respuesta |
|---|---|---|---|---|---|
| Colocar bomba | `InputController` (`F` / `R2` / botón táctil) | `BombAction:FireServer("Place", rootPart.Position)` | `RemoteGateway` valida esquema + rate limit + tipo | `BombService.TryPlaceBomb` revalida ronda, personaje, arena, rango, cooldown y límite | Sin respuesta; el efecto es la bomba en el Workspace |
| Pedir estado | — | `PlayerAction:FireServer("RequestState")` | `RemoteGateway` | `PlayerService.GetSessionFromPlayer` | atributos `Level`, `XP`, `Coins`, `Gems` |
| Marcarse listo | — | `PlayerAction:FireServer("SetReady", bool)` | `RemoteGateway` | `PlayerService.SetReady` | atributo de sesión |
| Estado de ronda | `UIController` lee atributos | — | — | `RoundService` publica `RoundState`, `RoundTimeRemaining`, `RoundNumber`, `AliveCount` | HUD |
| Resultado | `UIController` lee atributos | — | — | `MatchService.GrantRoundRewards` | atributos + `RoundResult` |

El servidor **nunca** espera argumentos que el cliente no envíe, y el
cliente **nunca** espera una respuesta por remoto que el servidor no envíe:
el HUD lee atributos, no eventos.
| Service | Init | Start | Destroy | Dependencias inyectadas | Riesgo runtime |
|---|---|---|---|---|---|
| WorldService | sí | sí | sí | ninguna | Bajo. `LoadWorlds` filtra por `FeatureConfig`. |
| SpawnService | sí | sí | sí | RoundService, MatchService | **Alto**: `rescueFromVoid` decide zona con `roundService.IsPlaying()`. Sin cablear, cae al lobby. |
| DestructionService | sí | sí | sí | ninguna | Bajo. Escanea `Block_` por prefijo. |
| RoundService | sí | sí | sí | ninguna | **Crítico**: es la máquina de estados. Todo cuelga de él. |
| CombatService | sí | sí | sí | RoundService, PlayerService | **Crítico**: única autoridad de daño. |
| PlayerService | sí | sí | sí | RoundService, CombatService, MatchService | **Crítico**: ciclo de vida y recompensas. |
| ExplosionService | sí | sí | sí | DestructionService, CombatService | **Crítico**: sin `CombatService` no hay daño. |
| BombService | sí | sí | sí | RoundService, ExplosionService | **Crítico**: sin `RoundService` no hay bombas. |
| MatchService | sí | sí | sí | RoundService, PlayerService, BombService, DestructionService, CombatService | **Crítico**: sin `RoundService` no hay traslados. |
## Máquina de estados de la ronda

| Estado | Duración | Provoca la salida | Transición |
|---|---|---|---|
| `Waiting` | 1 s | el propio bucle | `Countdown` si hay jugadores; si no, re-sondea en 1 s |
| `Countdown` | 5 s | el propio bucle | `RoundStarting` |
| `RoundStarting` | 3 s | el propio bucle | `Playing` — **teletransporte a la arena** |
| `Playing` | 180 s | el propio bucle | `RoundEnding` si queda ≤1 vivo o se agota el tiempo; `SuddenDeath` si quedan ≤30 s |
| `SuddenDeath` | 30 s | el propio bucle | `RoundEnding` (daño ×1.5) |
| `RoundEnding` | 3 s | el propio bucle | `Rewards` — **se limpian las bombas** |
| `Rewards` | 4 s | el propio bucle | `ReturningToLobby` — **se pagan recompensas** |
| `ReturningToLobby` | 4 s | el propio bucle | `Waiting` — **vuelta al lobby y reparación del mapa** |

Los ocho estados del diagrama son alcanzables. `SuddenDeath` ya lo era antes
de esta auditoría (se corrigió en `1bab076`).

## Spawn

Flujo completo: `Players.PlayerAdded` → `PlayerService.OnPlayerAdded` →
`createSession` → `player.RespawnTime = GameConfig.RespawnTime` →
`bindCharacter` → `CharacterAdded` → `bindHumanoid` (CombatService) →
`OnHumanoidDied` → `PlayerService.OnPlayerDied` →
`RoundService.Transition(RoundEnding)`.

Todos los puntos donde podría haber `nil` están guardados:

- `MatchService.MovePlayer` comprueba `player.Character`,
  `HumanoidRootPart` y `Humanoid` antes de `PivotTo`.
- `CombatService.bindHumanoid` usa `WaitForChild("Humanoid", 10)` y
  desconecta la conexión de `Died` anterior antes de crear la nueva.
- `PlayerService.bindCharacter` conecta `CharacterAdded` **y** invoca el
  handler si `player.Character` ya existe, para no perder a un jugador que
  entra rápido.
- `SpawnService.rescueFromVoid` distingue zona con
  `resolveRescueTarget`: **arena** si `roundService.IsPlaying()` y
  `MatchService` está disponible; **lobby** si no. Este bug ya estaba
  corregido en `b63c5e2`, pero dependía del cableado que estaba roto, así
  que en la práctica siempre caía al lobby.

## Estado de verificación

| Comprobación | Resultado |
|---|---|
| Tests (`RunTests.lua`) | **138 passed / 0 failed** (131 + 7 nuevas) |
| `luau-compile` sobre `src/` | exit 0 |
| `rojo build` | OK, 170 instancias |
| `rojo sourcemap` | OK |
| `verify-structure.js` | PASS, 9/9 servicios |
| `rojo serve` + HTTP | **200 OK** (3857 bytes) |
| **Runtime en Roblox Studio** | **BLOCKED** — requiere que el usuario pulse Play |

`rojo serve` contestando 200 **no** demuestra que Studio esté sincronizado.
El árbol se comparó leyendo el `.rbxlx`, que es la fuente real, pero la
ejecución dentro del motor sigue sin verificarse.

Ver [`studio-diagnostic.md`](./studio-diagnostic.md) para el procedimiento
de comprobación dentro de Studio.

## Herramienta de auditoría

`tools/audit-rbxlx.js` permite inspeccionar el árbol realmente generado,
que es lo que llega a Roblox:

```powershell
node tools\audit-rbxlx.js out.rbxlx
node tools\audit-rbxlx.js out.rbxlx --paths ArenaFloor,Remotes,BombAction
node tools\audit-rbxlx.js out.rbxlx --props ArenaFloor,LobbySpawn1
```

- Sin argumentos: imprime el árbol, la presencia de los objetos críticos y
  la lista completa de nombres con su clase y su cantidad.
- `--paths`: rutas completas donde aparece cada objeto.
- `--props`: propiedades (Position, Size, Anchored, CanCollide...) de los
  objetos indicados.

Se creó durante esta auditoría porque leer `Remotes.model.json` no demuestra
que los `RemoteEvent` existan en el `.rbxlx`, y el `.rbxlx` no demuestra que
Studio lo cargue. Son tres capas distintas y las tres se han comprobado por
separado.

Los 26 `ModuleScript` restantes de `src/ServerScriptService/Services/` son
de fases futuras. **No se registran, no se arrancan y no se deben tocar**
(FASE 9, monstruos, etc.).