--!strict
--[[
HudLayout.spec
PRUEBAS DE LA ARQUITECTURA VISUAL DEL HUD.

QUE COMPRUEBAN Y POR QUE NO ES "ESTA DENTRO DE LA PANTALLA"
----------------------------------------------------------
"Que se ve bien" no es una asercion. Lo que si se puede comprobar, y es
justo lo que estaba roto, son las propiedades que el diseno promete:

  1. NINGUN par de zonas permanentes se solapa.
  2. El CENTRO de la pantalla queda libre (ahi esta el gameplay).
  3. Todo cabe DENTRO de la pantalla, con margen.
  4. La BOMBA no se monta con nada ni se sale de la pantalla.

Y todo eso se recorre en las SIETE resoluciones que declara
`Layout.ReferenceResolutions`, no en la del autor. Un responsive que solo
se ha visto en 1280x720 no es responsive.

La tabla que se recorre es la MISMA que aplica `UIController` al arrancar:
si el arbol del generador y esta tabla divergieran, estas pruebas estarian
midiendo otra cosa. Esa es la razon de que la cuenta viva en un modulo.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Layout = require("../../src/ReplicatedStorage/Shared/Libraries/HudLayout")

--- Todas las zonas que el generador declara bajo `Root`.
local ZONE_NAMES = {
"TopBar",
"LeftPanel",
"RightPanel",
"BottomCenter",
"BottomLeft",
"Notifications",
"Timer",
"BossBar",
}

--- Devuelve el nombre del choque entre dos zonas, o `nil` si no se tocan.
--- @param zones table
--- @param a string
--- @param b string
--- @return string? choque
local function firstOverlap(zones: any, a: string, b: string): string?
if Layout.Overlaps(zones[a], zones[b]) then
return ("%s <-> %s"):format(a, b)
end

return nil
end

local function describeHudLayout()
Harness.describe("HudLayout: las zonas permanentes NO se solapan", function()
Harness.it("ningun par de zonas permanentes se pisa", function()
for _, res in ipairs(Layout.ReferenceResolutions) do
local zones = Layout.Zones(res.width, res.height, 0)

for _, a in ipairs(Layout.PersistentZones) do
for _, b in ipairs(Layout.PersistentZones) do
if a < b then
expect.toBeFalsy(
firstOverlap(zones, a, b),
("%s (%dx%d): %s"):format(res.label, res.width, res.height, a .. " <-> " .. b)
)
end
end
end
end
end)

Harness.it("la BOMBA no se monta con nada", function()
-- La asercion CENTRAL del enunciado: la accion primaria no puede
-- quedar escondida ni tapada. Con las zonas separadas por
-- construccion, esto no depende de un margen bien elegido.
for _, res in ipairs(Layout.ReferenceResolutions) do
local zones = Layout.Zones(res.width, res.height, 0)

for _, other in ipairs({ "BottomLeft", "LeftPanel", "RightPanel", "TopBar" }) do
expect.toBeFalsy(
firstOverlap(zones, "BottomCenter", other),
("bomba vs %s en %s"):format(other, res.label)
)
end
end
end)

        Harness.it("el CENTRO de la pantalla queda libre de paneles", function()
            for _, res in ipairs(Layout.ReferenceResolutions) do
                local zones = Layout.Zones(res.width, res.height, 0)
                local center = zones.Center

                for _, name in ipairs(Layout.PersistentZones) do
                    expect.toBeFalsy(
                        Layout.Overlaps(zones[name], center),
                        ("%s invade el centro en %s"):format(name, res.label)
                    )
                end

                -- La banda de gameplay tiene que EXISTIR: una banda de ancho
                -- o alto CERO es un centro tapado igual, y "nadie invade el
                -- centro" pasaria sin decir nada.
                expect.toBe(center.width > 0, true)
                expect.toBe(center.height > 0, true)
            end
        end)

Harness.it("el temporizador va DEBAJO de la barra, no encima", function()
-- La banda superior la comparten la barra de identidad y el
-- temporizador. Anclados los dos a `y = 0` se montaban: medido en
-- PLAY, "RONDA 0 / 00:00" caia sobre el nombre del mundo. Esta
-- asercion ata la tabla con la cuenta que hace `tools/hud.js`.
for _, res in ipairs(Layout.ReferenceResolutions) do
local zones = Layout.Zones(res.width, res.height, 0)
expect.toBeFalsy(
Layout.Overlaps(zones.Timer, zones.TopBar),
("el temporizador pisa la barra en %s"):format(res.label)
)
expect.toBe(
zones.LeftPanel.y >= zones.Timer.y + zones.Timer.height,
true
)
end
end)
Harness.it("toda zona cabe DENTRO de la pantalla", function()
for _, res in ipairs(Layout.ReferenceResolutions) do
local zones = Layout.Zones(res.width, res.height, 0)
local screen = { x = 0, y = 0, width = res.width, height = res.height }

for _, name in ipairs(ZONE_NAMES) do
expect.toBe(Layout.Fits(zones[name], screen), true)
end
end
end)

Harness.it("el inset inferior SUBE el HUD, no lo deja bajo el gesto", function()
for _, res in ipairs(Layout.ReferenceResolutions) do
local sinInset = Layout.Zones(res.width, res.height, 0)
local conInset = Layout.Zones(res.width, res.height, 34)

expect.toBe(conInset.BottomCenter.y < sinInset.BottomCenter.y, true)
expect.toBe(
conInset.BottomCenter.y + conInset.BottomCenter.height,
res.height - 34 - Layout.MarginFor(res.width)
)
end
end)

Harness.it("en vertical estrecho las acciones de contexto se apilan", function()
-- Regla de composicion, no de coordenadas: por debajo de 560 px de
-- ancho no caben dos columnas abajo, y forzar la de al lado
-- empujaria la bomba contra el borde.
local compacto = Layout.Zones(390, 844, 0)
local ancho = Layout.Zones(1280, 720, 0)

expect.toBeFalsy(Layout.Overlaps(compacto.BottomLeft, compacto.BottomCenter))
expect.toBeFalsy(Layout.Overlaps(ancho.BottomLeft, ancho.BottomCenter))
expect.toBe(Layout.IsCompact(390), true)
expect.toBe(Layout.IsCompact(1280), false)
end)
end)
Harness.describe("HudLayout: la escala responsive tiene limites", function()
Harness.it("la escala global nunca sale del rango declarado", function()
for _, res in ipairs(Layout.ReferenceResolutions) do
local scale = Layout.ScaleFor(res.width, res.height)

expect.toBe(scale >= 0.62, true)
expect.toBe(scale <= 1.35, true)
end
end)

Harness.it("una pantalla mas grande NUNCA da una escala menor", function()
-- Si crecer la pantalla encogiera el HUD, el responsive estaria
-- invertido y el HUD se encogeria justo cuando hay mas sitio.
local pequeno = Layout.ScaleFor(375, 667)
local mediano = Layout.ScaleFor(768, 1024)
local grande = Layout.ScaleFor(1280, 720)
local enorme = Layout.ScaleFor(1440, 900)

expect.toBe(pequeno <= mediano, true)
expect.toBe(mediano <= grande, true)
expect.toBe(grande <= enorme, true)
end)

Harness.it("FitScale achica lo que no cabe y respeta el tope", function()
-- Zona de 100x100 con contenido de diseno de 200x200: la mitad.
expect.toBeClose(Layout.FitScale(100, 100, 200, 200), 0.5, 0.001)
-- Zona enorme: el tope manda, el texto no se infla.
expect.toBe(Layout.FitScale(4000, 4000, 200, 200, 1), 1)
-- Zona de tamano cero (aun sin medir): no revienta.
expect.toBe(Layout.FitScale(0, 0, 200, 200), 1)
end)

Harness.it("el margen crece con la pantalla pero no se dispara", function()
expect.toBe(Layout.MarginFor(320), 12)
expect.toBe(Layout.MarginFor(1280) > Layout.MarginFor(390), true)
expect.toBe(Layout.MarginFor(4000) <= 24, true)
end)
end)
end

return describeHudLayout
