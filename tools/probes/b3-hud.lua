-- b3-hud.lua (CLIENTE)
-- BLOQUE 3: HUD en el cliente. SIN ESPERAS: no se usa WaitForChild, porque
-- el puente MCP tiene un timeout de ~15 s y una espera lo consume entero.
--
-- Se mira lo que YA existe. Si algo falta, se dice que falta; no se repara.
local p = game:GetService("Players").LocalPlayer
local out = {}
local function say(f, ...) table.insert(out, string.format(f, ...)) end

say("LocalPlayer = %s", tostring(p and p.Name))

local pgui = p and p:FindFirstChildOfClass("PlayerGui")
say("PlayerGui = %s", tostring(pgui))
if not pgui then return table.concat(out, "\n") end

local guis = {}
for _, c in ipairs(pgui:GetChildren()) do
	if c:IsA("ScreenGui") then
		table.insert(guis, c)
	end
	say("  %s (%s)", c.Name, c.ClassName)
end
say("ScreenGuis = %d", #guis)

local hud = pgui:FindFirstChild("KeshusyHUD")
say("KeshusyHUD = %s", tostring(hud))
if not hud then return table.concat(out, "\n") end
say("Enabled = %s ResetOnSpawn = %s", tostring(hud.Enabled), tostring(hud.ResetOnSpawn))

-- Ruta EXACTA que recorre InputController para encontrar el boton de bomba.
local node = hud
for _, step in ipairs({ "Root", "BottomBar", "BombAction" }) do
	node = node and node:FindFirstChild(step)
	say("  %s -> %s", step, tostring(node and node:GetFullName()))
end
if not node then return table.concat(out, "\n") end

say("BombAction Enabled = %s Visible = %s", tostring(node.Enabled), tostring(node.Visible))
say("  AbsoluteSize = %s Position = %s", tostring(node.AbsoluteSize), tostring(node.Position))

local piezas = {}
for _, c in ipairs(node:GetChildren()) do table.insert(piezas, c.Name) end
table.sort(piezas)
say("  piezas = %s", table.concat(piezas, ", "))

return table.concat(out, "\n")