--!strict
--[[
	Profile.spec
	Pruebas del esquema del perfil, su sanitizado y su serializabilidad.

	El caso que mas importa es "un perfil roto CON DATOS no se tira".
	Un perfil incompleto al que se le crea uno encima pierde el
	inventario del jugador. Estas pruebas lo fijan como comportamiento
	obligatorio.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local ProfileSchema = require("../../src/ReplicatedStorage/Shared/Libraries/ProfileSchema")

return function()
	Harness.describe("Profile: perfil nuevo", function()
		Harness.it("tiene TODAS las secciones presentes", function()
			local profile = ProfileSchema.NewProfile(1)

			-- La seccion vacia sigue estando: ausente y vacia obligan a
			-- todos los lectores a preguntar "ya existe?".
			for _, section in ipairs(ProfileSchema.Sections) do
				expect.toBe(type(profile[section]), "table")
			end
		end)

		Harness.it("empieza en la version actual", function()
			local profile = ProfileSchema.NewProfile(1)
			expect.toBe(profile.DataVersion, ProfileSchema.CurrentVersion)
		end)

		Harness.it("un perfil nuevo es valido", function()
			local valid = ProfileSchema.Validate(ProfileSchema.NewProfile(1))
			expect.toBe(valid, true)
		end)

		Harness.it("empieza con cero saldo y sin items", function()
			local EconomyRules = require("../../src/ReplicatedStorage/Shared/Libraries/EconomyRules")
			local profile = ProfileSchema.NewProfile(1)

			-- El saldo se consulta por la economia, no leyendo el campo a
			-- mano: leerlo a mano fijaria en la prueba una forma interna que
			-- la economia es la que define.
			expect.toBe(EconomyRules.GetBalance(profile.Currencies, "Coins"), 0)
			expect.toBe(EconomyRules.GetBalance(profile.Currencies, "Gems"), 0)
			expect.toBe(next(profile.Inventory.Items), nil)
		end)
	end)

	Harness.describe("Profile: validacion y sanitizado", function()
		Harness.it("rechaza algo que no es una tabla", function()
			local valid, problems = ProfileSchema.Validate("no soy un perfil")
			expect.toBe(valid, false)
			expect.toBe(#problems > 0, true)
		end)

		Harness.it("rechaza un perfil al que le falta una seccion", function()
			local profile = ProfileSchema.NewProfile(1)
			profile.Inventory = nil

			local valid = ProfileSchema.Validate(profile)
			expect.toBe(valid, false)
		end)

		Harness.it("NO tira un perfil roto que TIENE datos", function()
			-- El caso critico: inventario perdido por un campo que falta.
			local profile = ProfileSchema.NewProfile(1)
			profile.Inventory = { Items = { Hat_Keshusy = { Quantity = 1 } } }
			profile.Settings = nil

			local sanitized, problems, repaired = ProfileSchema.Sanitize(profile, 1)

			expect.toBe(repaired, true)
			-- Lo que se mantiene: el inventario del jugador.
			expect.toBe(sanitized.Inventory.Items.Hat_Keshusy.Quantity, 1)
			-- Lo que se repara: la seccion que faltaba.
			expect.toBe(type(sanitized.Settings), "table")
			expect.toBe(#problems > 0, true)
		end)

		Harness.it("crea uno nuevo si el perfil estaba VACIO", function()
			-- Aqui no hay nada que perder, asi que empezar de cero es
			-- correcto y es lo unico sensato.
			local empty = { DataVersion = 1 }
			local sanitized, _, repaired = ProfileSchema.Sanitize(empty, 1)

			expect.toBe(repaired, true)
			expect.toBe(type(sanitized.Currencies.Balances), "table")
		end)

		Harness.it("un perfil saneado SIEMPRE es valido", function()
			local broken = { DataVersion = 1, Currencies = { Coins = 50 } }
			local sanitized = ProfileSchema.Sanitize(broken, 1)
			expect.toBe((ProfileSchema.Validate(sanitized)), true)
		end)
	end)

	Harness.describe("Profile: serializabilidad", function()
		Harness.it("acepta un perfil normal", function()
			local serializable = ProfileSchema.IsSerializable(ProfileSchema.NewProfile(1))
			expect.toBe(serializable, true)
		end)

		Harness.it("rechaza una funcion dentro", function()
			-- Un perfil con una funcion NO se puede guardar en un
			-- DataStore, y el error que da Roblox no dice ni que ni donde.
			local profile = ProfileSchema.NewProfile(1)
			profile.Settings.OnChange = function() end

			local serializable, reason = ProfileSchema.IsSerializable(profile)
			expect.toBe(serializable, false)
			expect.toContain(tostring(reason), "funcion")
		end)

		Harness.it("rechaza un NaN o un infinito", function()
			local profile = ProfileSchema.NewProfile(1)
			profile.Currencies.Coins = 0 / 0
			expect.toBe((ProfileSchema.IsSerializable(profile)), false)

			profile.Currencies.Coins = math.huge
			expect.toBe((ProfileSchema.IsSerializable(profile)), false)
		end)

		Harness.it("rechaza un ciclo", function()
			-- Una tabla que se contiene a si misma cuelga el serializador.
			local profile = ProfileSchema.NewProfile(1)
			profile.Settings.Loop = profile.Settings

			expect.toBe((ProfileSchema.IsSerializable(profile)), false)
		end)
	end)

	Harness.describe("Profile: compatibilidad con las reglas", function()
		Harness.it("un perfil nuevo tiene la forma que espera la economia", function()
			-- Este es un contrato entre DOS modulos, y por eso se prueba
			-- aqui y no dentro de `EconomyRules`: si `NewProfile` volviera a
			-- usar `{ Coins = 0 }`, la economia rechazaria TODAS sus
			-- operaciones con "estado invalido" y el jugador tendria saldo
			-- cero para siempre, sin ningun error visible.
			local EconomyRules = require("../../src/ReplicatedStorage/Shared/Libraries/EconomyRules")
			local profile = ProfileSchema.NewProfile(1)

			expect.toBe(type(profile.Currencies.Balances), "table")
			expect.toBe(EconomyRules.GetBalance(profile.Currencies, "Coins"), 0)

			-- Y debe poder usarse: una escritura sobre la seccion del perfil
			-- tiene que llegar a la economia.
			local ok = EconomyRules.Grant(profile.Currencies, "Coins", 100, "test", "test")
			expect.toBe(ok, true)
			expect.toBe(EconomyRules.GetBalance(profile.Currencies, "Coins"), 100)
		end)

		Harness.it("un perfil nuevo tiene la forma que espera el inventario", function()
			local InventoryRules = require("../../src/ReplicatedStorage/Shared/Libraries/InventoryRules")
			local ItemCatalog = require("../../src/ReplicatedStorage/Shared/Config/ItemCatalog")
			local profile = ProfileSchema.NewProfile(1)

			local inventory = InventoryRules.new(ItemCatalog)
			local ok = inventory:AddItem(profile.Inventory, "Cure_Potion", 1, "test")
			expect.toBe(ok, true)
			expect.toBe(inventory:GetQuantity(profile.Inventory, "Cure_Potion"), 1)
		end)

		Harness.it("normaliza un perfil con la forma ANTIGUA sin perder saldo", function()
			-- Un perfil guardado antes de que la economia tuviera ledger
			-- tiene `{ Coins = 500 }` en vez de `{ Balances = {...} }`.
			-- Perder ese saldo seria perder la partida del jugador.
			local EconomyRules = require("../../src/ReplicatedStorage/Shared/Libraries/EconomyRules")
			local legacy = {
				DataVersion = ProfileSchema.CurrentVersion,
				Currencies = { Coins = 500, Gems = 12 },
				Inventory = { Items = {} },
				Progression = { XP = 250 },
			}

			local changed = ProfileSchema.NormalizeSections(legacy, 1)
			expect.toBe(changed, true)
			expect.toBe(EconomyRules.GetBalance(legacy.Currencies, "Coins"), 500)
			expect.toBe(EconomyRules.GetBalance(legacy.Currencies, "Gems"), 12)
			expect.toBe(legacy.Progression.XP, 250)
		end)

		Harness.it("un perfil ya normalizado no cambia", function()
			local profile = ProfileSchema.NewProfile(1)
			expect.toBe(ProfileSchema.NormalizeSections(profile, 1), false)
		end)

		Harness.it("un perfil normalizado es serializable", function()
			local profile = ProfileSchema.NewProfile(1)
			ProfileSchema.NormalizeSections(profile, 1)
			expect.toBe((ProfileSchema.IsSerializable(profile)), true)
		end)
	end)

	Harness.describe("Profile: migraciones", function()
		Harness.it("un perfil ya actual NO se migra", function()
			local profile = ProfileSchema.NewProfile(1)
			local migrated, notes, err = ProfileSchema.Migrate(profile)

			expect.toBe(err, nil)
			expect.toBe(migrated.DataVersion, ProfileSchema.CurrentVersion)
			expect.toBe(#notes, 0)
		end)

		Harness.it("NO toca el perfil original", function()
			-- `Migrate` trabaja sobre una COPIA: si falla a mitad, lo que
			-- hay en memoria sigue siendo lo que se leyo del DataStore.
			local profile = ProfileSchema.NewProfile(1)
			ProfileSchema.Migrate(profile)
			expect.toBe(profile.DataVersion, ProfileSchema.CurrentVersion)
		end)

		Harness.it("rechaza un perfil de version FUTURA", function()
			-- Un perfil de una version futura no se "migra hacia abajo":
			-- el siguiente guardado destruiria lo que esa version guardo.
			local profile = ProfileSchema.NewProfile(1)
			profile.DataVersion = ProfileSchema.CurrentVersion + 5

			local migrated, _, err = ProfileSchema.Migrate(profile)
			expect.toBe(migrated, nil)
			expect.toContain(tostring(err), "futura")
		end)

		Harness.it("rechaza algo que no es un perfil", function()
			local migrated, _, err = ProfileSchema.Migrate("basura")
			expect.toBe(migrated, nil)
			expect.toContain(tostring(err), "tabla")
		end)
	end)
end