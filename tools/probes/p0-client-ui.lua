-- p0-client-ui.lua
-- Geometria REAL de la UI en el cliente de Play.
--
-- Mide el boton de bomba y TODOS los paneles del HUD, y dice si se solapan.
-- No modifica nada.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

if not player then
	return { error = "sin LocalPlayer" }
end

local playerGui = player:FindFirstChildOfClass("PlayerGui")

if not playerGui then
	return { error = "sin PlayerGui" }
end

local camera = workspace.CurrentCamera
local viewport = camera and Vector2.new(camera.ViewportSize.X, camera.ViewportSize.Y) or Vector2.zero

--- Rectangulo absoluto de un GuiObject.
local function rectOf(instance)
	if not instance or not instance:IsA("GuiObject") then
		return nil
	end
	local pos = instance.AbsolutePosition
	local size = instance.AbsoluteSize
	return {
		x = pos.X,
		y = pos.Y,
		w = size.X,
		h = size.Y,
		right = pos.X + size.X,
		bottom = pos.Y + size.Y,
	}
end

--- Interseccion de dos rectangulos, o nil.
local function overlap(a, b)
	if not a or not b then
		return nil
	end
	local x = math.max(a.x, b.x)
	local y = math.max(a.y, b.y)
	local r = math.min(a.right, b.right)
	local d = math.min(a.bottom, b.bottom)
	if r <= x or d <= y then
		return nil
	end
	return { x = x, y = y, w = r - x, h = d - y, area = (r - x) * (d - y) }
end

local out = {
	viewport = { x = viewport.X, y = viewport.Y },
	guis = {},
	panels = {},
	bombButton = nil,
	overlaps = {},
}

-- Todos los ScreenGui del cliente, con su DisplayOrder.
for _, child in ipairs(playerGui:GetChildren()) do
	if child:IsA("ScreenGui") then
		table.insert(out.guis, {
			name = child.Name,
			displayOrder = child.DisplayOrder,
			ignoreGuiInset = child.IgnoreGuiInset,
			enabled = child.Enabled,
			resetOnSpawn = child.ResetOnSpawn,
		})
	end
end

-- HUD: todos los paneles hermanos de KeshusyHUD.
local hud = playerGui:FindFirstChild("KeshusyHUD")

if hud then
	for _, panel in ipairs(hud:GetChildren()) do
		if panel:IsA("GuiObject") then
			local r = rectOf(panel)
			table.insert(out.panels, {
				name = panel.Name,
				x = r and math.floor(r.x) or -1,
				y = r and math.floor(r.y) or -1,
				w = r and math.floor(r.w) or -1,
				h = r and math.floor(r.h) or -1,
				visible = panel.Visible,
			})
		end
	end
end

-- Boton de bomba: esta en OTRO ScreenGui (TouchControls).
local touch = playerGui:FindFirstChild("TouchControls")
local bombButton = touch and touch:FindFirstChild("BombButton")

if bombButton and bombButton:IsA("GuiObject") then
	local r = rectOf(bombButton)
	out.bombButton = {
		found = true,
		gui = touch.Name,
		displayOrder = touch.DisplayOrder,
		x = math.floor(r.x),
		y = math.floor(r.y),
		w = math.floor(r.w),
		h = math.floor(r.h),
		anchorX = bombButton.AnchorPoint.X,
		anchorY = bombButton.AnchorPoint.Y,
		posScaleX = bombButton.Position.X.Scale,
		posOffX = bombButton.Position.X.Offset,
		posScaleY = bombButton.Position.Y.Scale,
		posOffY = bombButton.Position.Y.Offset,
		pieces = {},
	}

	for _, piece in ipairs(bombButton:GetChildren()) do
		if piece:IsA("GuiObject") then
			local pr = rectOf(piece)
			table.insert(out.bombButton.pieces, {
				name = piece.Name,
				class = piece.ClassName,
				x = pr and math.floor(pr.x) or -1,
				y = pr and math.floor(pr.y) or -1,
				w = pr and math.floor(pr.w) or -1,
				h = pr and math.floor(pr.h) or -1,
				visible = piece.Visible,
			})
		end
	end
else
	out.bombButton = { found = false }
end

-- Solapamientos del boton contra CADA panel del HUD.
if out.bombButton.found then
	local br = rectOf(bombButton)

	for _, panel in ipairs(hud and hud:GetChildren() or {}) do
		if panel:IsA("GuiObject") and panel.Visible then
			local ov = overlap(br, rectOf(panel))

			if ov then
				table.insert(out.overlaps, {
					panel = panel.Name,
					area = math.floor(ov.area),
					overlapX = math.floor(ov.w),
					overlapY = math.floor(ov.h),
				})
			end
		end
	end
end

return out