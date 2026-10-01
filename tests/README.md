# tests

Suite de pruebas del proyecto.

| Carpeta  | Alcance                                                |
| -------- | ------------------------------------------------------ |
| `shared/` | Modulos puros compartidos (sin servicios de Roblox)     |
| `server/` | Servicios de servidor con entorno simulado             |
| `client/` | Controllers y presentacion                             |

Convencion de nombres: `<Modulo>.<Area>.spec.lua`

## Ejecucion

Desde la raiz del repositorio, con el interprete de Luau:

```text
luau.exe tests/RunTests.lua
```

Estado actual: **56 pruebas, 0 fallos**. El proceso devuelve codigo
de salida 0 cuando todo pasa, lo que permite usarlo en integracion
continua.

## Como funciona

- `TestHarness.lua` ofrece `describe`, `it` y `expect`. Un error dentro
  de una prueba cuenta como fallo, nunca como exito.
- Cada `.spec.lua` devuelve una funcion que registra sus pruebas; asi
  una suite que no carga se detecta como fallo y no se ignora en
  silencio.
- `RunTests.lua` carga cada suite con `pcall` e informa tambien de los
  errores de carga.

## Alcance honesto

Se prueba la logica pura compartida: `Maid`, `RateLimiter`,
`StateMachine`, `RemoteSchema` y las configuraciones.

NO se prueba aqui, y por tanto NO se marca PASS:

- comportamiento en Workspace, Players o fisica;
- DataStore, MonetizationService y Receipts;
- UI y su comportamiento visual;
- rendimiento real con jugadores conectados.

Eso se verifica dentro de Roblox Studio y se documenta como
`BLOCKED` en el archivo de fase correspondiente.

TestEZ puede integrarse mas adelante para las pruebas que si
necesitan el motor; el harness actual no lo imposibilita.
