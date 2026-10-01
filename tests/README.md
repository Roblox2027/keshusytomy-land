# tests

Suite de pruebas del proyecto.

| Carpeta  | Alcance                                                |
| -------- | ------------------------------------------------------ |
| `shared/` | Modulos puros compartidos (sin servicios de Roblox)     |
| `server/` | Servicios de servidor con entorno simulado             |
| `client/` | Controllers y presentacion                             |

Convencion de nombres: `<Modulo>.<Area>.spec.lua`

Herramienta objetivo: TestEZ (se integra en la FASE 38 - QA).
Mientras TestEZ no este configurado, esta carpeta queda reservada
y no contiene stubs que aparenten cobertura real.
