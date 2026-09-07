#!/usr/bin/env node
// How deep the guest can recurse before the HOST's stack gives out.
//
// `max_depth` exists to turn a stack overflow into an answer a person can
// read, which it can only do if it sits below the host's real ceiling. On a
// JavaScript engine that ceiling is not a property of the backend alone: it
// moves with the build, with `wasm-opt`, and -- more than either -- with how
// much stack the caller has already spent. So it is measured rather than
// assumed, and measured against the module that actually ships.
//
//   tools/depth-probe.mjs                     the page's own module
//   tools/depth-probe.mjs path/to/other.wasm  any module exporting `analyze`
//
// The module needs a `max_depth` well above what is being probed, or the
// guest's own guard answers first and the ceiling is never reached. Set it in
// `playground/playground.mbt`, rebuild, and put it back afterwards.
import { readFileSync } from 'node:fs';

const wasmPath = process.argv[2]
  ? new URL(process.argv[2], `file://${process.cwd()}/`)
  : new URL('../playground/playground.wasm', import.meta.url);

const mod = await WebAssembly.compile(readFileSync(wasmPath), {
  builtins: ['js-string'],
  importedStringConstants: '_',
});
const { analyze } = (await WebAssembly.instantiate(mod, {})).exports;

// Three shapes, because a frame's cost is its pending expressions and not
// only its call. They do not order consistently across builds.
const SHAPES = {
  tail: (n) => `def down(n):\n    if n == 0:\n        return 0\n    return down(n - 1)\n\nprint(down(${n}))\n`,
  accumulating: (n) => `def down(n):\n    if n == 0:\n        return 0\n    return 1 + down(n - 1)\n\nprint(down(${n}))\n`,
  nested: (n) => `def down(n):\n    if n == 0:\n        return 0\n    return ((down(n - 1) + 1) * 2 - 2) // 2\n\nprint(down(${n}))\n`,
};

// A run that finished is one the host's stack held. There are two ways not to
// finish and they mean opposite things: a thrown RangeError is the ceiling
// being found, while the guest's own `max_depth` answering is the module
// refusing to go deep enough to find it.
function attempt(shape, depth) {
  try {
    const r = JSON.parse(analyze(SHAPES[shape](depth))).run;
    if (r.state === 'finished') return 'held';
    return /call stack deeper than/.test(r.detail || '') ? 'guarded' : 'other';
  } catch {
    return 'overflowed';
  }
}
const survives = (shape, depth) => attempt(shape, depth) === 'held';

// Five tries per depth. The stack available to a call depends on what is
// already on it, so one try is not a measurement.
const holds = (shape, depth) => {
  for (let i = 0; i < 5; i++) if (!survives(shape, depth)) return false;
  return true;
};

const CEILING = 1 << 16;
console.log(`${wasmPath.pathname.split('/').pop()}, guest calls before the host stack goes:`);
for (const shape of Object.keys(SHAPES)) {
  if (holds(shape, CEILING)) {
    console.log(`  ${shape.padEnd(13)} > ${CEILING}`);
    continue;
  }
  let lo = 0, hi = CEILING;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (holds(shape, mid)) lo = mid; else hi = mid;
  }
  // Which wall was hit at `hi` decides whether this is a measurement at all.
  const wall = attempt(shape, hi);
  const note = wall === 'guarded'
    ? "  <- the module's own max_depth, not the stack: raise it and rebuild"
    : wall === 'other'
      ? '  <- the run did not overflow; check the program, not the stack'
      : '';
  console.log(`  ${shape.padEnd(13)} ${lo}${note}`);
}
