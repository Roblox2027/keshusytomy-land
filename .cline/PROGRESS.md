# PROGRESS

## Estado general
- Branch: main (HEAD == origin/main = c939967) - baseline Fase 0+1 sin commitear hasta verify verde completo
- Fase actual: 1 -> 2
- Estado: FASE 1 COMPLETADA (verify exit 0, generator idempotente)

## Fases
- [x] 0 Audit (fix zoneRim fallback `_Rim_999`; fix Forest ruta alternativa CentralPath->ExitNorth; verify completo PASS)
- [x] 1 Generator (auditoria: determinismo PASS, idempotencia 2x SHA256 identico, git status estable, escribe solo default.project.json + tools/sync-lighting.lua, sin random/timestamps/IDs; fix `return map;` duplicado; bateria verify completa PASS)
- [x] 2 Sistemas existentes (inventario 37 servicios: 28 registrados / 9 stubs ~810-835B sin registrar por diseño / 0 duplicados `*Service2`; FIX: EventService y MiniBossService cableados - construidos pero muertos en runtime; verify:wiring PASS 28/19/45; verify completo exit 0. Hallazgos pendientes: HordeService sin bucle spawn/kill y StartHorde sin llamantes = Fase 31-37; EventService sin HUD consumidor = Fase 58-59)
- [ ] 3 Acceso mundos
- [ ] 4 Arquitectura mundos
- [ ] 5 Terreno organic
- [ ] 6-10 Forest/Desert/Ice/Volcano/Cyber
- [ ] 11 Verticalidad
- [ ] 12-14 Estructuras/Destruccion/Destruccion structural
- [ ] 15 Bombas
- [ ] 16-29 Monster/Hunters/Stalker/Patrols/Ambushers/Guardians/Nests/Noise/Threat/Dynamic spawn
- [ ] 30 99 noches
- [ ] 31-37 Escalado/Dia-Noche/Hordas/Eventos/Mini-bosses/Bosses
- [ ] 38-51 Powerups/Chests/Resources/Secrets/Quests/Progression/Economy/Shop/Cosmetic/Boosts/Daily/Bundles/Developer products/GamePasses
- [ ] 52 Multiplayer
- [ ] 53-54 Security/Performance
- [ ] 55-57 Death/Respawn/Reentry
- [ ] 58-59 HUD/Audio/VFX
- [ ] 60 Tests
- [ ] 61-62 MCP/Datamodel/Play Test
- [ ] 63 Responsive/Regression/Certification/Git

## Infraestructura
- MCP Roblox: BLOCKED (plugin MCP no activo en Studio; puerto 58741 sin escuchar). Detectado con `npm run mcp:list` y `npm run runtime:scan`.
- Studio: proceso RobloxStudioBeta ABIERTO (PID 29564) pero sin MCP ni Play Test dirigible headless.
