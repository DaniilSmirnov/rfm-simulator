import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {RoomState, MAX_PLAYERS, STAGE_COUNT, CAR_COUNT, protocol, validWorld} from '../server/room-core.mjs';

const read = path => readFile(new URL('../' + path, import.meta.url), 'utf8');
const state = () => ({ pos: [0, 1, 2], car: [3, 4, 5], heading: 1, yaw: 2, pitch: 0, in_car: false, tow: false, beer: -1 });

test('room protocol file is the single source of client and server limits', async () => {
  assert.equal(MAX_PLAYERS, protocol.max_players);
  assert.equal(new Set(protocol.actions).size, protocol.actions.length, 'actions are unique');
  const gd = await read('game/scripts/net_protocol.gd');
  assert.match(gd, /res:\/\/data\/net_protocol\.json/);
  const room = await read('game/scripts/room.gd');
  assert.doesNotMatch(room, /SHARED_ACTIONS|\/8|max_length = 6/, 'room.gd uses NetProtocol instead of literals');
  const exportPresets = await read('game/export_presets.cfg');
  assert.match(exportPresets, /include_filter="data\/\*\.json"/, 'the protocol file ships in Web builds');
});

test('web scripts accept exactly the protocol room id format', async () => {
  const charClass = protocol.room_id_pattern.match(/\[[^\]]+\]\{\d+\}/)[0];
  for (const path of ['web/room-session.js', 'web/platform/vk.js']) {
    assert.ok((await read(path)).includes(charClass), path + ' uses ' + charClass);
  }
});

test('server content counts follow the catalog and the game stage list', async () => {
  const stageGd = await read('game/scripts/stage.gd');
  const stages = stageGd.match(/^const STAGES = \[(.*)\]$/m)[1].split('",').length;
  assert.equal(STAGE_COUNT, stages);
  const r = new RoomState();
  assert.equal(r.add('Host', 1000, true, {stage: 99}).stage, STAGE_COUNT - 1);
  assert.equal(r.add('Guest', 1000, false, {car_model: CAR_COUNT}).car_model, 1, 'unknown car falls back to the slot');
});

test('host world must be a plain object with plain keys', () => {
  assert.equal(validWorld({elapsed: 1, cold_revs: {camp: 1}}), true);
  for (const bad of [null, [], 'x', {'Bad key': 1}, Object.fromEntries(Array.from({length: 200}, (_, i) => ['k' + 'x'.repeat(i % 20) + 'a'.repeat(i)  , 1]))]) {
    assert.equal(validWorld(bad), false);
  }
  const r = new RoomState();
  const h = r.add('Host', 1000, true);
  assert.throws(() => r.sync({token: h.token, state: state(), world: {'Bad key': 1}}, 1100), /снимок мира/);
  assert.doesNotThrow(() => r.sync({token: h.token, state: state(), world: {elapsed: 1}}, 1200));
});

test('protocol 2 guests are simulated by the host once they received the world', () => {
  const r = new RoomState();
  const h = r.add('Host', 1000, true, {protocol: protocol.protocol_version});
  const g = r.add('Guest', 1000, false, {protocol: protocol.protocol_version});
  const legacy = r.add('Old', 1000);
  let reply = r.sync({token: g.token, state: {...state(), drive_enabled: false}}, 1100);
  assert.equal(reply.world, null, 'no world yet');
  assert.equal(r.data.players[g.player].state.drive_enabled, false);
  r.sync({token: h.token, state: state(), world: {elapsed: 1}}, 1200);
  r.sync({token: g.token, state: {...state(), drive_enabled: false}}, 1300);
  reply = r.sync({token: g.token, state: {...state(), drive_enabled: false}}, 1400);
  assert.equal(r.data.players[g.player].state.drive_enabled, true, 'the guest cannot opt out of host simulation');
  r.sync({token: legacy.token, state: {...state(), drive_enabled: false}}, 1500);
  assert.equal(r.data.players[legacy.player].state.drive_enabled, false, 'older clients keep their own flag');
  assert.equal(r.data.players[h.player].state.drive_enabled, false, 'the host is never simulated');
});
