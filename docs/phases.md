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
| 11 | Boss | **PENDING PLAY** | CODIGO NUEVO, sin certificar en PLAY. Antes no existia nada (ver abajo) |
| 25 | VFX / Powerups | **PENDING PLAY** | CODIGO NUEVO, sin certificar en PLAY. Antes era 4 de 8 (ver abajo) |
| 14 | Economy / 15 Inventory / 26 Shop | PASS | ver la tabla de la columna economica |
| 15 | DataStore | HARNESS | logica real; la persistencia real esta bloqueada por el entorno |
| 28 | Quests / 31 Codes | NO INICIADA | stubs honestos |
| 34 | Anti-Exploit | PARCIAL | primera capa real; servicio completo pendiente |

### Auditoria global de gameplay: bombas y muerte de enemigos

Dos bugs de gameplay, **en los cinco mundos**, reproducidos y corregidos.
Ninguno venia del mundo donde se reporto: los dos eran de la clase "el
codigo crecio de una regla sin estado y nadie lo pregunta".

#### BUG 1 -- las bombas solo se colocaban en la zona de arena

**CAUSA REAL, no supuesta.** `BombService.detectArenaBounds` derivaba los
limites de bomba de UNA sola pieza: `ArenaFloor`. Y desde el commit que
convirtio los cinco mundos en mundos con zonas y rutas, `ArenaFloor` dejo
de ser la losa del mundo: paso a ser el suelo de la ZONA DE ARENA, con un
semilado minimo de 34 studs (`tools/worlds.js`, `ARENA_FLOOR_MIN_HALF`).

El mundo son 11 zonas y 19 rutas; la arena es UNA. Todo lo demas caia
fuera del rectangulo y se rechazaba con `OUTSIDE_ARENA`: el spawn, la
entrada, los senderos y la zona del jefe, en Forest, Desert, Ice, Volcano
y Cyber por igual. El sintoma "se coloca en algunas posiciones y en otras
no" era el mapa entero excepto un rectangulo.

Se corrigio en tres capas:

1. `BombPlacementRules` (nuevo, logica pura): el area jugable es la
   **union** del suelo de un mundo, con el mismo margen que
   `WorldBoundsRules`, y solo se rechaza por numero, area o rango.
2. `BombService.detectArenaBounds` lee el suelo real (`Zones/`, `Routes/`,
   `Blocks/`, `ArenaFloor`) y excluye decoracion, `Keshusy`, `Hazards` y
   `Border`: un adorno con `CanQuery` inesperado ya no puede EXPANDIR el
   area jugable (punto 49 de la auditoria).
3. El rayo de asiento se reparo: antes bajaba 20 studs con
   `RespectCanCollide = false` (atravesaba el suelo y podia parar en un
   trigger) y no excluia la carpeta de bombas ni la de monstruos. Ahora
   busca 40 arriba y 80 abajo, solo sobre geometria SOLIDA, y excluye al
   personaje, las bombas y los enemigos por `IsMonsterFolder`.

Lo que NO se hizo: tocar la seguridad. Siguen vigente la autoridad del
servidor, la validacion numerica (NaN/infinito/no-tipo), el rango de 18
studs, el enfriamiento, el tope de bombas por jugador y por mundo, y el
limite del mundo. No se abrio nada de eso "para que la bomba siempre salga".

#### BUG 2 -- enemigos con Health = 0 que seguian vivos

**CAUSA REAL, no supuesta.** La muerte no tenia ESTADO. Habia un unico
`record.Dead`, que se ponia a true DENTRO del manejador de
`Humanoid.Died` y en ningun otro sitio. De ahi salian tres fallos
medibles:

1. Si `Died` no se disparaba, nadie lo comprobaba: el enemigo se quedaba
   con 0 de vida, persiguiendo, golpeando y ocupando el mapa.
2. `ApplyDamageToMonster` escribia `LastDamageSource` **despues** de
   `TakeDamage`, y `TakeDamage` dispara `Died` de forma sincrona: en el
   GOLPE MORTAL el manejador leia al asesino ANTERIOR. El enemigo moria,
   el contador de bajas subia, y el XP no llegaba (o llegaba el de otro).
3. `playDeathVfx` no tenia destroy garantizado: si su hilo fallaba, el
   modelo se quedaba en el Workspace para siempre, y como ya no estaba en
   `_monsters`, nada lo volvia a mirar.

La correccion es una mascara de estados real, `Alive -> Dying -> Dead ->
Cleaned`, en `MonsterDeathRules` (puro, probado sin motor):

- **Atomica**: `EnterDying` concede el derecho a pagar y solo lo concede
  desde `Alive`. Dos golpes simultaneos producen UNA recompensa.
- **Congelacion inmediata**: al morir se anulan `WalkSpeed`, `JumpPower`,
  `AutoRotate`, el objetivo y la patrulla, ANTES de pagar y de animar. Sin
  esto, un enemigo al que una cadena de bombas mata durante su propio
  `Attack` aun podia completar el golpe.
- **Barrido por vida**: `SweepDead` corre en cada latido, FUERA del filtro
  de ronda, y procesa la muerte de cualquier enemigo con `Health <= 0`,
  sin Humanoid o sin modelo. Un `Died` perdido se recupera; uno duplicado
  no hace nada.
- **Cleanup con plazo maximo** (`DEATH_CLEANUP_DEADLINE`): un enemigo que
  no puede morir visible desaparece igualmente.
- `BreakJointsOnDeath = false`: la muerte visible la hace el servicio, con
  plazo, y para eso el modelo tiene que seguir intacto un momento.

Los cinco bosses (Grooty, Sand Beast, Frost King, Magma Lord, Cyber Core)
comparten el MISMO camino de muerte: no hay un ciclo "de jefe" que pueda
quedarse con 0 de vida mientras la fauna no.

#### Estado de la auditoria

| Mundo | Bomb placement | Enemy death | Boss death |
| ----- | -------------- | ----------- | ---------- |
| Forest | PASS (geometria) | PASS (contrato) | PASS (contrato) |
| Desert | PASS (geometria) | PASS (contrato) | PASS (contrato) |
| Ice | PASS (geometria) | PASS (contrato) | PASS (contrato) |
| Volcano | PASS (geometria) | PASS (contrato) | PASS (contrato) |
| Cyber | PASS (geometria) | PASS (contrato) | PASS (contrato) |

`PASS (geometria)` = `tools/bomb-placement-grid.js` acepta las 5x5, los
centros y las esquinas de cada zona, los puntos de cada ruta y los bordes.
`PASS (contrato)` = `tests/shared/MonsterDeath.spec.lua` sobre la mascara
de estados real que usa `MonsterService`.

**GLOBAL GAMEPLAY AUDIT: BLOCKED.**

El estado NO es `READY`, y no por prudencia: es que **el play test no se ha
podido ejecutar**. Studio/MCP no responde (`verify:env` lo dice), asi que
no hay evidencia de que la bomba se vea, de que el enemigo desaparezca en
pantalla ni de que la recompensa llegue. La regla del proyecto es
inegociable: los tests automaticos no certifican el juego en ejecucion.

Lo que queda PENDING PLAY, y es TODO lo que de verdad demuestra el
arreglo: entrar en cada uno de los cinco mundos, colocar bombas en varias
zonas, matar un enemigo normal / en ataque / persiguiendo / con golpes
seguidos / con bomba / con otro sistema, comprobar recompensa y
desaparicion, llegar al boss, matarlo, comprobar su cleanup, morir,
respawnear y reentrar.

#### Pruebas nuevas

- `tests/shared/BombPlacement.spec.lua` (contrato de colocacion).
- `tests/shared/MonsterDeath.spec.lua` (contrato de muerte de enemigos y
  bosses).
- `tools/bomb-placement-grid.js` (rejilla 5x5 en los cinco mundos).
  `npm run test:bomb-grid:legacy` es el **control negativo**: reproduce el
  area jugable antigua (solo `ArenaFloor`, sin margen) y falla en los
  cinco mundos con 78-92 celdas rechazadas. Sin ese control, la rejilla
  solo demuestra que sabe restar.

### Auditoria total 2026-10-04: lo que NO existia y ahora si

Esta seccion no es un plan: son dos huecos que la auditoria encontro
midiendo el SOURCE, no leyendo documentacion. Los dos estaban
"resueltos" en apariencia: habia datos, habia mapa y habia interfaz.

**1. LOS BOSSES NO EXISTIAN.**

Lo que habia:

-   `WorldDefinitions/*.lua` declaraba `BossDefinitionId` en los cinco
    mundos (`ForestGrooty`, `DesertSandBeast`, `IceFrostKing`,
    `VolcanoMagmaLord`, `CyberCore`).
-   `tools/worlds.js` construia la plataforma `BossSpawn_<Id>` en los
    cinco, con su totem, su corona y su suelo.
-   El HUD tenia el panel `Overlays/BossBar`, con nombre y barra.

Lo que NO habia: **ni una definicion de boss**. `MonsterDefinitions`
tenia nueve bichos y ningun jefe. Ningun servicio leia
`BossDefinitionId`. Ningun servicio leia `BossSpawn_<Id>`. Nadie
escribia `BossName`, `BossHealth` ni `BossMaxHealth`.

Consecuencia real: Grooty, Sand Beast, Frost King, Magma Lord y Cyber
Core eran decoracion. El panel de boss del HUD estaba bien construido y
nunca se encendia una sola vez.

Lo que se ha escrito:

-   Cinco definiciones en `MonsterDefinitions` con `IsBoss`, `World`,
    vida de 900 a 3800 y 100 XP.
-   `MonsterScaleRules.BossByWorld` + `GetBossId`: el mapa mundo->boss
    que consume `MatchService`.
-   `MonsterService`: barra de vida publicada SOLO a quien esta en el
    mundo del boss, tres fases (100 % / 60 % / 30 %) que suben el dano
    de 1.0 a 1.5x, y apagado de la barra al morir y al limpiar ronda.
-   `MatchService.SpawnBossForWorld` + `CollectBossSpawnPoint` +
    `UpdateBossSpawns`: el jefe aparece cuando el jugador SE ACERCA a su
    plataforma (70 studs), no al entrar en la arena.

**2. LOS POWERUPS ERAN 4 DE 8, Y UNO DE LOS 4 NO EXISTIA.**

`PowerupService.KINDS` era `{ Bomb, Speed, Shield, Heal }`. Pero:

-   `VisualKit.POWERUPS` tenia **cinco** entradas, con `Fire` incluida.
-   `ApplyEffect` tenia un caso `Fire` COMPLETO, con atributo y duracion.
-   El HUD tenia su `"PODER"` pintado en la fila de efectos.

`Fire` no estaba en `KINDS`, y `KINDS` es la lista que decide que se
GENERA. Es decir: "+PODER" estaba implementado, anunciado y pintado, y
nunca aparecia en el mundo. Ni una prueba fallaba, porque cada capa era
correcta por separado.

Ademas faltaban cuatro de la especificacion: `Dash`, `Ghost`, `Magnet`
y `Freeze`, que no existian en ninguna capa.

Lo que se ha escrito:

-   `KINDS` pasa a los nueve, y pasa a ser la fuente unica.
-   `Dash` (2.5 s a 2.4x), `Ghost` (transparencia 0.85), `Magnet`
    (radio 46, arrastre suave) y `Freeze` (5 s, radio 55) implementados
    con efecto REAL y con su atributo `...Until`.
-   La flecha `PowerupService -> MonsterService` en `ServerMain`: sin ella
    `Freeze` se recogia y no congelaba a nadie.
-   `UIController` lee los cuatro atributos nuevos: antes hacian su
    efecto en el servidor y no se veian en ninguna parte.
-   `VisualKit.POWERUPS` con las cinco entradas nuevas.

**POR QUE NO HAY UN "PASS" DE PLAY EN ESTA SECCION**

Porque no se ha podido ejecutar. El puente MCP de Roblox Studio
(`127.0.0.1:58741`) dejo de escuchar durante la auditoria y no se
recupero: el proceso `RobloxStudioBeta` sigue vivo pero el puerto no
acepta conexiones, y `get_place_info` responde `fetch failed` de forma
reproducible. Sin ese puente no hay `solo_playtest`, ni
`eval_server_runtime`, ni capturas.

Lo que SI se ha comprobado, y es lo que sostiene el codigo nuevo:

-   `npm test`: **715 pasan, 0 fallan**.
-   `npm run verify`: PASS integral, incluido `rojo:build`.
-   `tools/powerup-boss-contract.js`: nuevo, comprueba que los 9 powerups
    generados = pintados = implementados = leidos por el HUD, y que los 5
    bosses estan declarados, generados y con barra en el HUD.
-   `luau-compile` sale 0 en los 8 ficheros editados.
-   `verify:structure` y `verify:wiring`: PASS.
-   `test:worlds`, `test:contract`, `test:navigation`, `test:spawn`,
    `test:world-edge`, `test:monster-access`: PASS en los cinco mundos.

Lo que NO se ha comprobado: que el jefe aparezca, que la barra baje, que
el jugador mate a Grooty y cobre. Eso es `PENDING PLAY` y sigue siendo
`PENDING PLAY` hasta que el puente vuelva.
| P0 | Borde de mundo sin cuadrilatero | PENDING PLAY | codigo y verificadores en PASS; falta PLAY real |

### P0: el borde de mundo sin cuadrilatero (estado real)

El objetivo era quitar el cuadrilatero artificial y dejar el flujo
borde -> caida -> muerte -> respawn -> reentrada. **No se declara PASS**:
lo verificado por codigo esta todo en verde, pero el recorrido completo se
tiene que ver en Roblox Studio.

Lo que se corrigio y por que importa:

| Defecto | Como se manifestaba |
| ------- | ------------------- |
| Muro perimetral de 264-272 piezas `Border_Wall_*` por mundo | El cuadrilatero. Ademas hacia pasar la navegabilidad: el muro es lo que hacia "correcto" el mapa |
| Bordes con `CanCollide = true` | El borde era terreno decorado que ademas frenaba al jugador |
| 13 de 30 spawns de monstruo invalidos | Sin suelo, sin holgura o inalcanzables desde el spawn del jugador |
| Caida teletransportada al punto de salida | El jugador caia, no moria: no habia flujo real |
| Anillos de zona cerrados hacia el vacio | El 48% de la frontera de Forest acababa en muro, y era `Zone_*_Rim_*`, no el borde del mundo |

La ultima fila es la mas instructive. El muro de una zona **de** ser
particion entre dos lugares con puerta; no tiene sentido en el lado por el que
el mundo se acaba. Por eso `zoneRim` construye el arco que mira a una zona
vecina y omite el que mira al vacio.

Verificadores anadidos, todos en PASS y registrados en `npm run verify`:

| Script | Que mide |
| ------ | -------- |
| `npm run test:spawn` | El spawn del jugador: suelo, 20x20 libres, orientacion y sondas |
| `npm run test:world-edge` | Sin cuadrilatero: cero `Border/` colisionable, cero muro perimetral, silueta rellena < 70%, caida alcanzable por N/S/E/O y caida que **mata** en el servidor |
| `npm run test:monster-access` | Cada `MonsterSpawn`: suelo, holgura, ruta andando desde el spawn del jugador y separacion |

`test:world-edge` comprueba tambien, sobre el fuente, que la ruta de caida de
`SpawnService` no hace `PivotTo`: la muerte la ejecuta el motor con
`Humanoid.Health = 0`, y el limite logico (`WorldBoundsRules`) marca pero no
actua.

LO QUE SIGUE SIN PROBAR, Y POR QUE NO ES PASS

- **PLAY real en los cinco mundos.** Entrada, 10 y 30 studs del borde, giro,
  bordes N/S/E/O, caida, muerte, respawn y reentrada. Sin captura, no hay PASS.
- **La muerte y el respawn en ejecucion.** El codigo esta cableado y el
  `analyze` no reporta errores propios, pero que `Humanoid.Health = 0` dispare
  `Died` y que el jugador reaparezca en el spawn de SU mundo es una afirmacion
  que solo se comprueba en el motor.
- **La reentrada.** El mundo se recuerda por el atributo `World` que escribe
  `MatchService.MovePlayer`, y `SpawnService` lo usa cuando la posicion ya no
  dice nada (al reaparecer el personaje nace en el lobby). Ese camino esta
  escrito y razonado, no observado.

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

- **PLAY real del borde de mundo.** Los tres verificadores del P0
  (`test:spawn`, `test:world-edge`, `test:monster-access`) miden geometria y
  fuente, y dan PASS. No sustituyen a correr el juego: que el personaje caiga,
  muera por `Humanoid.Health = 0`, reaparezca en el spawn de SU mundo y se pueda
  reentrar solo se ve en PLAY. Hasta esa captura, el P0 queda PENDING PLAY.

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
