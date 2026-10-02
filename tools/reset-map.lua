-- reset-map.lua
-- Vacia el mapa de Workspace para que la proxima importacion sea la UNICA
-- fuente de verdad.
--
-- POR QUE EXISTE
-- --------------
-- La fusion y la deduplicacion son correcciones INCREMENTALES: conservan lo
-- que ya hay en el Workspace y solo sustituyen lo que falta. Funcionan bien
-- mientras el estado actual sea correcto, pero dejan una trampa:
--
-- Si una sincronizacion anterior dejo geometria en una posicion INVALIDA
-- (por ejemplo, todas las Partes apiladas en el origen porque el `.rbxm`
-- generado tenia un bloque `<Properties>` de mas), ninguna pasada posterior
-- la arregla: cada instancia ya "existe", asi que la deduplicacion descarta
-- la copia correcta que trae la importacion nueva y se queda con la mala.
-- El mapa queda atrapado en ese estado para siempre.
--
-- Vaciar antes de importar rompe el ciclo. El resultado ya no depende de lo
-- que hubiera antes, solo de `default.project.json`.
--
-- CUANDO SE EJECUTA
-- -----------------
-- Solo desde `sync-all.js`, y SOLO si `mapIsHealthy` dice que hace falta.
-- Nunca a mano: el mapa se regenera entero justo despues.
--
-- ES SEGURO porque `default.project.json` declara el mapa completo. Si el
-- generador no lo hiciera, este script dejaria el Workspace vacio, y por eso
-- la comprobacion de salud es obligatoria y no un extra.

local Workspace = game:GetService("Workspace")

--- Contenedores que `default.project.json` declara como hijos de Workspace.
--- Todo lo demas (`Bombs`, `ExplosionVfx`, el modelo del jugador) es
--- efimero y no forma parte del mapa.
local MAP_ROOTS = { "Environment", "SpawnLocations", "Lobby", "Worlds" }

--- Cantidad de Partes y de instancias del mapa.
local function countMap()
	local parts = 0
	local instances = 0
	for _, name in ipairs(MAP_ROOTS) do
		local container = Workspace:FindFirstChild(name)
		if container then
			instances += #container:GetDescendants()
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
		end
	end
	return parts, instances
end

--- Indica si el mapa actual es utilizable o hay que reconstruirlo.
---
--- Se declaran tres senales de un mapa roto, todas verificables:
---   1. Partes grandes pegadas al origen (geometria sin colocar);
---   2. ausencia total de Partes (importacion vacia o fallida);
---   3. envoltorios de trabajo de una importacion anterior sin integrar.
--- @return boolean healthy
--- @return string? reason
local function mapIsHealthy()
	-- 3. Envoltorios residuales: su presencia significa que una importacion
	-- anterior no se integro.
	for _, name in ipairs({ "WorkspaceSource", "Workspace" }) do
		if Workspace:FindFirstChild(name) then
			return false, ("envoltorio de trabajo '%s' presente"):format(name)
		end
	end

	local parts = countMap()
	if parts == 0 then
		return false, "el mapa no tiene ninguna Part"
	end

	-- 1. Geometria sin colocar. El diseno pone el lobby entre -70 y 70 y la
	-- arena alrededor de x = 500: una Part grande en el origen es siempre
	-- un fallo de posicionamiento, nunca una pieza intencionada.
	for _, name in ipairs(MAP_ROOTS) do
		local container = Workspace:FindFirstChild(name)
		if container then
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("BasePart") then
					if d.Position.Magnitude < 0.001 and d.Size.Magnitude > 20 then
						return false,
							("Part '%s' de tamano %.0f pegada al origen"):format(
								d:GetFullName(), d.Size.Magnitude
							)
					end
				end
			end
		end
	end

	-- Un mapa con muy pocas Partes para los mundos declarados tambien es
	-- sospechoso: el generador produce cientos.
	if parts < 100 then
		return false, ("el mapa tiene solo %d Partes; el generador produce cientos"):format(parts)
	end

	return true, nil
end

local healthy, reason = mapIsHealthy()

if healthy then
	local parts, instances = countMap()
	return string.format(
		"mapa sano: %d Partes, %d instancias. No se toca nada.",
		parts,
		instances
	)
end

-- Purgado.
local removed = 0

for _, name in ipairs(MAP_ROOTS) do
	local container = Workspace:FindFirstChild(name)
	if container then
		for _, child in ipairs(container:GetChildren()) do
			child:Destroy()
			removed += 1
		end
	end
end

for _, name in ipairs({ "WorkspaceSource", "Workspace" }) do
	local wrapper = Workspace:FindFirstChild(name)
	if wrapper and wrapper:IsA("Folder") then
		wrapper:Destroy()
		removed += 1
	end
end

return string.format(
	"MAPA ROTO (%s). Purgados %d hijos de primer nivel; la proxima importacion reconstruye el mapa.",
	reason,
	removed
)
