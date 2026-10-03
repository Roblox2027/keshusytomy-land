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
| `HEAD` | `d3fcb13` | `git rev-parse HEAD` |
| `HEAD == origin/main` | SI | ambos `d3fcb13` |
| Arbol | limpio salvo `Install-RobloxAIKit.ps1` (bootstrap preexistente, NO tocar) | `git status --short` |
| Suite Luau | **372/372 PASS** | `npm test` |
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
| UNIT | PASS | 372/372 `npm test` |
| STRUCTURE | PASS | `verify-structure.js` 33/33 |
| WIRING | PASS | `verify-wiring.js` |
| BUILD | PASS | `rojo build` |
| SYNC | PASS | `sync-scripts.js` 0 fallidos |
| SERVER RUNTIME | PASS | `probes/snapshot.lua`: ronda 169 en curso, 4 monstruos, 48 bloques, 0 atascos |
| PLAYER RUNTIME | PARTIAL | jugador real presente; lado cliente BLOCKED |
| ROUND | PARTIAL | historico correcto y 169 rondas seguidas sin atascos; faltan bloques de 25/50/100 **con metricas** |
| BOMB | PARTIAL | servicio presente; falta la prueba de 100 explosiones sin residuos |
| DESTRUCTION | PARTIAL | 48 bloques vivos / 0 destruidos; falta destruccion encadenada medida |
| MONSTER | PARTIAL | 4 monstruos vivos; falta muerte simultanea y limpieza |
| COMBAT | PARTIAL | servicios reales; falta evidencia de dano/muerte en PLAY |
| REWARD | PASS (logica) | cadena `VALIDATE->AUTHORIZE->GRANT->RECORD` probada |
| ECONOMY | PASS | pruebas + `economy-cert` |
| INVENTORY | PASS (logica) | equipar/desequipar/apilado |
| PROGRESSION | PASS | subida multiple de nivel |
| SHOP | PASS (logica) | idempotencia, cobro antes de entregar, devolucion |
| **CODES (reglas)** | **PASS** | `CodeRules` 22 pruebas + 14/14 en runtime real |
| **CODES (servicio)** | **NOT IMPLEMENTADO** | `CodeService` sigue siendo un stub: las reglas existen y estan probadas, pero no hay servicio que las conecte a `EconomyService` ni al remoto |
| PORTAL | PARTIAL | controlador y veredicto de servidor existen; no observable desde el cliente |
| UI | **BLOCKED** | requiere `eval_client_runtime` |
| CLEANUP | PARTIAL | Maid/RateLimiter probados; falta medir en runtime tras N rondas |
| SECURITY | **PASS (nuevo)** | `PayloadGuard` 10/10 vectores en runtime + 26 pruebas |
| PERFORMANCE | BLOCKED | exige minutos de juego continuo observado |
| RECOVERY | PARTIAL | hay `Maid` y `Destroy`; falta la matriz de fallos simulados |
| REGRESSION | PASS (esta pasada) | esta matriz |

## 3-bis. Codigos: que esta probado y que NO

Muy importante para no leer de mas lo hecho:

**PROBADO (logica pura + runtime)**

| Propiedad | Evidencia |
| --- | --- |
| El mismo codigo no se paga dos veces | 100 intentos -> 1 recompensa |
| 50 repeticiones seguidas -> 1 recompensa | probe en runtime |
| Variantes de escritura cuelan igual (`keshusy-2026`) | `already_used` |
| El canje sobrevive a la reconexion | perfil recargado, sigue rechazado |
| Otros jugadores si pueden canjearlo | 3 jugadores -> contador global 3 |
| `MaxRedemptions` agota para todos | 4o jugador -> `exhausted` |
| Codigo caducado rechazado | `expired` |
| Codigo inexistente sin dejar rastro | `unknown` |
| Recompensa negativa/fraccionaria/NaN rechazada al DEFINIR el codigo | `bad_amount` |
| Perfil viejo sin las tablas no rompe | migracion |
| Estado corrupto rechazado sin conceder | `invalid_state` |

**NO PROBADO (y no se da por hecho)**

- `CodeService` sigue siendo un stub. Las reglas son correctas, pero
  ningun remoto las invoca todavia, asi que **un jugador no puede
  canjear un codigo todavia**. Las reglas son la pieza critica, no el
  sistema completo.

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