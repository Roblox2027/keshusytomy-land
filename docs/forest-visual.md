# Keshusy Forest — reconstrucción visual

## Que se reconstruyo

La arena era, literalmente, **48 cubos de 8×8×8 en `WoodPlanks`**, sin
rotacion, sobre una retícula de paso 8.25 y un suelo de `Concrete` de
180×180 de un solo color. Medido en la fuente y confirmado en runtime.

Ahora es un bosque. Sin cambiar el contrato `Block_*`.

## Estructura

```
Workspace.Worlds.Forest
  ArenaFloor            suelo (Grass)
  ArenaCenter/N/S/E/W   marcadores de neon, sin colision
  ArenaWall_N/S/W/E     muralla perimetral (unica colision de decoracion)
  Blocks/               28 bloques del perimetro
  CentralStructure/     20 bloques del relicario
  Terrain/              66 piezas: crestas, 4 senderos, 3 claros de arena
  Decoration/           437 piezas: arboles, arbustos, flores, setas, piedras
  Border/               104 piezas: colinas, raices y arboles del borde
  Keshusy/              137 piezas: cristales, anillos de energia, luciernagas
```

Total: **1227 Partes** con posicion declarada.

## Las cuatro variantes

Cada bloque elige una de cuatro siluetas. Se asignan de forma
determinista y repartida (12 de cada una sobre 48), sin `Math.random()`:
el mapa tiene que salir igual byte a byte en cada build, porque de eso
depende `source-runtime-diff`.

| Variante | Tamano | Material | Silueta |
|---|---|---|---|
| A | 6×11×6 | Wood | tronco con copa |
| B | 12×4×10 | Grass | losa de musgo, muy inclinada |
| C | 8×7×9 | Rock | roca compacta |
| D | 7×9×7 | Slate | nodo de cristal Keshusy |

Mas 390 piezas de decoracion colgando de los bloques (copas, raices,
musgo, vetas de cristal, setas y piedras).

**Por que la geometria principal sigue siendo una sola `BasePart`:**

1. `IsDestructibleBlock` exige `instance:IsA("BasePart")`. Un Model con
   hijos dejaria de ser destruible.
2. El radio de explosion se calcula por distancia entre centros
   (`ExplosionService` → `CombatMath.FalloffDamage`). Cambiar tamano y
   rotacion no altera ese calculo; cambiar la FORMA si, asi que la forma
   va en las partes HIJO.
3. `snapshotBlock` guarda `Transparency`, `CanCollide` y `CanTouch`. Nada
   de eso depende de la forma.

## Iluminacion

Declarada en el proyecto (antes no lo estaba, pese a que el comentario
dijera que sobraba):

- `ClockTime` 15.2, `Brightness` 2.4
- `Ambient` / `OutdoorAmbient` verdes y frios
- `Atmosphere` con densidad 0.22 (niebla que da profundidad)
- `ForestBloom` para que el Neon florezca
- **4 `PointLight` en todo el mapa**: el nucleo del relicario, el cristal
  mas alto, el claro de arena y el hueco norte. Un punto por arbol serian
  casi 200 y hundirian el frame rate sin aportar nada legible.

## Regla: decoracion no es obstaculo

Todo lo de `Terrain`, `Decoration`, `Border` y `Keshusy` se crea con
`decor()`, es decir **siempre con `CanCollide = false`**.

Medido en el build: **120 partes colisionables** en todo el mapa, que son
exactamente el suelo del lobby, los muros, las plataformas y postes de las
estaciones, los 8 portales, el Core, los 6 spawns, el suelo y los muros de
la arena, y los 48 bloques. Ni un arbol.

La unica excepcion declarada es `ArenaWall_*`, que delimita la arena.

## Spawn

Los 6 spawns se colocan buscando la posicion libre mas cercana a la
deseada, con un margen de 9 studs respecto a cualquier pieza solida del
lobby (incluidos los postes de los portales). Antes, `LobbySpawn5` y
`LobbySpawn6` aparecian debajo de una farola y de un poste de portal.

Ademas cada uno mira al centro (el Keshusy Core), con la orientacion
**persistida en `default.project.json`**, no corregida en runtime: si se
corrige al entrar, el primer fotograma del juego ya es el equivocado.

## Verificacion

| Herramienta | Que comprueba |
|---|---|
| `forest-verify.js` | contrato, variedad y decoracion en la FUENTE |
| `forest-build-check.js` | lo mismo en el `.rbxlx` que produce Rojo, y que el generador es determinista |
| `verify-geometry.js` | posicion, tamano y orientacion reales en runtime |
| `destroy-restore-check.js` | que el ciclo destruir/restaurar conserva la geometria |
| `spawn-check.lua` | que los spawns están libres y mirando al centro |

Todas dan PASS. **Ninguna comprueba que el bosque se vea bien**: eso
sigue sin poder verificarse sin una captura.

## Reconciliacion del bloque visual (HEAD 320cd08)

Lo anterior ya estaba hecho y commiteado. Este bloque NO reconstruyo el
bosque: lo **reconcilio**, porque el informe previo no se puede dar por
cierto y habia que volver a medir antes de tocar nada.

### Lo que se midio de nuevo, en runtime

| Medida | Valor |
|---|---|
| Partes totales en Workspace | 1245 |
| Colisionables | 124 |
| Neon | 299 |
| Translucidas | 105 |
| Bloques `Block_` | 48 |
| SpawnLocations | 6 |
| Tamanos distintos | 434 |
| Piezas inclinadas | 93 |
| SOURCE vs RUNTIME | 0 ausentes, 0 sobrantes |

El bosque ya no es la rejilla: 434 tamanos distintos, 93 piezas
inclinadas, 4 variantes deterministas y 1227 Partes declaradas.

### Lo que estaba MAL y se corrigio

`apply-map-positions.js` no escribia ninguna propiedad de apariencia. Sobre
una sesion de Play limpia se midieron **50 posiciones, 49 tamanos, 62
colores y 49 materiales** que no estaban donde decia la fuente. Ninguna de
las comprobaciones existentes lo veian, porque todas comparaban recuento y
nombre de instancias. Detalle completo, con los dos errores que cometi al
arreglarlo, en `docs/sync-defects.md` seccion 7.

### Lo que se comprobo que NO era un fallo

- Los cuatro portales con panel gris **no** estaban rotos:
  `VisualService` los apaga a proposito (`VisualService.lua:442`).
- `client-probe.js` dando FAIL con `Lobby 0/98` **no** era un fallo del
  cliente: el jugador esta legitimamente en la Arena a 500 studs.
  La puerta ahora mide la zona en la que esta.

## Lo que NO se puede verificar aqui

`capture_screenshot` sigue dando `request_timeout`. La comprobacion
estructural no puede sustituir a mirar la pantalla: un mapa puede tener
la geometria perfecta y leerse como un almacen de cajas. Ese judgement
sigue pendiente de una persona.