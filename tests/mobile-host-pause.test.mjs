import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { RoomState } from '../server/room-core.mjs';

const read = async path => readFile(new URL('../' + path, import.meta.url), 'utf8');

test('fullscreen control does not sit over top-right mobile pause controls', async () => {
  const source = await read('web/fullscreen.js');
  assert.match(source, /left: 50%/);
  assert.match(source, /translateX\(-50%\)/);
  assert.doesNotMatch(source, /right: max\(12px/);
});

test('vehicle uses circular joystick with independent accelerator and brake', async () => {
  const source = await read('game/scripts/mobile_controls.gd');
  assert.doesNotMatch(source, /delta\.y = 0/);
  assert.match(source, /add_button\("Газ"/);
  assert.match(source, /add_button\("Тормоз"/);
});

test('camera follows moving car, while flames run on independent visual time', async () => {
  const game = await read('game/scripts/game.gd');
  const player = await read('game/scripts/player_motion.gd');
  const cooking = await read('game/scripts/camp_cooking.gd');
  assert.match(player, /var travel_yaw = game\.heading/);
  assert.match(player, /lerp_angle\(game\.view_yaw, travel_yaw/);
  assert.match(game, /camp_cooking\.animate_flames\(Time\.get_ticks_msec\(\)/);
  assert.match(cooking, /func animate_flames\(visual_time: float\)/);
});

test('hidden or unresponsive host pauses all guests and resumes on return', () => {
  const room = new RoomState();
  const host = room.add('Host', 1000, true);
  const guest = room.add('Guest', 1000);
  const state = { pos:[0,0,0],car:[0,0,0],heading:0,yaw:0,pitch:0,in_car:true };
  const hostSync = time => room.sync({ token:host.token,state,world:{paused:false} },time);
  const guestSync = time => room.sync({ token:guest.token,state },time);
  hostSync(1000);
  assert.equal(guestSync(1200).world.paused, false);
  room.heartbeat(host.token, 1300, true);
  assert.equal(guestSync(1400).world.paused, true);
  room.heartbeat(host.token, 1500, false);
  assert.equal(guestSync(1600).world.paused, false);
  assert.equal(guestSync(5501).world.paused, true);
  hostSync(5600);
  assert.equal(guestSync(5700).world.paused, false);
});
