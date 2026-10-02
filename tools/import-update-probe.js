"use strict";

/*
	import-update-probe.js
	Mide si `import_rbxm` ACTUALIZA las propiedades de una instancia que YA
	existe con el mismo nombre.

	POR QUE EXISTE
	--------------
	Tras reconstruir el bosque, los bloques llegaron a Studio con la
	decoracion nueva (325 hijos `Deco_*`) pero con la geometria VIEJA:
	`Block_0` media 8x8x8 en vez de 6x11x6 y estaba en y = 4 en vez de
	y = 5.5.

	El `.rbxm` que se importa TIENE los valores correctos:

	    <Vector3 name="size">      6, 11, 6
	    <Vector3 name="Position">  477.5, 5.5, -45
	    <Vector3 name="Orientation"> -7, 220, -7

	asi que el problema no es la fuente. La unica explicacion que queda es
	que la importacion trate "ya existe este nombre" como "no toques las
	propiedades de lo que ya hay".

	La consecuencia es GRAVE y conviene dejar escrita: si el importador no
	refresca propiedades, cambiar el tamano o el material de una pieza del
	mapa NO llega a Studio por esa via, y la unica forma fiable seria
	purgar el mapa entero antes de importar.

	La sonda importa DOS veces el mismo `.rbxm`: la primera crea las
	instancias, la segunda tendria que actualizar sus valores. Despues se
	mira si la segunda ha tenido efecto.

	Uso:  node tools/import-update-probe.js
*/

const fs = require("fs");
const path = require("path");

const mcp = require("./mcp");

const ROOT = path.resolve(__dirname, "..");
const CACHE = path.join(ROOT, ".cache");
const RBXM = path.join(CACHE, "update-probe.rbxm");

/** Estado de la sonda: tamano y posicion de `HostPart`. */
const READ_LUAU = `
local Workspace = game:GetService("Workspace")
local probe = Workspace:FindFirstChild("UpdateProbe")
if not probe then return "sin sonda" end
local host = probe:FindFirstChild("HostPart")
if not host then return "sonda sin HostPart" end
local s = host.Size
local p = host.Position
return string.format("size=%.1fx%.1fx%.1f pos=%.1f,%.1f,%.1f hijos=%d",
	s.X, s.Y, s.Z, p.X, p.Y, p.Z, #host:GetChildren())
`;

const CLEAN_LUAU = `
local p = game:GetService("Workspace"):FindFirstChild("UpdateProbe")
if p then p:Destroy() end
return "limpiado"
`;

/**
 * Construye el `.rbxm` con los valores pedidos.
 * @param {number[]} size
 * @param {number[]} pos
 */
function rbxmFor(size, pos) {
	return `<roblox version="4">
  <Item class="Folder" referent="1">
    <Properties>
      <string name="Name">UpdateProbe</string>
    </Properties>
    <Item class="Part" referent="2">
      <Properties>
        <string name="Name">HostPart</string>
        <bool name="Anchored">true</bool>
        <Vector3 name="Position">
          <X>${pos[0]}</X>
          <Y>${pos[1]}</Y>
          <Z>${pos[2]}</Z>
        </Vector3>
        <Vector3 name="size">
          <X>${size[0]}</X>
          <Y>${size[1]}</Y>
          <Z>${size[2]}</Z>
        </Vector3>
      </Properties>
    </Item>
  </Item>
</roblox>
`;
}

const textOf = (res) => String(res && res.returnValue !== undefined ? res.returnValue : res);

async function importOnce(size, pos) {
	fs.writeFileSync(RBXM, rbxmFor(size, pos), "utf8");
	await mcp.tool("import_rbxm", {
		source: { path: RBXM },
		parent_path: "game.Workspace",
		target: "edit",
	});
	return textOf(await mcp.tool("execute_luau", { code: READ_LUAU }));
}

async function main() {
	fs.mkdirSync(CACHE, { recursive: true });
	await mcp.tool("execute_luau", { code: CLEAN_LUAU });

	console.log("=== 1. Primera importacion (crea HostPart) ===");
	const first = await importOnce([4, 4, 4], [10, 20, 30]);
	console.log("  " + first);

	console.log("");
	console.log("=== 2. Segunda importacion (deberia ACTUALIZAR) ===");
	console.log("   se pide size=20x30x10 y pos=100,200,300");
	const second = await importOnce([20, 30, 10], [100, 200, 300]);
	console.log("  " + second);

	await mcp.tool("execute_luau", { code: CLEAN_LUAU });
	fs.rmSync(RBXM, { force: true });

	// La sonda se destruye SIEMPRE, incluso si el importador no actualiza.
	// Antes se borraba solo en el camino feliz y se dejaba puesta cuando la
	// sonda "fallaba", que era justo el caso interesante: la carpeta se
	// quedaba en `Workspace` y contaminaba el recuento de instancias de
	// `source-runtime-diff`.
	await mcp.tool("execute_luau", {
		code: `
local probe = game:GetService("Workspace"):FindFirstChild("UpdateProbe")
if probe then
	probe:Destroy()
	return "sonda purgada"
end
return "no habia sonda"
`,
	});

	console.log("");
	console.log("=== JUICIO ===");
	const updated = /size=20\.0x30\.0x10\.0/.test(second) && /pos=100\.0,200\.0,300\.0/.test(second);

	if (updated) {
		console.log("  `import_rbxm` ACTUALIZA las propiedades existentes: PASS.");
		console.log("  El desfase del bosque tiene otra causa.");
	} else {
		console.log("  `import_rbxm` IGNORA las propiedades de lo que ya existe.");
		console.log("");
		console.log("  CONSECUENCIA: cambiar tamano, material o rotacion de una pieza");
		console.log("  del mapa NO llega a Studio por `import_rbxm`. Solo llega si la pieza");
		console.log("  es NUEVA. Por eso hay que PURGAR el mapa antes de importar cuando");
		console.log("  se reescribe la geometria, y no confiar en una fusion incremental.");
		process.exitCode = 1;
	}
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exit(2);
});