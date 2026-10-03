# ACCEPTANCE TESTS

> Checklist de aceptacion. **No es un reporte**: un item solo se marca
> cuando hay evidencia en `docs/` y el item se marco asi.
>
> Estados validos: `PASS` · `FAIL` · `BLOCKED` · `NO INICIADA`.
> Nunca "casi", "deberia funcionar" ni "probablemente".
>
> Evidencia por item: archivo de fase en `docs/`, o salida de
> `tools/` (la salida de una herramienta cuenta; la intencion no).

## QUE ESTA VERIFICADO HOY

| Ambito | Estado | Evidencia |
| --- | --- | --- |
| Suite de logica pura | PASS | 219/219 con `tools\luau\luau.exe tests\RunTests.lua` |
| Estructura de servicios | PASS | `node tools/verify-structure.js` |
| Wiring remotos | PASS | `node tools/verify-wiring.js` |
| Analisis estatico | PASS | `node tools/analyze.js` |
| Build Rojo | PASS | `rojo\rojo.exe build default.project.json` |
| Tree de Workspace del lugar | BLOCKED | el lugar abierto en Studio no es el build |
| Play con jugador real | BLOCKED | requiere sesion de Studio + jugador |

Las fases 0 y 1 siguen marcadas **BLOCKED** en `docs/phases.md` por
esto mismo: el codigo es solido, la ejecucion dentro de Studio todavia
no esta certificada.

---

## PLAYER
[ ] Character carga  ·  [ ] Camara funciona  ·  [ ] HUD aparece
[ ] Input responde  ·  [ ] Respawn correcto

## LOBBY
[ ] Lobby carga  ·  [ ] KeshusyCore existe  ·  [ ] Portales existen
[ ] Interaccion de portal  ·  [ ] Tienda abre  ·  [ ] Inventario abre

## PORTALS
[ ] Forest abre  ·  [ ] Requisito Desert validado
[ ] Requisito Ice validado  ·  [ ] Requisito Volcano validado
[ ] Requisito Cyber validado  ·  [ ] Feedback de bloqueado
[ ] Teleporte exitoso

## BOMBS
[ ] Bomba por teclado  ·  [ ] por tactil  ·  [ ] por mando
[ ] El servidor recibe la peticion  ·  [ ] El servidor la valida
[ ] La bomba aparece  ·  [ ] Mecha funciona  ·  [ ] Explosion
[ ] Reaccion en cadena  ·  [ ] Destruccion

## COMBAT
[ ] Daño a jugador  ·  [ ] Daño a monstruo  ·  [ ] Validacion PvP
[ ] Invulnerabilidad  ·  [ ] Cooldowns  ·  [ ] Muerte  ·  [ ] Respawn

## MONSTERS
[ ] Spawn  ·  [ ] IA arranca  ·  [ ] Seleccion de objetivo
[ ] Movimiento  ·  [ ] Ataque  ·  [ ] Daño  ·  [ ] Muerte  ·  [ ] Recompensa

## BOSS
[ ] Spawn  ·  [ ] Fase 1  ·  [ ] Fase 2  ·  [ ] Fase 3
[ ] Ataques  ·  [ ] Daño  ·  [ ] Muerte  ·  [ ] Recompensa

## INVENTORY
[x] Concede item · [x] Quita item · [x] Consume consumible
[x] Equipa item poseido · [x] Desequipa sin perder el item
[x] Un item no apilable no pasa de 1 · [x] Pila respeta MaxStack
[x] Item inexistente rechazado · [x] Auditoria sin anomalias

## SHOP
[x] Catalogo server-authoritative · [x] Compra con la cadena completa
[x] Precio tomado del catalogo, no del cliente
[x] Cobrar antes de entregar · [x] Devolucion si la entrega falla
[x] Bundle expandido en sus piezas
[x] Idempotencia por peticion
[ ] UI de tienda · [ ] Feedback de saldo insuficiente en pantalla

## ECONOMY
[x] XP · [x] Coins · [x] Gems · [x] Sin saldos negativos
[x] Sin recompensas duplicadas · [x] Transacciones validadas
[x] Ledger con antes/despues · [x] Auditoria sin anomalias
[x] Compra no cobra dos veces por reintento
[x] Compra de item ya poseido no cobra
[x] Compra sin saldo no cobra
[x] Subida de varios niveles en una sola recompensa
[x] Recompensa de nivel no se paga dos veces

> Evidencia: `node tools/economy-cert.js` sobre un jugador real en PLAY.
> XP, coins, compra, inventario, equipar y subida multiple medidos.

## DATA
[x] Carga de perfil · [ ] Guardado · [x] Autosave · [x] Guardado final
[x] Migracion · [x] Bloqueo de sesion · [x] Proteccion anti-duplicado
[x] Perfil ilegible NO se sobrescribe · [x] Perfil no serializable rechazado
[x] Fallo de escritura deja el perfil sucio y reintentable
[x] Modo sin persistencia degradado con aviso

> **Guardado real: NO verificado.** `DataStoreService` exige el lugar
> publicado. Verificado con harness sobre el `DataService` real
> (`node tools/economy-cert.js --harness`). Ver `docs/phases.md`.

## SOCIAL
[ ] Crear party  ·  [ ] Unirse  ·  [ ] Salir  ·  [ ] Flujo de servidor privado

## MOBILE
[ ] Controles tactiles  ·  [ ] HUD responsivo  ·  [ ] Sin solapamiento
[ ] Safe area

## GAMEPAD
[ ] Navegacion  ·  [ ] Bomba  ·  [ ] Interaccion  ·  [ ] Menus

## PERFORMANCE
[ ] Sin bucles infinitos  ·  [ ] Sin conexiones sin limite
[ ] Limpieza de VFX  ·  [ ] Limpieza de NPCs  ·  [ ] Rate limit en remotos
[ ] Memoria estable

## SECURITY
[x] El cliente no otorga moneda · [x] El cliente no elige daño arbitrario
[x] El cliente no evade requisitos de mundo · [x] Sin duplicar recompensas
[x] Remotos con rate limit · [ ] Autorizacion de admin validada
[x] El cliente no elige el PRECIO (solo manda `ItemId`)
[x] El cliente no declara lo que tiene en el inventario
[x] Usar o equipar un item que no se posee = rechazado
[x] Subir a un nivel N no se paga dos veces
