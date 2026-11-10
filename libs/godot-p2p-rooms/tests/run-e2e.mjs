// End-to-end check of the P2PRooms addon against the real room server:
// starts `wrangler dev` from the repository root, then a host and a guest in
// headless Godot that meet in a room and exchange packets over WebRTC.
//   node libs/godot-p2p-rooms/tests/run-e2e.mjs
// Needs Godot 4.4 (GODOT_BIN or the repository's cached editor) and downloads
// the webrtc-native GDExtension into ./webrtc on the first run.
import { spawn, spawnSync } from 'node:child_process';
import { access, mkdir, writeFile, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as wait } from 'node:timers/promises';
import { getGodot } from '../../../scripts/godot.mjs';

const lib = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repo = resolve(lib, '../..');
const WEBRTC = 'https://github.com/godotengine/webrtc-native/releases/download/1.1.0-stable/godot-extension-webrtc.zip';
const PORT = 8795;
const server = `http://127.0.0.1:${PORT}`;

async function exists(path) { try { await access(path); return true; } catch { return false; } }
if (!await exists(join(lib, 'webrtc', 'webrtc.gdextension'))) {
  console.log('Downloading webrtc-native...');
  const response = await fetch(WEBRTC);
  if (!response.ok) throw new Error('webrtc-native download failed: ' + response.status);
  const zip = join(lib, '.webrtc.zip');
  await writeFile(zip, Buffer.from(await response.arrayBuffer()));
  spawnSync('python3', ['-c', 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])', zip, lib], { stdio: 'inherit' });
  await rm(zip);
}
const godot = await getGodot();
// The first import registers the extension.
spawnSync(godot, ['--headless', '--path', lib, '--import'], { stdio: 'ignore', timeout: 120000 });

const children = [];
const stop = () => { for (const c of children) try { c.kill('SIGKILL'); } catch {} };
process.on('exit', stop);
function start(command, args, cwd, tag) {
  const child = spawn(command, args, { cwd, env: { ...process.env, WRANGLER_SEND_METRICS: 'false' }, stdio: ['ignore', 'pipe', 'pipe'] });
  children.push(child);
  child.log = '';
  const take = b => { child.log += b; for (const line of String(b).split('\n')) if (line.trim() && tag) console.log(`[${tag}] ${line}`); };
  child.stdout.on('data', take);
  child.stderr.on('data', take);
  child.done = new Promise(ok => child.on('exit', code => ok(code)));
  return child;
}
async function until(check, label, timeout) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { const v = await check(); if (v) return v; await wait(100); }
  throw new Error('Timed out: ' + label);
}

await mkdir(join(repo, 'dist'), { recursive: true }); // wrangler.jsonc serves assets from it
start(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'dev', '--local', '--ip', '127.0.0.1', '--port', String(PORT), '--show-interactive-dev-session=false'], repo, '');
await until(async () => { try { return (await fetch(server + '/api/rooms', { method: 'POST', body: '{}' })).status > 0; } catch { return false; } }, 'wrangler dev', 120000);

const client = (role, extra = []) => start(godot, ['--headless', '--path', lib, '--script', 'res://tests/e2e_client.gd', '--', `--server=${server}`, `--role=${role}`, ...extra], lib, role);
const host = client('host');
const room = await until(() => host.log.match(/ROOM ([0-9A-F]{6})/)?.[1], 'room id', 20000);
const guest = client('guest', [`--room=${room}`]);
const [hostCode, guestCode] = await Promise.all([host.done, guest.done]);
const ok = hostCode === 0 && guestCode === 0 && /HOST_PASS/.test(host.log) && /GUEST_PASS/.test(guest.log) && /refused with another protocol/.test(guest.log);
console.log(ok ? 'E2E PASS' : `E2E FAIL (host ${hostCode}, guest ${guestCode})`);
stop();
process.exit(ok ? 0 : 1);
