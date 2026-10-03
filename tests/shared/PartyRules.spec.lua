--!strict
--[[
	PartyRules.spec
	Crear, invitar, aceptar, rechazar, salir, expulsar y disolver.

	EL ORDEN DE ESTA SUITE ES EL DE LOS FALLOS QUE IMPORTAN
	----------------------------------------------------------
	Una party parece trivial hasta que se combinan las condiciones de
	carrera. Estas pruebas atacan exactamente eso:

	    - crear dos veces (doble clic)
	    - aceptar dos veces (doble clic)
	    - aceptar una invitacion caducada
	    - quedarse en dos parties a la vez
	    - el lider se va y la party queda sin dueño

	La ultima merece nombre propio: si se transfiriera el liderazgo
	automaticamente, un exploiter que espera a que el lider salga se
	quedaria con el grupo sin haberlo pedido nunca.
]]

local Harness = require("../TestHarness")
local expect = Harness.expect

local Rules = require("../../src/ReplicatedStorage/Shared/Libraries/PartyRules")

local T0 = 1000

--- Estado COMPARTIDO del servidor, como lo crearia el servicio.
local function shared()
	return { Parties = {} }
end

local function playerState(playerId)
	return Rules.NewPlayerState(playerId)
end

local function describePartyRules()
	Harness.describe("PartyRules", function()
		---------------------------------------------------------
		-- CREAR
		---------------------------------------------------------

		Harness.it("crear una party deja al jugador como lider", function()
			local s = shared()
			local state = playerState(1)

			local accepted, rejection = Rules.Create(s, state, 1, "p1")
			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)

			expect.toBe(Rules.IsInParty(state), true)
			expect.toBe(Rules.IsLeader(state), true)
			expect.toBe(state.PartyId, "p1")
			expect.toBe(Rules.GetMemberCount(s, "p1"), 1)
		end)

		Harness.it("crear dos veces NO crea dos parties", function()
			-- El doble clic. Sin esta comprobacion, el jugador estaria en
			-- dos grupos y cada uno creeria que el es su lider.
			local s = shared()
			local state = playerState(1)

			Rules.Create(s, state, 1, "p1")

			local accepted, rejection = Rules.Create(s, state, 1, "p2")
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.AlreadyInParty)

			-- El estado sigue apuntando a la PRIMERA party.
			expect.toBe(state.PartyId, "p1")
			expect.toBe(s.Parties.p2, nil)
		end)

		Harness.it("diez crear seguidos producen una sola party", function()
			local s = shared()
			local state = playerState(1)
			local acceptedCount = 0

			for i = 1, 10 do
				if Rules.Create(s, state, 1, ("p%d"):format(i)) then
					acceptedCount += 1
				end
			end

			expect.toBe(acceptedCount, 1)

			local parties = 0
			for _ in pairs(s.Parties) do
				parties += 1
			end
			expect.toBe(parties, 1)
		end)

		Harness.it("un id de party repetido se rechaza, no se sobrescribe", function()
			-- Si se sobrescribiera, los miembros de la party original
			-- quedarían en un grupo que ya no existe.
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			local other = playerState(2)
			local accepted, rejection = Rules.Create(s, other, 2, "p1")

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.AlreadyInParty)
			expect.toBe(s.Parties.p1.LeaderId, 1)
		end)

		Harness.it("un id o un jugador que no son validos se rechazan", function()
			local s = shared()
			expect.toBe(Rules.Create(s, playerState(1), 1, ""), false)
			expect.toBe(Rules.Create(s, playerState(1), 1, nil), false)
			expect.toBe(Rules.Create(s, playerState(1), "uno", "p1"), false)
			expect.toBe(Rules.Create(s, nil, 1, "p1"), false)
			expect.toBe(Rules.Create("no soy tabla", playerState(1), 1, "p1"), false)
		end)
---------------------------------------------------------
		-- INVITAR
		---------------------------------------------------------

		Harness.it("el lider invita y la invitacion queda registrada", function()
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			local accepted, rejection = Rules.Invite(s, leader, 1, 2, T0)
			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)
			expect.toBe(s.Parties.p1.Invites[2], T0 + Rules.INVITE_TTL_SECONDS)
		end)

		Harness.it("un miembro que NO es lider no puede invitar", function()
			-- Sin esta comprobacion, cualquier miembro podria meter gente
			-- en el grupo sin que nadie lo pidiera.
			local s = shared()
			local leader = playerState(1)
			local member = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Accept(s, member, 1, 2, T0)

			local accepted, rejection = Rules.Invite(s, member, 2, 3, T0)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NotLeader)
		end)

		Harness.it("quien no esta en party no puede invitar", function()
			local s = shared()
			local accepted, rejection = Rules.Invite(s, playerState(1), 1, 2, T0)

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NotInParty)
		end)

		Harness.it("uno no puede invitarse a si mismo", function()
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			local accepted, rejection = Rules.Invite(s, leader, 1, 1, T0)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.SamePlayer)
		end)

		Harness.it("una party llena no admite mas invitaciones", function()
			-- El tope es REAL: sin el, un exploiter podria invitar a cientos
			-- de cuentas.
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			for id = 2, Rules.MAX_MEMBERS do
				local member = playerState(id)
				Rules.Invite(s, leader, 1, id, T0)
				Rules.Accept(s, member, 1, id, T0)
			end

			expect.toBe(Rules.GetMemberCount(s, "p1"), Rules.MAX_MEMBERS)

			local accepted, rejection = Rules.Invite(s, leader, 1, 99, T0)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.PartyFull)
		end)

		Harness.it("invitar dos veces renueva, no duplica", function()
			-- Dos entradas para el mismo jugador harian que al aceptar, la
			-- segunda encontrase la party llena.
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Invite(s, leader, 1, 2, T0 + 5)

			local invites = 0
			for _ in pairs(s.Parties.p1.Invites) do
				invites += 1
			end

			expect.toBe(invites, 1)
		end)
---------------------------------------------------------
		-- ACEPTAR
		---------------------------------------------------------

		Harness.it("aceptar une al jugador a la party", function()
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)

			local accepted, rejection, party = Rules.Accept(s, guest, 1, 2, T0)
			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)
			expect.toBe(party.Id, "p1")

			expect.toBe(Rules.GetMemberCount(s, "p1"), 2)
			expect.toBe(guest.PartyId, "p1")
			expect.toBe(Rules.IsLeader(guest), false)
		end)

		Harness.it("aceptar dos veces solo une una vez", function()
			-- El doble clic. La invitacion se consume DENTRO de `Accept`.
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)

			expect.toBe(Rules.Accept(s, guest, 1, 2, T0), true)

			local accepted, rejection = Rules.Accept(s, guest, 1, 2, T0)
			expect.toBe(accepted, false)
			-- El motivo es `already_in_party` y no `unknown_invite`: la
			-- comprobacion "ya estoy en una party" va ANTES de mirar la
			-- invitacion. Es el orden correcto, porque "ya estas en una
			-- party" es lo que el jugador necesita ver al pulsar dos veces,
			-- no "esa invitacion ya no existe".
			expect.toBe(rejection, Rules.Reject.AlreadyInParty)
			expect.toBe(Rules.GetMemberCount(s, "p1"), 2)
		end)

		Harness.it("una invitacion caducada ya no se acepta", function()
			-- Sin caducidad, una invitacion enviada antes de una desconexion
			-- seria aceptable horas despues y el jugador entraria en un grupo
			-- que no ha elegido.
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)

			local accepted, rejection = Rules.Accept(
				s,
				guest,
				1,
				2,
				T0 + Rules.INVITE_TTL_SECONDS + 1
			)

			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.InviteExpired)

			-- Y la caducada se limpia sola: aceptarla mas tarde seguiria
			-- fallando, pero por "no existe" y no por tiempo.
			expect.toBe(s.Parties.p1.Invites[2], nil)
		end)

		Harness.it("no se puede estar en dos parties a la vez", function()
			-- Dos "aceptar" de parties distintas simultaneos: su `PartyId`
			-- apuntaria a una, pero la otra lo contaria como miembro para
			-- siempre, y no podria salir nunca.
			local s = shared()
			local leaderA = playerState(1)
			local leaderB = playerState(3)
			local guest = playerState(2)
			Rules.Create(s, leaderA, 1, "pA")
			Rules.Create(s, leaderB, 3, "pB")
			Rules.Invite(s, leaderA, 1, 2, T0)
			Rules.Invite(s, leaderB, 3, 2, T0)

			expect.toBe(Rules.Accept(s, guest, 1, 2, T0), true)

			local accepted, rejection = Rules.Accept(s, guest, 3, 2, T0)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.AlreadyInParty)

			-- La party perdedora NO lo cuenta como miembro.
			expect.toBe(Rules.GetMemberCount(s, "pB"), 1)
		end)

		Harness.it("aceptar sin invitacion no hace nada", function()
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")

			local accepted, rejection = Rules.Accept(s, guest, 1, 2, T0)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.UnknownInvite)
		end)

		Harness.it("aceptar la invitacion de un lider que se fue no hace nada", function()
			-- El lider se fue: su party ya no existe, aunque el estado del
			-- invitado diga lo que diga.
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Leave(s, leader, 1)

			local accepted, rejection = Rules.Accept(s, guest, 1, 2, T0)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.UnknownInvite)
		end)

		---------------------------------------------------------
		-- RECHAZAR
		---------------------------------------------------------

		Harness.it("rechazar consume la invitacion", function()
			-- Si no se consumiera, el jugador podria aceptarla un segundo
			-- mas tarde desde la misma pantalla, que es justo lo que
			-- "rechazar" significa.
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)

			expect.toBe(Rules.Decline(s, 1, 2), true)
			expect.toBe(s.Parties.p1.Invites[2], nil)
			expect.toBe(Rules.Accept(s, guest, 1, 2, T0), false)
		end)
---------------------------------------------------------
		-- SALIR Y DISOLVER
		---------------------------------------------------------

		Harness.it("un miembro puede salir sin disolver la party", function()
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Accept(s, guest, 1, 2, T0)

			local left, _, stranded = Rules.Leave(s, guest, 2)
			expect.toBe(left, true)
			expect.toBe(stranded, nil)

			-- La party sigue viva, con su lider.
			expect.toBe(Rules.GetMemberCount(s, "p1"), 1)
			expect.toBe(Rules.IsLeader(leader), true)
			expect.toBe(Rules.IsInParty(guest), false)
		end)

		Harness.it("si el lider se va, la party SE DISUELVE", function()
			-- REGLA 3. No se transfiere el liderazgo: hacerlo permitiria que
			-- un exploiter que espera a que el lider salga se quedase con el
			-- grupo sin haberlo pedido nunca.
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Accept(s, guest, 1, 2, T0)

			local left, _, stranded = Rules.Leave(s, leader, 1)
			expect.toBe(left, true)

			-- La party desaparece del estado compartido.
			expect.toBe(s.Parties.p1, nil)
			expect.toBe(Rules.GetMemberCount(s, "p1"), 0)

			-- Y el servicio recibe la lista de quien se quedo sin grupo, para
			-- poder limpiarle el estado. Sin esto, el miembro creeria estar
			-- en una party que ya no existe.
			expect.toBe(#stranded, 1)
			expect.toBe(stranded[1], 2)
		end)

		Harness.it("el lider NO cede la party a un miembro", function()
			-- Comprobacion explicita del motivo de la disolucion: si
			-- `guest.IsLeader` fuera true despues, habria una via para
			-- quedarse con grupos ajenos esperando a que su lider salga.
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Accept(s, guest, 1, 2, T0)

			Rules.Leave(s, leader, 1)
			expect.toBe(Rules.IsLeader(guest), false)
		end)

		Harness.it("salir sin estar en party no hace nada", function()
			local s = shared()
			expect.toBe(Rules.Leave(s, playerState(1), 1), false)
		end)

		Harness.it("un estado que apunta a una party muerta se limpia", function()
			-- Una reconexion a medias puede dejar el estado apuntando a un id
			-- que ya no existe. Sin esta rama, cada operacion futura
			-- fallaria con NotInParty y no podria volver a crear.
			local s = shared()
			local state = playerState(1)
			state.PartyId = "fantasma"
			state.IsLeader = true

			expect.toBe(Rules.Leave(s, state, 1), false)
			expect.toBe(state.PartyId, nil)
			expect.toBe(state.IsLeader, false)
		end)

		Harness.it("cien create/leave seguidos no dejan parties huerfanas", function()
			-- La prueba de fuga: si `Leave` no borrara la party del estado
			-- compartido, este bucle llenaria el servidor de grupos muertos.
			local s = shared()

			for i = 1, 100 do
				local state = playerState(i)
				Rules.Create(s, state, i, ("p%d"):format(i))
				Rules.Leave(s, state, i)
			end

			local remaining = 0
			for _ in pairs(s.Parties) do
				remaining += 1
			end

			expect.toBe(remaining, 0)
		end)
---------------------------------------------------------
		-- EXPULSAR
		---------------------------------------------------------

		Harness.it("el lider puede expulsar a un miembro", function()
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Accept(s, guest, 1, 2, T0)

			local accepted, rejection = Rules.Kick(s, leader, 1, 2)
			expect.toBe(accepted, true)
			expect.toBe(rejection, nil)
			expect.toBe(Rules.GetMemberCount(s, "p1"), 1)
		end)

		Harness.it("un miembro NO puede expulsar a otro", function()
			local s = shared()
			local leader = playerState(1)
			local guest = playerState(2)
			local other = playerState(3)
			Rules.Create(s, leader, 1, "p1")
			Rules.Invite(s, leader, 1, 2, T0)
			Rules.Accept(s, guest, 1, 2, T0)
			Rules.Invite(s, leader, 1, 3, T0)
			Rules.Accept(s, other, 1, 3, T0)

			local accepted, rejection = Rules.Kick(s, guest, 2, 3)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NotLeader)
			expect.toBe(Rules.GetMemberCount(s, "p1"), 3)
		end)

		Harness.it("el lider no puede expulsarse a si mismo por Kick", function()
			-- Kick no disuelve: un lider que se autoexpulsa dejaria un grupo
			-- sin lider. Para irse usa Leave.
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			local accepted, rejection = Rules.Kick(s, leader, 1, 1)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.SamePlayer)
			expect.toBe(Rules.GetMemberCount(s, "p1"), 1)
		end)

		Harness.it("expulsar a alguien que no esta en la party no hace nada", function()
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			local accepted, rejection = Rules.Kick(s, leader, 1, 99)
			expect.toBe(accepted, false)
			expect.toBe(rejection, Rules.Reject.NotInParty)
		end)

		---------------------------------------------------------
		-- CONSULTAS Y ESTADOS ROTOS
		---------------------------------------------------------

		Harness.it("los miembros salen ordenados y estables", function()
			-- Sin orden, la UI compararia listas distintas en cada lectura.
			local s = shared()
			local leader = playerState(1)
			Rules.Create(s, leader, 1, "p1")

			for id = 2, 4 do
				local member = playerState(id)
				Rules.Invite(s, leader, 1, id, T0)
				Rules.Accept(s, member, 1, id, T0)
			end

			local first = table.concat(Rules.GetMembers(s, "p1"), ",")
			local second = table.concat(Rules.GetMembers(s, "p1"), ",")

			expect.toBe(first, "1,2,3,4")
			expect.toBe(first, second)
		end)

		Harness.it("consultar una party que no existe devuelve vacio, no error", function()
			local s = shared()
			expect.toBe(Rules.GetMemberCount(s, "no_existe"), 0)
			expect.toBe(#Rules.GetMembers(s, "no_existe"), 0)
			expect.toBe(Rules.GetParty(s, "no_existe"), nil)
			expect.toBe(Rules.GetParty(s, nil), nil)
			expect.toBe(Rules.GetParty("no soy tabla", "p1"), nil)
			expect.toBe(#Rules.GetMembers("no soy tabla", "p1"), 0)
		end)

		Harness.it("un estado compartido vacio no rompe nada", function()
			-- Estado migrado de una version anterior, o `Init` recien llamado.
			local fresh = {}
			expect.toBe(Rules.Create(fresh, playerState(1), 1, "p1"), true)
			expect.toBe(Rules.FindPartyByMember(fresh, 1).Id, "p1")
		end)
	end)
end

return describePartyRules