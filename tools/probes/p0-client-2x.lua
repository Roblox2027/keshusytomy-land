-- p0-client-2x.lua (CLIENTE)
-- P0 ABSOLUTO por el camino REAL: dos bombas desde el cliente, visibles.
--
-- Antes de este cambio, la PRIMERA peticion dejaba el cerrojo "en vuelo"
-- abierto para siempre y el jugador solo podia colocar una bomba en toda la
-- sesion. Aqui se mide el ciclo COMPLETO y el tiempo que dura el cerrojo.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local out = {}
local function say(fmt, ...) table.insert(out, string.format(fmt, ...)) end

local player = Players.LocalPlayer
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

say("=== CLIENTE: DOS BOMBAS POR EL CAMINO REAL ===")
say("Mundo = %s | ronda viva = %s", tostring(player:GetAttribute("World")),
	tostring(player:GetAttribute("RoundState")))
say("Posicion = (%.0f, %.0f, %.0f)", root and root.Position.X or 0,
	root and root.Position.Y or 0, root and root.Position.Z or 0)

local function cargar(nombre)
	local s = StarterPlayer:WaitForChild("Controllers"):FindFirstChild(nombre)
	if not s then return nil end
	local ok, mod = pcall(require, s)
	return if ok then mod else nil
end

local BombController = cargar("BombController")
local InputController = cargar("InputController")

if not BombController or not InputController then
	return table.concat(out, "\n") .. "\nno se pudieron cargar los controllers"
end

local folder = workspace:FindFirstChild("Bombs")
say("Workspace.Bombs = %s", tostring(folder and folder:GetFullName()))

--- Estado del cerrojo y lo que hay en el mundo, con el tiempo medido.
local function medir(etiqueta)
	local st = BombController.GetState()
	say("")
	say("[%s] enviado=%d suprimido=%d enVolo=%s puedePedir=%s enfriamiento=%.2f",
		etiqueta, st.RequestsSent, st.RequestsSuppressed,
		tostring(BombController.HasPendingRequest()),
		tostring(st.CanRequest), st.CooldownRemaining)

	local n = folder and #folder:GetChildren() or 0
	say("        Workspace.Bombs = %d | BombRejection = %s | BombCapacity = %s",
		n, tostring(player:GetAttribute("BombRejection")),
		tostring(player:GetAttribute("BombCapacity")))

	return n
end

medir("INICIO")

--- Pulsa por la MISMA funcion que la tecla F, y espera a que el cerrojo se
--- suelte. La espera esta ACOTADA: si el cerrojo no se abre, la sonda lo DICE
--- con el tiempo que ha estado cerrado en vez de colgarse.
local function intentarBomba(nombre)
	local t0 = os.clock()
	local enviada = InputController.RequestBombPlacement()
	say("")
	say(">>> %s: RequestBombPlacement = %s", nombre, tostring(enviada))

	local esperado = folder and #folder:GetChildren() or 0
	local abierta = false

	for _ = 1, 40 do
		task.wait(0.25)

		local n = folder and #folder:GetChildren() or 0

		if n > esperado then
			abierta = true
			break
		end

		if not BombController.HasPendingRequest() then
			abierta = true
			break
		end
	end

	say("    cerrojo abierto = %s tras %.2f s",
		tostring(abierta), os.clock() - t0)

	return abierta
end

local okA = intentarBomba("BOMBA A")
medir("TRAS BOMBA A")

-- BOMBA B: hay que dejar pasar el enfriamiento. Se espera de verdad.
local espera = 1.8
say("")
say("Esperando %.1f s de enfriamiento...", espera)
task.wait(espera)

local okB = intentarBomba("BOMBA B")
medir("TRAS BOMBA B")

-- Las dos a la vez, con posiciones y mechas propias.
if folder then
	local vivos = {}
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			table.insert(vivos, m)
		end
	end

	say("")
	say("BOMBAS VIVAS A LA VEZ = %d", #vivos)

	for _, m in ipairs(vivos) do
		local solidas = 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				solidas += 1
			end
		end
		local p = m.PrimaryPart
		say("  id=%s en (%.0f, %.0f, %.0f) visibles=%d mecha=%s",
			tostring(m:GetAttribute("BombId")),
			p and p.Position.X or 0, p and p.Position.Y or 0, p and p.Position.Z or 0,
			solidas, tostring(m:GetAttribute("FuseRemaining")))
	end

	if #vivos == 2 then
		local pa, pb = vivos[1].PrimaryPart, vivos[2].PrimaryPart
		local fa = vivos[1]:GetAttribute("FuseRemaining")
		local fb = vivos[2]:GetAttribute("FuseRemaining")
		say("")
		say("INDEPENDENCIA: distancia = %.1f studs | mechaA=%s mechaB=%s",
			(pa.Position - pb.Position).Magnitude, tostring(fa), tostring(fb))
	end
end

-- TERCERA: debe RECHAZARSE con motivo explicito, no con "anti-exploit".
task.wait(1.8)
local okC = InputController.RequestBombPlacement()
say("")
say("BOMBA C (debe rechazarse por capacidad): enviada=%s", tostring(okC))
task.wait(0.6)
say("BombRejection tras la tercera = %s", tostring(player:GetAttribute("BombRejection")))

medir("FIN")

return table.concat(out, "\n")
