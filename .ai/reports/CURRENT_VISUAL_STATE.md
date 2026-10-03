# ESTADO VISUAL ACTUAL

Medido contra el DataModel de Roblox Studio por MCP (`execute_luau`), no
contra el repositorio ni contra informes anteriores.

- Fecha: 2026-10-03
- Rojo: 7.7.0 (`rojo/rojo.exe`)
- Studio: conectado, plugin de Rojo sincronizando en vivo
- SOURCE <-> RUNTIME: `tools/source-runtime-diff.js` = PASS (2995 en source, 2999 en runtime, 0 faltantes)
- Pruebas: 499/499 PASS
- `rojo build`: OK

## COMO SE MIDIO

`execute_luau` sobre el DataModel abierto. Cada "PARTES" es el numero de
`BasePart` reales bajo esa rama del arbol. No se cuenta metadata: se cuenta
geometria.

## LOBBY

| Elemento | Estado | Evidencia |
| --- | --- | --- |
| Keshusy Core | PARTIAL | 15 Partes reales (orbe, anillos, pilares, plinto). Geometria propia, pero sin particulas, sin animacion y sin sonido |
| Portal Forest | PASS | 11 Partes, silueta propia (arco de madera: `Canopy`, `Root_L`) |
| Portal Desert | PARTIAL | 10 Partes. Sin silueta diferenciada respecto a Forest |
| Portal Ice | PARTIAL | 10 Partes. Sin silueta diferenciada |
| Portal Volcano | PARTIAL | 11 Partes. Sin silueta diferenciada |
| Portal Cyber | PASS | 15 Partes, la silueta mas construida (pilonas de neon) |
| Estaciones de servicio | MISSING | No existen Folder para SHOP / INVENTORY / MISSIONS / EVENTS / SEASON / RANKINGS / TRAINING / SOCIAL |
| Iluminacion propia | MISSING | El unico `Lighting` es `Atmosphere` + `ForestBloom`, global del lugar |

## MUNDOS

Los cinco existen con geometria y los cinco cumplen el CONTRATO completo.
Medido con `tools/world-contract-verify.js` contra el DataModel de Studio.

El verificador distingue `STRUCTURE` (la ruta existe), `CONTENT` (hay piezas
reales) y `USABLE` (el spawn funciona). Una carpeta vacia NO cuenta como PASS:
es lo que hacia que la tabla anterior no significara nada.

| Mundo | Partes | Bloques | SpawnPoint | Exit | Hazards | MonsterSpawns | PowerupSpawns | BossSpawn |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Forest | 1174 | 48 | SI (libre) | SI | 31 | 4 | 4 | SI |
| Desert | 368 | 44 | SI | SI | 5 | 4 | 4 | SI |
| Ice | 390 | 44 | SI | SI | 5 | 4 | 4 | SI |
| Volcano | 364 | 44 | SI | SI | 5 | 4 | 4 | SI |
| Cyber | 430 | 44 | SI | SI | 5 | 4 | 4 | SI |

**CONTRATO DE MUNDOS: PASS** en los cinco.

### QUE SE CONSTRUYO EN FOREST

Forest era el mundo de ENTRADA y era el mas pobre de estructura: no tenia por
donde aparecer, ni por donde salir, ni donde nacen los monstruos, ni donde
aparece el powerup, ni donde esta el boss. El portal que lleva a el no llevaba
a ninguna parte utilizable.

Todo se genera en `tools/generate-project.js` (fuente de verdad), NO a mano en
Studio:

| Pieza | Detalle |
| --- | --- |
| `SpawnPoint_Forest` | `SpawnLocation` real tras la puerta sur, mirando al relicario. Verificado SIN obstaculos encima. |
| `Exit_Forest` | Plataforma con arco (dos postes, dintel) y flecha luminosa. Al sur, enfrente del spawn. |
| `Hazards` | 31 piezas: charcos venenosos, raices venenosas y esporas. |
| `MonsterSpawns` | 4 marcadores en anillo a 30 studs del centro. |
| `PowerupSpawns` | 4 marcadores a 64 studs, fuera de la muralla de bloques. |
| `BossSpawn_Forest` | Plataforma al norte con totems de raiz y corona luminosa. |

Los NOMBRES son los mismos que los otros cuatro mundos a proposito: es lo que
permite que un unico verificador compruebe las cinco arenas.

### PELIGROS DE FOREST: QUE HACEN Y CUAL NO

| Familia | Efecto | Dano |
| --- | --- | --- |
| `Hazard_Poison_*` | Charco bajo. Quitame vida mientras estas dentro. | SI, continuo |
| `Hazard_ThornRoot_*` | Raiz solida. Engancha y ralentiza al entrar. | SI, estado (no muerte) |
| `Hazard_Spore_*` | Nube flotante translucida. Solo VFX y oclusion. | NO, por diseno |

La ultima fila esta documentada a proposito: un peligro invisible que hace dano
sin explicarse seria peor que no tenerlo.

Las tres son `decor()`: NO colisionan. El dano lo aplica el sistema de combate
leyendo el nombre, no una Piece invisible que empuja al jugador.

## HUD / UI

| Elemento | Estado | Evidencia |
| --- | --- | --- |
| `StarterGui.KeshusyHUD` | PASS | `ScreenGui` real en el SOURCE y en Studio. 57 instancias. |
| Componentes | PASS | 9 paneles: TopBar, PlayerStats, Currency, BombStats, Objective, Mission, Timer, BossBar, Notifications. |
| HUD conectado al estado real | PARCIAL | `UIController` enlaza los 9 paneles. FALTA sesion de jugador para verlo en runtime. |
| Notificaciones | IMPLEMENTADO | `Controller.Notify` con ciclo CREATE -> SHOW -> TIMEOUT -> DESTROY, tope de 4 y limpieza en `Destroy`. Sin sesion: no verificado en pantalla. |
| Inventory UI | MISSING | No existe `ScreenGui` de inventario. |
| Shop UI | MISSING | No existe `ScreenGui` de tienda. |
| Missions UI | MISSING | Solo la linea de resumen dentro del HUD. |

### QUE CAMBIO EN EL HUD

Antes el HUD se construia POR CODIGO dentro de `UIController.buildGui()`.
Eso dejaba a `StarterGui` VACIO en el origen, que es exactamente lo que
declaraba el informe: 0 hijos. No era un fallo de medicion, era el sintoma de
que la interfaz no existia como arbol.

Ahora `tools/hud.js` genera el `ScreenGui` y `UIController` se limita a
ENLAZARLO. La UI no decide nada: lee atributos que solo el servidor escribe.

Consecuencias practicas:

- El HUD se puede auditar sin entrar en juego.
- Cada campo es un componente reutilizable, no una etiqueta en un monolito.
- Un atributo ausente se muestra `--`, no `0`: un 0 de XP dice "no tienes
  nada" y un -- dice "no lo se".
- Las barras arrancan a escala 0. Una barra llena sin datos seria una mentira
  visual: el jugador veria la vida al maximo antes de que el servidor
  publicase nada.
- `BossBar` nace OCULTA. Una barra de jefe vacia permanente persuade al
  jugador de ignorarla, y el dia que aparezca de verdad ya no la mira.

### NOTIFICACIONES

Se escuchan ATRIBUTOS, no se hace polling. Cada aviso nace de un dato que el
servidor acaba de publicar, asi que no puede inventarse: si el servidor no subio
de nivel, no aparece "NIVEL". El valor ANTERIOR se compara para detectar el
salto, porque reescribir un atributo con el mismo valor sigue disparando la
senal.

## HUD / UI

| Elemento | Estado | Evidencia |
| --- | --- | --- |
| StarterGui.UI | MISSING | 0 hijos. Un Folder vacio |
| HUD en juego | MISSING | Sin sesion de jugador activa; no se puede observar nada en runtime |
| Inventory UI | MISSING | Sin ningun `ScreenGui` en el repositorio |
| Shop UI | MISSING | Sin ningun `ScreenGui` en el repositorio |
| Missions UI | MISSING | Sin ningun `ScreenGui` en el repositorio |
| Notifications | MISSING | Sin ningun `ScreenGui` en el repositorio |

`UIController` (17.9 KB) y `PortalController` (16.1 KB) existen como codigo
de cliente. Ninguno tiene ningun objeto de interfaz que controlar, porque
StarterGui no contiene ni un solo ScreenGui. El codigo de UI esta escrito y no
tiene donde verse.

## ILUMINACION POR MUNDO

| Mundo | Estado |
| --- | --- |
| Forest | MISSING |
| Desert | MISSING |
| Ice | MISSING |
| Volcano | MISSING |
| Cyber | MISSING |

Lighting es global y unico. No hay estilo por mundo.

## ESTADO DE LA HERRAMIENTA DE SINCRONIZACION

Corregido en este bloque. `tools/sync-scripts.js` daba RESULTADO: FAIL sobre
`EconomyRules` con el archivo correctamente escrito e identico. Cuatro
causas encadenadas, todas de la herramienta y ninguna del juego:

1. `get_script_source` esta capada a 300 lineas y antepone numeros de linea.
   La comprobacion era de prefijo, asi que el final del archivo nunca se
   verificaba.
2. El hash inicial usaba operadores de bits (`~`, `&`). El sandbox de
   `execute_luau` NO los compila: la sonda no compilaba, la funcion devolvia
   `null` en silencio, y los 87 scripts parecian "no existir en Studio".
3. Studio no normaliza los saltos de linea de forma uniforme (algunos scripts
   quedan con CRLF y otros con LF), asi que la longitud no coincidia nunca.
4. Studio mide BYTES, no caracteres. Con BOM UTF-8 y acentos la cuenta de JS
   no coincide con la de Luau.

La comprobacion ahora lee `Script.Source` dentro de Studio y compara longitud
en bytes y hash aritmetico (djb2 con primo), sin operadores de bits, sin CR y
en bytes UTF-8. Es una comprobacion MAS fuerte que la anterior: ya no basta un
prefijo, el archivo entero tiene que coincidir. Ademas avisa cuando la sonda
falla en vez de tragarse el error.

Verificado con un sentinel: al appender una linea a `Ice.lua` en disco, Studio
la recibio en segundos (el plugin de Rojo esta conectado), y al revertir el
archivo en disco Studio tambien revirtio. La deteccion de divergencias se
ejercito de verdad, no solo se administro que no fallara.

## LO QUE FALTA PARA QUE EL JUGADOR PUEDA JUGAR

Resuelto en este bloque:

1. ~~Forest sin SpawnPoint ni Exit~~ -> RESUELTO. Spawn verificado libre y
   salida con arco y senal.
2. ~~StarterGui vacio~~ -> RESUELTO. `KeshusyHUD` con 9 componentes, 57
   instancias, presente en el SOURCE y en Studio.
3. Notificaciones -> IMPLEMENTADO, falta certificarlas con jugador en sesion.

Sigue pendiente:

4. Sin sesion de jugador activa no se ha podido observar el HUD en pantalla.
   La implementacion esta y sincronizada; la CERTIFICACION de jugador no.
5. Sin UI de inventario ni de tienda.
6. Sin iluminacion diferenciada por mundo.
7. Sin VFX ni audio conectados a eventos reales.
8. La interaccion de la salida de Forest (`Exit_Forest`) es geometria y punto
   de retorno, pero el flujo FOREST -> LOBBY no se ha ejercitado con jugador.

## LO QUE ESTA SIN VERIFICAR

- No se ha podido ejecutar `PLAY`: el MCP Client no tiene sesion de jugador,
  asi que la ruta `JOIN -> LOBBY -> PORTAL -> FOREST -> HUD -> GAMEPLAY` NO
  esta certificada. Todo lo de arriba es verificacion de SOURCE y de RUNTIME
  sin jugador.
- `tools/analyze.js` sigue en FAIL: 886 incidencias, de las que 882 ya estaban
  antes de este bloque. Ninguna es de los archivos tocados.
- `sync-all.js` acaba en DIVERGE por una sola diferencia:
  `StarterGui: source=Folder runtime=StarterGui`. Es el propio servicio
  declarado como Folder en el proyecto para poder colgar el HUD. Faltan 0
  instancias y sobran 0.

## ESTADO GLOBAL

GAME STATUS = NOT READY

Cinco mundos, cinco portales y geometria real ya existen en Studio, y eso es
un avance real y verificable. Pero el criterio del proyecto es el flujo
completo, y el flujo se rompe en el primer mundo: Forest no tiene por donde
entrar. Y el jugador no ve ninguna interfaz.
