const mcp = require("./mcp");

/**
 * Elimina LocalScripts duplicados por nombre.
 *
 * POR QUE EXISTE
 * --------------
 * Al anadir `ClientTelemetry.client.lua` a la fuente, Studio acabo con DOS
 * LocalScripts llamados `ClientTelemetry` en StarterPlayerScripts. Ejecutar
 * el mismo script dos veces no es inocuo: se conectan dos contestadores al
 * mismo RemoteFunction y el informe del cliente deja de ser fiable.
 *
 * Un comprobador de recuento de instancias habria dado "todo correcto": hay
 * los dos, y los dos se llaman igual. Solo hace falta grouping por nombre.
 *
 * Uso:  node tools/dedupe-scripts.js
 */
const DEDUPE = `
local services = {
    game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"),
    game:GetService("StarterGui"),
    game:GetService("ReplicatedStorage"),
}

local removed = 0
local report = {}

for _, service in ipairs(services) do
    local byName = {}
    local order = {}

    for _, child in ipairs(service:GetChildren()) do
        if byName[child.Name] then
            child:Destroy()
            removed += 1
        else
            byName[child.Name] = child
            table.insert(order, child.Name)
        end
    end

    table.sort(order)
    report[service:GetFullName()] = order
end

report.__removed = removed
return report
`;

async function main() {
	const result = await mcp.toolJson("execute_luau", {
		operation_id: "dedupe-scripts-1",
		target: "edit",
		code: DEDUPE,
	});

	if (result && result.success) {
		const value =
			typeof result.returnValue === "string"
				? JSON.parse(result.returnValue)
				: result.returnValue;
		console.log("duplicados eliminados: " + value.__removed);
		for (const [service, children] of Object.entries(value)) {
			if (service === "__removed") continue;
			console.log("");
			console.log(service);
			for (const child of children) {
				console.log("  " + child);
			}
		}
		if (value.__removed > 0) process.exitCode = 1;
		return;
	}

	console.error("ERROR: " + JSON.stringify(result));
	process.exitCode = 2;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});