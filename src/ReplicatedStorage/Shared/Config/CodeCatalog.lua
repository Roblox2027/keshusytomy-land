--!strict
--[[
	CodeCatalog
	Catalogo de codigos promocionales.

	POR QUE ESTA SEPARADO
	----------------------
	El MECANISMO de canje vive en `CodeRules` (logica pura) y el servicio
	que lo aplica en `CodeService`. Aqui solo vive el CONTENIDO: que codigos
	existen y que dan.

	Es la misma separacion que `ItemCatalog` / `ShopRules` / `ShopService`,
	y por el mismo motivo: cambiar el balance de una promocion no debe
	obligar a tocar la logica que decide si un canje es valido.

	CAMBIOS QUE NO SE DEBEN HACER
	------------------------------
	El `Code` es la CLAVE con la que se serializa el canje en el perfil del
	jugador (`Redemptions[codigo_normalizado]`). Renombrar un codigo
	published pierde el registro de todos los que ya lo canjearon, y
	vuelve a permitir el canje. Para retirarlo se marca `Available = false`
	(se sigue reconociendo, deja de pagarse).

	FORMATO DE LAS CLAVES
	---------------------
	El catalogo se indexa por la clave NORMALIZADA (`Rules.Normalize`), que
	es minuscula y sin espacios, guiones ni guiones bajos. Escribirlos a
	mano en mayusculas es mas legible, pero el indice NO lo es, y esa
	distancia es justo el error que hace que un codigo exista y no se pueda
	canjear. Por eso `Validate` lo comprueba al arrancar.
]]

local CodeCatalog = {}

--- Codigos publicados. El indice va en la clave NORMALIZADA.
local CODES: { [string]: any } = {
	-- Bienvenida. Sin caducidad ni limite: existe para siempre, y con el
	-- limite a uno por jugador no se puede abusar de el.
	keshusy = {
		Code = "KESHUSY",
		Rewards = { Coins = 100 },
		MaxRedemptions = nil,
		ExpiresAt = nil,
		Description = "Codigo de bienvenida.",
		Available = true,
	},

	-- Promocion de temporada con tope GLOBAL. Es el caso que distingue
	-- "ya lo usaste" de "agotado para todos": el primero lo decide el
	-- perfil del jugador y el segundo, el contador compartido del servidor.
	lan2026 = {
		Code = "LAN2026",
		Rewards = { Coins = 500, Gems = 5 },
		MaxRedemptions = 1000,
		ExpiresAt = nil,
		Description = "Promocion de temporada.",
		Available = true,
	},
}

--- Devuelve el catalogo indexado por clave normalizada.
--- @return { [string]: any }
function CodeCatalog.GetAll(): { [string]: any }
	return CODES
end

--- Definicion de un codigo tal y como lo escribiria el jugador.
--- @param rawCode any
--- @return any?
function CodeCatalog.Get(rawCode: any): any?
	return CODES[rawCode]
end

--- Codigos disponibles para la UI, como lista ordenada y estable.
--- @return { any }
function CodeCatalog.List(): { any }
	local list = {}

	for _, definition in pairs(CODES) do
		if definition.Available then
			table.insert(list, definition)
		end
	end

	-- Orden estable por clave: sin esto la UI reordenaria los productos en
	-- cada lectura y las pruebas compararian listas distintas.
	table.sort(list, function(a: any, b: any): boolean
		return tostring(a.Code) < tostring(b.Code)
	end)

	return list
end

--- Comprueba que el catalogo es utilizable por el servidor.
---
--- Se llama al ARRANCAR, no al canjear: un codigo publicado con una
--- recompensa rota debe aparecer como fallo de arranque, no como "este
--- codigo no existe" un martes a las tres de la manana.
--- @param codeRules any? modulo `CodeRules`; se INYECTA porque `script` no
---   existe en el interprete de pruebas y la dependencia se resuelve desde
---   el consumidor (ver `RemoteSchema`).
--- @return { string } problemas lista vacia = todo cuadra
function CodeCatalog.Validate(codeRules: any?): { string }
	local rules = codeRules or require(script.Parent.Libraries.CodeRules)
	local problems: { string } = {}

	for key, definition in pairs(CODES) do
		local normalized = rules.Normalize(definition.Code)

		if normalized ~= key then
			table.insert(problems, ("'%s': la clave '%s' no es la forma normalizada de '%s'"):format(
				tostring(definition.Code),
				key,
				tostring(normalized)
			))
		end

		local valid, reason = rules.IsDefinitionValid(definition)

		if not valid then
			table.insert(problems, ("'%s': definicion invalida (%s)"):format(
				tostring(definition.Code),
				tostring(reason)
			))
		end
	end

	return problems
end

return CodeCatalog