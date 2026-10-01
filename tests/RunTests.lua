--!strict
--[[
	RunTests.lua
	Punto de entrada de la suite de pruebas local (FASE 1).

	Ejecucion (desde la raiz del repositorio):
		luau.exe tests/RunTests.lua

	Los modulos de `src/` que dependen de ReplicatedStorage se cargan
	con el arbol simulado de `tests/MockEnvironment.lua`. Lo que solo
	se puede probar dentro de Roblox Studio (Workspace, Players,
	DataStore, fisica) NO se marca PASS aqui: queda BLOCKED y se
	documenta como pendiente de verificacion manual.
]]

local Harness = require("./TestHarness")

-- Las rutas son relativas a este archivo (tests/), no a la raiz.
local SUITES = {
	{ name = "Maid", path = "./shared/Maid.spec" },
	{ name = "RateLimiter", path = "./shared/RateLimiter.spec" },
	{ name = "StateMachine", path = "./shared/StateMachine.spec" },
	{ name = "RemoteSchema", path = "./shared/RemoteSchema.spec" },
	{ name = "GameConfig", path = "./shared/GameConfig.spec" },
}

local loadedSuites = 0

for _, suite in SUITES do
	local ok, result = pcall(require, suite.path)

	if not ok then
		Harness.failed += 1
		table.insert(Harness.failures, {
			Suite = suite.name,
			Test = "(carga de la suite)",
			Message = tostring(result),
		})
	else
		loadedSuites += 1
		-- Cada spec devuelve una funcion que registra sus pruebas.
		result()
	end
end

print(("Suites cargadas: %d de %d"):format(loadedSuites, #SUITES))

local exitCode = Harness.report()

-- `os.exit` no esta disponible en todas las versiones del interprete
-- standalone. Si existe, se usa para propagar el codigo de salida a
-- CI; si no, el resultado se lee directamente en la salida.
if type(os.exit) == "function" then
	os.exit(exitCode)
end