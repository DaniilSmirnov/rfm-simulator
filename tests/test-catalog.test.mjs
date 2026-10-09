import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join,dirname} from 'node:path';
import {groups,nodeSuites,verifyRegistry,slowTests} from '../scripts/test-catalog.mjs';

const here=dirname(fileURLToPath(import.meta.url));
test('every functional Godot test is registered exactly once in a CI shard',async()=>{
 const actual=await readdir(join(here,'..','game','tests'));
 const manifest=verifyRegistry(actual);
 assert.equal(manifest.count,actual.filter(f=>/^test_[a-z0-9_]+\.gd$/.test(f)).length);
 assert.ok(manifest.count>=55);
 assert.equal(new Set(Object.values(groups).flat()).size,manifest.count);
 for(const files of Object.values(groups))assert.ok(files.length>=10);
});
test('critical VK and vehicle contract cases are not hidden in night-only jobs',()=>{
 for(const file of ['test_rolling_wheels.gd','test_niva_integration.gd','test_vehicle_contract.gd',
  'test_vk_catalog_matrix.gd','test_vk_invite_ui.gd','test_room_origin.gd','test_trunk.gd'])
  assert.ok(groups.core.includes(file),file);
 for(const file of ['test_rally_traffic.gd','test_network_motion.gd','test_tow_recovery.gd'])
  assert.ok(groups.simulation.includes(file),file);
 for(const file of ['test_woodland.gd','test_canyon.gd','test_baked_village.gd'])
  assert.ok(groups.world.includes(file),file);
});
test('duplicate and missing registry entries are rejected, not silently skipped',()=>{
 const all=Object.values(groups).flat();
 assert.throws(()=>verifyRegistry(all.slice(1)),/missing_files/);
 assert.throws(()=>verifyRegistry([...all,'test_unregistered.gd']),/unclassified/);
 for(const file of slowTests)assert.ok(all.includes(file),file);
});
test('node test groups include VK, browser viewport and multiplayer regressions',()=>{
 const combined=Object.values(nodeSuites).flat(1).flat();
 for(const f of ['tests/platform.test.mjs','tests/auth-vk.test.mjs',
  'tests/mobile-host-pause.test.mjs','tests/rate-limits.test.mjs',
  'tests/room-core.test.mjs','tests/room-session.test.mjs'])
  assert.ok(combined.includes(f),f);
});
