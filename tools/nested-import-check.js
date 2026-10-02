"use strict";

/*
	nested-import-check.js
	Comprueba, de forma REAL, si el importador de Studio (`import_rbxm`)
	conserva los hijos `Part` de una `Part`.

	POR QUE HACE FALTA
	------------------
	El bosque cuelga la decoracion de cada bloque como HIJO de la Part
	(`Block_12.Deco_B_Root_12_0`). Al sincronizar, los 48 bloques llegan a
	Studio pero sus 325 hijos `Part` NO. En cambio los hijos `PointLight`
	de otras Parts SI llegan.

	Eso NO es un problema de Roblox: una Part admite cualquier hijo. La
	sospecha cae sobre `import_rbxm`, que es una via propia de Studio y no
	el mismo codigo que el constructor nativo de instancias.

	Este script monta un `.rbxm` minimo que contiene, bajo el mismo padre:

	    Folder
	      HostPart
	        ChildPart        <- Parte que se sospecha
	        ChildLight       <- clase que si sobrevive

	y lo importa de verdad por MCP. La sonda va primero A MANO (creando
	las instancias con `Instance.new`) y despues por IMPORTACION, para no
	confundir "Studio no lo admite" con "el importador no lo trae".

	Uso:  node tools/nested-import-check.js
*/

const fs = require("fs");
const path = require("path");

const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const RBXM = path.join(CACHE, "nested-probe.rbxm");
const ARGS = path.join(CACHE, "nested-probe-args.json");

/** Lista los hijos de `HostPart` dentro de la sonda. */
const COUNT_LUAU = `
local Workspace = game:GetService("Workspace")
local probe = Workspace:FindFirstChild("NestedProbe")
if not probe then return "sin sonda" end
local host = probe:FindFirstChild("HostPart")
if not host then return "sonda sin HostPart" end
local names = {}
for _, child in ipairs(host:GetChildren()) do
	table.insert(names, child.Name .. "[" .. child.ClassName .. "]")
end
return table.concat(names, ", ")
`;

const CLEAN_LUAU = `
local p = game:GetService("Workspace"):FindFirstChild("NestedProbe")
if p then p:Destroy() end
return "limpiado"
`;

/** Construye la jerarquia a mano, sin pasar por el importador. */
const BUILD_MANUAL_LUAU = `
local Workspace = game:GetService("Workspace")
local old = Workspace:FindFirstChild("NestedProbe")
if old then old:Destroy() end

local probe = Instance.new("Folder")
probe.Name = "NestedProbe"
probe.Parent = Workspace

local host = Instance.new("Part")
host.Name = "HostPart"
host.Anchored = true
host.Size = Vector3.new(4, 4, 4)
host.Parent = probe

-- El caso que se sospecha.
local childPart = Instance.new("Part")
childPart.Name = "ChildPart"
childPart.Anchored = true
childPart.Size = Vector3.new(2, 2, 2)
childPart.Parent = host

-- El caso de control, que se sabe que sobrevive.
local childLight = Instance.new("PointLight")
childLight.Name = "ChildLight"
childLight.Brightness = 1
childLight.Range = 10
childLight.Parent = host

return "construido"
`;

/**
 * El `.rbxm` minimo, con el mismo formato que emite Rojo: `referent` mas
 * `Properties`. El hijo `Part` va DENTRO del `Item` del padre, que es
 * exactamente como Rojo serializa el bosque.
 */
const RBXM_CONTENT = `<roblox version="4">
  <Item class="Folder" referent="1">
    <Properties>
      <string name="Name">NestedProbe</string>
    </Properties>
    <Item class="Part" referent="2">
      <Properties>
        <string name="Name">HostPart</string>
        <bool name="Anchored">true</bool>
        <Vector3 name="size">
          <X>4</X>
          <Y>4</Y>
          <Z>4</Z>
        </Vector3>
      </Properties>
      <Item class="Part" referent="3">
        <Properties>
          <string name="Name">ChildPart</string>
          <bool name="Anchored">true</bool>
          <Vector3 name="size">
            <X>2</X>
            <Y>2</Y>
            <Z>2</Z>
          </Vector3>
        </Properties>
      </Item>
      <Item class="PointLight" referent="4">
        <Properties>
          <string name="Name">ChildLight</string>
          <float name="Brightness">1</float>
          <float name="Range">10</float>
        </Properties>
      </Item>
    </Item>
  </Item>
</roblox>
`;
const textOf = (res) => String(res && res.returnValue !== undefined ? res.returnValue : res);

async function main() {
	fs.mkdirSync(CACHE, { recursive: true });

	console.log("=== 1. Jerarquia creada A MANO en Studio ===");
	await mcp.tool("execute_luau", { code: BUILD_MANUAL_LUAU });
	const manual = textOf(await mcp.tool("execute_luau", { code: COUNT_LUAU }));
	console.log("  hijos de HostPart: " + manual);

	// Se borra antes de importar para no mezclar los dos escenarios.
	await mcp.tool("execute_luau", { code: CLEAN_LUAU });

	console.log("");
	console.log("=== 2. La misma jerarquia via import_rbxm ===");
	fs.writeFileSync(RBXM, RBXM_CONTENT, "utf8");
	fs.writeFileSync(
		ARGS,
		JSON.stringify({ source: { path: RBXM }, parent_path: "game.Workspace", target: "edit" }),
		"utf8"
	);

	// `mcp.tool(name, args)` pasa los argumentos TAL CUAL a la herramienta.
	// `sync-all.js` usa un fichero porque su envoltorio (`studio-mcp.js`)
	// lee ese fichero; aqui se llama a `mcp` directamente, asi que hay que
	// pasar el objeto. Pasar `{ jsonfile: ... }` hacia `import_rbxm`
	// produce "data must have required property 'source'", que es
	// exactamente lo que paso al intentar la sonda por primera vez.
	const importResult = await mcp.tool("import_rbxm", {
		source: { path: RBXM },
		parent_path: "game.Workspace",
		target: "edit",
	});
	console.log("  import_rbxm devolvio: " + textOf(importResult).slice(0, 300));

	const imported = textOf(await mcp.tool("execute_luau", { code: COUNT_LUAU }));
	console.log("  hijos de HostPart: " + imported);

	// La sonda no debe quedarse en el mapa del juego.
	await mcp.tool("execute_luau", { code: CLEAN_LUAU });

	fs.rmSync(RBXM, { force: true });
	fs.rmSync(ARGS, { force: true });

	console.log("");
	console.log("=== JUICIO ===");
	if (manual.indexOf("ChildPart") !== -1) {
		console.log("  Studio ACEPTA Part-hijo-de-Part: la jerarquia NO es el problema.");
	} else {
		console.log("  Studio NO admite Part-hijo-de-Part.");
	}

	if (imported.indexOf("ChildPart") === -1 && imported.indexOf("ChildLight") !== -1) {
		console.log("  `import_rbxm` DROPEA los hijos Part y CONSERVA los PointLight.");
		console.log("  CONCLUSION: la decoracion debe ir en una CARPETA hermana, no colgada");
		console.log("  de la Part. Es un cambio de JERARQUIA del mapa, no de contrato.");
		process.exitCode = 1;
	} else if (imported.indexOf("ChildPart") !== -1) {
		console.log("  `import_rbxm` conserva ambos: la perdida del bosque es de otro paso.");
	} else {
		console.log("  La importacion perdio AMBOS: el fallo es del importador en general.");
	}
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(2);
});