# KESHUSYTOMY-LAN-D - CONTEXTO IA

Generado: 2026-10-03T02:14:39.233Z (actualizado manualmente tras los bloques
de codigos, misiones, anti-exploit y party)

> Este archivo es un INDICE generado, no una fuente de verdad.
> La fuente de verdad del estado del desarrollo es `docs/phases.md`.
> Si este archivo y `docs/phases.md` se contradicen, gana `docs/phases.md`.

## Git

- Rama: `main`
- Commit local: `9887e47` - fix(juego): el lobby ya tiene salidas y las bombas
  funcionan en los cinco mundos
- Arbol: limpio salvo `docs/README.md` y `Install-RobloxAIKit.ps1`, que son
  preexistentes y ajenos a este bloque
- PUSH: **FUNCIONA**. El bloqueo documentado antes (`git push` colgaba) ya no se
  reproduce: `e9a12b0..9887e47 main -> main` en menos de 100 s. `HEAD` y
  `origin/main` coinciden en `9887e47`.

## FUENTES DE VERDAD (leer antes de decidir)

| Documento | Rol |
| --- | --- |
| `docs/phases.md` | estado real por fase (PASS / BLOCKED / NO INICIADA) |
| `docs/architecture.md` | capas y reglas de diseno |
| `docs/audit.md` | auditoria de la fase 1 |
| `docs/runtime-source-diff.md` | diferencias runtime vs source |
| `docs/sync-defects.md` | defectos de sincronizacion conocidos |
| `.ai/spec/GAME_SPEC.md` | reglas de producto (indice, no estado) |
| `.ai/qa/ACCEPTANCE_TESTS.md` | checklist de aceptacion |
| `tools/README.md`, `tests/README.md` | convenciones de herramientas y pruebas |

## ULTIMA VERIFICACION DEL ENTORNO

| Rojo build | PASS |
| Suite Luau | RESULTADO: PASS |
| verify-structure | OK |
| verify-wiring | OK |
| analyze.js (typecheck) | FAIL |
| Studio/MCP | CONECTADO |

> analyze.js esta en FAIL. Es previo a este bootstrap (521 incidencias tambien sin estos archivos) y corresponde a `.ai/qa/ACCEPTANCE_TESTS.md`, no al entorno. No se maquilla como PASS ni se oculta.

## Convenciones

- Layout de pruebas: `tests/shared`, `tests/server`, `tests/client`
- Nombre de suite: `<Modulo>.<Area>.spec.lua`
- Ejecutar: `tools\luau\luau.exe tests\RunTests.lua`
- Analisis estatico de autoridad: `node tools/analyze.js`
  (prelude `tools/roblox-definitions/RobloxEnvironment.lua`; **no** usar
  `luau-analyze` pelado, produce cientos de falsos positivos)
- Rojo local: `rojo\rojo.exe` (ignorado por git a proposito)

## Inventario de fuente (MEDIDO, no supuesto)

- Servicios de servidor: 33 -> **23 reales, 10 stub**
- Controllers de cliente: 12 -> **6 reales, 6 stub**
- Suites de prueba: 29
- Pruebas: **499 pasan / 0 fallan**

### Los 10 servicios de servidor que SIGUEN siendo stub

Se identifican por tener menos de 40 lineas (los implementados tienen mas):

Analytics, Announcement, Badge, Event, Matchmaking, Moderation,
Monetization, Party, Report, Teleport.

> `PartyService` sigue siendo un stub, pero su LOGICA ya esta implementada y
> probada en `PartyRules` (30 pruebas). Falta el servicio que la aplique.

### Los 6 controllers de cliente que siguen siendo stub

Camera, Effects, Inventory, Mobile, Party, Shop.

> `InventoryController` y `ShopController` son los dos que bloquean la UI de
> inventario y de tienda. Hasta que existan, la UI NO puede certificarse.

## Bloqueos de infraestructura (NO son fallos de codigo)

- DataStore real: sin lugar publicado -> **HARNESS**, nunca PASS.
- Cliente MCP: **RESUELTO (2026-10-03)**. El "bloqueo" era que el servidor MCP
  no estaba arrancado. Se arranca con `npx -y @chrrxs/robloxstudio-mcp@latest`
  y con eso `eval_server_runtime`, `eval_client_runtime` y
  `simulate_keyboard_input` responden. La certificacion de jugador con teclado
  REAL ya se hizo: ver `.ai/reports/CURRENT_VISUAL_STATE.md`.
- `capture_screenshot` sigue sin capturar el viewport del cliente en marcha
  (`StudioCaptureService cannot capture this DataModel right now`). La
  certificacion VISUAL continua pendiente.

## REGLA INNEGOCIABLE

Ninguna funcionalidad esta terminada porque el archivo exista.
Solo esta terminada cuando se verifico la cadena completa:

    SOURCE -> BUILD -> ROJO -> STUDIO -> PLAY -> PLAYER -> INPUT
    -> SERVER -> RESULTADO -> REWARD/PERSISTENCIA -> QA

Un script que lee archivos demuestra que los archivos existen. No
demuestra nada sobre el juego en ejecucion. Para eso esta
`tools/diagnostics/runtime-scan.js`, que consulta Studio via MCP y
reporta `BLOCKED` cuando no puede comprobarlo.
