-- fix-starterscripts.lua
-- Corrige `StarterPlayer.StarterPlayerScripts` en Studio.
--
-- Con el proyecto anterior Rojo creo una CARPETA con ese nombre en vez
-- del contenedor real del motor, y colgo de ella `ClientMain` y los 12
-- Controllers. Roblox solo clona el `StarterPlayerScripts` autentico:
-- un Folder con el mismo nombre NO se clona y sus LocalScripts no se
-- ejecutan nunca. El cliente, sencillamente, no arrancaba.
--
-- `Instance.new("StarterPlayerScripts")` no esta permitido, asi que se
-- retira la carpeta erronea y se sube su contenido al contenedor real,
-- que Studio ya tiene y estaba vacio.

local StarterPlayer = game:GetService("StarterPlayer")

local real = StarterPlayer:FindFirstChild("StarterPlayerScripts")
local impostor = nil

for _, child in ipairs(StarterPlayer:GetChildren()) do
	if child.Name == "StarterPlayerScripts" and not child:IsA("StarterPlayerScripts") then
		impostor = child
	end
end

if real == nil then
	return "ERROR: no existe el StarterPlayerScripts real"
end

if impostor == nil then
	return string.format(
		"OK sin cambios: StarterPlayerScripts real con %d hijos",
		#real:GetChildren()
	)
end

local moved = 0
for _, child in ipairs(impostor:GetChildren()) do
	child.Parent = real
	moved += 1
end
impostor:Destroy()

local names = {}
for _, c in ipairs(real:GetChildren()) do
	table.insert(names, c.Name .. "[" .. c.ClassName .. "]")
end

return string.format(
	"CORREGIDO: %d hijos movidos al contenedor real. Ahora: %s",
	moved,
	table.concat(names, ", ")
)
