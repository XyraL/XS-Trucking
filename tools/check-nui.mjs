// Every endpoint the page posts to needs a RegisterNUICallback, and every
// callback should be reachable from the page. A missing one fails silently:
// the fetch resolves with nothing and the button simply does not work.
//
// Also checks that no NUI file hardcodes the resource name. PascalCase folders
// are case-sensitive on Linux, so a hardcoded host is a landmine.
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
        else out.push(rel);
    }
    return out;
}

const jsFiles = walk('html').filter((f) => f.endsWith('.js'));
const luaFiles = walk('client').filter((f) => f.endsWith('.lua'));

const posted = new Map();
const handled = new Set();
const problems = [];

for (const file of jsFiles) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');

    // XS.bill posts too. It wraps the endpoint so it can put a customer
    // picker up and post it a second time, which hides the name from a plain
    // XS.post scan — and an endpoint nothing appears to post to reads as dead
    // code somebody then deletes.
    for (const m of src.matchAll(/XS\.(?:post|bill)\(\s*['"]([^'"]+)['"]/g)) {
        if (!posted.has(m[1])) posted.set(m[1], file);
    }

    // mock.js is the browser harness; it is the one file allowed to name the
    // resource, and it guards on GetParentResourceName before doing anything.
    if (!file.endsWith('mock.js')) {
        for (const m of src.matchAll(/https:\/\/XS-Trucking/gi)) {
            problems.push(`${file} hardcodes the resource host — use GetParentResourceName()`);
        }
    }
}

for (const file of luaFiles) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');
    for (const m of src.matchAll(/RegisterNUICallback\(\s*['"]([^'"]+)['"]/g)) handled.add(m[1]);
}

// XS.rpc goes through the one 'rpc' callback, which only relays names in the
// client's PLAYER or ADMIN lists, to a server callback of the same name. A
// name missing from either end fails without a sound, so both are checked.
const rpcUsed = new Map();
for (const file of jsFiles) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');
    for (const m of src.matchAll(/XS\.rpc\(\s*['"]([^'"]+)['"]/g)) {
        if (!rpcUsed.has(m[1])) rpcUsed.set(m[1], file);
    }
}

const allowed = new Set();
const uiLua = path.join(ROOT, 'client/ui.lua');
if (existsSync(uiLua)) {
    const src = readFileSync(uiLua, 'utf8');
    for (const block of src.matchAll(/local (?:PLAYER|ADMIN) = \{([\s\S]*?)\n\}/g)) {
        for (const m of block[1].matchAll(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*true/g)) allowed.add(m[1]);
    }
}

const served = new Set();
for (const file of walk('server').filter((f) => f.endsWith('.lua'))) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');
    for (const m of src.matchAll(/^(?:register|guarded)\(\s*'([^']+)'/gm)) served.add(m[1]);
    for (const m of src.matchAll(/lib\.callback\.register\(\s*'XS-Trucking:server:([^']+)'/g)) served.add(m[1]);
}

for (const [name, file] of rpcUsed) {
    if (!allowed.has(name)) problems.push(`the page calls rpc '${name}' (${file}) but client/ui.lua does not relay it`);
    if (!served.has(name)) problems.push(`the page calls rpc '${name}' (${file}) but no server callback is registered for it`);
}
for (const name of allowed) {
    if (!served.has(name)) problems.push(`client/ui.lua relays '${name}' but no server callback is registered for it`);
}

if (rpcUsed.size) posted.set('rpc', 'html/js/core.js');

for (const [endpoint, file] of posted) {
    if (!handled.has(endpoint)) {
        problems.push(`the page posts '${endpoint}' (${file}) but no RegisterNUICallback handles it`);
    }
}

for (const endpoint of handled) {
    if (!posted.has(endpoint)) {
        problems.push(`RegisterNUICallback '${endpoint}' is never posted to by the page`);
    }
}

// The mock guard has to test the CEF global, not the hostname alone: the
// browser lowercases the URL host while GetParentResourceName returns the real
// casing, so a capitalised resource name slips straight past a bare compare.
const mockPath = path.join(ROOT, 'html/js/mock.js');

if (existsSync(mockPath)) {
    const mock = readFileSync(mockPath, 'utf8');

    if (!mock.includes("typeof GetParentResourceName === 'function'")) {
        problems.push('mock.js does not guard on GetParentResourceName — it will replace fetch in game');
    }

    if (!mock.includes('toLowerCase()')) {
        problems.push('mock.js hostname guard does not fold case — a capitalised resource name defeats it');
    }
}

if (problems.length) {
    console.log('check-nui FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log(`check-nui ok — ${posted.size} endpoints and ${rpcUsed.size} rpc calls, all handled`);
