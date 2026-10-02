# Auditoría completa del sistema

Fecha: 2026-10-02
Rama: `main` · HEAD: `c9fda9f` · Working tree: limpio al inicio
Remoto: `origin` → `https://github.com/Roblox2027/keshusytomy-land.git`
(5 commits por delante de `origin/main`. **No se ha hecho push.**)

---

# STATUS

| Componente | Estado | Evidencia |
| --- | --- | --- |
| Tests unitarios | **PASS** | 138 pasan, 0 fallan |
| Estructura de servicios | **PASS** | `verify-structure` 9/9 |
| Rojo build | **PASS** | exit 0, 170 instancias |
| Sourcemap | **PASS** | generado |
| Analizador estático | **INCONCLUSO** | 670 incidencias, en su mayoría entorno ausente |
| **Roblox Studio runtime** | **FALL** | el lugar abierto está VACÍO |
| **SOURCE ↔ RUNTIME** | **DIVERGE (P0)** | 170 instancias en build vs 6 en Studio |
| GAME PLAYABLE | **FAIL** | no se puede arrancar nada |

---

# ROOT CAUSES

## P0 — El juego no funciona en Studio porque **nunca llegó a Studio**

Esta es la causa raíz y explica por sí sola el reporte del usuario.

Evidencia directa del DataModel conectado por MCP:

```
Workspace            [4] Baseplate(Part), Camera(Camera),
                         SpawnLocation(SpawnLocation), Terrain(Terrain)
ReplicatedStorage    [0]
ServerScriptService  [0]
StarterGui           [0]
StarterPlayer        [2] StarterCharacterScripts, StarterPlayerScripts
```

Búsquedas que vuelven **0 resultados**:

### Por qué Rojo no lo arregla automáticamente

`rojo serve` está escuchando y responde en `localhost:34872` (HTTP 200), y el
plugin de Rojo de Studio está conectado a ese puerto. **Pero el lugar
abierto es `KeshusyTomy-LanD.rbxl`, un archivo `.rbxl` binario, no el
proyecto de Rojo.**

El plugin de Rojo solo inyecta el árbol cuando el lugar abierto es el
proyecto de Rojo, o cuando se pulsa **Sync**. Abrir un `.rbxl` arbitrario y
conectar el plugin **no** inyecta nada por sí solo.

`.gitignore` excluye `*.rbxl`, así que `KeshusyTomy-LanD.rbxl` es un
archivo local no versionado: es la baseplate vacía que el usuario guardó.

## P1 — El analizador estático no es utilizable como puerta

`luau-analyze` en modo standalone **no conoce el entorno Roblox**. No tiene
definiciones de `game`, `Instance`, `Vector3`, `CFrame`, `task`, `Enum`,
`warn`, `Player`, ni de los tipos de las APIs de Roblox.

Consecuencia: **275 de 670 incidencias (41%) son falsos positivos** que no
requieren tocar el código. Ver `problems-classification.md`.

Sin un `.luaurc` con las definiciones de Roblox, la herramienta produce
ruido y su salida **no puede usarse como criterio de calidad**. Ejecutarla
y contar errores lleva a "arreglar" código correcto.

## P2 — `RemoteGateway` tiene un defecto real de tipado

Independiente del entorno: es un bug de código genuino, no ruido.

```lua
-- RemoteGateway.lua:72-73
capacity = resolved.capacity or 10,
```

`resolved` es `options or {}`. El analizador lo tipa como
`{ } | { capacity: number?, refillPerSecond: number? }` y no puede probar

# SOURCE ↔ RUNTIME AUDIT

Comparación entre lo que Rojo **construye** y lo que Studio **tiene**.

| Servicio | Build de Rojo | Studio conectado | Estado |
| --- | --- | --- | --- |
| Instancias totales | 170 | 6 | **DIVERGE** |
| `ReplicatedStorage` | 1 (Shared, WorldDefinitions, Remotes) | 0 | **FALTA** |
| ├ `Remotes` | 1 Folder | 0 | **FALTA** |
| ├ 8 `RemoteEvent` | 8 | 0 | **FALTA** |
| ├ `Shared/Config` | 3 ModuleScript | 0 | **FALTA** |
| ├ `Shared/Constants` | 1 ModuleScript | 0 | **FALTA** |
| ├ `Shared/Libraries` | 5 ModuleScript | 0 | **FALTA** |
| ├ `Shared/Types` | 1 ModuleScript | 0 | **FALTA** |
| ├ `Shared/Utils` | 1 ModuleScript | 0 | **FALTA** |
| └ `WorldDefinitions` | 5 ModuleScript | 0 | **FALTA** |
| `ServerScriptService` | 1 + 30 + 2 | 0 | **FALTA** |
| ├ `ServerMain` | 1 Script | 0 | **FALTA** |
| ├ `Services` | 30 ModuleScript | 0 | **FALTA** |
| └ `Systems` | 2 ModuleScript | 0 | **FALTA** |
| `StarterGui/UI` | 1 Folder | 0 | **FALTA** |
| `StarterPlayer` | 1 + 12 | 0 | **FALTA** |
| ├ `ClientMain` | 1 LocalScript | 0 | **FALTA** |
| └ `Controllers` | 12 ModuleScript | 0 | **FALTA** |
| `Workspace` | 4 (Environment, Lobby, SpawnLocations, Worlds) | 4 (Baseplate, Camera, SpawnLocation, Terrain) | **DIVERGE** |
| └ `Lobby` | 9 Part | — | **FALTA** |
| └ `SpawnLocations` | 6 SpawnLocation | 1 genérico | **DIVERGE** |
| └ `Worlds/Forest` | 1 + 48 Block + arena | — | **FALTA** |
| `Lighting` | — | 5 efectos por defecto | — |
| `ServerStorage` | 0 | 0 | OK |
| `SoundService` | 0 | 0 | OK |
| `Teams` | 0 | 0 | OK |

**Conclusión: la divergencia es del 100%.** No hay una sola instancia del
proyecto presente en el lugar que se está ejecutando. `Workspace` coincide
solo en el número de hijos (4), y son objetos distintos: `Baseplate` en
lugar de `Lobby`, un `SpawnLocation` genérico en lugar de los 6.

Lo que sí es correcto y verificable:

- El proyecto de Rojo está bien: las rutas, los `require`, el mapa y los
  8 `RemoteEvent` se construyen sin errores.
- El `Remotes.model.json` usa un formato heredado (`ClassName` + `Children`)
  que Rojo 7 ya no soporta, **pero** Rojo 7.7.0 lo sigue interpretando y
  produce los 8 `RemoteEvent` correctamente. Verificado en el build, no
  asumido. Es deuda técnica, no un fallo actual.
- No hay servicios duplicados, ni controllers duplicados, ni remotos
  duplicados, ni rutas inconsistentes.

que `resolved.capacity` exista en la rama `{}`. Requiere una anotación
explícita del tipo en el `or`.

---



---

# INVENTARIO (FASE 0.1)

**Shared** (ReplicatedStorage/Shared)
`Config/` GameConfig, FeatureConfig, PerformanceConfig ·
`Constants/` GameConstants · `Libraries/` Maid, RateLimiter, RemoteSchema,
StateMachine, CombatMath · `Types/` Types · `Utils/` Logger

**WorldDefinitions**: Forest, Desert, Ice, Volcano, Cyber

**Remotes** (8, todos declarados, todos usados por el gateway):
PlayerAction, BombAction, ShopAction, InventoryAction, QuestAction,
PortalAction, PartyAction, SettingsAction

**Server** — `ServerMain` + `Systems/` (ServiceRegistry, RemoteGateway) +
`Services/` × 30

**Controllers** (12): Audio, Bomb, Camera, Effects, Input, Inventory,
Mobile, Party, Portal, Shop, UI + ControllerRegistry

**Tests** (10 suites, 138 tests): Maid, RateLimiter, StateMachine,
RemoteSchema, GameConfig, CombatMath, Destruction, Gameplay,
ServiceStructure, BootWiring

**Mapa**: Lobby (9 Part + 6 SpawnLocation) + Forest (ArenaFloor,
ArenaCenter, 48 bloques destructibles, estructura central 3×3×3)

### Servicios registrados (9) vs servicios presentes (30)

Solo 9 de los 30 servicios se registran en `ServerMain`:

WorldService, SpawnService, DestructionService, RoundService,
CombatService, PlayerService, ExplosionService, BombService, MatchService

Los otros 21 (MonsterService, AIService, DataService, EconomyService,
ProfileService, ProgressionService, InventoryService, ShopService,
QuestService, PartyService, PortalService, TeleportService, AnalyticsService,
MonetizationService, CodeService, BadgeService, EventService,
AnnouncementService, ModerationService, ReportService,
MatchmakingService) están escritos y se compilan, pero **no se registran ni
se arrancan**. No están muertos por error: son fases futuras (9+). No se
tocan. Queda documentado para que no se confundan con un olvido.

### Grafo de dependencias (servicios activos)

```
WorldService
├── SpawnService
├── DestructionService ──┐
├── RoundService         │
│   ├── CombatService <──┘
│   │   ├── PlayerService
│   │   └── ExplosionService <── DestructionService
│   │       └── BombService

---

# FIXES

En esta tanda **no se ha modificado código de producción**. Los cambios son
de diagnóstico:

| Archivo | Propósito |
| --- | --- |
| `tools/studio-mcp.js` | Cliente HTTP del MCP de Studio, con autenticación por token. Permite auditar el DataModel real en vez de solo el filesystem. |
| `tools/audit-probe.lua` | Sondea el árbol real de los 9 servicios clave del lugar conectado. |
| `tools/classify-problems.js` | Agrupa las incidencias del analizador por causa raíz y separa falsos positivos de defectos reales. |

Motivo de no tocar producción: el único defecto de código confirmado
(`RemoteGateway` P2) no impide que el juego funcione, y la causa P0 no está
en el código sino en cómo se abrió el lugar. Arreglar tipado antes de
montar el proyecto en Studio sería trabajo sin verificar.

---

# TESTS

```
PRUEBAS: 138 pasaron | 0 fallaron
RESULTADO: PASS
```

Nota: la primera ejecución devolvió código 1 sin salida visible; al
capturar stdout correctamente son 138/138. La diferencia era de captura,
no de resultado.

---

# COMPILE

`luau-compile` implícito: los tests cargan los 10 módulos compartidos, lo
que exige que analice y ejecute cada uno. Si hubiera un error de sintaxis,
la suite no cargaría.

---

# ROJO

```
rojo.exe build -o temp-build.rbxlx   ->  exit 0
170 instancias · 8 RemoteEvent · 30 servicios · 12 controllers
```

Estructura verificada instancia por instancia contra el árbol esperado.

---

# MCP / STUDIO

- Token encontrado en `~/.robloxstudio-mcp/auth-token` (65 bytes).
- 48 herramientas disponibles; 6 usadas en esta auditoría.
- Studio conectado: `instance:vld-24b`, lugar `KeshusyTomy-LanD.rbxl`.
- **El lugar está vacío.** Ver tabla SOURCE ↔ RUNTIME.

---

# PROBLEMS

670 incidencias del analizador, agrupadas en 4 causas raíz:

| Causa raíz | Incidencias | Severidad |
| --- | --- | --- |
| Falta la definición del entorno Roblox | 202 | INFO (falso positivo) |
| `require` con ruta dinámica (`WaitForChild`) | 51 | INFO (falso positivo) |
| Consecuencia de `Instance` sin tipo | 22 | INFO (falso positivo) |
| Defecto de tipado real | 395 | P2 |

**395 siguen siendo P2, no P0.** Casi todas son consecuencia en cascada de
que `Instance` sea `unknown` (al perder el tipo se pierde también el de
todo lo que se le llama). Sin las definiciones de Roblox no es posible
separar el defecto genuino del ruido, y por eso la puerta de análisis
estático queda **INCONCLUSA**, no en rojo.

Detalle completo en `problems-classification.md`.

---

# RUNTIME

| Gate | Estado |
| --- | --- |
| SERVER START | **FAIL** — no hay código en el lugar |
| CLIENT START | **FAIL** — ídem |
| SPAWN | **NO EJECUTADO** |
| ROUND / BOMB / EXPLOSION | **NO EJECUTADO** |
| DAMAGE / DEATH / RESULTS | **NO EJECUTADO** |
| LOBBY | **NO EJECUTADO** |

Ninguna puerta puede evaluarse. No se declara PASS por ausencia de errores:
no hubo ejecución.

---

# SECURITY

No evaluable en runtime. La revisión estática del diseño es favorable:
`RemoteGateway` centraliza la validación en 6 pasos (servidor aceptando →
emisor real → canal registrado → acción en esquema → rate limit → forma del
payload) y el cliente no es autoridad de nada. **Pendiente de verificación
en ejecución** (FASE 53).

---

# PERFORMANCE

No evaluable. `StreamingEnabled: false` está fijado a propósito en el
proyecto; con 170 instancias es aceptable, pero debe medirse.

---

# GIT

Working tree limpio salvo los 3 archivos de diagnóstico nuevos. Sin push.
Remote sin cambios.

---

# CURRENT PHASE

**FASE 0 — completada como auditoría. FASE 1 (ServiceRegistry): auditada,
no ejecutable todavía.**

El bloqueo no es de código. El proyecto de Rojo es correcto y completo
para las fases 0–8. Falta montarlo en el lugar de Studio.

---

# BLOCKERS

**B1 — El lugar de Studio no contiene el proyecto.** Acción humana
requerida. Sin esto no hay runtime que verificar y las fases 1–8 no pueden
certificarse.

**B2 — El analizador no tiene definiciones de Roblox.** Acción humana
requerida para el archivo de definiciones. Mientras tanto, la puerta de
análisis estático no es concluyente.

---

# NEXT PHASE

Montar el proyecto en Studio y volver a ejecutar la auditoría runtime.
Cuando el servidor arranque, la cadena a verificar es la de
`docs/studio-diagnostic.md` (pasos 1 a 7), que ya está escrita y es válida.

FASE 9 (Monsters) **no** comienza: depende de fases 0–8 certificadas en
runtime, y hoy ninguna lo está.

│   └── ...
└── MatchService <── RoundService, PlayerService, BombService,
                      DestructionService
```

**Sin ciclos.** Verificado: el orden topológico es consistente con el
campo `dependencies` de cada entrada, y `ServerMain.wireDependencies()`
inyecta después de `InitAll` y antes de `StartAll`, que es el único orden
en que las referencias tienen sentido.

| Búsqueda | Resultados | Lo esperado |
| --- | --- | --- |
| `ServerMain` | 0 | 1 (Script) |
| `ArenaFloor` | 0 | 1 (Part) |

El lugar abierto en Studio es la **plantilla vacía por defecto de Roblox**.
Tiene `Baseplate` y un `SpawnLocation` genérico, que son los que Studio crea
al hacer `File → New`. No hay ni un solo script del proyecto dentro.

`ServerScriptService` con 0 hijos significa que **`ServerMain.server.lua`
nunca se ha ejecutado**. Por eso no hay Output, ni `[BOOT]`, ni errores de
Luau, ni nada: no hay código corriendo. El juego "no funciona" porque no
está montado en el lugar que se está ejecutando.
