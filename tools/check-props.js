const fs = require('fs');
const readline = require('readline');

async function main() {
    const rl = readline.createInterface({
        input: fs.createReadStream('KESHUSY-LAN-D.rbxlx'),
        crlfDelay: Infinity
    });
    
    let inItem = false;
    let itemLine = 0;
    let itemName = '';
    let referent = '';
    let propNames = new Set();
    let foundLobbyFloor = false;
    let foundLamp0 = false;
    
    for await (const line of rl) {
        // Detect start of Item
        const itemMatch = line.match(/<Item class="Part" referent="(\d+)">/);
        if (itemMatch) {
            inItem = true;
            itemLine = itemMatch;
            referent = itemMatch[1];
            propNames = new Set();
            continue;
        }
        
        if (inItem) {
            // Look for Name property
            const nameMatch = line.match(/<string name="Name">([^<]+)<\/string>/);
            if (nameMatch) {
                itemName = nameMatch[1];
            }
            
            // Collect all property names
            const propMatch = line.match(/<(\w+) name="([^"]+)">/);
            if (propMatch) {
                propNames.add(propMatch[2]);
            }
            
            // Detect end of item
            if (line.trim() === '</Item>') {
                if (itemName === 'LobbyFloor') {
                    foundLobbyFloor = true;
                    console.log('LobbyFloor (referent ' + referent + ') properties:');
                    console.log('  ' + Array.from(propNames).sort().join(', '));
                }
                if (itemName === 'Lamp_0') {
                    foundLamp0 = true;
                    console.log('Lamp_0 (referent ' + referent + ') properties:');
                    console.log('  ' + Array.from(propNames).sort().join(', '));
                }
                if (itemName === 'Lamp_8') {
                    console.log('Lamp_8 (referent ' + referent + ') properties:');
                    console.log('  ' + Array.from(propNames).sort().join(', '));
                }
                if (foundLobbyFloor && foundLamp0 && itemName === 'Lamp_8') break;
                
                inItem = false;
                itemName = '';
                referent = '';
            }
        }
    }
}

main();
