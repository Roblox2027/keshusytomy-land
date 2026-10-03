-- Comprueba que el codigo REAL del servidor es el nuevo.
--
-- Se `require` el modulo DENTRO del servidor en ejecucion: si el fichero
-- sincronizado no compilara, `require` falla aqui y se ve. Ademas se lee
-- `script.Source` del ModuleScript vivo, que es lo que el servidor esta
-- ejecutando de verdad (no lo que hay en el repositorio).
local out = {}

local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
local mod = services and services:FindFirstChild("MonsterService")

if not mod then
	return { error = "MonsterService no encontrado" }
end

local source = ""
-- `Source` no es legible desde el runtime del servidor (Roblox lo restringe al
-- plugin), asi que no se intenta: la prueba de que el codigo es el nuevo la
-- dan `require` (que evalua el fichero real) y el comportamiento medido.
local ok, result = pcall(require, mod)
out.requireOk = ok
out.requireError = if ok then nil else tostring(result)

if ok then
	local ai = require(game:GetService("ReplicatedStorage").Shared.Libraries.AIService)

	-- Se registra la FORMA de lo que se ha cargado, no un valor concreto: si
	-- el servidor tiene la version vieja cacheada, `States` es una cadena
	-- (la firma del `return "AIService"` accidental) o directamente nil, y el
	-- diagnostico lo dice sin romperse en la primera llamada a una funcion.
	out.aiType = type(ai)
	out.aiKeys = {}

	if type(ai) == "table" then
		for key in pairs(ai) do
			out.aiKeys[#out.aiKeys + 1] = tostring(key)
		end
		table.sort(out.aiKeys)

		out.hasStates = ai.States ~= nil
		out.hasThink = type(ai.Think) == "function"
		out.hasGetPlayerSpeed = type(ai.GetPlayerSpeed) == "function"

		if out.hasGetPlayerSpeed then
			out.playerSpeed = ai.GetPlayerSpeed()
			out.maxChase = ai.MaxChaseSpeed()
			out.maxCharge = ai.MaxChargeSpeed()
		end

		local defs = require(game:GetService("ReplicatedStorage").Shared.MonsterDefinitions)
		out.balanceProblems = defs.GetBalanceProblems()
	end

	-- Tabla de velocidades por monstruo: la cifra que decide si el juego es
	-- jugable o si el enemigo es imbatible.
	out.chase = {}
	for _, id in ipairs(require(game:GetService("ReplicatedStorage").Shared.MonsterDefinitions).GetIds()) do
		local d = require(game:GetService("ReplicatedStorage").Shared.MonsterDefinitions).Get(id)
		out.chase[id] = ("patrol %.1f / chase %.1f / charge %.1f / aviso %.1fs")
			:format(d.PatrolSpeed, d.ChaseSpeed, d.ChargeSpeed, d.WarningTime)
	end
end

return out