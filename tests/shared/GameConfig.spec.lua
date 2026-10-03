--!strict
--[[
	GameConfig.spec
	Pruebas de integridad de la configuracion.

	Un valor de configuracion invalido (limite 0, duracion negativa,
	flag inexistente) provocaria fallos difiles de diagnosticar mas
	adelante. Aqui se falla temprano.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

-- GameConfig es un modulo sin dependencias: se carga directamente.
local GameConfig = require("../../src/ReplicatedStorage/Shared/Config/GameConfig")
local PerformanceConfig = require("../../src/ReplicatedStorage/Shared/Config/PerformanceConfig")
local FeatureConfig = require("../../src/ReplicatedStorage/Shared/Config/FeatureConfig")
local AudioConfig = require("../../src/ReplicatedStorage/Shared/Config/AudioConfig")

local function isPositiveNumber(value: any): boolean
	return type(value) == "number" and value > 0
end

local function describeGameConfig()
	Harness.describe("GameConfig", function()
		Harness.it("tiene identidad y version", function()
			expect.toBe(GameConfig.GameName, "KeshusyTomy-LanD")
			expect.toBe(type(GameConfig.GameVersion), "string")
			expect.toContain(GameConfig.GameVersion, ".")
			expect.toBe(type(GameConfig.DataVersion), "number")
		end)

		Harness.it("las duraciones de ronda son positivas", function()
			expect.toBe(isPositiveNumber(GameConfig.RoundDuration), true)
			expect.toBe(isPositiveNumber(GameConfig.CountdownDuration), true)
			expect.toBe(isPositiveNumber(GameConfig.SuddenDeathTime), true)
		end)

		Harness.it("el juego es multipropÃƒÂ³sito: duraciones utilizables", function()
			expect.toBe(GameConfig.RoundDuration > GameConfig.CountdownDuration, true)
		end)

		Harness.it("las configuraciones de dominio son modulos separados", function()
			-- Cada dominio tiene su propio archivo: no se concentra
			-- toda la configuracion en un unico modulo gigante.
			expect.toBe(type(PerformanceConfig.Limits), "table")
			expect.toBe(type(FeatureConfig.ENABLE_FOREST), "boolean")
			expect.toBe(GameConfig.Performance, nil)
		end)
	end)

	Harness.describe("PerformanceConfig", function()
		Harness.it("todos los limites son enteros positivos", function()
			for name, value in PerformanceConfig.Limits do
				expect.toBe(isPositiveNumber(value), true)
				expect.toBe(value == math.floor(value), true)
				if not isPositiveNumber(value) then
					error(("limite invalido: %s = %s"):format(name, tostring(value)))
				end
			end
		end)

		Harness.it("hay presupuesto para cada categoria del documento", function()
			local limits = PerformanceConfig.Limits
			for _, key in {
				"MaxPlayers",
				"MaxMonsters",
				"MaxBombs",
				"MaxExplosions",
				"MaxProjectiles",
				"MaxVFX",
				"MaxParticles",
				"MaxTempInstances",
			} do
				expect.toBe(isPositiveNumber(limits[key]), true)
			end
		end)

		Harness.it("los limites por jugador son mas bajos que los globales", function()
			local limits = PerformanceConfig.Limits
			expect.toBe(limits.MaxBombsPerPlayer < limits.MaxBombs, true)
			expect.toBe(limits.MaxProjectilesPerPlayer < limits.MaxProjectiles, true)
			expect.toBe(limits.MaxMonstersPerPlayer < limits.MaxMonsters, true)
		end)

		Harness.it("los intervalos de muestreo son positivos", function()
			expect.toBe(isPositiveNumber(PerformanceConfig.MetricsSampleInterval), true)
			expect.toBe(isPositiveNumber(PerformanceConfig.MonitorInterval), true)
			expect.toBe(isPositiveNumber(PerformanceConfig.AutoSaveInterval), true)
			expect.toBe(isPositiveNumber(PerformanceConfig.IdleCheckInterval), true)
		end)
	end)

	Harness.describe("FeatureConfig", function()
		Harness.it("declara los interruptores de mundo y modo del documento", function()
			for _, flag in {
				"ENABLE_FOREST",
				"ENABLE_DESERT",
				"ENABLE_ICE",
				"ENABLE_VOLCANO",
				"ENABLE_CYBER",
				"ENABLE_RANKED",
				"ENABLE_BOSS_RUSH",
				"ENABLE_EVENTS",
				"ENABLE_NEW_SHOP",
			} do
				expect.toBe(type(FeatureConfig[flag]), "boolean")
			end
		end)

		Harness.it("la monetizacion esta apagada en desarrollo", function()
			-- Regla de seguridad: no se procesan compras reales en dev.
			expect.toBe(FeatureConfig.ENABLE_MONETIZATION, false)
		end)

		-- Esta prueba SOSTIENE el contrato de los cinco mundos, asi que se
		-- actualiza junto con `FeatureConfig`. Antes afirmaba que Forest era
		-- el unico habilitado: era una verdad sobre un mundo vacio, no una
		-- regla del juego. Los cinco tienen arena construida, asi que los
		-- cinco han de estar habilitados y los cinco han de ser `true`.
		Harness.it("los cinco mundos estan habilitados", function()
			expect.toBe(FeatureConfig.ENABLE_FOREST, true)
			expect.toBe(FeatureConfig.ENABLE_DESERT, true)
			expect.toBe(FeatureConfig.ENABLE_ICE, true)
			expect.toBe(FeatureConfig.ENABLE_VOLCANO, true)
			expect.toBe(FeatureConfig.ENABLE_CYBER, true)
		end)
	end)

	Harness.describe("AudioConfig", function()
		-- Estos campos son la lista de sonidos que el juego pide. Estar en
		-- `nil` significa "aun no hay asset subido", y el controller lo
		-- trata como silencio en vez de inventarse un ID. La prueba fija
		-- esa regla: si alguien pega un numero, tiene que ser un ID de
		-- verdad, no unplaceholder.
		local SFX_FIELDS = {
			"BombPlaceId",
			"BombFuseId",
			"ExplosionId",
			"BlockDestroyId",
			"PlayerHurtId",
			"PlayerDeathId",
			"PowerUpId",
			"RoundStartId",
			"RoundWinId",
			"CoinRewardId",
			"CoreIdleId",
			"CoreChargeId",
			"CoreActivateId",
			"PortalOpenId",
			"PortalDeniedId",
			"UiClickId",
			"UiConfirmId",
		}

		Harness.it("cada efecto es nil o un ID numerico real", function()
			for _, field in ipairs(SFX_FIELDS) do
				local value = AudioConfig[field]

				-- `nil` es valido: significa que aun no se ha subido.
				if value ~= nil then
					expect.toBe(type(value), "string")
					-- Un ID de Roblox son digitos. Cualquier otra cosa
					-- (un nombre, un "placeholder", un 0) haria que el
					-- cliente pidiera un asset inexistente en cada
					-- explosion.
					expect.toBe(
						tostring(value):match("^%d+$") ~= nil,
						true
					)
				end
			end
		end)

		Harness.it("declara los cinco mundos del contrato", function()
			-- Anadir un mundo no puede obligar a tocar el audio: la clave
			-- tiene que EXISTIR aunque el mundo aun no tenga musica. Por eso
			-- se comprueba la presencia de la clave, no su valor.
			for _, worldId in ipairs({ "Forest", "Desert", "Ice", "Volcano", "Cyber" }) do
				local found = false
				for key in pairs(AudioConfig.WorldMusic) do
					if key == worldId then
						found = true
						break
					end
				end
				expect.toBe(found, true)
				-- `false` = declarado pero sin musica subida. `nil` = la
				-- entrada no existe, que si seria un fallo.
				expect.toBe(AudioConfig.WorldMusic[worldId], false)
			end
		end)

		Harness.it("los volumenes estan en rango y el de efectos por encima", function()
			expect.toBe(AudioConfig.MusicVolume > 0 and AudioConfig.MusicVolume <= 1, true)
			expect.toBe(AudioConfig.SfxVolume > 0 and AudioConfig.SfxVolume <= 1, true)
			-- La musica no debe tapar los efectos: son los que dan
			-- feedback de gameplay.
			expect.toBe(AudioConfig.SfxVolume > AudioConfig.MusicVolume, true)
		end)

		Harness.it("el pool de efectos tiene un tope util", function()
			-- Sin tope, una cadena de explosiones abre un `Sound` por
			-- detonacion. Y un tope de 0 dejaria el juego mudo siempre.
			expect.toBe(AudioConfig.MaxConcurrentSfx >= 4, true)
			expect.toBe(AudioConfig.MaxConcurrentSfx <= 64, true)
		end)

		Harness.it("el fundido de musica es lo bastante corto para no molestar", function()
			expect.toBe(isPositiveNumber(AudioConfig.MusicFadeTime), true)
			expect.toBe(AudioConfig.MusicFadeTime <= 5, true)
		end)
	end)
end

return describeGameConfig