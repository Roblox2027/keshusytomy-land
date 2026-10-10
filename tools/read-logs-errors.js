const fs = require('fs');
const buf = fs.readFileSync('C:\\Users\\bdani\\AppData\\Local\\Temp\\kilo\\runtime_logs.json');
let str = buf.toString('utf-16le');
const start = str.indexOf('{');
str = str.slice(start);
const j = JSON.parse(str);
const entries = j.entries || [];

// Look for ERROR and WARN entries related to service failures
console.log('=== ERROR/WARN entries ===');
for (const e of entries) {
    if (e.level === 'ERROR' || e.level === 'WARN') {
        if (e.message.includes('fallo') || e.message.includes('Failed') || 
            e.message.includes('FAIL') || e.message.includes('fail') ||
            e.message.includes('Destruction') || e.message.includes('Explosion') ||
            e.message.includes('BombService') || e.message.includes('MatchService') ||
            e.message.includes('PortalService') || e.message.includes('Init')) {
            console.log(e.level + ': ' + e.message);
        }
    }
}
