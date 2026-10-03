"use strict";

/*
	generate-ai-context.js

	Genera `.ai/AI_CONTEXT.md`: el indice que debe leer Cline antes de
	tocar la arquitectura.

	Por que no es una copia de la documentacion:
	El proyecto ya tiene `docs/phases.md` como FUENTE DE VERDAD del estado
	(fases 0 y 1, con PASS/BLOCKED/NO INICIADA). Este archivo no lo
	redefine ni lo duplica: lo apunta, resume en pocas lineas y anade
	unicamente lo que es derivado del entorno y puede quedar obsoleto
	(commit, herramientas, resultado de la ultima verificacion).

	REGLA: nada de aqui afirma estado de juego. El juego se verifica
	en Studio; ver `tools/diagnostics/runtime-scan.js`.

	Uso:  node tools/generate-ai-context.js
*/

const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const root = process.cwd();

function run(command) {
	try {
		return cp
			.execSync(command, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
			.trim();
	} catch (e) {
		return null;
	}
}

function exists(p) {
	return fs.existsSync(path.join(root, p));
}

function readIfExists(p, fallback = null) {
	const full = path.join(root, p);
	return fs.existsSync(full) ? fs.readFileSync(full, "utf8") : fallback;
}

function listLuauFiles() {
	const out = [];
	const skip = new Set([".git", "node_modules", ".ai", ".cache", ".gradle", ".android", "rojo"]);

	(function walk(dir) {
		if (!fs.existsSync(dir)) return;
		for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
			if (skip.has(item.name)) continue;
			const full = path.join(dir, item.name);
			if (item.isDirectory()) walk(full);
			else if (/\.luau$|\.lua$/.test(item.name)) out.push(path.relative(root, full));
		}
	})(root);

	return out.sort();
}

// Estado de fases: se EXTRAE de docs/phases.md, no se reescribe aqui.
const phasesDoc = readIfExists("docs/phases.md", "");
const phaseRows = phasesDoc
	.split("\n")
	.filter((l) => /^\|\s*\d/.test(l) && /\|\s*(PASS|FAIL|BLOCKED|NO INICIADA)/.test(l))
	.map((l) => l.trim())
	.slice(0, 12);

const verification = readIfExists(".ai/runtime/environment-verification.json");
let verificationBlock = "AUSENTE: ejecutar `node tools/verify-environment.js`";
if (verification) {
	try {
		const v = JSON.parse(verification);
		verificationBlock = [
			"| Rojo build | " + v.tools.rojoBuild + " |",
			"| Suite Luau | " + v.tools.testSuite + " |",
			"| verify-structure | " + v.tools.verifyStructure + " |",
			"| verify-wiring | " + v.tools.verifyWiring + " |",
			"| analyze.js (typecheck) | " + (v.codeHealth ? v.codeHealth.analyze : "AUSENTE") + " |",
			"| Studio/MCP | " + v.studio + " |"
		].join("\n");

		// `analyze` NO es una puerta del entorno: es un estado PREEXISTENTE
		// del codigo del juego. Se imprime con su nota para que quede
		// visible y no se lea como un fallo del arranque.
		if (v.codeHealth && v.codeHealth.analyze !== "OK") {
			verificationBlock +=
				"\n\n> analyze.js esta en FAIL. Es previo a este bootstrap " +
				"(521 incidencias tambien sin estos archivos) y corresponde a " +
				"`.ai/qa/ACCEPTANCE_TESTS.md`, no al entorno. No se maquilla " +
				"como PASS ni se oculta.";
		}

	} catch (e) {
		verificationBlock = "JSON ilegible; volver a ejecutar la verificacion.";
	}
}

const luau = listLuauFiles();
const services = luau.filter((f) => /Services?[/\\]/.test(f));
const controllers = luau.filter((f) => /Controllers?[/\\]/.test(f));
const specs = luau.filter((f) => f.includes("tests/") && f.endsWith(".spec.lua"));

const status = run("git status --short") || "CLEAN";
const branch = run("git branch --show-current") || "?";
const commit = run("git rev-parse --short HEAD") || "?";
const lastCommitSubject = run('git log -1 --pretty=%s') || "?";

const context = `# KESHUSYTOMY-LAN-D - CONTEXTO IA

Generado: ${new Date().toISOString()}

> Este archivo es un INDICE generado, no una fuente de verdad.
> La fuente de verdad del estado del desarrollo es \`docs/phases.md\`.
> Si este archivo y \`docs/phases.md\` se contradicen, gana \`docs/phases.md\`.

## Git

- Rama: \`${branch}\`
- Commit: \`${commit}\` - ${lastCommitSubject}
- Arbol: ${status === "CLEAN" ? "limpio" : "CON CAMBIOS SIN COMMITear"}

## FUENTES DE VERDAD (leer antes de decidir)

| Documento | Rol |
| --- | --- |
| \`docs/phases.md\` | estado real por fase (PASS / BLOCKED / NO INICIADA) |
| \`docs/architecture.md\` | capas y reglas de diseno |
| \`docs/audit.md\` | auditoria de la fase 1 |
| \`docs/runtime-source-diff.md\` | diferencias runtime vs source |
| \`docs/sync-defects.md\` | defectos de sincronizacion conocidos |
| \`.ai/spec/GAME_SPEC.md\` | reglas de producto (indice, no estado) |
| \`.ai/qa/ACCEPTANCE_TESTS.md\` | checklist de aceptacion |
| \`tools/README.md\`, \`tests/README.md\` | convenciones de herramientas y pruebas |

## ULTIMA VERIFICACION DEL ENTORNO

${verificationBlock}

## Convenciones

- Layout de pruebas: \`tests/shared\`, \`tests/server\`, \`tests/client\`
- Nombre de suite: \`<Modulo>.<Area>.spec.lua\`
- Ejecutar: \`tools\\luau\\luau.exe tests\\RunTests.lua\`
- Analisis estatico de autoridad: \`node tools/analyze.js\`
  (prelude \`tools/roblox-definitions/RobloxEnvironment.lua\`; **no** usar
  \`luau-analyze\` pelado, produce cientos de falsos positivos)
- Rojo local: \`rojo\\rojo.exe\` (ignorado por git a proposito)

## Inventario de fuente

- Luau total: ${luau.length}
- Servicios de servidor: ${services.length}
- Controllers de cliente: ${controllers.length}
- Suites de prueba: ${specs.length}

## REGLA INNEGOCIABLE

Ninguna funcionalidad esta terminada porque el archivo exista.
Solo esta terminada cuando se verifico la cadena completa:

    SOURCE -> BUILD -> ROJO -> STUDIO -> PLAY -> PLAYER -> INPUT
    -> SERVER -> RESULTADO -> REWARD/PERSISTENCIA -> QA

Un script que lee archivos demuestra que los archivos existen. No
demuestra nada sobre el juego en ejecucion. Para eso esta
\`tools/diagnostics/runtime-scan.js\`, que consulta Studio via MCP y
reporta \`BLOCKED\` cuando no puede comprobarlo.
`;

fs.mkdirSync(path.join(root, ".ai"), { recursive: true });
fs.writeFileSync(path.join(root, ".ai/AI_CONTEXT.md"), context, "utf8");

console.log(context);
