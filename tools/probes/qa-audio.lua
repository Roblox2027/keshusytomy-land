-- qa-audio.lua
-- Estado REAL del audio en la sesion de Play.
--
-- Distingue lo que el enunciado exige separar:
--   - ARQUITECTURA: existe el catalogo, el pool decide distancia/cooldown.
--   - ASSETS: hay `SoundId` validos. Sin `id` no hay sonido, por muy correcta
--     que sea la arquitectura.
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local Replicated = game:GetService("ReplicatedStorage")
local AudioConfig = require(Replicated.Shared.Config.AudioConfig)

local Events = AudioConfig.Events
local total = 0
local conId = 0
local sinId = 0
local faltan = {}

for name, def in pairs(Events) do
	total += 1
	local id = def.id
	if type(id) == "string" and id ~= "" then
		conId += 1
	else
		sinId += 1
		table.insert(faltan, name)
	end
end

table.sort(faltan)

-- Sons que existen de verdad en el servidor.
local sonidos = 0
local nombres = {}
for _, inst in ipairs(SoundService:GetDescendants()) do
	if inst:IsA("Sound") then
		sonidos += 1
		if #nombres < 8 then
			table.insert(nombres, inst.Name .. "=" .. tostring(inst.SoundId))
		end
	end
end

local p = Players:GetPlayers()[1]

return string.format(
	"eventos declarados=%d | con SoundId=%d | SIN SoundId=%d\nSounds vivos en SoundService=%d %s\nprimeros eventos sin id: %s",
	total,
	conId,
	sinId,
	sonidos,
	table.concat(nombres, ", "),
	table.concat(faltan, ", ")
)