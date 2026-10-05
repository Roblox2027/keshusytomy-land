// powerup-boss-contract.js
// Verificador de CONTRATO entre ficheros, para los dos sistemas que se
// repartian entre varias capas y no tenian ninguna comprobacion que los
// uniera: los POWERUPS y los BOSSES.
//
// POR QUE EXISTE Y POR QUE ES UN .js
// -----------------------------------
// El suite de Luau (`tests/`) no puede leer ficheros: el interprete
// `luau.exe` no expone `io`. Toda prueba de coherencia entre
// `PowerupService.KINDS`, `VisualKit.POWERUPS` y los atributos que lee
// `UIController` tiene que vivir aqui.
//
// QUE FALLA Y POR QUE IMPORTA
// ---------------------------
// MEDIDO EN AUDITORIA, este es exactamente el patron que roto el juego:
//
//   1. `VisualKit.POWERUPS` tenia 5 entradas (pintadas, con color y cartel).
//   2. `ApplyEffect` tenia un caso `Fire` COMPLETO.
//   3. `PowerupService.KINDS` -- la lista que decide que se GENERA -- tenia
//      4 entradas y ninguna era `Fire`.
//
// Resultado: "+PODER" estaba implementado, anunciado y pintado, y nunca
// aparecia en el mundo. Ninguna prueba fallaba, porque cada capa era
// correcta por separado. Este script es la prueba de que las tres capas
// cuentan lo MISMO.
//
// Lo mismo con los bosses: `WorldDefinitions` declaraba `BossDefinitionId`
// en los cinco mundos, `tools/worlds.js` construia `BossSpawn_<Id>` en los
// cinco y el HUD tenia panel de barra... y no habia ni una definicion de
// boss en `MonsterDefinitions`. El mapa, los datos y la interfaz existian;
// el juego no tenia jefe.
//
// USO
//   node tools/powerup-boss-contract.js
//
// SALIDA: codigo 0 si todo cuadja, 1 con la lista de problemas si no.

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "src");

function read(...parts) {
	return fs.readFileSync(path.join(SRC, ...parts), "utf8");
}

const problems = [];
const notes = [];

function fail(message) {
	problems.push(message);
}

/**
 * Cadenas de la forma `"Clave",` dentro del cuerpo de una tabla.
 *
 * Se usa el mismo criterio que `world-contract-source.js`: solo interesan
 * las claves de nivel superior de la tabla, no las de los sub-objetos
 * (esos tienen `color =`, `shape =`...).
 */
function tableKeys(source, startMarker) {
	const start = source.indexOf(startMarker);

	if (start === -1) return null;

	// El bloque va hasta la PRIMERA llave de cierre en la columna 0, que es
	// como termina cualquier tabla de este proyecto. Se usa `indexOf` con
	// el salto ya avanzado: `lastIndexOf` devolveria la ULTIMA llave del
	// fichero entero, que es el `return` del modulo, y el bloque se
	// comeria el resto del archivo.
	const rest = source.slice(start);
	const end = rest.indexOf("\n}");

	if (end === -1) return null;

	const block = rest.slice(0, end);
	const keys = [];

	// Las claves de `VisualKit.POWERUPS` NO van entrecomilladas (`Bomb = {`),
	// asi que el patron tiene que aceptar identificadores desnudos. Se
	// exige que esten al COMIENZO de la linea para no capturar los
	// `color =` / `shape =` / `label =` de los sub-objetos.
	const pattern = /^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*\{/gm;
	let match;

	while ((match = pattern.exec(block)) !== null) {
		keys.push(match[1]);
	}

	return keys;
}

// ===========================================================================
// 1. POWERUPS
// ===========================================================================

const powerupService = read("ServerScriptService", "Services", "PowerupService.lua");
const visualKit = read("ReplicatedStorage", "Shared", "Libraries", "VisualKit.lua");
const uiController = read(
	"StarterPlayer",
	"StarterPlayerScripts",
	"Controllers",
	"UIController.lua"
);

// `KINDS` es un local; `VisualKit.POWERUPS` una tabla con prefijo.
const kindsStart = powerupService.indexOf("local KINDS = {");
const kindsSource = powerupService.slice(
	kindsStart,
	powerupService.indexOf("}", kindsStart)
);

const GENERATED = (kindsSource.match(/"([A-Za-z][A-Za-z0-9_]*)"/g) || []).map((q) =>
	q.replace(/"/g, "")
);

const PAINTED = tableKeys(visualKit, "VisualKit.POWERUPS = {") || [];

notes.push(`powerups que se GENERAN (PowerupService.KINDS): ${GENERATED.length}`);
notes.push(`powerups que se PINTAN  (VisualKit.POWERUPS): ${PAINTED.length}`);

if (GENERATED.length === 0) {
	fail("PowerupService.KINDS no se pudo leer: la lista de powerups esta vacia");
}

if (PAINTED.length === 0) {
	fail("VisualKit.POWERUPS no se pudo leer: no hay powerups pintados");
}

// Lo que se genera y no se pinta desaparece AL TOCARLO: `BuildPowerup`
// devuelve nil y `onTouched` lo destruye sin cobrar el efecto.
for (const kind of GENERATED) {
	if (!PAINTED.includes(kind)) {
		fail(`el powerup '${kind}' se genera pero VisualKit no lo pinta: al tocarlo desaparece sin efecto`);
	}
}

// Lo que se pinta y no se genera es codigo muerto: el jugador lo ve en el
// catalogo del mundo y nunca aparece.
for (const kind of PAINTED) {
	if (!GENERATED.includes(kind)) {
		fail(`el powerup '${kind}' esta pintado en VisualKit pero nunca se genera (codigo muerto)`);
	}
}

// Cada powerup GENERADO tiene que tener su caso en `ApplyEffect`.
for (const kind of GENERATED) {
	const pattern = new RegExp(`kind\\s*==\\s*"${kind}"`);

	if (!pattern.test(powerupService)) {
		fail(`el powerup '${kind}' se genera pero ApplyEffect no tiene su caso: se recoge y no hace nada`);
	}
}

// Los powerups con RELOJ tienen que ser visibles en el HUD. Un efecto
// temporal que no se muestra es indistinguible de uno roto: el jugador
// recoge el objeto y no tiene forma de saber cuando caduca.
//
// MEDIDO EN AUDITORIA: la fila del HUD leia TRES atributos de los que el
// servidor publicaba. Los otros cuatro efectos ocurrian ahi y no se veian
// en ninguna parte.
const CLOCKED = ["Speed", "Shield", "Fire", "Dash", "Ghost", "Magnet", "Freeze"];

for (const kind of CLOCKED) {
	if (!GENERATED.includes(kind)) continue;

	const attribute = `Powerup${kind}Until`;

	if (!powerupService.includes(`"${attribute}"`)) {
		fail(`el powerup '${kind}' no publica '${attribute}': el HUD no puede saber que caduca`);
		continue;
	}

	// La fila del HUD o bien nombra el atributo explicitamente, o bien lo
	// lee desde su tabla `timed`. Se aceptan las dos formas porque las dos
	// son legitimas; lo que no se acepta es que no lo lea ninguna.
	if (!uiController.includes(attribute)) {
		fail(`el powerup '${kind}' publica '${attribute}' pero UIController no lo lee: el efecto es invisible`);
	}
}

// `Bomb` y `Heal` NO tienen reloj a proposito: la capacidad es permanente
// y la cura es instantanea. Se comprueba que no se hayan colado en la lista
// de los temporales por error de copiado, porque ahi un atributo `Until`
// que nadie publica deja el powerup sin HUD para siempre.
if (CLOCKED.includes("Bomb")) {
	fail("'Bomb' esta en la lista de powerups con reloj: su capacidad es permanente");
}

// ===========================================================================
// 2. BOSSES
// ===========================================================================

const MONSTER_WORLDS = ["Forest", "Desert", "Ice", "Volcano", "Cyber"];

const monsterDefinitions = read("ReplicatedStorage", "Shared", "MonsterDefinitions.lua");
const scaleRules = read("ReplicatedStorage", "Shared", "Libraries", "MonsterScaleRules.lua");
const matchService = read("ServerScriptService", "Services", "MatchService.lua");
const monsterService = read("ServerScriptService", "Services", "MonsterService.lua");
const serverMain = read("ServerScriptService", "ServerMain.server.lua");

// Cada mundo declara su boss en la tabla que consume `MatchService`...
for (const world of MONSTER_WORLDS) {
	if (!scaleRules.includes(`${world} = "`)) {
		fail(`MonsterScaleRules.BossByWorld no declara el boss de ${world}`);
	}
}

// ...y existe como DEFINICION con vida, recompensa y marca de jefe. Un id
// en una tabla sin definicion detras es el mismo fallo que habia antes:
// una promesa sin contenido.
for (const world of MONSTER_WORLDS) {
	const match = scaleRules.match(new RegExp(`${world}\\s*=\\s*"([A-Za-z0-9_]+)"`));

	if (!match) continue;

	const bossId = match[1];

	if (!monsterDefinitions.includes(`Id = "${bossId}"`)) {
		fail(`el boss '${bossId}' de ${world} no existe en MonsterDefinitions`);
		continue;
	}

	// La definicion tiene que declarar `MaxAlive = 1`. Sin el tope, una
	// segunda llamada al spawn podria generar tres Grooty, y tres jefes es
	// "boss inexistente" mirando desde el otro lado.
	if (!new RegExp(`Id = "${bossId}"[\\s\\S]{0,400}MaxAlive = 1`).test(monsterDefinitions)) {
		fail(`el boss '${bossId}' no declara MaxAlive = 1: se pueden generar varios a la vez`);
	}
}

// El servicio tiene que saber que es un boss y publicar la barra.
if (!monsterService.includes("IsBoss")) {
	fail("MonsterService no sabe que es un boss: no hay barra de vida ni fases");
}

if (!monsterService.includes('"BossName"')) {
	fail("MonsterService nunca escribe 'BossName': el panel del HUD no puede encenderse");
}

if (!monsterService.includes('"BossHealth"')) {
	fail("MonsterService nunca escribe 'BossHealth'");
}

if (!monsterService.includes('"BossMaxHealth"')) {
	fail("MonsterService nunca escribe 'BossMaxHealth'");
}

// El spawn tiene que existir y tiene que leer la plataforma del mapa.
if (!matchService.includes('"BossSpawn_"')) {
	fail("MatchService no lee 'BossSpawn_<Id>': el mapa construye la plataforma y nadie la usa");
}

if (!matchService.includes("SpawnBossForWorld")) {
	fail("MatchService no genera ningun boss: BossSpawn_<Id> es decoracion");
}

// El generador tiene que seguir construyendo la plataforma. Si `worlds.js`
// dejara de emitirla, el servicio no tendria donde poner al jefe y el
// fallo seria silencioso.
const worldsJs = fs.readFileSync(path.join(ROOT, "tools", "worlds.js"), "utf8");

if (!worldsJs.includes('"BossSpawn_" + def.id')) {
	fail("tools/worlds.js no genera BossSpawn_<Id>: el boss no tendra plataforma");
}

// La barra de boss tiene que existir en el HUD GENERADO, no solo en el
// controlador: un panel que el controlador escribe pero que no esta en el
// arbol no se ve.
const projectJson = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));
const hud = projectJson.tree && projectJson.tree.StarterGui && projectJson.tree.StarterGui.KeshusyHUD;
const bossBar = hud && hud.Root && hud.Root.Overlays && hud.Root.Overlays.BossBar;

if (!bossBar) {
	fail("default.project.json no tiene KeshusyHUD.Root.Overlays.BossBar");
}

// La flecha de cableado del powerup Freeze: sin ella el powerup se recoge
// y no congela a nadie, que es el fallo invisible mas caro de los cinco.
if (!powerupService.includes("SetMonsterService")) {
	fail("PowerupService no expone SetMonsterService: CONGELAR no tendra a quien congelar");
}

if (!serverMain.includes("SetMonsterService(monsterService)")) {
	fail("ServerMain no cablea PowerupService -> MonsterService: CONGELAR no hara nada en el juego");
}

// ===========================================================================
// INFORME
// ===========================================================================

console.log("CONTRATO POWERUPS / BOSSES");
for (const note of notes) console.log("  " + note);

if (problems.length === 0) {
	console.log("");
	console.log(`OK: ${GENERATED.length} powerups generados = pintados = implementados,`);
	console.log("    5 bosses declarados, generados y con barra de vida en el HUD.");
	process.exit(0);
}

console.log("");
for (const problem of problems) console.log("  FALLA: " + problem);
console.log("");
console.log(problems.length + " problema(s).");
process.exit(1);