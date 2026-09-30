// Every native this resource calls, checked against the real list.
//
// A misremembered native is nil, and calling nil throws only when that exact
// line runs — so it hides until somebody uses the feature. `readPaint` asked
// for IsVehiclePrimaryColourCustom, which does not exist; the real one is
// GetIsVehiclePrimaryColourCustom, and the tablet crashed the first time a
// customer opened it.
//
// The list is fetched once and cached beside this file. With no cache and no
// connection the check reports SKIPPED rather than ok — a checker that goes
// quiet is worse than no checker.
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const CACHE = path.join(HERE, '.natives-cache.json');

const SOURCES = [
    'https://runtime.fivem.net/doc/natives.json',
    'https://runtime.fivem.net/doc/natives_cfx.json',
];

// Runtime helpers and Lua globals that are not natives.
const NOT_NATIVES = new Set([
    'Citizen', 'CreateThread', 'Wait', 'SetTimeout', 'RegisterNetEvent', 'AddEventHandler',
    'TriggerEvent', 'TriggerServerEvent', 'TriggerClientEvent', 'RegisterCommand',
    'RegisterNUICallback', 'SendNUIMessage', 'SetNuiFocus', 'GetCurrentResourceName',
    'GetResourceState', 'AddStateBagChangeHandler', 'Entity', 'Player', 'GetPlayers',
    'GetPlayerName', 'GetPlayerPed', 'GetPlayerIdentifiers', 'IsPlayerAceAllowed',
    'IsDuplicityVersion', 'PerformHttpRequest', 'CancelEvent', 'GetInvokingResource',
    'MySQL', 'Config', 'Util', 'Mods', 'Tuning', 'Service', 'Framework', 'Inventory',
    'Target', 'XSM', 'Store', 'Pricing', 'Vehicles', 'Invoices', 'Orders', 'Team',
    'Banking', 'Phone', 'Discord', 'DB', 'Servicing', 'CustomTuning', 'Builder',
    'Placement', 'Preview', 'Repair', 'Hud', 'Zones', 'Catalogue', 'Stance', 'Perf',
    'Dyno', 'Lift', 'Nitrous', 'Lighting', 'Odometer', 'ServiceUI',
    'VehToNet', 'NetToVeh', 'NetToEnt', 'EntToNet', 'PedToNet', 'NetToPed',
    'Await', 'Citizen', 'promise', 'json', 'joaat', 'exports', 'vector3', 'vector4',
    'print', 'pcall', 'type', 'tostring', 'tonumber', 'pairs', 'ipairs', 'table',
    'string', 'math', 'os', 'io', 'error', 'assert', 'select', 'next', 'unpack',
]);

// FiveM's Lua names are not plain PascalCase. A segment starting with a digit
// keeps its underscore and stays lower case, which is why the real names are
// GetGroundZFor_3dCoord and GetVehicleModColor_1 rather than the tidier forms.
function pascal(name) {
    let out = '';

    for (const part of name.replace(/^_+/, '').split('_')) {
        if (!part) continue;

        if (/^\d/.test(part)) out += `_${part.toLowerCase()}`;
        else out += part[0].toUpperCase() + part.slice(1).toLowerCase();
    }

    return out;
}

// Lua comments and string literals, blanked so SQL inside [[ ]] is not read as
// code. COUNT(), VALUES() and COALESCE() are not natives anybody called.
// Scanned left to right, so an apostrophe inside a "double-quoted" string
// cannot open a fake single-quoted one. Newlines survive, keeping line numbers.
function strip(src) {
    let out = '';
    let i = 0;
    const blank = (text) => text.replace(/[^\n]/g, ' ');

    while (i < src.length) {
        const two = src.slice(i, i + 2);

        if (two === '--' || two === '[[') {
            const long = two === '[[' || src.slice(i + 2, i + 4) === '[[';
            const from = i;
            let end;
            if (long) {
                end = src.indexOf(']]', i + 2);
                end = end === -1 ? src.length : end + 2;
            } else {
                end = src.indexOf('\n', i);
                if (end === -1) end = src.length;
            }
            out += blank(src.slice(from, end));
            i = end;
            continue;
        }

        const ch = src[i];
        if (ch === '"' || ch === "'") {
            const from = i;
            i += 1;
            while (i < src.length && src[i] !== ch && src[i] !== '\n') {
                if (src[i] === '\\') i += 1;
                i += 1;
            }
            i += 1;
            out += ch + blank(src.slice(from + 1, i - 1)) + ch;
            continue;
        }

        out += ch;
        i += 1;
    }

    return out;
}

async function load() {
    if (existsSync(CACHE)) {
        return new Set(JSON.parse(readFileSync(CACHE, 'utf8')));
    }

    const names = new Set();

    for (const url of SOURCES) {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`${url} -> ${res.status}`);

        const json = await res.json();

        for (const ns of Object.values(json)) {
            for (const native of Object.values(ns)) {
                if (native.name) names.add(pascal(native.name));
                for (const alias of native.aliases || []) names.add(pascal(alias));
            }
        }
    }

    writeFileSync(CACHE, JSON.stringify([...names].sort()));
    return names;
}

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

let natives;

try {
    natives = await load();
} catch (err) {
    console.log(`check-natives SKIPPED — could not load the native list (${err.message})`);
    console.log('  it caches on the first successful run; re-run with a connection');
    process.exit(0);
}

const files = ['bridge', 'shared', 'client', 'server'].flatMap(walk);

// Anything the resource defines itself is not a native.
const defined = new Set();

for (const file of files) {
    const src = strip(readFileSync(path.join(ROOT, file), 'utf8'));

    for (const m of src.matchAll(/(?:^|\s)(?:local\s+)?function\s+([A-Za-z0-9_.:]+)\s*\(/g)) {
        defined.add(m[1].split(/[.:]/).pop());
    }

    for (const m of src.matchAll(/(?:^|\s)(?:local\s+)?([A-Za-z0-9_]+)\s*=\s*function\s*\(/g)) {
        defined.add(m[1]);
    }
}

const problems = [];
const seen = new Set();

for (const file of files) {
    // Stripped, but line-for-line: the blanking keeps newlines so the numbers
    // still point at the real source.
    const lines = strip(readFileSync(path.join(ROOT, file), 'utf8')).split(/\r?\n/);

    for (const [i, line] of lines.entries()) {
        for (const m of line.matchAll(/(?<![.:\w])([A-Z][A-Za-z0-9_]{3,})\s*\(/g)) {
            const name = m[1];

            if (natives.has(name)) continue;
            if (NOT_NATIVES.has(name)) continue;
            if (defined.has(name)) continue;
            if (seen.has(name)) continue;

            seen.add(name);
            problems.push(`${file}:${i + 1} calls ${name}(), which is not a native and nothing defines it`);
        }
    }
}

if (problems.length) {
    console.log('check-natives FAILED');
    for (const problem of problems) console.log(`  ${problem}`);
    process.exit(1);
}

console.log(`check-natives ok — every native call resolves (${natives.size} known)`);
