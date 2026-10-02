// Seguridad del Keshusy Core contra un cliente hostil.
//
// Comprueba, en el servidor REAL, que:
//   A) un fragmento lejos del nucleo se rechaza,
//   B) junto al nucleo se acepta y suma la carga de la CONFIGURACION,
//   C) el envio inmediato se rechaza por recarga,
//   D) el canal remoto no admite ningun payload del cliente.
const mcp = require("./mcp");

const CODE = `
local out = {}
local Players = game:GetService("Players")
local core = require(game:GetService("ServerScriptService").Services.CoreService)

local player = Players:GetPlayers()[1]
if not player then
	return "SIN JUGADOR"
end

local function moveTo(target)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	root.CFrame = CFrame.new(target)
	return true
end

out[#out + 1] = "jugador=" .. player.Name
out[#out + 1] = "pos nucleo=" .. tostring(core.GetPosition())
out[#out + 1] = "rango=" .. tostring(core.INTERACT_RANGE)

-- A) Lejos del nucleo: el rango debe impedir el fragmento.
local corePos = core.GetPosition()
moveTo(corePos + Vector3.new(0, 0, 500))
task.wait(0.3)

local chargeBefore = core.GetState().Charge
local okFar, reasonFar = core.TryAddFragmentFor(player)
out[#out + 1] = "A) lejos -> ok=" .. tostring(okFar) .. " motivo=" .. tostring(reasonFar)
out[#out + 1] = "   carga=" .. tostring(core.GetState().Charge) .. " (antes=" .. tostring(chargeBefore) .. ")"

-- B) Junto al nucleo: debe aceptarse.
moveTo(corePos)
task.wait(0.3)

local okNear, reasonNear = core.TryAddFragmentFor(player)
out[#out + 1] = "B) junto -> ok=" .. tostring(okNear) .. " motivo=" .. tostring(reasonNear)
out[#out + 1] = "   carga=" .. tostring(core.GetState().Charge) .. "/" .. tostring(core.GetState().MaxCharge)

-- C) Inmediatamente despues: la recarga debe rechazar.
local okFast, reasonFast = core.TryAddFragmentFor(player)
out[#out + 1] = "C) seguido -> ok=" .. tostring(okFast) .. " motivo=" .. tostring(reasonFast)
out[#out + 1] = "   carga=" .. tostring(core.GetState().Charge)

-- D) El canal no admite payload numerico ni tabla.
local RS = game:GetService("ReplicatedStorage").Shared
local schemaLib = require(RS.Libraries.RemoteSchema)
local GC = require(RS.Constants.GameConstants)
local schema = schemaLib.new(GC.RemoteAction)
local validate = schemaLib.ValidatePayload

out[#out + 1] = "D) payload numero -> " .. tostring(validate("Ninguno", 9999))
out[#out + 1] = "D) payload tabla -> " .. tostring(validate("Ninguno", { charge = 1000 }))
out[#out + 1] = "D) sin payload -> " .. tostring(validate("Ninguno", nil))

-- E) Lo que suma un fragmento lo decide la CONFIG, no el cliente.
local cfg = require(RS.Config.GameConfig)
out[#out + 1] = "E) carga por fragmento=" .. tostring(cfg.CoreChargePerFragment)
out[#out + 1] = "E) aumento real=" .. tostring(core.GetState().Charge - chargeBefore)

return table.concat(out, "\\n")
`;

(async () => {
	await mcp.init();
	// `serverLuau` y no `tool("execute_luau")`: el codigo del servidor
	// debe ejecutarse en el PEER del servidor. Con `tool` corria en otro
	// contexto y `Players:GetPlayers()` salia vacio, lo que hacia pensar
	// que no habia jugador cuando si lo habia (lo que si ve boot-state,
	// que usa serverLuau).
	const r = await mcp.serverLuau(CODE);
	console.log(r || JSON.stringify(r));
})().catch((e) => console.log("ERR " + e.message));