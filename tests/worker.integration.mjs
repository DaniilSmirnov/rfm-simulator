import { spawn } from 'node:child_process';
import { setTimeout as wait } from 'node:timers/promises';
import { once } from 'node:events';
import assert from 'node:assert/strict';
import { root } from '../scripts/godot.mjs';
const worker = spawn(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'dev', '--local', '--ip', '127.0.0.1', '--port', '8791', '--show-interactive-dev-session=false'], { cwd: root, env: { ...process.env, WRANGLER_SEND_METRICS: 'false' }, stdio: ['ignore', 'pipe', 'pipe'] });
let logs = '';
worker.stdout.on('data', b => { logs = (logs + b).slice(-8000); });
worker.stderr.on('data', b => { logs = (logs + b).slice(-8000); });
const origin = 'http://127.0.0.1:8791';
async function api(path, body, headers = {}) {
  const response = await fetch(origin + path, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return { status: response.status, ...await response.json() };
}
try {
  let ready = false;
  for (let i = 0; i < 40; i++) {
    if (worker.exitCode !== null) throw Error('Worker stopped: ' + logs);
    try { if ((await fetch(origin)).ok) { ready = true; break; } } catch {}
    await wait(500);
  }
  assert.ok(ready, 'Worker must start: ' + logs);
  const rootPage = await (await fetch(origin + '/')).text();
  assert.ok(rootPage.includes('platform/standalone.js'));
  assert.ok(!rootPage.includes('src="vk-bridge.js"'));
  const redirect = await fetch(origin + '/vk?vk_user_id=42&sign=test', {redirect:'manual'});
  assert.equal(redirect.status, 308);
  assert.equal(redirect.headers.get('Location'), origin + '/vk/?vk_user_id=42&sign=test');
  const vkPage = await fetch(origin + '/vk/');
  assert.equal(vkPage.status, 200);
  assert.ok((await vkPage.text()).includes('src="vk-bridge.js"'));
  assert.equal((await fetch(origin + '/vk/index.wasm.gz')).headers.get('Content-Type'), 'application/gzip');
  assert.equal((await api('/api/rooms', { name: 'X' }, { Origin: 'https://foreign.test' })).status, 403);
  assert.equal((await api('/api/rooms/000000/join', { name: 'X' })).status, 404);
  const host = await api('/api/rooms', { name: 'Host', stage: 1, car_model: 5 });
  assert.equal(host.status, 200);
  const base = `/api/rooms/${host.room}`;
  const guest = await api(base + '/join', { name: 'Guest', stage: 0, car_model: 2 });
  assert.equal(guest.status, 200);
  assert.equal(host.stage, 1);
  assert.equal(guest.stage, 1);
  assert.equal(guest.car_model, 2);
  const state = { pos: [0, 1, 2], car: [2, 3, 4], heading: 0, yaw: 0, pitch: 0, in_car: false, tow: false, beer: -1, eat: 1.85 };
  assert.equal((await api(base + '/sync', { token: 'wrong', state })).status, 401);
  const published = await api(base + '/sync', { token: host.token, state, world: { camp: [12, 3, 40], paused: false } });
  const shared = await api(base + '/sync', { token: guest.token, state, commands: [{ seq: 1, action: 'table' }] });
  assert.deepEqual(shared.world.camp, [12, 3, 40]);
  assert.equal(shared.players.length, 2);
  assert.deepEqual(shared.players.map(p => p.slot), [0, 1]);
  assert.deepEqual(shared.players.map(p => p.car_model), [5, 2]);
  assert.equal(shared.stage, 1);
  assert.equal(shared.world_time, published.world_time);
  assert.ok(shared.server_time >= shared.world_time);
  assert.equal(shared.players.find(p => p.id === host.player).state_time, published.world_time);
  assert.equal(shared.players.find(p => p.id === guest.player).state.eat, 1.85);
  const hostSync = await api(base + '/sync', { token: host.token, state });
  assert.equal(hostSync.commands[0].action, 'table');
  assert.equal((await api(base + '/heartbeat', { token: guest.token })).alive, true);
  await api(base + '/leave', { token: host.token });
  assert.equal((await api(base + '/sync', { token: guest.token, state })).status, 410);
  assert.equal((await api(base + '/join', { name: 'Late' })).status, 404);
  console.log('PASS: real Durable Object API, room lifecycle, ownership, commands and heartbeat');
} finally {
  const stopped = once(worker, 'exit').catch(() => {});
  worker.kill('SIGTERM');
  await Promise.race([stopped, wait(2000)]);
  if (worker.exitCode === null) worker.kill('SIGKILL');
}
