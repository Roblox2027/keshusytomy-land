# Keshusy Core

Fecha: 2026-10-02

Estado: **implementado y verificado en runtime**.

## Que es

El corazon del lobby. Los jugadores aportan fragmentos, la barra se
llena, y al llegar al maximo el nucleo se activa y desbloquea el mundo
siguiente.

## Separacion de responsabilidades

El motivo de que exista `CoreRules` como modulo aparte es el mismo que
para `CombatMath`: **las reglas tienen que poder probarse de verdad**.

| Archivo | Que contiene | Se prueba con |
| --- | --- | --- |
| `Shared/Libraries/CoreRules.lua` | Maquina de estados, limites, recarga | `luau.exe` (22 pruebas) |
| `Services/CoreService.lua` | Mapa, jugadores, difusion, ciclo de vida | Studio (runtime) |

Si las reglas vivieran dentro de `CoreService`, ninguna se podria
ejecutar fuera de Roblox y las 22 pruebas no existirian.

## Estados

```
Inactive ──carga=max──> Activating ──ventana──> Active
    ^                        │                  │
    │                        │                  ├─drenaje──> Inactive
    └──drenaje── Overloaded <──sobrecarga── Event
```

- `Inactive`: admite fragmentos.
- `Activating`: la secuencia corre; **no** admite fragmentos.
- `Active`: estable; se descarga despacio para poder volver a cargarse.
- `Overloaded`: se drena sola; no admite fragmentos.
- `Event`: bonificacion tras activarse.

Solo `Inactive`, `Active` y `Event` aceptan fragmentos. La decision
esta en `CoreRules.AcceptsFragments`, en un unico sitio.

## Decisiones que el cliente NO puede tomar

| El cliente intenta | Que pasa |
| --- | --- |
| Aportar un fragmento sin payload | Es lo unico que se acepta: `CoreAction.Interact` no admite numero ni tabla |
| Enviar la cantidad de carga | Rechazado por el esquema (`PayloadType.None`) |
| Enviar un estado o un tiempo | Rechazado: el estado lo decide `CoreRules` |
| Aportar desde lejos | Rechazado por `INTERACT_RANGE` (40 studs) |
| Enviar fragmentos en rafaga | Rechazado por `CoreFragmentCooldown` (0.5 s) |
| Llenar la barra en solitario | `CoreFragmentsPerPlayer` (20) |

`CoreAction.Interact` se declara deliberadamente **sin payload**: si
admitiera un numero, el servidor tendria que fiarse de el para saber
cuanta carga aporta el jugador.

## Verificacion

**Pruebas de reglas (22, locales):**

```text
luau.exe tests/RunTests.lua
PRUEBAS: 160 pasaron | 0 fallaron
```

Las pruebas se comprobaron contra mutaciones: al quitar el limite por
jugador y al quitar la recarga, cada una fallo. Una prueba que no puede
fallar no vale como prueba.

**Seguridad (runtime, `tools/core-security.js`):**

```text
A) lejos -> ok=false motivo=demasiado lejos del nucleo
   carga=0 (antes=0)
B) junto -> ok=true
   carga=10/100
C) seguido -> ok=false motivo=demasiado rapido
   carga=10
D) payload numero -> false
D) payload tabla -> false
D) sin payload -> true
E) aumento real=10
```

El aumento real coincide con `GameConfig.CoreChargePerFragment` (10):
la cifra la pone la configuracion del servidor.

## Dos bugs reales encontrados al verificarlo

### 1. `ClampCharge` borraba la barra con `+inf`

La primera version trataba cualquier valor no finito como 0. Con un
maximo de 100, una carga `+inf` se convertia en una barra **vacia** y
el nucleo volvia a `Inactive` cuando en realidad estaba sobrecargado.

Se corrigio distinguiendo los tres casos, que no significan lo mismo:

| Entrada | Resultado | Por que |
| --- | --- | --- |
| `NaN` | 0 | No es comparable con nada: esta corrupto |
| `+inf` | `maxCharge` | Es una carga "demasiado grande", no inexistente |
| `-inf` | 0 | Descrita por debajo del rango |

Lo encontro la prueba `una carga infinita se recorta al maximo`, que
fallaba con "se esperaba 100, se obtuvo 0".

### 2. Studio tenia DOS `CoreService`

El servicio aparecia con `Init=si`, `Start=si` pero
`IsInitialized=no`, lo que es contradictorio. La causa era un
**duplicado de instancia**: `Services` tenia 33 hijos en vez de 32.

Por que importaba: `boot-state.js` recorria los hijos y leia el
**primero**, que era la copia vieja sin inicializar, mientras la sonda
que resolvia por nombre leia la buena. Dos herramientas con el mismo
codigo daban resultados distintos, y ambas parecian razonables.

Se elimino la copia incompleta conservando la que tenia el ciclo de
vida completo (`Start` y `GetState` presentes), y se verifico que el
build de Rojo contiene una sola instancia (`<string name="Name">CoreService</string>`).

Es el mismo fallo que ya documenta `dedupe-workspace.lua` para
`Workspace.Worlds`: un duplicado no es cosmetico, porque
`FindFirstChild` devuelve el primero que encuentra.

## Nota sobre `mcp.serverLuau`

El codigo del servidor debe ejecutarse en el peer del **servidor**
(`mcp.serverLuau`). Con `mcp.tool("execute_luau")` corre en otro
contexto y `Players:GetPlayers()` sale vacio: parece que no hay
jugador cuando si lo hay. `boot-state.js` ya usaba `serverLuau`; el
primer diagnostico de este trabajo usaba `tool` y dio un falso
"sin jugador".

## Lo que NO se verifica aqui

La parte visual (anillos, brillo, color por estado) se comprueba que
`Start` la aplica sin error en runtime, pero **el aspecto final en
pantalla no se ha revisado**: eso requiere mirar el juego. No se
declara PASS.

## Desbloqueo de mundos

`IsWorldUnlocked` y `GetNextWorldId` usan el orden
`Forest, Desert, Ice, Volcano, Cyber`. El primero siempre esta
accesible; cada activacion abre UNO mas.

Con la `FeatureConfig` actual solo `Forest` esta habilitado, asi que
`GetNextWorldId` devuelve `nil`: no hay mundo siguiente que abrir. Es
el comportamiento correcto con cuatro mundos apagados, no un fallo.