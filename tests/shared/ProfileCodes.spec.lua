--!strict
--[[
	ProfileCodes.spec
	Migracion de la seccion `Codes` del perfil.

	POR QUE ESTA SUITE EXISTE
	-------------------------
	La seccion `Codes` cambio de forma: era una tabla lisa y ahora tiene
	`Redemptions` y `Counts` separados. Ese cambio no es cosmetico: en la
	forma antigua, la raiz de `Codes` podia llevar a la vez codigos
	canjeados y contadores por jugador, y un codigo llamado `player12`
	ocupaba el mismo hueco que el jugador 12.

	Una migracion que tirara esa seccion devolveria al jugador el derecho a
	canjear un codigo que ya uso, que es exactamente el fallo que este
	sistema existe para impedir. Estas pruebas comprueban que se
	CONSERVA lo que se puede conservar y que NO se inventa lo que no.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local ProfileSchema = require("../../src/ReplicatedStorage/Shared/Libraries/ProfileSchema")

local function describeProfileCodesSection()
	Harness.describe("ProfileSchema: seccion Codes", function()
		---------------------------------------------------------
		-- FORMA NUEVA
		---------------------------------------------------------

		Harness.it("un perfil nuevo trae Codes con forma fija", function()
			local profile = ProfileSchema.NewProfile(7)

			expect.toBe(type(profile.Codes), "table")
			expect.toBe(type(profile.Codes.Redemptions), "table")
			expect.toBe(type(profile.Codes.Counts), "table")
		end)

		Harness.it("los espacios de nombres de Codes estan separados", function()
			-- Es el fallo concreto que motivo este diseno: en la raiz de
			-- `Codes` no puede haber NADA. Todo lo que se guarda vive en
			-- `Redemptions` (codigos) o en `Counts` (userId), nunca en la
			-- raiz, que es donde antes se mezclaban los dos.
			local profile = ProfileSchema.NewProfile(7)

			-- Lo legitimo de la seccion.
			expect.toBe(type(profile.Codes.Redemptions), "table")
			expect.toBe(type(profile.Codes.Counts), "table")

			-- En la raiz solo puede estar `PlayerId`: ningun canje y ningun
			-- contador debe aparecer alli.
			for key in pairs(profile.Codes) do
				expect.toBe(key == "PlayerId" or key == "Redemptions" or key == "Counts", true)
			end
		end)

		---------------------------------------------------------
		-- MIGRACION DE PERFILES VIEJOS
		---------------------------------------------------------

		Harness.it("un perfil sin Codes la recibe", function()
			local legacy = ProfileSchema.NewProfile(7)
			legacy.Codes = nil

			expect.toBe(ProfileSchema.NormalizeSections(legacy, 7), true)
			expect.toBe(type(legacy.Codes), "table")
			expect.toBe(type(legacy.Codes.Redemptions), "table")
		end)

		Harness.it("los canjes de la forma VIEJA se conservan", function()
			-- El motivo de la migracion: si estos canjes se perdieran, un
			-- jugador que ya canjeo un codigo volveria a poder canjearlo.
			local legacy = ProfileSchema.NewProfile(7)
			legacy.Codes = { keshusy = true, lan2026 = true }

			expect.toBe(ProfileSchema.NormalizeSections(legacy, 7), true)
			expect.toBe(legacy.Codes.Redemptions.keshusy, true)
			expect.toBe(legacy.Codes.Redemptions.lan2026, true)
		end)

		Harness.it("una clave numerica suelta NO se convierte en codigo canjeado", function()
			-- En la forma antigua la raiz tambien llevaba contadores por
			-- jugador. Copiar un numero como si fuera un canje haria que
			-- un codigo quedara "usado" sin que nadie lo usara.
			local legacy = ProfileSchema.NewProfile(7)
			legacy.Codes = { keshusy = true, ["12"] = 3 }

			expect.toBe(ProfileSchema.NormalizeSections(legacy, 7), true)
			expect.toBe(legacy.Codes.Redemptions.keshusy, true)
			expect.toBe(legacy.Codes.Redemptions["12"], nil)
		end)

		Harness.it("un canje marcado en false no se migra como usado", function()
			-- `false` significa "no canjeado": migrarlo como `true`
			-- quemaria un codigo que el jugador todavia puede usar.
			local legacy = ProfileSchema.NewProfile(7)
			legacy.Codes = { keshusy = false }

			expect.toBe(ProfileSchema.NormalizeSections(legacy, 7), true)
			expect.toBe(legacy.Codes.Redemptions.keshusy, nil)
		end)

		Harness.it("un perfil ya en la forma nueva no se toca", function()
			-- Normalizar no puede marcar `changed` sobre un perfil sano:
			-- si lo hiciera, cada carga lo registraria como reparado y el
			-- log se llenaria de avisos falsos.
			local profile = ProfileSchema.NewProfile(7)

			expect.toBe(ProfileSchema.NormalizeSections(profile, 7), false)
		end)

		Harness.it("la seccion Codes sigue siendo serializable", function()
			-- Un perfil con `Codes` roto (una cadena, por ejemplo) no puede
			-- guardarse: el DataStore daria "cannot serialize" sin decir
			-- ni que ni donde.
			local profile = ProfileSchema.NewProfile(7)

			local ok, reason = ProfileSchema.IsSerializable(profile)
			expect.toBe(ok, true)
			expect.toBe(reason, nil)
		end)
	end)
end

return describeProfileCodesSection