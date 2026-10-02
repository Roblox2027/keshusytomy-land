# FASE 0 — P0 de ronda: cerrado

Fecha: 2026-10-02
Estado: **PASS** para el P0 de ciclo de ronda.

---

## 1. Que se rompia

Sintoma reportado: `RoundService` se queda permanentemente en `RoundEnding`,
`remaining = 0`, heartbeat congelado y `task.wait` bloqueado.

---

## 2. Causa raiz EXACTA

- **Archivo:** `src/ServerScriptService/Services/RoundService.lua`
- **Funcion:** `runRoundLoop`
- **Condicion:** `task.wait(remaining)` con el `remaining` del estado en el que
  el bucle entraba.

`PlayerService.OnPlayerDied` llamaba a `RoundService.Transition(RoundEnding)`
desde **su propio hilo** al morir el ultimo vivo. El estado de la maquina
cambiaba, pero el bucle seguia dormido con el plazo del `Playing` (180 s).

### Evidencia medida (tools/round-probe.js, no deducida)

| Campo | Valor |
| --- | --- |
| `state` | `RoundEnding` |
| `remaining` | `0` |
| `_stateEndsAt - os.clock()` | `-140` → plazo vencido hace **140 s** |
| `heartbeat` | `46`, congelado |
| `coroutine.status(loop)` | `suspended` (vivo, no muerto) |
| historial | 8 ciclos **completos**; la ronda 9 nunca avanza |

### Por que `task.wait` NO era la causa

Se determino que hilo esperaba, que condicion deberia permitir continuar, que
valor no cambiaba, quien deberia cambiarlo, si habia yield infinito, si habia
excepcion y si el hilo estaba vivo. Resultado:

- El hilo estaba **vivo y sano**, dormido en un `task.wait` con un numero grande
  (un yield normal, no infinito).
- La condicion que deberia permitir continuar (vencer `_stateEndsAt`) **si se
  cumplio**, pero el bucle no volvio a mirarla.
- **Ninguna excepcion**: el Output estaba limpio. Por eso el fallo era invisible.
- No habia estado terminal en el diagrama: el problema era la carrera entre dos
  escritores del estado.

**`task.wait` era la consecuencia, no la causa.** La causa era dormir un plazo
que otro hilo puede invalidar en cualquier momento.

---

## 3. Correccion

1. **Sondeo en rebanadas** (`RoundTickInterval = 0.25`). Una transicion externa
   se ve en menos de 0.25 s; los estados largos siguen sin acumular retraso.
2. **`RequestEnd`**: el exterior avisa, el bucle (unico escritor) ejecuta.
   Elimina la carrera por construccion.
3. **Vigilante de atasco**: si un estado vence y no avanza, se fuerza la salida,
   se cuenta en `_stallCount` y se registra la razon. Ciclo sano = 0 atascos.
4. **Duraciones en `GameConfig`**: `3/3/4/4` dejan de ser numeros magicos. Sin
   eso no se puede ejecutar un ciclo completo en tiempo razonable ni **probar**
   que la ronda se repite.
5. **`GetTimeSinceStateStart` / `GetDiagnostics`**: `GetTimeRemaining` se recorta
   a 0 al vencer, asi que estado vencido y bucle muerto se veian **identicos**.

---

## 4. Resultados

| Ciclos | Resultado | Atascos |
| --- | --- | --- |
| 10 | **PASS 10/10** | 0 |
| 25 | **PASS 25/25** | 0 |
| 50 | no ejecutado (MCP cayo) | — |
| 100 | no ejecutado (MCP cayo) | — |

200+ rondas observadas de forma continua, hasta la ronda 209, sin un atasco.

**Regresion:** 198/198 tests, verify-wiring PASS (32 servicios, 36 llamadas
cruzadas), verify-structure PASS (32/32), 0 errores y 0 warnings en el log,
monstruos 4 en `Playing` y 0 en `RoundEnding`, combate/destruccion PASS,
portales PASS.

---

## 5. Limites honestos

- **Input real de cliente NO certificado.** El cliente MCP agota el tiempo de
  espera. Ademas se comprobo que **`FireServer` no puede invocarse desde el
  servidor**, asi que el transporte del remoto desde el cliente queda fuera.
  No se simula PASS.
- **`SuddenDeath` no observado en PLAY** (con 1 vivo la ronda se decide antes).
- **50 y 100 ciclos no ejecutados**, por el mismo bloqueo. No se declaran PASS.
- Los 19 stubs siguen sin implementar, por decision: la ronda era la
  precondicion.

Inventario de los 19 stubs en `docs/runtime-defects.md`.