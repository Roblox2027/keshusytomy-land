--!strict
--[[
	TestDriverService
	Lado SERVIDOR del reproductor de pruebas del cliente.

	QUE ES Y QUE NO ES
	------------------
	ES: el mecanismo que permite pedirle al cliente que ejecute una
	intencion de jugador, para certificar `CLIENT INPUT PATH VERIFIED`
	cuando el MCP no puede enviar teclas al cliente.

	NO ES: una puerta trasera de funcionalidad. El servicio no coloca
	bombas, no teletransporta a nadie y no modifica nada del juego. Solo
	fija un atributo, y ese atributo lo lee un LocalScript del cliente
	que luego recorre InputController -> Remote -> Gateway -> servicio.

	POR QUE ES SEGURO
	-----------------
	1. Solo arranca con `ENABLE_CLIENT_TEST_DRIVER`.
	2. Sin esa bandera, `Command()` no hace NADA y devuelve false.
	3. El cliente responde fijando `TestDriverResult`, asi que un PASS
	   se apoya en la respuesta del cliente, no en la intencion del
	   servidor.
	4. El intervalo minimo lo impone el cliente (`TestDriverLogic`), de
	   modo que no se puede usar para martillear el remoto.

	Como consecuencia, marcar `CLIENT INPUT PATH VERIFIED` sigue
	exigiendo ver el resultado en el cliente. Este servicio por si solo
	no certifica nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHARED = ReplicatedStorage:WaitForChild("Shared")
local CONFIG = SHARED:WaitForChild("Config")
local LIBRARIES = SHARED:WaitForChild("Libraries")
local UTILS = SHARED:WaitForChild("Utils")

local FeatureConfig = require(CONFIG:WaitForChild("FeatureConfig"))
local TestDriverLogic = require(LIBRARIES:WaitForChild("TestDriverLogic"))
local Logger = require(UTILS:WaitForChild("Logger"))

local Service = {}

Service.IsInitialized = false
Service.IsRunning = false

local ATTRIBUTE = "TestDriverInstruction"
local RESULT_ATTRIBUTE = "TestDriverResult"

--- Pide al cliente que ejecute una intencion de jugador.
---
--- NO ejecuta la accion en el servidor. Fija un atributo y espera a que
--- el LocalScript del cliente la realice por el camino real.
--- @param player Player destinatario
--- @param action string accion de `TestDriverLogic.Actions`
--- @param worldId string? destino, solo para portales
--- @return boolean dispatched
--- @return string? reason
function Service.Command(player: Player, action: string, worldId: string?): (boolean, string?)
	if not FeatureConfig.ENABLE_CLIENT_TEST_DRIVER then
		return false, "reproductor desactivado por FeatureConfig"
	end

	if type(player) ~= "table" or not player:IsA("Player") then
		return false, "destinatario no valido"
	end

	if not player.Parent then
		return false, "el destinatario ya no esta en el servidor"
	end

	-- El destino viaja DENTRO de la instruccion. El servidor no decide
	-- si el viaje procede: eso lo decide `PortalService` cuando el
	-- cliente llegue a disparar `PortalAction`.
	local encoded = TestDriverLogic.Encode(action, worldId)

	-- El contador permite distinguir una instruccion nueva de una
	-- repetida: si el valor no cambia, no hay evento y el cliente no
	-- se entera.
	player:SetAttribute(ATTRIBUTE .. "Seq", (player:GetAttribute(ATTRIBUTE .. "Seq") or 0) + 1)
	player:SetAttribute(ATTRIBUTE, encoded)
	player:SetAttribute(RESULT_ATTRIBUTE, "PENDIENTE")

	Logger.Info(("TestDriverService: instruccion '%s' enviada a %s"):format(encoded, player.Name))

	return true, nil
end

--- Lee el veredicto que devolvio el cliente.
--- @param player Player
--- @return string? verdict
function Service.GetResult(player: Player): string?
	if type(player) ~= "table" or not player:IsA("Player") then
		return nil
	end

	return player:GetAttribute(RESULT_ATTRIBUTE)
end

--- Cantidad de instrucciones enviadas a un jugador.
--- @param player Player
--- @return number
function Service.GetCommandCount(player: Player): number
	if type(player) ~= "table" or not player:IsA("Player") then
		return 0
	end

	return player:GetAttribute(ATTRIBUTE .. "Seq") or 0
end

--- Inicializacion del servicio. Idempotente.
--- @return boolean success
function Service.Init(): boolean
	if Service.IsInitialized then
		return true
	end

	Service.IsInitialized = true
	return true
end

--- Comienza a permitir comandos de prueba.
--- @return boolean success
function Service.Start(): boolean
	if not Service.IsInitialized then
		return false
	end

	Service.IsRunning = true

	Logger.Info(("TestDriverService: %s"):format(
		FeatureConfig.ENABLE_CLIENT_TEST_DRIVER
			and "activo (reproductor de pruebas habilitado)"
			or "inactivo (ENABLE_CLIENT_TEST_DRIVER = false)"
	))

	return true
end

--- Limpieza del servicio.
--- @return boolean success
function Service.Destroy(): boolean
	-- Se borran los atributos para que ningun cliente quede con una
	-- instruccion pendiente de ejecutar tras parar el servicio.
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute(ATTRIBUTE) then
			player:SetAttribute(ATTRIBUTE, nil)
		end
	end

	Service.IsRunning = false
	Service.IsInitialized = false
	return true
end

return Service