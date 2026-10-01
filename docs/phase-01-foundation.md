# FASE 1 - Foundation

## STATUS

```text
PASS        (logica pura y build verificados)
BLOCKED     (Roblox Studio: requiere ejecucion manual)
```

## FILES CREATED

```text
src/ReplicatedStorage/Shared/Config/PerformanceConfig.lua
src/ReplicatedStorage/Shared/Config/FeatureConfig.lua
src/ReplicatedStorage/Shared/Libraries/Maid.lua
src/ReplicatedStorage/Shared/Libraries/RateLimiter.lua
src/ReplicatedStorage/Shared/Libraries/StateMachine.lua
src/ReplicatedStorage/Shared/Libraries/RemoteSchema.lua
src/ServerScriptService/Systems/ServiceRegistry.lua
src/ServerScriptService/Systems/RemoteGateway.lua
src/ServerScriptService/Services/SpawnService.lua
src/StarterPlayer/StarterPlayerScripts/Controllers/ControllerRegistry.lua
tests/TestHarness.lua
tests/RunTests.lua
tests/shared/Maid.spec.lua
tests/shared/RateLimiter.spec.lua
tests/shared/StateMachine.spec.lua
tests/shared/RemoteSchema.spec.lua
tests/shared/GameConfig.spec.lua
```

## FILES MODIFIED

```text
src/ReplicatedStorage/Shared/Config/GameConfig.lua
src/ReplicatedStorage/Shared/Constants/GameConstants.lua
src/ServerScriptService/ServerMain.server.lua
src/ServerScriptService/Services/PlayerService.lua
src/ServerScriptService/Services/RoundService.lua
src/ServerScriptService/Services/WorldService.lua
src/StarterPlayer/StarterPlayerScripts/ClientMain.client.lua
```

## FUNCTIONALITY

### ServiceRegistry

- Registro unico por servidor, instanciado desde `ServerMain`.
- Orden topologico iterativo (Tarjan) a partir de `dependencies`.
- Ciclo de vida `Init` -> `Start` -> `Destroy`, cada uno con `pcall`.
- Un servicio que falla NO detiene a los demas: el servidor queda en
  modo degradado y lo reporta.
- Un `Maid` por servicio: se limpia aunque `Destroy` falle o no exista.
- Apagado en orden inverso, idempotente y sin bloquearse.

### ControllerRegistry

- Equivalente cliente del registro de servicios.
- `RegisterAll` carga los `ModuleScript` de `Controllers`.
- Fallo aislado por controller; `StopAll` en orden inverso.

### RemoteGateway (seguridad)

Toda peticion remota pasa por esta cadena, en orden:

1. El servidor acepta trabajo (`_isRunning`).
2. El emisor es un jugador conectado, verificado contra `Players`.
3. El canal esta registrado.
4. La accion existe en el esquema.
5. La frecuencia es aceptable: token bucket por
   `userId:canal.accion`.
6. La forma del payload coincide con el tipo declarado.

Solo entonces se ejecuta el handler, tambien dentro de `pcall`.

- Los rechazos se registran con ventana de 60 s, para no inundar la
  consola si un cliente hace spam.
- Los limites de un jugador se borran al salir (evita fuga de memoria).
- Los 8 canales quedan registrados y validados **sin handlers**: las
  peticiones se descartan de forma segura hasta que su fase exista. No
  se declararon funciones vacias que aparenten funcionar.

### RemoteSchema (logica pura)

- Mapa canal -> accion -> tipo de payload.
- `ValidatePayload` filtra forma y rango, nunca permisos.
- `ValidateVectorComponents` aísla la regla de rango de posicion para
  poder probarla con numeros simples.

### Maid

- `Add` / `Remove` / `Connect` / `Delay` / `DoCallbacks` / `Destroy`.
- Libera funciones, hilos, tablas, Instances y conexiones.
- `Destroy` es idempotente y continua limpiando aunque un cleanup falle.
- `Add` posterior a `Destroy` libera el recurso de inmediato (sin fuga).

### RateLimiter

- Token bucket por clave, con reloj inyectable (pruebas deterministas).
- Tolera rafagas cortas y frena el abuso sostenido.
- `Reset` por clave y `Clear` global.

### StateMachine

- Transiciones declarativas: lo no declarado se rechaza.
- Estados terminales, `Stop`, `Reset`, historial y hooks desregistrables.

### Servicios

- **WorldService**: carga solo los mundos habilitados por
  `FeatureConfig`; expone disponibilidad, nivel requerido y
  `CanEnterWorld`.
- **RoundService**: diagrama de ronda explicito basado en `StateMachine`;
  rechaza transiciones invalidas.
- **SpawnService**: descubre `SpawnLocation` y reparte por rotacion
  determinista. El servidor decide la posicion.
- **PlayerService**: sesion en memoria, handlers idempotentes de
  entrada/salida, atributos para la interfaz, `SetPlayerState` y
  `SetReady`. **No persiste**: eso es la FASE 15.
## TESTS

```text
Ejecutar desde la raiz del repositorio:
luau.exe tests/RunTests.lua

Passed: 56
Failed: 0
Blocked: 0
```

| Suite        | Pruebas | Que verifica                                     |
| ------------ | ------- | ------------------------------------------------ |
| Maid         | 9       | idempotencia, cleanup, error en callback         |
| RateLimiter  | 10      | rafaga, saturacion, regeneracion, costes         |
| StateMachine | 13      | transiciones validas/invalidas, terminal, reset  |
| RemoteSchema | 12      | formas, rangos, NaN, inyeccion, tablas gigantes  |
| GameConfig   | 12      | limites positivos, flags, versiones              |

### Bugs reales encontrados por estas pruebas

Las pruebas no se escribieron despues del codigo: lo encontraron.

1. `Maid` guardaba desde indice 0, por lo que `#cleanups` era 0 y
   `Destroy` no liberaba nada.
2. `Maid:Remove` nunca encontraba el recurso por un `-1` residual.
3. `StateMachine` tenia parametros `self` duplicados en cuatro metodos.
4. `Maid` usaba `typeof`, inexistente fuera del motor de Roblox.
5. Interfaz inconsistente (`.` frente a `:`) entre `Maid` y sus pruebas.
6. `GetDuration` de `RoundService` tenia una rama inalcanzable.
7. `RemoteGateway` uso `typeof` sobre un argumento que no lo es.
8. Syntax error por un `end` sobrante tras un reemplazo parcial.

## ROJO

```text
.\rojo\rojo.exe build -o test.rbxlx
Building project 'KeshusyTomy-LanD'
Built project to test.rbxlx
ROJO: PASS
```

Sintaxis verificada en todos los `.lua` con `luau-compile`:
`ALL LUA FILES COMPILE OK`.

## ROBLOX STUDIO

```text
BLOCKED
```

Cline no puede ejecutar Roblox Studio. Lo siguiente **no** esta
verificado en motor y debe comprobarse manualmente:

1. `.\rojo\rojo.exe serve` y conectar el plugin de Rojo.
2. Play en Studio y confirmar en la consola:
   - `ServiceRegistry: 4 servicios -> ...`
   - `RemoteGateway: 8 canales validados (...)`
   - `RoundService listo. Estado inicial: Waiting`
   - `PlayerService listo. Jugadores conectados: 1`
   - `SpawnService: N puntos de aparicion encontrados`
3. Confirmar que `Workspace.Worlds` y `Workspace.SpawnLocations`
   existen; si faltan, el juego avisa y continua.
4. Cerrar el servidor y confirmar
   `todos los servicios detenidos`.

## PERFORMANCE

- Sin trabajo por frame en esta fase: no hay `Heartbeat`.
- Sin bucles sin condicion de salida.
- Los buckets del rate limiter se liberan al salir el jugador.
- Cada servicio tiene su propio `Maid`: limpieza garantizada.
- Limites y umbrales de aviso centralizados en `PerformanceConfig`.

## SECURITY

- El cliente no decide nada. XP, monedas, compras, dano y recompensas
  aun no existen, y los remotos ya filtran emisor, accion, frecuencia
  y forma del payload.
- `ENABLE_MONETIZATION = false` en desarrollo, verificado por prueba.
- Sin datos personales ni tokens en los logs.

## BUGS

Ninguno conocido en codigo.

## KNOWN LIMITATIONS

- `PlayerService` no persiste: al salir se pierde la sesion (FASE 15).
- `RoundService` no tiene temporizadores ni logica de ronda (FASE 7).
- `WorldService` no construye mapas ni arenas (FASES 6 y 19).
- El lobby es solo una carpeta vacia (FASE 17).
- El nivel del jugador es fijo en 1 hasta que exista progresion
  (FASE 12), por lo que la comprobacion de nivel aun no tiene efecto.
- Los 8 remotos validan y descartan; ningun handler de negocio actua
  todavia. Es intencional, no un descuido.

## GIT

```text
Commit: feat: implement phase 1 foundation
```

## NEXT PHASE

```text
FASE 2 - Player System
```

CharacterService, estados vivo/muerto, reaparicion, escudo,
atributos y sesion temporal conectada a `PlayerService`.