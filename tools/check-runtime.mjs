// The client Lua runtime has no `os` and no `io`. Touching either is an
// instant `attempt to index a nil value (global 'os')`, and it only fires when
// that particular line runs — so it hides until somebody uses the feature.
//
// Shared files are the trap: they read as server code and load on both sides.
// A guarded use is fine, so a nearby IsDuplicityVersion() clears it.
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifest = readFileSync(path.join(ROOT, 'fxmanifest.lua'), 'utf8');

// Server-only standard library, and the natives that only exist one side.
const SERVER_ONLY = /\b(os|io)\s*\./;
const CLIENT_ONLY = /\b(GetGameTimer|PlayerPedId|GetEntityCoords|SendNUIMessage|SetNuiFocus)\s*\(/;

function block(name) {
    const found = manifest.match(new RegExp(`${name}\\s*\\{([\\s\\S]*?)\\n\\}`, 'm'));
    if (!found) return [];

    return [...found[1].matchAll(/['"]([^'"]+)['"]/g)]
        .map((m) => m[1])
        .filter((entry) => !entry.startsWith('@') && entry.endsWith('.lua'));
}

const shared = block('shared_scripts');
const client = block('client_scripts');

const problems = [];

function scan(file, pattern, what) {
    const full = path.join(ROOT, file);
    if (!existsSync(full)) return;

    const lines = readFileSync(full, 'utf8').split(/\r?\n/);

    for (const [i, line] of lines.entries()) {
        if (line.trim().startsWith('--')) continue;
        if (!pattern.test(line)) continue;

        // A guard anywhere in the enclosing few lines is enough.
        const window = lines.slice(Math.max(0, i - 8), i + 1).join('\n');
        if (/IsDuplicityVersion\s*\(/.test(window)) continue;

        problems.push(`${file}:${i + 1} uses ${what} with no IsDuplicityVersion guard`);
    }
}

// A shared file runs on both sides, so either restriction applies.
for (const file of shared) {
    scan(file, SERVER_ONLY, 'server-only `os`/`io`');
}

// A client file has no business touching them at all.
for (const file of client) {
    if (shared.includes(file)) continue;
    scan(file, SERVER_ONLY, 'server-only `os`/`io`');
}

// And a shared file must not assume the client natives either.
for (const file of shared) {
    scan(file, CLIENT_ONLY, 'a client-only native');
}

if (problems.length) {
    console.log('check-runtime FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log(`check-runtime ok — ${shared.length} shared and ${client.length} client files use nothing their runtime lacks`);
