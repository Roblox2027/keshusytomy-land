fix(sync): la colocacion del mapa no escribia NINGUNA propiedad de apariencia

La reconstruccion del bosque ya estaba commiteada en 320cd08. Este bloque
NO reconstruye el mapa: lo reconcilia, porque el informe previo no se puede
dar por cierto y habia que volver a medir antes de tocar nada.

LO QUE ESTABA MAL. apply-map-positions.js colocaba Position, Size y
Orientation, y NADA mas: no escribia Color, Material, Transparency ni
CanCollide. Solo no seria un fallo si Rojo aplicase el resto al importar,
pero import_rbxm no actualiza las instancias que ya existen (defecto 1), de
modo que ninguna propiedad de apariencia llegaba nunca a Studio. Sobre una
sesion de Play limpia se midieron 50 posiciones, 49 tamanos, 62 colores y
49 materiales fuera de sitio. Ninguna comprobacion existente lo veia: todas
comparaban recuento y nombre de instancias, que es justo lo que coincide.

LO QUE PARECIA UN FALLO Y NO LO ERA. Cuatro portales llegaban con el panel
en gris 70/74/86 en vez del color de su mundo. No estaba roto:
VisualService.lua:442 lo pone a proposito, porque gris y sin chispas es la
senal de "aqui no se entra". Al arreglar lo anterior, apply empezo a
repintarlos y VisualService los volvio a poner gris, y el verificador dio
FAIL sobre un runtime correcto. La propiedad queda declarada: los paths de
RUNTIME_OWNED_APPEARANCE no reciben apariencia desde la fuente, y su
geometria se sigue aplicando. Dos duenos de la misma propiedad no pueden
escribirla sin declararlo.

TAMBIEN SE CORRIGE LA PUERTA DEL CLIENTE, que exigia ver Partes del Lobby
siempre y daba FAIL siendo el juego correcto: el ciclo de ronda lleva al
jugador a la Arena, a 500 studs, asi que alli el Lobby no tiene por que
verse. Ahora mide la zona en la que esta, y ademas exige que la zona se haya
podido determinar. lobby-teleport-check.js demuestra que el teleport al
Lobby funciona y que lo revierte la ronda, como estaba previsto.

DOCUMENTADOS LOS ERRORES PROPIOS, porque el estado final no los explica:
una tolerancia de 1/255 en el color hacia el script no idempotente (Roblox
guarda Color en coma flotante de 32 bits y 70/255 se relee como 69), el
bloque de apariencia quedo dentro de la contabilidad de ejemplos y no se
ejecutaba, e IsVisibleFrom en el cliente agota el puente MCP. Tambien la
carrera entre play.js restart y la carga del servidor: aplicada demasiado
pronto, la colocacion informa alreadyCorrect sobre un mapa roto, que es el
peor resultado posible porque desaparece el sintoma sin arreglar nada.

Verificacion (Play, servidor vivo): verify-geometry, portal-source-audit,
destroy-restore-check, combat-verify, portal-verify, forest-verify,
forest-build-check, spawn-check, source-runtime-diff y client-probe dan
PASS. capture_screenshot sigue dando request_timeout tras varios intentos
en jpeg y png y en mas de una sesion: la comprobacion es estructural y no
se presenta como visual.

NO PUSH.