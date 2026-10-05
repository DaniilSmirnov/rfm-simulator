import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RoomState, MAX_PLAYERS } from '../server/room-core.mjs';
const state = (x = 0) => ({ pos: [x, 1, 2], car: [3, 4, 5], heading: 1, yaw: 2, pitch: 0, in_car: false, tow: false, beer: -1 });
const setup = () => { const r = new RoomState(); const h = r.add('Хозяин', 1000, true); const g = r.add('Друг', 1000); return { r, h, g }; };
test('create, join, private tokens and roster without token leaks', () => {
  const { r, h, g } = setup();
  assert.notEqual(h.token, g.token);
  assert.equal(h.slot, 0);
  assert.equal(g.slot, 1);
  const reply = r.sync({ token: h.token, state: state(), world: { racers: [] } }, 1100);
  assert.equal(reply.players.length, 2);
  assert.equal(reply.players[0].token, undefined);
  assert.equal(reply.host, h.player);
});
test('unknown room and full room return useful errors', () => {
  assert.throws(() => new RoomState().add('g', 0), e => e.status === 404);
  const { r } = setup();
  for (let i = 2; i < MAX_PLAYERS; i++) r.add('g', 1000);
  assert.throws(() => r.add('overflow', 1000), e => e.status === 409);
});
test('only the host can publish shared world and receive commands', () => {
  const { r, h, g } = setup();
  const world = { camp: [1, 2, 3], racers: [] };
  r.sync({ token: h.token, state: state(), world }, 1100);
  const guest = r.sync({ token: g.token, state: state(10), world: { camp: 'forged' }, commands: [{ seq: 1, action: 'table' }] }, 1200);
  assert.deepEqual(guest.world, world);
  assert.deepEqual(guest.commands, []);
  const host = r.sync({ token: h.token, state: state() }, 1300);
  assert.equal(host.commands[0].player, g.player);
  assert.equal(host.commands[0].state.pos[0], 10);
});
test('retry is idempotent and commands remain until host acknowledges them', () => {
  const { r, h, g } = setup();
  const body = { token: g.token, state: state(), commands: [{ seq: 1, action: 'chairs' }] };
  r.sync(body, 1100); r.sync(body, 1200);
  const a = r.sync({ token: h.token, state: state() }, 1300);
  const b = r.sync({ token: h.token, state: state() }, 1400);
  assert.equal(a.commands.length, 1); assert.equal(b.commands.length, 1);
  assert.equal(r.sync({ token: h.token, state: state(), ack: [a.commands[0].id] }, 1500).commands.length, 0);
  assert.equal(r.sync(body, 1600).accepted, 1);
  assert.equal(r.data.commands.length, 0);
});
test('invalid tokens, positions and actions cannot modify room', () => {
  const { r, g } = setup();
  assert.throws(() => r.sync({ token: 'fake', state: state() }, 1100), e => e.status === 401);
  assert.throws(() => r.sync({ token: g.token, state: { ...state(), pos: [Infinity, 0, 0] } }, 1100), e => e.status === 400);
  r.sync({ token: g.token, state: state(), commands: [{ seq: 1, action: 'die' }, { seq: -3, action: 'rally' }] }, 1100);
  assert.equal(r.data.commands.length, 0);
});
test('late join receives picnic and current rally snapshot', () => {
  const { r, h } = setup();
  const world = { camp: [1, 2, 3], chairs: true, cooking: true, cook_time: 25, racers: [{ id: 1 }] };
  r.sync({ token: h.token, state: state(), world }, 1100);
  const late = r.add('late', 1200);
  assert.deepEqual(r.sync({ token: late.token, state: state() }, 1300).world, world);
});
test('guest departure removes its pending commands and host departure closes room', () => {
  const { r, h, g } = setup();
  r.sync({ token: g.token, state: state(), commands: [{ seq: 1, action: 'rally' }] }, 1100);
  r.leave(g.token);
  assert.equal(r.data.commands.length, 0);
  assert.equal(Object.keys(r.data.players).length, 1);
  r.leave(h.token);
  assert.throws(() => r.add('new', 1200), e => e.status === 404);
});
test('timeout removes idle guest and closes room when host disappears', () => {
  const { r, h, g } = setup();
  r.sync({ token: h.token, state: state() }, 91000);
  r.expire(92000);
  assert.equal(r.data.players[g.player], undefined);
  assert.equal(r.data.closed, false);
  r.expire(182000);
  assert.equal(r.data.closed, true);
});
test('Durable Object restoration preserves identities and world', () => {
  const { r, h, g } = setup();
  r.sync({ token: h.token, state: state(), world: { paused: true } }, 1100);
  const restored = new RoomState(structuredClone(r.data));
  assert.equal(restored.sync({ token: g.token, state: state() }, 1200).world.paused, true);
});

test('background heartbeat keeps membership alive without advancing world', () => {
  const { r, h, g } = setup();
  r.sync({ token: h.token, state: state(), world: { elapsed: 1 } }, 1100);
  r.heartbeat(h.token, 85000);
  r.heartbeat(g.token, 85000);
  r.expire(95000);
  assert.equal(r.data.closed, false);
  assert.equal(Object.keys(r.data.players).length, 2);
  assert.equal(r.data.world.elapsed, 1);
});
