const fs = require('fs');
const proj = JSON.parse(fs.readFileSync('default.project.json', 'utf-8'));
const lobby = proj.tree.Workspace.Lobby;

// Check structure around PvPArena parts
console.log('=== Lobby top-level children ===');
for (const key of Object.keys(lobby)) {
    if (key === '$className' || key === '$properties') continue;
    const child = lobby[key];
    const props = child.$properties || {};
    console.log(key + ': class=' + child.$className + ' children=' + Object.keys(child).filter(k => k !== '$className' && k !== '$properties').length + ' Position=' + JSON.stringify(props.Position));
}

// Check if PvPArena parts are inside a Model
console.log('\n=== Checking PvPArena_Floor ===');
const pvpFloor = lobby.PvPArena_Floor;
if (pvpFloor) {
    console.log('Found at top level. Position:', JSON.stringify(pvpFloor.$properties?.Position));
} else {
    console.log('NOT at top level');
}

// Check all keys for PvA
console.log('\n=== All lobby keys starting with PvPArena ===');
for (const key of Object.keys(lobby).filter(k => k.startsWith('PvP'))) {
    console.log('  ' + key);
}

// Check all keys for Podium
console.log('\n=== All lobby keys starting with Podium ===');
for (const key of Object.keys(lobby).filter(k => k.startsWith('Podium'))) {
    const child = lobby[key];
    console.log('  ' + key + ': Position=' + JSON.stringify(child.$properties?.Position));
}

// Check ShopHall
console.log('\n=== All lobby keys starting with ShopHall ===');
for (const key of Object.keys(lobby).filter(k => k.startsWith('ShopHall'))) {
    const child = lobby[key];
    console.log('  ' + key + ': Position=' + JSON.stringify(child.$properties?.Position));
}

// Check SafeZone
console.log('\n=== All lobby keys starting with SafeZone ===');
for (const key of Object.keys(lobby).filter(k => k.startsWith('SafeZone'))) {
    const child = lobby[key];
    console.log('  ' + key + ': Position=' + JSON.stringify(child.$properties?.Position));
}
