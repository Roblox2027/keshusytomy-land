// reconcile-runtime.js
// AUDITORIA DE RECONCILIACION sobre el lugar REAL abierto en Studio.
//
// Por que existe: el informe anterior se hizo sobre el sistema de
// archivos. Este script pregunta al Studio que esta ABIERTO, que es lo
// unico que vale como evidencia de runtime.
//
// Uso:  node tools/reconcile-runtime.js

const mcp = require("./mcp");

/** Lista hijos directos de un path del DataModel. */
async function children(path) {
	const out = await mcp.toolJson("execute_luau", {
		code: `
			local node = game
			for segment in string.gmatch("${path}", "[^%.]+") do
				node = node:FindFirstChild(segment)
				if not node then return "MISSING: ${path}" end
			end
			local names = {}
			for _, c in ipairs(node:GetChildren()) do
				table.insert(names, c.Name .. " [" .. c.ClassName .. "]")
			end
			return table.concat(names, "\\n")
		`,
	});
	// `execute_luau` devuelve un OBJETO con `returnValue`, no una cadena.
	// Sin desempaquetarlo, `children` devolveria siempre una lista vacia y la
	// auditoria concluiria falsamente que no hay nada en el lugar.
	const payload = typeof out === "string" ? out : out && out.returnValue;
	return typeof payload === "string" ? payload.split("\n") : [];
}

/** Cuenta ModulesScript de un folder separando reales (grandes) de stubs. */
async function classify(path) {
	const out = await mcp.toolJson("execute_luau", {
		code: `
			local node = game
			for segment in string.gmatch("${path}", "[^%.]+") do
				node = node:FindFirstChild(segment)
				if not node then return "MISSING: ${path}" end
			end
			local real, stub = {}, {}
			for _, c in ipairs(node:GetChildren()) do
				if c:IsA("ModuleScript") or c:IsA("Script") or c:IsA("LocalScript") then
					local lines = 0
					for _ in string.gmatch(c.Source, "[^\\n]+") do lines += 1 end
					if lines > 60 then
						table.insert(real, c.Name .. "=" .. lines)
					else
						table.insert(stub, c.Name .. "=" .. lines)
					end
				end
			end
			table.sort(real); table.sort(stub)
			return "REAL(" .. #real .. "): " .. table.concat(real, ", ")
				.. "\\nSTUB(" .. #stub .. "): " .. table.concat(stub, ", ")
		`,
	});
	return out;
}

async function main() {
	await mcp.init();

	const mode = process.argv[2] || "all";

	if (mode === "all" || mode === "place") {
		console.log("=== LUGAR ABIERTO ===");
		console.log(JSON.stringify(await mcp.toolJson("get_place_info", {})));
	}

	if (mode === "all" || mode === "tree") {
		for (const p of [
			"ReplicatedStorage.Remotes",
			"ServerScriptService.Services",
			"ServerScriptService.Systems",
			"StarterPlayer.StarterPlayerScripts.Controllers",
			"Workspace",
			"ReplicatedStorage",
		]) {
			console.log(`\n=== ${p} ===`);
			try {
				console.log((await children(p)).join(" | "));
			} catch (e) {
				console.log("ERROR: " + e.message);
			}
		}
	}

	if (mode === "all" || mode === "classify") {
		for (const p of [
			"ServerScriptService.Services",
			"ServerScriptService.Systems",
			"StarterPlayer.StarterPlayerScripts.Controllers",
		]) {
			console.log(`\n=== CLASIFICACION ${p} ===`);
			console.log(await classify(p));
		}
	}

	if (mode === "portals") {
		// Atributos que `PortalService.CollectPortals` necesita para que un
		// portal sea USABLE. Sin RequiredLevel/WorldId el servicio lo
		// descarta y el portal existe pero no acepta viajes.
		console.log(
			await mcp.toolJson("execute_luau", {
				code: `
					local lines = {}
					for _, d in ipairs(workspace:FindFirstChild("Lobby"):GetDescendants()) do
						if d.Name:match("^Portal_") then
							local attrs = {}
							for name, value in d:GetAttributes() do
								table.insert(attrs, ("%s=%s"):format(name, tostring(value)))
							end
							table.sort(attrs)
							local kids = {}
							for _, k in ipairs(d:GetChildren()) do
								table.insert(kids, k.Name .. "/" .. k.ClassName)
							end
							table.sort(kids)
							table.insert(lines, ("%s [%s] attrs=[%s] hijos=[%s]"):format(
								d.Name, d.ClassName, table.concat(attrs, ", "), table.concat(kids, ", ")
							))
						end
					end
					table.sort(lines)
					return table.concat(lines, "\\n")
				`,
			})
		);
	}

	if (mode === "map") {
		// Mapa real: donde hay portales y si cada mundo tiene arena.
		// Sin portales, `PortalService` arranca con 0 portales y el jugador
		// no tiene nada con lo que interactuar aunque el servicio sea "real".
		console.log(
			await mcp.toolJson("execute_luau", {
				code: `
					local lines = {}
					local function scan(label, container)
						if not container then
							table.insert(lines, label .. ": MISSING")
							return
						end
						local portals, total = {}, 0
						for _, d in ipairs(container:GetDescendants()) do
							total += 1
							if d.Name:match("^Portal_") then
								table.insert(portals, d.Name)
							end
						end
						table.sort(portals)
						table.insert(lines, ("%s: descendants=%d portales=[%s]"):format(
							label, total, table.concat(portals, ", ")
						))
					end

					scan("Lobby", workspace:FindFirstChild("Lobby"))
					local worlds = workspace:FindFirstChild("Worlds")
					if worlds then
						for _, w in ipairs(worlds:GetChildren()) do
							scan("Worlds." .. w.Name, w)
						end
					end
					return table.concat(lines, "\\n")
				`,
			})
		);
	}

	if (mode === "worlds") {
		// Destinos reales del mapa y atributo `World` publicado.
		//
		// Comprueba que `MovePlayer` publica el mundo que corresponde de
		// verdad, y no uno fijo: si el HUD dijera "Lobby" con el jugador
		// dentro de la arena, el jugador no sabria donde esta.
		console.log(
			await mcp.serverLuau(`
				local Players = game:GetService("Players")
				local Services = game:GetService("ServerScriptService"):FindFirstChild("Services")
				local MatchService = require(Services:FindFirstChild("MatchService"))
				local RoundService = require(Services:FindFirstChild("RoundService"))
				local player = Players:GetPlayers()[1]

				local function pos()
					if not player then return "sin jugador" end
					local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if not r then return "sin root" end
					return string.format("%.0f, %.0f, %.0f", r.Position.X, r.Position.Y, r.Position.Z)
				end

				local keys = MatchService.GetDestinationKeys and MatchService.GetDestinationKeys() or {}
				local dests = {}
				for _, k in ipairs(keys) do
					local d = MatchService.GetDestination(k)
					if d then
						table.insert(dests, string.format("%s=(%.0f, %.0f, %.0f)", k, d.Position.X, d.Position.Y, d.Position.Z))
					end
				end

				-- Traslado forzado a la arena: es el camino que ejecuta la ronda.
				MatchService.MovePlayer(player, "Arena")
				local afterArena = {
					pos = pos(),
					world = player:GetAttribute("World"),
				}

				MatchService.MovePlayer(player, "Lobby")
				local afterLobby = {
					pos = pos(),
					world = player:GetAttribute("World"),
				}

				return {
					RoundPlaying = RoundService.IsPlaying and RoundService.IsPlaying() or false,
					Destinations = dests,
					AfterArena = afterArena,
					AfterLobby = afterLobby,
				}
			`)
		);
	}

	if (mode === "portalenter") {
		// CATEGORIA DE PRUEBA: SERVER DIRECT CALL.
		//
		// Llama al handler real (`HandleEnter`), el mismo que ejecuta
		// `PortalAction.Enter`, y comprueba que el jugador se mueve y que el
		// veredicto se intenta enviar. NO prueba el camino del cliente.
		console.log(
			await mcp.serverLuau(`
				local Players = game:GetService("Players")
				local Services = game:GetService("ServerScriptService"):FindFirstChild("Services")
				local PortalService = require(Services:FindFirstChild("PortalService"))
				local Remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
				local player = Players:GetPlayers()[1]

				if not player then
					return { error = "sin jugador" }
				end

				local function pos()
					local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if not r then return nil end
					return string.format("%.0f, %.0f, %.0f", r.Position.X, r.Position.Y, r.Position.Z)
				end

				local before = pos()

				-- Camino RECHAZADO primero: el motivo tiene que ser util.
				PortalService.HandleEnter(player, "Desert")

				-- Camino deForest, que es el unico registrado.
				PortalService.HandleEnter(player, "Forest")

				-- Lo que se publico tras el traslado.
				local attributes = {}
				for _, name in ipairs({ "World", "Level", "PlayerState" }) do
					attributes[name] = player:GetAttribute(name)
				end

				return {
					Before = before,
					After = pos(),
					World = player:GetAttribute("World"),
					PortalRemoteExists = Remotes ~= nil and Remotes:FindFirstChild("PortalAction") ~= nil,
					Attributes = attributes,
				}
			`)
		);
	}

	if (mode === "portalcheck") {
		// CATEGORIA DE PRUEBA: SERVER DIRECT CALL.
		//
		// Esto NO es input de jugador. Se salta `InputController` y
		// `PortalController` y llama al handler del servidor directamente.
		// Prueban la decision y el teleport, y nada mas. Para la cadena
		// completa hace falta el cliente, que ahora mismo no responde.
		console.log(
			await mcp.serverLuau(`
				local Players = game:GetService("Players")
				local Services = game:GetService("ServerScriptService"):FindFirstChild("Services")
				local PortalService = require(Services:FindFirstChild("PortalService"))
				local player = Players:GetPlayers()[1]

				if not player then
					return { error = "sin jugador" }
				end

				local before = {}
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					before = { x = root.Position.X, y = root.Position.Y, z = root.Position.Z }
				end

				-- CanTravel devuelve el MOTIVO, asi que se puede ver por que
				-- se rechaza sin provocar el efecto.
				local results = {}
				for _, worldId in ipairs({ "Forest", "Desert", "Cyber", "Inventado" }) do
					local allowed, reason = PortalService.CanTravel(player, worldId)
					table.insert(results, {
						WorldId = worldId,
						Allowed = allowed,
						Reason = reason or "aceptado",
						RequiredLevel = (PortalService.GetPortal(worldId) or {}).RequiredLevel or "n/a",
					})
				end

				return {
					PlayerLevel = PortalService.GetPlayerLevel(player),
					PortalsRegistered = #PortalService.GetPortalIds(),
					Results = results,
					PositionBefore = before,
				}
			`)
		);
	}

	if (mode === "verify") {
		// Compara el fuente REAL de Studio con el del repositorio.
		//
		// `sync-scripts.js` avisa cuando una lectura sale truncada, y una
		// escritura "correcta" sobre una lectura truncada puede no haberse
		// aplicado. Este modo comprueba el FINAL del archivo, que es justo
		// lo que no se pudo leer antes.
		const paths = process.argv.slice(3);
		for (const p of paths) {
			const source = await mcp.toolJson("get_script_source", { instancePath: p });
			const text = typeof source === "string" ? source : source && source.source;
			const lines = typeof text === "string" ? text.split("\n") : [];
			console.log(
				`${p}: lineas=${lines.length} ultima="${(lines[lines.length - 1] || "").trim()}"`
			);
		}
	}

	if (mode === "client") {
		// Estado del CLIENTE real. Es la diferencia entre "el servidor
		// arranca" y "el jugador ve algo": sin esto, un controller roto en
		// el cliente pasaria desapercibido.
		console.log(
			await mcp.clientLuau(`
				local Players = game:GetService("Players")
				local player = Players.LocalPlayer
				if not player then
					return { error = "sin LocalPlayer" }
				end

				local playerGui = player:WaitForChild("PlayerGui", 10)
				local guis = {}
				if playerGui then
					for _, g in ipairs(playerGui:GetChildren()) do
						table.insert(guis, g.Name .. "/" .. g.ClassName)
					end
					table.sort(guis)
				end

				-- Texto REAL que el jugador tiene en pantalla.
				local texts = {}
				local function collect(node, depth)
					if depth > 6 then return end
					for _, child in ipairs(node:GetChildren()) do
						if child:IsA("TextLabel") or child:IsA("TextButton") then
							local t = child.Text
							if t ~= nil and t ~= "" then
								table.insert(texts, child.Name .. "=" .. tostring(t):gsub("\\n", " / "))
							end
						end
						if child:IsA("GuiObject") then
							collect(child, depth + 1)
						end
					end
				end
				if playerGui then
					collect(playerGui, 0)
				end
				table.sort(texts)

				return {
					Guis = guis,
					Texts = texts,
					Character = player.Character ~= nil,
				}
			`)
		);
	}

	if (mode === "globals") {
		// Que expone el servidor en `_G`. Sin esto no hay forma de preguntar
		// al runtime por el estado real de un servicio durante el playtest.
		console.log(
			await mcp.serverLuau(`
				local names = {}
				for k in pairs(_G) do
					table.insert(names, tostring(k))
				end
				table.sort(names)
				return names
			`)
		);
	}

	if (mode === "portalsvc") {
		// Estado REAL de PortalService dentro del servidor en ejecucion:
		// cuantos portales registro y con que nivel. Es la prueba de que la
		// cadena de portales existe de verdad y no solo en el codigo.
		console.log(
			await mcp.serverLuau(`
				local Services = game:GetService("ServerScriptService"):FindFirstChild("Services")
				local ok, PortalService = pcall(require, Services:FindFirstChild("PortalService"))
				if not ok then
					return { error = "no se pudo cargar PortalService: " .. tostring(PortalService) }
				end

				local ids = PortalService.GetPortalIds()
				local detail = {}
				for _, id in ipairs(ids) do
					local p = PortalService.GetPortal(id)
					table.insert(detail, {
						WorldId = id,
						DisplayName = p.DisplayName,
						RequiredLevel = p.RequiredLevel,
						State = p.State,
						Position = string.format("%.0f, %.0f, %.0f", p.Position.X, p.Position.Y, p.Position.Z),
					})
				end

				return { Count = #ids, Portals = detail }
			`)
		);
	}

	if (mode === "player") {
		// Estado REAL del jugador conectado durante el playtest. Es la
		// unica fuente que permite decir si alguien puede jugar de verdad.
		console.log(
			await mcp.serverLuau(`
				local Players = game:GetService("Players")
				local list = Players:GetPlayers()
				if #list == 0 then
					return { error = "sin jugadores conectados" }
				end

				local report = {}
				for _, p in ipairs(list) do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					table.insert(report, {
						Name = p.Name,
						Level = p:GetAttribute("Level"),
						XP = p:GetAttribute("XP"),
						Coins = p:GetAttribute("Coins"),
						RoundState = p:GetAttribute("RoundState"),
						RoundNumber = p:GetAttribute("RoundNumber"),
						TimeRemaining = p:GetAttribute("RoundTimeRemaining"),
						HasCharacter = p.Character ~= nil,
						Health = hum and hum.Health or -1,
						Position = root and string.format("%.0f, %.0f, %.0f", root.Position.X, root.Position.Y, root.Position.Z) or "n/a",
					})
				end
				return report
			`)
		);
	}

	if (mode === "services") {
		// Estado de los servicios en el SERVIDOR en ejecucion.
		console.log(
			await mcp.serverLuau(`
				local out = {}
				local registry = _G.__ServiceRegistry
				if not registry then
					return { error = "ServiceRegistry no expuesto en _G" }
				end
				local names = registry:GetNames and registry:GetNames() or {}
				for _, n in ipairs(names) do
					out[n] = registry:GetState(n)
				end
				return out
			`)
		);
	}

	if (mode === "logfilter") {
		const needle = process.argv[3] || "";
		console.log(await mcp.tool("get_runtime_logs", { tail: 200, filter: needle }));
	}

	if (mode === "logs") {
		console.log(await mcp.tool("get_runtime_logs", { tail: 250 }));
	}

	if (mode === "all" || mode === "sim") {
		console.log("\n=== ESTADO DE SIMULACION ===");
		console.log(JSON.stringify(await mcp.toolJson("get_simulation_state", {})));
	}
}

main().catch((e) => {
	console.error("FALLO:", e.message);
	process.exit(1);
});