# Fases de desarrollo

Regla fundamental: **no se pasa a la siguiente fase si la actual no funciona.**

Cada fase debe: implementarse, integrarse, probarse, corregirse, volverse a
probar, documentarse y recibir commit. Estados validos: `PASS`, `FAIL`, `BLOCKED`.
Nunca "casi terminado", "deberia funcionar" ni "probablemente funciona".

| Fase | Nombre          | Depende de |
| ---- | --------------- | ---------- |
| 0    | Bootstrap       | -          |
| 1    | Foundation      | 0          |
| 2    | Player          | 1          |
| 3    | Input           | 2          |
| 4    | Bomb            | 3          |
| 5    | Explosion       | 4          |
| 6    | Destruction     | 5          |
| 7    | Round           | 2          |
| 8    | PvP             | 7          |
| 9    | Monsters        | 7          |
| 10   | AI              | 9          |
| 11   | Boss            | 10         |
| 12   | XP              | 7          |
| 13   | Economy         | 12         |
| 14   | Inventory       | 2          |
| 15   | DataStore       | 2          |
| 16   | Worlds          | 7          |
| 17   | Lobby           | 16         |
| 18   | Portals         | 16         |
| 19   | Matchmaking     | 7          |
| 20   | Party           | 19         |
| 21   | UI              | 2          |
| 22   | Mobile          | 21         |
| 23   | Gamepad         | 3          |
| 24   | Audio           | 21         |
| 25   | VFX             | 21         |
| 26   | Shop            | 13, 14     |
| 27   | Monetization    | 26         |
| 28   | Quests          | 14         |
| 29   | Battle Pass     | 13, 21     |
| 30   | Achievements    | 12         |
| 31   | Codes           | 13         |
| 32   | Badges          | 30         |
| 33   | Moderation      | 15         |
| 34   | Anti-Exploit    | 2          |
| 35   | Analytics       | 15         |
| 36   | Live Ops        | 26         |
| 37   | Performance     | 25         |
| 38   | QA              | 37         |
| 39   | Beta            | 38         |
| 40   | Release         | 39         |

## Estado actual

Ultima verificacion con evidencia en **PLAY real** (`Solo Playtest`, 1 cliente
conectado), no por lectura de archivos.

| Fase | Nombre | Estado | Evidencia |
| ---- | ------ | ------ | --------- |
| 0 | Bootstrap | PASS | `phase-00-bootstrap.md` |
| 1 | Foundation | PASS | arranque limpio: 14 servicios, 9 canales, `fetch-logs` = 0 errores / 0 avisos |
| 2 | Player | PASS | personaje, vida, reaparicion y traslado a arena medidos en PLAY |
| 3 | Input | PARTIAL | arquitectura DEVICE->CONTROLLER->REMOTE existe; la **pulsacion** real de teclado/tactil NO verificada (peers cliente dan timeout) |
| 4 | Bomb | PASS | `tools/bomb-e2e.js`: colocacion -> mecha -> explosion -> dano, medido |
| 5 | Explosion | PASS | `Detonate` afecta 4-5 partes y baja un bloque de 100 a 40 |
| 6 | Destruction | PASS | 48 bloques registrados, dano real aplicado |
| 7 | Round | PASS | ciclo completo y **repetido**; `_stallCount = 0` en regimen |
| 9 | Monsters (PvE) | PASS | 4 monstruos generados por ronda, detectan y hacen dano |
| 14 | Economy / 15 Inventory / 26 Shop | PASS | ver la tabla de la columna economica |
| 15 | DataStore | HARNESS | logica real; la persistencia real esta bloqueada por el entorno |
| 28 | Quests / 31 Codes | NO INICIADA | stubs honestos |
| 34 | Anti-Exploit | PARCIAL | primera capa real; servicio completo pendiente |

### Columna economica: que se certifico y como

Evidencia recogida en **PLAY real** con un jugador de verdad
(`SiSoyPapito`), no por lectura de archivos. Sonda: `node tools/economy-cert.js`.

| Sistema | Estado | Evidencia medida en runtime |
| ------ | ------ | --------------------------- |
| EconomyService | PASS | `grant +1000` deja saldo 1000; el mismo `requestId` repetido deja 1000 |
| Ledger | PASS | traza encadenada `before -> after`; `AuditPlayer` = 0 problemas |
| InventoryService | PASS | compra -> item en inventario -> equipar; equipar sin poseer = rechazado |
| ProgressionService | PASS | 500 XP cruzan **3 niveles de golpe** (1 -> 4); recompensas 150/200/250 pagadas |
| ShopService | PASS | compra pagada 500 y item entregado; 2a compra = `already_owned` **sin cobrar** |
| ProfileService | PASS | perfil cargado al entrar y atributos publicados |
| DataService | **HARNESS** | ver abajo |

**Lo que NO se declara PASS, y por que:**

- **Persistencia real = HARNESS, no PASS.** `DataStoreService` no funciona en
  un lugar sin publicar: "You must publish this place to the web to access
  DataStore". Es una limitacion del ENTORNO, no del codigo. Se verifico con un
  harness (`tools/probes/persistence-harness.lua`) que instala un almacen
  SIMULADO en el `DataService` REAL y recorre sus rutas de verdad: carga,
  guardado, recuperacion, autosave que solo escribe lo sucio, rechazo de
  perfil ilegible, rechazo de perfil no serializable (con 0 escrituras), fallo
  de escritura que deja el perfil sucio y reintentable, bloqueo de sesion
  (propio aceptado, ajeno rechazado, vencido aceptado) y normalizacion de un
  perfil con forma antigua conservando el saldo.
  Lo que el harness **no** demuestra: que el DataStore real acepte esos datos.

- **MODO SIN PERSISTENCIA en Studio.** `DataService.Start` degrada a memoria
  con aviso explicito si no puede abrir el DataStore. El juego se juega igual;
  lo que no se guarda es el perfil. Nunca se dice "guardado" si no se guardo.

- **UI de economia, inventario y tienda: NO INICIADA.** Los servicios publican
  el estado por atributo, pero no hay pantallas. Las **cantidades** por item y
  las definiciones completas requieren `InvokeClient`, que es fase de UI.

- **AntiExploitService completo: NO INICIADA.** Hay una primera capa real
  (validacion de forma en el remoto, rate limit y rechazos registrados por
  nombre de jugador), no el servicio completo.

### Servicios sin implementar (13 de 33)

Quedan stubs que declaran `Init`/`Destroy` y nada mas.
`tools/runtime-probe.js` los cuenta en runtime, no por opinion:

AnalyticsService, AnnouncementService, AntiExploitService, BadgeService,
CodeService, EventService, MatchmakingService, ModerationService,
MonetizationService, PartyService, QuestService, ReportService,
TeleportService.

Los seis de esta fase (Data, Profile, Economy, Inventory, Progression, Shop)
ya NO estan en esa lista: arrancan en runtime con `Start = si`.

### Defectos P0 corregidos en esta ronda

1. **La ronda no respetaba su reloj.** El bucle consultaba `decideNextState`
   en cada rebanada de 0.25 s sin mirar si el plazo habia vencido. Con un solo
   jugador la regla "si queda un vivo, se acaba" era cierta desde el primer
   instante de `Playing`, asi que la ronda terminaba de inmediato. Medido:
   ronda 1369 paso de `Waiting` a `Rewards` en menos de 15 s con
   `RoundDuration = 180`, y el historial acumula 1400+ rondas en minutos.
   El juego era **injugable**: no habia tiempo ni para una bomba.

2. **Falsa alarma de atasco.** El vigilante comparaba el tiempo total desde el
   inicio del estado contra el margen. Con los plazos ya respetados, los 180 s
   reales de `Playing` se contaban como atasco en CADA ronda. Se midi el
   `grace` (tiempo vencido sin transicionar) y se reinicia al cambiar de estado.

3. **El jugador se quedaba en el lobby durante la ronda.** `PlayerService`
   preguntaba `IsPlaying()`, que es falsa en `RoundStarting`, y mandaba al
   lobby lo que `MatchService` acababa de llevar a la arena. El log lo repetia
   en cada ronda: `movido a Arena` seguido de `movido a Lobby`. Se anadio
   `RoundService.IsRoundActive()`, que cubre `RoundStarting`, `Playing` y
   `SuddenDeath`. `SpawnService` tenia el mismo error en el rescate.

### Pruebas que habian dado FAIL sin defecto real

- `tools/bomb-chain.js` exigia derribar un bloque con UNA bomba. El balance
  declara 2 (120 de dano, bloque de 100 de vida, 50% de escala). La prueba
  estaba mal, no el juego.
- `tools/bomb-e2e.js` media un bloque concreto por nombre que podia estar a
  44 studs, fuera del radio de 24. Ahora cuenta cuantos bloques reciben dano.

### Defectos encontrados al CERTIFICAR la columna economica

Todos se encontraron ejecutando el juego, no leyendo el codigo. Ninguno
habria salido con `luau-compile`, `rojo build` ni los tests unitarios.

1. **`DataStoreService.GetDataStore` con punto en vez de dos puntos.**
   `Expected ':' not '.' calling member function GetDataStore`. El `Start`
   devolvia false, `DataService` quedaba en `Failed` y el perfil de NADIE se
   cargaba: economia a cero y compras rechazadas con `no_profile`.

2. **El perfil nunca se cargaba, aunque el servicio arrancara.** Los seis
   servicios de la columna eran locales de `wireDependencies`, que es una
   FUNCION: al terminar, `ServerMain.Start` y los handlers de los remotos veian
   `nil`. El perfil no se cargaba y los remotos de tienda e inventario salian
   sin hacer nada, sin un solo error rojo.

3. **`SetAttribute` con un diccionario.** El inventario se publicaba como
   `{ Cure_Potion = 3 }` y Roblox lanza "Dictionary is not a supported attribute
   type". Pasaba DESPUES de cobrar: el jugador pagaba y se quedaba sin item.

4. **Lo mismo con un array.** El arreglo anterior (publicar un array de ids)
   fallo con "Array is not a supported attribute type". Los atributos solo
   admiten escalares, asi que ahora viaja una cadena.

5. **Punto donde debia haber dos puntos sobre una instancia de reglas.**
   `Progression.GetLevel(estado, curva)` hacia que `self` fuera el estado del
   jugador en vez de la instancia, y dentro reventaba con
   "attempt to call missing method 'GetXP' of table".

6. **La forma del perfil no era la que esperaba la economia.** `NewProfile`
   creaba `Currencies = { Coins = 0 }` y `EconomyRules` espera
   `{ Balances = {...}, Sequence = 0 }`. Toda operacion economica se rechazaba
   con "estado de economia invalido" y el jugador tenia saldo cero para
   siempre, sin error visible. Ahora hay una sola forma y un
   `NormalizeSections` que repara perfiles viejos conservando el saldo.

7. **La compra repetida devolvia "ya lo tienes" en vez del resultado
   original.** `Validate` se ejecutaba antes de mirar el registro de compras,
   asi que un reintento tras perder la conexion cobraba bien pero mostraba un
   error al jugador. Ahora el registro se consulta PRIMERO.

8. **El XP repetido volvia a pagar la subida de nivel.** `AddXP` devolvia el
   resultado guardado tal cual, con `levelsGained = 1`, y quien llamara pagaria
   dos veces. Ahora devuelve una copia con `levelsGained = 0` y `Replayed`.

9. **Hueco en la auditoria del ledger.** `FindBalanceMismatch` solo comparaba
   entradas contiguas, asi que editar el saldo DESPUES de la ultima transaccion
   pasaba desapercibido. Ahora compara el saldo actual con el `balanceAfter` de
   la ultima transaccion de cada moneda.

### Lo que sigue bloqueado

- **Persistencia real.** Requiere el lugar publicado para que
  `DataStoreService` funcione. En Studio el juego corre en MODO SIN
  PERSISTENCIA, avisado en el log. La logica se certifico con harness.

- **Cliente MCP**: `client-1` agota el tiempo de espera. Es infraestructura, no
  juego. Por eso la fase 3 (input) queda PARTIAL y no PASS: la arquitectura
  esta cableada, pero la pulsacion fisica no se ha podido observar.

## Formato de reporte de fase

```text
PHASE:
STATUS:            # PASS | FAIL | BLOCKED
FILES CREATED:
FILES MODIFIED:
FUNCTIONALITY:
TESTS:
BUGS:
RESULT:
NEXT PHASE:
```

`LAUNCH_READY = TRUE` solo cuando exista evidencia de que el juego
funciona realmente en Roblox Studio y supero las pruebas correspondientes.
