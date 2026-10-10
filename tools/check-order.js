const fs = require('fs');
const proj = JSON.parse(fs.readFileSync('default.project.json', 'utf-8'));
const lobby = proj.tree.Workspace.Lobby;
const keys = Object.keys(lobby).filter(k => k !== '$className' && k !== '$properties');
console.log('Lobby children order (first 20):');
keys.slice(0, 20).forEach((k, i) => {
    console.log('  ' + i + ': ' + k);
});
console.log('\nTotal children:', keys.length);
