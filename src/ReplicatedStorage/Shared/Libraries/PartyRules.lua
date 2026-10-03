--!strict
--[[
	PartyRules
	Parties como logica pura: crear, invitar, aceptar, expulsar, disolver.

	POR QUE SEPARADO DEL SERVICIO
	------------------------------
	Una party es un grafo pequeno pero con MUCHAS condiciones de carrera:
	el invitado puede salir mientras llega la invitacion, el lider puede
	desconectarse en el mismo instante que acepta el tercero, y un jugador
	que ya esta en otra party recibe dos "crear" del mismo segundo.

	Todo eso se decide con tablas y numeros, sin motor y sin reloj de
	Roblox, asi que se puede probar de forma EXHAUSTIVA. `PartyService`
	anade lo que las reglas no saben: resolver `Player`, notificar por
	remoto y limpiar al desconectar.

	LAS REGLAS QUE DEFINEN ESTE MODULO
	----------------------------------
	1. UN JUGADOR ESTA EN COMO MAXIMO UNA PARTY. Sin esta regla, "crear"
	   dos veces seguido daria dos grupos y cada uno creeria ser el lider.

	2. LA PARTY TIENE UN LIDER, y solo el lider puede invitar o expulsar.
	   Un miembro no puede escalar privilegios pidiendole a otro que le
	   expulse y entre.

	3. OPERAR SIN LIDER ES INDEFINIDO. Si el lider se va, la party se
	   DISUELVE y todos vuelven al estado sin party. No se elige un lider
	   automaticamente: hacerlo permitiria que un exploiter que espera a
	   que el lider salga se quede con el grupo sin haberlo pedido nunca.

	4. UNA INVITACION CADUCA. Sin caducidad, una invitacion enviada antes de
	   una desconexion volveria a ser aceptable al volver, y el jugador
	   acabaria en un grupo que no elige.

	LA REGLA DE ORO
	----------------
	Todas las operaciones son ATOMICAS: validan y escriben en la MISMA
	llamada. Dos peticiones simultaneas (doble clic, o el reintento tras
	perder la conexion) encuentran el hueco ocupado y solo una gana.
]]

local Rules = {}

--- Motivos de rechazo. Texto estable: la UI decide que texto mostrar.
Rules.Reject = {
	AlreadyInParty = "already_in_party",
	NotInParty = "not_in_party",
	NotLeader = "not_leader",
	PartyFull = "party_full",
	SamePlayer = "same_player",
	UnknownInvite = "unknown_invite",
	InviteExpired = "invite_expired",
	InviteSelf = "invite_self",
	InvalidId = "invalid_id",
	NoSuchPlayer = "no_such_player",
}

--- Tamano maximo de una party.
---
--- Es un tope REAL, no decorativo: sin el, un exploiter podria invitar a
--- cientos de cuentas y el servidor intentaria moverlas a todas.
Rules.MAX_MEMBERS = 4

--- Segundos que vive una invitacion.
---
--- Sin caducidad, una invitacion enviada antes de una desconexion seria
--- aceptable al volver horas despues, y el jugador entraria en un grupo que
--- no ha elegido. Ver regla 4 de la cabecera.
Rules.INVITE_TTL_SECONDS = 60

--- Estado de la party de un jugador.
---
--- Es lo UNICO que se guarda por jugador. El resto de la party (lider,
--- miembros, invitaciones) vive en el estado COMPARTIDO, porque un jugador
--- no puede ver los grupos de los demas.
---
--- Se guarda en el perfil para que la party sobreviva a una reconexion:
--- perderla al caer la conexion seria desconectar a un equipo entero por un
--- problema de red.
--- @param playerId number
--- @return any state
function Rules.NewPlayerState(playerId: number): any
	return {
		PlayerId = playerId,
		PartyId = nil,
		IsLeader = false,
	}
end
--- Estado de una party, o nil.
---
--- `shared` es el estado COMPARTIDO del servidor: tabla de partyId ->
--- party. No puede vivir en el perfil de cada jugador, porque un jugador
--- no puede ver los grupos ajenos y porque un mismo grupo tiene que ser el
--- MISMO objeto para todos sus miembros, o dos miembros no se verian entre
--- si.
--- @param shared any
--- @param partyId any
--- @return any?
function Rules.GetParty(shared: any, partyId: any): any?
	if type(shared) ~= "table" or type(partyId) ~= "string" then
		return nil
	end

	local party = shared.Parties[partyId]

	if type(party) ~= "table" then
		return nil
	end

	return party
end

--- Crea una party con un jugador como lider.
---
--- Es ATOMICA: comprueba que NO esta en otra party y escribe el estado de
--- las DOS partes (el perfil del jugador y la party compartida) en la misma
--- llamada. Si se escribieran por separado, una excepcion en medio dejaria
--- al jugador "en una party" que no existe, o en una party sin lider.
--- @param shared any
--- @param playerState any estado del jugador (se MUTA)
--- @param playerId number
--- @param partyId string id de la nueva party
--- @return boolean accepted
--- @return string? rejection
function Rules.Create(shared: any, playerState: any, playerId: number, partyId: string): (boolean, string?)
	if type(shared) ~= "table" or type(playerState) ~= "table" then
		return false, Rules.Reject.InvalidId
	end

	if type(playerId) ~= "number" or type(partyId) ~= "string" or partyId == "" then
		return false, Rules.Reject.InvalidId
	end

	-- Ya esta en una party: no se crea otra. Este es el caso del doble clic.
	if playerState.PartyId ~= nil then
		return false, Rules.Reject.AlreadyInParty
	end

	if type(shared.Parties) ~= "table" then
		shared.Parties = {}
	end

	if shared.Parties[partyId] ~= nil then
		-- El id de party lo genera el SERVIDOR. Si se colara un id
		-- repetido, dos grupos distintos se pisarian. Se rechaza en vez de
		-- sobrescribir: sobrescribir dejaria miembros huerfanos.
		return false, Rules.Reject.AlreadyInParty
	end

	shared.Parties[partyId] = {
		Id = partyId,
		LeaderId = playerId,
		Members = { [playerId] = true },
		Invites = {},
	}

	playerState.PartyId = partyId
	playerState.IsLeader = true

	return true, nil
end

--- Comprueba si un jugador esta en una party.
--- @param playerState any
--- @return boolean inParty
function Rules.IsInParty(playerState: any): boolean
	return type(playerState) == "table" and playerState.PartyId ~= nil
end

--- Indica si un jugador es el lider de SU party.
--- @param playerState any
--- @return boolean isLeader
function Rules.IsLeader(playerState: any): boolean
	return type(playerState) == "table"
		and playerState.PartyId ~= nil
		and playerState.IsLeader == true
end

--- Invita a un jugador a la party del invitador.
---
--- El cliente manda SOLO el `targetUserId`. El servidor comprueba que el
--- invitador es el lider de la party en la que esta: sin esa comprobacion,
--- un miembro cualquiera podria invitar a gente ajena.
--- @param shared any
--- @param inviterState any
--- @param inviterId number
--- @param targetId number
--- @param nowSeconds number
--- @return boolean accepted
--- @return string? rejection
function Rules.Invite(
	shared: any,
	inviterState: any,
	inviterId: number,
	targetId: number,
	nowSeconds: number
): (boolean, string?)
	if type(targetId) ~= "number" then
		return false, Rules.Reject.InvalidId
	end

	if targetId == inviterId then
		return false, Rules.Reject.SamePlayer
	end

	if not Rules.IsInParty(inviterState) then
		return false, Rules.Reject.NotInParty
	end

	-- REGLA 2: solo el lider invita. Un miembro que invita sin ser lider
	-- podria meter gente en el grupo sin que nadie lo pidiera.
	if not Rules.IsLeader(inviterState) then
		return false, Rules.Reject.NotLeader
	end

	local party = Rules.GetParty(shared, inviterState.PartyId)

	if not party then
		return false, Rules.Reject.NotInParty
	end

	local memberCount = 0
	for _ in pairs(party.Members) do
		memberCount += 1
	end

	if memberCount >= Rules.MAX_MEMBERS then
		return false, Rules.Reject.PartyFull
	end

	if type(party.Invites) ~= "table" then
		party.Invites = {}
	end

	-- Si ya hay una invitacion viva, se RENUEVA en vez de duplicarse: dos
	-- entradas para el mismo jugador harian que al aceptar, la segunda
	-- encontrase la party llena.
	party.Invites[targetId] = nowSeconds + Rules.INVITE_TTL_SECONDS

	return true, nil
end
--- Acepta una invitacion.
---
--- Es ATOMICA y consume la invitacion EN LA MISMA LLAMADA: dos pulsaciones
--- seguidas Acceptancearian, y la segunda encontraria la party ya llena.
---
--- Al aceptar, el estado del jugador se actualiza en el MISMO paso que la
--- party. Si se escribieran por separado, un fallo en medio dejaria a un
--- miembro en la party sin figurar en ella.
--- @param shared any
--- @param playerState any estado del jugador (se MUTA)
--- @param inviterId number quien nvito
--- @param playerId number quien acepta
--- @param nowSeconds number
--- @return boolean accepted
--- @return string? rejection
--- @return any? party la party a la que se unio
function Rules.Accept(
	shared: any,
	playerState: any,
	inviterId: number,
	playerId: number,
	nowSeconds: number
): (boolean, string?, any?)
	if type(playerState) ~= "table" then
		return false, Rules.Reject.InvalidId, nil
	end

	if type(inviterId) ~= "number" then
		return false, Rules.Reject.InvalidId, nil
	end

	if inviterId == playerId then
		return false, Rules.Reject.SamePlayer, nil
	end

	-- Ya esta en una party: no puede estar en dos. Sin esta comprobacion,
	-- dos "aceptar" simultaneos de parties distintas dejarian al jugador en
	-- las dos: su `PartyId` apuntaria a una, pero la otra lo contaria como
	-- miembro para siempre.
	if playerState.PartyId ~= nil then
		return false, Rules.Reject.AlreadyInParty, nil
	end

	local party = Rules.FindPartyByMember(shared, inviterId)

	if not party then
		return false, Rules.Reject.UnknownInvite, nil
	end

	local expiresAt = party.Invites[playerId]

	if expiresAt == nil then
		return false, Rules.Reject.UnknownInvite, nil
	end

	-- REGLA 4: la invitacion caduca. Sin esta comprobacion, una invitacion
	-- enviada antes de una desconexion seria aceptable horas despues.
	if nowSeconds >= expiresAt then
		party.Invites[playerId] = nil
		return false, Rules.Reject.InviteExpired, nil
	end

	local memberCount = 0
	for _ in pairs(party.Members) do
		memberCount += 1
	end

	if memberCount >= Rules.MAX_MEMBERS then
		return false, Rules.Reject.PartyFull, nil
	end

	-- Consumo + escritura, en este orden y en la misma operacion.
	party.Invites[playerId] = nil
	party.Members[playerId] = true

	playerState.PartyId = party.Id
	playerState.IsLeader = false

	return true, nil, party
end

--- Rechaza una invitacion.
---
--- Rechazar consume la invitacion. Si no se consumiera, el jugador podria
--- aceptarla un segundo mas tarde desde la misma pantalla, que es
--- exactamente lo que "rechazar" significa.
--- @param shared any
--- @param inviterId number
--- @param playerId number
--- @return boolean rejected
function Rules.Decline(shared: any, inviterId: number, playerId: number): boolean
	local party = Rules.FindPartyByMember(shared, inviterId)

	if party and type(party.Invites) == "table" then
		party.Invites[playerId] = nil
		return true
	end

	return false
end

--- Busca la party de la que forma parte un jugador.
---
--- Se busca por MIEMBRO y no por `playerState.PartyId` a proposito: el
--- estado del jugador puede estar desincronizado (una reconexion a
--- medias, por ejemplo), y si la party real no lo tiene, no debe entrar en
--- ella.
--- @param shared any
--- @param playerId number
--- @return any?
function Rules.FindPartyByMember(shared: any, playerId: number): any?
	if type(shared) ~= "table" or type(shared.Parties) ~= "table" then
		return nil
	end

	for _, party in pairs(shared.Parties) do
		if type(party) == "table" and party.Members[playerId] then
			return party
		end
	end

	return nil
end
--- Sale de la party, o la disuelve si era el lider.
---
--- REGLA 3: si el lider se va, la party se DISUELVE. No se transfiere el
--- liderazgo automaticamente: hacerlo permitiria que un exploiter que
--- espera a que el lider salga se quede con el grupo sin haberlo pedido.
---
--- @param shared any
--- @param playerState any estado del jugador (se MUTA)
--- @param playerId number
--- @return boolean left
--- @return any? party party abandonada (o disuelta)
--- @return { number }? stranded ids de los que se quedaron sin party
function Rules.Leave(shared: any, playerState: any, playerId: number): (boolean, any?, { number }?)
	if not Rules.IsInParty(playerState) then
		return false, nil, nil
	end

	local party = Rules.GetParty(shared, playerState.PartyId)

	playerState.PartyId = nil
	playerState.IsLeader = false

	if not party then
		-- El estado del jugador apuntaba a una party que ya no existe: se
		-- limpia el estado y se devuelve `false` porque no hubo party que
		-- abandonar. Sin esta rama, el jugador quedaria apuntando a un id
		-- muerto y cada operacion futura fallaria con `NotInParty`.
		return false, nil, nil
	end

	local wasLeader = party.LeaderId == playerId

	party.Members[playerId] = nil

	if not wasLeader then
		return true, party, nil
	end

	-- REGLA 3: sin lider no hay party. Se devuelve la lista de los que se
	-- quedan sin grupo para que el servicio pueda limpiarles el estado.
	local stranded = {}

	for memberId in pairs(party.Members) do
		table.insert(stranded, memberId)
	end

	table.sort(stranded)
	shared.Parties[party.Id] = nil

	return true, party, stranded
end

--- El lider expulsa a un miembro.
---
--- No puede expulsarse a si mismo con esta via: el lider que quiere
--- salir usa `Leave`. La diferencia importa porque Kick no disuelve, y un
--- lider que se autoexpulsa sin querer dejaria un grupo sin lider.
--- @param shared any
--- @param leaderState any
--- @param leaderId number
--- @param targetId number
--- @return boolean accepted
--- @return string? rejection
function Rules.Kick(
	shared: any,
	leaderState: any,
	leaderId: number,
	targetId: number
): (boolean, string?)
	if type(targetId) ~= "number" then
		return false, Rules.Reject.InvalidId
	end

	if targetId == leaderId then
		return false, Rules.Reject.SamePlayer
	end

	if not Rules.IsLeader(leaderState) then
		return false, Rules.Reject.NotLeader
	end

	local party = Rules.GetParty(shared, leaderState.PartyId)

	if not party then
		return false, Rules.Reject.NotInParty
	end

	if not party.Members[targetId] then
		return false, Rules.Reject.NotInParty
	end

	party.Members[targetId] = nil

	-- Se limpia su invitacion si tenia alguna: si no, al volver a invitarle
	-- podria aceptar una invitacion VIEJA que creia caducada.
	if type(party.Invites) == "table" then
		party.Invites[targetId] = nil
	end

	return true, nil
end

--- Cuantos miembros tiene una party.
--- @param shared any
--- @param partyId any
--- @return number
function Rules.GetMemberCount(shared: any, partyId: any): number
	local party = Rules.GetParty(shared, partyId)

	if not party then
		return 0
	end

	local count = 0
	for _ in pairs(party.Members) do
		count += 1
	end

	return count
end

--- Los ids de una party, ORDENADOS.
---
--- Ordenados porque `pairs` no garantiza orden, y la UI compararia listas
--- distintas en cada lectura.
--- @param shared any
--- @param partyId any
--- @return { number }
function Rules.GetMembers(shared: any, partyId: any): { number }
	local party = Rules.GetParty(shared, partyId)

	if not party then
		return {}
	end

	local members = {}

	for memberId in pairs(party.Members) do
		table.insert(members, memberId)
	end
	table.sort(members)

	return members
end

return Rules