// Runs every checker. The checkers only help if they all actually get run.
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

const CHECKS = ['check-manifest.mjs', 'check-events.mjs', 'check-nui.mjs', 'check-returns.mjs', 'check-netids.mjs', 'check-runtime.mjs', 'check-natives.mjs', 'check-lua.mjs', 'check-js.mjs'];

let failed = 0;

for (const check of CHECKS) {
    const run = spawnSync(process.execPath, [path.join(HERE, check)], { encoding: 'utf8' });

    process.stdout.write(run.stdout || '');
    process.stderr.write(run.stderr || '');

    if (run.status !== 0) failed += 1;
}

if (failed > 0) {
    console.log(`\n${failed} check(s) failed.`);
    process.exit(1);
}

console.log('\nall checks passed.');
