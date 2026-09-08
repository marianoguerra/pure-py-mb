#!/usr/bin/env node
// Serve `probe.html` with two modules beside it, and collect what it measures.
//
//   tools/depth-probe-page/serve.mjs            just serve; open the URL yourself
//   tools/depth-probe-page/serve.mjs firefox    drive a headless Firefox
//   tools/depth-probe-page/serve.mjs chromium   drive a headless Chromium
//
// It needs two modules, which it takes from `_build` and `playground/`:
//
//   unguarded.wasm  a build whose `max_depth` is far above anything probed,
//                   or the guest's own guard answers before the engine does.
//                   Set it in `playground/playground.mbt`, build, put it back.
//   shipped.wasm    `playground/playground.wasm`, to ask the question that
//                   decides whether a page survives: does the module we serve
//                   hold at its own limit and report rather than throw past it?
//
// The engine traps are the reason this drives the browser rather than telling
// you to. Firefox hands off to an already-running instance and exits unless
// MOZ_NO_REMOTE=1 and --no-remote, and it will not create a profile
// directory that does not exist. A headless browser has nowhere to print, so
// the page POSTs back here.
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync, mkdirSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const here = new URL('.', import.meta.url);
const root = new URL('../../', import.meta.url);
const PORT = 8731;

const UNGUARDED = new URL('unguarded.wasm', here);
const SHIPPED = new URL('playground/playground.wasm', root);
if (!existsSync(UNGUARDED)) {
  console.error(`${fileURLToPath(UNGUARDED)}: not here.
Build one with a large max_depth in playground/playground.mbt:
  moon build --target wasm-gc --release && tools/optimize-wasm.sh <path>
then copy it here as unguarded.wasm and restore the real max_depth.`);
  process.exit(2);
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.wasm': 'application/wasm' };
const server = createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/result') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      res.end('ok');
      console.log(body);
      server.close();
      process.exit(0);
    });
    return;
  }
  const path = req.url === '/' ? '/probe.html' : req.url.split('?')[0];
  const from = path === '/shipped.wasm' ? SHIPPED : new URL('.' + path, here);
  try {
    res.setHeader('Content-Type', TYPES[path.slice(path.lastIndexOf('.'))] ?? 'application/octet-stream');
    res.end(readFileSync(from));
  } catch {
    res.statusCode = 404;
    res.end('not here');
  }
});

const url = `http://127.0.0.1:${PORT}/`;
server.listen(PORT, () => {
  const engine = process.argv[2];
  if (!engine) return console.log(`serving ${url} — open it in the engine you ship to`);

  // In the system temp directory rather than under $HOME, because both of
  // these are snaps here and the Chromium one cannot write a profile into
  // ~/.cache -- it fails on `SingletonLock` and aborts rather than run.
  const profile = `${tmpdir()}/pure-py-depth-probe/${engine}`;
  rmSync(profile, { recursive: true, force: true });
  mkdirSync(profile, { recursive: true });

  // A separate profile is not enough for Firefox: without MOZ_NO_REMOTE it
  // hands the URL to whatever Firefox is already open and exits 0, and the
  // result never arrives. The snap's launcher does not pass the variable
  // through either, so reach past it to the real binary when it is there.
  const SNAP_FIREFOX = '/snap/firefox/current/usr/lib/firefox/firefox';
  const firefox = existsSync(SNAP_FIREFOX) ? SNAP_FIREFOX : 'firefox';
  const [cmd, args, env] = engine === 'firefox'
    ? [firefox, ['--headless', '--no-remote', '--new-instance', '--profile', profile, url],
       { ...process.env, MOZ_NO_REMOTE: '1' }]
    : ['chromium', ['--headless', '--disable-gpu', '--no-sandbox', `--user-data-dir=${profile}`, url],
       process.env];

  const child = spawn(cmd, args, { env, stdio: 'ignore' });
  child.on('error', (e) => { console.error(`${cmd}: ${e.message}`); process.exit(1); });
});

setTimeout(() => {
  console.error('no result in three minutes; run without an engine argument and open the URL yourself');
  process.exit(1);
}, 180000);
