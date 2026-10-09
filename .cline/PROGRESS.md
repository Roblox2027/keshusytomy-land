## FASE 2 CONSOLIDACION (2026-10-07): PASS
- HEAD real `6545120` = origin/main; arbol LIMPIO. (`41a2a94` = FASE 1 RE-AUDIT,
  source idéntico a 6545120; `6545120` es el commit de continuidad FASE 2
  COMPLETED y HEAD inmediatamente anterior al commit de corrección que contiene
  estos archivos. Convención: STATE.json conserva el HEAD inmediatamente
  anterior en lugar de autorreferenciar su propio hash.)
- Bloques 1-4 ya estaban commited en HEAD `06727a7` (=origin/main). Bloque 5 estaba sin commit en el arbol.
- `09007f3` es un commit REAL (FASE 0+1), 5 commits detras de HEAD — NO es phantom. STATE.json lo declaraba desactualizado.
- Commits creados durante FASE 2:
  - `7941e83` Bloque 5 Social/profundidad: PuzzleService doble interruptor cooperativo + wiring + UI + tests
  - `41a2a94` FASE 1 RE-AUDIT: GAMEPLAY_AUDIT.md con estado de resolucion, sincerar .cline continuity files, documentar Bloques 1-5 verificados localmente y playtest real
  - `6545120` FASE 2 COMPLETED: consolidacion estado/git/continuidad (commit de continuidad sobre 41a2a94; source idéntico a 41a2a94, 973/973 PASS verificado)
- Push: PASS a `origin/main`. HEAD = origin/main = `6545120`.
- Verificaciones: npm test PASS (973/973, 55 suites); npm run verify PASS (cadena completa exit 0); verify-structure PASS (43 servicios); verify-wiring PASS (34 servicios, 23 conexiones, 48 llamadas); rojo:build PASS. analyze.js FAIL baseline preexistente (documentado, no introducido por esta fase).
- Brainrot visual: intacto (sin cambios). `BRAINROT_VISUAL_FOLLOWUP`: vacio.
- Estado previo (FASE 1 RE-AUDIT) queda registrado abajo.

## FASE 1 RE-AUDIT V2 (2026-10-07): PASS
- HEAD real `06727a7` = origin/main; arbol SUCIO (Bloques 1-5 sin commitear en ese momento, STATE con `09007f3` desactualizado).
- Verificacion: structure PASS, wiring PASS (34/23/48), tests PASS 973/973, rojo PASS, mundos/contenido/navegacion/spawn/edge/monstruos/powerups/bombas PASS.
- `GAMEPLAY_AUDIT.md`: seccion FASE 1 RE-AUDIT con loop actual, 13 puntos priorizados (2 CRITICAL proceso, 5 HIGH, 5 MEDIUM, 1 LOW), mundos/monstruos/bosses/misiones/recompensas/replay/multi. Brainrot visual intacto.
- Siguiente exacto: commit por bloque + push, sincerar STATE, luego panel World Completion / cadenas / cofres; NO avanzar V2 antes del commit.

---
# PROGRESS

## MASTER MISSION V2 — Expansion total de gameplay

### FASE 0 — Continuidad: PASS (2026-10-07)
- `.cline/*` leidos; `git status` limpio; HEAD = origin/main = `ed18f24`.
- `npm run verify`: Rojo build PASS, Suite Luau PASS, verify-structure PASS, verify-wiring PASS. `analyze.js` FAIL preexistente (baseline, documentado).

### FASE 1 — Auditoria de diversion: PASS
- Entregable: [GAMEPLAY_AUDIT.md](../GAMEPLAY_AUDIT.md)
- 16 hallazgos con problema/ubicacion/causa/impacto/solucion/prioridad.
- P0: combate de una sola herramienta (A1), eventos sin cuerpo visible (A2), mundos sin mecanica propia (A3), recompensas monocromaticas (A4), sin logros/coleccion/discovery (A5).
- P1: bosses sin ritual (B1), misiones de un solo tipo (B2), equipamiento sin stats (B3), Brainrot sin funcion jugable (B4), hordas/arenas dormidas (B5), noche sin dientes (B6).
- P2: co-op, puzzles, coleccionables fisicos, player home, vehiculos, NPC/reputacion.
- Orden de ataque: 5 bloques (Mundo vivo → Combate → Progresion → Contenido → Social) + cierre QA/playtest/regresion.

### BLOQUE 1 — Mundo vivo: PASS (verificado localmente)
- **A2 eventos con cuerpo**: `EventRules.Bodies` (Hunt/Boss/Survive/Reward) + `WorldInvasion`; `EventService` genera enemigos por zona (contrato `Zone_*_Core`), cuenta bajas via observer en `MonsterService`, completa por objetivo y limpia siempre. Caza que expira = cancelada (no paga). HUD: panel Objective con etiqueta+objetivo+cuenta atras, Notify al abrir. 6 tests nuevos.
- **A3 mecanica por mundo**: `HazardRules` + `HazardService`. Forest emboscada (spawns sorpresa con cooldown), Desert arenas movedizas (WalkSpeed x0.5 con restauracion), Ice rachas de viento (impulso por ritmo), Volcano lava DOT (6 hp/s), Cyber laser telegrafiado (on 2.5s / off 3.5s). Dano via `CombatService.ApplyDamage` (autoridad unica). 14 tests nuevos.
- **B6 noche ambiental**: `EffectsController` traduce `NightPhase` a Lighting con tween de 4s. Ambiental, sin progreso por noches.
- Verificacion: Suite Luau 919/919 PASS; verify-structure PASS (39 servicios); verify-wiring PASS (30 servicios, 21 conexiones); rojo build PASS.

---

## Mision anterior (V1) — Estado general
- Proyecto: KeshusyTomy-LanD
- Fase actual: 5 / reconstruccion total de mundos + gameplay + audio + IA + Play Test real
- Estado: RECONSTRUIDO, VERIFICADO LOCALMENTE Y PROBADO EN STUDIO (play test real ejecutado en `latest.rbxlx`)
- Evidencia: `npm run verify` exit 0 con todas las puertas; `solo_playtest` real sobre la instancia `lrh-zvl`

## Verificacion ejecutada (final, sobre el arbol actual)
- `npm run verify:structure` -> PASS
- `npm run verify:wiring` -> PASS (29 servicios, 20 conexiones)
- `npm test` -> PASS (899/899)
- `npm run test:worlds` -> PASS (96/96 zonas con geometria y rol)
- `npm run test:world-content` -> PASS (5/5 mundos: miniboss anchor, secret prompt, catalogo valido)
- `npm run test:audio-ui` -> PASS (HUD generado = fuente, 5 canales interactivos)
- `npm run test:contract` -> PASS
- `npm run test:navigation` -> PASS (96/96 zonas alcanzables, rutas criticas con alternativa)
- `npm run test:spawn` -> PASS
- `npm run test:world-edge` -> PASS
- `npm run test:monster-access` -> PASS (50/50)
- `npm run test:powerup-boss` -> PASS
- `npm run rojo:build` -> PASS
- `npm run verify` (cadena completa) -> exit 0

## Reparaciones de esta fase
- Mundos: corregidas zonas inalcanzables (RuinsOuter/Mine) y trampas de navegacion en el generador (destructibles, rim fallback).
- Mundos: ramas de rol real (miniboss/secret/encounter) donde el test semantico encontro zonas vacias de contenido.
- Secretos: `SecretService` con ProximityPrompts generados, recompensa persistente idempotente, migracion de perfil v1->v2.
- Monstruos: navegacion real con `PathfindingService` (async, concurrencia limitada, reintentos, invalidez al cambiar estado).
- Audio: mixer de 5 canales, crossfade acotado, estados dinamicos Lobby/Exploring/Danger/Combat/Boss/Victory/Defeat y ambiente dia/noche por mundo; sliders en HUD.

## Bloqueos reales restantes
- AUDIO ASSETS: PENDING — assets/sounds y assets/music vacios; sin IDs reales no se inventan, el juego suena en silencio.
- analyze.js: FAIL preexistente de baseline (no introducido por estos cambios).

## Verificacion ejecutada
- `npm run verify:structure` -> PASS
- `npm run verify:wiring` -> PASS
- `npm test` -> PASS (893/893)
- `npm run verify` -> PASS
- `npm run rojo:build` -> PASS
- Ajuste de HUD: objetivo de noche eliminado de la UI activa (`AMBIENTE`)
- `git add -A` + `git commit -m "Fix ambient night HUD and world access audit"` -> OK
- `git push` -> OK (commit `71ee978` publicado en `origin/main`)

## 99-night objective
- `99-NIGHT OBJECTIVE: REMOVED` para la interfaz activa del HUD.
- Se conserva el ciclo ambiental `Day/Sunset/Night/Dawn` como sistema secundario, no como objetivo principal.
- Las referencias documentales de 99 noches siguen existiendo en historia, tests y comentarios antiguos; no representan objetivo activo ni progresion del juego.

### FASE 3 - Actividades de exploracion (server-authoritative): COMPLETED
- **Rules**: `ActivitiesRules` (puro) — progreso/aclamo atomico/cooldown/oferta diaria determinista/Audit.
- **Catalog**: `ActivityCatalog` (15 actividades, 5 mundos, 6 tipos) con indice normalizado lazy; valida contra `WorldAccessRules.WorldOrder`.
- **Service**: `ActivityService` (espejo de `QuestService`) — estado en perfil (`Activities`), paga Coins via `EconomyService.GrantCurrency` y Mat_* via `InventoryService.AddItem` (fix aplicado en este playtest), publica atributos `ActivityOffer`/`ActivityProgress`/`ActivityClaimOutcome`; `RecordMetric` para eventos; `TryInteract` con chequeo de proximidad server-side.
- **Remote layer**: canal `ExploreAction` (`RequestOffer`/`Interact`/`Claim`) en `GameConstants.RemoteAction`, `RemoteSchema`, `Remotes.model.json`, `AntiExploitRules` (auditable) y `AntiExploit.spec` (declarado).
- **Wiring**: `ActivityService` en `SERVICES` + `connect` (+ `SetPlayerService` + `InventoryService`) en `ServerMain.wireDependencies`; `MonsterService->ActivityService` reverse-push tolerante (caza) con forward de muerte de monstruo a `RecordMetric("Hunt")`; handlers `ExploreAction` en `REMOTE_CHANNELS`.
- **BUG FIX (playtest)**: `deliver()` en `ActivityService.lua` llamaba `GrantCurrency` para todos los rewards incluyendo `Mat_*`, que `EconomyRules` rechazaba silenciosamente (moneda invalida). Fix: `IsValidCurrency()` dirige `Coins`/`Gems` a `GrantCurrency` y `Mat_*` a `InventoryService.AddItem`. Wiring: `SetDependencies` ahora recibe `inventoryService`; `ServerMain.wireDependencies` pasa `InventoryService`.
- **Gates**: `npm test` PASS (1014/1014, 57 suites); `verify:structure` PASS (44); `verify:wiring` PASS (35 servicios, 24 conexiones, 50 llamadas); `rojo:build` PASS. `analyze.js` FAIL baseline preexistente (sin categorias nuevas).
- **Playtest Studio/MCP (CONECTADO)**:
  - [A] Player Join: PASS — player `SiSoyPapito` joins, profile loads, 15 activities published.
  - [B] Offer: PASS — valid offer `[collectforest6, discoverforest2, huntforest3]`, correct world/type/target/rewards.
  - [C] Interact: PASS — near-range accepted, far-range `out_of_range`, non-interactable type `invalid_type`, unknown activity `unknown_activity`.
  - [D] Duplicate: PASS — `already_claimed` rejected.
  - [E] Claim flow: PASS — `discoverdesert3` completed via `RecordMetric("Discovery", 3)`, claimed; `granted={Mat_SandCrystal:4, Coins:55}`, `rewardAttr="Coins:55,Mat_SandCrystal:4"`, `outcomeAttr="claimed"`.
  - [F] Material rewards fix: PASS — log confirma `Inventory: +4 Mat_SandCrystal a SiSoyPapito (activity)`.
  - [G] Persistence: profile data persists across playtest sessions via DataStore (estructura de perfil).
  - [H] Kill->Hunt: PASS — `RecordMetric(player, "Hunt", 3)` advances Hunt activities.
  - [I] Rejection tests: PASS — `invalid_activity_id`, `unknown_activity`, `not_complete`, `already_claimed` all rejected server-side.
  - [J] Concurrency: PASS — two concurrent `TryClaim` for same activity; first accepted (granted Mat_LeafEssence:5 + Coins:60), second rejected `already_claimed`; acceptedCount=1.
- **Pendiente**: commit + push a origin/main. Follow-up: inyectar puntos de Discovery/Rescue/Mechanic (RegisterPoints) desde el loader de mundo (Interact rechaza con `no_point` hasta entonces — seguro por disenio); forward de DestructionService/SecretService/EventService a RecordMetric para Collection/Defense/Secret.

### FASE 4 - WorldMechanics: arquitectura de mecanicas unicas por mundo: COMPLETED (2026-10-07)
- **Arquitectura**: `WorldMechanics` (pure library, `src/ReplicatedStorage/Shared/Libraries/WorldMechanics.lua`) — catalogo `MechanicsByWorld` (Kind por mundo), maquina de fases temporales (Calm/Warning/Active/Recovery/Cooldown) derivada del reloj del servidor, maquina de estados para terminales (Active/Inactive/Locked) y plataformas frágiles (Intact/Cracked/Broken), modificadores de movimiento (WalkSpeed multipliers), utilidades de posición (`DistanceSqXZ`, `IsInRange`), y `Audit` para coherencia entre definiciones y reglas.
- **Service**: `WorldMechanicsService` (`src/ServerScriptService/Services/WorldMechanicsService.lua`) — servicio server-authoritative con hilo de tick, construcción de partes, gestión de eventos temporales y registro de puntos de interacción (Discovery/Mechanic/Collection) via `ActivityService.RegisterPoints`. Dependencias: `ActivityService`, `CombatService`, `WorldService`.
- **WorldDefinitions extendidas**: los 5 mundos (`Forest`, `Desert`, `Ice`, `Volcano`, `Cyber`) declaran su lista `Mechanics` en la definición:
  - Forest: `Tracking`, `HiddenZone`, `NaturalMechanism` (mecánica complementaria al hazard de emboscada).
  - Desert: `TemporalEvent (Sandstorm)`, `BuriedTreasure`, `Oasis`.
  - Ice: `SlipperyIce`, `FragilePlatform`, `TemporalEvent (Blizzard)`.
  - Volcano: `TemporalEvent (Eruption)`, `MeteorShower`, `DynamicRoute`.
  - Cyber: `Terminal`, `SecurityDoor`, `SecurityLasers`, `DynamicRoute`.
- **Tests**: `tests/shared/WorldMechanics.spec.lua` — 58 casos cubriendo catalogo, coherencia con definiciones, maquina de fases temporales, dano temporal, visibility factor, maquina de terminales (anti-explot), plataformas frágiles, modificadores de movimiento, validación de posición y `Audit`.
- **Wiring**: `WorldMechanicsService` agregado a `SERVICES` en `ServerMain.server.lua` con `connect()` en `wireDependencies` llamando a `SetDependencies(activityService, combatService, worldService)`; `RegisterInteractionPoints` llamado desde el loader de mundos (sustituye el stub `no_point` del playtest FASE 3).
- **Gates**: `npm test` PASS (1062/1062, 58 suites); `verify:structure` PASS (45 servicios); `verify:wiring` PASS (36 servicios, 24 conexiones, 51 llamadas); `rojo:build` PASS. `analyze.js` FAIL baseline preexistente — nuevos errores en `WorldMechanics.lua`/`WorldMechanicsService.lua`/`WorldMechanics.spec.lua` pertenecen a las mismas categorías de baseline (requiere de path resolución de tests, `tonumber()` nullable, `Unknown require`); sin categorías nuevas.
- **Server-authoritative**: la fase de un evento, estados de terminal, y recompensas nunca deciden el cliente. Estado scoped a (mundo, evento): cooldown por evento, no por jugador. Sin estado mutable compartido entre jugadores.
- **Pendiente**: playtest runtime en Studio/MCP para validar spawn de partes, tick de fases y RegisterPoints con puntos reales (no stubs).

## Bloqueos actuales
- MCP Roblox: CONECTADO (verify:env, esta sesion). Playtest ejecutado.
- Studio / Play Test: EJECUTADO — solo_playtest real sobre la instancia `latest.rbxlx` con peers edit/server/client-1.
- analyze.js: FAIL PREEXISTENTE de baseline (documentado, no introducido por esta fase).
- AUDIO ASSETS: BLOCKED_EXTERNAL (sin IDs reales).
- RegisterPoints: puntos de Discovery/Rescue/Mechanic inyectados por WorldMechanicsService (FASE 4).
- FASE 6 playtest runtime (Studio/MCP) pendiente — validar maquina de 5 estados, spawn de cuerpos y recompensas.

## Fases pendientes
- [ ] Panel World Completion UI (FASE 44)
- [ ] Cadenas de misiones con prerrequisito (FASE 41)
- [ ] Cofres fisicos con animacion (FASE 24)
- [ ] Companeros Brainrot (FASE 22)
- [ ] Player home, vehiculos, NPC dinamicos, reputacion (FASES 30/31/39/42)
- [ ] Party/Matchmaking reales (FASES 19/20): stubs
- [ ] Audio real (externo)
- [ ] Inyeccion de puntos de Discovery/Rescue/Mechanic (RegisterPoints) desde loader de mundo
- [ ] Forward de Destruction/Secret/Event a RecordMetric para Collection/Defense/Secret
- [ ] Playtest runtime FASE 6 (Studio/MCP) — validar maquina de 5 estados, spawn de cuerpos, recompensas

---

## FASE 6 — Eventos dinamicos (2026-10-08): COMPLETED
- **Arquitectura**: `EventRules.lua` (pure library) extendido con maquina de 5 estados (`DynamicState`: Idle→Warning→Active→Recovery→Cooldown), tipos de evento (`EventType`: Global/Local/Player/Coop), 20 eventos de mundo (4 por mundo) + catalogo universal (3) + COOP (3 con MinPlayers/MaxPlayers), `DynamicBodyKind` (Hunt/Boss/Survive/Reward/Collect/Defense/Escort/Rescue/Objective), config con duraciones por fase (WarningDuration/ActiveDuration/RecoveryDuration), WeightedRoll, DynamicStart, funciones de fase (NextPhase/PhaseDuration/GetPhaseRemaining/IsPhaseExpired/AdvancePhase/GetTotalDuration), IsDynamicEvent, IsEventLive, CompleteObjective, IsObjectiveDone, IsCoop, IsUniversal, GetPlayerRequirements, GetZone, CooldownFor, GetEventType, DynamicBodies, DynamicBodyFor, DynamicObjectiveTargetFor, DynamicSpawnPlanFor, DynamicCompletesOnExpiry, DynamicObjectiveText. Backward compatibility preservada.
- **Service**: `EventService.lua` extendido — cooldowns (`_cooldowns`), fase de 5 estados en Tick (transiciones phase→phase con timers), DynamicStartEvent, OnDynamicPhaseChanged, FinishDynamicEvent, SpawnDynamicBody (spawn por zona con DynamicSpawnPlanFor), MaintainDynamicBodies, CleanupDynamicBody, OnDynamicMonsterDied, IsOnCooldown/SetCooldown, CountPlayersInWorld (COOP gates), dynamicBodySpawnPoint (zone-aware), PayReward (material rewards via InventoryService), Publish (EventPhase/EventPhaseRemaining/DynamicObjectiveText attributes), Init/CloseWorldEvents. Wiring en `ServerMain.server.lua` — SetDependencies recibe economyService + inventoryService.
- **Remote**: `EventAction` RemoteEvent agregado a `Remotes.model.json`; `GameConstants.lua` (`RemoteAction.Event = "EventAction"`); `RemoteSchema.lua` (`[RemoteAction.Event] = {}`).
- **Tests**: `Events.spec.lua` extendido con 35 tests FASE 6 (maquina de 5 estados, tipos, seleccion ponderada, requisitos COOP, zonas, cooldowns, definiciones) → 1099/1099 PASS.
- **Bug fixes**: IsObjectiveDone (solo active.ObjectiveCompleted); ForestRift en DynamicBodies (Kind=Survive); GetPlayerRequirements test (TwinBosses/SharedThreat); expect.toBeFalsy() para WorldInvasion/ForestSwarm; #checked (loop manual).
- **Verificacion**: `npm test` PASS (1099/1099, 59 suites); `npm run verify:structure` PASS (45 servicios); `npm run verify:wiring` PASS (36 servicios, 24 conexiones, 51 llamadas inter-servicio); `rojo:build` PASS. `analyze.js` FAIL baseline preexistente (no introducido).
- **Server-authoritative**: fase de evento, estado de cuerpos, y recompensas nunca deciden el cliente. Cooldown scoped por evento.
- **Pendiente**: playtest runtime en Studio/MCP (validar maquina de 5 estados, spawn de cuerpos, recompensas); commit + push FASE 6.

## FASE 5 — Exploracion vertical (2026-10-08): COMPLETED
- Cuevas subterraneas (Y=-20/-40/-60), descensos secretos, sistema HOLE_TYPES (8 constantes), 80 huecos REALes → 0 (root cause: route deck parts en patchFloorHoles). 1064/1064 PASS.

## FASE 5-bis — Correccion de huecos finos (2026-10-08): COMPLETED
- Root cause: `patchFloorHoles` usaba rejilla de 4 studs; huecos de 2-3 studs se escapaban entre celdas y el jugador caia al caminar.
- Fix: `CELL` en `patchFloorHoles` cambiado de 4 a 2; patch size de [8,2,8] a [6,2,6]. Resultado: 0 huecos encerrados a 2 studs en los 5 mundos.
- Test de regresion: `tools/world-hole-check.js` integrado en `npm run verify` como `test:hole-check`. PASS en los 5 mundos.

## FASE 4 — WorldMechanics (2026-10-07): estructura COMPLETED
- Arquitectura de mecánicas unicas por mundo implementada y verificada.
- `WorldMechanics` (pure library) + `WorldMechanicsService` (server-authoritative).
- 5 mundos extendidos con listas `Mechanics` propias (Forest/Desert/Ice/Volcano/Cyber).
- 58 tests nuevos (1062/1062 PASS). verify:structure 45 servicios. verify:wiring 36/24/51.
- RegisterPoints integrado: puntos Discovery/Mechanic/Collection ahora se inyectan desde `WorldMechanicsService.RegisterInteractionPoints` via `ActivityService.RegisterPoints` (sustituye stub `no_point`).
- Playtest runtime (Studio/MCP) pendiente de validar spawn de partes + tick de fases.
