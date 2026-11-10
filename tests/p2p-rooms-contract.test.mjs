import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as wait } from 'node:timers/promises';
import { RallyRoom } from '../server/worker.mjs';

// libs/godot-p2p-rooms (P2PRooms) is a friend's game on the same room server.
// It relies on the part of the room contract below; a server change that
// breaks one of these breaks that game too (see libs/godot-p2p-rooms/README.md).
const APP_PROTOCOL = 1000001;
// P2PRooms.MEMBERSHIP_STATE: the least state a sync is accepted with.
const MEMBERSHIP_STATE = { pos: [0, 0, 0], car: [0, 0, 0], heading: 0, yaw: 0, pitch: 0, in_car: false };

class FakeSocket {
  constructor() { this.sent = []; this.attachment = null; this.closed = null; }
  send(text) { this.sent.push(JSON.parse(text)); }
  serializeAttachment(value) { this.attachment = structuredClone(value); }
  deserializeAttachment() { return this.attachment; }
  close(code) { this.closed = code; }
  take(type) { const found = this.sent.filter(m => m.type === type); this.sent = this.sent.filter(m => m.type !== type); return found; }
}
async function fakeRoom() {
  const sockets = [];
  const storage = new Map();
  let alarm = null;
  const ctx = {
    blockConcurrencyWhile: fn => fn(),
    acceptWebSocket: ws => sockets.push(ws),
    getWebSockets: () => sockets,
    storage: { get: async key => storage.get(key), put: async (key, value) => storage.set(key, structuredClone(value)), getAlarm: async () => alarm, setAlarm: async value => { alarm = value; }, deleteAll: async () => storage.clear() },
  };
  const room = new RallyRoom(ctx);
  await wait(0);
  return { room, sockets };
}
async function post(room, action, body) {
  const response = await room.fetch(new Request(`http://room/${action}`, { method: 'POST', body: JSON.stringify(body) }));
  return { status: response.status, ...await response.json() };
}
async function hello(room, sockets, token) {
  const ws = new FakeSocket();
  sockets.push(ws);
  await room.webSocketMessage(ws, JSON.stringify({ type: 'hello', id: 1, token }));
  return ws;
}

test('P2PRooms contract: create, join, hello and membership syncs', async () => {
  const { room, sockets } = await fakeRoom();
  const host = await post(room, 'create', { name: 'Хост', protocol: APP_PROTOCOL });
  assert.equal(host.status, 200);
  assert.equal(host.host, true);
  assert.equal(typeof host.player, 'string');
  assert.equal(typeof host.token, 'string');
  // Another game's protocol number is refused with 409.
  assert.equal((await post(room, 'join', { name: 'Чужой', protocol: 14 })).status, 409);
  const guest = await post(room, 'join', { name: 'Гость', protocol: APP_PROTOCOL });
  assert.equal(guest.status, 200);
  assert.equal(guest.host, false);

  const hws = await hello(room, sockets, host.token);
  assert.equal(hws.take('hello')[0].player, host.player);
  const gws = await hello(room, sockets, guest.token);
  assert.equal(gws.take('hello')[0].player, guest.player);

  await room.webSocketMessage(gws, JSON.stringify({ type: 'sync', id: 2, state: MEMBERSHIP_STATE }));
  const reply = gws.take('reply')[0];
  assert.equal(reply.id, 2);
  assert.equal(reply.host, host.player);
  assert.ok(Number.isFinite(reply.server_time));
  assert.deepEqual(reply.players.map(p => [p.id, p.name, p.slot]), [[host.player, 'Хост', 0], [guest.player, 'Гость', 1]]);

  // The host's sync is pushed to guests at once, with the same roster.
  await room.webSocketMessage(hws, JSON.stringify({ type: 'sync', id: 3, state: MEMBERSHIP_STATE }));
  assert.equal(hws.take('reply')[0].host, host.player);
  const push = gws.take('push').at(-1);
  assert.equal(push.host, host.player);
  assert.equal(push.players.length, 2);
});

test('P2PRooms contract: WebRTC setup is relayed between host and guest only', async () => {
  const { room, sockets } = await fakeRoom();
  const host = await post(room, 'create', { name: 'Хост', protocol: APP_PROTOCOL });
  const a = await post(room, 'join', { name: 'A', protocol: APP_PROTOCOL });
  const b = await post(room, 'join', { name: 'B', protocol: APP_PROTOCOL });
  const hws = await hello(room, sockets, host.token);
  const aws = await hello(room, sockets, a.token);
  const bws = await hello(room, sockets, b.token);
  const offer = { kind: 'offer', sdp: 'v=0', session: 123 };
  await room.webSocketMessage(aws, JSON.stringify({ type: 'signal', to: host.player, data: offer }));
  assert.deepEqual(hws.take('signal'), [{ type: 'signal', from: a.player, data: offer }]);
  const answer = { kind: 'answer', sdp: 'v=0', session: 123 };
  await room.webSocketMessage(hws, JSON.stringify({ type: 'signal', to: a.player, data: answer }));
  assert.deepEqual(aws.take('signal'), [{ type: 'signal', from: host.player, data: answer }]);
  // Guest to guest is refused, and the socket stays open.
  await room.webSocketMessage(aws, JSON.stringify({ type: 'signal', to: b.player, data: offer }));
  assert.equal(aws.take('signal_error')[0].status, 404);
  assert.equal(bws.take('signal').length, 0);
  assert.equal(aws.closed, null);
});

test('P2PRooms contract: the host leaving closes the room for guests', async () => {
  const { room, sockets } = await fakeRoom();
  const host = await post(room, 'create', { name: 'Хост', protocol: APP_PROTOCOL });
  const guest = await post(room, 'join', { name: 'Гость', protocol: APP_PROTOCOL });
  const gws = await hello(room, sockets, guest.token);
  assert.equal((await post(room, 'leave', { token: host.token })).left, true);
  await room.webSocketMessage(gws, JSON.stringify({ type: 'sync', id: 4, state: MEMBERSHIP_STATE }));
  const error = gws.take('error')[0];
  assert.equal(error.status, 410);
  assert.equal(gws.closed, 4410);
});
