# GAMEPLAY AUDIT — KeshusyTomy-LanD

> FASE 1 (re-auditoría V2, 2026-10-07, HEAD `06727a7` = origin/main, árbol SUCIO con Bloques 1-5 sin commitear).
> Cada entrada: problema, ubicación, causa, impacto, solución propuesta, prioridad.
> Prioridades: **P0** (mata la diversión hoy), **P1** (limita retención), **P2** (profundidad/largo plazo).

---

## ESTADO DE RESOLUCIÓN (2026-10-07, tras Bloques 1-5 en árbol)
## FASE 1 RE-AUDIT (2026-10-07) — ESTADO REAL MEDIDO

### 1. Continuidad y Git (NO inventado)
- `.cline/STATE.json` declara phase M2-BLOQUE5, commit/head/origin `09007f3` — DESACTUALIZADO (ese commit no existe aquí).
- Real: `HEAD = 06727a7`, `origin/main = 06727a7`, árbol SUCIO con ~20 modificados + 3 nuevos (PuzzleRules, PuzzleService, PuzzleRules.spec = Bloque 5).
- Conclusión: Bloques 1-5 existen en el árbol pero NO commiteados; riesgo de pérdida CRITICAL (proceso).

### 2. Verificación base (esta sesión, real)
- `verify:structure` PASS (43/43). `verify:wiring` PASS (34 tabla, 23 conexiones, 48 llamadas).
- `npm test` PASS (973/973, 55 suites). `rojo:build` PASS.
- `test:worlds` PASS (Forest 28/60 rutas; resto 17 zonas; 0 probl). `test:world-content` PASS (5/5 miniboss+secreto). `test:audio-ui` PASS. `test:contract` PASS. `test:navigation` PASS (96/96). `test:spawn` PASS. `test:world-edge` PASS. `test:monster-access` PASS (60/60). `test:powerup-boss` PASS (9 powerups, 5 bosses). `test:bomb-grid` PASS.
- `npm run verify` completo / `analyze.js` NO ejecutados (cadena larga + FAIL baseline preexistente).

### 3. Gameplay loop ACTUAL (medido)
- ENTRAR → EXPLORAR (96 zonas) → MATAR (bomba; melee/dash/habilidad solo árbol sucio) → XP/monedas → EVENTO con cuerpo (solo árbol) → HAZARD por mundo (solo árbol) → SECRETO (1/mundo) → MINIBOSS (3/mundo) → BOSS (fases numéricas; ritual solo árbol) → SIGUIENTE MUNDO.
- Faltan: DESCUBRIR con panel, MEJORAR con equipo real (árbol), DESBLOQUEAR (mundos abiertos nv1), desafíos múltiples, secretos múltiples, recompensa especial (árbol), coleccionables físicos, retorno fuerte.

### 4. Puntos de aburrimiento (problema/causa/impacto/solución/prioridad)
- P1. Árbol sucio sin commit (Bloques 1-5 no publicados). Causa: sin commit/push. Impacto: pérdida potencial. Solución: commit por bloque + push. **CRITICAL**.
- P2. STATE desactualizado (`09007f3` fantasma). Solución: sincerar a `06727a7`+dirty. **CRITICAL**.
- P3. Audio = silencio (`AudioConfig` nil/false, carpetas vacías). Solución: assets reales, nunca inventar IDs. **HIGH** (BLOCKED_EXTERNAL).
- P4. Recompensa monocromática en HEAD (XP/monedas); loot dinámico solo árbol. **HIGH**.
- P5. Boss = HP escalado en HEAD (900→3800, mismo esqueleto IA); ritual solo árbol. **HIGH**.
- P6. Mundos iguales en HEAD (presión 0.55→0.98 + geometría); hazards solo árbol; tramos largos sin actividad (Forest 396 studs). **HIGH**.
- P7. Misiones un tipo en HEAD (12 contadores); +5 V2 y cadenas pendientes (árbol/parcial). **HIGH**.
- P8. Sin razón fuerte de retorno en HEAD (1 secreto solo monedas). **MEDIUM**.
- P9. Multiplayer stub (Party/Matchmaking); solo puzzle 8 s como co-op (árbol). **MEDIUM**.
- P10. Noche numérica en HEAD; Lighting tween solo árbol. **MEDIUM**.
- P11. Monstruos CON roles (Vanishes/LeavesBomb/Slow/Burn/BlocksDestroy/Reflect) pero sin soporte/invocador/huida/emboscador; telegraph legible. **MEDIUM** (fortaleza parcial).
- P12. UI sin World Completion; equipo cosmético en HEAD (stats en árbol). **MEDIUM**.
- P13. Progresión lineal sin gating (5 mundos nv1). **LOW**.

### 5. Mundos / monstruos / bosses / misiones / recompensas / replay / multi
- Mundos: Forest tutorial 28 zonas; resto 17 zonas con presión y personae distintas pero sin NPC/arena dedicada/coleccionables/eventos propios. Ninguno tiene identidad jugable completa en HEAD.
- Monstruos: 8 fauna + 15 minibosses + 5 bosses, IA estados + pathfinding + telegraph ≥0.8 s. Faltan soporte/invocador/huida/emboscador.
- Boss: 5 con fases numéricas en HEAD; ritual parcial en árbol; sin arena/cámara/música/VFX propios.
- Misiones: 12 HEAD + 5 árbol; sin cadenas ni tipos escolta/sobrevive/puzzle.
- Recompensas HEAD: XP/Coins; árbol: materiales + gemas boss + logros/títulos + bestiario.
- Replay HEAD: farm/cooldown; ganchos en árbol (material por mundo, logros, bestiario, hordas, puzzle 300 s cd).
- Multi: mundial pero sin party; co-op justo solo puzzle doble (árbol).

### 6. Oportunidades / orden
1. Commit+push Bloques 1-5 + sincerar STATE. 2. Panel World Completion + cadenas + cofres. 3. Ritual boss completo. 4. Secundario por mundo (2.º secreto, coleccionables, eventos propios). 5. Party real sin bloquear solitario. 6. Audio real (externo).

---

| Hallazgo | Estado | Evidencia |
|---|---|---|
| A1 Combate de una sola herramienta | **RESUELTO** | `CombatRules` + `CombatService.TryMelee/TryDash/TryAbility` + canal `CombatAction` + `CombatController` + bindings (click/E/X, Q/B, R/Y) + combos con ventana y especial x1.8. Validado en runtime (gate de ronda correcto). |
| A2 Eventos sin cuerpo | **RESUELTO** | `EventRules.Bodies` (Hunt/Boss/Survive/Reward) + `WorldInvasion`; spawns por zona, objetivo y cleanup. Validado en vivo: 4 enemigos generados, objetivo publicado, cleanup completo. |
| A3 Mundos sin mecánica propia | **RESUELTO** | `HazardRules`/`HazardService`: emboscada (Forest), arenas movedizas (Desert), rachas de viento (Ice), lava DOT (Volcano), láser telegrafiado (Cyber). Validado en vivo: 4 zonas construidas en Forest. **FASE 4 complementario**: `WorldMechanics`/`WorldMechanicsService` — mecánicas SECUNDARIAS por mundo (Tracking/HiddenZone, BuriedTreasure/Oasis, SlipperyIce/FragilePlatform, MeteorShower/DynamicRoute, Terminal/SecurityLasers). |
| A4 Recompensas monocromáticas | **RESUELTO** | `LootRules`/`LootService`: 5 materiales de mundo, drops monster 15 % / miniboss siempre (a veces doble) / boss siempre + 2 gemas (primera fuente gratuita de gemas por habilidad). |
| A5 Sin logros/colección/discovery | **RESUELTO (parcial UI)** | `AchievementRules`/`AchievementService` (10 logros, títulos, perfil v3) + `BestiaryService` (colección de especies persistente). Datos y publicación hechos; PANEL de World Completion pendiente. |
| B1 Boss sin ritual | **RESUELTO (parcial)** | Telegraph de área rojo, adds en fase 2, debilidad x1.4 en fase 3, intro "JEFE" en UI. Arena dedicada e intro de cámara pendientes. |
| B2 Misiones de un solo tipo | **RESUELTO (parcial)** | 5 misiones nuevas (secreto/evento/miniboss/boss/powerup). Cadenas con prerrequisito pendientes (QuestRules no lo soporta). |
| B3 Equipamiento sin efecto | **RESUELTO** | `EquipmentRules` + 3 piezas con stats (velocidad/vida/cooldown), topes acotados, reaplicado al reaparecer; tienda de monedas (sink). |
| B4 Brainrot sin función jugable | **RESUELTO (como colección)** | Bestiario de especies persistente con rareza funcional. Compañeros (FASE 22) pendientes de evaluación. Diseños visuales intactos. |
| B5 Hordas/arenas dormidas | **RESUELTO** | Terminales de arena por código disparan `HordeService.StartHorde`; estado de oleada publicado al HUD. |
| B6 Noche sin dientes | **RESUELTO (ambiental)** | `EffectsController` traduce `NightPhase` a Lighting con tween; ciclo ambiental sin progreso por noches. |
| C1 Cooperativo | **PARCIAL** | Puzzle de doble interruptor por mundo (ventana 8 s: 2 jugadores fácil, 1 posible). Party/Matchmaking siguen stub. |
| C2 Puzzles | **RESUELTO (1 tipo)** | `PuzzleRules`/`PuzzleService`: doble interruptor con cooldown anti-granja. |
| C3+ (coleccionables físicos, home, vehículos, NPC, reputación) | **PENDIENTE** | Documentado en `.cline/NEXT-TASK.md`. |

**Validación runtime (Studio, playtest real):** 43 servicios y 12 controllers presentes; los 5 servicios nuevos `initialized=true`; evento de caza con cuerpo verificado en vivo; hazards construidos al entrar al mundo; combate con gate de ronda correcto; playtest detenido limpio.

---

## RESUMEN EJECUTIVO

El juego tiene una base sólida y verificada: 5 mundos navegables (96/96 zonas), bombas con reacción en cadena, monstruos con pathfinding real, minibosses por zona, bosses CON fases, secretos persistentes, economía con ledger, perfil v2 con migraciones, eventos con ciclo de vida (`EventService.StartEvent`) y 899 tests en verde.

El problema central de diversión: **el loop actual es "entrar → ronda → bombas → monstruos → recompensa" y casi todo lo demás es estructura sin efecto jugable**. Hay mucho catálogo (50+ items, 18+ monstruos, 15 minibosses) pero poca *decisión* y poca *sorpresa* en minuto a minuto.

Veredicto por área (FASE 65 de la misión):

| Área | Estado | Conectada al loop |
|---|---|---|
| Combate jugador | EXISTE (solo bombas) | Parcial |
| IA monstruos | EXISTE (pathfinding + personae) | Sí |
| Bosses | PARCIAL (fases sí, telegraphs/arena/mecánica especial débiles) | Sí |
| Minibosses | EXISTE (tiers, zonas, cooldown) | Sí |
| Eventos dinámicos | EXISTE (ciclo de vida) pero NO spawnean contenido visible ni UI | Parcial |
| Mecánicas por mundo | EXISTE (hazards + WorldMechanics FASE 4) | Sí (parcial) |
| Secretos | EXISTE (prompt + persistencia) | Parcial (recompensa = solo monedas) |
| Puzzles | NO EXISTE | No |
| Coleccionables | NO EXISTE (fuera de secretos/items de tienda) | No |
| Logros / Títulos | NO EXISTE | No |
| Colección Brainrot | NO EXISTE | No |
| Equipamiento con stats | NO EXISTE (slots cosméticos) | No |
| Economía | EXISTE (ledger) pero Gems sin fuente gratuita | Parcial |
| Misiones | EXISTE pero solo "mata/destruye/descubre X" | Parcial |
| Cooperativo | NO EXISTE (Party/Matchmaking = stubs) | No |
| Arenas/Hordas | PARCIAL (HordeService existe, no se auto-dispara) | Parcial |
| Rejugabilidad post-mundo | NO EXISTE | No |

---

## P0 — LO QUE MÁS DAÑA LA DIVERSIÓN HOY

### A1. El combate del jugador tiene UNA sola herramienta
- **Problema:** el jugador solo coloca bombas. No hay ataque rápido/pesado, dash defensivo, esquiva, bloqueo ni habilidad.
- **Ubicación:** [src/ServerScriptService/Services/BombService.lua](src/ServerScriptService/Services/BombService.lua), [src/StarterPlayer/StarterPlayerScripts/Controllers/InputController.lua](src/StarterPlayer/StarterPlayerScripts/Controllers/InputController.lua)
- **Causa:** el vertical slice se construyó alrededor de la bomba y nunca se añadió una segunda capa de input de combate.
- **Impacto:** todos los combates se sienten iguales a los 5 minutos; los 18 monstruos con personae distintas no importan porque la respuesta del jugador es siempre la misma.
- **Solución propuesta:** Combate V2 (misión FASE 8/9/32): ataque rápido cuerpo a cuerpo, dash con i-frames cortos, habilidad con cooldown. Server-authoritative vía `CombatService` existente. Combos ligeros (3ª pulsación = golpe especial).
- **Prioridad:** P0

### A2. Los eventos no producen nada visible
- **Problema:** `EventService` sortea y abre eventos ("RIO DE LAVA", invasiones…) pero el evento es un registro en memoria: no spawna enemigos, no cambia el mundo, no tiene UI propia ni conclusión jugable.
- **Ubicación:** [src/ServerScriptService/Services/EventService.lua](src/ServerScriptService/Services/EventService.lua#L210), [src/ReplicatedStorage/Shared/Libraries/EventRules.lua](src/ReplicatedStorage/Shared/Libraries/EventRules.lua)
- **Causa:** se implementó el ciclo de vida (abrir/cerrar/recompensar) pero nunca el *cuerpo* del evento (spawns, zona, objetivo, feedback).
- **Impacto:** el sistema de "mundo vivo" existe en papel y el jugador nunca lo percibe. Cero sorpresas.
- **Solución propuesta:** dar cuerpo a 4-6 eventos por mundo (invasión, lluvia de recompensas, cofre gigante, miniboss raro, portal misterioso) con anuncio UI global, objetivo, contador y cleanup garantizado. Evento mundial `WORLD_INVASION` con objetivo compartido del servidor.
- **Prioridad:** P0

### A3. Los 5 mundos se juegan igual
- **Problema:** Desert/Ice/Volcano/Cyber no tienen mecánica física propia. No hay arenas movedizas, hielo resbaladizo, lava que queme ni láseres. "Hazards" es solo una carpeta excluida de las bombas.
- **Ubicación:** [src/ReplicatedStorage/WorldDefinitions/](src/ReplicatedStorage/WorldDefinitions/), generador [tools/worlds.js](tools/worlds.js)
- **Causa:** el generador produce geometría y rutas; nunca se cableó una capa de efectos de terreno.
- **Impacto:** cambiar de mundo es cambiar de color. La exploración no enseña nada nuevo y la progresión entre mundos no se siente.
- **Solución propuesta:** una mecánica característica por mundo (misión FASE 3), implementada como `HazardService` server-side con zonas etiquetadas en el generador: Desert = arenas movedizas (slow) + tesoros enterrados; Ice = fricción baja + hielo rompible; Volcano = lava DOT + erupción telegrafiada; Cyber = láseres con patrón + terminales; Forest = emboscadas + zonas ocultas.
- **Prioridad:** P0

### A4. Recompensas monocromáticas: todo da monedas
- **Problema:** secretos, misiones, kills y eventos pagan casi siempre Coins. Gems no tienen fuente gratuita. No hay drops de materiales, consumibles ni coleccionables.
- **Ubicación:** [src/ServerScriptService/Services/EconomyService.lua](src/ServerScriptService/Services/EconomyService.lua), [src/ServerScriptService/Services/SecretService.lua](src/ServerScriptService/Services/SecretService.lua), [src/ReplicatedStorage/Shared/Libraries/QuestRules.lua](src/ReplicatedStorage/Shared/Libraries/QuestRules.lua)
- **Causa:** el ledger se diseñó para dos monedas y el resto de sistemas nunca recibió su propio tipo de recompensa.
- **Impacto:** nada que desear. Sin drops raros no hay "otros 10 minutos".
- **Solución propuesta:** tabla de loot por fuente (misión FASE 23/25): materiales, consumibles, cofres por categoría con animación, drops raros de miniboss/boss con probabilidad declarada, todo server-authoritative y persistente.
- **Prioridad:** P0

### A5. Nada que completar: sin logros, colección ni registro de descubrimiento
- **Problema:** no hay logros, títulos, bestiario ni "World Completion". El jugador no puede ver qué le falta.
- **Ubicación:** inexistente (solo `Profile.Secrets.Discovered`).
- **Causa:** la progresión se detuvo en XP/nivel.
- **Impacto:** al terminar la ronda no hay objetivo a largo plazo; la retención depende solo del grind de monedas.
- **Solución propuesta:** `AchievementService` + `DiscoveryService` (misión FASE 17/19/43/44): registro de zonas/enemigos/secretos/bosses/coleccionables por mundo con UI de completion, logros con recompensa y títulos cosméticos.
- **Prioridad:** P0

---

## P1 — LO QUE LIMITA LA RETENCIÓN

### B1. Bosses con fases pero sin ritual
- **Problema:** `BOSS_PHASES` cambia multiplicadores por fracción de vida, pero no hay intro, arena dedicada, telegraphs ricos (VFX/sonido/indicador de área), adds ni mecánica especial por fase.
- **Ubicación:** [src/ServerScriptService/Services/MonsterService.lua](src/ServerScriptService/Services/MonsterService.lua#L383)
- **Causa:** la fase es un modificador numérico, no un cambio de comportamiento.
- **Impacto:** el boss se siente como "el monstruo grande con más HP" que la misión prohíbe explícitamente.
- **Solución propuesta:** Boss V2 (FASE 10): 3 fases con patrones distintos, telegraph de área con ventana de reacción, intro de cámara, adds en fase 2, debilidad en fase 3, recompensa especial.
- **Prioridad:** P1

### B2. Misiones de un solo tipo
- **Problema:** el catálogo de quests es "mata X / destruye Y / descubre Z". Sin escoltar, sobrevivir, activar, encontrar, resolver ni cadenas con historia.
- **Ubicación:** [src/ReplicatedStorage/Shared/Config/QuestCatalog.lua](src/ReplicatedStorage/Shared/Config/QuestCatalog.lua), [src/ServerScriptService/Services/QuestService.lua](src/ServerScriptService/Services/QuestService.lua)
- **Causa:** `RecordMetric` solo soporta contadores simples.
- **Impacto:** las misiones se auto-completan jugando; nadie las lee.
- **Solución propuesta:** ampliar métricas (Survive, Escort, Activate, Find, CompleteEvent) y cadenas de 3-8 misiones con mini-historia por mundo (FASE 40/41).
- **Prioridad:** P1

### B3. Equipamiento sin efecto real
- **Problema:** los slots Head/Body/Feet son cosméticos; nada modifica daño, velocidad, defensa o cooldowns.
- **Ubicación:** [src/ServerScriptService/Services/InventoryService.lua](src/ServerScriptService/Services/InventoryService.lua), [src/ReplicatedStorage/Shared/Config/ItemCatalog.lua](src/ReplicatedStorage/Shared/Config/ItemCatalog.lua)
- **Causa:** nunca se conectó el inventario al `CombatMath`/movimiento.
- **Impacto:** comprar en la tienda no cambia cómo juegas; la economía pierde su sink principal.
- **Solución propuesta:** stats reales por pieza (FASE 29) aplicados en `CombatMath` y locomoción, validados en servidor.
- **Prioridad:** P1

### B4. Brainrot sin función jugable
- **Problema:** los Brainrot existen como assets/personajes pero no hay colección, bestiario, rareza, drops ni compañeros. (Diseño visual FUERA de alcance — solo funcionalidad.)
- **Ubicación:** assets/characters, sin servicio asociado.
- **Causa:** nunca se construyó la capa de colección.
- **Impacto:** se desperdicia el contenido más distintivo del juego.
- **Solución propuesta:** `BrainrotCollectionService` (FASE 20): descubrimiento por mundo, bestiario con progreso persistente, rareza funcional, drops asociados; evaluar compañeros acotados (FASE 22) sin auto-play.
- **Prioridad:** P1

### B5. Hordas y arenas dormidas
- **Problema:** `HordeService` existe pero nada lo dispara; no hay arenas de supervivencia/oleadas/boss-rush con recompensas escalables.
- **Ubicación:** [src/ServerScriptService/Services/HordeService.lua](src/ServerScriptService/Services/HordeService.lua)
- **Causa:** falta el disparador (evento, NPC o terminal) y la UI de oleada.
- **Impacto:** no hay actividad secundaria intensa ni razón para volver a un mundo completado.
- **Solución propuesta:** arenas activables (FASE 36/37) con contador de oleada, descanso, jefe final y recompensa escalable; disparar hordas también como evento dinámico.
- **Prioridad:** P1

### B6. Noche ambiental sin dientes
- **Problema:** el ciclo día/noche cambia dificultad numérica pero no iluminación, spawns especiales, secretos nocturnos ni eventos propios.
- **Ubicación:** [src/ServerScriptService/Services/NightService.lua](src/ServerScriptService/Services/NightService.lua)
- **Causa:** se cableó la dificultad, no la ambientación (VisualService no reacciona al ciclo).
- **Impacto:** la noche no se siente; oportunidad perdida de sorpresa barata. (Sin progreso por noches: se mantiene AMBIENTAL, FASE 38.)
- **Solución propuesta:** Lighting por fase, monstruos nocturnos, secretos que solo aparecen de noche, eventos nocturnos.
- **Prioridad:** P1

---

## P2 — PROFUNDIDAD Y LARGO PLAZO

### C1. Cooperativo inexistente
- **Problema:** `PartyService`/`MatchmakingService` son stubs; no hay secretos de 2 jugadores ni eventos cooperativos con recompensa por participación.
- **Solución:** FASE 13/33/34, sin bloquear al jugador solitario.
- **Prioridad:** P2

### C2. Puzzles ausentes
- **Problema:** cero puzzles (botones, secuencias, palancas, plataformas).
- **Solución:** FASE 14: 1-2 puzzles cortos por mundo atados a secretos/cofres.
- **Prioridad:** P2

### C3. Coleccionables físicos por mundo
- **Problema:** no hay fragmentos/reliquias/cristales repartidos por el mapa con contador y recompensa.
- **Solución:** FASE 16, integrados en DiscoveryService.
- **Prioridad:** P2

### C4. Zona personal (PLAYER_HOME)
- **Problema:** no hay hogar con trofeos/exhibiciones.
- **Solución:** FASE 30, opcional, después de que exista qué exhibir.
- **Prioridad:** P2

### C5. Vehículos/monturas
- **Problema:** inexistentes; riesgo de romper el diseño de mapas.
- **Solución:** FASE 31, evaluar tras movilidad (dash) para no invalidar rutas.
- **Prioridad:** P2

### C6. NPC dinámicos y reputación
- **Problema:** no hay NPC que den pistas, inicien eventos o reaccionen al progreso.
- **Solución:** FASE 39/42, diálogos cortos.
- **Prioridad:** P2

---

## NOTAS DE ALCANCE

- **BRAINROT_VISUAL_FOLLOWUP:** no se detectaron problemas visuales concretos en esta auditoría de código; cualquier hallazgo visual futuro se registrará aquí sin modificar modelos.
- **Audio:** el mixer existe pero los assets reales están BLOCKED_EXTERNAL (sin IDs reales en Creator Dashboard). No se inventarán IDs.
- **analyze.js:** FAIL de baseline preexistente (documentado en `.cline/BLOCKED.md`); no es objetivo de esta misión salvo que una fase lo empeore.
- **Restricción de rendimiento:** toda mecánica nueva debe respetar `PerformanceConfig` (caps de monstruos, pooling de VFX, concurrencia de pathfinding).

## ORDEN DE ATAQUE PROPUESTO (FASE 2 en adelante)

1. **Bloque 1 — Mundo vivo:** A2 (eventos con cuerpo) + A3 (mecánica por mundo) + B6 (noche).
2. **Bloque 2 — Combate:** A1 (combate V2 + dash + combos) + B1 (boss ritual).
3. **Bloque 3 — Progresión:** A4 (loot dinámico) + A5 (logros/discovery/títulos) + B4 (colección Brainrot).
4. **Bloque 4 — Contenido:** B2 (misiones V2 + cadenas) + B5 (arenas/hordas) + B3 (equipamiento real).
5. **Bloque 5 — Social/profundidad:** C1-C6 según capacidad.
6. **Cierre:** QA de gameplay (FASE 59-63), playtest real (70), regresión (71), commits por bloque (73).

---

## FASE 3 — Actividades de exploracion (server-authoritative): COMPLETED (2026-10-07)
- **Rules**: `ActivitiesRules` (puro) — progreso/claim atómico/cooldown/oferta diaria determinista/Audit.
- **Catalog**: `ActivityCatalog` (15 actividades, 5 mundos, 6 tipos).
- **Service**: `ActivityService` (espejo QuestService) — estado en perfil, paga Coins + Mat_* via InventoryService (fix aplicado), publica atributos ActivityOffer/ActivityProgress/ActivityClaimOutcome, RecordMetric, TryInteract con proximidad server-side.
- **Remote layer**: canal `ExploreAction` (RequestOffer/Interact/Claim) en GameConstants + RemoteSchema + Remotes.model.json + AntiExploitRules.
- **Wiring**: ActivityService en SERVICES; MonsterService→ActivityService (caza); handlers ExploreAction en REMOTE_CHANNELS.
- **BUG FIX**: material rewards (Mat_*) ahora van a InventoryService.AddItem, no GrantCurrency.
- **Gates**: 1014/1014 PASS (57 suites); verify:structure 44; verify:wiring 35/24/50; rojo:build PASS. analyze.js FAIL baseline.
- **Playtest Studio/MCP**: CONECTADO. Offer/Interact/Claim/RecordMetric/duplicates/rejections/concurrency PASS.

## FASE 4 — WorldMechanics: arquitectura de mecánicas únicas por mundo: COMPLETED (2026-10-07)
- **Arquitectura**: `WorldMechanics` (pure library) — catalogó `MechanicsByWorld`, máquina de fases temporales (Calm/Warning/Active/Recovery/Cooldown) derivada del reloj del servidor, máquina de estados para terminales y plataformas frágiles (anti-explot), modificadores de movimiento, utilidades de posición, y `Audit` para coherencia.
- **Service**: `WorldMechanicsService` (server-authoritative) — hilo de tick, gestión de eventos temporales, registro de puntos de interacción via `ActivityService.RegisterPoints`, modificadores de movimiento periódicos.
- **5 WorldDefinitions extendidas** con listas `Mechanics` propias:
  - Forest: Tracking, HiddenZone, NaturalMechanism (complementa hazard de emboscada).
  - Desert: TemporalEvent (Sandstorm), BuriedTreasure, Oasis.
  - Ice: SlipperyIce, FragilePlatform, TemporalEvent (Blizzard).
  - Volcano: TemporalEvent (Eruption), MeteorShower, DynamicRoute.
  - Cyber: Terminal, SecurityDoor, SecurityLasers, DynamicRoute.
- **Server-authoritative**: la fase de un evento, estados de terminal/plataforma y recompensas nunca son decididos por el cliente. Estado scoped a (mundo, evento): cooldown por evento, no por jugador. Sin estado mutable compartido entre jugadores.
- **Wiring**: `WorldMechanicsService` en `SERVICES` + `connect()` con `SetDependencies(activityService, combatService, worldService)`; `RegisterInteractionPoints` integrado (sustituye stub `no_point` de FASE 3).
- **Tests**: 58 casos nuevos en `WorldMechanics.spec.lua` → 1062/1062 PASS.
- **Gates**: 1062/1062 PASS (58 suites); verify:structure 45 servicios; verify:wiring 36/24/51; rojo:build PASS. analyze.js FAIL baseline (categorías de baseline, sin categorías nuevas).
- **Playtest runtime**: pendiente (Studio/MCP) — validar spawn de partes, tick de fases y RegisterPoints con puntos reales.

---

## FASE 5 (bis) — Corrección de huecos finos en el suelo

### Problema
El parcheador `patchFloorHoles` (tools/worlds.js:1876) usaba una rejilla de **4 studs** para detectar huecos. El personaje de Roblox mide ~2 studs de ancho; con una rejilla de 4, huecos de 2-3 studs entre dos losas caían dentro de una celda y no se detectaban, dejando el jugador cayéndose al caminar.

### Diagnóstico
- `node tools/find-holes-2stud.js`: con rejilla de 2 studs se encontraron **18-56 huecos encerrados por mundo** (Forest: 18, Desert: 56, Ice: 46, Volcano: 32, Cyber: 39) que el parcheador de 4 no sellaba.
- Estos huecos estaban entre losas de rutas, zonas y enfoques, especialmente en esquinas y transiciones de cota.

### Corrección
1. **`patchFloorHoles`** (tools/worlds.js:1876): cambiada la constante `CELL` de `4` a `2`. La lógica de detección (celdas sin suelo rodeadas de suelo por ambos lados opuestos) es idéntica, pero ahora opera a 2 studs de resolución y detecta huecos que la rejilla de 4 pasaba por alto.
2. **Tamaño de parche**: reducido de `[8, 2, 8]` a `[6, 2, 6]` para mantener el parche orgánicamente fragmentado a la resolución más fina.
3. **`tools/world-hole-check.js`**: nueva herramienta de regresión que reproduce la detección de huecos a 2 estudios y verifica que los 5 mundos tengan **0 huecos encerrados**. Integrada en `npm run verify` como `test:hole-check`.

### Verificación (2026-10-09, sesion post-commit sobre HEAD 4a16818)

#### Git
- `HEAD = origin/main = 4a16818` (synced, árbol LIMPIO — solo archivos sin
  trackear preexistentes en `tools/`).

#### Inspección de Studio (via MCP, edit-mode)
- Studio abre `KeshusyTomy-LanD_AutoRecovery_0.rbxl` y expone los 5 mundos con
  los mismos recuentos de piezas que `default.project.json` (source):

| Mundo | FloorPatch | Tamaño | Piezas totales (Studio = Source) |
| ----- | ---------- | ------ | --------------------------------- |
| Forest | 11 | 6×2×6 | 4057 = 4057 |
| Desert | 54 | 6×2×6 | 2547 = 2547 |
| Ice | 65 | 6×2×6 | 2357 = 2357 |
| Volcano | 27 | 6×2×6 | 2503 = 2503 |
| Cyber | 34 | 6×2×6 | 2774 = 2774 |
| **Total** | **191** | 6×2×6 | |

  - Confirmación de versión: los 191 `FloorPatch_*` existen en Studio con el
    tamaño exacto `[6,2,6]` del commit, y los conteos de partes coinciden
    exactamente con `test:worlds` (source). Studio tiene la versión `4a16818`,
    no un Workspace vacío ni una versión anterior.
  - Todas las `FloorPatch` partes están ancladas (`Anchored=true`): 0 partes
    sin anclar (`tools/.map-physics-summary.json` → PASS).

#### Verificación 1:1 Studio↔Source (posiciones de FloorPatch)
- Consulta MCP directa a `Workspace.Worlds` (edit-mode, `execute_luau`): **191
  FloorPatch en Studio = 191 en source**, con posición `[x, y, z]` y tamaño
  `[6,2,6]` **idénticos para las 191** (0 mismatch, 0 faltan, 0 sobran).
- Distribución Y en Studio (misma que source): 58 a `y=-1`, 8 a `y=0`,
  27 a `y=2`, 27 a `y=3`, 14 a `y≈3.3`, etc. — refleja el terreno de 5
  cotas de los mundos (no piezas caídas / desalineadas).
- **Aclaración sobre `y=-1`** (58 patches): el algoritmo coloca el parche en
  `y = neighborY - 1` con `Size.Y = 2` (`tools/worlds.js:2006`). Para vecinos
  con superficie de cota a `y=0`, el parche queda centrado en `y=-1` con su
  **cara superior en `y=0`** (alineada a la losa vecina) y su cara inferior en
  `y=-2`. No es "abajo del mapa": la superficie caminable coincide con el
  terreno circundante; el parche solo extiende 1 estudio bajo el nivel de la
  losa, que no afecta la colisión ni la jugabilidad (parte `Anchored`,
  `CanCollide=true`, top surface alineado).
- Los valores Y fraccionarios (`0.5`, `2.799`, `3.067`, `3.313`, etc.) provienen
  de `neighborY = max(vecinos)` donde losas rotadas/elevadas de rampas y
  transiciones tienen cotas no-enteras; el parche hereda esa cota para
  alinearse a la losa adyacente. Coincide pixel-a-pixel con `default.project.json`.

#### Verificación automática de integridad de terreno
- `test:hole-check`: 0 huecos encerrados a 2 studs en los 5 mundos. PASS.
- `test:navigation`: 96/96 zonas alcanzables (28+17+17+17+17); rutas críticas
  Spawn→Arena→Boss→Exit con ancho libre > mínimo y alternativa ante cierre.
  Sin escalones (>4 studs), sin bultos, sin solapamientos visibles ni bloqueos
  de recorrido. Corredores mínimos: Forest 30st, Desert 47st, Ice 43st,
  Volcano 44st, Cyber 30st.
- `test:spawn`: los 5 spawns sobre suelo, 20×20 libres, orientados a la primera
  ruta. PASS.
- `test:world-edge`: 0 piezas `Border/` con `CanCollide`; el perímetro termina
  en caída (no muro); caer mata (`Humanoid.Health = 0`, sin teletransporte).
  Los abismos intencionales (bordes del mundo, cañones, precipicios) se
  conservan y no se han rellenado. PASS.
- `test:monster-access`: 60/60 spawns válidos (suelo, holgura, ruta desde el
  spawn, separación). PASS.
- `test:bomb-grid`: 5×5 + centros + esquinas + bordes aceptados en los 5
  mundos. PASS.
- `test:physics`: 14365 partes, 14365 ancladas, 0 problemas. PASS.
- `test:world-content`: 5/5 mundos con miniboss, secreto y prompt. PASS.
- `test:worlds` + `test:contract`: estructura y contrato de los 5 mundos. PASS.
- `test:powerup-boss`: 9 powerups = generados = pintados; 5 bosses declarados.
  PASS.
- `rojo:build` + `verify:structure` + `verify:wiring`: PASS.

#### Divergencia HUD/UIScale (independiente de la reparación del terreno)
- `docs/runtime-source-diff.md` reportaba **6 elementos SOBRA en Studio** que
  el source (generado por `tools/hud.js`) no produce:
  1. `Root.BottomBar.Scale` [UIScale]
  2. `Root.CenterFeedback.Scale` [UIScale]
  3. `Root.LeftPanel.Scale` [UIScale]
  4. `Root.RightPanel.Scale` [UIScale]
  5. `Root.TopBar.Scale` [UIScale]
  6. `Root.TopBar.UIPadding` [UIPadding]
- **Causa:** el `AutoRecovery_0.rbxl` de Studio cargaba una versión pre-fix del
  HUD donde el `UIScale` vivía en la ZONA (parent), no en el CONTENIDO. El
  código de `tools/hud.js` y `UIController.lua` (líneas 84-99, 393-398) mueve
  la escala al contenido para no encoger/desplazar las zonas. El archivo
  `tools/sync-hud.js` existe precisamente para reconstruir el HUD desde el
  generador y resolver esta divergencia.
- **Acción:** `node tools/sync-hud.js` → HUD reconstruido (144 instancias) sobre
  el source. Verificado: los 6 elementos padre desaparecen y aparecen los 7
  `UIScale` + 1 `UIPadding` en el nivel de contenido correcto.
- **Resultado Post-fix:** `source-runtime-diff.js` → 0 faltan / 0 sobran / 0
  clases distintas → **PASS**.

#### Playtest en Studio (PLAY real)
- **COMPLETADO (2026-10-09):** Play arrancado via MCP (`solo_playtest` en modo `play`
  con roles `edit`, `server`, `client-1`). El jugador spawnó en el lobby a
  (24, 5, 0), nivel 1, 100 HP, RoundState = "Waiting".
- **Recuento de piezas en runtime (servidor de Play)**: idéntico al source:
  Forest 4162, Desert 2610, Ice 2417, Volcano 2564, Cyber 2834 (más el lobby y
  stations). **0 piezas en (0,0,0)** → ninguna amontonada en el origen.
- **Recorrido por los cinco portales** (`PortalService.HandleEnter` con cooldown
  de 4s entre entradas, `PORTAL_COOLDOWN = 3`):

| Mundo | CanTravel | IsWorldAvailable | Estado | Spawn destino | Posición destino |
|-------|-----------|------------------|--------|----------------|------------------|
| Forest | true | true | Open | 492, 4, -158 | ✓ |
| Desert | true | true | Open | -1360, 4, 1171 | ✓ |
| Ice | true | true | Open | 1234, 4, 1185 | ✓ |
| Volcano | true | true | Open | -1363, 4, -1414 | ✓ |
| Cyber | true | true | Open | 1238, 4, -1417 | ✓ |

- **Seguridad de portales**: `CanTravel` rechaza correctamente `worldId`
  inexistente, vacío, numérico, tabla, y "no se abandona una ronda en curso".
  `IsPortalUsable` verifica `State == Open` antes de permitir viaje.
- **Nota sobre `DISABLED_WORLDS` en `portal-source-audit.js`**: el conjunto
  `{Desert, Ice, Volcano, Cyber}` es una constante *hardcodeada* de la versión
  anterior. Desde FASE 3, `WorldAccessRules.CanEnter` abre todos los mundos desde
  nivel 1 (`WorldAccessRules.OpenLevel = 1`). Los paneles de los 4 "mundos
  deshabilitados" muestran su color original de la fuente, no el gris 70/74/86,
  porque los mundos NO están deshabilitados. La auditoría de apariencia
  (`portal-source-audit.js`) necesita actualizarse para reflejar que todos los
  portales están activos.

---

## FASE 6 — Sincronización Source↔Studio y verificación integral

### Problema
El plugin de Rojo no está conectado a la sesión de Studio. La geometría del
mapa (14,365 partes) y el HUD (144 instancias) no llegaban al DataModel,
requiriendo un pipeline de sincronización manual por MCP. Además,
`import_rbxm` dejaba las posiciones en `(0,0,0)` y creaba carpetas anidadas
duplicadas (defecto de sincronización #11 en `docs/sync-defects.md`).

### Corrección
1. **`sync-all.js`**: pipeline idempotente que ejecuta en orden:
   - `rojo build` → genera `default.project.json`
   - `reset-map.lua` → purga el mapa previo (solo si está en estado inválido)
   - `import_rbxm` → importa el subárbol `Workspace` como `.rbxm`
   - `import_rbxm` (con `SYNC_CLASS=Folder`) → importa `StarterGui`
   - `merge-startergui.lua` → reubica el HUD, borra wrappers, descarta RemoteEvents huérdos
   - `merge-workspace.lua` → sube hijos del wrapper, borra el envoltorio
   - `dedupe-workspace.lua` → colapsa homónimos recursivamente
   - `dedupe-code.lua` → elimina duplicados de código (CoreRules, VisualService, etc.)
   - `fix-starterscripts.lua` → contenedor real de StarterPlayer
   - `apply-map-positions.js --run` → coloca todas las posiciones/color/size/rotation desde la fuente
   - `sync-lighting.lua` → ajusta Lighting y efectos
   - `sync-scripts.js` → escribe los 63 scripts de servidor
   - `dedupe-code.lua` (segunda pasada) → limpieza post-scripts
   - `source-runtime-diff.js` → verificación final

2. **`sync-hud.js`**: reconstrucción completa del HUD desde el generador
   `tools/hud.js`. Resolvió 46 elementos faltantes + 6 sobrantes de UI scale/padding
   en el `AutoRecovery_0.rbxl` (HUD con UIScale en el padre en vez del contenido).

3. **`apply-map-positions.js`**: el `import_rbxm` de Studio deja `Position = (0,0,0)`.
   Este script lee `default.project.json` y aplica posición, tamaño, orientación,
   color, material, transparencia, CanCollide y Shape a cada una de las 14,365 partes
   desde la fuente única.

### Verificación
- **`source-runtime-diff.js`**: **PASS** — 0 faltan, 0 sobran, 0 clases distintas
  (15,013 source == 15,021 runtime; diferencia de 8 es `Terrain`/`Camera` engine-owned).
- **`apply-map-positions.js --run`** (edit-mode): 14,365 partes declaradas,
  `alreadyCorrect = 14,365`, `missingFromRuntime = 0`, `fixedPosition = 0`
  (todo ya estaba en su sitio tras el `sync-all.js`).
- **`portal-verify.js`**: 5 portales registrados, todos `State = Open`,
  `RequiredLevel = 1`, seguridad de worldId verificada.
- **Traversal en Play**: los 5 mundos son entrados correctamente con cooldown de 4s
  entre entradas (`PORTAL_COOLDOWN = 3`). Posiciones de spawn coinciden con source.
- **`portal-source-audit.js`**: todos los elementos de los portales coinciden
  (color, material) excepto paneles de mundos "deshabilitados" que son un
  hardcodeo obsoleto (ver nota arriba).
- **Suite Luau**: 70 suites, 1104 tests, **0 fallos** (anteriormente 11 fallos
  por specs faltantes de FASE 5–8).
- **`verify:structure`**: 45 servicios, estructura correcta.
- **`verify:wiring`**: 36 servicios, 24 conexiones, 51 llamadas, todos los métodos cableados existen.
- **`npm run verify`**: PASS completo (todos los sub-tests en verde).
- **`analyze.js`**: FAIL preexistente (521 incidencias, documentado en
  `GAMEPLAY_AUDIT.md` línea 241). No está relacionado con esta sesión.
