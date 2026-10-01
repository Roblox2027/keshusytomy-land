--!strict
--[[
	TestHarness
	Micro framework de pruebas: describe / it / expect.

	Por que existe (FASE 1):
	El proyecto necesita pruebas REALES ejecutables sin depender de
	Roblox Studio ni de TestEZ. Este modulo no usa ningun servicio de
	Roblox, por lo que corre igual con:

		- luau.exe (validacion local / CI)
		- TestEZ dentro de Studio (si se integra mas adelante)

	Regla del proyecto: una prueba que no comprueba nada real no vale.
	Por eso `expect` falla de verdad y el proceso devuelve codigo != 0.
]]

local Harness = {}

export type Failure = {
	Suite: string,
	Test: string,
	Message: string,
}

Harness.suites = {}
Harness.passed = 0
Harness.failed = 0
Harness.failures = {}
Harness._currentSuite = nil

--- Agrupa pruebas.
--- @param name string
--- @param body () -> ()
function Harness.describe(name: string, body: () -> ())
	local previous = Harness._currentSuite
	Harness._currentSuite = name

	local ok, err = pcall(body)
	if not ok then
		Harness.failed += 1
		table.insert(Harness.failures, {
			Suite = name,
			Test = "(suite)",
			Message = tostring(err),
		})
	end

	Harness._currentSuite = previous
end

--- Declara una prueba. Un error dentro cuenta como fallo, no como exito.
--- @param name string
--- @param body () -> ()
function Harness.it(name: string, body: () -> ())
	local ok, err = pcall(body)

	if ok then
		Harness.passed += 1
	else
		Harness.failed += 1
		table.insert(Harness.failures, {
			Suite = Harness._currentSuite or "(sin suite)",
			Test = name,
			Message = tostring(err),
		})
	end
end

--- Afirmaciones. Fallan lanzando un error con mensaje explicito.
Harness.expect = {}

--- @param value any
function Harness.expect.toBeTruthy(value: any)
	if not value then
		error(("se esperaba un valor verdadero, se obtuvo %s"):format(tostring(value)), 2)
	end
end

--- @param value any
function Harness.expect.toBeFalsy(value: any)
	if value then
		error(("se esperaba un valor falso, se obtuvo %s"):format(tostring(value)), 2)
	end
end

--- @param actual any
--- @param expected any
function Harness.expect.toBe(actual: any, expected: any)
	if actual ~= expected then
		error(("se esperaba %s, se obtuvo %s"):format(tostring(expected), tostring(actual)), 2)
	end
end

--- @param actual number
--- @param expected number
--- @param tolerance number?
function Harness.expect.toBeClose(actual: number, expected: number, tolerance: number?)
	local margin = tolerance or 1e-6
	if math.abs(actual - expected) > margin then
		error(("se esperaba ~%s, se obtuvo %s"):format(tostring(expected), tostring(actual)), 2)
	end
end

--- @param haystack string
--- @param needle string
function Harness.expect.toContain(haystack: string, needle: string)
	if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
		error(("se esperaba que %s contuviera %q"):format(tostring(haystack), needle), 2)
	end
end

--- Indica si una funcion lanzo un error.
--- @param fn () -> ()
--- @return boolean threw
--- @return string? message
function Harness.expect.toThrow(fn: () -> ()): (boolean, string?)
	local ok, err = pcall(fn)
	if ok then
		return false
	end
	return true, tostring(err)
end

--- Imprime el informe y devuelve el codigo de salida del proceso.
--- @return number exitCode
function Harness.report(): number
	print(("="):rep(56))
	print(("PRUEBAS: %d pasaron | %d fallaron"):format(Harness.passed, Harness.failed))
	print(("="):rep(56))

	for _, failure in Harness.failures do
		print(("FAIL  [%s] %s"):format(failure.Suite, failure.Test))
		print(("      %s"):format(failure.Message))
	end

	if Harness.failed == 0 then
		print("RESULTADO: PASS")
		return 0
	end

	print("RESULTADO: FAIL")
	return 1
end

return Harness