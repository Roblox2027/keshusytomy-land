# NEXT TASK — FASE 6 Eventos dinamicos: COMPLETED (2026-10-08)

## Siguiente fase: FASE 7 — Panel World Completion UI (FASE 44) + cofres fisicos (FASE 24) + cadenas de misiones (FASE 41)

## Estado de FASE 6 (completada)
- **Maquina de 5 estados**: `DynamicState` (Idle→Warning→Active→Recovery→Cooldown) en `EventRules.lua` + `EventService.lua` Tick. Phase transitions con timers (WarningDuration/ActiveDuration/RecoveryDuration).
- **20 eventos de mundo** (4 por mundo): Forest (Ambush, LostCreature, ForestRift, NightHunters); Desert (BuriedTreasure, Caravan, SandBeastHunt); Ice (IceBreak, FrozenRescue, FrostPack); Volcano (Rockfall, VolcanicEvacuation, MagmaHunt); Cyber (SystemFailure, SecurityLockdown, HackTheCore, SecuritySwarm). Catalogo universal: TreasureRush, MonsterSurge, EliteSpawn. COOP: SharedThreat, TwinBosses, Nexus (MinPlayers/MaxPlayers).
- **EventTypes**: Global, Local, Player, Coop. WeightedRoll para seleccion. Cooldown por evento (`_cooldowns`). COOP gates via CountPlayersInWorld.
- **Cuerpos temporales**: `DynamicBodyKind` (Hunt/Boss/Survive/Reward/Collect/Defense/Escort/Rescue/Objective) + DynamicBodies catalog. Spawn por zona (`dynamicBodySpawnPoint`). Limpieza automatica (`CleanupDynamicBody`). Recompensas via EconomyService/InventoryService (`PayReward`).
- **Remote**: `EventAction` RemoteEvent (UI feedback). Agregado a Remotes.model.json + GameConstants.RemoteAction.Event + RemoteSchema channel.
- **Verificacion**: npm test PASS (1099/1099, 59 suites; +35 tests FASE 6 en Events.spec.lua); verify:structure PASS (45); verify:wiring PASS (36/24/51); rojo:build PASS.
- **Bug fixes**: IsObjectiveDone, ForestRift en DynamicBodies, GetPlayerRequirements test (TwinBosses/SharedThreat), expect.toBeFalsy() para WorldInvasion/ForestSwarm, #checked (loop manual).
- **Pendiente**: commit + push FASE 6; playtest runtime Studio/MCP (validar maquina de 5 estados, spawn, recompensas).

## Estado de FASE 5 (completada)
- Cuevas subterraneas (Y=-20/-40/-60), descensos secretos, sistema HOLE_TYPES (8 constantes). 80 huecos REALes → 0 (route deck parts en patchFloorHoles). 1064/1064 PASS.

## Estado de FASE 4 (completada)
- **Arquitectura WorldMechanics**: `WorldMechanics.lua` (pure library) + `WorldMechanicsService.lua` (server-authoritative) implementados.
- **5 mundos extendidos** con listas `Mechanics` propias: Forest (Tracking/HiddenZone/NaturalMechanism), Desert (TemporalEvent/Sandstorm/BuriedTreasure/Oasis), Ice (SlipperyIce/FragilePlatform/TemporalEvent/Blizzard), Volcano (TemporalEvent/Eruption/MeteorShower/DynamicRoute), Cyber (Terminal/SecurityDoor/SecurityLasers/DynamicRoute).
- **Tests**: 58 casos nuevos en `WorldMechanics.spec.lua` → 1062/1062 PASS.
- **Verificacion**: verify:structure PASS (45 servicios); verify:wiring PASS (36 servicios, 24 conexiones, 51 llamadas); rojo:build PASS.
- **Wiring**: `WorldMechanicsService` en `SERVICES` + `connect()` con `SetDependencies(activityService, combatService, worldService)`. RegisterPoints integrado (sustituye stub `no_point`).
- **analyze.js**: FAIL baseline preexistente; nuevos errores en archivos WorldMechanics pertenecen a categorías de baseline (path resolution de tests, `tonumber()` nullable, `Unknown require`); sin categorías nuevas.
- **Playtest runtime** pendiente (Studio/MCP) — validar spawn de partes, tick de fases y RegisterPoints con puntos reales.
- **Commit + push**: pendiente (FASE 4 COMPLETED, arbol DIRTY).

## Estado de FASE 3 (completada)
- Implementada, verificada localmente (1014/1014 PASS, verify:structure/wiring PASS, rojo:build PASS) y playtesteada en Studio/MCP (CONECTADO).
- BUG FIX: material rewards (Mat_*) ahora se entregan via InventoryService.AddItem en lugar de GrantCurrency.
- Playtest resultados: Offer/Interact/Claim/RecordMetric/duplicates/rejections/concurrency todos PASS.
- Estado git: arbol LIMPIO tras commit FASE 3 (ced7b56 = origin/main).
- Studio/MCP: CONECTADO y playtesteado.

## Estado de FASE 2 (completada)
- HEAD real `6545120` = origin/main. (`41a2a94` = FASE 1 RE-AUDIT; source idéntico
  a 6545120. `6545120` = commit de continuidad FASE 2 COMPLETED y último estado
  verificado con 973/973 PASS. El HEAD actual tras el commit de corrección que
  contiene este archivo es sucesor de 6545120; STATE.json lo referencia por
  convención de no-autorreferencia.)
- Bloques 1-4 ya estaban commited en HEAD `06727a7` (=origin/main). Bloque 5 estaba sin commit.
- FASE 2: commited Bloque 5 (`7941e83`) + FASE 1 RE-AUDIT docs (`41a2a94`) y
  continuidad FASE 2 (`6545120`), push a origin/main, sincerado STATE.json a
  HEAD `6545120`, arbol LIMPIO.
- Las modificaciones V2 existentes en el arbol fueron consolidadas antes de continuar.
- Verificaciones: npm test PASS (973/973), npm run verify PASS (cadena completa exit 0), analyze.js FAIL baseline (documentado).
- Brainrot visual intacto. AUDIO ASSETS BLOCKED_EXTERNAL (sin IDs reales).

## Reglas vigentes
- NO redisenar Brainrot (visual). Problemas visuales -> `BRAINROT_VISUAL_FOLLOWUP`.
- NO inventar IDs de audio.
- Server-authoritative en dano/moneda/drops/recompensas; rate limit via RemoteGateway.
- Server-authoritative en mecánicas: la fase de un evento, estados de terminal/plataforma y recompensas nunca deciden el cliente. Estado scoped a (mundo, evento).
- Respetar `PerformanceConfig` (caps, pooling, concurrencia).
- Antes de cada commit: `git diff --check`; despues: push real a `origin/main`.
- Verificacion por bloque: suite Luau + verify:structure + verify:wiring + rojo build + tests nuevos; y sonda runtime en Studio cuando la sesion este disponible.
- FASE 4: WorldMechanics registrado antes de FASE 44 (Panel UI) y FASE 41 (cadenas), para que los puntos RegisterPoints se inyecten correctamente y el panel tenga datos reales de completion.

## Estado real
- FASE 0-4: PASS (commits 09007f3, 7941e83, 41a2a94, 6545120, ced7b56, 9247d7a en origin/main). FASE 5 COMPLETED (cuevas, HOLE_TYPES, 0 huecos). FASE 6 COMPLETED (eventos dinamicos, 1099/1099 PASS). Studio/MCP CONECTADO.
- Entorno (verify:env, esta sesion): Studio/MCP CONECTADO; analyze.js FAIL baseline preexistente; rojo build PASS; npm test 1099/1099 PASS; npm run verify PASS.
- `GAMEPLAY_AUDIT.md` actualizado con estado de resolucion por hallazgo.

## Siguiente iteracion (FASE 6, completada)
1. **Arquitectura Eventos dinamicos** (FASE 6): `EventRules.lua` (5-state machine, 20 eventos, catalogos, DynamicBodies) + `EventService.lua` (phase transitions, cooldowns, spawn, rewards, cleanup) + `ServerMain.server.lua` (wiring) + `EventAction` remote. COMPLETED — 1099/1099 PASS.
2. **Panel World Completion** (FASE 44): los datos ya se publican por atributos; falta el panel en UI + test de contrato.
3. **Cadenas de misiones** (FASE 41): `QuestRules` no soporta prerrequisitos; ampliar con `RequiresQuestId`.
4. **Cofres fisicos** (FASE 24): categorias, apertura con animacion/sonido/VFX y drop via `LootRules`.
5. **Companeros Brainrot** (FASE 22): evaluar sobre el bestiario; NUNCA auto-play. Disenios visuales intactos.
6. **Player home / vehiculos / NPC dinamicos / reputacion** (FASES 30/31/39/42).
7. **Party/Matchmaking** (FASES 19/20): stubs.
8. **Audio real** (externo): subir IDs reales al Creator Dashboard.
9. **FASE 3 follow-up**: forward de DestructionService/SecretService/EventService a RecordMetric para Collection/Defense/Secret.

## Orden de ataque propuesto (FASE 7 en adelante)
1. Commit + push FASE 6 a origin/main.
2. Panel World Completion + cofres fisicos + cadenas de misiones.
3. Playtest runtime FASE 6 (Studio/MCP) — validar maquina de 5 estados, spawn de cuerpos, recompensas.
4. Ritual boss completo.
5. Secundario por mundo (2.º secreto, coleccionables, eventos propios).
6. Party real sin bloquear solitario.
7. Audio real (externo).
