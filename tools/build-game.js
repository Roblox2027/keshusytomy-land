// build-game.js
// UN SOLO COMANDO PARA TENER EL JUEGO LISTO.
//
// POR QUE EXISTE
// --------------
// El juego tiene muchos `.rbxlx` repartidos en `.cache/` y `.ai/runtime/`
// (restos de pruebas antiguas). Si abres uno de esos, NO ves la ultima
// modificacion: ves una foto vieja. Este script deja un UNICO archivo
// canonico en la raiz (`KESHUSY-LAN-D.rbxlx`), siempre con lo ultimo, y borra
// antes los `.rbxlx` viejos del cache para que no haya nada que confunda.
//
// HACE, EN ESTE ORDEN:
//   1. Borra los `.rbxlx` viejos de `.cache/` y `.ai/runtime/`.
//   2. Regenera `default.project.json` (lobby, mundos, monstruos, scripts).
//   3. Construye el archivo canonico `KESHUSY-LAN-D.rbxlx` en la raiz.
//
// USO:
//   node tools/build-game.js
//   npm run build:game
//
// Despues abre `KESHUSY-LAN-D.rbxlx` en Studio. Ese archivo es SIEMPRE lo
// ultimo. Si prefieres edicion en vivo, usa `rojo serve` (npm run rojo:serve).

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const CANONICAL = path.join(ROOT, "KESHUSY-LAN-D.rbxlx");

function step(msg) {
	console.log(`\n=== ${msg} ===`);
}

function run(cmd) {
	// Hereda stdio para que se vea el progreso de Rojo/generador en directo.
	execSync(cmd, { stdio: "inherit", cwd: ROOT, shell: process.env.ComSpec || "cmd.exe" });
}

// 1. Limpieza de cache. Se borran TODOS los `.rbxlx` de las carpetas de cache
//    (`.cache/`, `.ai/runtime/`) y tambien los `.rbxlx` sueltos de la RAIZ que
//    no sean el canonico (restos de `build.rbxlx`, `forest.rbxlx`, etc. que
//    confundian: abrir uno daba una foto vieja). NUNCA se toca `src/`.
function cleanCache() {
	step("1/3  Limpiando .rbxlx viejos (cache + raiz)");
	const cacheDirs = [".cache", path.join(".ai", "runtime")];
	let removed = 0;

	for (const dir of cacheDirs) {
		const abs = path.join(ROOT, dir);
		if (!fs.existsSync(abs)) continue;

		for (const file of fs.readdirSync(abs)) {
			if (file.toLowerCase().endsWith(".rbxlx")) {
				fs.rmSync(path.join(abs, file), { force: true });
				removed += 1;
				console.log(`  borrado: ${dir}\\${file}`);
			}
		}
	}

	// Raiz: borra cualquier `.rbxlx` que NO sea el canonico, para que solo
	// quede `KESHUSY-LAN-D.rbxlx` y no haya nada mas que abrir por error.
	for (const file of fs.readdirSync(ROOT)) {
		const lower = file.toLowerCase();
		if (!lower.endsWith(".rbxlx")) continue;

		const abs = path.join(ROOT, file);
		if (!fs.statSync(abs).isFile()) continue;
		if (path.resolve(abs) === path.resolve(CANONICAL)) continue;

		fs.rmSync(abs, { force: true });
		removed += 1;
		console.log(`  borrado: ${file}`);
	}

	console.log(removed === 0 ? "  (nada que borrar)" : `  ${removed} archivo(s) borrado(s)`);
}

// 2. Regenerar el proyecto (default.project.json).
function generate() {
	step("2/3  Regenerando el proyecto");
	run("node tools/generate-project.js");
}

// 3. Construir el archivo canonico en la raiz.
function build() {
	step("3/3  Construyendo KESHUSY-LAN-D.rbxlx");
	run("rojo\\rojo.exe build default.project.json -o KESHUSY-LAN-D.rbxlx");
}

function report() {
	const stat = fs.statSync(CANONICAL);
	const mb = (stat.size / 1024 / 1024).toFixed(1);
	console.log("\n========================================================");
	console.log("  LISTO. Abre este archivo en Studio:");
	console.log(`    ${CANONICAL}`);
	console.log(`  ${mb} MB  -  ${stat.mtime.toLocaleString()}`);
	console.log("========================================================");
	console.log("  Este archivo es SIEMPRE lo ultimo. Los .rbxlx viejos");
	console.log("  del cache ya se borraron, asi que no hay nada que confunda.");
	console.log("  Para edicion en vivo: npm run rojo:serve");
}

try {
	cleanCache();
	generate();
	build();
	report();
} catch (err) {
	console.error("\n[build-game] FALLO:", err.message);
	process.exit(1);
}
