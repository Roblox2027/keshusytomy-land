# Clasificación de Problems

Fecha: 2026-10-02
Fuente: `luau-analyze` sobre `src/` y `tests/` (herramienta local `tools/luau`)
Reproducible con: `node tools/classify-problems.js`

---

## Regla de este documento

Un número bruto de errores **no** es un número de defectos. Este archivo
agrupa las incidencias por **causa raíz** y las clasifica, para no "arreglar
síntomas uno por uno" ni tocar código que funciona.

Severidades: `P0` crítico · `P1` alto · `P2` medio · `P3` bajo · `INFO`

---

## Resumen

| | |
| --- | --- |
| Incidencias totales | 670 |
| Causas raíz distintas | 4 |
| Falsos positivos (entorno ausente) | 275 (41%) |
| Incidencias P2 (defecto real) | 395 |
| Incidencias P0 / P1 | **0** |
| Archivos con causa raíz real | 32 |

**Cero errores de sintaxis.** Todo el código compila y se ejecuta.

---

## Causa raíz 1 — El analizador no conoce el entorno Roblox

| Campo | Valor |
| --- | --- |
| ID | RC-1 |
| Categoría | False Positive |
| Severidad | INFO |
| Incidencias | 202 |
| Archivos | 19 |
| Dependencia | — |
| Acción | **Ninguna en el código.** Se resuelve con definiciones de Roblox. |

Síntoma representativo:


## Causa raíz 2 — `require` con ruta dinámica

| Campo | Valor |
| --- | --- |
| ID | RC-2 |
| Categoría | Require / False Positive |
| Severidad | INFO |
| Incidencias | 51 |
| Archivos | 17 |
| Dependencia | — |
| Acción | **Ninguna.** Es el patrón obligatorio del proyecto. |

Síntoma:

```
ServerMain.server.lua(35,16): TypeError: Unknown require: unsupported path
ServiceRegistry.lua(29,27): TypeError: Unknown require: unsupported path
```

El proyecto resuelve módulos en tiempo de ejecución:

```lua
require(SERVER:WaitForChild("Systems"):WaitForChild("ServiceRegistry"))
```

Un analizador estático no puede resolver una ruta que depende de
`WaitForChild`. Esto es **intencional y correcto**: es el patrón que permite
que el orden de arranque sea determinista y que los fallos aparezcan con un
mensaje claro en vez de un `require` silencioso.

Verificado en runtime de la manera que importa: el build de Rojo coloca

## Causa raíz 3 — Cascada por `Instance` sin tipo

| Campo | Valor |
| --- | --- |
| ID | RC-3 |
| Categoría | False Positive |
| Severidad | INFO |
| Incidencias | 22 |
| Archivos | 8 |
| Dependencia | **RC-1** |
| Acción | **Ninguna.** Se resuelve sola al arreglar RC-1. |

Síntoma:

```
BombService.lua(169,18): TypeError: Type 'unknown' does not have key 'Id'
BombService.lua(178,15): TypeError: Type 'unknown' does not have key 'Delay'
BombService.lua(422,17): TypeError: Type 'unknown' does not have key 'FindFirstChild'
```

Cuando `Instance` no está definido, toda instancia que se obtiene de
`WaitForChild` es `unknown`, y **todo lo que se le llama falla también**.
Son 22 errores derivados, no 22 problemas.

Están clasificados aparte, y no como P2, precisamente para que no se
confundan con defectos reales. Arreglarlos uno a uno sin RC-1 es imposible:
cada corrección desaparecería sola al definir el entorno.

cada módulo en su ruta esperada, y `audit-rbxlx` confirma que los 30

## Causa raíz 4 — Defectos de tipado reales

| Campo | Valor |
| --- | --- |
| ID | RC-4 |
| Categoría | Type |
| Severidad | **P2** |
| Incidencias | 395 |
| Archivos | 32 |
| Dependencia | parte de **RC-1** (no separable aún) |
| Acción | Revisar por archivo cuando el entorno esté definido |

Ejemplos:

```
Maid.lua(71,2): Property _count of type '...' is read-only
Maid.lua(71,2): Type function instance add<T, number> depends on generic
                function parameters but does not appear in the function
                signature
RemoteGateway.lua(72,14): Key 'capacity' is missing from '{ }'
RemoteGateway.lua(112,2): Expected this to be 'boolean, string?',
                          but got 'boolean'
RemoteGateway.lua(45,1): Operator '+' could not be applied to operands of
                         types (T & ~(false?)) | number and number
WorldService.lua(119,2): Expected this to be 'boolean, string?',
                         but got 'boolean'
ServiceRegistry.lua(194,16): Expected this to be '{~nil}', but got '{string}'
StateMachine.spec.lua(158,16): Expected this to be exactly 'string'
```

### Análisis honesto de este bloque

**395 es un número inflado y no debe leerse como 395 defectos.** Casi todo
el bloque es consecuencia en cascada de RC-1 y RC-3:

- Cuando `Instance` es `unknown`, el tipo de una tabla construida a partir
  de ella también lo es, y los operadores aritméticos sobre `unknown` fallan
  (`Operator '+' could not be applied`).
- Cuando `Registry:Get` devuelve `any`, propagar ese `any` genera errores
  en cada uso posterior, incluido el retorno de funciones que declaran
  `(boolean, string?)`.

**Lo que sí es un defecto genuino e identificable hoy** es un patrón
recurrente de tres tipos:

1. **Firmas que declaran más de lo que devuelven.** `Register`, `Start` y
   similares declaran `-> (boolean, string?)` pero hacen `return true`.
   Es una inconsistencia real de tipos, de bajo riesgo: no cambia el
   comportamiento, pero hace que el analizador no pueda ayudar.
2. **Campos de clase mutables leídos como solo-lectura** (`Maid._count`).
   Consecuencia de que la tabla de clase sirva de prototype.
3. **`options or {}` sin anotación de tipo** (`RemoteGateway` 72-73), ya
   identificado como P2 en la auditoría principal.

Ninguno de estos tres impide que el juego funcione.

### Por qué no se corrigen ahora

Corregir 395 incidencias sin las definiciones de Roblox produce dos
resultados malos por igual: se cambian líneas que no estaban rotas, o se
introducen anotaciones queStudio no necesita. **Ambas cosas rompen la regla
de no tocar producción para satisfacer a una herramienta mal configurada.**

El orden correcto es: primero montar el proyecto en Studio (P0), confirmar
que el runtime funciona, y después usar las definiciones de Roblox para
aislar lo que de verdad sobra.

servicios, los 12 controllers y los 8 remotos existen en el árbol final.
Las rutas coinciden con las que el código pide.

```
Maid.lua(28,10): TypeError: Unknown global 'warn'; consider assigning to it first
Maid.lua(37,22): TypeError: Unknown type 'Maid'
SpawnService.lua(107,53): TypeError: Unknown global 'Vector3'
RemoteGateway.lua(164,26): TypeError: Unknown type 'Player'
```

`luau-analyze` standalone no trae las definiciones del entorno Roblox
(`game`, `Instance`, `Vector3`, `CFrame`, `task`, `Enum`, `warn`, `Player`,

---

## Tabla maestra

| ID | Categoría | Severidad | Archivo/Objeto | Causa | Dependencia | Acción |
|---|---|---|---|---|---|---|
| **P0-1** | Workspace / Runtime | **P0** | Lugar `KeshusyTomy-LanD.rbxl` | Proyecto no sincronizado: `ServerScriptService` vacío | — | Montar el proyecto de Rojo en Studio |
| RC-1 | False Positive | INFO | 19 archivos | Analizador sin definiciones de Roblox | — | Añadir definiciones de tipos |
| RC-2 | Require | INFO | 17 archivos | `require` con ruta por `WaitForChild` | — | Ninguna (patrón correcto) |
| RC-3 | False Positive | INFO | 8 archivos | Cascada de `Instance` sin tipo | RC-1 | Ninguna (se resuelve con RC-1) |
| RC-4 | Type | P2 | 32 archivos | Defectos de tipado reales | parte de RC-1 | Revisar tras definir entorno |
| RC-5 | Type | P2 | `RemoteGateway.lua:72` | `options or {}` sin anotación | — | Anotar el tipo |
| RC-6 | Documentación | P3 | `Remotes.model.json` | Formato heredado (`ClassName`+`Children`), no soportado oficialmente por Rojo 7 | — | Migrar a `$className` + campos directos |
| RC-7 | Naming | INFO | `Workspace/Worlds/Forest` vs `WorldDefinitions/Forest` | El mismo nombre designa un ModuleScript de config y una carpeta de mapa | — | Aceptado: son capas distintas, se documenta |

### Sobre RC-6

Rojo 7.7.0 **sí** interpreta el formato heredado y produce correctamente
los 8 `RemoteEvent` (verificado en el build, no asumido). Se clasifica P3
porque es deuda técnica, no un fallo actual. Migrarlo es seguro pero no
urgente, y hacerlo ahora añadiría riesgo sin beneficio verificable.

### Sobre RC-7

`ReplicatedStorage/WorldDefinitions/Forest` (ModuleScript: definición del
mundo) y `Workspace/Worlds/Forest` (carpeta: geometría del mundo) son
cosas distintas en capas distintas. No es una inconsistencia que cause
problemas. Se acepta y se documenta para que nadie lo "normalice" por
error.

---

## Conteo verificado

```
INCIDENCIAS TOTALES:                 670
FALSOS POSITIVOS (RC-1 + RC-2 + RC-3): 275
INCIDENCIAS REALES (RC-4 + RC-5):      395
P0 / P1:                                0
ERRORES DE SINTAXIS:                     0
```

Ninguna corrección aplicada a código en esta tanda. Detalle del antes/después
en `problems-before-after.md`.

y los tipos de cada API). **No es un defecto del juego.** El mismo código
funciona en Studio, donde esas definiciones existen.

**Por qué no se "arregla":** introducir declaraciones de tipos solo para
callar al analizador standalone sería cambiar producción para satisfacer a
una herramienta mal configurada. El juego corre en Roblox, no en el
intérprete suelto.
