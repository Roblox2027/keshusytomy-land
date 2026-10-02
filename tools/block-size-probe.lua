-- edit-vs-play-probe.lua
-- Compara la geometria de un bloque entre EDICION y PLAY.
--
-- POR QUE EXISTE
-- --------------
-- `verify-geometry.js` mide el runtime de PLAY y dice que `Block_0` mide
-- 8x8x8, cuando la sesion de EDICION lo tiene a 6x11x6 (comprobado con
-- `block-size-probe.lua`).
--
-- Edit sesion y Play sesion son arboles DISTINTOS: Play es una copia. Si
-- divergen, la copia se hizo de un estado anterior, yeso significa que
-- Play arranco antes de que se aplicara la geometria nueva.
--
-- Aqui se comprueba que Play se ve afectado por los cambios de la sesion
-- de edicion. Si no lo esta, `verify-geometry` no puede usarse hasta que
-- se arranque Play DESPUES de aplicar el mapa.
--
-- Se mide en las dos, en la misma ejecucion, y se compara.

local Workspace = game:GetService("Workspace")

local function readBlock(blockName)
	local forest = Workspace:FindFirstChild("Worlds") and Workspace.Worlds:FindFirstChild("Forest")
	if not forest then return nil end
	local blocks = forest:FindFirstChild("Blocks")
	if not blocks then return nil end
	local block = blocks:FindFirstChild(blockName)
	if not block then return nil end
	return block
end

local function describe(block)
	if not block then return "AUSENTE" end
	local s = block.Size
	local o = block.Orientation
	return string.format(
		"size=(%.1f, %.1f, %.1f) orient=(%.1f, %.1f, %.1f) hijos=%d",
		s.X, s.Y, s.Z, o.X, o.Y, o.Z, #block:GetChildren()
	)
end

-- Es la MISMA Part leida en las dos vistas: el Luau corre en el servidor
-- de Play, asi que `Workspace` aqui es la copia de Play. La sesion de
-- edicion se consulta por separado con studio-mcp.js.
local inPlay = readBlock("Block_0")

return "PLAY: " .. describe(inPlay)