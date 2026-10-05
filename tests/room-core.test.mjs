import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RoomState, MAX_PLAYERS } from '../server/room-core.mjs';
const state = (x = 0) => ({ pos: [x, 1, 2], car: [3, 4, 5], heading: 1, yaw: 2, pitch: 0, in_car: false, tow: false, beer: -1 });
const setup = () => { const r = new RoomState(); const h = r.add('Хозяин', 1000, true); const g = r.add('Друг', 1000); return { r, h, g }; };
test('snapshot timestamps belong to state updates rather than polls or heartbeats', () => {
  const { r, h, g } = setup();
  r.sync({ token: h.token, state: state(), world: { elapsed: 1 } }, 1100);
  r.heartbeat(h.token, 1150);
  let reply = r.sync({ token: g.token, state: state() }, 1200);
  assert.equal(reply.server_time, 1200);
  assert.equal(reply.world_time, 1100);
  assert.equal(reply.players.find(p => p.id === h.player).state_time, 1100);
  const restored = new RoomState(structuredClone(r.data));
  reply = restored.sync({ token: h.token, state: state(), world: { elapsed: 2 } }, 1300);
  assert.equal(reply.world_time, 1300);
  assert.equal(reply.players.find(p => p.id === g.player).state_time, 1200);
});
test('host stage and individual car choices persist through joins, sync and restore', () => {
  const r = new RoomState();
  const h = r.add('Host', 1000, true, { stage: 1, car_model: 5 });
  const g = r.add('Guest', 1000, false, { stage: 0, car_model: 2 });
  assert.equal(h.stage, 1);
  assert.equal(g.stage, 1);
  assert.equal(g.car_model, 2);
  const restored = new RoomState(structuredClone(r.data));
  const reply = restored.sync({ token: g.token, state: { ...state(), car_model: 7, stage: 0 } }, 1200);
  assert.equal(reply.stage, 1);
  assert.deepEqual(reply.players.map(p => p.car_model), [5, 2]);
  const late = restored.add('Late', 1300, false, { stage: 0, car_model: Infinity });
  assert.equal(late.stage, 1);
  assert.equal(late.car_model, late.slot);
});
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

test('personal car suspension tilt survives sync and invalid tilt falls back safely', () => {
  const { r, h } = setup();
  let reply = r.sync({ token: h.token, state: { ...state(), tilt: [0.15, 1, -0.2] } }, 1100);
  assert.deepEqual(reply.players[0].state.tilt, [0.15, 1, -0.2]);
  reply = r.sync({ token: h.token, state: { ...state(), tilt: [null, 1, 0] } }, 1200);
  assert.deepEqual(reply.players[0].state.tilt, [0, 1, 0]);
});

test('eight assigned car slots survive sync and reuse vacated slots', () => {
  const { r, h } = setup();
  for (let i = 2; i < 8; i++) r.add('Друг', 1000);
  const reply = r.sync({ token: h.token, state: { ...state(), slot: 7 } }, 1100);
  assert.deepEqual(reply.players.map(p => p.slot).sort(), [0, 1, 2, 3, 4, 5, 6, 7]);
  assert.equal(reply.players.find(p => p.id === h.player).slot, 0);
  const departing = Object.values(r.data.players).find(p => p.slot === 4);
  r.leave(departing.token);
  assert.equal(r.add('Новый', 1200).slot, 4);
});
test('food animation phase survives sync and defaults to idle for older clients', () => {
  const { r, h } = setup();
  let reply = r.sync({ token: h.token, state: { ...state(), eat: 1.85 } }, 1100);
  assert.equal(reply.players[0].state.eat, 1.85);
  reply = r.sync({ token: h.token, state: state() }, 1200);
  assert.equal(reply.players[0].state.eat, -1);
  reply = r.sync({ token: h.token, state: { ...state(), eat: Infinity } }, 1300);
  assert.equal(reply.players[0].state.eat, -1);
});

test('beer count, vehicle speed and bounded tree requests survive room sync', () => {
  const { r, h } = setup();
  const reply = r.sync({ token: h.token, state: { ...state(), beers: 30, speed: 12, trees: [{ id: 7, dir: [1, 0, 0] }, { id: -1, dir: [1, 0, 0] }, { id: 3, dir: [null, 0, 0] }] } }, 1100);
  assert.equal(reply.players[0].state.beers, 30);
  assert.equal(reply.players[0].state.speed, 12);
  assert.deepEqual(reply.players[0].state.trees, [{ id: 7, dir: [1, 0, 0] }]);
});
