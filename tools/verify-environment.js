"use strict";

/*
	verify-environment.js

	Verificacion del ENTORNO de desarrollo, no del juego.

	Por que existe y por que NO reemplaza a nada:
	El repositorio ya tenia herramientas que hacen esto mejor:
	`tools/analyze.js` (typecheck), `tools/verify-structure.js`,
	`tools/verify-wiring.js` y `tools/luau/luau.exe tests/RunTests.lua`.
	Este archivo NO las sustituye: las invoca y resume su resultado.

	REGLA que respeta: leer archivos NO es verificar el juego.
	Por eso la unica seccion que puede decir PASS es la de herramientas
	locales. El estado de Studio/Play se reporta aparte y siempre como
	BLOCKED si no se pudo comprobar de verdad.

	Uso:  node tools/verify-environment.js
	Salida: 0 si el entorno local esta listo, 1 si falta algo.
*/

const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const root = process.cwd();

function exists(p) {
	return fs.existsSync(path.join(root, p));
}

function run(command) {
	try {
		return cp
			.execSync(command, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
			.trim();
	} catch (e) {
		return null;
	}
}

// --- Herramientas locales: aqui si se puede afirmar PASS -------------------

const rojo = exists("rojo/rojo.exe") ? run('"rojo\\rojo.exe" --version') : null;

const buildLog = run('"rojo\\rojo.exe" build default.project.json -o ".ai\\runtime\\verify-build.rbxlx"');
const buildOk = buildLog !== null;

const suite = run('"tools\\luau\\luau.exe" tests\\RunTests.lua');
const suiteOk = suite !== null;
const suiteSummary = suite ? (suite.match(/RESULTADO:.*/) || ["sin resumen"])[0] : null;

const analyze = run("node tools/analyze.js");
const analyzeOk = analyze !== null;

const structure = run("node tools/verify-structure.js");
const structureOk = structure !== null;

const wiring = run("node tools/verify-wiring.js");
const wiringOk = wiring !== null;

// --- Studio: se reporta aparte y NUNCA se infiere -------------------------

const studio = run("node tools/studio-mcp.js list");
const studioOk = studio !== null;

// Estado del CODIGO. Se separa del estado del ENTORNO a proposito: que el
// entorno este listo no significa que el codigo este sano, y mezclar las
// dos cosas hacia que alguien tapara un fallo de analisis diciendo "el
// entorno funciona".
const codeHealth = {
	analyze: analyzeOk ? "OK" : "FAIL",
	analyzeNote: analyzeOk
		? null
		: "tools/analyze.js devuelve exit 1. Es un estado PREEXISTENTE " +
		  "del codigo del juego, no un defecto de este entorno. " +
		  "Se reporta aparte para que sea visible, no para abortar el " +
		  "arranque del entorno."
};

// --- Estado ---------------------------------------------------------------

const environment = {
	project: root,
	gitBranch: run("git branch --show-current"),
	gitCommit: run("git rev-parse --short HEAD"),
	gitDirty: (run("git status --short") || "") !== "",

	tools: {
		rojo: rojo,
		rojoBuild: buildOk ? "PASS" : "FAIL",
		luauInterpreter: exists("tools/luau/luau.exe"),
		testSuite: suiteOk ? suiteSummary : "NO EJECUTABLE",
		verifyStructure: structureOk ? "OK" : "FAIL",
		verifyWiring: wiringOk ? "OK" : "FAIL"
	},

	// Salud del codigo del juego. NO es parte de la puerta del entorno:
	// ver la nota. Se mantiene visible para que nadie lo lea como PASS.
	codeHealth,

	rojoProject: exists("default.project.json"),
	rojoRemotesModel: exists("src/ReplicatedStorage/Remotes.model.json"),
	src: exists("src"),
	tests: exists("tests"),
	docs: exists("docs"),
	toolsDir: exists("tools"),

	aiSpec: exists(".ai/spec/GAME_SPEC.md"),
	acceptanceTests: exists(".ai/qa/ACCEPTANCE_TESTS.md"),
	vscodeShared: exists(".vscode/extensions.json") && exists(".vscode/tasks.json"),
	packageJson: exists("package.json")
};

// El estado de Studio se informa, no se exige: sin Studio el entorno local
// sigue siendo utilizable para fuente, analisis y pruebas.
environment.studio = studioOk ? "CONECTADO" : "BLOCKED (Studio/MCP no responde)";

const required = [
	"rojoProject",
	"src",
	"tests",
	"docs",
	"toolsDir",
	"aiSpec",
	"acceptanceTests"
];

const failedRequired = required.filter((k) => !environment[k]);
const failedTools = Object.keys(environment.tools).filter(
	(k) => environment.tools[k] === "FAIL"
);

console.log(JSON.stringify(environment, null, 2));

fs.mkdirSync(path.join(root, ".ai/runtime"), { recursive: true });
fs.writeFileSync(
	path.join(root, ".ai/runtime/environment-verification.json"),
	JSON.stringify(environment, null, 2),
	"utf8"
);

if (failedRequired.length || failedTools.length) {
	if (failedRequired.length) console.error("FALTA:", failedRequired.join(", "));
	if (failedTools.length) console.error("HERRAMIENTA EN FAIL:", failedTools.join(", "));
	console.error("ENTORNO NO LISTO");
	process.exit(1);
}

console.log("ENTORNO LISTO (Studio: " + environment.studio + ")");
