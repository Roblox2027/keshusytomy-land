# Defectos encontrados verificados en runtime

Fecha: 2026-10-02 (iteracion 2: identidad visual)
Alcance: fallos detectados ejecutando el juego en Roblox Studio, no leyendo el
codigo. Todos estan corregidos y comprobados con evidencia de ejecucion.

Este documento existe porque la leccion se repite: **los dos fallos mas graves
que se han encontrado en este proyecto eran invisibles para cualquier
comprobacion de source**. El codigo se leia bien, compilaba, y todas las
pruebas locales pasaban.

---

## Principio: una comprobacion que no puede fallar es peor que no tenerla

Tres herramientas de este repositorio llegaban a informar "PASS" sin poder
detectar el fallo que decian detectar:

| Herramienta | Que informaba | Por que mentiala |
| --- | --- | --- |
| `sync-scripts.js` (antes) | "ya iguales: 63" | Comparaba 300 caracteres. La cabecera de cada archivo es identica antes y despues de cualquier cambio, asi que siempre coincidia. Seis divergencias reales quedaron ocultas. |
| `source-runtime-diff.js` | "PASS, 271 = 281" | Compara recuento y nombre. Las 162 Parts pueden estar todas apiladas en `(0,0,0)` y el informe sigue diciendo PASS: los nombres coinciden. |
| `boot-state.js` (antes) | "31 servicios no arrancados" | Leia `res.IsStarted`, un campo que ningun servicio publica. Daba `nil` para todos y hacia fallar la puerta con un servicio que si habia arrancado. |

La regla que se aplica desde entonces: **si una comprobacion no puede detectar
el fallo que dice detectar, no vale como puerta**. Por eso existe ahora
`verify-geometry.js` (mide posiciones, no nombres) y el sincronizador informa
de lo que no pudo verificar en vez de darlo por bueno.

---

## P0 - `import_rbxm` pierde todas las posiciones

**Sintoma.** El lobby entero estaba apilado en el origen. Las 98 Parts de
`Workspace.Lobby` tenian `Position = (0,0,0)`, mientras la arena, declarada en
el mismo archivo, conservaba las suyas.

**Causa.** No era una sola, y menos la evidente:

1. `sync-workspace.js` cortaba el subarbol en el primer `>` del `<Item>`, de
   modo que el bloque `<Properties>` del Workspace quedaba pegado al Folder
   envoltorio. El `.rbxm` llevaba **dos `<Properties>` en un mismo `<Item>`**:
   XML invalido que Studio acepta aplicando solo lo que entiende.
2. `merge-workspace.lua` buscaba un envoltorio llamado `Workspace`, pero el
   Folder raiz del `.rbxm` se llama `WorkspaceSource`. La fusion se salia
   entera y el arbol importado se quedaba colgando, duplicado.
3. `dedupe-workspace.lua` conservaba la instancia equivocada al fusionar
   homonimos, llevandose por delante la geometria bien situada.

**Aislamiento.** `tools/build-probe-rbxm.js` genera un `.rbxm` de **una sola
Part** con XML bien formado y `Position (123, 45, -67)`. Tambien se importa en
`(0,0,0)`. La perdida ocurre dentro de Studio y no depende del mapa, del
generador ni del corte de `<Properties>`.

**Correccion.** Las posiciones se vuelven a colocar despues de importar, desde
`default.project.json`, que sigue siendo la fuente unica
(`tools/apply-map-positions.js`). Y `verify-geometry.js` mide si cada Part
esta donde debe, que es justo lo que el recuento de instancias no veia.

**Verificacion.** 162/162 Partes en su sitio.


---

## P0 - `RateLimiter` reventaba en su primer uso real

**Sintoma.** `attempt to call a nil value` en `RateLimiter.lua:61` la primera
vez que se consumia un token.

**Causa.** `TryConsume`, `GetTokens`, `Reset` y `Clear` se declaraban como
**metodos** (`function self.X(self, ...)`) pero **todos** los llamantes los
invocaban con **punto**: `travelLimiter.TryConsume(userId)` en `PortalService`,
y `self._limiter.TryConsume/Reset/Clear` en `RemoteGateway`.

Con punto, el primer parametro declarado recibe el argumento en lugar de la
instancia: dentro de `TryConsume`, `self` era la clave (un string) y `key` era
`nil`, asi que `self.clock()` era `(string).clock()`.

**Por que nadie lo habia visto.** `RateLimiter.spec` invoca el modulo con dos
puntos, que si funciona. El primer consumidor real por punto fue el remoto de
portales, durante el vertical slice.

**Alcance.** `RemoteGateway` es la puerta de entrada de **todos** los remotos
del juego, y sus tres llamadas fallaban igual. El rate limiting de la
seguridad estaba roto desde el origen.

**Correccion.** `resolveReceiver` normaliza el receptor: si el primer
argumento es la propia instancia, la llamada fue con dos puntos; si no, fue con
punto y ese argumento era la clave. Ambas convenciones funcionan. No se
cambiaron los llamantes, porque eso dejaria la trampa puesta para el
siguiente que escriba `limiter.TryConsume(k)`.

**Verificacion.** Con punto y con dos puntos, la misma secuencia
(`si,si,si,no,no,no` con capacidad 3), claves independientes aisladas y reloj
inyectado repoblando de forma determinista.

---

## P1 - La comprobacion de integridad de escrituras daba falsos negativos

Al anadir una comprobacion post-escritura a `sync-scripts.js`, esta fallo con
"escritura incompleta: Studio tiene 300 lineas y el disco 534" en seis
archivos.

**Diagnostico.** No era una escritura truncada: era la **lectura** la que esta
truncada. `get_script_source` devuelve como maximo 300 lineas y lo marca con
`truncated: true`.

**Correccion.** La comparacion pasa a ser de prefijo, y los casos truncados se
**informan** en vez de darse por buenos, porque el final de esos archivos no
queda verificado. La comprobacion de "ya esta al dia" tambien distingue: con
lectura truncada reescribe siempre.

---

## P1 - La puerta de `ReplicatedStorage.Config` era un falso positivo

`runtime-tree.js` exigia `ReplicatedStorage.Config` y lo reportaba como
incumplimiento. Se comprobaron los 13 modulos que cargan configuracion
(`ServerMain`, los servicios con config, `ServiceRegistry`, `Logger`,
`ControllerRegistry`): **todos** hacen `SHARED:WaitForChild("Config")`. Ninguno
pide `ReplicatedStorage.Config`.

El contrato estaba mal escrito y reportaba como rotura algo que ningun codigo
necesita.

---

## P1 - `GameConfig.lua` tenia dos cabeceras

El archivo tenia dos bloques de comentario y **dos directivas `--!strict`**
concatenadas. La segunda se ignoraba con el aviso "Comment directive is
ignored because it is placed after the first non-comment token", de modo que
parte del archivo creia estar en modo estricto y la otra no.

Ademas los dos bloques describian el mismo modulo con textos distintos.

---

## Nota sobre como se diagnostico

Dos de estos fallos se diagnosticaron **mal** al principio, y conviene
dejarlo escrito:

- Se sospecho de `RateLimiter.new` y de una captura de upvalue, cuando el
  problema era la convencion de llamada. Lo que lo resolvio fue escribir un
  reproductor fuera de Roblox (`luau.exe`) que probara seis variantes,
  incluida la comparacion punto/dos puntos.
- Se sospecho de `BombService._bombFolder` corrupto por un error que decia
  `AddChild is not a valid member of Folder`. El codigo era correcto; el
  puente bloquea ese metodo. Un control con un Folder nuevo y con
  `Parent = ...` lo demostro.

En ambos casos el dato decisivo no fue leer mas codigo, sino **construir la
prueba minima que separase las dos hipotesis**.

---

# P0 - El mundo no emitia NADA de luz: 0 luces, 0 particulas, 0 sonidos

**Sintoma.** El lobby existia (98 Partes), el Core existia (15 Partes) y los
cinco portales existian (7 Partes cada uno). Y aun asi, al darle PLAY, lo que
se veia era un mapa de cajas: exactamente el fallo que el diseno prohibe.

**Medicion en runtime** (no lectura de codigo), con `eval_server_runtime`:

| Que se midio | Antes | Despues |
| --- | --- | --- |
| Luces en el mundo | **0** | **35** |
| `Sparkles` | **0** | **6** |
| GUI 3D (`SurfaceGui`/`BillboardGui`) | **0** | **5** |
| `Ambient` / `OutdoorAmbient` | `0.274` / `0.274` (iguales) | `0.27,0.31,0.41` / `0.59,0.62,0.69` |
| Niebla | ninguna (`FogEnd` 100000) | `FogStart` 180, `FogEnd` 900 |
| Portales con nombre visible | 0 de 5 | 5 de 5 |

**Causa.** El mapa se generaba con Partes `Neon`, que NO emiten luz: `Neon` es
solo un material. Ademas `Lighting` estaba en los valores de Studio por defecto,
con `Ambient` identico a `OutdoorAmbient`, que es exactamente la combinacion que
aplana el relieve. Y los portales eran siete cajas de color sin una sola letra:
el jugador no podia saber a donde llevaba cada uno ni que nivel exigia.

**Correccion.** Nuevo `VisualService`, que anade PRESENTACION en runtime:
`PointLight` en farolas, stations, Core, portales y arena; `Sparkles` en el
nucleo y los portales; `SurfaceGui` + `TextLabel` con nombre y nivel en cada
portal; y una configuracion de `Lighting` con ambiente diferenciado y niebla
suave. El Core pulsa y sus dos anillos giran.

**Por que en runtime y no en `default.project.json`.** El pipeline de
sincronizacion importa el mapa con `import_rbxm`, y esa via pierde las
posiciones de todas las Partes (el P0 de mas arriba). Anadir hijos no-BasePart
al JSON los meteria por ese mismo camino. La GEOMETRIA sigue teniendo una unica
fuente de verdad (`tools/generate-project.js`, 162/162 en su sitio); aqui solo
se anade presentacion, que es lo que debe poder cambiar sin mover un stud.

**Verificacion.** En PLAY: `16 luces en el lobby, 9 del Core, 5 de portales,
5 de arena, 5 carteles`, y el nucleo measured en 8.52 de lado frente a 8.0 base,
es decir, pulsando de verdad.

---

# P1 - `player.RespawnLocation` nunca se asignaba

**Sintoma.** El mapa tenia 6 `SpawnLocation` HABILITADOS en el lobby y, a la
vez, `player.RespawnLocation = nil` en la sesion en vivo.

**Por que importa.** Sin esa propiedad, Roblox decide el punto de reaparicion
por su cuenta. En este mapa eso significa el ORIGEN, que esta en mitad del
vacio entre el lobby (0,0,0) y la arena (500,0,0): el jugador cae, `SpawnService`
lo rescata y reaparece otra vez, en bucle. Ademas, al morir en la ronda, nunca
vuelve al lobby.

**Causa.** `SpawnService` recogia y repartia spawns, y `PlayerService` no pedia
ninguno: nadie asignaba la propiedad. `SetDependencies` de `PlayerService`
recibia `roundService`, `combatService` y `matchService`, y no `spawnService`.

**Correccion.** `PlayerService.SetDependencies` acepta `spawnService`,
`AssignRespawnLocation` fija el punto al ENTRAR (no en cada muerte: durante una
ronda el renacimiento lo decide `MatchService`), y `ServerMain` lo cablea.

**Verificacion.** `respawnLocation` paso de `NIL` a
`Workspace.SpawnLocations.LobbySpawn1`.

---

# P1 - El plugin de Rojo duplicaba servicios, librerias y remotos

**Sintoma.** `source-runtime-diff` no llegaba a PASS y reportaba homonimos:
`CoreRules[2]`, `CoreAction[2]` y, en cuanto se anadio `VisualService`,
`VisualService[2]`.

**Causa raiz (medida).** El plugin de Rojo esta CONECTADO a esta sesion de
Studio y sincroniza por su cuenta, mientras `tools/sync-scripts.js` escribe a
mano. Los dos caminos crean la instancia y el que llega segundo deja un
homonimo. Por eso los duplicados aparecian justo en los ficheros tocados por un
`sync-all` reciente.

**Por que no es cosmetico.** `FindFirstChild("CoreRules")` y
`WaitForChild("VisualService")` devuelven el PRIMERO que encuentran, no el
correcto. Con dos `CoreAction`, un `WaitForChild` puede cablearse al remoto
huerfano y `CoreService` deja de funcionar SIN NINGUN ERROR: el `require` es
correcto y el juego, no.

**Correccion.** Nuevo `tools/dedupe-code.lua`, ejecutado dos veces en
`sync-all.js`: antes de escribir los scripts y otra vez despues, porque el
plugin puede crear un homonimo en cualquier momento. Es RECURSIVO: la primera
version solo bajaba dos niveles y dejaba vivo `CoreRules`, que vive tres
niveles abajo (`ReplicatedStorage > Shared > Libraries`). El propio script
reporta la cuenta final, asi que un fallo se ve en vez de pasar.

**Verificacion.** `RESULTADO: PASS` con 0 faltantes, 0 sobrantes.

---

# P1 - `Orientation + 360` reventaba el arranque de `VisualService`

**Sintoma.** `Init de 'VisualService' fallo: ...:288: attempt to perform
arithmetic (add) on Vector3 and number`. El error abortaba `Init` ANTES de
encender portales y lobby, y el servicio se quedaba a medias.

**Causa.** `BasePart.Orientation` es un Vector3 de Euler, no un numero. Sumarle
`360` es una suma de Vector3 con number.

**Correccion.** Se anima `CFrame` (`ring.CFrame * CFrame.Angles(...)`), que gira
la pieza sobre su propio centro y es la forma correcta. Cada anillo gira en un
eje distinto.

**Verificacion.** El log pasa a `16 luces en el lobby, 9 del Core, 5 de
portales, 5 de arena, 5 carteles` y `VisualService Started`.

---

# P2 - El candado de los portales bloqueados salia como caracteres rotos

**Sintoma.** El cartel de los mundos deshabilitados mostraba `ƒöÆ` en vez del
emoji de candado.

**Causa.** `GothamBold` no tiene ese glifo, y el emoji llegaba ya corrupto por la
capa de texto.

**Correccion.** Texto plano: `BLOQUEADO`.

**Nota de diseno aplicada.** Un mundo deshabilitado por `FeatureConfig` no se
anuncia como disponible: su panel se apaga (gris, sin chispas) y su cartel dice
`BLOQUEADO`. Mostrar "Nivel 1" sobre un portal que el servidor rechaza seria
informacion falsa en pantalla. El texto sale de `WorldDefinitions`, la misma
tabla que usa `PortalService` para validar.

