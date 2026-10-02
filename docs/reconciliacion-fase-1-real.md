# RECONCILIACION FASE 1 REAL

Fecha: 2026-02-10
Rama: `main`, commit base `f2461a7`

Este documento NO hereda conclusiones de informes anteriores. Todo lo que
se afirma aqui se obtuvo de (a) lectura del codigo actual del repositorio,
(b) ejecucion de la suite local y del build de Rojo, y (c) diagnostico del
puente MCP. Cuando no se pudo comprobar en runtime, se dice `BLOCKED` y no
se inventa un veredicto.

---

## 0. Veredicto de partida

El informe anterior declaraba un PASS de `RoundService`. Ese PASS es real y
sigue en pie. **No dice nada del juego**, y la razon de fondo es concreta:

> 198 pruebas passing prueban logica PURA. El camino del jugador
> (`tecla -> controller -> remoto -> gateway -> servicio -> runtime`) no
> estaba certificado, y al inspeccionarlo resulto que una pieza de esa
> cadena no existia.

---

## 1. Inventario real (codigo actual)

### 1.1 Servicios del servidor (33)

**Implementados de verdad (13)** — logica real, tamano consistente:

| Servicio | Bytes | Nota |
| --- | --- | --- |
| `RoundService` | 24750 | ciclo de ronda, verificado por pruebas |
| `VisualService` | 22372 | mapa, luces, portales visibles |
| `PlayerService` | 19410 | sesion, XP, monedas, nivel |
| `BombService` | 16185 | colocacion, mecha, cadena, limites |
| `CoreService` | 16165 | nucleo del lobby |
| `PortalService` | 16062 | viaje entre mundos |
| `MonsterService` | 14691 | spawn e IA de monstruos |
| `MatchService` | 13617 | entrada/salida de arena |
| `ExplosionService` | 11721 | radio, dano, destruccion |
| `CombatService` | 10841 | dano y muerte |
| `SpawnService` | 7769 | puntos de aparicion |
| `DestructionService` | 7101 | bloques y vida |
| `WorldService` | 6262 | deteccion de arenas |

**Stubs: interfaz declarada, cuerpo vacio (20).** Todos con exactamente el
mismo tamano (~820 bytes), que es la firma de un archivo generado con solo
`Init`/`Destroy` que devuelven `true`:

`PartyService`, `CodeService`, `EconomyService`, `QuestService`,
`TeleportService`, `ReportService`, `ProfileService`, `MonetizationService`,
`ShopService`, `EventService`, `AnnouncementService`, `MatchmakingService`,
`AntiExploitService`, `InventoryService`, `BadgeService`, `AnalyticsService`,
`DataService`, `ModerationService`, `ProgressionService`.

**Esto invalida cualquier afirmacion previa sobre DATA, ECONOMY, INVENTORY,
SHOP, QUEST, PARTY, PROGRESSION, SEASON, BOSS, POWERUPS, MONETIZACION,
RANKINGS, MISSIONS y EVENTS.** Esos sistemas no existen. `DataService.lua`
son 835 bytes y su unica logica es `Service.IsInitialized = true`.

### 1.2 Controllers del cliente (12)

**Implementados (4):** `AudioController` (8777), `ControllerRegistry`
(7444), `InputController` (7205), `UIController` (6381).

**Stubs (8), mismo patron de ~825 bytes:** `PartyController`,
`BombController`, `ShopController`, `PortalController`, `MobileController`,
`EffectsController`, `CameraController`, `InventoryController`.

### 1.3 Canales remotos (9 declarados, 4 con handler)

| Canal | Handler en `ServerMain` | Estado |
| --- | --- | --- |
| `PlayerAction` | `SetReady`, `RequestState` | real |
| `BombAction` | `Place` | real |
| `PortalAction` | `Enter` | real |
| `CoreAction` | `Interact`, `RequestState` | real |
| `ShopAction` | **vacio** | sin handler |
| `InventoryAction` | **vacio** | sin handler |
| `QuestAction` | **vacio** | sin handler |
| `PartyAction` | **vacio** | sin handler |
| `SettingsAction` | **vacio** | sin handler |

`RemoteSchema` DECLARA acciones para esos canales vacios (`Shop.Preview`,
`Shop.Purchase`, `Inventory.Equip`, `Quest.Claim`, `Party.Create`...). El
gateway las acepta, las limita y las descarta con un `Debug`. Es el
comportamiento correcto y honesto, pero significa que la UI de tienda, si
se abriera, no compraria nada.

### 1.4 UI

`src/StarterGui/UI/` contiene unicamente `README.md`. **No existe HUD.**
---

## 2. El defecto P0 encontrado

`InputController` resolvia `BombAction` y ejecutaba `FireServer` por su
cuenta, mientras `BombController` era un stub de 826 bytes.

La cadena real era:

```
Tecla -> InputController -> Remote -> Servidor
```

y la cadena documentada era:

```
Tecla -> InputController -> BombController -> Remote -> Servidor
```

Diferencia concreta: `BombController` **no existia como realidad**. Eso
importa por una razon que no es de estilo. Una prueba que quisiera
verificar "el jugador puede colocar una bomba" no tenia ninguna funcion
del cliente que ejecutar. Solo existia una llamada directa al servicio en
el servidor, que es justo el camino que la fase prohibe declarar como PASS.

Segundo defecto, de UX: el boton de bomba solo se creaba con
`UserInputService.TouchEnabled`. En PC no habia ninguna forma VISIBLE de
colocar una bomba.

---

## 3. Estado del puente MCP: BLOCKED

Diagnostico, sin matar ningun proceso:

- `RobloxStudioBeta` PID 73620: **activo** desde 11:32.
- Token de autenticacion: **presente** en `~/.robloxstudio-mcp/auth-token`.
- `Get-NetTCPConnection -State Listen` para los puertos 58741/58742/58743:
  **cero resultados**.
- Puertos en escucha del propio PID de Studio: **ninguno**.
- `node tools/studio-mcp.js list` -> `FALLO: fetch failed`.

**Conclusion.** Studio esta abierto, pero el componente que expone el
puente MCP **no esta escuchando**. El plugin/bridge de Studio no se
inicio. No es un problema de permisos, de puerto ocupado ni de un proceso
colgado, y no se puede resolver desde fuera de Studio.

Por tanto, en esta tanda **no se pudo arrancar ninguna sesion de Play**.
Todo lo que dependa de runtime real queda `BLOCKED`, y se marca asi.

Lo que si se pudo ejecutar, y paso:

```text
luau tests/RunTests.lua          216 pruebas, 0 fallos, 15 suites
rojo build default.project.json  OK
luau-compile --only-parse       OK en los 9 archivos tocados
tools/verify-structure.js       33 servicios, PASS
tools/verify-wiring.js          PASS
```

---

## 4. Lo que se implemento en esta tanda

Objetivo acotado: **cerrar el P0 de entrada** (secciones 2, 3, 5 y 6 del
encargo), que es el bloque del que dependen todos los demas.

1. **`BombController` real.** Envia por `BombAction`, aplica freno local de
   spam y expone `GetCooldownRemaining`, `CanRequest` y `GetState` para el
   HUD. No decide nada de negocio: no comprueba ronda, arena ni distancia.

2. **`InputController` reencuadrado.** Traduce dispositivo -> intencion y
   delega en `BombController`. Teclado (F), mando (R2), boton y toque
   desembocan en **la misma funcion**. Esto es lo que hace que la prueba
   del reproductor signifique algo: no es un camino paralelo, es el mismo.

3. **Boton de bomba en todos los dispositivos**, no solo tactiles, con
   `MouseButton1Click` del propio boton (se degrada el `TouchTap` global a
   simple respaldo) y contador de cooldown visible cada 100 ms.

4. **`TestDriverLogic`** (logica pura, 18 pruebas): que instrucciones
   existen, cuales se rechazan, y el intervalo minimo entre ejecuciones.
   Una prueba comprueba explicitamente que la lista de instrucciones NO
   contiene ninguna via hacia un servicio.

5. **`ClientTestDriver.client.lua`**: LocalScript real. Recibe una
   instruccion por atributo y ejecuta
   `InputController.RequestBombPlacement()`, que recorre controller ->
   remoto -> gateway -> validacion -> rate limit -> `BombService`.
   **No puede llamar a ningun servicio**: `ServerScriptService` no es
   accesible desde el cliente. Esa imposibilidad es la garantia.

6. **`TestDriverService`**: lado servidor. Fija el atributo y lee el
   veredicto del cliente. No ejecuta nada del juego.

7. **`ENABLE_CLIENT_TEST_DRIVER`**, apagado por defecto. En produccion el
   reproductor no hace nada.

---

## 5. Lo que SIGUE sin certificar

Todo lo siguiente sigue `BLOCKED` o `NO IMPLEMENTADO`. En ningun caso se
declara PASS:

| Sistema | Estado real |
| --- | --- |
| `CLIENT INPUT PATH` | implementado, **BLOCKED** (falta sesion de Play) |
| HUD completo | NO IMPLEMENTADO (solo el boton de bomba) |
| Portales desde el jugador | `PortalController` es stub: el jugador no puede usarlos |
| Tienda / Inventario / Misiones / Party / Temporada | NO IMPLEMENTADO (stubs) |
| Data / Profile / Persistencia | NO IMPLEMENTADO (stub) |
| Economy / Progression / Season / Boss / Powerups | NO IMPLEMENTADO |
| Mundos Desert, Ice, Volcano, Cyber | solo `WorldDefinition`, sin contenido |
| PvP con 2 jugadores | BLOCKED (sin Play) |
| Mobile / Gamepad | BLOCKED EXTERNAL |
| 10/25/50/100 partidas | NO EJECUTADAS |

---

## 6. Bugs abiertos

1. **`PortalController` es un stub.** El servidor tiene `PortalAction.Enter`
   funcionando y `PortalService.HandleEnter` implementado, pero **nada en
   el cliente llega a dispararlo**. El jugador no puede entrar en Forest.
   Es el siguiente P0.
2. **El esquema declara acciones sin handler** en Shop, Inventory, Quest y
   Party. No es un bug (el gateway las descarta bien), pero si se construye
   la UI sin implementar el servidor, la UI mintira al jugador.
3. **No hay HUD.** `UIController` existe pero no hay nada que dibujar.
4. **La ronda depende de `MinPlayersToStart = 1`** en `GameConfig`, lo que
   significa que el ciclo arranca solo y nunca ha sido probado con la
   condicion real de "dos jugadores".

---

## 7. Orden de trabajo propuesto

El siguiente bloque debe ser `PortalController`, por el mismo motivo que
este: el servidor ya funciona y el cliente nunca lo invoca. Con el,

```
Jugador -> interaccion -> PortalController -> PortalAction
        -> PortalService -> nivel -> mundo -> teletransporte -> spawn
```

y despues, en este orden: HUD, Data/Profile (con prueba real de
salir/volver), Economy, Inventory, Shop.

Ningun PASS global es posible hasta que la lista de la seccion 30 del
encargo este completa. A dia de hoy, de esos 21 bloques, hay **0** en PASS.
No hay HP, ni bombas, ni XP, ni monedas, ni nivel, ni temporizador. El
unico elemento de interfaz real es el boton de bomba que crea
`InputController` en tiempo de ejecucion.