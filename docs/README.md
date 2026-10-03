# Documentacion

| Documento                              | Contenido                                  |
| -------------------------------------- | ------------------------------------------ |
| `architecture.md`                      | Capas, reglas de diseno, flujo de datos    |
| `phases.md`                            | Plan de fases y formato de reporte         |
| `workspace.md`                         | Convenciones de Workspace y mundos         |
| `full-system-audit.md`                 | **Auditoría completa: estado, causas raíz** |
| `problems-classification.md`           | **Problems por causa raíz y severidad**    |
| `problems-before-after.md`             | **Línea base y criterio de medición**      |
| `studio-diagnostic.md`                 | Qué mirar en Studio, paso a paso           |
| `runtime-audit.md`                     | Revisión de diseño de los sistemas         |
| `studio-certification.md`              | Evidencia de certificación                  |
| `audit.md`                             | Auditoría de la fase 1                     |
| `phase-00-bootstrap.md`                | Reporte de la fase 0                      |
| `phase-01-foundation.md`                | Reporte de la fase 1                      |
| `vertical-slice.md`                    | Objetivo funcional de la primera version   |

## Herramientas de auditoría

| Herramienta | Para qué |
| --- | --- |
| `node tools/studio-mcp.js list` | lista las herramientas del MCP de Studio |
| `node tools/studio-mcp.js <herramienta> <valor>` | consulta el Studio real |
| `node tools/studio-mcp.js execute_luau --file <ruta>` | ejecuta Luau en el Studio conectado |
| `node tools/classify-problems.js` | agrupa los problemas por causa raíz |
| `node tools/verify-structure.js` | comprueba que los servicios estén bien formados |
| `node tools/audit-rbxlx.js <archivo>` | vuelca el árbol de un `.rbxlx` construido |
| `tools/luau/luau.exe tests/RunTests.lua` | ejecuta la suite |

Convencion: los reportes de fase se archivan como `phase-NN-<nombre>.md`.

## MCP de Roblox Studio

El puente hacia Studio lo da `@chrrxs/robloxstudio-mcp`. Son dos piezas y
las dos tienen que estar arriba:

1. **Servidor MCP** (lo lanza el cliente, por eso no hay proceso manual).
   Configurado en la config MCP de Cline:
   `npx -y @chrrxs/robloxstudio-mcp@latest --auto-install-plugin`.
   El servidor abre `http://127.0.0.1:58741/mcp` y autentica con el token
   de `~/.robloxstudio-mcp/auth-token`.
2. **Plugin de Studio** (`MCPPlugin.rbxmx`, en
   `%LOCALAPPDATA%\Roblox\Plugins`). Sin el, el puerto 58741 escucha pero
   `get_place_info` y `execute_luau` se quedan esperando.

Comprobacion rapida del estado del puente:

```powershell
Get-NetTCPConnection -State Listen | Where-Object LocalPort -eq 58741
node tools/studio-mcp.js list
```

Si el puerto no escucha, el servidor MCP no esta corriendo todavia. Si
escucha pero las herramientas no responden, el plugin no se ha conectado:
Studio tiene que estar abierto y el plugin habilitado en la pestana
Plugins.
