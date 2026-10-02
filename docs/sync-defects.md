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

## Falso positivo conocido

`tools/verify-wiring.js` falla con:

> ServerMain: el bucle de registro NO hace `require(entry.module)`

Es un FALSO POSITIVO. `ServerMain.server.lua:415` si hace
`pcall(require, entry.module)`. El patron que busca el verificador no
encuentra esa forma concreta. Ni `verify-wiring.js` ni `ServerMain` se han
modificado en este bloque.
