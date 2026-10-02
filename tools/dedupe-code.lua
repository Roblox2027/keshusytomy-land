-- dedupe-code.lua
-- Elimina homonimos duplicados en los contenedores de CODIGO.
--
-- POR QUE EXISTE
-- ---------------
-- `dedupe-workspace.lua` solo recorre `Workspace`. Con el mapa en orden,
-- los duplicados aparecieron en el otro sitio y nadie los eliminaba:
--
--   ReplicatedStorage.Shared.Libraries.CoreRules   [ModuleScript] x2
--   ReplicatedStorage.Remotes.CoreAction            [RemoteEvent]  x2
--   ServerScriptService.Services.VisualService      [ModuleScript] x2
--
-- CAUSA RAIZ (medida, no supuesta)
-- ---------------------------------
-- El plugin de Rojo esta CONECTADO a esta sesion de Studio y sincroniza
-- por su cuenta mientras `tools/sync-scripts.js` escribe a mano. Los dos
-- caminos crean la instancia y el que llega segundo se queda con un
-- homonimo. Por eso los duplicados aparecen justo en los ficheros
-- tocados por un `sync-all` reciente, y por eso el recuento de
-- `source-runtime-diff` se desalineaba en cuanto se anadia algo nuevo.
--
-- POR QUE UN DUPLICADO ES UN FALLO GRAVE Y NO COSMETICO
-- -----------------------------------------------------
-- `FindFirstChild("CoreRules")` y `WaitForChild("Services"):WaitForChild("VisualService")`
-- devuelven el PRIMERO que encuentran, no el correcto. Con dos
-- `CoreAction`, un `WaitForChild("CoreAction")` puede cablearse al remoto
-- huerfano y el `CoreService` dejaria de funcionar sin ningun error: el
-- codigo.require seria correcto y el juego, no. Un duplicado silencioso
-- es peor que un fallo visible.
--
-- CRITERIO
-- --------
-- Gana la instancia CONSOLIDADA (la que ya estaba) y se destruye la
-- recien llegada, igual que en `dedupe-workspace.lua`. En codigo no se
-- fusiona contenido: un ModuleScript no tiene hijos que rescued y un
-- RemoteEvent no admite fusion. Se descarta el sobrante entero.
--
-- Es idempotente: ejecutarlo dos veces seguidas no cambia nada la segunda.

local report = {}
local removed = 0

--- Recorre un contenedor y elimina homonimos, en TODA la profundidad.
---
--- Es RECURSIVO a proposito. Antes solo bajaba dos niveles y por eso
--- dejaba vivo un duplicado real: `CoreRules` vive en
--- `ReplicatedStorage -> Shared -> Libraries -> CoreRules`, tres niveles
--- por debajo de la raiz, y un recorrido de dos niveles nunca lo
--- alcanzaba. El informe de verificacion de este mismo script ya lo
--- delata (`CoreRules=2` con "0 duplicados eliminados"): sin recursion,
--- la puerta de sync nunca llegaba a PASS.
---
--- @param container Instance
--- @param label string
--- @param depth number
local function dedupeDeep(container, label, depth)
	local seen = {}

	for _, child in ipairs(container:GetChildren()) do
		if seen[child.Name] then
			child:Destroy()
			removed += 1
			table.insert(report, label .. "/" .. child.Name .. " (duplicado " .. child.ClassName .. ")")
		else
			seen[child.Name] = child

			-- Se baja por los contenedores con estructura (carpetas), nunca
			-- por Scripts ni ModuleScripts: no tienen hijos propios y su
			-- contenido es codigo, no un arbol que fusionar.
			if child:IsA("Folder") and depth < 6 then
				dedupeDeep(child, child.Name, depth + 1)
			end
		end
	end
end

-- Las raices que el proyecto declara. Se recorren enteras, enrecursive.
local ROOTS = {
	game:GetService("ServerScriptService"),
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"),
	game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts"),
}

for _, root in ipairs(ROOTS) do
	if root and root:IsA("Instance") then
		dedupeDeep(root, root:GetFullName(), 0)
	end
end

-- Comprobacion posterior: el servicio tiene que quedar UNO. Se mide, no
-- se supone: si esto no se verifica, un fallo aqui pasaria inadvertido
-- justo como paso antes.
local function countNamed(container, name)
	local total = 0
	if not container then
		return 0
	end
	for _, child in ipairs(container:GetChildren()) do
		if child.Name == name then
			total += 1
		end
	end
	return total
end

local services = game:GetService("ServerScriptService"):FindFirstChild("Services")
local libraries = game:GetService("ReplicatedStorage").Shared:FindFirstChild("Libraries")
local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")

local verified = ("VisualService=%d CoreRules=%d CoreAction=%d"):format(
	countNamed(services, "VisualService"),
	countNamed(libraries, "CoreRules"),
	countNamed(remotes, "CoreAction")
)

return string.format(
	"duplicados de codigo eliminados: %d\noperaciones:\n  %s\nverificacion: %s",
	removed,
	#report > 0 and table.concat(report, "\n  ") or "-",
	verified
)