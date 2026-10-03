-- Mide la ESTRUCTURA de los mundos en el runtime de Studio.
--
-- POR QUE ESTE PROBE Y NO `.ai/probes/world-bounds.lua`
-- ------------------------------------------------------
-- El antiguo contaba "zones" buscando un atributo `Zone` en un Model. Rojo 7.7
-- no soporta `$attributes` en los archivos de proyecto (esta documentado en
-- `generate-project.js`), asi que ese recuento daba 0 SIEMPRE, hiciese lo que
-- hiciese el mapa. Un 0 que no depende de la realidad no mide nada.
--
-- Aqui se cuentan las carpetas `Zones/` y `Routes/` y, sobre todo, las PIEZAS
-- de cada una, que es lo que de verdad distingue una zona de una carpeta vacia.
local out = {}
local W = game:GetService("Workspace")
local worlds = W:FindFirstChild("Worlds")

if worlds then
	for _, wd in ipairs(worlds:GetChildren()) do
		local minv, maxv
		local parts = 0

		for _, d in ipairs(wd:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				local c = d.Position
				if d.Anchored then
					if not minv then
						minv = c
						maxv = c
					else
						minv = Vector3.new(math.min(minv.X, c.X), math.min(minv.Y, c.Y), math.min(minv.Z, c.Z))
						maxv = Vector3.new(math.max(maxv.X, c.X), math.max(maxv.Y, c.Y), math.max(maxv.Z, c.Z))
					end
				end
			end
		end

		local entry = { parts = parts }

		-- ZONAS: carpeta `Zones`, con su numero de hijos y las piezas de cada una.
		local zonesFolder = wd:FindFirstChild("Zones")
		local zoneList = {}
		if zonesFolder then
			for _, z in ipairs(zonesFolder:GetChildren()) do
				local floorParts, solidParts = 0, 0
				for _, d in ipairs(z:GetDescendants()) do
					if d:IsA("BasePart") then
						if d.Name:match("_Core$") or d.Name:match("_Slab_%d+$") then
							floorParts += 1
						end
						if d.CanCollide then solidParts += 1
						end
					end
				end
				table.insert(zoneList, { name = z.Name, floor = floorParts, solid = solidParts })
			end
		end
		entry.zones = #zoneList
		entry.zoneDetail = zoneList

		-- RUTAS: carpeta `Routes`, contando las losas de cada recorrido.
		local routesFolder = wd:FindFirstChild("Routes")
		local routeList = {}
		if routesFolder then
			for _, r in ipairs(routesFolder:GetChildren()) do
				local decks = 0
				for _, d in ipairs(r:GetDescendants()) do
					if d:IsA("BasePart") and d.Name:match("_Deck_%d+$") then
						decks += 1
					end
				end
				table.insert(routeList, { name = r.Name, decks = decks })
			end
		end
		entry.routes = #routeList
		entry.routeDetail = routeList

		if minv then
			entry.size = {
				math.floor(maxv.X - minv.X),
				math.floor(maxv.Y - minv.Y),
				math.floor(maxv.Z - minv.Z),
			}
		end

		local kids = {}
		for _, c in ipairs(wd:GetChildren()) do
			table.insert(kids, c.Name .. "[" .. c.ClassName .. "]")
		end
		entry.top = kids
		out[wd.Name] = entry
	end
end

return out
