# Diagnóstico en Roblox Studio

Este documento dice **exactamente qué mirar** dentro de Roblox Studio para
confirmar, o refutar, que el juego arranca.

Hasta que alguien pulse Play y copie la salida, el runtime sigue
**BLOCKED**. Nada de lo que hay en `runtime-audit.md` sustituye a esta
comprobación.

## Preparación

1. Abre `default.project.json` en Studio (**File → Open → Project**), o
   conecta el plugin de Rojo.
2. En una terminal, desde la raíz del repositorio:

   ```powershell
   .\rojo\rojo.exe serve default.project.json --port 34872
   ```

3. En Studio, **Plugins → Rojo → Connect**. Debe aparecer `34872`.

Un HTTP 200 en `http://127.0.0.1:34872` significa que Rojo escucha. **No**
significa que Studio esté sincronizado ni que el juego funcione.

## Ventanas que hay que abrir

- **View → Output**, pestaña **Output** (la del servidor).
- **View → Output**, pestaña **Script** o el conmutador de arriba, para el
  cliente.
- El **Explorer**, para comprobar que el árbol existe mientras corre.

`GameConfig.DebugMode = true` (ya viene así), así que la traza `[BOMB]` y
los `[BOOT]` salen sin tocar nada.

## Qué hacer PRIMERO

No pruebes el juego entero. Sigue esta cadena y para en el primer paso que
falle. Cada paso depende del anterior, y cada paso dice exactamente dónde se
rompió.

### Paso 1 — El servidor arranca

Pulsa **Play** (no Run, no F8: Play, para que haya jugador).

En el Output del **servidor** debes ver, en este orden:

```
[KeshusyTomy-LanD] INFO: KeshusyTomy-LanD v0.1.0 | server starting...
[KeshusyTomy-LanD] INFO: ServiceRegistry: 9 servicios inicializados (...)
[KeshusyTomy-LanD] INFO: [WIRING OK] ExplosionService -> DestructionService, CombatService
[KeshusyTomy-LanD] INFO: [WIRING OK] CombatService -> RoundService, PlayerService
[KeshusyTomy-LanD] INFO: [WIRING OK] BombService -> RoundService, ExplosionService
[KeshusyTomy-LanD] INFO: [WIRING OK] PlayerService -> RoundService, CombatService, MatchService
[KeshusyTomy-LanD] INFO: [WIRING OK] SpawnService -> RoundService, MatchService
[KeshusyTomy-LanD] INFO: [WIRING OK] MatchService -> RoundService, PlayerService, BombService, DestructionService, CombatService
[KeshusyTomy-LanD] INFO: ServiceRegistry: 9 servicios arrancados (...)
[KeshusyTomy-LanD] INFO: RemoteGateway: 8 canales validados (...)
[KeshusyTomy-LanD] INFO: [BOOT] SERVIDOR ARRANCADO
[KeshusyTomy-LanD] INFO: [BOOT] estado del servidor: Running
[KeshusyTomy-LanD] INFO: [BOOT]   BombService       Started
...  (una línea por servicio)
[KeshusyTomy-LanD] INFO: [BOOT] servicios criticos OK (9)
```

**Si falla aquí**, el Output te lo dice solo:

| Lo que ves | Qué significa |
|---|---|
| `[WIRING FAIL] ...` | Falta un servicio: mira el nombre que aparece detrás de `sin`. |
| `[BOOT FAIL] <X> no arranco (estado: ...)` | Ese servicio no superó `Init` o `Start`. Copia el texto exacto. |
| `MatchService: faltan marcadores de destino` | El mapa no llegó a Studio. Recarga el proyecto y comprueba `Workspace.Lobby.LobbyCenter` y `Workspace.Worlds.Forest.ArenaCenter` en el Explorer. |
| `Server initialization aborted. Missing: ...` | Falta `Shared.Config.GameConfig`, `Shared.Constants.GameConstants` o `Shared.Utils.Logger`. |
| `BombService: no se encontro ArenaFloor` | `Workspace.Worlds.Forest.ArenaFloor` no está en su sitio. |

### Paso 2 — El cliente arranca

En el Output del **cliente**:

```
[KeshusyTomy-LanD] INFO: [BOOT] CLIENT_STARTED
[KeshusyTomy-LanD] INFO: [BOOT] CONTROLLERS_REGISTERED (11): ...
[KeshusyTomy-LanD] INFO: [BOOT] CONTROLLERS_STARTED
[KeshusyTomy-LanD] INFO: [BOOT]   InputController  Started
[KeshusyTomy-LanD] INFO: [BOOT]   UIController    Started
...
[KeshusyTomy-LanD] INFO: UIController listo.
[KeshusyTomy-LanD] INFO: InputController listo (F / R2 / toque para colocar bomba).
```

Si no aparece `CONTROLLERS_STARTED`, o si ves
`[BOOT FAIL] CONTROLLERS_REGISTERED = 0`, el árbol de
`StarterPlayerScripts/Controllers` no llegó.
### Paso 3 — El spawn

El personaje debe aparecer en el lobby, sobre uno de los 6 `LobbySpawn*`. En
el servidor verás:

```
[KeshusyTomy-LanD] INFO: #<id> <nombre> conectado. Sesiones activas: 1
[KeshusyTomy-LanD] INFO: PlayerService listo. Jugadores conectados: 1
```

Si el personaje no aparece o cae al vacío, mira si hay
`no hay destino de rescate para <nombre>`.

### Paso 4 — La ronda

`GameConfig.MinPlayersToStart = 1`, así que **no hace falta un segundo
jugador**. En unos 9 segundos (1 `Waiting` + 5 `Countdown` + 3
`RoundStarting`) el HUD debe cambiar de `Waiting` a `Countdown`, y luego a
`RoundStarting`.

```
[KeshusyTomy-LanD] INFO: --- ronda 1 empieza ---
```

**Este es el paso que fallaba antes.** Cuando `MatchService` no se suscribía
a la ronda, el HUD avanzaba de estado pero el personaje **se quedaba en el
lobby**: la ronda existía, el teletransporte no.

El HUD debe mostrar `Ronda: Playing` y el personaje debe estar **en la
arena**, no en el lobby. Mira también el Explorer: el jugador ya no está
cerca del origen, sino a unos 500 studs.

Si la ronda avanza pero el personaje no se mueve, busca en el Output:

```
MatchService: RoundService no inyectado; no habra traslados
```

o

```
MatchService: la suscripcion a los cambios de ronda NO quedo registrada
```

### Paso 5 — La bomba

Solo con la ronda en `Playing`. Pulsa **F** (o **R2** en mando; el botón
táctil solo existe con `TouchEnabled`).

En el Output del servidor, con DEBUG activo:

```
[BOMB] request de <nombre> en (x, y, z)
[BOMB] created id=1 por <nombre> (mecha 3.0s)
[BOMB] fuse agotada, detona la bomba 1
[BOMB] detonate id=1 en (x, y, z) por <id>
```

Debe verse una esfera negra en el Workspace durante 3 segundos y luego
desaparecer con una explosión.

Si **no** sale `[BOMB] request`, el problema es de entrada: el remoto no
llega. Comprueba que `InputController` está en `Started`.

Si sale `[BOMB] request` pero no `[BOMB] created`, lee el motivo:

| Mensaje | Causa |
|---|---|
| `validation fallo: no hay ronda en curso` | No estás en `Playing`. |
| `validation fallo: fuera de la arena X[...] Z[...]` | Estás en el lobby, o los límites se detectaron mal. |
| `validation fallo: fuera de rango (N studs, max 18)` | Demasiado lejos. Acércate. |
| `validation fallo: en cooldown` | 1.5 s entre bombas. Espera. |
| `validation fallo: personaje no jugable` | Sin `Humanoid` o sin vida. |

Los límites de la arena se imprimen al arrancar:

```
BombService: limites de arena X[...] Z[...]
```

Si sale `BombService: no se encontro ArenaFloor; no habra limite de mapa`, el
mapa no está completo en Studio.

**Prueba mínima:** el HUD (`GameHUD`) aparece en la esquina superior
### Paso 6 — La explosión

Con dos bombas cerca, o una bomba junto a un bloque `Block_`, debe verse
`[BOMB] detonate` y los bloques deben volverse transparentes e intangibles
(`CanCollide = false`). Al volver al lobby (`ReturningToLobby`), el mapa se
repara y debe verse `N bloques restaurados`.

### Paso 7 — El daño y la muerte

`CombatService` da 120 de daño base contra 100 de vida, así que una bomba en
el centro mata de un golpe. Los primeros 2.5 s (`SpawnProtectionTime`) el
jugador es invulnerable.

Comprueba que el HUD marca `Vivos: 0` y que el estado de la ronda avanza a
`RoundEnding` → `Rewards` → `ReturningToLobby`.

## Qué Output copiar

Si algo falla, copia **todo** el bloque del Output del servidor desde la
primera línea hasta el final del arranque, incluyendo:

- Todas las líneas `[KeshusyTomy-LanD]`.
- Todas las líneas en **rojo** (excepciones de Luau).
- Todas las líneas con `WARN` o `ERROR`.
- Todas las líneas con `[BOOT]`, `[WIRING` y `[BOMB]`.

Y del Output del cliente, desde `[BOOT] CLIENT_STARTED` hasta
`UIController listo`.

No hace falta el log de errores de producción, ni datos de jugadores: el
Logger no registra ninguno.

## Lo que NO se puede comprobar sin Studio

Queda **BLOCKED** hasta que haya evidencia real:

- Que Roblox acepte los `ModuleScript` y sus rutas de `require`.
- Que el personaje aparezca y la física del mapa sea correcta.
- Que el teletransporte mueva el `Model` completo y no lo deje colgando.
- Que `Humanoid:TakeDamage` mate de verdad y que `Died` se dispare.
- Que el botón táctil aparezca y funcione en un dispositivo real.
- Que la sincronización de Rojo cargue el árbol correcto.

Los 138 tests, `luau-compile`, `rojo build`, `sourcemap` y
`verify-structure` siguen dando luz verde sin tocar nada de esto. Ese es
precisamente el motivo de este documento.
izquierda con `Ronda: Waiting` y abajo `Nivel 1 | XP 0 | Monedas 0`. Si no
aparece, `UIController` no arrancó.