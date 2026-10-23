import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as wait } from 'node:timers/promises';
import { RallyRoom, dedicatedCreate } from '../server/worker.mjs';

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
  let alarm = null;
  const ctx = {
    blockConcurrencyWhile: fn => fn(),
    acceptWebSocket: ws => sockets.push(ws),
    getWebSockets: () => sockets,
    storage: { get: async key => storage.get(key), put: async (key, value) => storage.set(key, structuredClone(value)), getAlarm: async () => alarm, setAlarm: async value => { alarm = value; }, deleteAll: async () => storage.clear() },
  };
  return { room: new RallyRoom(ctx), sockets, storage, ctx };
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

test('a new hello retires the earlier sockets of the same participant', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const now = Date.now();
  const h = room.room.add('Host', now, true);
  const g = room.room.add('Guest', now);
  const hostWs = await connect(room, sockets, h.token);
  const guestOld = await connect(room, sockets, g.token);
  assert.equal(guestOld.closed, null);
  const guestNew = await connect(room, sockets, g.token);
  assert.equal(guestOld.closed, 4409, 'the earlier socket is closed');
  assert.equal(guestNew.closed, null);
  assert.equal(hostWs.closed, null, 'other participants are untouched');
  // The close handshake is asynchronous: the old socket stays in the runtime's
  // list for a while, but it no longer receives anything.
  assert.ok(sockets.includes(guestOld));
  for (const ws of [hostWs, guestOld, guestNew]) ws.take();
  await room.webSocketMessage(hostWs, JSON.stringify({ type: 'sync', id: 2, state: state(), cold_revs: {}, world: { elapsed: 5, cold_revs: {} } }));
  assert.equal(guestOld.take('push').length, 0);
  assert.equal(guestNew.take('push').length, 1);
  await room.webSocketMessage(guestOld, JSON.stringify({ type: 'hello', token: g.token }));
  assert.equal(guestOld.take('hello').length, 0, 'replaced sockets cannot reclaim membership');
  assert.deepEqual(room.sockets(g.player), [guestNew]);
  // A late message on the retired socket is refused, not served.
  await room.webSocketMessage(guestOld, JSON.stringify({ type: 'sync', id: 3, state: state() }));
  assert.equal(guestOld.take('error')[0].status, 401);
  assert.equal(guestOld.take('reply').length, 0);
  // Reconnecting the host retires its old socket too; a repeated hello on the
  // same socket changes nothing.
  const hostNew = await connect(room, sockets, h.token);
  assert.equal(hostWs.closed, 4409);
  await room.webSocketMessage(hostNew, JSON.stringify({ type: 'hello', id: 5, token: h.token, cold_revs: {} }));
  assert.equal(hostNew.closed, null);
});

test('direct-link setup reaches only the current socket of the other side, once', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const now = Date.now();
  const h = room.room.add('Host', now, true);
  const g = room.room.add('Guest', now);
  const hostWs = await connect(room, sockets, h.token);
  const guestOld = await connect(room, sockets, g.token);
  const guestNew = await connect(room, sockets, g.token);
  for (const ws of [hostWs, guestOld, guestNew]) ws.take();
  // The host answers and sends candidates to a guest that has reconnected.
  const answer = { kind: 'answer', sdp: 'v=0', session: 7 };
  const candidate = { kind: 'candidate', media: '0', index: 0, name: 'candidate:1', session: 7 };
  for (const data of [answer, candidate]) await room.webSocketMessage(hostWs, JSON.stringify({ type: 'signal', to: g.player, data }));
  assert.equal(guestOld.take('signal').length, 0);
  assert.deepEqual(guestNew.take('signal').map(m => m.data), [answer, candidate]);
  // And the other way round: the guest's offer reaches the host once.
  const offer = { kind: 'offer', sdp: 'v=0', session: 8 };
  await room.webSocketMessage(guestNew, JSON.stringify({ type: 'signal', to: h.player, data: offer }));
  assert.deepEqual(hostWs.take('signal'), [{ type: 'signal', from: g.player, data: offer }]);
});

test('direct-link setup is relayed between the host and a guest only', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const now = Date.now();
  const h = room.room.add('Host', now, true);
  const g = room.room.add('Guest', now);
  const g2 = room.room.add('Other', now);
  const hostWs = await connect(room, sockets, h.token);
  const guestWs = await connect(room, sockets, g.token);
  const otherWs = await connect(room, sockets, g2.token);
  for (const ws of [hostWs, guestWs, otherWs]) ws.take();
  const offer = { kind: 'offer', sdp: 'v=0', session: 7 };
  await room.webSocketMessage(guestWs, JSON.stringify({ type: 'signal', to: h.player, data: offer }));
  assert.deepEqual(hostWs.take('signal'), [{ type: 'signal', from: g.player, data: offer }]);
  assert.equal(otherWs.take('signal').length, 0, 'other members never see the setup');
  const answer = { kind: 'answer', sdp: 'v=0', session: 7 };
  await room.webSocketMessage(hostWs, JSON.stringify({ type: 'signal', to: g.player, data: answer }));
  assert.equal(guestWs.take('signal')[0].data.kind, 'answer');
  // Guests cannot open links to each other, and strangers cannot signal.
  await room.webSocketMessage(guestWs, JSON.stringify({ type: 'signal', to: g2.player, data: offer }));
  assert.equal(otherWs.take('signal').length, 0);
  const refused = guestWs.take('signal_error')[0];
  assert.equal(refused.status, 404);
  assert.equal(guestWs.closed, null, 'a refused relay keeps the room session open');
  await room.webSocketMessage(guestWs, JSON.stringify({ type: 'signal', to: h.player, data: { sdp: 'x'.repeat(20000) } }));
  assert.equal(guestWs.take('signal_error')[0].status, 400);
  const stranger = new FakeSocket();
  sockets.push(stranger);
  await room.webSocketMessage(stranger, JSON.stringify({ type: 'signal', to: h.player, data: offer }));
  assert.equal(hostWs.take('signal').length, 0);
});

test('direct-link setup is rate limited per member', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const now = Date.now();
  const h = room.room.add('Host', now, true);
  const g = room.room.add('Guest', now);
  const guestWs = await connect(room, sockets, g.token);
  await connect(room, sockets, h.token);
  guestWs.take();
  for (let i = 0; i < 130; i++) await room.webSocketMessage(guestWs, JSON.stringify({ type: 'signal', to: h.player, data: { kind: 'candidate', session: 1 } }));
  assert.ok(guestWs.take('signal_error').some(m => m.status === 429));
});

test('a participant with two sockets gets each push once per socket, not once per socket pair', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const now = Date.now();
  const h = room.room.add('Host', now, true);
  const g = room.room.add('Guest', now);
  const hostWs = await connect(room, sockets, h.token);
  // Hibernation can restore duplicate attachments saved before replacement.
  const guestOld = await connect(room, sockets, g.token);
  const guestNew = new FakeSocket();
  guestNew.serializeAttachment(guestOld.deserializeAttachment());
  sockets.push(guestNew);
  for (const ws of [hostWs, guestOld, guestNew]) ws.take();
  await room.webSocketMessage(hostWs, JSON.stringify({ type: 'sync', id: 2, state: state(), cold_revs: {}, world: { elapsed: 5, cold_revs: {} } }));
  assert.equal(guestOld.take('push').length, 1, 'old socket receives the snapshot once');
  assert.equal(guestNew.take('push').length, 1, 'new socket receives the snapshot once');
  // Both sockets of the host are served by one merged push as well.
  const hostSecond = new FakeSocket();
  hostSecond.serializeAttachment(hostWs.deserializeAttachment());
  sockets.push(hostSecond);
  for (const ws of [hostWs, hostSecond]) ws.take();
  await room.webSocketMessage(guestNew, JSON.stringify({ type: 'sync', id: 3, state: state(1), cold_revs: {} }));
  await wait(80);
  assert.equal(hostWs.take('push').length, 1);
  assert.equal(hostSecond.take('push').length, 1);
});

test('pending sockets are capped and expire through the durable alarm after restoration', async t => {
  const { room, sockets, storage, ctx } = fakeRoom();
  await wait(0);
  const host = room.room.add('Host', Date.now(), true);
  storage.set('room', structuredClone(room.room.data));
  const NativeResponse = globalThis.Response;
  t.mock.method(globalThis, 'Response', function(body, options) {
    if (options?.status === 101) return options;
    return new NativeResponse(body, options);
  });
  globalThis.Response.json = NativeResponse.json;
  globalThis.WebSocketPair ??= function() {};
  t.mock.method(globalThis, 'WebSocketPair', function() { return [new FakeSocket(), new FakeSocket()]; });
  const request = new Request('https://game.test/socket', { headers: { Upgrade: 'websocket' } });
  for (let i = 0; i < 8; i++) assert.equal((await room.fetch(request)).status, 101);
  assert.equal((await room.fetch(request)).status, 429);
  assert.equal(sockets.length, 8);
  const deadline = sockets[0].attachment.hello_deadline;
  assert.ok(deadline > Date.now() && deadline <= Date.now() + 10000);
  assert.equal(await ctx.storage.getAlarm(), deadline);
  await room.persist(Date.now(), true);
  assert.equal(await ctx.storage.getAlarm(), deadline, 'saving room state does not postpone hello expiry');
  for (const ws of sockets) ws.attachment.hello_deadline = Date.now() - 1;
  const restored = new RallyRoom(ctx);
  await wait(0);
  await restored.alarm();
  for (const ws of sockets) assert.equal(ws.closed, 4401);
  await room.webSocketMessage(sockets[0], JSON.stringify({ type: 'hello', token: host.token }));
  assert.equal(room.sockets(host.player).length, 0);
  assert.equal((await room.fetch(request)).status, 101);
  const expiredOnUpgrade = sockets.at(-1);
  expiredOnUpgrade.attachment.hello_deadline = Date.now() - 1;
  assert.equal((await room.fetch(request)).status, 101);
  assert.equal(expiredOnUpgrade.closed, 4401, 'upgrades expire pending sockets even before the alarm');
  const disconnected = sockets.at(-1);
  await room.webSocketClose(disconnected, 1000);
  assert.equal(disconnected.attachment.hello_deadline, undefined, 'closing releases pending capacity');
  await room.webSocketMessage(disconnected, JSON.stringify({ type: 'hello', token: host.token }));
  assert.equal(disconnected.take('hello').length, 0, 'retired sockets cannot authenticate');
});


test('expired hello is rejected before the alarm runs', async () => {
  const { room, sockets } = fakeRoom();
  await wait(0);
  const host = room.room.add('Host', Date.now(), true);
  const ws = new FakeSocket();
  ws.serializeAttachment({ hello_deadline: Date.now() - 1 });
  sockets.push(ws);
  await room.webSocketMessage(ws, JSON.stringify({ type: 'hello', token: host.token }));
  assert.equal(ws.closed, 4401);
  assert.equal(room.sockets(host.player).length, 0);
});

test('only the dedicated key marks a room as served and picks its ID', () => {
  const raw = JSON.stringify({ name: 'Сервер', dedicated: true, room: 'D0D0D0', stage: 1 });
  const anonymous = dedicatedCreate(raw, null, 'key');
  assert.deepEqual(JSON.parse(anonymous.raw), { name: 'Сервер', stage: 1 });
  assert.equal(anonymous.room, '');
  const served = dedicatedCreate(raw, 'key', 'key');
  assert.deepEqual(JSON.parse(served.raw), { name: 'Сервер', stage: 1, dedicated: true });
  assert.equal(served.room, 'D0D0D0');
  assert.equal(dedicatedCreate(JSON.stringify({ room: '../x' }), 'key', 'key').room, '');
  for (const [key, secret] of [['wrong', 'key'], ['ke', 'key'], ['', ''], ['key', undefined]]) {
    assert.throws(() => dedicatedCreate(raw, key, secret), e => e.status === 403);
  }
});

test('a dedicated server whose socket closes closes its room at once', async () => {
  const { room, sockets, storage } = fakeRoom();
  await wait(0);
  const server = room.room.add('Сервер', Date.now(), true, { dedicated: true });
  const guest = room.room.add('Guest', Date.now(), false);
  const serverWs = await connect(room, sockets, server.token);
  const guestWs = await connect(room, sockets, guest.token);
  guestWs.take();
  await room.webSocketClose(serverWs, 1006);
  assert.equal(room.room.data.closed, true);
  assert.deepEqual(guestWs.take('error').map(m => m.status), [410], 'the guest is told the room is closed');
  assert.equal(guestWs.closed, 4410);
  assert.equal(storage.size, 0);

  // An ordinary host may come back over HTTP: its socket closing keeps the room.
  const other = fakeRoom();
  await wait(0);
  const host = other.room.room.add('Host', Date.now(), true);
  const hostWs = await connect(other.room, other.sockets, host.token);
  await other.room.webSocketClose(hostWs, 1006);
  assert.equal(other.room.room.data.closed, false);
});
