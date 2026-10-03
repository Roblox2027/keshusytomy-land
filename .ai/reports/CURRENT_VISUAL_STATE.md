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
| **Mundos explorables** | **FAIL** | Los 5 tienen bounding box ~210x210, 0 zonas, 0 rutas. Una arena cuadrada con decoracion. Incumple "un mundo no puede ser un cuadrilatero pequeno" |
| **Bosses** | **NO IMPLEMENTADO** | `BossSpawn_*` es una placa de 26x26. No hay `BossService` entre los 34 servicios. Ningun boss, ninguna fase, ninguna recompensa |
| **Monetizacion** | **NO IMPLEMENTADO** | `MonetizationService` son 31 lineas de stub. Sin `ProcessReceipt`, sin ledger, sin ids |
| **Portales** | **PARTIAL** | Los 5 existen con su cartel, pero `prompts=0`: la entrada depende del boton del HUD, no de un prompt en el mundo |
| **Audio** | **BLOCKED** | `AudioConfig` tiene todos los `assetId` en `nil`. No hay ficheros de audio. No se inventa ningun id |
| **Captura visual** | **BLOCKED** | `capture_screenshot` responde `StudioCaptureService cannot capture this DataModel right now` |

### El mundo, con numeros

Medido con `.ai/probes/world-bounds.lua`:

| Mundo | Bounding box | Zonas | Rutas |
| --- | --- | --- | --- |
| Forest | 211 x 37 x 212 | 0 | 0 |
| Desert | 214 x 35 x 215 | 0 | 0 |
| Ice | 210 x 25 x 209 | 0 | 0 |
| Volcano | 214 x 38 x 214 | 0 | 0 |
| Cyber | 218 x 32 x 221 | 0 | 0 |

Cinco arenas cuadradas con distinta paleta. Es exactamente lo que la
especificacion prohibe cuando dice "Forest = verde, Desert = amarillo".

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