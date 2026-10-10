const fs = require('fs');
const proj = JSON.parse(fs.readFileSync('default.project.json', 'utf-8'));
const lobby = proj.tree.Workspace.Lobby;

// Compare working vs broken parts
const check = ['Lamp_0', 'Lamp_8', 'CodesPoint', 'LobbyFloor', 'LobbyWall_N', 'Station_Shop_Lamp', 'PvPArena_Floor'];
for (const name of check) {
    const p = lobby[name];
    if (p) {
        const props = p.$properties || {};
        console.log(name + ':');
        console.log('  Position:', JSON.stringify(props.Position));
        console.log('  CanCollide:', props.CanCollide);
        console.log('  Material:', props.Material);
        console.log('  Transparency:', props.Transparency);
        console.log('  Size:', JSON.stringify(props.Size));
    } else {
        console.log(name + ': NOT FOUND');
    }
}
