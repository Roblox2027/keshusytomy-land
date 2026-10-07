# GAMEPLAY AUDIT — KeshusyTomy-LanD

> FASE 1 de la MASTER MISSION V2.
> Auditoría de diversión sobre el estado real del código (commit `ed18f24`).
> Cada entrada: problema, ubicación, causa, impacto, solución propuesta, prioridad.
> Prioridades: **P0** (mata la diversión hoy), **P1** (limita retención), **P2** (profundidad/largo plazo).

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
| Mecánicas por mundo | NO EXISTE (hazards sin efecto físico) | No |
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
