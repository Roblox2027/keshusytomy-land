// combat-verify.js
// Ejecuta tools/combat-verify.lua en el servidor vivo y juzga el resultado.
//
// POR QUE EL LUAU VIVE EN UN ARCHIVO APARTE
// ----------------------------------------
// La primera version llevaba el Luau embebido en un literal de plantilla JS.
// Un `$` o un backtick dentro del snippet puede cerrar ese literal antes de
// tiempo, y entonces Node ejecuta Luau como si fuera JavaScript: el modulo
// falla con un ReferenceError por una variable que solo existe DENTRO del
// texto (por ejemplo `combat is not defined`) y blames a la linea 1, que es
// un comentario. `node -c` lo daba por valido, porque el literal si estaba
// balanceado: lo que estaba mal era donde terminaba.
//
// Con el Luau en su propio archivo no hay literal, no hay backtick y no hay
// nada que reinterpretar.
//
// QUE SE VERIFICA Y QUE NO
// -----------------------
// El puente MCP de Studio rechaza `Instance:AddChild()` (se comprobo que el
// receptor es una Instance valida y que `Parent = ...` si funciona sobre el
// mismo Folder). Colocar una bomba desde este contexto es imposible, y
// presentarlo como un fallo de `BombService` seria falso.
//
// Asi que NO se coloca ninguna bomba. Se mide la cadena de REGLAS: la ronda
// tiene que estar en curso, una bomba lejos del jugador tiene que rechazarse,
// y el bloque tiene que recibir dano, secretarse y repararse.
//
// Uso:  node tools/combat-verify.js

const fs = require("fs");
const path = require("path");

const mcp = require("./mcp");

const SNIPPET = path.join(__dirname, "combat-verify.lua");

function report(res) {
	console.log("COMBATE Y DESTRUCCION (reglas, sin crear instancias)");
	console.log("---------------------------------------------------------------");
	if (!res || typeof res !== "object") {
		console.log("  sin respuesta del servidor: " + JSON.stringify(res));
		return false;
	}
	if (res.error) {
		console.log("  la prueba no pudo arrancar: " + res.error);
		return false;
	}

	for (const s of res.steps) console.log("  " + s);

	const d = res.destruction;
	console.log("");
	console.log("DESTRUCCION");
	console.log("  bloques visibles antes:   " + d.before);
	console.log("  bloques registrados:      " + d.registered);
	console.log("  bloque probado:           " + d.block);
	console.log(`  antes:  transp=${d.transparencyBefore} collide=${d.canCollideBefore}`);
	console.log("  impactos hasta destruir:  " + d.hits);
	console.log(`  vida final: ${d.finalHealth}`);
	console.log(`  despues: transp=${d.transparencyAfter} collide=${d.canCollideAfter}`);
	console.log(`  atributo IsDestroyed:     ${d.isDestroyedAttr}`);
	console.log("  bloques visibles:         " + d.after);
	console.log("  destruidos segun servicio:" + d.destroyedCount);
	console.log("  tras RestoreAll:");
	console.log(`    visibles=${d.afterRestore} destruidos=${d.destroyedAfterRestore}`);
	console.log(`    transp=${d.transparencyRestored} collide=${d.collideRestored}`);

	console.log("");
	// `ApplyDamage` devuelve true justo cuando destruye: dos impactos con 60
	// de dano y 100 de vida son el minimo que el diseno permite.
	const destroyed = d.after < d.before && d.isDestroyedAttr === true;
	const hidden = d.transparencyAfter >= 1 && d.canCollideAfter === false;
	const repaired = d.afterRestore === d.before && d.destroyedAfterRestore === 0;
	const ok = destroyed && hidden && repaired;

	console.log("COMBATE/DESTRUCCION: " + (ok ? "PASS" : "FAIL"));
	if (!ok) {
		console.log("");
		console.log("  Se esperaba que el bloque, tras acumular dano suficiente:");
		console.log("    - se SECRETE (transparente y sin colision), no se destruya,");
		console.log("      para que RestoreAll pueda repararlo en la siguiente ronda;");
		console.log("    - marque IsDestroyed, que es lo que lee el resto del juego;");
		console.log("    - y RestoreAll devuelva la arena a su estado original.");
	}
	return ok;
}

async function main() {
	const inst = await mcp.toolJson("get_connected_instances", {});
	if (!inst?.instances?.some((i) => i.peers && i.peers.server)) {
		console.log("SIN SERVIDOR EN VIVO: arranca Play con `node tools/play.js start`.");
		process.exitCode = 2;
		return;
	}

	const code = fs.readFileSync(SNIPPET, "utf8");
	const res = await mcp.serverLuau(code);
	if (!report(res)) process.exitCode = 1;
}

main().catch((e) => {
	console.error("FALLO: " + e.message);
	process.exitCode = 2;
});
