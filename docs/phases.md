# Fases de desarrollo

Regla fundamental: **no se pasa a la siguiente fase si la actual no funciona.**

Cada fase debe: implementarse, integrarse, probarse, corregirse, volverse a
probar, documentarse y recibir commit. Estados validos: `PASS`, `FAIL`, `BLOCKED`.
Nunca "casi terminado", "deberia funcionar" ni "probablemente funciona".

| Fase | Nombre          | Depende de |
| ---- | --------------- | ---------- |
| 0    | Bootstrap       | -          |
| 1    | Foundation      | 0          |
| 2    | Player          | 1          |
| 3    | Input           | 2          |
| 4    | Bomb            | 3          |
| 5    | Explosion       | 4          |
| 6    | Destruction     | 5          |
| 7    | Round           | 2          |
| 8    | PvP             | 7          |
| 9    | Monsters        | 7          |
| 10   | AI              | 9          |
| 11   | Boss            | 10         |
| 12   | XP              | 7          |
| 13   | Economy         | 12         |
| 14   | Inventory       | 2          |
| 15   | DataStore       | 2          |
| 16   | Worlds          | 7          |
| 17   | Lobby           | 16         |
| 18   | Portals         | 16         |
| 19   | Matchmaking     | 7          |
| 20   | Party           | 19         |
| 21   | UI              | 2          |
| 22   | Mobile          | 21         |
| 23   | Gamepad         | 3          |
| 24   | Audio           | 21         |
| 25   | VFX             | 21         |
| 26   | Shop            | 13, 14     |
| 27   | Monetization    | 26         |
| 28   | Quests          | 14         |
| 29   | Battle Pass     | 13, 21     |
| 30   | Achievements    | 12         |
| 31   | Codes           | 13         |
| 32   | Badges          | 30         |
| 33   | Moderation      | 15         |
| 34   | Anti-Exploit    | 2          |
| 35   | Analytics       | 15         |
| 36   | Live Ops        | 26         |
| 37   | Performance     | 25         |
| 38   | QA              | 37         |
| 39   | Beta            | 38         |
| 40   | Release         | 39         |

## Formato de reporte de fase

```text
PHASE:
STATUS:            # PASS | FAIL | BLOCKED
FILES CREATED:
FILES MODIFIED:
FUNCTIONALITY:
TESTS:
BUGS:
RESULT:
NEXT PHASE:
```

`LAUNCH_READY = TRUE` solo cuando exista evidencia de que el juego
funciona realmente en Roblox Studio y supero las pruebas correspondientes.
