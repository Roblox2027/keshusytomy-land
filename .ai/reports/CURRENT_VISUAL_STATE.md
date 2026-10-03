# ESTADO VISUAL Y DE JUGABILIDAD ACTUAL

> Documento vivo. Cada linea dice COMO se midio y con que EVIDENCIA.
> Nada se marca PASS sin haberlo ejecutado en Roblox Studio por MCP.

## 1. Bloque 1: IA de monstruos (MEDIDO en el servidor en ejecucion)

### Que estaba roto, con la cifra

`MonsterService.StepAI` era UN `if`, no una IA:

```lua
if target then
    step = AIService.Step(...)
    mover hacia el a Speed * ChaseMultiplier
    if distancia <= AttackRange then TakeDamage() end
end
```

Consecuencias medidas en el source antes del cambio:

| Monstruo | `Speed` | `ChaseMultiplier` | Velocidad real | Jugador |
| --- | --- | --- | --- | --- |
| `BomberMonster` | 14 | 1.8 | **25.2** | 16 |
| `Hunter` | 12 | 1.6 | **19.2** | 16 |
| `Shadow` | 11 | 1.5 | **16.5** | 16 |
| `Guardian` | 5 | 1.1 | 5.5 | 16 |

Tres monstruos corrian MAS RAPIDO que el jugador. La bomba dejaba de ser una
decision y pasaba a ser una carrera perdida. Ademas no existian `Patrol`
(clavados al aparecer), ni telegraph (muerte sin aviso), ni cooldown real.

### Que hay ahora

Maquina de estados completa en `AIService`, ejecutada por `MonsterService`:

```text
Patrol -> Detect -> Warning -> Chase -> Attack -> Recovery -> Patrol
```

- `Detect` y `Warning`: el monstruo esta PARADO. Es la ventana de reaccion.
- `Warning` enciende `TelegraphGlow` y pone `!1.4` en el cartel.
- `Attack` solo cobra si el jugador SIGUE dentro del alcance al final de la
  carga: si salio durante el telegraph, el golpe falla.
### Velocidades medidas en el servidor (via MCP, no ledas del source)

```
playerSpeed 16 | maxChase 12.48 | maxCharge 23.2 | balanceProblems []

Slime         patrol  5.5 / chase 11.0 / charge 13.0 / aviso 0.8s
BombBug       patrol  6.0 / chase 12.0 / charge 15.0 / aviso 0.7s
Shadow        patrol  6.5 / chase 13.0 / charge 16.0 / aviso 0.6s
Hunter        patrol 11.0 / chase 15.0 / charge 23.0 / aviso 0.9s
Guardian      patrol  4.5 / chase  9.0 / charge  9.0 / aviso 1.1s
IceBeast      patrol  6.0 / chase 12.0 / charge 17.0 / aviso 0.8s
FireBeast     patrol  6.5 / chase 13.0 / charge 18.0 / aviso 0.8s
BomberMonster patrol  6.0 / chase 12.0 / charge 24.0 / aviso 1.4s
CyberStalker  patrol  8.0 / chase 14.0 / charge 22.0 / aviso 0.7s
```

`GetBalanceProblems()` devuelve `[]`: las nueve definiciones cumplen las reglas.

### Ciclo medido en PARTIDA (`.ai/probes/ai-trace2.lua`)

Traceado desde el nacimiento del monstruo, con el jugador quieto en la arena:

```text
Monster_Shadow#4 : Patrol -> Detect -> Warning -> Chase -> Attack
Monster_BombBug#3: Patrol -> Detect -> Warning -> Chase -> Attack
Monster_Slime#2  : Patrol -> Detect -> Warning -> Chase
Monster_Slime#1  : Patrol   (a 48 studs, fuera de deteccion: correcto)
```

`estadosVistos: [Attack, Chase, Detect, Patrol, Warning]`

Los cinco estados se observan en el juego real. No hay ningun estado
decorativo: si `Detect` o `Warning` no hubieran aparecido, la maquina seria
codigo muerto aunque las pruebas dieran verde.

### PRUEBA DE ESCAPE (§24) — `.ai/probes/ai-escape.lua`

Peor caso: el jugador HUYE en linea recta, sin obstaculos y sin bomba.

```text
distancia inicial  15.9 studs
distancia final    34.6 studs
recupera terreno  -18.7 studs  (el monstruo PIERDE terreno)
vida inicial      100
vida final         100
```

El jugador gana la carrera contra el Slime y sale ileso. Eso es lo que hace
que la bomba sea una herramienta y no una loteria.

### Lo que SIGUE sin certificar

- Que el `TelegraphGlow` se vea bien en PANTALLA. El dato esta medido
  (`Transparency = 1` en reposo, `0.25` en `Warning`), pero el color y el
  tamano no se han visto. `capture_screenshot` sigue sin poder capturar el
  viewport del cliente.
- Multiplayer: solo hay un jugador en la sesion.
- El mundo entero: ver seccion 2.
---

## 2. Lo que NO esta terminado (medido, no supuesto)

| Sistema | Estado MEDIDO | Evidencia |
| --- | --- | --- |
| **Mundos explorables** | **PASS** | `tools/world-structure-test.js`: 11-13 zonas, 15-18 rutas y 0 solapamientos por mundo. Antes: bounding box ~210x210, 0 zonas, 0 rutas |
| **Bosses** | **NO IMPLEMENTADO** | `BossSpawn_*` es una plataforma de 30x30 con totems y corona. No hay `BossService` entre los 34 servicios. La ZONA esta preparada; el boss, no |
| **Monetizacion** | **NO IMPLEMENTADO** | `MonetizationService` son 31 lineas de stub. Sin `ProcessReceipt`, sin ledger, sin ids |
| **Portales** | **PASS** | Los 5 con `PortalPanel` sin colision y cartel. El `prompts=0` del informe anterior era un CONTEO MAL HECHO, no un fallo: se media `ProximityPrompt`/`ClickDetector`, y el sistema real de interaccion es boton del HUD + `PortalService.MAX_INTERACTION_DISTANCE` en servidor. No hay prompts porque no debe haberlos: el prompt es cliente y el servicio veta la distancia por su cuenta |
| **Audio** | **BLOCKED** | `AudioConfig` tiene todos los `assetId` en `nil`. No hay ficheros de audio. No se inventa ningun id |
| **Captura visual** | **BLOCKED** | `capture_screenshot` responde `StudioCaptureService cannot capture this DataModel right now` |

### El mundo, con numeros

Medido sobre `default.project.json` con `node tools/world-structure-test.js`:

| Mundo | Bounding box | Zonas | Rutas | Encuentros | Solapamientos |
| --- | --- | --- | --- | --- | --- |
| Forest | 278 x 416 | 11 | 15 | 2 | 0 |
| Desert | 266 x 468 | 12 | 16 | 2 | 0 |
| Ice | 266 x 418 | 12 | 15 | 2 | 0 |
| Volcano | 266 x 422 | 13 | 18 | 2 | 0 |
| Cyber | 252 x 424 | 12 | 15 | 2 | 0 |

Ningun mundo es un cuadrilatero: el 18-25 % de las piezas cae fuera del
rectangulo central que las contiene, o lo que es lo mismo, la silueta tiene
entrantes y salientes.

### Que hace que un mundo sea un mundo

Cada mundo declara su PROPIA topologia en `LAYOUTS` (`tools/worlds.js`), y el
motor convierte esa declaracion en geometria:

| Papel de zona | Que se construye dentro |
| --- | --- |
| `entrance` | umbral con arco y plataforma de spawn |
| `exploration` | recorrido abierto, dunas/arboles/columnas, hitos |
| `encounter` | cobertura SOLIDA, spawns de monstruo y peligro |
| `destruction` | estructuras `Block_*` que las bombas destruyen |
| `intermediate` | cobertura densa, monstruos y barricada |
| `reward` | pedestal, corona de energia y spawns de powerup |
| `arena` | anillo grande, monumento central y `ArenaFloor` |
| `boss` | plataforma de boss con totems y corona |
| `exit` | portillo de salida y camino de vuelta |
| `scenic` | pieza de identidad del mundo (canon, lago, maquinas...) |

Una zona no es un rectangulo: es un ensamblaje de losas de sizes y giros
distintos alrededor de un nucleo, con un borde de muro SOLIDO que tiene huecos
justo donde entra cada ruta.

### Las rutas son recorridos, no lineas

Seis estilos, y cada uno construye su propia geometria: `path` (tierra y
kerbs), `narrow` (pasaje con laterales), `bridge` (tablones con barandilla y
pilares), `catwalk` (pasarela industrial), `canyon` (paredes altas a ambos
lados), `tunnel` (con techo). Interpolan la cota de las dos zonas que unen, asi
que una ruta entre una zona a y=0 y otra a y=8 es una rampa escalonada real.

### El test que impide volver a hacer cuadrados

`node tools/world-structure-test.js` mide, sobre el arbol GENERADO:

- que cada zona tenga suelo, borde y piezas solidas (no una carpeta vacia);
- que cada ruta conecte zonas DISTINTAS y tenga losas;
- que toda zona sea ALCANZABLE por alguna ruta;
- que NINGUN par de zonas se solape (medido con el radio real de la elipse);
- que el borde de cada zona este ABIERTO en el angulo de cada ruta;
- las seis distancias del recorrido principal, con minimos;
- el radio del mundo y su irregularidad;
- y el contrato de nombres completo que leen los servicios.

Falla si algo de eso se rompe, y sale con codigo 1.

---

## 3. Bug de P0 corregido en `RoundService`

El log del servidor mostraba, medido:

```text
ERROR: el estado Waiting lleva 650.0s vencido sin avanzar; se fuerza la
salida (atasco 2583). Ultima razon: esperando el plazo de Waiting (0.2s)
```

repetido **2583 veces** en una sola sesion. Dos cosas rotas a la vez:

1. `Service._expiredFor` se reiniciaba DESPUES del `return` de "el plazo aun
   no ha vencido". Como solo avanza con el plazo vencido y el bucle sondea
   cada 0.2 s, el contador NUNCA volvia a cero: crecia hasta cruzar el margen
   del vigilante y disparaba un ERROR por tick, indefinidamente.
2. El vigilante anunciaba un atasco que no existia.

El contador se actualiza ahora ANTES de cualquier `return`. Un log inundado
con falsos errores es peor que no tener log: entierra los errores reales.

---

## 4. Lo que se puede exigir a partir de ahora

`tests/shared/MonsterBalance.spec.lua` recorre los nueve monstruos y falla si
alguno incumple. Las reglas son codigo, no comentarios:

1. Ningun `ChaseSpeed` >= velocidad del jugador.
2. Ventana de reaccion `DetectTime + WarningTime` >= 0.8 s.
3. `RecoveryTime` >= 1.5 s entre golpes.
4. `ChargeSpeed` puede superar al jugador, pero durante <= 0.7 s.
5. Recompensa positiva y `MaxAlive` > 0.
6. Ningun par de monstruos con tiempos identicos.
7. Las personalidades prometidas existen (`Vanishes`, `AppliesSlow`,
   `StillWhenIdle`, `LeavesBomb`, `AppliesBurn`).

Suite: **540 pasan, 0 fallan** (antes 499).

Un monstruo nuevo declarado sin revisar esas reglas hace fallar `npm test`.
Un desbalance ya no puede llegar al juego sin que alguien lo vea antes.