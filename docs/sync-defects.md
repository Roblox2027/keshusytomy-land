# Defectos de la sincronizacion Studio <-> Rojo

Defectos MEDIDOS durante la reconstruccion de Keshusy Forest, no
supuestos. Cada uno tiene la sonda que lo demuestra.

Estos importan mas que el bosque: hacen que cambiar la geometria del mapa
no llegue a Studio, y fallan de forma que se puede confundir con "el mapa
esta mal".

---

## 1. `import_rbxm` NO actualiza lo que ya existe

**Medido por:** `tools/import-update-probe.js`

Importa el mismo `.rbxm` dos veces. La segunda pide `size=20x30x10` y
`position=100,200,300` sobre una instancia que ya existe. Resultado: sigue
en 4x4x4 y en el origen.

```
=== 1. Primera importacion (crea HostPart) ===
  size=4.0x4.0x4.0 pos=0.0,0.0,0.0
=== 2. Segunda importacion (deberia ACTUALIZAR) ===
  size=4.0x4.0x4.0 pos=0.0,0.0,0.0
```

**Consecuencia:** cambiar el tamano, el material o la rotacion de una
pieza del mapa NO llega a Studio por esa via. Solo llega si la pieza es
nueva.

**Por que no se detectaba antes:** los bloques llegaron con su
decoracion nueva (325 hijos `Deco_*`, porque anadir hijos si funciona)
pero con la geometria del mapa viejo (8x8x8 en vez de 6x11x6). El
recuento de instancias daba PASS: los nombres coinciden y el numero
tambien. Solo `verify-geometry` lo ve.

**Correccion:** `tools/remap.js` PURGA el mapa antes de importar, siempre,
y despues `apply-map-positions.js` coloca posicion, tamano y orientacion
a mano. `reset-map.lua` por si solo NO sirve: su criterio de salud es
estructural ("hay mas de 100 Partes y nada amontonado en el origen") y un
mapa VIEJO pero sano lo supera.

---

## 2. `dedupe-workspace.lua` destruia los hijos de las piezas duplicadas

**Medido por:** `source-runtime-diff` con 326 instancias ausentes.

Cuando dos instancias comparten nombre, la fusion conservaba la que ya
estaba y destruia la nueva. Solo reubicaba los hijos si AMBAS eran
`Folder`:

```lua
elseif existing:IsA("Folder") and child:IsA("Folder") then
    mergeInto(existing, child, ...)
else
    child:Destroy()   -- <- se llevaba por delante los hijos
end
```

Un `Block_N` es un `Part`, no un `Folder`: sus hijos `Deco_*` morian con
el duplicado. El bloque se conservaba (ya existia) pero sin decoracion, y
el bosque llegaba a Studio como 48 cajas peladas.

`child` no ser `Folder` NO significa "sin hijos": cualquier instancia
admite hijos, incluida una `Part`.

---

## 3. Rojo 7.7.0 no soporta atributos de instancia

**Medido por:** `tools/attr-probe.js`

| Sintaxis | Resultado |
|---|---|
| `$attributes: {...}` al nivel de la instancia | build ok, atributo **AUSENTE** |
| `$properties: { Attributes: {...} }` | build **RECHAZADO** |
| campo suelto en el nodo | build **RECHAZADO** |

Ninguna funciona. Rojo devuelve siempre el mismo error
("Failed to deserialize JSON") sin decir el campo culpable, asi que se
perdia mucho tiempo buscando por el mapa entero
(`tools/rojo-bisect.js` automatiza esa busqueda).

**Como se resolvio:** la variante de cada bloque viaja en el NOMBRE de su
decoracion (`Deco_A_Leaf_12`). Sobrevive al build y se lee en Studio sin
ejecutar nada.

---

## 4. `Lighting` no llega por el pipeline

`sync-workspace.js` extrae SOLO el subarbol `Workspace`. `Lighting` es un
servicio hermano del DataModel, asi que nunca entra por `import_rbxm`.

No se notaba porque el proyecto no declaraba `Lighting` y Studio traia
los suyos por defecto. Ahora el bosque declara `Atmosphere` y
`BloomEffect` propios, asi que hace falta `tools/gen-lighting-lua.js` +
`tools/apply-lighting.lua`, que se GENERAN desde `default.project.json`
para no crear una segunda fuente de verdad.

---

## 5. Play arranca de una COPIA EN DISCO

Studio arranca Play desde
`AutoSaves/<place>_AutoRecovery_1.rbxl`, no desde el arbol de la sesion de
edicion. Los cambios que entran por MCP no llegan a esa copia.

Comprobado con `tools/server-vs-edit.js`, que lee lo mismo por los dos
caminos:

```
SERVIDOR : size=(8.0, 8.0, 8.0)
EDICION  : size=(6.0, 11.0, 6.0)
```

Mismo `instanceId`. Por eso `apply-map-positions.js` tiene `--run-server`
y `remap.js` aplica la iluminacion tambien al servidor: el cliente ve lo
que ve el servidor.

---

## 6. Roblox normaliza el giro Y a (-180, 180]

Un yaw declarado de 220 grados llega como -140. Es el mismo giro.
Compararlos en crudo daba 360 grados de diferencia y marcaba como
incorrectas 32 piezas que estaban bien.

La comparacion tiene que tratar esos dos valores como iguales.

---

## 7. `apply-map-positions.js` NO aplicaba NINGUNA propiedad de apariencia

**Medido por:** `tools/portal-source-audit.js` (nuevo)

`apply-map-positions.js` colocaba `Position`, `Size` y `Orientation`.
**No escribia `Color`, `Material`, `Transparency` ni `CanCollide`.**

Por si sola no seria un fallo: Rojo deberia aplicar el resto al importar.
Lo es en combinacion con el defecto 1 (`import_rbxm` no actualiza lo que ya
existe), y produce un sintoma muy dificil de leer:

```text
Portal_Ice    panel declarado 140/214/245  ->  runtime 70/74/86
Portal_Desert panel declarado 255/152/72   ->  runtime 70/74/86
Portal_Volcano panel declarado 240/110/72  ->  runtime 70/74/86
Portal_Cyber  panel declarado 190/120/255  ->  runtime 70/74/86
```

Cuatro portales con el color que tenian **antes** de este bloque. El gris
`70/74/86` NO era un color equivocado: es el que `VisualService.lua:442`
pone a proposito en los mundos deshabilitados. El sintoma parecia "el mapa
no llega" y en parte era cierto, pero la causa de fondo era que **nunca se
escribieron propiedades de apariencia**.

Medido sobre una sesion de Play recien arrancada, la colocacion encontro
**50 posiciones, 49 tamanos, 62 colores y 49 materiales** que no estaban
donde decia la fuente.

**Correccion:** `apply-map-positions.js` escribe tambien la apariencia, con
las mismas comparaciones previas que ya usaba para no generar trafico
inutil. `CanCollide` se restaura SIEMPRE, tambien a `false`: un `Block_` sin
colision deja de ser obstaculo y rompe el contrato de destruccion sin que
ninguna comprobacion de recuento lo note.

### 7.1 Dos errores QUE PRODUJE AL ARREGLARLO

Se documentan porque el estado final no los explica y volver a hacerlos
seria facil.

**La tolerancia de color de 1/255 hacia el script NO idempotente.**
Roblox guarda `Color` en coma flotante de 32 bits: un canal escrito como
`70/255` se relee como `69`. Con un margen de 1/255 la comprobacion lo
daba por distinto, reescribia el color en cada pasada e informaba de 36
colores "arreglados" una y otra vez sin que nada cambiara. El margen son
3/255, que es lo que suman los tres canales.

**El bloque de apariencia quedo insertado dentro de la contabilidad de
ejemplos.** Se coloco dentro de `if touched then / if #examples < 5 then`, que
solo se ejecuta si algo cambio, asi que la apariencia no se aplicaba a las
piezas que ya estaban bien. El sintoma era desconcertante: el script
informaba `alreadyCorrect` para justo las piezas que queria corregir.
`node -c` no lo detecta. Solo se ve leyendo donde termino el bloque.

### 7.2 Propiedad compartida: el panel de los portales bloqueados

Al arreglar 7, `apply-map-positions` empezo a repintar los cuatro paneles
bloqueados con el color de su mundo, **`VisualService` los volvio a poner
gris, y el verificador dio FAIL sobre un runtime correcto**.

El gris no es decoracion: es la senal de juego de "aqui no se entra", y
depende de `FeatureConfig` en cada arranque, asi que no puede vivir en la
fuente. Dos sistemas no pueden ser duenos de la misma propiedad, y el
conflicto se manifesto en las dos direcciones:

- aplicando el color de la fuente: el verificador daba 4 discrepancias;
- sin aplicarlo: `apply` y `VisualService` se peleaban cada arranque.

**Correccion:** la propiedad se declara explicitamente.
`RUNTIME_OWNED_APPEARANCE` lista los paths cuya apariencia manda el
runtime, y a esas piezas el manifiesto les pasa `nil` en color y material.
Su GEOMETRIA se sigue aplicando, porque de esa si responde la fuente.
`portal-source-audit.js` comprueba el gris como valor ESPERADO en los
cuatro mundos deshabilitados, y el color de la fuente en Forest.

No es un caso particular: es la regla general. Un mapa tiene dos duenos de
la verdad, la fuente para lo declarado y el runtime para lo que depende del
estado de la partida. Lo que no se puede es que los dos escriban la misma
propiedad sin que nadie lo haya declarado.

---

## 8. La puerta del cliente media la zona equivocada

**Medido por:** `tools/client-probe.js` + `tools/lobby-teleport-check.js`

`client-probe.js` cerraba con:

```lua
local ok = c.hasCamera and c.hasPlayerGui and (c.visibleLobbyParts or 0) > 0
```

Exigia ver Partes **del Lobby**, siempre. Daba FAIL con el juego
correcto: el ciclo de ronda lleva al jugador a la Arena (`x = 500`), a 500
studs del Lobby, asi que alli el Lobby no tiene por que verse. Era un fallo
de la sonda, no del juego, y se estaba reportando como lo segundo.

`lobby-teleport-check.js` mide el paso intermedio, que es el que decide:

```text
ANTES   : 499,3,-59
SALIDA  : movido a LobbySpawn1
+500ms  : 0,5,-24     <- el teleport FUNCIONA
+1500ms : -13,3,-18
+3000ms : -23,5,-2
+5000ms : -0,5,25     <- la ronda lo revierte
```

El teleport al Lobby funciona y el jugador esta alli a los 500 ms. Lo que
sigue es la ronda revirtiendolo, que es su comportamiento previsto. Con
`facelobby` el cliente llega a mostrar `Lobby 11/98` y despues `Lobby 0/98`
en dos ejecuciones seguidas con el mismo mapa.

La camara no era el problema: en PLAY esta a 5.3 de altura con el personaje
en 3.0, unos 2.3 studs por encima, lo normal en `CameraType.Custom`.

**Correccion:** la puerta pregunta lo que el jugador tiene delante **en la
zona en la que esta**, y ademas exige que la zona se haya podido
determinar: un `zone` vacio si significaria que el cliente no ve el mapa, y
eso si es un fallo. Se siguen exigiendo camara y `PlayerGui`. Los motivos se
imprimen uno a uno en vez de un `FAIL` sin explicar.

---

## 9. `IsVisibleFrom` en el cliente agota el puente MCP

**Medido por:** `tools/client-camera-sample.lua`

La primera version de la sonda de camara recorria
`Lobby:GetDescendants()` llamando a `IsVisibleFrom` en cada Part. Las cuatro
muestras consecutivas dieron `request_timeout` a los 30 s, y el cliente
siguio sin responder a eval incluso triviales hasta reiniciar Play.

`IsVisibleFrom` es una prueba de oclusion REAL, no una comparacion de
distancia: su coste crece rapido y cuatro veces seguidas en el mismo ciclo
desbordan el puente. El recuento por region de `client-probe.js` ya cubre
la visibilidad, asi que la sonda se quedo en lo que si hacia falta: donde
estan la camara y el personaje, medidos en el MISMO instante.

La leccion: `IsVisibleFrom` no se usa para medir "cuantas partes hay cerca".
Ya hay una comprobacion mas barata para eso.

---

## 10. Carrera entre `apply-map-positions` y la carga del servidor

**Medido por:** `play.js restart` seguido de `verify-geometry.js`

`play.js` anuncia `SERVIDOR LISTO` cuando el servidor existe, **no** cuando
ha terminado de cargar. Play arranca desde una copia en disco
(defecto 5), y esa copia se replica al servidor durante unos segundos mas.

Si `apply-map-positions.js --run-server` se ejecuta en esa ventana, mide el
estado a medio cargar y por eso informa de que **todo esta correcto**:

```text
# servidor recien arrancado, aplicar demasiado pronto
"alreadyCorrect": 1226,  "fixedPosition": 0,  "fixedSize": 0
```

Un minuto despues, sobre ese mismo servidor:

```text
GEOMETRIA: FAIL
Worlds.Forest.Blocks.Block_0: mide 8.0x8.0x8.0, deberia medir 6x11x6
(tamano incorrecto: 48, descolocadas: 40)
```

Los dos resultados son del mismo servidor y del mismo mapa, y no se
contradicen: la medicion se hizo antes de que llegara la copia.

Con **25 s de espera** entre `restart` y `apply`, la colocacion encuentra lo
que hay de verdad (`fixedPosition: 50`, `fixedSize: 49`) y todo lo que sigue
da PASS.

Peor: `apply` devolviendo `alreadyCorrect` sobre un mapa que en realidad
esta roto es el peor resultado posible, porque **desaparece el sintoma sin
haber arreglado nada**. Sin este aviso, el siguiente paso natural ("ya esta
bien, sigamos") deja el mapa viejo en el servidor.

**Regla:** despues de `play.js restart`, esperar antes de aplicar o medir.
`play.js status` informa de que el servidor EXISTE, no de que este LISTO.

---

## 11. `import_rbxm` duplica en vez de reemplazar

**Medido por:** `tools/dedupe-modules.js` y `get_place_info`

Cuatro modulos existian DOS VECES en el mismo padre:

```
ReplicatedStorage/Shared/Libraries/AIService        x2
ReplicatedStorage/Shared/Libraries/TestDriverLogic  x2
ReplicatedStorage/Shared/MonsterDefinitions         x2
ServerScriptService/Services/TestDriverService      x2
```

**Por que no lo ve nadie:**

- Un recuento de instancias da PASS: los dos existen y los dos se llaman
  igual.
- `dedupe-scripts.js` recorre los HIJOS DIRECTOS de tres servicios. Estos
  duplicados estan dos niveles mas abajo, asi que para esa herramienta no
  existen.
- `source-runtime-diff.js` SI lo detectaba, pero como "2 sobrantes" sin decir
  cuales, porque solo tenia en cuenta los que sobran en Studio.

**Por que `require` no es inocuo con un duplicado:** el juego carga el primer
`FindFirstChild` que encuentre. Si ese es el viejo, se ejecuta codigo que
nadie ha tocado en semanas, y el sintoma es "el arreglo no funciona" sin
ningun error en ninguna parte. Un `MonsterService` con dos copias puede
contener la version de 531 lineas y la de 31 a la vez.

**Correccion:** `tools/dedupe-modules.js`. El disco es la autoridad: se
conserva la copia cuyo `Source` coincide con el archivo de `src/` y se
informa del resto. Con `--apply` destruye; sin el, solo informa.

Deliberadamente NO borra un modulo UNICO aunque su fuente no coincida con el
disco: eso es desincronizacion de fuente y corresponde a `sync-scripts.js`.
Borrar el unico seria destruir codigo que Rojo reescribe, y el sintoma
volveria un sinfin de veces.

---

## 12. `set_script_source` del MCP anade un byte delante de cada caracter de doble ancho

**Medido por:** `tools/verify-source-text.js`

Este es el defecto mas caro de los doce, porque **no cambia ni una sola
instancia del arbol**. Los nombres coinciden, el numero de instancias
coincide, `verify-structure` da PASS y `verify-wiring` da PASS. Solo el TEXTO
lo delata.

Prueba controlada: se escribio un ModuleScript con UN solo U+00BF y se releyo:

```text
CREADO:   ServerScriptService.MojibakeProbe
ESCRITO:  newSourceLength=48  method=UpdateSourceAsync
RELEIDO:  len=48 C2BF=1
  esperado si NO hay doble codificacion: len=47 C2BF=0
```

La herramienta `set_script_source`, que usa `sync-scripts.js` en cada
archivo, escribe el texto con el byte `C2` anadido delante de cada caracter de
doble ancho. `¿` (C2 BF) sale como `Â¿` (C3 82 C2 BF).

**Consecuencia:** las tildes y simbolos del repositorio llegan DOBLEMENTE
codificados a Studio. Los comentarios quedan ilegibles justo en las reglas de
seguridad, que es donde mas cuesta leerlos:

```text
-- no conf├¡a en una sola comprobacion.        (era: no confia)
--- ┬┐El servidor esta aceptando trabajo?    (era: ?El servidor)
```

Y `RoundService.lua:564` era peor: "corrutina espiral" llego con seis bytes
(`EB 82 98 EC 84 A0`, U+B098 U+C120) donde tenia cinco letras. Sin una regla
general que lo revierta, y sin que haga falta: la palabra se deduce del
sentido de la frase.

**Correccion:** `tools/ascii-only.js` traduce el fuente a ASCII. Sin `--fix`
informa y devuelve codigo distinto de 0, para poder usarse como puerta; con
`--fix` reescribe.

Se elige ASCII y no "arreglar la herramienta" porque el plugin MCP esta fuera
del repositorio y su version no es nuestra. El ASCII atraviesa su codificacion
intacto, y ademas el codigo de este proyecto ya estaba escrito casi por entero
sin acentos ("esta", "aqui", "codigo"): la herramienta solo termina el
trabajo en vez de cambiar el criterio del proyecto.

**Verificacion:** `tools/verify-source-text.js` recorre todos los scripts de
Studio contando caracteres no ASCII. Resultado tras el arreglo:

```text
scripts=74 conNoAscii=0
```

Que es lo que un recuento de instancias jamas habria dicho.

---

## Desmontaje de dos sondas que mintieron

Durante este bloque dos sondas dieron un veredicto equivocado. Se documenta COMO
fallaron porque el fallo de una sonda se parece mucho a un fallo del juego, y
esa confusion es la que cuesta el tiempo:

**1. "SIN MONSTRUOS" durante cuatro minutos.** Una sonda contaba los
monstruos en `workspace:FindFirstChild("Monsters")`. La carpeta SI existe:
`MonsterService.GetFolder()` la crea con `Parent = Workspace`. Lo que fallaba
era la LLAMADA: `eval_server_runtime` suelto responde `"Requested module
experienced an error while loading"` cuando el servidor esta ocupado, y ese
texto se lee igual que "la carpeta no existe". Se usa `mcp.serverLuau`, que
desenvuelve esa capa y distingue un error de transporte de un `false` real.

**2. "El jugador nunca recibe dano" durante toda la sesion.** Es cierto, pero
no por un bug. Las rondas de ESTA sesion duran menos de un segundo por estado,
porque el TestDriver acorta los tiempos, y la proteccion de aparicion dura
unos 1.85 s. La ventana se renueva en cada vuelta a la arena, asi que nunca
expira: `_blockedDamage` iba por 1580 mientras `_damageEvents` se quedaba en 0.

La prueba que lo aisla llama a la puerta de dano del servidor con el mismo
`Humanoid` del jugador y compara con y sin proteccion:

```
estado=Playing  vivos=4  ApplyDamage=false  motivo=invulnerable
                            sinProteccion=true  motivo=nil  vida=93
```

Con ronda activa y sin proteccion el dano SE APLICA (100 -> 93). El ataque del
monstruo y la cadena de dano funcionan; lo que se media era el reloj del
entorno de prueba.

La leccion general: antes de declarar un fallo hay que comprobar si la propia
sonda esta midiendo el instante correcto. Una prueba ejecutada en el momento
equivocado no informa de nada, ni a favor ni en contra.

---

## Reglas que se siguen ahora

1. `node tools/dedupe-modules.js` antes de declarar el arbol sano. Sin
   `--apply` es un informe.
2. `node tools/ascii-only.js` sin `--fix` en la puerta: sale distinto de 0 si
   hay no-ASCII en el fuente.
3. `node tools/verify-source-text.js` tras sincronizar: si el disco es ASCII y
   Studio no, el transporte ha vuelto a fallar.
4. Verificar con el TEXTO y no con los NOMBRES cuando lo que se ha tocado es el
   fuente. El defecto 12 no cambia ni una instancia del arbol.

---

## Falso positivo conocido

`tools/verify-wiring.js` falla con:

> ServerMain: el bucle de registro NO hace `require(entry.module)`

Es un FALSO POSITIVO. `ServerMain.server.lua:415` si hace
`pcall(require, entry.module)`. El patron que busca el verificador no
encuentra esa forma concreta. Ni `verify-wiring.js` ni `ServerMain` se han
modificado en este bloque.
