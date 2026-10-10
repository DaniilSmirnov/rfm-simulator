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

test('room id alphabet and pattern describe the same format', () => {
  const pattern = new RegExp(protocol.room_id_pattern);
  const alphabet = [...protocol.room_id_alphabet];
  assert.ok(pattern.test(alphabet.slice(0, protocol.room_id_length).join('').padEnd(protocol.room_id_length, alphabet[0])));
  for (let code = 32; code < 127; code++) {
    const c = String.fromCharCode(code);
    assert.equal(pattern.test(c.repeat(protocol.room_id_length)), alphabet.includes(c), 'character ' + c);
  }
  assert.equal(pattern.test('A'.repeat(protocol.room_id_length + 1)), false);
});

test('game scripts avoid engine modules missing from the Web template', async () => {
  const custom = await read('engine/custom.py');
  assert.match(custom, /modules_enabled_by_default = False/);
  // Disabled modules parse natively but fail to compile in the exported game.
  const disabled = {RegEx: 'regex', XMLParser: 'xml', ZIPReader: 'zip'};
  const dir = new URL('../game/scripts/', import.meta.url);
  for (const file of (await readdir(dir)).filter(f => f.endsWith('.gd'))) {
    const text = (await readFile(new URL(file, dir), 'utf8')).replace(/#.*$/gm, '');
    for (const [symbol, module] of Object.entries(disabled)) {
      if (custom.includes(`module_${module}_enabled = True`)) continue;
      assert.doesNotMatch(text, new RegExp(`\\b${symbol}\\b`), `${file} uses ${symbol} (module_${module} is disabled)`);
    }
  }
});

test('web scripts accept exactly the protocol room id format', async () => {
  const charClass = protocol.room_id_pattern.match(/\[[^\]]+\]\{\d+\}/)[0];
  for (const path of ['web/room-session.js', 'web/platform/vk.js']) {
    assert.ok((await read(path)).includes(charClass), path + ' uses ' + charClass);
  }
});

test('server content counts follow the catalog and the game stage list', async () => {
  const stages = JSON.parse(await read('game/data/stages.json')).stages.length;
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

test('network classes from optional engine modules are reached through ClassDB', async () => {
  // Older Web templates lack these modules: a bare identifier would stop the
  // script from compiling, a ClassDB lookup just reports the class missing.
  const dir = new URL('../game/scripts/', import.meta.url);
  for (const file of (await readdir(dir)).filter(f => f.endsWith('.gd'))) {
    const code = (await readFile(new URL(file, dir), 'utf8')).replace(/#.*$/gm, '').replace(/"(?:\\.|[^"\\])*"/g, '""');
    assert.doesNotMatch(code, /\b(WebSocketPeer|WebRTCPeerConnection|WebRTCDataChannel|WebRTCMultiplayerPeer)\b/, `${file} names an optional network class directly`);
  }
});

test('stage registry: one entry per catalog stage, each with an existing biome script', async () => {
  const {stages} = JSON.parse(await read('game/data/stages.json'));
  const catalog = JSON.parse(await read('game/data/store_catalog.json')).filter(p => p.type === 'stage');
  assert.deepEqual(catalog.map(p => p.content_id).sort((a, b) => a - b), stages.map((_, i) => i));
  assert.equal(new Set(stages.map(s => s.id)).size, stages.length, 'stage ids are unique');
  for (const [i, s] of stages.entries()) {
    assert.equal(catalog.find(p => p.content_id === i).title, s.title, 'catalog title of stage ' + i);
    const biome = await read(s.biome.replace('res://', 'game/'));
    assert.match(biome, /^extends "res:\/\/scripts\/stage_biome\.gd"/, s.biome + ' implements the stage contract');
  }
  const stageGd = await read('game/scripts/stage.gd');
  assert.doesNotMatch(stageGd.replace(/#.*$/gm, ''), /\bif (not )?(winter|provence|desert|lakeland)\b|variant == \d/, 'stage.gd does not branch on a stage identity');
});

test('car registry: one record per catalog car, same names, known drive and model', async () => {
  const {cars} = JSON.parse(await read('game/data/cars.json'));
  const catalog = JSON.parse(await read('game/data/store_catalog.json')).filter(p => p.type === 'car');
  assert.equal(cars.length, CAR_COUNT);
  assert.deepEqual(catalog.map(p => p.content_id).sort((a, b) => a - b), cars.map((_, i) => i));
  for (const [i, car] of cars.entries()) {
    assert.equal(catalog.find(p => p.content_id === i).title, car.name, 'catalog title of car ' + i);
    assert.ok(!car.handling?.drive || ['front', 'rear', 'all'].includes(car.handling.drive), car.name + ' drive');
    assert.ok(!car.model || car.model === 'shell' ? car.shape?.length === 6 : true, car.name + ' needs a shape');
  }
  // Car look, handling and trunk come from cars.json, not from index checks.
  for (const file of ['game/scripts/props.gd', 'game/scripts/player_handling.gd']) {
    const code = (await read(file)).replace(/#.*$/gm, '');
    const fleet = code.slice(code.indexOf('func player_car('), code.indexOf('func skewer('));
    const scope = file.endsWith('props.gd') ? fleet + code.slice(code.indexOf('func trunk_profile('), code.indexOf('func gear_box(')) : code;
    assert.doesNotMatch(scope, /variant (==|!=|in|not in) [\d[]/, file + ' has no per-car index branches');
  }
});
