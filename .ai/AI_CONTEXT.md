# KESHUSYTOMY-LAN-D - CONTEXTO IA

Generado: 2026-10-07T13:32:26.336Z

> Este archivo es un INDICE generado, no una fuente de verdad.
> La fuente de verdad del estado del desarrollo es `docs/phases.md`.
> Si este archivo y `docs/phases.md` se contradicen, gana `docs/phases.md`.

## Git

- Rama: `main`
- Commit: `6545120` - FASE 2 COMPLETED: pass consolidacion estado/git/continuidad. HEAD=origin/main=41a2a94. Arbol limpio. STATE.json sincerado. Todos los .cline files actualizados.
- Arbol: limpio

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

## Inventario de fuente

- Luau total: 284
- Servicios de servidor: 43
- Controllers de cliente: 13
- Suites de prueba: 55

## REGLA INNEGOCIABLE

Ninguna funcionalidad esta terminada porque el archivo exista.
Solo esta terminada cuando se verifico la cadena completa:

    SOURCE -> BUILD -> ROJO -> STUDIO -> PLAY -> PLAYER -> INPUT
    -> SERVER -> RESULTADO -> REWARD/PERSISTENCIA -> QA

Un script que lee archivos demuestra que los archivos existen. No
demuestra nada sobre el juego en ejecucion. Para eso esta
`tools/diagnostics/runtime-scan.js`, que consulta Studio via MCP y
reporta `BLOCKED` cuando no puede comprobarlo.
