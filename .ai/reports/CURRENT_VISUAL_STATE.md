# ESTADO VISUAL ACTUAL

Medido contra el DataModel de Roblox Studio por MCP (`execute_luau`,
`eval_server_runtime`, `eval_client_runtime`), no contra el repositorio ni
contra informes anteriores.

- Fecha: 2026-10-03 (bloque de GAMEPLAY VISUAL: bomba, monstruos, dano, HUD)
- Rojo: 7.7.0 (`rojo/rojo.exe`)
- Studio: conectado, plugin MCP 3.1.6
- SOURCE <-> RUNTIME: `tools/source-runtime-diff.js` = 0 faltantes, 0 sobrantes
- Pruebas: 499/499 PASS
- `rojo build`: OK
- `verify-structure`, `verify-wiring`, `world-contract-verify`: PASS

## BLOQUE VISUAL: QUE ERA UNA CAJA Y AHORA ES UN MODELO

Las tres entidades centrales eran tecnicamente correctas y visualmente
inexistentes. Todo lo de abajo se ha MEDIDO desde el cliente durante PLAY.

| Entidad | Antes (medido) | Ahora (medido desde el cliente) |
| --- | --- | --- |
| Bomba | 1 `Part` Ball 2x2x2 Neon roja, sin fusible, sin tapa, sin radio, sin mecha | `Model` de 7 piezas: `BombBody` 3x3x3 Metal, `BombBand` Neon, `BombTop`, `Fuse`, `FuseGlow` + `PointLight`, `RadiusIndicator` (aro tumbado de 48x0.2x48 = radio real 24), `Attachment` (`ExplosionOrigin`) y `BillboardGui` de mecha. **6 piezas visibles**, cartel leyendo `3`, temporizador real, particulas |
| Monstruo | 1 `Part` 3x3x3 + raiz invisible. Sin ojos, sin nombre, sin vida visible | `Model` con `Root` (`PrimaryPart`), `Body`, `EyeLeft`/`EyeRight`, detalles por bioma (antenas del BombBug, crystal del IceBeast, visor del CyberStalker), `Highlight`, `NameTag` con nombre y barra de vida. **3 a 7 piezas visibles** segun tipo |
| Explosion | 1 `Part` INVISIBLE con 2 emisores | `Model` con `Core` (crece y se apaga), `Shockwave` (cilindro que crece hasta el RADIO EXACTO y se desvanece), luz y dos emisores. Autodestruccion a 0.8 s |
| Powerup | **NO EXISTIA NADA** | `PowerupService` nuevo: 4 por mundo, `Model` con `Core` Neon, `Halo`, luz y cartel (`+BOMBA`, `+VELOCIDAD`, `ESCUDO`, `+VIDA`), flotando y girando |

### Animacion y feedback (medidos en el modelo, no supuestos)

- **Aparicion de la bomba**: escala 0.05 -> 0.45 -> 0.75 -> 1.12 -> 1 (rebote).
  Antes la bomba aparecia estate y luego CRECIA durante la mecha.
- **Mecha visible**: el cartel baja de 3 a 0 en pasos de 0.1 s. En el ultimo
  segundo la bomba parpadea en rojo, el cartel pasa a `!` y las chispas se
  multiplican. El aro de peligro se marca (0.55 -> 0.25 de transparencia).
- **PIEL por mundo**: Forest grafito + banda Keshusy, Desert ocre, Ice azul,
  Volcano rojo, Cyber cian. La bomba comparte mecanica, no apariencia.
- **Aparicion de monstruo**: el cuerpo entra escalandose desde 0.4.
- **Impacto**: destello blanco de 0.08 s + la barra del `NameTag` baja.
- **Muerte**: el cartel y el contorno se borran, el cuerpo se encoge y se
  destruye. Antes `Model:Destroy()` en el mismo frame.

## MCP: YA NO ESTA BLOQUEADO

Este informe antes declaraba `PLAYER = BLOCKED`. **Ya no es cierto.**

| Pieza | Estado | Evidencia |
| --- | --- | --- |
| MCP SERVER | PASS | `127.0.0.1:58741` escuchando, v3.1.6 |
| MCP CLIENT | PASS | `eval_server_runtime`, `eval_client_runtime` responden |
| PLAYER | PASS | jugador real `SiSoyPapito` en sesion |

El bloqueo era que el servidor MCP no estaba arrancado. Se arranca con:

```powershell
npx -y @chrrxs/robloxstudio-mcp@latest
```

## LO QUE ESTABA ROTO Y YA ESTA ARREGLADO

Cuatro defectos. Ninguno se ve leyendo el codigo: los cuatro salen de JUGAR.

### 1. BOM UTF-8 en los cinco `WorldDefinitions`

`require(ReplicatedStorage.WorldDefinitions.Forest)` devolvia:

    Expected identifier when parsing expression, got Unicode character U+feff

Luau no acepta BOM al principio del archivo. Los cinco mundos NO se
registraban, y con ellos se caia toda la cadena:

    WorldService.GetWorldIds()     = ""        (ningun mundo)
    PortalService.CollectPortals() = 0         (ningun portal)
    PortalService.TryEnter         = "portal inexistente"

El lobby tenia cinco portales de geometria y **cero salidas**. Todo lo demas
daba PASS porque nada de eso lo consultaba. Tamben afectados:
`CodeService.lua` y `QuestService.lua`.

Guardia permanente: `tools/ascii-only.js` detecta y quita el BOM y lo cuenta
como pendiente aunque el resto del archivo sea ya ASCII.

### 2. La ronda secuestraba el lobby

`RoundService.hasEnoughPlayers()` contaba `#Players:GetPlayers()`. Con
`MinPlayersToStart = 1`, entrar al servidor lanzaba una ronda de 180 s. Como
`PortalService.CanTravel` rechaza mientras hay ronda, el lobby se quedaba sin
salidas durante casi tres minutos:

    CanTravel Forest = false hay una ronda en curso

Ahora cuenta los jugadores **dentro de una arena**, leidos del atributo `World`
que escribe el servidor en `MatchService.MovePlayer`.

### 3. `UIController._portalHideToken` era `nil` y se incrementaba

`ShowPortalFeedback` reventaba en su ultima linea util:

    UIController:552: attempt to perform arithmetic (add) on nil and number

El cartel se escribia (mundo, nivel, motivo) pero la funcion lanzaba **antes**
de programar el temporizador que lo oculta. Resultado: el `pcall` de
`PortalController` devolvia false, el cartel se quedaba pegado en pantalla
para siempre y el jugador nunca leia el motivo del rechazo. El error estaba
ademas duplicado en `Start`, que lo reiniciaba a `nil`.

### 4. Las bombas no funcionaban en cuatro de los cinco mundos

`BombService.detectArenaBounds()` devolvia el `ArenaFloor` del PRIMER mundo
(Forest, siempre el primero) y lo comparaba contra todos:

    Forest   (500, 0, 0)    -> dentro   -> bomba OK
    Desert   (-400, 400)    -> FUERA    -> "fuera de la arena"
    Ice      (400, 400)     -> FUERA    -> "fuera de la arena"
    Volcano  (-400, -400)   -> FUERA    -> "fuera de la arena"
    Cyber    (400, -400)    -> FUERA    -> "fuera de la arena"

Cuatro de los cinco portales llevaban a una arena donde el jugador no podia
hacer su unica accion. Ahora hay un rectangulo por mundo y la validacion usa
el mundo real del jugador.

## EVIDENCIA DE JUEGO (medida, no supuesta)

Jugador `SiSoyPapito`, teclas reales via `simulate_keyboard_input`.

| Prueba | Resultado |
| --- | --- |
| JOIN | 1 jugador, personaje con vida, `KeshusyHUD` en `PlayerGui` |
| Portal Forest con `E` | `(-32, 3, -28)` -> `(500, 3, 0)`, `World=Forest` |
| Portal bloqueado (nivel bajo) | `requiere nivel 10` / `20` / `35` / `50` |
| Ronda en arena | `RoundStarting` -> `Playing`, 10 s reales sin salir |
| Bomba con `F` | se crea `Bomb` visible en `Workspace.Bombs` |
| Mecha | 3 s -> `detona` -> 120 de dano -> limpieza sola |
| Destruccion | 2 bombas (60 de dano c/u contra 100) -> `IsDestroyed=true` |
| Monstruos | `Slime`, `BombBug`, `Shadow` creados en la arena |

Los cinco mundos, con entrada, spawn y alcance de bomba:

| Mundo | Entra | `World` | Spawn | Dentro de arena |
| --- | --- | --- | --- | --- |
| Forest | SI | Forest | (500, 3, 0) | SI |
| Desert | SI (nivel 10) | Desert | (-400, 3, 400) | SI |
| Ice | SI (nivel 20) | Ice | (400, 3, 400) | SI |
| Volcano | SI (nivel 35) | Volcano | (-400, 3, -400) | SI |
| Cyber | SI (nivel 50) | Cyber | (400, 3, -400) | SI |

## LO QUE SIGUE SIN ESTAR

- **Sin capturas de pantalla del juego en marcha.** `capture_screenshot` dice
  `StudioCaptureService cannot capture this DataModel right now`: captura el
  editor, no el viewport del cliente. La certificacion VISUAL sigue pendiente.
- Las bombas siguen exigiendo ronda `Playing`: es correcto (evita placing en el
  lobby), pero significa que la ronda debe estar viva para jugar.
- Inventory y Shop siguen siendo stubs de 31 lineas.
- El HUD muestra los datos del servidor, pero `Misiones: --` porque `QuestService`
  no publica ese atributo al HUD.
- `tools/analyze.js`: FAIL preexistente.

GAME STATUS = **NOT READY** (ver bloque de gameplay visual mas abajo)
## LOS TRES DEFECTOS QUE NO SE VEEN LEYENDO EL CODIGO

Ninguno se descubre leyendo: salen de JUGAR y de MIRAR el cliente.

### 1. Los monstruos NUNCA aparecian (P0: cuatro por ronda, cero en pantalla)

`MonsterService.Spawn` buscaba `model:FindFirstChild("HumanoidRootPart")`.
El modelo del monstruo lo construye `VisualKit` y su raiz se llama `Root`, asi
que la busqueda devolvia `nil`, el modelo se destruia y el spawn terminaba:

    MonsterService: el modelo construido no tiene PrimaryPart/Humanoid.

Cuatro monstruos por ronda, cero monstruos en pantalla, sin un solo error de
sintaxis y con todas las pruebas en verde. Ahora se usa `model.PrimaryPart`,
que es el CONTRATO del modelo y no un nombre literal.

### 2. Los monstruos persiguian dejando el cuerpo clavado

La IA movia `record.RootPart.CFrame`. `Body` es HERMANO de la raiz, no hijo, y
se quedaba en el sitio: el enemigo corria con una estela de cuerpos parados.
Medido en la misma ronda, antes y despues de corregirlo:

    antes:  Slime (525,17)   BombBug (475,-17)   Shadow (517,-25)
    ahora:  Slime (522,15)   BombBug (479,-14)   Shadow (513,-19)

Ahora se mueve el MODELO entero con `PivotTo` y se orienta hacia el objetivo,
para que los ojos miren a donde va.

### 3. El lobby tiene cinco portales repartidos en X, no uno en el centro

Los umbrales estan en `X = -32, -16, 0, 16, 32` y cada uno pertenece a un
mundo. El de Forest esta en `(-32, 4.75, -34)`, NO en el centro del lobby.
Ponerse en el centro y esperar que el portal de Forest funcione falla SIEMPRE
por distancia, y eso no es un portal roto: es estar en el portal equivocado.
Cada mundo:

| Mundo | Umbral del portal | Nivel | Arena |
| --- | --- | --- | --- |
| Forest | (-32, 4.75, -34) | 1 | (500, 3, 0) |
| Desert | (-16, 4.75, -34) | 10 | (-400, 3, 400) |
| Ice | (0, 4.75, -34) | 20 | (400, 3, 400) |
| Volcano | (16, 4.75, -34) | 35 | (-400, 3, -400) |
| Cyber | (32, 4.75, -34) | 50 | (400, 3, -400) |

## FEEDBACK DE DANO Y HUD (medido en el cliente)

`EffectsController` era un stub de 25 lineas. Ahora, medido desde el cliente
durante PLAY:

| Prueba | Resultado medido |
| --- | --- |
| Dano al jugador | vida 100 -> 65, aparece el numero flotante **`-35`** |
| Contenedor `DamageNumbers` | existe en el `ScreenGui` generado |
| Borde `DamageVignette` | existe, rojo, se desvanece solo |
| Barra de vida | `relleno=0.65` tras el dano, por TWEEN de 0.25 s |
| Panel `ActiveBombs` | existe, oculto con 0, muestra `x1` con una |
| Panel `PowerupRow` | existe, muestra `ESCUDO` / `VELOCIDAD` / `PODER` |
| HUD completo | `MUNDO: Forest`, monedas `0`, objetivo `Forest`, timer `00:01` |

La barra de vida ahora se ANIMA. Antes el ancho saltaba de golpe y el impacto
del dano se perdia: el jugador veia "estaba al 80 y ahora al 20" sin ningun
instante intermedio.

### Donde NO se solapan los paneles

El boton tactil de bomba que crea `InputController` ocupa `(1, -32)` con
96x96. `ActiveBombs` se coloco a su IZQUIERDA (X [-260, -140]) para que el
contador de bombas activas no tape el control que coloca bombas. Un HUD que
tapa el boton es un HUD roto.

## LO QUE SIGUE SIN ESTAR

- **Sin capturas de pantalla del juego en marcha.** `capture_screenshot`
  responde `StudioCaptureService cannot capture this DataModel right now`:
  captura el editor, no el viewport del cliente. La certificacion visual POR
  IMAGEN sigue pendiente; la certificacion por MEDIDA del DataModel del
  cliente (lo que hay en este informe) no depende de una captura.
- **Sin audio.** `AudioConfig` tiene todos sus IDs en `nil` porque no hay
  ficheros de audio en el repositorio. El sistema esta completo y en silencio
  a proposito: no se inventa ningun `assetId`.
- **Movil y gamepad**: no hay prueba real de disposicion.
- **Powerups a medio efecto**: `Bomb` sube el contador y `Speed` sube la
  velocidad (los dos medidos en el atributo). `Shield` publica su atributo pero
  `CombatService` todavia NO reduce el dano, y `Fire` publica el suyo pero la
  bomba no lee el multiplicador. Visibles y creibles; el efecto mecanico de
  esos dos queda pendiente.
- Inventory y Shop siguen siendo stubs.
- `Misiones: --` porque `QuestService` no publica ese atributo al HUD.
- `tools/analyze.js`: FAIL preexistente.

GAME STATUS = **NOT READY**

No por falta de jugabilidad: la bomba, los monstruos, los powerups, la
explosion, el dano y el HUD son VISIBLES y medibles desde el cliente. Quedan
audio, disposicion (movil y mando), dos efectos de powerup por conectar a su
mecanica, y las capturas del juego en marcha.
