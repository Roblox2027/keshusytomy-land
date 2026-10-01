# assets

Recursos no codificados del juego.

| Carpeta      | Contenido                                    |
| ------------ | -------------------------------------------- |
| characters   | Modelos de personajes jugables y NPCs         |
| monsters     | Modelos de monstruos y bosses                 |
| bombs        | Modelos y efectos de bombas                   |
| explosions   | Modelos y efectos de explosion                |
| maps         | Mapas (.rbxl exportados) de cada mundo        |
| sounds       | Efectos de sonido cortos                      |
| music        | Musica de lobby y de cada mundo              |
| ui           | Iconos, imagenes y fuentes de la interfaz     |

Reglas:

- Los assets binarios se versionan en Git solo si son pequenos.
- Los mapas pesados se guardan en Git LFS o en el servicio de assets
  de Roblox, nunca dentro de `src/`.
- Ningun asset puede contener scripts: los scripts viven en `src/`.
