# MATRIZ DE REGRESION

> Documento vivo. Cada item dice COMO se comprueba y con que EVIDENCIA.
> Un item sin evidencia ejecutable queda `BLOCKED`, nunca `PASS`.

## 0. Por que esta matriz existe

El informe anterior mezclaba "el codigo existe" con "el juego funciona".
Esta matriz separa las dos cosas y, sobre todo, separa **GAME** de
**INFRAESTRUCTURA**: un bloqueio de herramienta no se convierte en un
defecto del juego ni al reves.

## 1. Estado del entorno (medido en esta pasada)

| Elemento | Estado | Evidencia |
| --- | --- | --- |
| `HEAD` | `022c286` | `git rev-parse HEAD` |
| `HEAD == origin/main` | SI | ambos `022c286` |
| Arbol | limpio salvo `Install-RobloxAIKit.ps1` (bootstrap preexistente, NO tocar) | `git status --short` |
| Suite Luau | **350/350 PASS** | `npm test` |
| verify-structure | PASS (33/33) | `node tools/verify-structure.js` |
| verify-wiring | PASS (20 en SERVICES, 13 conexiones, 36 llamadas) | `node tools/verify-wiring.js` |
| analyze.js | **FAIL (714)** | `node tools/analyze.js` |
| Build Rojo | PASS | `rojo\rojo.exe build` |
| Sync a Studio | PASS (61 iguales / 0 fallidos) | `node tools/sync-scripts.js` |
| MCP **servidor** | CONECTADO (48 herramientas) | `node tools/studio-mcp.js list` |
| MCP **cliente** | **BLOCKED** | `eval_client_runtime` agota tiempo incluso con `return 1+1` |
| DataStore real | **BLOCKED** (lugar no publicado) | harness; ver nota abajo |

## 2. GAME vs INFRAESTRUCTURA

Esta separacion es obligatoria en el informe. Un `BLOCKED` de
infraestructura **no** degrada el estado del juego, y un PASS de logica
**no** certifica el juego en ejecucion.

| Ambito | Veredicto | Motivo |
| --- | --- | --- |
| GAME | PARTIAL | Nucleo, bombas, destruccion, PvE, rondas, economia, inventario, tienda y progresion funcionan en servidor real |
| INFRAESTRUCTURA | BLOCKED | Cliente MCP inoperativo; DataStore real exige lugar publicado |

## 3. Matriz por categoria

`PASS` = ejecutado y correcto. `PARTIAL` = parte ejecutada, resto
bloqueado. `FAIL` = ejecutado y fallido. `BLOCKED` = no ejecutable en este
entorno. `NO IMPLEMENTADO` = no existe.

| Categoria | Estado | Evidencia / bloqueo |
| --- | --- | --- |
| UNIT | PASS | 350/350 `npm test` |
| STRUCTURE | PASS | `verify-structure.js` 33/33 |
| WIRING | PASS | `verify-wiring.js` |
| BUILD | PASS | `rojo build` |
| SYNC | PASS | `sync-scripts.js` 0 fallidos |
| SERVER RUNTIME | PASS | `probes/snapshot.lua`: ronda 43 en curso, 4 monstruos, 48 bloques |
| PLAYER RUNTIME | PARTIAL | jugador real presente y con vida/posicion; lado cliente BLOCKED |
| ROUND | PARTIAL | historico `Waiting>Countdown>RoundStarting>Playing>RoundEnding>Rewards>ReturningToLobby` correcto; faltan bloques de 25/50/100 rondas |
| BOMB | PARTIAL | servicio presente; falta la prueba de 100 explosiones sin residuos |
| DESTRUCTION | PARTIAL | 48 bloques vivos / 0 destruidos en el snapshot; falta la prueba de destruccion real encadenada |
| MONSTER | PARTIAL | 4 monstruos vivos; falta medir muerte simultanea y limpieza |
| COMBAT | PARTIAL | servicios reales; falta evidencia de daño y muerte en PLAY |
| REWARD | PASS (logica) | cadena `VALIDATE->AUTHORIZE->GRANT->RECORD` en `EconomyRules` + pruebas |
| ECONOMY | PASS | pruebas + `economy-cert` |
| INVENTORY | PASS (logica) | pruebas de equipar/desequipar/apilado |
| PROGRESSION | PASS | pruebas de subida multiple de nivel |
| SHOP | PASS (logica) | idempotencia, cobro antes de entregar, devolucion |
| PORTAL | PARTIAL | controlador y veredicto de servidor existen; **no** se puede observar el lado cliente (p adherido, overlay) |
| UI | **BLOCKED** | requiere `eval_client_runtime` para observar HUD, aperturas y cierres |
| CLEANUP | PARTIAL | Maid/RateLimiter probados; falta medir en runtime tras N rondas |
| SECURITY | **PASS (nuevo)** | `PayloadGuard` 10/10 vectores en runtime real + 26 pruebas |
| PERFORMANCE | BLOCKED | exige minutos de juego continuo observado |
| RECOVERY | PARTIAL | hay `Maid` y `Destroy`; falta la matriz de fallos simulados |
| REGRESSION | PASS (esta pasada) | esta matriz |

## 4. Seguridad: vectores probados en runtime

Ejecutados con `node tools/probes/payload-guard.lua server` **contra el
servidor en ejecucion**, no contra el repositorio.

| Vector | Resultado |
| --- | --- |
| `NaN` | RECHAZADO |
| `Infinity` | RECHAZADO |
| Numero normal | ACEPTADO |
| Negativo (`-1` como cantidad) | RECHAZADO |
| Billon (`1e18`) | RECHAZADO |
| Tabla ciclica | RECHAZADO (`too_deep`) |
| Codigo de control en cadena | RECHAZADO |
| Cadena de 5000 caracteres | RECHAZADO |
| Clave no permitida (`Admin`) | RECHAZADO |
| Aridad incorrecta | RECHAZADO |

Resultado: **10/10 rechazados, 0 concedidos.**

## 5. Lo que NO se puede certificar aqui (y no se marcara PASS)

| Ambito | Bloqueo |
| --- | --- |
| UI / HUD / inventario / tienda visibles | `eval_client_runtime` en tiempo de espera |
| Portales: prompt, cartel y overlay | idem |
| Mobile / gamepad / PC fisicos | no hay dispositivo real conectado |
| DataStore real | el lugar no esta publicado |
| Monetizacion real | sin IDs de pas/productos ni lugar publicado |
| Rendimiento sostenido | requiere sesion larga observada |

## 6. Bug del inventario del contexto (corregido)

`.ai/AI_CONTEXT.md` era un indice GENERADO y mentia de forma systematica:

- declaraba `Commit: 6faf509` cuando el arbol estaba en otro commit;
- decia `Servicios de servidor: 72` cuando hay **33**;
- decia `Controllers de cliente: 24` cuando hay **12**;
- decia `Suites de prueba: 0` cuando hay **21**.

Causas raiz, todas en `tools/generate-ai-context.js`:

1. los filtros comparaban con `/` y en Windows las rutas llegan con `\`;
2. el filtro de suites exigia `f.includes("tests/")`;
3. `.kilo/worktrees/` (una copia de trabajo del repo DENTRO del repo) se
   contaba como codigo propio, inflando los totales.

Un indice que miente sobre cuantos tests existen es peor que no tener
indice: dirige a leer evidencia que no existe.