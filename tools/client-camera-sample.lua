-- client-camera-sample.lua
-- Muestra, EN EL MISMO INSTANTE y en el cliente, donde estan la camara y el
-- personaje y cuantas Partes del Lobby se ven desde la camara.
--
-- POR QUE ES UN ARCHIVO Y NO UNA CADENA
-- ------------------------------------
-- El Luau lleva comillas dobles y el camino de Node a Studio las mutila en
-- la linea de comandos. `tools/client-probe.js` y `tools/combat-verify.js`
-- ya usan un archivo aparte por el mismo motivo.
--
-- ESTE SCRIPT NO SE EJECUTA EN EL SERVIDOR
-- ----------------------------------------
-- `workspace.CurrentCamera` solo existe en el cliente. En el servidor daria
-- error, y presentarlo como un fallo de visibilidad seria falso.
--
-- POR QUE NO CUENTA PARTES VISIBLES
-- ---------------------------------
-- La primera version recorria `Lobby:GetDescendants()` llamando a
-- `IsVisibleFrom` en CADA Part, y las cuatro muestras dieron
-- `request_timeout` a los 30 s. `IsVisibleFrom` es una prueba de oclusion
-- REAL y su coste crece rapido; repetirla varias veces en el mismo ciclo lo
-- desborda. El recuento por region de `client-probe.js` ya cubre la
-- visibilidad, asi que aqui no se repite.
--
-- LO QUE SI SE MIDE, Y POR QUE IMPORTA
-- ------------------------------------
-- `client-probe.js facelobby` dio `Lobby 11/98` y despues `Lobby 0/98` en
-- dos ejecuciones seguidas con el mismo mapa, y en una la camara aparecia
-- en y = 56.5 con el personaje en y = 3.
--
-- Hay dos explicaciones muy distintas y esta sonda las separa:
--
--   a) la camara esta de verdad a 53 studs del personaje y el jugador ve
--      otra cosa; o
--   b) la camara va bien y lo que cambia es DONDE esta el personaje,
--      porque el ciclo de ronda lo teletransporta entre medir y medir.
--
-- Si la distancia camara-personaje sale estable y pequena, la camara va
-- bien y el ratio de visibilidad cambia por donde esta el jugador.

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local character = player and player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")

if not camera then
	return { error = "el cliente no tiene CurrentCamera" }
end
if not root then
	return { camara = tostring(camera.CFrame.Position), error = "sin HumanoidRootPart" }
end

return {
	personaje = string.format("%.0f,%.0f,%.0f", root.Position.X, root.Position.Y, root.Position.Z),
	camara = string.format("%.0f,%.0f,%.0f", camera.CFrame.Position.X, camera.CFrame.Position.Y, camera.CFrame.Position.Z),
	tipoCamara = camera.CameraType.Name,
	distanciaCamaraPersonaje = string.format("%.1f", (camera.CFrame.Position - root.Position).Magnitude),
	mira = string.format("%.2f,%.2f,%.2f", camera.CFrame.LookVector.X, camera.CFrame.LookVector.Y, camera.CFrame.LookVector.Z),
	campoVision = string.format("%.0f", camera.FieldOfView),
}