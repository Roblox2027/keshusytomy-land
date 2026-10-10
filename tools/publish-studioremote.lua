-- publish-studioremote.lua
-- Publica el lugar actual de Studio a Roblox usando PublishService.
-- Si el lugar no esta publicado (PlaceId = 0), crea uno nuevo.

local PublishService = game:GetService("PublishService")
local HttpService = game:GetService("HttpService")

local result = {
	success = false,
	placeId = game.PlaceId,
	gameId = game.GameId,
	message = "",
}

-- Si el lugar ya esta publicado, solo actualiza la version guardada.
if game.PlaceId ~= 0 then
	result.message = "El lugar ya esta publicado con PlaceId=" .. game.PlaceId
	result.success = true
	return result
end

-- El lugar no esta publicado. Intentar publicarlo.
local ok, err = pcall(function()
	PublishService:PublishToRoblox()
end)
result.success = ok
result.message = ok and "Publicado correctamente" or ("Error: " .. tostring(err))

-- Dar tiempo al publish para propagarse.
wait(2)

result.placeId = game.PlaceId
result.gameId = game.GameId

return result
