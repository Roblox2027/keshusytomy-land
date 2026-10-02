# Verificacion en runtime

Herramientas que comprueban el juego CONTRA el servidor de Roblox Studio, no
contra el codigo del repositorio.

Que un servicio exista, cargue sin error y tenga `IsInitialized = true` NO
demuestra que funcione. Estas herramientas existen porque esa distincion
resulto decisiva: durante este trabajo se encontraron fallos que pasaban
todos los chequeos de source y solo se manifestaban en ejecucion.

## Como usarlas

```text
node tools/sync-all.js        # source == runtime (incluye colocar el mapa)
node tools/play.js restart    # arranca Play con cliente
```

A partir de ahi, todas se ejecutan contra el servidor vivo y salen con codigo
1 si fallan, de modo que sirven como puerta:

| Herramienta | Que mide |
| --- | --- |
| `runtime-tree.js` | Los paths que el contrato exige en el DataModel |
| `boot-state.js` | Que cargan los 31 servicios y hay jugador vivo |
| `verify-geometry.js` | Que cada Part esta donde el mapa dice, no solo que exista |
| `portal-verify.js` | Portales registrados y rechazo de peticiones malformadas |
| `combat-verify.js` | Reglas de dano, destruccion de bloques y reparacion |
| `source-map-audit.js` | Mapa declarado frente al mapa de Studio |
| `source-runtime-diff.js` | Recuento de instancias source frente a runtime |

## Limitaciones del entorno

Estan documentadas porque afectan a lo que se puede y no se puede verificar,
y preferimos declararlas a dejar que parezcan defectos del juego.

### `get_script_source` trunca a 300 lineas

Seis de los 63 scripts superan ese limite. La lectura llega con
`truncated: true`, asi que el FINAL de esos archivos no puede comprobarse por
MCP. `sync-scripts.js` lo informa en vez de dar la escritura por buena, y
reescribe siempre los archivos cuya lectura vino truncada.

### `Instance:AddChild()` esta bloqueado en el puente

Falla con `AddChild is not a valid member of Folder`. Se descarto que fuera un
defecto del juego:

- el receptor es una Instance valida (`Bomb._bombFolder` es el mismo Folder
  que `Workspace.Bombs`);
- `x.Parent = folder` SI funciona sobre ese mismo Folder;
- asignar `folder.AddChild = ...` falla con el mismo error.

Es una limitacion del contexto de ejecucion del puente. La consecuencia
practica es que **no se pueden colocar bombas desde una prueba de MCP**:
`combat-verify.js` mide la cadena de reglas (estado de ronda, alcance,
dano, destruccion y reparacion) sin crear instancias, y no afirma nada sobre
el camino de creacion de la bomba.

### Rojo no tiene proyecto adjunto

`http://localhost:34872/api/active-project` responde, pero no hay sesion. El
arbol llega a Studio por la cadena `sync-all.js`, que es el equivalente
funcional: build, import, merge, dedupe, colocacion de geometria y scripts.

`Plugin > Rojo > Connect` sigue siendo el camino previsto y no se puede
ejecutar desde MCP.
