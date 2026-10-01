--!strict
--[[
    EconomyService
    Saldo de monedas y transiciones economicas validadas en servidor.

    FASE 0 - Bootstrap: interfaz declarada, sin implementar.
    La implementacion se realiza por fases, cuando existan las
    dependencias minimas que cada servicio necesita.
]]

local Service = {}

--- Indica si Init ya se ejecuto correctamente.
Service.IsInitialized = false

--- Inicializacion del servicio. Debe ser idempotente.
--- @return boolean success
function Service.Init(): boolean
    -- FASE 1+ : preparar estado propio y conexiones de eventos.
    Service.IsInitialized = true
    return true
end

--- Limpieza del servicio. Debe detener todo lo iniciado en Init.
--- @return boolean success
function Service.Destroy(): boolean
    Service.IsInitialized = false
    return true
end

return Service
