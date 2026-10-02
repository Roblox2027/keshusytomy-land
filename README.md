# KeshusyTomy-LanD

Juego de bombas y destruccion en Roblox. Este repositorio contiene
**la fuente de verdad del codigo**: todo el codigo permanente se escribe
aqui como archivos Luau y llega a Roblox Studio mediante Rojo.

Estado actual: **FASE 1 - Foundation**. La fundacion (registros,
ciclo de vida, validacion de remotos y limpieza) esta implementada y
probada. El juego en si todavia no es jugable: eso llega en las fases
de contenido.

## Pruebas

La suite se ejecuta con el interprete de Luau, sin necesidad de abrir
Roblox Studio:

```text
luau.exe tests/RunTests.lua
```

Estado actual: **160 pruebas, 0 fallos** (11 suites).

Las pruebas cubren solo la logica pura compartida. Lo que depende del
motor (Workspace, Players, fisica, DataStore) se verifica
manualmente en Studio y se marca `BLOCKED` hasta entonces; nunca se
declara PASS sin haberlo comprobado.

## Tecnologia

- Roblox
- Luau
- Rojo 7.x
- VS Code
- Git

## Desarrollo

La fuente de verdad del codigo es este repositorio.

Flujo:

```text
VS Code
   ↓
Archivos Luau
   ↓
Rojo
   ↓
Roblox Studio
   ↓
Play/Test
```

Roblox Studio **NO** debe convertirse en la fuente principal del codigo.
Los cambios permanentes se hacen en los archivos del repositorio y se
sincronizan con Rojo. Studio se usa para ejecutar, probar, visualizar
y construir los elementos que realmente deban existir alli.

## Estructura

```text
KeshusyTomy-LanD/
├── src/                        # Arbol de Roblox sincronizado por Rojo
│   ├── ServerScriptService/
│   │   ├── ServerMain.server.lua   # Punto de entrada del servidor
│   │   ├── Services/               # Servicios, uno por dominio
│   │   └── Systems/                # Sistemas compartidos entre servicios
│   ├── ReplicatedStorage/
│   │   ├── Shared/
│   │   │   ├── Config/             # GameConfig (valores de balance)
│   │   │   ├── Constants/         # Estados y enumerados
│   │   │   ├── Types/              # Tipos Luau (solo tipado)
│   │   │   ├── Utils/              # Logger y utilidades
│   │   │   └── Libraries/          # Modulos internos de proposito general
│   │   ├── Remotes.model.json          # 8 RemoteEvent (canales no confiables)
│   │   └── WorldDefinitions/       # Datos de Forest, Desert, Ice, Volcano, Cyber
│   ├── StarterPlayer/
│   │   └── StarterPlayerScripts/
│   │       ├── ClientMain.client.lua   # Punto de entrada del cliente
│   │       ├── Controllers/            # Un controller = una responsabilidad
│   │       └── Mobile/                 # Codigo tactil / tablet
│   ├── StarterGui/
│   │   └── UI/                     # GUI generadas por Rojo
│   └── Workspace/
│       ├── Lobby/                  # Espera, menu, teletransportes
│       ├── Worlds/                 # Forest, Desert, Ice, Volcano, Cyber
│       ├── SpawnLocations/         # Puntos de aparicion
│       └── Environment/            # Luz, cielo, notas, decoracion
├── assets/                       # Recursos no codificados
├── tests/                        # Suite de pruebas (server, client, shared)
├── tools/                        # Scripts de soporte (sin logica de juego)
├── docs/                         # Documentacion tecnica
├── default.project.json          # Configuracion de Rojo
├── project.config.json           # Metadatos del proyecto
└── .gitignore
```

## Rojo

### Requisitos

Rojo **7.x**. En esta maquina hay un binario local en `rojo/`; si el
comando `rojo` no esta en el PATH, se puede usar directamente:

```text
.\rojo\rojo.exe --version
```

El binario es una herramienta de desarrollo: esta excluido de Git y el
juego nunca depende de el en tiempo de ejecucion.

### Conectar Studio

Terminal 1:

```text
rojo serve
```

En Roblox Studio:

```text
Plugin > Rojo > Connect
```

A partir de ese momento:

```text
VS Code → guardar archivo → Rojo → Roblox Studio
```

Los cambios se reflejan en Studio sin copiar scripts a mano.

Si `rojo` no esta disponible, no se instala nada automaticamente:
descargalo desde la fuente oficial, descomprimelo en una carpeta de
herramientas y anadela al PATH, o usa el binario local `rojo\rojo.exe`.

## Seguridad

El cliente **nunca** es autoridad. Todo lo siguiente se decide en servidor:
XP, monedas, gemas, dano, kills, recompensas, inventario, compras, niveles,
desbloqueos, quests y resultados.

Los `RemoteEvent` son canales de comunicacion y entradas **no confiables**:
se sanean, se limitan en frecuencia y se validan en el servidor.

Se declaran en `src/ReplicatedStorage/Remotes.model.json` (formato JSON
Model de Rojo 7, no un `remotes.json`). Para anadir un canal nuevo se
agrega una entrada `{ "Name": "...", "ClassName": "RemoteEvent" }` a ese
archivo y su nombre a `GameConstants.RemoteAction`; el codigo cliente y
servidor lo resuelven siempre desde ahi.

## Rendimiento

El diseno contempla PC, mobile, tablet y gamepad. Se evita `Heartbeat`
innecesario, loops sin condicion de salida, conexiones sin cleanup,
creacion masiva de `Instance` y spam de remotes. La arquitectura admite
pooling y throttling en fases posteriores.

## Roadmap

Primera meta funcional (Vertical Slice):

```text
LOBBY → FOREST → PLAYER → MOVEMENT → BOMB → EXPLOSION → DESTRUCTIBLE BLOCK
→ MONSTER → DAMAGE → PVP → DEATH → XP → REWARD → RESULTS → LOBBY
```

El plan completo de fases vive en `docs/phases.md`.

## Estado del proyecto

| Fase | Nombre    | Estado |
| ---- | --------- | ------ |
| 0    | Bootstrap | PASS   |
| 1    | Foundation | PASS*  |

`*` PASS sobre logica pura, build de Rojo y sintaxis. La verificacion
en Roblox Studio sigue `BLOCKED` hasta que se ejecute manualmente; los
detalles estan en `docs/phase-01-foundation.md`.

Solo se marca PASS una fase cuando fue implementada, integrada, probada,
corregida, documentada y confirmada con commit.
