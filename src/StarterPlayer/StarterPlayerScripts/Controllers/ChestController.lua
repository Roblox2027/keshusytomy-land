--!strict
--[[
	ChestController
	Feedback visual para la apertura de cofres (FASE 20).

	POR QUE EXISTE
	--------------
	El servidor decide todo: qué habilidad cae, si el cofre ya se abrió
	y si el jugador está cerro. El cliente NUNCA valida nada. Este controller
	lo único que hace es:

	  - Pedir la oferta al entrar (RequestOffer) para que la UI muestre el
	    número de cofres abiertos desde el primer frame.
	  - Escuchar los ATRIBUTOS que el servidor publica al abrir un cofre
	    (`ChestJustOpened`, `SkillUnlockedId`, `SkillUnlockedName`,
	    `SkillUnlockedRarity`) y convertirlos en notificaciones en pantalla.

	LAS REGLAS QUE NO SE ROMPEN
	--------------------------
	1. El cliente no decide el premio. Solo muestra lo que el servidor ya
	   validó y publicó por atributos.
	2. Una notificación no puede perderse por un race condition en el orden
	   de los atributos: el servidor escribe todos antes de que el cliente
	   los lea, y el cliente muestra el aviso una sola vez por cambio.
	3. El cofre físico se abre por ProximityPrompt, no por este controller:
	   este Controller solo reacciona al resultado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local UTILS = SHARED:WaitForChild("Utils")
local CONTROLLERS = script.Parent

local GameConstants = require(SHARED:WaitForChild("Constants"):WaitForChild("GameConstants"))
local Logger = require(UTILS:WaitForChild("Logger"))
local UIController = require(CONTROLLERS:WaitForChild("UIController"))
local AudioController = require(CONTROLLERS:WaitForChild("AudioController"))

local RemoteAction = GameConstants.RemoteAction

local Controller = {}

Controller.IsActive = false

local _maid: any? = nil
local _chestRemote: RemoteEvent? = nil

--- Pide al servidor la oferta de cofres al iniciar el controller.
local function requestInitialOffer()
	if not _chestRemote then
		return
	end

	local ok, err = pcall(function()
		_chestRemote:FireServer("RequestOffer")
	end)

	if not ok then
		Logger.Warn(("ChestController: no se pudo pedir oferta: %s"):format(tostring(err)))
	end
end

--- Muestra una notificación por cofre abierto o habilidad nueva.
---
--- Lee los atributos publicados por `ChestService.HandlePromptTriggered` y
--- construye el texto del aviso. El servidor ya validó la apertura; aquí
--- solo se traduce a lenguaje visual.
--- @param player Player
local function handleChestNotification(player: Player)
	if not player or not player.Parent then
		return
	end

	local skillId = player:GetAttribute("SkillUnlockedId")
	local skillName = player:GetAttribute("SkillUnlockedName")
	local skillRarity = player:GetAttribute("SkillUnlockedRarity")

	if type(skillId) ~= "string" or skillId == "" then
		return
	end

	-- Color por rareza: cada una tiene su propio matiz visual.
	local rarityColor: Color3 = Color3.fromRGB(236, 241, 255)

	if skillRarity == "Legacy" then
		rarityColor = Color3.fromRGB(200, 170, 255)
	elseif skillRarity == "Epic" then
		rarityColor = Color3.fromRGB(170, 120, 255)
	elseif skillRarity == "Rare" then
		rarityColor = Color3.fromRGB(120, 200, 255)
	elseif skillRarity == "Common" then
		rarityColor = Color3.fromRGB(170, 255, 180)
	end

	local displayName = if type(skillName) == "string" and skillName ~= ""
		then skillName
		else skillId

	UIController.Notify(("¡HABILIDAD!: %s"):format(displayName), rarityColor)
	AudioController.PlayEvent("ChestOpen")
end

--- Activa el controller. Debe ser idempotente.
--- @param maid any?
--- @return boolean success
function Controller.Start(maid: any?): boolean
	if Controller.IsActive then
		return true
	end

	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		Logger.Warn("ChestController: no hay carpeta Remotes.")
		return false
	end

	local remote = remotes:FindFirstChild(RemoteAction.Chest)
	if not remote or not remote:IsA("RemoteEvent") then
		Logger.Error("ChestController: no existe ChestAction.")
		return false
	end

	_chestRemote = remote
	_maid = maid
	Controller.IsActive = true

	-- Pedir el estado inicial: el jugador puede haber abierto cofres en una
	-- sesión anterior, y la UI debe reflejarlo sin que tenga que abrir uno.
	requestInitialOffer()

	-- Escuchar la apertura de cofres: el servidor publica `ChestJustOpened`
	-- cuando un ProximityPrompt se dispara con éxito.
	if _maid then
		_maid:Connect(player:GetAttributeChangedSignal("ChestJustOpened"), function()
			local chestKey = player:GetAttribute("ChestJustOpened")
			if type(chestKey) == "string" and chestKey ~= "" then
				handleChestNotification(player)
			end
		end)
	end

	-- Escuchar habilidades nuevas por separado: el servidor también publica
	-- `SkillUnlockedId` directamente, y este handler cubre el caso en que
	-- la notificación no viaje por `ChestJustOpened` (p. ej. carga inicial).
	if _maid then
		_maid:Connect(player:GetAttributeChangedSignal("SkillUnlockedId"), function()
			local skillId = player:GetAttribute("SkillUnlockedId")
			if type(skillId) == "string" and skillId ~= "" then
				handleChestNotification(player)
			end
		end)
	end

	Logger.Info("ChestController listo (escaneando cofres cercanos).")
	return true
end

--- Desactiva el controller y libera referencias.
--- @return boolean success
function Controller.Destroy(): boolean
	Controller.IsActive = false
	_chestRemote = nil
	_maid = nil
	return true
end

return Controller
