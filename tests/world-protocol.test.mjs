import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validateWorld } from '../server/world-protocol.mjs';
import { RoomState } from '../server/room-core.mjs';
const fixture = () => JSON.parse(readFileSync(new URL('../game/tests/fixtures/world_v1.json', import.meta.url)));
const state = {pos:[0,0,0],car:[0,0,0],heading:0,yaw:0,pitch:0,in_car:false};

test('versioned world validates complete nested snapshots and rejects incompatible data', () => {
  const world = fixture();
  assert.equal(validateWorld(world, {legacy:false}), '');
  for (const mutate of [w => w.world_protocol = 2, w => delete w.elapsed, w => w.elapsed = NaN,
    w => w.camp = [0,0], w => w.flag_poses.guest = Array(4).fill({pos:[0,0,0],yaw:0}),
    w => w.driving = [], w => w.fallen = [{id:0,dir:[0,0,0],age:'bad'}],
    w => w.npc_people = [{id:0,pos:[0,0,0],yaw:0,action:'watch',helper:'bad'}],
    w => w.camp_cooking = {pot:true,pot_pos:[0]}, w => w.cargo = {held:{guest:{kind:'table'}}}]) {
    const invalid = structuredClone(world); mutate(invalid); assert.notEqual(validateWorld(invalid, {legacy:false}), '');
  }
});
test('invalid host world is rejected atomically before player or world state changes', () => {
  const room = new RoomState(), host = room.add('host', 1, true);
  room.sync({token:host.token,state,world:fixture()}, 2);
  const before = structuredClone(room.data);
  assert.throws(() => room.sync({token:host.token,state:{...state,pos:[9,0,0]},world:{...fixture(),generation_version:9}}, 3), /снимок мира/);
  assert.deepEqual(room.data, before);
});
test('host results are authenticated, durable and rejected commands are not retried', () => {
  const room = new RoomState(), host = room.add('host', 1, true), guest = room.add('guest', 2);
  room.sync({token:guest.token,state,commands:[{seq:1,action:'table'}]}, 3);
  const id = room.data.commands[0].id;
  room.sync({token:guest.token,state,results:[{id,status:'applied'}],ack:[id]}, 4);
  assert.equal(room.data.commands.length, 1);
  room.sync({token:host.token,state,ack:[id],results:[{id,status:'rejected',reason:'Нет стола.'}]}, 5);
  const restored = new RoomState(structuredClone(room.data));
  const reply = restored.sync({token:guest.token,state,commands:[{seq:1,action:'table'}]}, 6);
  assert.equal(restored.data.commands.length, 0);
  assert.deepEqual(reply.results, [{id,player:guest.player,status:'rejected',reason:'Нет стола.'}]);
});
