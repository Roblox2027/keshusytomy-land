--!strict
--[[
	ClientTestDriver
	Reproductor de pruebas del CLIENTE, controlado por el servidor.

	POR QUE EXISTE
	--------------
	El MCP no puede enviar teclas ni raton al cliente de Studio, y
	`Remote:FireServer()` desde el servidor no es una prueba: el servidor
	no es el cliente, asi que eso no demuestra nada del camino del
	jugador.

	Este script es un LocalScript de VERDAD, dentro del cliente de
	VERDAD. Cuando el servidor le pide una instruccion, ejecuta la misma
	funcion que ejecutaria el jugador:

		Instruccion
		  -> InputController.RequestBombPlacement()
		    -> BombController.RequestPlace()
		      -> BombAction:FireServer("Place", ...)
		        -> RemoteGateway (validacion + rate limit)
		          -> BombService (autoridad)
		            -> bomba, mecha, explosion, dano, limpieza

	QUE NO PUEDE HACER
	------------------
	No importa ningun servicio del servidor. No existe forma de que este
	archivo llame a `BombService`, porque `ServerScriptService` no es
	accesible desde el cliente. Esa es la garantia de que la prueba
	recorre el camino real y no un atajo.

	Garantias de diseno
	------------------
	1. Solo arranca con `ENABLE_CLIENT_TEST_DRIVER`. Apagado por defecto,
	   asi que en produccion este script no hace NADA.
	2. Respeta el intervalo minimo entre ejecuciones, para no medir un
	   camino que un jugador no podria recorrer.
	3. Informa del RESULTADO por atributo, para que el servidor pueda leer
	   que la peticion salio y cual fue el veredicto.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local LIBRARIES = SHARED:WaitForChild("Libraries")
local UTILS = SHARED:WaitForChild("Utils")

local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
local TestDriverLogic = require(LIBRARIES:WaitForChild("TestDriverLogic"))
local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local CONTROLLERS = script.Parent:WaitForChild("Controllers")

local Attributes = {
	Instruction = "TestDriverInstruction",
	Result = "TestDriverResult",
	RanCount = "TestDriverRan",
}

local Driver = {}

Driver.IsRunning = false
Driver._lastRunAt = nil

--- Minimo tiempo entre ejecuciones.
--
-- Se alinea con el cooldown de bomba del servidor: por debajo de el, el
-- servidor rechazaria la segunda peticion por su propia regla y la
-- prueba mediria el rate limit en vez del camino del jugador.
Driver.MIN_INTERVAL = GameConfig.BombCooldown

--- Resuelve un controller esperando a que exista.
--- @param name string
--- @return any?
local function requireController(name: string): any?
	local module = CONTROLLERS:FindFirstChild(name)

	if not module then
		return nil
	end

	local ok, controller = pcall(require, module)

	if not ok then
		Logger.Error(("ClientTestDriver: no se pudo cargar '%s': %s"):format(name, tostring(controller)))
		return nil
	end

	return controller
end
--- Ejecuta UNA instruccion por el camino real del jugador.
---
--- Elige el controller segun la accion y llama a la MISMA funcion que
--- el jugador. Devuelve un veredicto legible, no un `true` mudo.
--- @param action string
--- @param worldId string?
--- @return boolean ok
--- @return string verdict
function Driver.Run(action: string, worldId: string?): (boolean, string)
	if action == TestDriverLogic.Actions.PlaceBomb then
		local input = requireController("InputController")

		if not input then
			return false, "InputController no disponible"
		end

		-- Se llama a `InputController`, no a `BombController` directamente:
		-- asi la prueba recorre tambien la traduccion de intencion, que es
		-- parte del camino del jugador.
		local sent = input.RequestBombPlacement()

		if sent then
			return true, "peticion de bomba enviada por BombAction"
		end

		return false, "InputController no envio la peticion (cooldown, sin personaje o sin canal)"
	end

	if action == TestDriverLogic.Actions.EnterPortal then
		if not worldId or worldId == "" then
			return false, "EnterPortal necesita un destino"
		end

		local portal = requireController("PortalController")

		if not portal then
			return false, "PortalController no disponible"
		end

		-- BUG CORREGIDO (FASE 2.1): se ignoraba el valor de retorno.
		--
		-- `RequestEnter` devuelve `false` cuando no hay canal o el portal no
		-- existe, y antes esta funcion devolvia `true` en cualquier caso que
		-- no fuera una excepcion. El log deia "peticion de portal enviada"
		-- mientras el propio controller registraba "PortalAction no
		-- disponible": un PASS falso del canal, emitido por el codigo que
		-- deberia detectarlo. Un informe que certifica lo contrario de lo que
		-- ocurre es peor que no informar.
		local ok, sent = pcall(portal.RequestEnter, worldId)

		if not ok then
			return false, ("PortalController fallo: %s"):format(tostring(sent))
		end

		if sent ~= true then
			return false, ("PortalController no envio la peticion a '%s' (canal ausente o portal desconocido)"):format(
				tostring(worldId)
			)
		end

		return true, ("peticion de portal enviada: %s"):format(worldId)
	end

	if action == TestDriverLogic.Actions.RequestState then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local remote = remotes:FindFirstChild("PlayerAction")

		if not remote or not remote:IsA("RemoteEvent") then
			return false, "PlayerAction no disponible"
		end

		remote:FireServer("RequestState")
		return true, "peticion de estado enviada"
	end

	return false, ("instruccion no soportada: %s"):format(tostring(action))
end

--- Publica el veredicto para que el servidor pueda leerlo.
--- @param verdict string
local function publish(verdict: string)
	local player = Players.LocalPlayer

	if not player then
		return
	end

	player:SetAttribute(Attributes.Result, verdict)
	player:SetAttribute(Attributes.RanCount, (player:GetAttribute(Attributes.RanCount) or 0) + 1)
end

--- Bucle que espera instrucciones del servidor.
local function runLoop()
	local player = Players.LocalPlayer

	if not player then
		return
	end

	-- Conexion al atributo: es como el servidor pide una instruccion sin
	-- abrir ningun remoto extra de testing.
	local connection = player:GetAttributeChangedSignal(Attributes.Instruction):Connect(function()
		local encoded = player:GetAttribute(Attributes.Instruction)

		if type(encoded) ~= "string" then
			return
		end

		local action, worldId, reason = TestDriverLogic.Decode(encoded)

		if not action then
			Logger.Warn(("ClientTestDriver: instruccion rechazada (%s)"):format(tostring(reason)))
			publish(("RECHAZADA: %s"):format(tostring(reason)))
			return
		end

		local now = os.clock()
		local allowed, why = TestDriverLogic.CanRun(action, Driver._lastRunAt, now, Driver.MIN_INTERVAL)

		if not allowed then
			Logger.Warn(("ClientTestDriver: %s no ejecutada (%s)"):format(action, tostring(why)))
			publish(("OMITIDA: %s"):format(tostring(why)))
			return
		end

		Driver._lastRunAt = now

		local ok, verdict = Driver.Run(action, worldId)

		if ok then
			Logger.Info(("ClientTestDriver: %s -> %s"):format(action, verdict))
		else
			Logger.Error(("ClientTestDriver: %s fallo: %s"):format(action, verdict))
		end

		publish(("%s: %s"):format(ok and "OK" or "FALLO", verdict))
	end)

	Driver.IsRunning = true

	Logger.Info(("ClientTestDriver activo. Instrucciones: %s"):format(
		table.concat(TestDriverLogic.SupportedActions(), ", ")
	))

	player.Destroying:Connect(function()
		connection:Disconnect()
	end)
end

-- Guarda de seguridad: en produccion este script no hace nada.
if not FeatureConfig.ENABLE_CLIENT_TEST_DRIVER then
	Logger.Info("ClientTestDriver: desactivado por FeatureConfig.")
	return
end

runLoop()