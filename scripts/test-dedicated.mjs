// Dedicated server smoke test: a headless server (game/scripts/net/dedicated.gd)
// creates a room with a fixed ID on a local Worker, a native guest joins it by
// that ID, drives on the server's simulation and does not see the server as a
// member on the stage. Once the guest is gone, the empty room starts over
// under the same ID. A wrong server key is refused.
//   node scripts/test-dedicated.mjs
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { existsSync } from 'node:fs';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { setTimeout as wait } from 'node:timers/promises';
import assert from 'node:assert/strict';
import { getGodot, root, run } from './godot.mjs';

const KEY = 'ci-dedicated-key';
const ROOM = 'D0D0D0';
const IDLE_RESTART = 20;
const workerPort = 8797;
const processes = [];
const logs = [];
const errors = [];
const samples = [];
let control = { id: 0, action: 'pause' };
const guest = () => samples.at(-1);
function launch(args, role, env = {}) {
  const child = spawn(args[0], args.slice(1), { cwd: root, env: { ...process.env, WRANGLER_SEND_METRICS: 'false', ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  processes.push(child);
  for (const stream of [child.stdout, child.stderr]) {
    let buffer = '';
    stream.on('data', bytes => {
      buffer += bytes;
      let i;
      while ((i = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, i);
        buffer = buffer.slice(i + 1);
        if (line.includes('NETWORK_SAMPLE ')) { samples.push(JSON.parse(line.slice(line.indexOf('NETWORK_SAMPLE ') + 15))); continue; }
        if (role !== 'worker' && /SCRIPT ERROR|Parse Error|ERROR:/.test(line)) errors.push(`[${role}] ${line}`);
        logs.push(`[${role}] ${line}`);
        if (role !== 'worker') console.log(`[${role}] ${line}`);
      }
    });
  }
  return child;
}
async function until(predicate, title, timeout = 60000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (errors.length) throw Error(errors.join('\n'));
    if (await predicate()) return;
    await wait(100);
  }
  throw Error(`${title} timed out; guest=${JSON.stringify(guest())}`);
}
const logged = (role, text) => logs.filter(line => line.startsWith(`[${role}] `) && line.includes(text)).length;
// Forwards the room API to the Worker (with the server's key header) and gives
// the guest its test controls (game/tests/network_client.gd).
const proxy = createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (path === '/test/control') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(control)); return; }
    let body = '';
    for await (const chunk of req) body += chunk;
    const key = req.headers['x-rally-dedicated'];
    const response = await fetch(`http://127.0.0.1:${workerPort}${path}`, { method: req.method, headers: { 'Content-Type': 'application/json', ...(key === undefined ? {} : { 'X-Rally-Dedicated': key }) }, body });
    res.writeHead(response.status, { 'Content-Type': 'application/json' });
    res.end(await response.text());
  } catch (error) { res.writeHead(500).end(String(error)); }
});
try {
  // wrangler dev needs the assets directory; a placeholder serves no page here.
  if (!existsSync(join(root, 'dist'))) { await mkdir(join(root, 'dist')); await writeFile(join(root, 'dist/index.html'), ''); }
  launch([process.execPath, 'node_modules/wrangler/bin/wrangler.js', 'dev', '--local', '--ip', '127.0.0.1', '--port', String(workerPort), '--show-interactive-dev-session=false', '--var', `DEDICATED_TOKEN:${KEY}`], 'worker');
  await until(async () => { try { return (await fetch(`http://127.0.0.1:${workerPort}`)).status > 0; } catch { return false; } }, 'worker start');
  await new Promise(resolve => proxy.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${proxy.address().port}`;
  const refused = await fetch(`${origin}/api/rooms`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Rally-Dedicated': 'wrong' }, body: JSON.stringify({ name: 'x', room: ROOM }) });
  assert.equal(refused.status, 403, 'a wrong server key is refused');
  const godot = await getGodot();
  run(godot, ['--headless', '--editor', '--path', join(root, 'game'), '--import', '--quit']);
  launch([godot, '--headless', '--path', 'game', '--', '--dedicated', '--stage=0', `--room=${ROOM}`, `--room-server=${origin}`, `--idle-restart=${IDLE_RESTART}`], 'server', { RALLY_DEDICATED_TOKEN: KEY });
  await until(() => logged('server', `ROOM_CONNECTED ${ROOM} host=true`) === 1, 'server creates its room', 90000);
  const guestProcess = launch([godot, '--headless', '--path', 'game', '--max-fps', '60', 'res://tests/network_client.tscn', '--', '--smoke-test', '--network-role=guest', `--network-room=${ROOM}`, `--room-server=${origin}`], 'guest');
  await until(() => guest()?.connected && guest()?.active, 'guest joins by ID and the server takes its car', 90000);
  assert.equal(guest().room, ROOM);
  assert.equal(guest().peers, 0, 'the server is nobody on the guest\'s stage');
  control = { id: 1, action: 'forward' };
  const start = guest().pos;
  await until(() => Math.hypot(...guest().pos.map((x, i) => x - start[i])) > 3, 'guest drives on the server\'s simulation', 30000);
  control = { id: 2, action: 'brake' };
  await until(() => Math.abs(guest().speed) < 0.1, 'guest brakes', 30000);
  control = { id: 3, action: 'pause' };
  await until(() => guest().pending === 0 && guest().seq > 0 && guest().ack === guest().seq, 'server acknowledges every input', 30000);
  assert.equal(guest().dead, false);
  guestProcess.kill('SIGTERM');
  await until(() => logged('server', 'starting the room over') === 1, 'empty room starts over', (IDLE_RESTART + 120) * 1000);
  await until(() => logged('server', `ROOM_CONNECTED ${ROOM} host=true`) === 2, 'the new room takes the same ID', 90000);
  assert.equal(errors.length, 0);
  console.log(`PASS: dedicated server: key check, fixed room ${ROOM}, guest joins and drives on the server, server invisible, idle restart under the same ID`);
} catch (error) {
  console.error(logs.slice(-80).join('\n'));
  if (process.env.GITHUB_ACTIONS) console.log(`::error title=Dedicated server::` + [String(error?.message ?? error).slice(0, 2000), ...logs.slice(-30)].join('\n').slice(-6000).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A'));
  throw error;
} finally {
  await writeFile(join(root, 'dedicated-test.log'), logs.join('\n'));
  for (const child of processes) child.kill('SIGTERM');
  await new Promise(resolve => proxy.close(resolve));
}
