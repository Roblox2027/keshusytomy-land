const fs = require('fs');
const proj = JSON.parse(fs.readFileSync('default.project.json', 'utf-8'));
const lobby = proj.tree.Workspace.Lobby;

for (const name of ['LobbyFloor', 'Station_Training_Lamp', 'PvPArena_Floor', 'Lamp_8']) {
    const p = lobby[name];
    if (p) {
        console.log(name + ':');
        console.log('  Position:', JSON.stringify(p.$properties?.Position));
        console.log('  Position type:', typeof p.$properties?.Position);
        console.log('  Size:', JSON.stringify(p.$properties?.Size));
    }
}
