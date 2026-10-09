import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as wait } from 'node:timers/promises';
import { RallyRoom } from '../server/worker.mjs';

// Minimal stand-in for the Durable Object hibernation API.
class FakeSocket {
  constructor() { this.sent = []; this.attachment = null; this.closed = null; }
  send(text) { this.sent.push(JSON.parse(text)); }
  serializeAttachment(value) { this.attachment = structuredClone(value); }
  deserializeAttachment() { return this.attachment; }
  close(code) { this.closed = code; }
  take(type) { const found = this.sent.filter(m => !type || m.type === type); this.sent = this.sent.filter(m => type && m.type !== type); return found; }
}
function fakeRoom() {
  const sockets = [];
  const storage = new Map();
  const ctx = {
    blockConcurrencyWhile: fn => fn(),
    acceptWebSocket: ws => sockets.push(ws),
    getWebSockets: () => sockets,
    storage: { get: async key => storage.get(key), put: async (key, value) => storage.set(key, structuredClone(value)), setAlarm: async () => {}, deleteAll: async () => storage.clear() },
  };
  return { room: new RallyRoom(ctx), sockets, storage };
}
const state = (x = 0) => ({ pos: [x, 1, 2], car: [3, 4, 5], heading: 1, yaw: 2, pitch: 0, in_car: true, tow: false, beer: -1 });
async function connect(room, sockets, token) {
  const ws = new FakeSocket();
  sockets.push(ws);
  await room.webSocketMessage(ws, JSON.stringify({ type: 'hello', id: 1, token, cold_revs: {} }));
  return ws;
}

test('socket sync requires a hello with a valid member token', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const host = room.room.add('Host', Date.now(), true);
  const stranger = new FakeSocket();
  sockets.push(stranger);
  await room.webSocketMessage(stranger, JSON.stringify({ type: 'sync', id: 2, state: state() }));
  assert.equal(stranger.take('error')[0].status, 401);
  assert.equal(stranger.closed, 4401);
  const forged = new FakeSocket();
  sockets.push(forged);
  await room.webSocketMessage(forged, JSON.stringify({ type: 'hello', id: 1, token: 'nope' }));
  assert.equal(forged.take('error')[0].status, 401);
  const ws = await connect(room, sockets, host.token);
  assert.equal(ws.take('hello')[0].player, host.player);
  await room.webSocketMessage(ws, JSON.stringify({ type: 'sync', id: 3, state: state(), world: { elapsed: 1 } }));
  const reply = ws.take('reply')[0];
  assert.equal(reply.id, 3);
  assert.equal(reply.world, undefined);
});

test('host world is pushed to guests immediately and guest input reaches the host without polling', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const now = Date.now();
  const h = room.room.add('Host', now, true);
  const g = room.room.add('Guest', now);
  const hostWs = await connect(room, sockets, h.token);
  const guestWs = await connect(room, sockets, g.token);
  await room.webSocketMessage(hostWs, JSON.stringify({ type: 'sync', id: 2, state: state(), cold_revs: {}, world: { elapsed: 5, cold_revs: { camp: 9 } }, cold: { camp: { camp: [1, 2, 3] } } }));
  let push = guestWs.take('push');
  assert.equal(push.length, 1);
  assert.equal(push[0].world.elapsed, 5);
  assert.deepEqual(push[0].world.cold, { camp: { camp: [1, 2, 3] } });
  await room.webSocketMessage(hostWs, JSON.stringify({ type: 'sync', id: 3, state: state(), world: { elapsed: 6, cold_revs: { camp: 9 } } }));
  push = guestWs.take('push');
  assert.equal(push[0].world.elapsed, 6);
  assert.equal(push[0].world.cold, undefined, 'unchanged cold world is not resent');
  const input = { seq: 1, ticks: 4, throttle: 1, steer: 0, brake: false };
  hostWs.take();
  for (let seq = 1; seq <= 3; seq++) {
    await room.webSocketMessage(guestWs, JSON.stringify({ type: 'sync', id: 10 + seq, state: { ...state(seq), drive_enabled: true, drive_inputs: [{ ...input, seq }] }, cold_revs: { camp: 9 }, commands: seq === 1 ? [{ seq: 1, action: 'table' }] : [] }));
    assert.equal(guestWs.take('reply')[0].id, 10 + seq);
  }
  await wait(80);
  const hostPushes = hostWs.take('push');
  assert.ok(hostPushes.length >= 1 && hostPushes.length <= 2, 'guest bursts are merged for the host');
  const last = hostPushes.at(-1);
  assert.equal(last.commands[0].action, 'table');
  assert.equal(last.players.find(p => p.id === g.player).state.drive_inputs[0].seq, 3);
  assert.equal(last.world, undefined);
});

test('socket errors report rate limits and closed rooms', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const h = room.room.add('Host', Date.now(), true);
  const g = room.room.add('Guest', Date.now());
  const guestWs = await connect(room, sockets, g.token);
  await room.webSocketMessage(guestWs, '{bad');
  assert.equal(guestWs.take('error')[0].status, 400);
  room.room.leave(h.token);
  await room.webSocketMessage(guestWs, JSON.stringify({ type: 'sync', id: 4, state: state() }));
  const error = guestWs.take('error')[0];
  assert.equal(error.status, 410);
  assert.equal(error.id, 4);
  assert.equal(guestWs.closed, 4410);
});
