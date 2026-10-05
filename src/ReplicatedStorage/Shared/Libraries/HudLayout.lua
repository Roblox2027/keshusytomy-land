--!strict
--[[
HudLayout
ARQUITECTURA VISUAL del HUD: zonas, safe area y escala.

POR QUE ESTE MODULO EXISTE
--------------------------
El HUD era una lista de paneles hermanos con `Position` en pixeles, y la
bomba vivia en OTRO `ScreenGui` (`TouchControls`). Para que no se solaparan
habia que calcular la posicion de la columna derecha APARTANDO la zona de
la bomba, y esa cuenta vivia en dos ficheros que ya habian divergido.
Un `UDim2` con offsets solo acierta en la resolucion para la que se
escribio.

AQUI NO HAY POSICIONES
----------------------
Este modulo NO decide donde se coloca nada: el GENERADOR declara anclas y
listas, y el motor resuelve. Lo que decide es lo que el motor no puede
saber por si solo:

  1. `Zones`: que rectangulo ocupa cada zona en cada viewport. Sirve para
     CERTIFICAR que nada se solapa y que el centro queda libre.
  2. `ScaleFor` / `FitScale`: el factor de `UIScale` con el que el
     contenido de cada zona cabe dentro de ella.
  3. `ReferenceResolutions`: las resoluciones que exige el diseno.

Es logica PURA (no toca servicios de Roblox), asi que se prueba en local
con `luau.exe`. Las coordenadas son de pantalla, ya descontado el inset
superior: es el espacio en el que mide `AbsolutePosition`.
]]

local Layout = {}

--- Resoluciones de referencia. El enunciado exige que el diseno funcione en
--- estas, asi que estan DECLARADAS: una prueba que las recorre es la que
--- certifica el responsive.
Layout.ReferenceResolutions = {
{ width = 375, height = 667, label = "movil pequeno" },
{ width = 390, height = 844, label = "movil moderno" },
{ width = 430, height = 932, label = "movil grande" },
{ width = 768, height = 1024, label = "tablet" },
{ width = 1024, height = 768, label = "escritorio pequeno" },
{ width = 1280, height = 720, label = "escritorio" },
{ width = 1440, height = 900, label = "escritorio grande" },
}

--- Separacion entre el borde de la pantalla y el HUD.
---
--- Proporcional al ancho con topes: en movil 12 px es lo que separa el panel
--- del gesto de borde, y en escritorio un margen de 12 se lee como un error
--- de pegado.
--- @param width number ancho de pantalla
--- @return number margen en pixeles
function Layout.MarginFor(width: number): number
return math.clamp(width * 0.03, 12, 24)
end

--- Separacion entre zonas contiguas.
Layout.Gap = 10

--- Alturas de las zonas fijas, en pixeles de DISENO (el `UIScale` las lleva
--- al tamano real de cada pantalla).
Layout.Metrics = {
TopBar = 56,
	BandGap = 10,
	BandTop = 10,
LeftPanel = 96,
RightPanel = 108,
BombAction = 152,
BottomLeft = 96,
Notifications = 168,
Timer = 46,
BossBar = 42,
}

--- Ancho maximo de los paneles laterales. Un panel de 280 px en una pantalla
--- de 375 se come tres cuartas partes del ancho y empuja al resto.
--- @param width number ancho de pantalla
--- @return number ancho maximo
function Layout.SideWidthFor(width: number): number
	-- La cuenta reserva una BANDA CENTRAL MINIMA ademas del tope de ancho: sin
	-- ella, dos paneles de 165 px en una pantalla de 375 se tocan en el centro
	-- y el hueco de gameplay desaparece. Un "el centro esta libre" que se
	-- cumple porque no hay centro es un falso PASS.
	local m = Layout.MarginFor(width)
	local usable = width - m * 2
	local centerMin = math.max(usable * 0.34, 120)
return math.max(math.min(width * 0.44, 260, (width - m * 2 - math.max((width - m * 2) * 0.34, 120) - Layout.Gap * 2) / 2), 80)
end

--- Por debajo de este ancho, las acciones de contexto NO caben AL LADO de la
--- bomba: se apilan ENCIMA de ella.
---
--- Es una regla de composicion, no un parche: en vertical estrecho el espacio
--- horizontal no da para dos columnas, y forzar la de al lado empuja la bomba
--- contra el borde o la monta.
--- @param width number ancho de pantalla
--- @return boolean apilado
function Layout.IsCompact(width: number): boolean
return width < 560
end

--- Rectangulo de una zona, en coordenadas de pantalla.
--- @param x number
--- @param y number
--- @param w number
--- @param h number
--- @return { x: number, y: number, width: number, height: number }
local function rect(x: number, y: number, w: number, h: number)
return { x = x, y = y, width = w, height = h }
end
--- Calcula TODAS las zonas del HUD para un viewport concreto.
---
--- Los nombres coinciden con los contenedores que declara `tools/hud.js`:
--- esta es la cuenta que certifica que el arbol y esta tabla describen la
--- MISMA disposicion.
--- @param width number ancho de pantalla
--- @param height number alto de pantalla
--- @param insetBottom number alto del inset inferior (gesto de movil)
--- @return { [string]: { x: number, y: number, width: number, height: number } }
function Layout.Zones(width: number, height: number, insetBottom: number): { [string]: any }
local m = Layout.MarginFor(width)
local gap = Layout.Gap
local metrics = Layout.Metrics
local safeHeight = height - insetBottom
local side = Layout.SideWidthFor(width)
local usable = width - m * 2

local topBar = rect(m, m, usable, metrics.TopBar)
-- `top` es el pie de la BANDA SUPERIOR COMPLETA: barra de identidad,
-- temporizador y las dos separaciones. Los paneles laterales empiezan
-- DESPUES de la banda entera, no despues de la barra: con el temporal en
-- medio, arrancarlos en `topBar.y + gap` los montaba sobre el.
--
-- Es la MISMA cuenta que hace `TOP_BAND_H` en `tools/hud.js`. Si divergieran,
-- estas pruebas medirian una disposicion que el juego no tiene.
local top = topBar.y + metrics.TopBar + metrics.BandGap + metrics.Timer + metrics.BandGap

local leftPanel = rect(m, top, side, metrics.LeftPanel)
local rightPanel = rect(width - m - side, top, side, metrics.RightPanel)

-- La bomba es la ACCION PRIMARIA: vive abajo a la CENTRO, y su zona se
-- calcula desde el borde inferior, no desde los paneles.
--
-- `min(usable, ...)` porque en una pantalla mas estrecha que la zona la
-- bomba se Sale: una accion primaria fuera de la pantalla es lo peor que
-- puede pasarle al diseno.
local bombWidth = math.min(metrics.BombAction, usable)
local bombAction = rect(
(width - bombWidth) / 2,
safeHeight - m - metrics.BombAction,
bombWidth,
metrics.BombAction
)

-- Acciones de contexto: al LADO de la bomba en ancho, ENCIMA en vertical.
local bottomLeft

if Layout.IsCompact(width) then
bottomLeft = rect(m, bombAction.y - gap - metrics.BottomLeft, usable, metrics.BottomLeft)
else
-- En horizontal el hueco hasta la bomba es el que hay: si no cabe, se
-- estrecha en vez de montarse encima.
local contextWidth = math.min(width * 0.3, 300, bombAction.x - m - gap)

bottomLeft = rect(m, bombAction.y, math.max(contextWidth, 1), metrics.BottomLeft)
end

-- Avisos temporales: centrados, en el tercio superior. El CENTRO del
-- gameplay queda libre; aqui solo hay overlays que aparecen y se van.
local noticeWidth = math.min(width * 0.82, 440, usable)
local notifications = rect(
(width - noticeWidth) / 2,
height * 0.24,
noticeWidth,
metrics.Notifications
)

local timerWidth = math.min(180, usable)
local timer = rect((width - timerWidth) / 2, topBar.y + metrics.TopBar + metrics.BandGap, timerWidth, metrics.Timer)

local bossWidth = math.min(440, usable)
local bossBar = rect(
(width - bossWidth) / 2,
timer.y + timer.height + gap * 0.5,
bossWidth,
metrics.BossBar
)

-- BANDA DE GAMEPLAY.
--
-- No es un porcentaje magico: es el hueco REAL que queda entre lo de
-- arriba y lo de abajo. Si se calculara como "el 40% central", en un
-- movil estrecho la banda invadiria el panel de misiones y la prueba de
-- "el centro esta libre" daria un falso PASS.
local centerTop = topBar.y + topBar.height + gap
local centerBottom = math.min(leftPanel.y + leftPanel.height, bottomLeft.y) - gap
local centerLeft = leftPanel.x + leftPanel.width + gap
-- El limite derecho es el del panel DERECHO y no el de la bomba: la bomba
	-- esta ABAJO y los paneles laterales ARRIBA, asi que en la banda central
	-- no se cruzan. Limitarlo por la bomba daba una banda de ancho CERO en
	-- movil, que es justo el falso PASS que esta comprobacion debe evitar.
	local centerRight = rightPanel.x - gap

local center = rect(
math.max(centerLeft, 0),
math.max(centerTop, 0),
math.max(centerRight - centerLeft, 0),
math.max(centerBottom - centerTop, 0)
)

return {
TopBar = topBar,
LeftPanel = leftPanel,
RightPanel = rightPanel,
BottomCenter = bombAction,
BottomLeft = bottomLeft,
Notifications = notifications,
Timer = timer,
BossBar = bossBar,
Center = center,
}
end

--- Zonas PERMANENTES: las que no pueden cambiar ni tapar el gameplay.
Layout.PersistentZones = {
"TopBar",
"LeftPanel",
"RightPanel",
"BottomCenter",
"BottomLeft",
}
--- Indica si dos rectangulos se solapan.
--- Se declara aqui y no se importa porque es la UNICA comprobacion de
--- geometria que necesitan las pruebas y la certificacion, y las dos tienen
--- que decir exactamente lo mismo.
--- @param a any { x, y, width, height }
--- @param b any { x, y, width, height }
--- @return boolean
function Layout.Overlaps(a: any, b: any): boolean
if not a or not b then
return false
end

return a.x < b.x + b.width
and b.x < a.x + a.width
and a.y < b.y + b.height
and b.y < a.y + a.height
end

--- El rectangulo cabe DENTRO del contenedor.
--- @param inner any rectangulo del contenido
--- @param outer any rectangulo de la zona
--- @return boolean
function Layout.Fits(inner: any, outer: any): boolean
return inner.x >= outer.x
and inner.y >= outer.y
and inner.x + inner.width <= outer.x + outer.width
and inner.y + inner.height <= outer.y + outer.height
end

--- Factor de `UIScale` GLOBAL del HUD.
---
--- Un unico factor para todo el HUD es lo que conserva la JERARQUIA entre
--- resoluciones: si cada panel escalara por su cuenta, dos paneles que en
--- escritorio se tocaban podrian separarse o montarse en movil.
--- @param width number
--- @param height number
--- @return number escala
function Layout.ScaleFor(width: number, height: number): number
return math.clamp(math.min(width / 1280, height / 720), 0.62, 1.35)
end

--- Factor de `UIScale` para que un contenido de tamano de DISENO quepa en su
--- zona sin tocarla.
---
--- Es `min` y no `max`: si el contenido no cabe, se achica; si sobra sitio, se
--- deja en 1 para que el texto no crezca hasta comerse la pantalla.
--- @param zoneWidth number ancho real de la zona
--- @param zoneHeight number alto real de la zona
--- @param contentWidth number ancho de diseno del contenido
--- @param contentHeight number alto de diseno del contenido
--- @param maxScale number? tope
--- @return number escala
function Layout.FitScale(
zoneWidth: number,
zoneHeight: number,
contentWidth: number,
contentHeight: number,
maxScale: number?
): number
if zoneWidth <= 0 or zoneHeight <= 0 or contentWidth <= 0 or contentHeight <= 0 then
return 1
end

local scale = math.min(zoneWidth / contentWidth, zoneHeight / contentHeight)

return math.clamp(scale, 0.5, maxScale or 1)
end

return Layout