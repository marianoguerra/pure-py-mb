#!/usr/bin/env node
// Every playground example, through the playground's own wasm module.
//
// The page's notes make claims -- this one is refused, that one has no
// answer, this one calls the host -- and a note that has drifted from what
// the code does is worse than no note. This runs `analyze` exactly as the
// page does, host and all, and prints what each example actually did.
//
// With `--expect`, it also checks each example against the outcome recorded
// beside it in `examples.js`, and fails if one has drifted.
import { readFileSync } from 'node:fs';
import { GROUPS } from '../playground/examples.js';

const wasmPath = new URL('../playground/playground.wasm', import.meta.url);
const bytes = readFileSync(wasmPath);
const mod = await WebAssembly.compile(bytes, {
  builtins: ['js-string'],
  importedStringConstants: '_',
});
const { analyze } = (await WebAssembly.instantiate(mod, {})).exports;

const strict = process.argv.includes('--expect');
let failures = 0;

// What an example did, in one word, from the page's own point of view.
function outcome(r) {
  if (!r.check.ok) {
    return r.check.short.includes('not yet supported') ? 'not-yet' : 'refused';
  }
  return r.run.state;
}

for (const group of GROUPS) {
  console.log('\n\x1b[1m' + group.label + '\x1b[0m');
  for (const item of group.items) {
    const r = JSON.parse(analyze(item.src));
    const got = outcome(r);
    const detail = !r.check.ok
      ? r.check.short
      : (r.run.detail || (r.run.output || '').trim().split('\n')[0] || '');
    const log = (r.run.log || []).length ? ` · host: ${r.run.log.length}` : '';
    const drifted = strict && item.expect && item.expect !== got;
    if (drifted) failures++;
    const mark = drifted ? '\x1b[31m✗\x1b[0m' : ' ';
    const want = drifted ? ` (expected ${item.expect})` : '';
    console.log(
      `${mark} ${item.name.padEnd(34)} ${got.padEnd(11)} ${detail.slice(0, 78)}${log}${want}`,
    );
  }
}

if (strict) {
  const missing = GROUPS.flatMap((g) => g.items).filter((i) => !i.expect);
  for (const m of missing) {
    console.log(`\x1b[31m✗\x1b[0m ${m.name}: no expected outcome recorded`);
    failures++;
  }
  console.log(failures ? `\n\x1b[31m${failures} drifted\x1b[0m` : '\n\x1b[32mall examples do what their notes say\x1b[0m');
  process.exit(failures ? 1 : 0);
}
