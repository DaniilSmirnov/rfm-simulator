import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {RoomState, validWorld} from '../server/room-core.mjs';
const fixtures = JSON.parse(await readFile(new URL('../game/tests/fixtures/world_snapshots.json',import.meta.url),'utf8'));
for (const {name,world} of fixtures.valid) test('accepts '+name,()=>assert.equal(validWorld(world),true));
for (const {name,world} of fixtures.invalid) test('rejects '+name,()=>assert.equal(validWorld(world),false));
test('invalid hot or cold update preserves the complete last good room state',()=>{
  const room=new RoomState();
  const host=room.add('Host',1000,true);
  const state={pos:[0,1,2],car:[0,1,2],heading:0,yaw:0,pitch:0,in_car:false};
  room.sync({token:host.token,state,world:{elapsed:1,cold_revs:{camp:1}},cold:{camp:{chairs:true}}},1100);
  const before=structuredClone(room.data);
  for(const data of [{world:{elapsed:99,driving:17}},{world:{elapsed:99,cold_revs:{camp:2}},cold:{camp:{camp:[1]}}}]) {
    assert.throws(()=>room.sync({token:host.token,state,...data},1200),e=>e.status===400);
    assert.deepEqual(room.data.world,before.world);
    assert.deepEqual(room.data.cold,before.cold);
    assert.deepEqual(room.data.cold_revs,before.cold_revs);
    assert.equal(room.data.world_time,before.world_time);
  }
});
test('rejects non-finite values and excessive nesting or collections',()=>{
  assert.equal(validWorld({elapsed:NaN}),false);
  assert.equal(validWorld({camp:[0,Infinity,0]}),false);
  assert.equal(validWorld({racers:Array(65).fill({id:1,variant:0,pos:[0,0,0],yaw:0,state:'racing'})}),false);
  let nested={}; for(let i=0;i<20;i++)nested={nested};
  assert.equal(validWorld({extension:nested}),false);
});
