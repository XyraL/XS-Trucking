// NetToVeh / NetworkGetEntityFromNetworkId log
//
//     Warning: [entity] GetNetworkObject: no object by ID n
//
// on EVERY call for an id the client has not streamed in. One call is noise;
// a call inside a loop or a retry is a console full of it, which is how the
// state bag handler drowned the log on the first in-game run.
//
// Client side, either guard with NetworkDoesNetworkIdExist first or use
// GetEntityFromStateBagName, which answers 0 quietly. The server knows every
// entity, so it is exempt.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function walk(dir) {
    const full = path.join(ROOT, dir);
    if (!existsSync(full)) return [];

    const out = [];
    for (const name of readdirSync(full)) {
        const rel = `${dir}/${name}`;
        if (statSync(path.join(ROOT, rel)).isDirectory()) out.push(...walk(rel));
        else if (rel.endsWith('.lua')) out.push(rel);
    }
    return out;
}

const problems = [];

for (const file of walk('client')) {
    const lines = readFileSync(path.join(ROOT, file), 'utf8').split(/\r?\n/);

    for (const [i, line] of lines.entries()) {
        if (line.trim().startsWith('--')) continue;
        if (!/\b(NetToVeh|NetToEnt|NetworkGetEntityFromNetworkId)\s*\(/.test(line)) continue;

        // The guard may sit on this line or in the handful above it.
        const window = lines.slice(Math.max(0, i - 6), i + 1).join('\n');

        if (!/NetworkDoesNetworkIdExist/.test(window)) {
            problems.push(`${file}:${i + 1} resolves a net id with no NetworkDoesNetworkIdExist guard — it warns for every id this client cannot see`);
        }
    }
}

if (problems.length) {
    console.log('check-netids FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log('check-netids ok — every client net-id lookup is guarded');
