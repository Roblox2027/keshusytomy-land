-- p0-require-layout.lua
-- ¿Se puede cargar `BombButtonLayout` en el cliente?
--
-- MEDIDO: con el boton en `Position = (0, 0)`, `applyBombButtonLayout` no llego
-- a ejecutarse. La causa mas probable de un `require` que no lanza error
-- visible es que el modulo NO exista en el arbol del cliente en ejecucion: en
-- ese caso queda en `nil` y el codigo que lo usa se detiene en silencio.
--
-- NO se lee `Source`: el hilo de la sonda no tiene permisos de plugin para
-- eso (falla con "lacking capability PluginOrOpenCloud"). El contenido del
-- fuente se comprueba por otra via, con `get_script_source` sobre el arbol de
-- EDICION.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

if not player then
return { error = "sin LocalPlayer" }
end

local libraries = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Libraries")
local layoutModule = libraries:FindFirstChild("BombButtonLayout")

local out = {
moduloExiste = layoutModule ~= nil,
clase = layoutModule and layoutModule.ClassName or "-",
}

local ok, result = pcall(function()
return require(libraries:WaitForChild("BombButtonLayout"))
end)

out.requireOk = ok
out.requireError = nil
out.tieneSizeFor = false
out.tieneResolve = false

if not ok then
out.requireError = tostring(result)
elseif type(result) == "table" then
out.tieneSizeFor = result.SizeFor ~= nil
out.tieneResolve = result.ResolveRightColumn ~= nil
else
out.requireError = "el modulo devolvio " .. type(result)
end

return out