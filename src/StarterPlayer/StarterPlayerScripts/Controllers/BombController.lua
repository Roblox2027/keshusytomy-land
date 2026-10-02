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

--- Minutos entre intento y resultado del servidor.
Controller._pendingSince = nil

--- Marca si hay una peticion en vuelo.
function Controller.HasPendingRequest(): boolean
	return Controller._pendingSince ~= nil
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
	Controller._pendingSince = _lastRequestAt
	Controller._requestsSent += 1

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
	Controller._pendingSince = nil
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
	Controller._pendingSince = nil
	return true
end

return Controller
