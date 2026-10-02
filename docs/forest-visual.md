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

## Lo que NO se puede verificar aqui

`capture_screenshot` sigue dando `request_timeout`. La comprobacion
estructural no puede sustituir a mirar la pantalla: un mapa puede tener
la geometria perfecta y leerse como un almacen de cajas. Ese judgement
sigue pendiente de una persona.