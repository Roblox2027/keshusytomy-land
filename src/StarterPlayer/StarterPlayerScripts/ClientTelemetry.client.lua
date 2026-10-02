--!strict
--[[
	ClientTelemetry

	Sonda de DIAGNOSTICO DEL CLIENTE. No forma parte del juego.

	POR QUE EXISTE
	--------------
	Las herramientas MCP que deberian hablar con el cliente
	(`eval_client_runtime`, `capture_screenshot`, `execute_luau` con
	target=client-1) devuelven todas `request_timeout ... stage: executing`
	contra el peer del cliente, aunque el servidor ve al jugador conectado y
	moviendolo por el mapa. Ninguna permite saber que ve el jugador.

	Este script da un camino INDEPENDIENTE para comprobarlo: contesta a un
	RemoteFunction con lo que el jugador tiene realmente delante (camara,
	viewport, PlayerGui, quantas Parts del Lobby estan en el frustum). Si el
	servidor recibe respuesta, el cliente esta vivo ejecutando Luau y la
	experiencia se puede describir con hechos, no con suposiciones.

	No dibuja nada ni altera el juego: solo responde cuando se le pregunta.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local TELEMETRY_REMOTE = "ClientTelemetry"

-- El servidor crea el RemoteFunction en runtime. Hasta que exista, este
-- script reintenta: se le puede preguntar en cualquier momento.
local connected = false

--- Informe del entorno del jugador: camara, viewport, PlayerGui y mundo.
local function buildReport(): { [string]: any }
	local report: { [string]: any } = {}

	report.localPlayer = LocalPlayer ~= nil and LocalPlayer.Name or "NIL"
	report.hasCharacter = LocalPlayer ~= nil and LocalPlayer.Character ~= nil

	local character = LocalPlayer and LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	report.health = humanoid and humanoid.Health or -1

	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		report.pos = string.format(
			"%.1f,%.1f,%.1f",
			root.Position.X,
			root.Position.Y,
			root.Position.Z
		)
	else
		report.pos = "n/a"
	end

	-- La camara es lo que define de verdad "que ve el jugador".
	local camera = workspace.CurrentCamera
	report.hasCamera = camera ~= nil

	if camera then
		local position = camera.CFrame.Position
		local look = camera.CFrame.LookVector
		report.camPos = string.format("%.1f,%.1f,%.1f", position.X, position.Y, position.Z)
		report.camLook = string.format("%.2f,%.2f,%.2f", look.X, look.Y, look.Z)
		report.camFov = camera.FieldOfView

		local viewport = camera.ViewportSize
		report.viewport = string.format("%dx%d", viewport.X, viewport.Y)

		-- VISIBILIDAD REAL, por region.
		--
		-- Medir solo `Lobby` daba un falso negativo: durante la ronda el
		-- jugador esta en la Arena (a 500 studs) y alli no hay ningun Part del
		-- Lobby, asi que "0 visibles" era correcto y no un fallo. Se mide
		-- TODO Workspace agrupado por carpeta de primer nivel, que es como
		-- se pregunta "que tiene el jugador delante de verdad".
		--
		-- No se usa `workspace:GetFrustumInView`: no existe en esta version
		-- de Studio. La vision se calcula aqui a mano (cono de vision +
		-- distancia + oclusion por raycast), que es lo que el jugador
		-- percibe.
		local visible = 0
		local blockedCount = 0
		local perRegion = {}
		-- Que instancia esta tapando cada Part: sin esto "57 ocluidas" no
		-- dice nada. Es la diferencia entre "no se ve porque es correcto"
		-- y "no se ve porque algo tapa el mapa".
		local occluders = {}

		if camera then
			local origin = camera.CFrame.Position
			local forward = camera.CFrame.LookVector
			-- El FOV abre el cono; el margen lateral crece con la distancia.
			local halfAngle = math.rad(camera.FieldOfView) / 2
			local tanHalf = math.tan(halfAngle)
			local maxDistance = 500

			for _, top in ipairs(workspace:GetChildren()) do
				local regionVisible = 0
				local regionTotal = 0

				if not top:IsA("BasePart") then
					for _, descendant in ipairs(top:GetDescendants()) do
						if descendant:IsA("BasePart") then
							regionTotal += 1

							local delta = descendant.Position - origin
							local distance = delta.Magnitude

							if distance > 0.01 and distance < maxDistance then
								local dot = forward:Dot(delta / distance)

								if dot > 0 then
									local lateral = math.sqrt(math.max(0, 1 - dot * dot)) / dot
									local angleOk = lateral <= tanHalf

									local okHit, hit = pcall(function()
										-- Se excluye el propio personaje del raycast: sin
										-- este filtro el torso y la cabeza del jugador
										-- bloqueaban el rayo desde la camara y toda
										-- la zona contaba como "0 visibles" cuando si
										-- se veia.
										local params = RaycastParams.new()
										params.FilterType = Enum.RaycastFilterType.Exclude
										params.FilterDescendantsInstances = {
											LocalPlayer.Character,
										}
										params.RespectCanCollide = false
										return workspace:Raycast(origin, delta, params)
									end)

									local occluded = okHit
										and hit ~= nil
										and hit.Instance ~= descendant
										and not hit.Instance:IsDescendantOf(descendant)

									if angleOk and not occluded then
										visible += 1
										regionVisible += 1
									elseif occluded then
										blockedCount += 1
										local blocker = hit.Instance.Name
										occluders[blocker] = (occluders[blocker] or 0) + 1
									end
								end
							end
						end
					end

					perRegion[top.Name] = string.format("%d/%d", regionVisible, regionTotal)
				end
			end
		end

		report.visibleParts = visible
		report.occludedParts = blockedCount
		report.visiblePerRegion = perRegion

		local blockerLines = {}
		for name, count in occluders do
			table.insert(blockerLines, name .. " x" .. count)
		end
		table.sort(blockerLines)
		report.occluders = table.concat(blockerLines, ", ")
	else
		report.viewport = "n/a"
	end

	-- PlayerGui: lo que el jugador tiene en pantalla encima del mundo.
	local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	report.hasPlayerGui = playerGui ~= nil

	local guiChildren = {}
	if playerGui then
		for _, child in ipairs(playerGui:GetChildren()) do
			table.insert(guiChildren, child.Name .. " [" .. child.ClassName .. "]")
		end
	end
	report.playerGuiChildren = guiChildren

	-- Iluminacion: si son las de Studio, el mundo se ve plano.
	-- Cada dato va en pcall: un solo campo protegido (Studio no expone
	-- `Technology` a un script normal) hacia fallar el informe ENTERO y se
	-- perdia toda la informacion util.
	local function read(label, fn): any
		local ok, value = pcall(fn)
		report[label] = ok and value or ("ilegible: " .. tostring(value))
	end

	read("clockTime", function()
		return Lighting.ClockTime
	end)
	read("brightness", function()
		return Lighting.Brightness
	end)
	read("ambient", function()
		return tostring(Lighting.Ambient)
	end)
	read("outdoorAmbient", function()
		return tostring(Lighting.OutdoorAmbient)
	end)
	read("globalShadows", function()
		return Lighting.GlobalShadows
	end)
	read("fogEnd", function()
		return Lighting.FogEnd
	end)
	read("hasSky", function()
		return Lighting:FindFirstChildOfClass("Sky") ~= nil
	end)

	-- Cuenta de Luay: si es 1, Lighting es el de Studio y el mapa se ve
	-- plano, sin ciclo de dia ni cielo.
	report.lightingCount = #Lighting:GetChildren()

	-- Mundo actual.
	local worlds = workspace:FindFirstChild("Worlds")
	report.hasWorlds = worlds ~= nil

	if worlds then
		local present = {}
		for _, child in ipairs(worlds:GetChildren()) do
			table.insert(present, child.Name)
		end
		report.worlds = present
	end

	report.workspaceDescendants = #workspace:GetDescendants()

	-- En que ZONA esta el jugador ahora. Es la distincion clave del
	-- problema: el Lobby y la Arena estan a 500 studs, asi que "no veo el
	-- Lobby" solo es un fallo si el jugador deberia estar en el Lobby.
	local function locate(position: Vector3): string
		local lobby = workspace:FindFirstChild("Lobby")
		if lobby then
			for _, descendant in ipairs(lobby:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local delta = descendant.Position - position
					if delta.Magnitude < 200 then
						return "Lobby"
					end
				end
			end
		end

		local worlds = workspace:FindFirstChild("Worlds")
		if worlds then
			for _, world in ipairs(worlds:GetChildren()) do
				for _, descendant in ipairs(world:GetDescendants()) do
					if descendant:IsA("BasePart") then
						local delta = descendant.Position - position
						if delta.Magnitude < 200 then
							return "Worlds/" .. world.Name
						end
					end
				end
			end
		end

		return "sin zona"
	end

	if root then
		report.zone = locate(root.Position)
	elseif camera then
		report.zone = locate(camera.CFrame.Position)
	end

	return report
end

--- Engancha el contestador al RemoteFunction del servidor.
local function connect(): boolean
	if connected then
		return true
	end

	local found = ReplicatedStorage:FindFirstChild(TELEMETRY_REMOTE)
	if not found or not found:IsA("RemoteFunction") then
		return false
	end

	found.OnClientInvoke = buildReport
	connected = true

	print(("[TELEMETRY] cliente respondiendo en '%s'"):format(TELEMETRY_REMOTE))
	return true
end

task.spawn(function()
	while not connect() do
		task.wait(0.5)
	end
end)

return buildReport