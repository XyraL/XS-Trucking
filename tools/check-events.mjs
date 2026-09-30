// Two handlers on one net event name is invisible until it crashes: both names
// resolve and every event has a handler, there are just two, and whichever
// reads a field the other payload does not carry throws.
//
// Also reports events triggered with no handler anywhere, and callbacks the
// client awaits that the server never registers.
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

const files = ['bridge', 'shared', 'client', 'server'].flatMap(walk);

const handlers = new Map();
const triggers = new Map();
const registered = new Set();
const awaited = new Map();

const add = (map, key, file) => {
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(file);
};

for (const file of files) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');

    for (const m of src.matchAll(/(?:RegisterNetEvent|AddEventHandler)\(\s*['"]([^'"]+)['"]\s*,/g)) {
        if (m[1].startsWith('XS-Trucking:')) add(handlers, m[1], file);
    }

    for (const m of src.matchAll(/Trigger(?:Server|Client)?Event\(\s*['"]([^'"]+)['"]/g)) {
        if (m[1].startsWith('XS-Trucking:')) add(triggers, m[1], file);
    }

    for (const m of src.matchAll(/lib\.callback\.register\(\s*['"]([^'"]+)['"]/g)) registered.add(m[1]);

    // server/callbacks.lua and server/admin.lua register through small helpers
    // that prefix the name, so the plain lib.callback.register scan misses them.
    if (file.startsWith('server/')) {
        for (const m of src.matchAll(/^(?:register|guarded)\(\s*'([^']+)'/gm)) registered.add(`XS-Trucking:server:${m[1]}`);
    }
    for (const m of src.matchAll(/lib\.callback\.await\(\s*['"]([^'"]+)['"]/g)) add(awaited, m[1], file);
}

const problems = [];

for (const [name, where] of handlers) {
    if (where.length > 1) {
        problems.push(`two handlers on '${name}': ${where.join(', ')}`);
    }
}

for (const [name, where] of triggers) {
    if (!handlers.has(name)) {
        problems.push(`'${name}' is triggered in ${where[0]} but nothing handles it`);
    }
}

for (const [name, where] of awaited) {
    if (!registered.has(name)) {
        problems.push(`callback '${name}' is awaited in ${where[0]} but never registered`);
    }
}

if (problems.length) {
    console.log('check-events FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log(`check-events ok — ${handlers.size} events, ${registered.size} callbacks`);
