const fs = require('fs');
const readline = require('readline');

async function main() {
    const rl = readline.createInterface({
        input: fs.createReadStream('KESHUSY-LAN-D.rbxlx'),
        crlfDelay: Infinity
    });
    
    let lineNum = 0;
    let inLobby = false;
    let lobbyDepth = 0;
    let foundParts = [];
    
    const targetParts = ['LobbyFloor', 'Lamp_0', 'Lamp_8', 'PvPArena_Floor', 'KeshusyCore', 'Portals'];
    
    rl.on('line', (line) => {
        lineNum++;
        
        // Find Lobby folder start
        if (line.includes('Name">Lobby</string>') && !inLobby) {
            inLobby = true;
            lobbyDepth = line.split('<Item').length - 1;
        }
        
        if (inLobby) {
            for (const name of targetParts) {
                if (line.includes('Name">' + name + '</string>')) {
                    foundParts.push({ name, line: lineNum });
                }
            }
            
            // Track nesting with </Item>
            const openItems = (line.match(/<Item/g) || []).length;
            const closeItems = (line.match(/<\/Item>/g) || []).length;
            
            // Look for the Lobby folder's parent close
            if (line.includes('</Item>') && lineNum > 60000 && openItems - closeItems < 0) {
                // We might be closing the Lobby folder
            }
        }
        
        // Stop after we've found all targets and passed them
        if (foundParts.length === targetParts.length && lineNum > foundParts[foundParts.length-1].line + 5) {
            rl.close();
        }
    });
    
    rl.on('close', () => {
        for (const p of foundParts) {
            console.log(p.name + ' at line ' + p.line);
        }
    });
}

main();
