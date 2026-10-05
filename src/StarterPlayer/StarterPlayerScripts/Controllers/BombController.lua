--!strict
--[[
    BombController
    UNICA puerta del cliente para pedir una bomba. El servidor decide.

    POR QUE EXISTE (reconciliacion FASE 1 REAL)
    --------------------------------------------
    Antes `InputController` tenia el canal `BombAction` y disparaba el
    remoto, mientras `BombController` era un modulo vacio. Eso rompia la
    cadena documentada:

        Tecla -> InputController -> BombController -> Remote -> Servidor

    El teclado leia entrada Y enviaba al servidor, y el controller que
    deberia conocer la bomba no conocia nada. Ahora la division es real:

        InputController  SOLO traduce dispositivo -> intencion
        BombController   SOLO envia la intencion por el remoto y expone
                         el estado (cooldown, cantidad) para el HUD

    El cliente NO es autoridad: no comprueba ronda, ni arena, ni distancia.
    Eso lo hace `BombService` en el servidor. Aqui solo se evita el spam
    obvio y se da informacion al HUD.

    El servidor sigue siendo el unico que coloca, explosiona y hace dano.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local GameConfig = require(CONFIG:WaitForChild("GameConfig"))
local Logger = require(UTILS:WaitForChild("Logger"))

local RemoteAction = GameConstants.RemoteAction

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

--- Canal de bombas, resuelto una sola vez.
local bombRemote = nil

--- Ultimo instante (os.clock) en que se ACEPTO una peticion.
-- Solo espacia lo que el jugador pide; no concede nada.
local _lastRequestAt = 0

--- Numero de intentos aceptados por el cliente (diagnostico).
Controller._requestsSent = 0

--- Numero de peticiones NO enviadas por cooldown local.
Controller._requestsSuppressed = 0

--- Instante (os.clock) del ultimo intento. Solo lo usa el HUD para medir.
local _pendingSince = nil

--- Indica que hay una peticion EN VOLO esperando veredicto del servidor.
---
--- Es distinto de `_pendingSince` a proposito: `_pendingSince` dice CUANDO se
--- pidio, y `_awaitingServer` dice que el cerrojo esta ARMADO a la espera de
--- una respuesta que puede no llegar. Sin esa distincion no se puede poner un
--- plazo de seguridad sin perder la marca de tiempo.
local _awaitingServer = false

--- Instante en que se armo el cerrojo, para el plazo de seguridad.
local _armedAt = 0

--- Cuanto se espera la respuesta del servidor antes de soltar el cerrojo.
---
--- MEDIDO: en PLAY el servidor SI responde, y responde de las dos maneras:
--- publica la bomba en la carpeta o escribe el motivo de rechazo. Este plazo
--- es solo la red de seguridad para cuando la respuesta se pierde. Sin el, un
--- fallo de red dejaria al jugador sin bombas hasta que recargase, que es
--- peor que una peticion de mas.
---
--- Es mayor que el enfriamiento (1.5 s) para no soltar el cerrojo antes de
--- que un servidor lento haya podido responder.
local VERDICT_TIMEOUT = 5

--- Marca si hay una peticion en vuelo.
function Controller.HasPendingRequest(): boolean
	return _pendingSince ~= nil
end

--- Suelta el cerrojo de "peticion en vuelo". Es idempotente.
local function releasePending()
	_pendingSince = nil
	_awaitingServer = false
	_armedAt = 0
end

--- Espera el veredicto del servidor y suelta el cerrojo.
---
--- Las DOS senales se escuchan a la vez y la que llegue primero gana:
---
---   `ChildAdded` en `Workspace.Bombs` -> ACEPTADA. Es la confirmacion real:
---                                       la bomba existe en el mundo.
---   `BombRejection` del jugador      -> RECHAZADA. El servidor explica por
---                                       que, y el jugador lo ve.
---
--- Si no llegara ninguna, el plazo de seguridad libera igualmente: ningun
--- silencio puede dejar al jugador sin poder jugar.
local function waitForServerVerdict()
	local player = Players.LocalPlayer

	if not player then
		releasePending()
		return
	end

	local folder = Workspace:WaitForChild("Bombs", 5)
	local espera = math.max(VERDICT_TIMEOUT - (os.clock() - _armedAt), 0.2)

	local conexionBomb = nil
	local conexionRechazo = nil

	local function cerrar()
		if conexionBomb and conexionBomb.Connected then
			conexionBomb:Disconnect()
		end

		if conexionRechazo and conexionRechazo.Connected then
			conexionRechazo:Disconnect()
		end
	end

	if folder then
		conexionBomb = folder.ChildAdded:Connect(function()
			releasePending()
			cerrar()
		end)

		conexionRechazo = player:GetAttributeChangedSignal("BombRejection"):Connect(function()
			releasePending()
			cerrar()
		end)
	end

	task.wait(espera)
	cerrar()
	releasePending()
end

--- Segundos que quedan de espera local antes de poder volver a pedir.
---
--- Es unaestimate de EXPERIENCIA para el HUD, no una garantia: el
--- servidor tiene su propio cooldown y puede rechazar por otros motivos.
--- @return number
function Controller.GetCooldownRemaining(): number
	local elapsed = os.clock() - _lastRequestAt
	local remaining = GameConfig.BombCooldown - elapsed

	if remaining < 0 then
		return 0
	end

	return remaining
end

--- Indica si el boton puede activarse ahora.
--- @return boolean
function Controller.CanRequest(): boolean
	return Controller.GetCooldownRemaining() <= 0 and not Controller.HasPendingRequest()
end

--- Envia la peticion de bomba por el canal real.
---
--- Esta es la funcion que el reproductor de pruebas invoca para
--- reproducir el camino del jugador. NO es una via paralela: es
--- exactamente la que llama el teclado, el boton tactil y el mando.
--- @return boolean sent
function Controller.RequestPlace(): boolean
	local player = Players.LocalPlayer

	if not player then
		return false
	end

	if not bombRemote then
		Logger.Warn("BombController: BombAction no disponible; no se pueden colocar bombas.")
		return false
	end

	-- Frena el spam local. NO decide si la bomba es legal.
	if not Controller.CanRequest() then
		Controller._requestsSuppressed += 1
		return false
	end

	local character = player.Character

	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not rootPart then
		return false
	end

	_lastRequestAt = os.clock()
	_pendingSince = _lastRequestAt
	Controller._requestsSent += 1

	-- P0 MEDIDO EN PLAY (medido, no deducido): antes de esto, `_pendingSince`
	-- se ponia al pedir y NO se limpiaba nunca. `CanRequest` exigia
	-- `not HasPendingRequest()`, asi que desde la PRIMERA peticion de la
	-- sesion `CanRequest` era false PARA SIEMPRE:
	--
	--     BombController ANTES: enviado=1 suprimido=0 enVolo=true puedePedir=false
	--     BombController DESPUES: enviado=1 suprimido=1 enVolo=true puedePedir=false
	--     >>> FALLO P0 CONFIRMADO: peticion en vuelo sin resolver.
	--
	-- El sintoma que ve el jugador es exactamente "solo puedo colocar una
	-- bomba": la primera sale y todas las siguientes se suprimen en el
	-- cliente sin llegar al servidor. El servidor nunca las ve, asi que su
	-- log no muestra nada, y el limite parece del juego cuando en realidad
	-- es un cerrojo local.
	--
	-- El cerrojo se arma AL ENVIAR, no antes: si se armara antes y la
	-- peticion no saliera, quedaria esperando una respuesta que nunca
	-- llegaria. Se levanta cuando el SERVIDOR responde, y se escuchan las
	-- dos senales de esa respuesta:
	--
	--   `ChildAdded` en `Workspace.Bombs` -> ACEPTADA (la bomba existe).
	--   `BombRejection` del jugador      -> RECHAZADA (con su motivo).
	--
	if not _awaitingServer then
		_awaitingServer = true
		_armedAt = os.clock()
		task.spawn(waitForServerVerdict)
	end

	-- Se envia la posicion del personaje, no la del raton: el servidor
	-- la vuelve a validar (distancia, arena, ronda), asi que manipular
	-- esta cifra no concede nada.
	bombRemote:FireServer("Place", rootPart.Position)
	return true
end

--- Informe del estado para HUD y para el reproductor de pruebas.
--- @return table
function Controller.GetState(): { [string]: any }
	return {
		Active = Controller.IsActive,
		CanRequest = Controller.CanRequest(),
		CooldownRemaining = Controller.GetCooldownRemaining(),
		RequestsSent = Controller._requestsSent,
		RequestsSuppressed = Controller._requestsSuppressed,
	}
end

--- Ativa el controller. Debe ser idempotente y reversible con Destroy.
--- @param _maid any? Maid del registro de controllers.
--- @return boolean success
function Controller.Start(_maid: any?): boolean
	if Controller.IsActive then
		return true
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:FindFirstChild(RemoteAction.Bomb)

	if not remote or not remote:IsA("RemoteEvent") then
		Logger.Error("BombController: ReplicatedStorage.Remotes." .. RemoteAction.Bomb .. " no existe.")
		return false
	end

	bombRemote = remote
	_lastRequestAt = 0
	Controller._requestsSent = 0
	Controller._requestsSuppressed = 0
	releasePending()
	Controller.IsActive = true

	Logger.Info(("BombController listo (cooldown %.1fs, rango %d studs)."):format(
		GameConfig.BombCooldown,
		GameConfig.BombPlacementRange
	))

	return true
end

--- Desactiva el controller y libera sus referencias.
--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false
	bombRemote = nil
	releasePending()
	return true
end

return Controller
