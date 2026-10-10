const path = require('path');
const proj = require(path.join(__dirname, '..', 'default.project.json'));
const lobby = proj.tree.Workspace.Lobby;

// Check specific parts that show at 0,0,0 at runtime
const checkNames = ['LobbyFloor', 'Lamp_8', 'Lamp_9', 'Lamp_10', 'Lamp_11', 'PvPArena_Floor', 'Podium_Base', 'ShopHall_Floor', 'SafeZone_Sign', 'Plaza_Party_Rug'];
for (const name of checkNames) {
    const child = lobby[name];
    if (child) {
        const props = child.$properties || {};
        console.log(name + ': Position=' + JSON.stringify(props.Position) + ' Size=' + JSON.stringify(props.Size) + ' class=' + child.$className);
    } else {
        console.log(name + ': NOT FOUND IN LOBBY');
    }
}

// Check if these parts are inside subfolders
console.log('\n--- Lobby direct children that are Part ---');
let directParts = 0;
let folderChildren = 0;
for (const key of Object.keys(lobby)) {
    if (key === '$className' || key === '$properties') continue;
    if (directParts < 30) console.log('  ' + key + ': ' + (lobby[key].$className || 'unknown'));
    directParts++;
}
console.log('Total direct children: ' + directParts);
