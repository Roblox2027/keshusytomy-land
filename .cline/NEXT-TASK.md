# NEXT TASK

Estado real observado:
- Los 5 mundos estan reconstruidos y verificados: 96/96 zonas alcanzables, contenido de rol real (miniboss, secreto, encuentro, arena, boss, salida).
- SecretService, pathfinding de monstruos, mixer de audio y sliders estan integrados y cableados.
- La cadena `npm run verify` completa sale con exit 0.
- Se ejecuto Play Test real en Studio sobre `latest.rbxlx` (instancia `lrh-zvl`): rondas, spawns de monstruos, minibosses, portales y bombas confirmados en logs en vivo.

Siguientes pasos reales:
1. Subir assets de audio reales al Creator Dashboard y pegar los IDs en `AudioConfig` para activar musica/ambiente/SFX.
2. Extender el Play Test visual/audio (algunas sondas de cliente hicieron timeout; el screenshot uso el fallback de CaptureService).
3. Ejecutar `tools/monster-ai-verify.js` contra una sesion de Play para confirmar persecucion->ataque de la nueva navegacion por waypoints.
4. Revisar el resto de la mision master (economia/tienda/inventario/brainrot catalogo) en la siguiente iteracion.

La fase de reconstruccion ya quedo validada y publicada.
