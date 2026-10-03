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
| 14 | Economy / 15 Inventory / 26 Shop / 28 Quests / 31 Codes | NO INICIADA | stubs honestos: 19 servicios sin implementar |
| 33 | DataStore / 35 Security / 47 Monetization | NO INICIADA | `DataService` y `AntiExploitService` son declaraciones de interfaz |

### Servicios sin implementar (19 de 33)

No es un defecto oculto: son stubs que declaran `Init`/`Destroy` y nada mas.
`tools/runtime-probe.js` los cuenta en runtime, no por opinion:

AnalyticsService, AnnouncementService, AntiExploitService, BadgeService,
CodeService, DataService, EconomyService, EventService, InventoryService,
MatchmakingService, ModerationService, MonetizationService, PartyService,
ProfileService, ProgressionService, QuestService, ReportService, ShopService,
TeleportService.

Ninguno tiene metodos de dominio. Hasta que se implementen, economia,
persistencia, tienda y anti-exploit **NO existen** aunque sus archivos esten.

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

### Lo que sigue bloqueado

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
