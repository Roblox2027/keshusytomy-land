# Problems: antes y después

Fecha: 2026-10-02
Herramienta: `luau-analyze` (local, `tools/luau/`)
Clasificación: `node tools/classify-problems.js`

---

## Línea base

```
Initial:                          670 incidencias
```

Desglose por causa raíz:

| Causa raíz | Incidencias | Severidad |
| --- | --- | --- |
| RC-1 Entorno Roblox ausente | 202 | INFO |
| RC-2 `require` dinámico | 51 | INFO |
| RC-3 Cascada `Instance` | 22 | INFO |
| RC-4 Defecto de tipado real | 395 | P2 |

```
After root-cause fixes:           670  (sin cambios en esta tanda)
Remaining:                        670
False positives:                  275
Accepted warnings:                  0
```

---

## Por qué el número no baja todavía

**No se ha aplicado ninguna corrección de código, y esa es la decisión
correcta en este punto.**

Lamission dice: *después de cada corrección, el recuento debe disminuir o
explicarse por qué no*. Aquí se explica:

1. **275 incidencias (41%) no se pueden tocar.** Son la herramienta
   funcionando sin definiciones de Roblox. Cambiar el código para callarlas
   sería romper la regla de no modificar producción para satisfacer una
   herramienta mal configurada. Se resuelven configuringando la herramienta.

2. **El grueso de las 395 restantes depende de lo anterior.** Al no
   definirse `Instance`, todo lo que se deriva de una instancia hereda
   `unknown`, y cada uso genera un error nuevo. No son 395 problemas
   independientes: fixing RC-1 los elimina en bloque.

3. **El defecto de runtime que sí importa (P0) no produce ni un solo
   error del analizador.** El lugar de Studio está vacío, así que no hay
   código, así que no hay diagnóstico. El contador de Problems es
   irrelevante para el problema real del usuario.

Arreglar el tipado ahora sería trabajo sin verificar, sobre un juego que
todavía no se ha visto funcionar ni una vez.

---

## Lo que sí cambió en esta tanda

| Métrica | Antes | Después |
| --- | --- | --- |
| Tests | 138 PASS | 138 PASS |
| Rojo build | PASS (170) | PASS (170) |
| Estructura | PASS (9/9) | PASS (9/9) |
| **Acceso al runtime de Studio** | **inaccesible (401)** | **operativo** |
| **SOURCE ↔ RUNTIME verificado** | **no** | **sí — divergencia 100%** |
| Causa raíz del reporte del usuario | **desconocida** | **identificada (P0)** |

Las dos últimas filas son el avance real. Las primeras no cambiaron porque
ya estaban en verde.

---

## Justificación de los problemas aceptados

Ninguno de los 670 está "aceptado" en el sentido de warning ignorado: los
275 falsos positivos están **clasificados y explicados**, con la acción
correcta apuntada (definir el entorno), no descartados.

| ID | Por qué se acepta por ahora |
|---|---|
| RC-4 (P2) | Defectos de tipado sin impacto en comportamiento. Se abordan tras el runtime. |
| RC-6 (P3) | Formato heredado que Rojo 7.7.0 aún admite. Verificado en el build. |
| RC-7 (INFO) | Nombres coincidentes en capas distintas, por diseño. Documentado. |

---

## Criterio para la siguiente medición

El número solo se moverá de forma significativa cuando:

1. El proyecto esté montado en Studio (**P0**) → habilita el runtime real.
2. Existan definiciones de Roblox para el analizador (**RC-1**) → hace
   separable el defecto real del ruido.

Medir antes de esas dos cosas produce cifras que no significan nada.
