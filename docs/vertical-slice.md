# Vertical Slice

Primera meta funcional. No se construye ningun sistema secundario hasta
que este flujo funcione de punta a punta en Roblox Studio.

```text
LOBBY
 ↓
FOREST
 ↓
PLAYER
 ↓
MOVEMENT
 ↓
BOMB
 ↓
EXPLOSION
 ↓
DESTRUCTIBLE BLOCK
 ↓
MONSTER
 ↓
DAMAGE
 ↓
PVP
 ↓
DEATH
 ↓
XP
 ↓
REWARD
 ↓
RESULTS
 ↓
LOBBY
```

## Criterios de aceptacion

1. El jugador aparece en el lobby sin errores en consola.
2. Puede entrar a Forest desde un portal validado por el servidor
   (nivel minimo comprobado en servidor, no en cliente).
3. Se mueve con teclado, gamepad, touch y tablet.
4. Coloca una bomba: el servidor valida distancia, cooldown y estado de ronda.
5. La bomba explode en el tiempo del servidor y aplica dano por area.
6. Los bloques destructibles desaparecen solo con dano del servidor.
7. Los monstruos aparecen, se mueven y reciben dano.
8. El PvP causa muerte, y la muerte la resuelve el servidor.
9. La muerte otorga XP y recompensa solo si la calculates el servidor.
10. Se muestra la pantalla de resultados y se devuelve al lobby.

Cada paso se prueba en Studio antes de pasar al siguiente.
