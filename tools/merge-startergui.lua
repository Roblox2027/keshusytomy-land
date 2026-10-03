-- merge-startergui.lua
-- Reubica el HUD importado y borra el envoltorio que deja `import_rbxm`.
-- 
-- POR QUE HACE FALTA
-- ------------------
-- `import_rbxm` importa el `.rbxm` como un Folder CONTENEDOR, no como el
-- servicio: los hijos del archivo cuelgan de una carpeta nueva llamada
-- `StarterGuiSource`. Para el Workspace eso lo resuelve `merge-workspace.lua`,
-- que sube los nietos y borra el envoltorio. Para `StarterGui` no habia paso
-- equivalente.
-- 
-- EL EFECTO ERA CONTRA-PRODUCTIVO
-- -------------------------------
-- Cada sincronizacion dejaban una copia MAS. Como el numero de instancias del
-- runtime CRECIA con cada pasada mientras el source se quedaba quieto, el
-- DIVERGE de `source-runtime-diff` se alejaba en lugar de acercarse, y nada
-- explicaba por que: el mapa estaba correcto.
-- 
-- Peor: cuando el envoltorio arrastraba a `ReplicatedStorage`, sus
-- RemoteEvents acababan DUPLICADOS dentro de `StarterGui`, donde no los busca
-- nadie, y la siguiente pasada los importaba otra vez.
-- 
-- LA RUTA DEBE COINCIDIR CON EL SOURCE
-- ------------------------------------
-- El proyecto declara el HUD como `StarterGui.KeshusyHUD`. La carpeta `UI`
-- desaparece al asignarse al servicio: `StarterGui: folder("UI", ...)` USA
-- ese Folder COMO si fuera el propio StarterGui, y Rojo aplana un nivel.
--
-- Si la importacion lo deja un nivel mas abajo, `StarterGui.UI.KeshusyHUD`,
-- el diff lo daria por ausente aunque este ahi mismo y se vea en juego.
-- Por eso los hijos se mueven a la RAIZ del servicio.
--
-- IDEMPOTENTE
-- -----------
-- Se puede ejecutar las veces que haga falta: si no hay envoltorio, no toca
-- nada; y si el HUD ya esta en su sitio, el barrido de duplicados lo deja
-- igual.

local StarterGui = game:GetService("StarterGui")
local ui = StarterGui
-- LIMPIEZA DE LA RUTA ANTIGUA
--
-- El HUD antes vivia en `StarterGui.UI.KeshusyHUD`, cuando el generador anadia
-- de verdad la carpeta `UI`. Ahora es `StarterGui.KeshusyHUD`. Esa copia vieja
-- no se borra sola: se queda en el runtime, `source-runtime-diff` la reporta
-- como 59 instancias de SOBRA y la sincronizacion acaba en DIVERGE aunque las
-- dos rutas apunten al mismo HUD.
--
-- Solo se borra cuando el HUD NUEVO ya esta en su sitio, que es lo que ocurre
-- porque este script corre DESPUES de importar. Si el nuevo no existiera, la
-- copia vieja seria lo unico que tendria el jugador y borrarla lo dejaria sin
-- interfaz.
--
-- Idempotente: si `UI` no existe, no hace nada.
local stale = StarterGui:FindFirstChild("UI")
local removedStale = 0

if stale and stale:IsA("Folder") and StarterGui:FindFirstChild("KeshusyHUD") then
	stale:Destroy()
	removedStale = 1
end

-- DEDUPLICADOS, Y CUAL GANA
-- --------------------------
-- `import_rbxm` anade SIEMPRE, y este script se puede ejecutar varias veces
-- seguidas, asi que `KeshusyHUD` aparece duplicado. Sin barrido, cada pasada
-- dejaba una copia mas y el numero de instancias del runtime CRECIA sin
-- parar mientras el diff se alejaba en lugar de acercarse.
--
-- GANA LA COPIA MAS NUEVA, que es la del envoltorio importado ahora mismo.
-- Conservar la primera habria parecido correcto y no lo es: `GetChildren()`
-- devuelve el orden de creacion, con la VIEJA delante, y el efecto era que
-- Studio se quedaba con la version anterior del HUD para siempre. El diff lo
-- daba como sincronizado porque compara NOMBRES, no propiedades, asi que
-- una barra de vida con el tamano equivocado pasaba por buena.
--
-- Por eso el barrido va DESPUES de mover los hijos nuevos y descarta todo lo
-- que no sea el recien llegado.
local moved, discarded, duplicates = 0, 0, 0

--- Borra de `parent` todos los hijos con nombre `name` EXCEPTO `keep`.
---
--- Solo dentro de la carpeta `ui` y solo Folder/ScreenGui: un `ModuleScript`
--- que comparta nombre con un `ScreenGui` es codigo y no se toca.
local function dropOthers(parent, name, keep)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name and child ~= keep and (child:IsA("ScreenGui") or child:IsA("Folder")) then
			child:Destroy()
			duplicates += 1
		end
	end
end

for _, wrapper in ipairs(StarterGui:GetChildren()) do
		-- Solo Folder. Un `ScreenGui` o un `ModuleScript` NUNCA deben borrarse:
		-- son interfaz y codigo reales, y un borrado aqui seria perder el HUD.
		--
		-- El sufijo "Source" lo pone `sync-workspace.js` al construir el .rbxm.
		if not (wrapper:IsA("Folder") and string.match(wrapper.Name, "Source$")) then
			continue
		end

		-- Se MUEVEN los hijos antes de destruir el envoltorio. Suspender en lugar
		-- de destruir evita perderlos.
		local children = wrapper:GetChildren()
		for _, child in ipairs(children) do
			if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
				-- Un Remote dentro de StarterGui no lo busca nadie: los canales
				-- viven en ReplicatedStorage. Se descarta en vez de moverlo para
				-- no crear una copia muerta que confunda al diff.
				child:Destroy()
				discarded += 1
			else
				child.Parent = ui
				moved += 1

				-- Aqui es donde el recien llegado GANA. La copia vieja del
				-- mismo nombre se destruye en el acto, y no despues: si se
				-- hiciera al final, `GetChildren` devolveria la vieja primero y
				-- el "conservar el primero" se quedaria con ella.
				dropOthers(ui, child.Name, child)
			end
		end

		wrapper:Destroy()
	end

return ("HUD reubicados: %d | remotos descartados: %d | duplicados: %d | ruta vieja: %d"):format(
	moved,
	discarded,
	duplicates,
	removedStale
)
