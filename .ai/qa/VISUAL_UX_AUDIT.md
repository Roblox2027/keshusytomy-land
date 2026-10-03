# AUDITORIA VISUAL Y UX

> Documento vivo. Separa lo que se ha PODIDO observar de lo que esta
> bloqueado por la herramienta. Un elemento que nadie ha visto en
> pantalla no se marca "correcto": se marca `BLOCKED`.

## 1. Restriccion del entorno (manda sobre todo lo demas)

El servidor MCP funciona: `eval_server_runtime` responde y hay un
servidor de juego CONECTADO con un jugador real. El **cliente** MCP no
funciona: `eval_client_runtime` agota el tiempo de espera incluso con
`return 1+1` (medido, no supuesto).

Consecuencia directa y honesta: **no se puede observar la pantalla del
jugador**. Todo lo que dependa de ver la interfaz queda `BLOCKED`.

## 2. Inventario de elementos temporales

Cada elemento que aparece y desaparece debe seguir el ciclo completo:

```
CREATE -> SHOW -> UPDATE -> HIDE -> DESTROY/CLEANUP
```

Nunca basta con `CREATE -> SHOW`.

### 2.1 Cartel de portal (`PortalFeedback`)

| Propiedad | Estado | Nota |
| --- | --- | --- |
| Se crea una sola vez por HUD | PASS (codigo) | `buildGui` lo crea dentro de `UIController`; el `PortalController` no crea panel propio, por diseño |
| Se oculta tras 3.5 s | PASS (codigo) | temporizador con token |
| Token evita el solape | PASS (codigo) | `_portalHideToken` invalida el temporizador anterior |
| Se ve correctamente | **BLOCKED** | requiere cliente |
| No queda pegado | **BLOCKED** | requiere cliente |

El token es la defensa correcta contra el fallo real: dos rechazos
seguidos dejarian dos hilos esperando y el primero ocultaria el cartel
del segundo antes de tiempo.

### 2.2 HUD (`GameHUD`)

| Campo | Origen | Estado |
| --- | --- | --- |
| Ronda / tiempo / vivos | atributos del servidor | PASS (logica) |
| Nivel / XP / monedas | atributos del servidor | PASS (logica) |
| Gemas | atributo `Gems` | PASS (logica) |
| Mundo | atributo `World` | PASS (logica) |
| Bombas | atributo `Bombs` | PASS (logica) |
| Poder del Core | `CoreState` / `CoreCharge` | PASS (logica) |
| HP | Humanoid del cliente | PASS (logica) |

Reglas de seguridad visual que SI se cumplen en el codigo:

- la UI **no calcula** nada de juego: lee `player:GetAttribute`;
- `ResetOnSpawn = false`, asi que no se duplica al reaparecer;
- `Start` es idempotente (`if Controller.IsActive then return true`), lo
  que impide dos HUD superpuestos si el controller se reinicia;
- `Destroy` revierte conexiones y elementos (via `Maid`).

### 2.3 Elementos aun NO verificados y por que

| Elemento | Bloqueo |
| --- | --- |
| UI de inventario | no implementada en cliente |
| UI de tienda | no implementada en cliente |
| Sistema de notificaciones | no existe |
| Popups de recompensa / subida de nivel | no existen |
| Numeros de dano flotantes | no existen |

## 3. Hallazgos de codigo en esta pasada

### 3.1 `hpLabel` sin usar (P4, no un fallo de juego)

`UIController` crea la etiqueta de HP y la guarda en `_labels["HP"]` a
traves de `makeLabel`, asi que **si** se actualiza en `refresh()`. La
variable local `hpLabel` no se usa nunca. Es ruido de analizador, no un
valor congelado: el HUD muestra el HP correcto.

### 3.2 Actualizacion del HUD cada segundo (riesgo real, P3)

El HUD refresca con un bucle de 1 s para cubrir la cuenta atras, que
cambia cada segundo sin disparar evento de atributo. No es "polling
agresivo", pero es un refresco por segundo por jugador. Con muchos
jugadores conviene un contador de intervaloAttributes en vez de un
bucle. **No se cambia aqui**: tocarlo sin poder observar la pantalla seria
cambiar a ciegas el unico componente que hoy nadie puede verificar.

### 3.3 Texto que no depende solo del color

El cartel de portal usa verde/ambar/rojo **ademas** de texto explicito
("Entrando...", "Requires Level N"), lo que cumple el criterio de no
depender unicamente del color.

## 4. Criterio de aprobacion de UI (no se relaja)

Una UI no esta PASS porque exista, compile o aparezca. Se exige:

```
OPEN -> INTERACT -> UPDATE -> CLOSE -> REOPEN -> UPDATE -> DESTROY
```

repetido. Con `eval_client_runtime` bloqueado, **el ciclo completo no se
ha ejecutado ni una vez**. Por tanto UI = `BLOCKED`, con el codigo en
estado `PARTIAL`.