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

Los cinco existen con geometria. Ninguno esta completo.

| Mundo | Partes | Bloques | SpawnPoint | Exit | Hazards | MonsterSpawns | PowerupSpawns | BossSpawn |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Forest | 1123 | 214 | NO | NO | NO | NO | NO | NO |
| Desert | 368 | 48 | SI | SI | 5 | 4 | 4 | SI |
| Ice | 390 | 48 | SI | SI | 5 | 4 | 4 | SI |
| Volcano | 364 | 48 | SI | SI | 5 | 4 | 4 | SI |
| Cyber | 430 | 48 | SI | SI | 5 | 4 | 4 | SI |

- Forest es el mundo de entrada del jugador y es EL MAS POBRE de estructura:
  no tiene por donde aparecer, ni por donde salir, ni donde nacen los
  monstruos, ni donde aparecen los powerups, ni donde esta el boss. El portal
  que lleva a el no puede llevar a una arena ronda.
- Forest si tiene decoracion y terreno (666 Partes de `Decoration` +
  `Terrain`), por eso es el mas grande en numero de Partes. Cantidad no es
  completitud.

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

1. Forest sin SpawnPoint ni Exit: el flujo JOIN -> LOBBY -> PORTAL 1 no cierra.
2. StarterGui vacio: el jugador no ve HP, ni bombas, ni XP, ni nivel, ni
   monedas, ni temporizador, ni barra de boss.
3. Sin UI de inventario, tienda, misiones ni notificaciones.
4. Sin iluminacion diferenciada por mundo.
5. Sin VFX ni audio connected a eventos reales.

## ESTADO GLOBAL

GAME STATUS = NOT READY

Cinco mundos, cinco portales y geometria real ya existen en Studio, y eso es
un avance real y verificable. Pero el criterio del proyecto es el flujo
completo, y el flujo se rompe en el primer mundo: Forest no tiene por donde
entrar. Y el jugador no ve ninguna interfaz.
