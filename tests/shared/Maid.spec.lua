--!strict
--[[
	Maid.spec
	Pruebas del gestor de limpieza.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Maid = require("../../src/ReplicatedStorage/Shared/Libraries/Maid")

local function describeMaid()
	Harness.describe("Maid", function()
		Harness.it("empieza vacio y activo", function()
			local maid = Maid.new()
			expect.toBe(maid:Count(), 0)
			expect.toBeFalsy(maid:IsDestroyed())
		end)

		Harness.it("Add registra recursos", function()
			local maid = Maid.new()
			maid:Add( function() end)
			maid:Add( function() end)
			expect.toBe(maid:Count(), 2)
		end)

		Harness.it("Destroy ejecuta los callbacks registrados", function()
			local maid = Maid.new()
			local calls = 0
			maid:Add( function()
				calls += 1
			end)

			maid:Destroy()

			expect.toBe(calls, 1)
			-- Tras destruir, el Maid queda marcado como destruido.
			expect.toBeTruthy(maid:IsDestroyed())
			expect.toBe(maid:Count(), 0)
		end)

		Harness.it("Destroy es idempotente: no ejecuta dos veces", function()
			local maid = Maid.new()
			local calls = 0
			maid:Add( function()
				calls += 1
			end)

			maid:Destroy()
			maid:Destroy()

			expect.toBe(calls, 1)
		end)

		Harness.it("un error en un callback no impide limpiar los demas", function()
			local maid = Maid.new()
			local secondRan = false

			maid:Add( function()
				error("boom")
			end)
			maid:Add( function()
				secondRan = true
			end)

			maid:Destroy()

			-- El Maid registra el fallo pero continua la limpieza.
			expect.toBe(secondRan, true)
		end)

		Harness.it("Remove libera inmediatamente y saca el recurso del Maid", function()
			local maid = Maid.new()
			local ran = false
			local resource = function()
				ran = true
			end

			maid:Add(resource)
			expect.toBe(maid:Remove(resource), true)

			-- Remove ya ejecuto el cleanup: se libera en el momento.
			expect.toBe(ran, true)
			expect.toBe(maid:Count(), 0)

			-- Y Destroy no vuelve a ejecutarlo (no hay doble liberacion).
			maid:Destroy()
			expect.toBe(maid:Count(), 0)
		end)

		Harness.it("Add despues de Destroy libera inmediatamente", function()
			local maid = Maid.new()
			maid:Destroy()

			local ran = false
			maid:Add( function()
				ran = true
			end)

			-- Sin fuga: un recurso tardio se libera en el momento.
			expect.toBe(ran, true)
		end)

		Harness.it("Remove devuelve false si el recurso no estaba", function()
			local maid = Maid.new()
			expect.toBe(maid:Remove(function() end), false)
		end)

		Harness.it("DoCallbacks ejecuta funciones sin destruir", function()
			local maid = Maid.new()
			local calls = 0
			maid:Add( function()
				calls += 1
			end)

			maid:DoCallbacks()

			expect.toBe(calls, 1)
			expect.toBeFalsy(maid:IsDestroyed())
			expect.toBe(maid:Count(), 1)
		end)
	end)
end

return describeMaid