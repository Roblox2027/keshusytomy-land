// sync-scripts-fase21.js
// Sincroniza UN conjunto de scripts de la fuente al DataModel REAL de Studio.
//
// POR QUE EXISTE (FASE 2.1)
// -------------------------
// `rojo build` produce un archivo; no cambia lo que Studio tiene abierto. Y
// Studio tiene abierto `KeshusyTomy-LanD_AutoRecovery_1.rbxl`, que NO es
// `KeshusyTomy-LanD.rbxlx`. Sin esta sincronizacion, la FASE 2.1 certificaria
// un DataModel viejo mientras se lee codigo nuevo: justo el falso PASS que
// la REGLA CRITICA de PASS prohibe.
//
// QUE HACE
// --------
// Para cada script: compara el Source del DataModel con el del archivo y,
// si difieren, escribe el de la fuente. Informa de cada comparacion para que
// quede registro de que se toco el arbol real y no solo el disco.
//
// Uso:
//   node tools/sync-scripts-fase21.js
//   node tools/sync-scripts-fase21.js --dry

const fs = require("fs");
const path = require("path");
const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");

/**
 * Destino en el DataModel -> archivo en la fuente.
 *
 * Se listan a mano y no se recorren el arbol: el recorrido automatico es lo
 * que produjo los duplicados de `TestDriverService` y `ClientTelemetry` que
 * se encontraron en la reconciliacion. Aqui cada destino aparece una vez.
 */
const TARGETS = [
	{
		instance: "StarterPlayer.StarterPlayerScripts.ClientBootProbe",
		file: path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts/ClientBootProbe.client.lua").replace(/\\/g, "/"),
		className: "LocalScript",
	},
	{
		instance: "StarterPlayer.StarterPlayerScripts.Controllers.PortalController",
		file: path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts/Controllers/PortalController.lua").replace(/\\/g, "/"),
		className: "ModuleScript",
	},
	{
		instance: "StarterPlayer.StarterPlayerScripts.ClientTestDriver",
		file: path.join(ROOT, "src/StarterPlayer/StarterPlayerScripts/ClientTestDriver.client.lua").replace(/\\/g, "/"),
		className: "LocalScript",
	},
	{
		instance: "ReplicatedStorage.Shared.Libraries.TestDriverLogic",
		file: path
			.join(ROOT, "src/ReplicatedStorage/Shared/Libraries/TestDriverLogic.lua")
			.replace(/\\/g, "/"),
		className: "ModuleScript",
	},
	{
		instance: "ServerScriptService.Services.BombService",
		file: path
			.join(ROOT, "src/ServerScriptService/Services/BombService.lua")
			.replace(/\\/g, "/"),
		className: "ModuleScript",
	},
	{
		instance: "ReplicatedStorage.Shared.Config.FeatureConfig",
		file: path.join(ROOT, "src/ReplicatedStorage/Shared/Config/FeatureConfig.lua").replace(/\\/g, "/"),
		className: "ModuleScript",
	},
];

/**
 * Luau que compara y opcionalmente escribe, en UN solo viaje por MCP.
 *
 * Cada spec viaja como LITERALES DE CADENA sueltos, no como un JSON dentro
 * de `[[...]]`. El motivo es concreto: la lista de specs termina en `]` y al
 * pegarle el cierre `]]` del literal Luau aparece `]]`, que cierra la cadena
 * larga antes de tiempo y rompe la compilacion con
 * `Expected ')' (to close '(' at column 30), got ']'`.
 */
function luauSync(dryRun) {
	const q = (s) => JSON.stringify(s);

	const declarations = TARGETS.map((t, i) => {
		// El Source viaja DESDE Node, no con `readfile`: `readfile` no esta
		// expuesto en el contexto de edicion de Studio y llamarlo aborta el
		// snippet con `attempt to call a nil value`.
		const source = fs.readFileSync(t.file, "utf8");
		return (
			`local INSTANCE_${i} = ${q(t.instance)}\n` +
			`local CLASS_${i} = ${q(t.className)}\n` +
			`local SOURCE_${i} = ${q(source)}`
		);
	}).join("\n");

	const list = TARGETS.map((t, i) => {
		const parts = t.instance.split(".");
		const steps = parts
			.slice(1)
			.map((p) => `node = node and node:FindFirstChild(${q(p)})`)
			.join("\n    ");

		return `
do
    local instancePath = INSTANCE_${i}
    local expectedClass = CLASS_${i}
    local node = game:GetService(${q(parts[0])})
    ${steps}

    if not node then
        results[#results + 1] = { path = instancePath, status = "FALTA", detail = "no existe en el DataModel" }
    elseif node.ClassName ~= expectedClass then
        results[#results + 1] = {
            path = instancePath,
            status = "CLASE",
            detail = ("es %s, se esperaba %s"):format(node.ClassName, expectedClass),
        }
    else
        local desired = SOURCE_${i}
        local current = node.Source
        local status, detail
        if current == desired then
            status, detail = "IGUAL", ("%d bytes"):format(#desired)
        elseif ${dryRun ? "true" : "false"} then
            status, detail = "DIFERENCIA", ("en disco %d, en Studio %d"):format(#desired, #current)
        else
            local ok, err = pcall(function()
                node.Source = desired
            end)
            if ok then
                status, detail = "ESCRITO", ("%d bytes"):format(#desired)
            else
                status, detail = "ERROR", tostring(err)
            end
        end
        results[#results + 1] = {
            path = instancePath,
            class = node.ClassName,
            expectedClass = expectedClass,
            status = status,
            detail = detail,
        }
    end
end`;
	}).join("\n");

	return `
${declarations}

local results = {}
${list}
return results
`;
}

async function main() {
	const dryRun = process.argv.includes("--dry");
	await mcp.init();
	const out = await mcp.toolJson("execute_luau", { code: luauSync(dryRun) });

	// `execute_luau` devuelve el valor como TEXTO JSON dentro de
	// `returnValue`. Sin desempaquetarlo, `rows` era una cadena y el
	// contador de escrituras daba 0 aunque hubiera escrito: un informe que
	// miente sobre su propio resultado es peor que no informs.
	const rows = parseRows(out);

	console.log(`=== SINCRONIZACION ${dryRun ? "(DRY RUN)" : "(ESCRITURA)"} ===\n`);
	let changed = 0;
	for (const r of rows) {
		console.log(`  ${String(r.status).padEnd(11)} ${r.path}`);
		console.log(`      clase=${r.class || "?"} (esperada ${r.expectedClass || "?"})  ${r.detail || ""}`);
		if (r.status === "ESCRITO") changed += 1;
	}
	console.log(`\nescritos=${changed} / comparados=${rows.length}`);
	if (changed === 0 && !dryRun) {
		console.log("El DataModel ya coincidia con la fuente.");
	}
	if (rows.some((r) => r.status !== "IGUAL")) process.exitCode = 1;
}

/** Desempaqueta `returnValue` (texto JSON) o acepta un array directo. */
function parseRows(out) {
	let value = out;
	if (value && typeof value === "object" && typeof value.returnValue === "string") {
		try {
			value = JSON.parse(value.returnValue);
		} catch {
			return [{ path: "(sin parsear)", status: "ERROR", detail: value.returnValue.slice(0, 400) }];
		}
	}
	if (Array.isArray(value)) return value;
	return [{ path: "(inesperado)", status: "ERROR", detail: JSON.stringify(value).slice(0, 400) }];
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
