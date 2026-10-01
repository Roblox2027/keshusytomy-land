# Arquitectura

## Regla de oro

```text
REPOSITORY → Rojo → Roblox Studio
```

Studio se usa para ejecutar, probar, visualizar y verificar. El codigo
permanente existe primero en el repositorio.

## Capas

```text
ServerScriptService
├── ServerMain          -> orquestacion: registro y arranque de servicios
├── Services            -> un dominio por archivo, sin dependencias entre si
└── Systems             -> logica compartida por varios servicios

StarterPlayerScripts
├── ClientMain          -> registro de controllers
└── Controllers         -> una responsabilidad por controller

ReplicatedStorage
├── Shared/Config       -> GameConfig: valores de balance
├── Shared/Constants    -> estados y enumerados
├── Shared/Types        -> contratos de datos (solo tipado)
├── Shared/Utils        -> Logger y utilidades
├── Shared/Libraries    -> modulos internos puros
├── Remotes.model.json  -> 8 RemoteEvent (canales no confiables)
└── WorldDefinitions   -> datos de cada mundo
```

## Reglas de diseno

1. **Un archivo, una responsabilidad.** Si un archivo hace dos cosas,
   se divide.
2. **Sin numeros magicos.** Los valores vienen de `GameConfig`.
3. **Cliente no es autoridad.** Todo `RemoteEvent` se trata como entrada
   no confiable: se valida tipo, rango, frecuencia y contexto.
4. **Sin trabajo por frame innecesario.** Se evita `Heartbeat` constante;
   la IA y los efectos usan throttling y pooling.
5. **Limpieza obligatoria.** Toda conexion, hilo o instancia creada tiene
   su `Destroy` correspondiente.
6. **Fallo aislado.** Un error en un servicio no debe tumbar el servidor:
   los servicios se inicializan con `pcall` y registran el fallo.
