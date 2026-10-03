-- payload-guard.lua
-- Prueba el PayloadGuard REAL dentro del servidor en ejecucion.
--
-- No lee el repositorio: hace `require` del ModuleScript que Studio tiene
-- cargado y le pasa los mismos vectores de ataque que cubren las pruebas.
-- Si el modulo no estuviera desplegado, el `require` falla y el probe lo
-- dice, en vez de devolver un PASS por leer un archivo.
local out = {}
local function line(s) out[#out + 1] = tostring(s) end

local libs = game:GetService("ReplicatedStorage").Shared.Libraries
local module = libs:FindFirstChild("PayloadGuard")

if not module then
	return "FALLO: PayloadGuard no existe en el runtime de Studio."
end

local ok, Guard = pcall(require, module)

if not ok or type(Guard) ~= "table" then
	return "FALLO: no se pudo cargar PayloadGuard: " .. tostring(Guard)
end

line("PayloadGuard cargado desde el runtime real.")

local function check(name, got, want)
	local pass = (got == want)
	line((pass and "  PASA  " or "  FALLA ") .. name .. "  -> " .. tostring(got))
	return pass
end

local passed, failed = 0, 0
local function record(okBool)
	if okBool then passed += 1 else failed += 1 end
end

-- 1. NaN: para Luau es un numero, asi que el paso 6 del gateway lo deja
--    pasar. Esta es exactamente la costura que cubre PayloadGuard.
record(check("NaN rechazado", Guard.IsFiniteNumber(0 / 0), false))
record(check("infinito rechazado", Guard.IsFiniteNumber(math.huge), false))
record(check("numero normal aceptado", Guard.IsFiniteNumber(1234), true))

-- 2. Cantidad negativa: el ataque clasico de economia.
record(check("negativo fuera de rango", Guard.CoerceNumber(-1, 1, 100), nil))
record(check("billon fuera de rango", Guard.CoerceNumber(1e18, 1, 100), nil))

-- 3. Tabla ciclica: si el recorrido no lleva `seen`, esto cuelga el hilo
--    del servidor. Que la prueba termine es en si mismo el resultado.
local cyclic = { Name = "x" }
cyclic.Self = cyclic
local cyclicOk, cyclicReason = Guard.ValidateTableShape(cyclic)
record(check("tabla ciclica rechazada", cyclicOk, false))
line("    motivo: " .. tostring(cyclicReason))

-- 4. Cadena gigante con codigo de control (inyeccion en el log).
local nasty = "Item\nAdmin=true"
record(check("codigo de control rechazado", (Guard.IsIdentifier(nasty)), false))
record(check("cadena de 5000 rechazada", (Guard.IsIdentifier(string.rep("A", 5000))), false))

-- 5. Lista blanca: un campo extra se rechaza aunque nadie lo lea.
local allowed = { ItemId = true }
local whiteOk, offending = Guard.RejectUnknownFields({ ItemId = "Bomb", Admin = true }, allowed)
record(check("campo no permitido rechazado", whiteOk, false))
line("    clave offendida: " .. tostring(offending))

-- 6. Aridad.
record(check("aridad incorrecta rechazada", Guard.ValidateArity(2, 1), false))

line(("\nRESUMEN: %d pasaron, %d fallaron"):format(passed, failed))
return table.concat(out, "\n")