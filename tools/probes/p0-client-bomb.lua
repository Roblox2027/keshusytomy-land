-- p0-client-bomb.lua (CLIENTE)
-- Lo que ve el JUGADOR, no lo que dice el servidor.
--
-- El P0 no se cierra con "el servidor creo la bomba". Se cierra con "el
-- cliente la VE". Esta sonda lee el Workspace DEL CLIENTE y ademas mide el
-- estado del `BombController`, que es quien decide si la peticion sale.

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

say("=== CLIENTE ===")
say("Jugador = %s mundo=%s", player.Name, tostring(player:GetAttribute("World")))

local folder = workspace:FindFirstChild("Bombs")
say("Workspace.Bombs en el cliente = %s", tostring(folder and folder:GetFullName()))

if not folder then
	say("NO existe la carpeta de bombas en el cliente: nada puede verse.")
	return table.concat(out, "\n")
end

local hijos = folder:GetChildren()
say("Bombas replicadas = %d", #hijos)

for _, model in ipairs(hijos) do
	local solidas, total = 0, 0
	local p = model.PrimaryPart

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			total += 1
			if d.Transparency < 1 then
				solidas += 1
			end
		end
	end

	say("  %s id=%s en (%.0f, %.0f, %.0f) partes=%d visibles=%d mecha=%s owner=%s",
		model.Name,
		tostring(model:GetAttribute("BombId")),
		p and p.Position.X or 0, p and p.Position.Y or 0, p and p.Position.Z or 0,
		total, solidas,
		tostring(model:GetAttribute("FuseRemaining")),
		tostring(model:GetAttribute("OwnerUserId")))
end

-- ESTADO DEL CONTROLLER: aqui vive el sintoma "solo puedo poner UNA bomba".
local okC, BombController = pcall(function()
	local controllers = script.Parent:FindFirstChild("Controllers")
	return controllers and controllers:FindFirstChild("BombController")
end)

say("")
say("=== BombController ===")

local bc = nil

for _, obj in ipairs(script.Parent:GetDescendants()) do
	if obj:IsA("ModuleScript") and obj.Name == "BombController" then
		bc = require(obj)
		break
	end
end

if not bc then
	say("No se encontro BombController en el arbol del cliente.")
	return table.concat(out, "\n")
end

local st = bc.GetState()
say("Activo = %s", tostring(st.Active))
say("Puede pedir = %s", tostring(st.CanRequest))
say("Enfriamiento restante = %.2f s", st.CooldownRemaining)
say("Peticiones enviadas = %d", st.RequestsSent)
say("Peticiones suprimidas = %d", st.RequestsSuppressed)
say("Tiene peticion EN VOLO = %s", tostring(bc.HasPendingRequest()))

-- ESTA ES LA PRUEBA DEL P0: si hay una peticion en vuelo que nunca se
-- limpia, `CanRequest` es falso PARA SIEMPRE y el jugador solo puede
-- colocar una bomba en toda la sesion.
if bc.HasPendingRequest() then
	say("")
	say("FALLO P0: hay una peticion en vuelo que NUNCA se resuelve.")
	say("       CanRequest quedara en false para siempre -> solo 1 bomba.")
end

return table.concat(out, "\n")
