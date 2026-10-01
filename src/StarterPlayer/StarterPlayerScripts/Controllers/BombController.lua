--!strict
--[[
    BombController
    Peticion de colocacion de bomba. El servidor decide si es valida.

    FASE 0 - Bootstrap: interfaz declarada, sin implementar.
    Un Controller tiene una unica responsabilidad y nunca
    duplica la logica de otro Controller.
]]

local Controller = {}

--- Indica si el controller esta activo.
Controller.IsActive = false

--- Activa el controller. Debe ser idempotente y reversible con Destroy.
--- @return boolean success
function Controller.Start(): boolean
    -- FASE 1+ : conectar eventos de entrada con limitacion de frecuencia.
    Controller.IsActive = true
    return true
end

--- Desactiva el controller y elimina todas sus conexiones.
--- @return boolean success
function Controller.Destroy(): boolean
    Controller.IsActive = false
    return true
end

return Controller
