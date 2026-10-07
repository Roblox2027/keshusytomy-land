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
	{ name = "CoreRules", path = "./shared/CoreRules.spec" },
	{ name = "RemoteSchema", path = "./shared/RemoteSchema.spec" },
	{ name = "PayloadGuard", path = "./shared/PayloadGuard.spec" },
	{ name = "CodeRules", path = "./shared/CodeRules.spec" },
	{ name = "CodeCatalog", path = "./shared/CodeCatalog.spec" },
	{ name = "QuestRules", path = "./shared/QuestRules.spec" },
	{ name = "QuestDaily", path = "./shared/QuestDaily.spec" },
	{ name = "QuestCatalog", path = "./shared/QuestCatalog.spec" },
	{ name = "AntiExploit", path = "./shared/AntiExploit.spec" },
	{ name = "PartyRules", path = "./shared/PartyRules.spec" },
	{ name = "GameConfig", path = "./shared/GameConfig.spec" },
	{ name = "AudioPool", path = "./shared/AudioPool.spec" },
	{ name = "AudioRules", path = "./shared/AudioRules.spec" },
	{ name = "CombatMath", path = "./shared/CombatMath.spec" },
	{ name = "Profile", path = "./shared/Profile.spec" },
	{ name = "ProfileCodes", path = "./shared/ProfileCodes.spec" },
	{ name = "Inventory", path = "./shared/Inventory.spec" },
	{ name = "Shop", path = "./shared/Shop.spec" },
	{ name = "Progression", path = "./shared/Progression.spec" },
	{ name = "Economy", path = "./shared/Economy.spec" },
	{ name = "Destruction", path = "./shared/Destruction.spec" },
	{ name = "BombButton", path = "./shared/BombButton.spec" },
	{ name = "BombPlacement", path = "./shared/BombPlacement.spec" },
	{ name = "BombCapacity", path = "./shared/BombCapacity.spec" },
	{ name = "HudLayout", path = "./shared/HudLayout.spec" },
	{ name = "BlockRespawn", path = "./shared/BlockRespawn.spec" },
	{ name = "Gameplay", path = "./shared/Gameplay.spec" },
	{ name = "WorldBounds", path = "./shared/WorldBounds.spec" },
	{ name = "RoundLifecycle", path = "./shared/RoundLifecycle.spec" },
	{ name = "RoundArenaRouting", path = "./shared/RoundArenaRouting.spec" },
	{ name = "ServiceStructure", path = "./shared/ServiceStructure.spec" },
	{ name = "BootWiring", path = "./shared/BootWiring.spec" },
	{ name = "AIService", path = "./shared/AIService.spec" },
	{ name = "MonsterScale", path = "./shared/MonsterScale.spec" },
	{ name = "MonsterDeath", path = "./shared/MonsterDeath.spec" },
	{ name = "MonsterBalance", path = "./shared/MonsterBalance.spec" },
	{ name = "TestDriverLogic", path = "./shared/TestDriverLogic.spec" },
	{ name = "WorldAccess", path = "./shared/WorldAccess.spec" },
	{ name = "NightCycle", path = "./shared/NightCycle.spec" },
	{ name = "Difficulty", path = "./shared/Difficulty.spec" },
	{ name = "Horde", path = "./shared/Horde.spec" },
	{ name = "Events", path = "./shared/Events.spec" },
	{ name = "MiniBoss", path = "./shared/MiniBoss.spec" },
	{ name = "SecretRules", path = "./shared/SecretRules.spec" },
	{ name = "ZonePopulation", path = "./shared/ZonePopulation.spec" },
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
