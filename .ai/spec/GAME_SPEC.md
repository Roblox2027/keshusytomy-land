# KESHUSYTOMY-LAN-D — ESPECIFICACION (INDICE)

> Este archivo es un **indice y un contrato**, no una copia del estado.
> El estado real de cada fase vive en `docs/phases.md` y es el unico
> que manda. Si aqui y alla se contradicen, gana `docs/phases.md`.

## Identidad

Juego de accion PvP/PvE en Roblox: arenas, bombas, monstruos,
exploracion de mundos, progresion, bosses, cosmeticos y eventos.

## Core loop

```
Lobby -> elegir actividad -> entrar a mundo -> ronda
      -> explorar -> colocar bomba -> destruir -> obtener drops
      -> combatir -> cumplir objetivo -> XP/Coins/Gems
      -> volver al Lobby -> progresar
```

## Mundos

1. Keshusy Forest  2. Boom Desert  3. Frozen Tomy
4. Volcano Rage   5. Cyber Keshusy

Definiciones de mundo: `src/ReplicatedStorage/WorldDefinitions/`.
Geometria en el mapa: `src/Workspace/Worlds/` y `default.project.json`.

## Modos

Classic PvP · Team Battle · Monster Hunt · Boss Rush ·
Chaos · Ranked · Private · Events

## Sistemas

Bombas, explosiones, destruccion, combate, monstruos, bosses,
powerups, XP, coins, gems, inventario, tienda, quests, season,
battle pass, party, events, codes, logros, datastore, monetizacion,
seguridad, UI, audio, VFX, performance.

Implementacion por sistema: `src/ServerScriptService/Services/`.
Reglas puras y probadas: `src/ReplicatedStorage/Shared/Libraries/`.

## REGLA FUNDAMENTAL

Una funcionalidad **NO** esta terminada porque el archivo exista.
Esta terminada solo cuando se verifico la cadena completa:

```
SOURCE -> BUILD -> ROJO -> STUDIO -> PLAY -> PLAYER -> INPUT
-> SERVER -> RESULTADO -> REWARD/PERSISTENCIA -> QA
```

Un `.lua` que compila, un test que pasa y un script que encuentra un
archivo NO cubren esa cadena. Para el estado de ejecucion:
`tools/diagnostics/runtime-scan.js` (consulta Studio via MCP y reporta
`BLOCKED` si no puede comprobarlo).

## Autoridad del servidor

El servidor decide, el cliente pide:

daño · bombas · recompensas · XP · coins · gems · inventario ·
compras · progresion · combate · estado de ronda · acceso a mundos ·
drops · datos

Nunca confiar en un valor critico enviado por el cliente. Limites de
tasa en `Shared/Libraries/RateLimiter.lua`; esquema de remotos en
`Shared/Libraries/RemoteSchema.lua`; validacion en
`Systems/RemoteGateway.lua`.
