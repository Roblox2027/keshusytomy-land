-- p0-hud.lua (CLIENTE)
-- Audita el HUD REAL del cliente: existe, esta habilitado y tiene la Zona
-- BottomBar > BombAction que `InputController` busca.
--
-- Por que importa: si `findBombAction` devuelve nil, `ensureBombButton`
-- espera 15 s, falla, y el jugador se queda sin boton de bomba. Eso se lee
-- como "la bomba no aparece" aunque el servidor este perfecto.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

say("=== HUD EN EL CLIENTE ===")

local pgui = player:WaitForChild("PlayerGui", 10)
if not pgui then
	return "sin PlayerGui"
end

say("Hijos de PlayerGui (%d):", #pgui:GetChildren())
for _, c in ipairs(pgui:GetChildren()) do
	local extra = ""
	if c:IsA("ScreenGui") then
		extra = (" enabled=%s resetOnSpawn=%s displayOrder=%d"):format(
			tostring(c.Enabled), tostring(c.ResetOnSpawn), c.DisplayOrder)
	end
	say("  %s (%s)%s", c.Name, c.ClassName, extra)
end

local hud = pgui:FindFirstChild("KeshusyHUD")
say("")
say("KeshusyHUD = %s", tostring(hud and hud:GetFullName()))

if not hud then
	say(">>> NO EXISTE KeshusyHUD en el cliente.")
	return table.concat(out, "\n")
end

say("Habilitado = %s", tostring(hud.Enabled))
say("ResetOnSpawn = %s", tostring(hud.ResetOnSpawn))

-- Ruta EXACTA que recorre `findBombAction`.
local node = hud
local ruta = { "KeshusyHUD", "Root", "BottomBar", "BombAction" }

for i = 2, #ruta do
	local paso = ruta[i]
	node = node:FindFirstChild(paso)
	say("  %s -> %s", paso, tostring(node and node:GetFullName()))

	if not node then
		break
	end
end

if not node then
	say(">>> LA RUTA SE CORTA: el HUD no tiene la Zona de bomba.")
	return table.concat(out, "\n")
end

say("BombAction = %s (%s)", node.Name, node.ClassName)
say("  Visible = %s | Active = %s | AbsoluteSize = %s",
	tostring(node.Visible), tostring(node.Active), tostring(node.AbsoluteSize))
say(" .Position = %s | AnchorPoint = %s", tostring(node.Position), tostring(node.AnchorPoint))
say("  ZIndex = %d", node.ZIndex)

say("  Tiene BombVisual = %s", tostring(node:FindFirstChild("BombVisual") ~= nil))
say("  Tiene State = %s", tostring(node:FindFirstChild("State") ~= nil))
say("  Tiene KeyHint = %s", tostring(node:FindFirstChild("KeyHint") ~= nil))
say("  Tiene Cooldown = %s", tostring(node:FindFirstChild("Cooldown") ~= nil))

-- Piezas dibujadas dentro de BombVisual.
local visual = node:FindFirstChild("BombVisual")
if visual then
	local piezas = {}
	for _, c in ipairs(visual:GetChildren()) do
		piezas[#piezas + 1] = c.Name
	end
	table.sort(piezas)
	say("  Piezas de BombVisual = %s", table.concat(piezas, ", "))
end

-- Zonas hermanas: sirve para detectar SOLAPES sin adivinar.
say("")
say("Zonas del HUD:")
for _, z in ipairs(hud:FindFirstChild("Root"):GetChildren()) do
	local extra = ""
	if z:IsA("GuiObject") then
		extra = (" pos=%s size=%s visible=%s zIndex=%d"):format(
			tostring(z.Position), tostring(z.Size), tostring(z.Visible), z.ZIndex)
	end
	say("  %s (%s)%s", z.Name, z.ClassName, extra)
end

return table.concat(out, "\n")
