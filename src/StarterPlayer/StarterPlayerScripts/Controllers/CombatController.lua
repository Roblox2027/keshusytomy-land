--!strict
--[[
    CombatController
    UNICA puerta del cliente para el combate cuerpo a cuerpo (mision V2).

    POR QUE EXISTE
    --------------
    El jugador tenia UNA herramienta (la bomba). El combate V2 anade
    ataque rapido, dash y habilidad, y este modulo es la unica via del
    cliente para pedirlas:

        Dispositivo -> InputController -> CombatController -> Remote -> Servidor

    EL CLIENTE NO ES AUTORIDAD
    --------------------------
    Las acciones NO llevan payload: el cliente no manda objetivo, ni
    distancia, ni dano, ni paso de combo. Todo eso lo decide el servidor
    (`CombatService` + `CombatRules`). Aqui solo se espacia el spam
    obvio y se anuncia el golpe especial cuando el SERVIDOR lo publica.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONSTANTS = SHARED:WaitForChild("Constants")
local UTILS = SHARED:WaitForChild("Utils")

local GameConstants = require(CONSTANTS:WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))

local RemoteAction = GameConstants.RemoteAction

local Controller = {}

Controller.IsActive = false

-- Canal de combate, resuelto una sola vez.
local combatRemote = nil
local _maid = nil

--- Espaciado local minimo entre peticiones. NO concede nada: solo evita
--- que una rafaga de clics inunde el canal; el cooldown de verdad lo
--- aplica el servidor.
local MIN_REQUEST_GAP = 0.1
local _lastRequestAt = 0

--- Diagnostico.
Controller._requestsSent = 0

--- Envia una accion de combate. Sin payload: el servidor decide el resto.
--- @param action string "Melee" | "Dash" | "Ability"
--- @return boolean sent
local function send(action: string): boolean
	if not combatRemote then
		return false
	end

	local now = os.clock()

	if now - _lastRequestAt < MIN_REQUEST_GAP then
		return false
	end

	_lastRequestAt = now
	Controller._requestsSent += 1
	combatRemote:FireServer(action)

	return true
end

--- Ataque rapido cuerpo a cuerpo.
--- @return boolean sent
function Controller.Melee(): boolean
	return send("Melee")
end

--- Dash con invulnerabilidad breve.
--- @return boolean sent
function Controller.Dash(): boolean
	return send("Dash")
end

--- Habilidad en area.
--- @return boolean sent
function Controller.Ability(): boolean
	return send("Ability")
end

--- @param maid any? Maid del registro de controllers.
--- @return boolean success
function Controller.Start(maid: any?): boolean
	if Controller.IsActive then
		return true
	end

	_maid = maid

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	combatRemote = remotes:WaitForChild(RemoteAction.Combat, 10)

	if not combatRemote then
		Logger.Error("CombatController: el remoto CombatAction no existe.")
		return false
	end

	-- El golpe ESPECIAL lo anuncia el servidor via `ComboStep`: el cliente
	-- no puede saber por su cuenta cuando toca el especial sin duplicar la
	-- cadena, y una cadena duplicada en cliente y servidor se desincroniza
	-- al primer paquete perdido.
	local player = Players.LocalPlayer

	if player and _maid then
		_maid:Connect(player:GetAttributeChangedSignal("ComboStep"), function()
			local step = player:GetAttribute("ComboStep")

			if step == 3 then
				local UIController = require(script.Parent:WaitForChild("UIController"))

				if UIController and UIController.Notify then
					UIController.Notify("GOLPE ESPECIAL", Color3.fromRGB(255, 190, 90))
				end
			end
		end)
	end

	Controller.IsActive = true
	Logger.Info("CombatController listo (melee, dash, habilidad).")
	return true
end

--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false
	combatRemote = nil
	_maid = nil
	return true
end

return Controller
