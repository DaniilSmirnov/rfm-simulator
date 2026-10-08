import { join } from 'node:path';
import { getGodot, root, run } from './godot.mjs';
const godot = await getGodot();
const project = join(root, 'game');
const suite = process.argv.find(arg => arg.startsWith('--suite='))?.split('=')[1] ?? 'all';
if (!['unit', 'integration', 'all'].includes(suite)) throw new Error('Unknown suite: ' + suite);
const isolated = ["test_architecture", "test_player_handling", "test_navigation_budget", "test_physics", "test_rally_handling", "test_resource_cache"];
const scenarios = ["test_shared_vehicle", "test_soundscape", "test_character_asset", "test_rolling_wheels", "test_cargo_selection_order", "test_camp_cooking", "test_trunk", "test_packing", "test_course_schedule", "test_crowd_navigation", "test_run_jump_npc", "test_course_officials", "test_city_physics", "test_vineyard", "test_rally_traffic", "test_demo", "test_mobile", "test_stage_safety_gate", "test_room", "test_food_fleet", "test_foraging", "test_poison_mushrooms", "test_party", "test_selection", "test_vk_access", "test_lobby_ui", "test_minimap", "test_world_loading", "test_network_motion", "test_furniture", "test_spectators", "test_rocks", "test_tow_recovery", "test_woodland", "test_terrain_seams", "test_crew_limit", "test_interaction", "test_drive_prediction", "test_road_surface"];
if (suite !== 'integration') {
  const { readdirSync } = await import('node:fs');
  const files = readdirSync(join(root, 'tests')).filter(name => name.endsWith('.test.mjs')).map(name => join(root, 'tests', name));
  run(process.execPath, ['--test', ...files]);
}
run(godot, ['--headless', '--editor', '--path', project, '--import']);
let scripts = suite === 'unit' ? isolated : suite === 'integration' ? scenarios : [...isolated, ...scenarios];
const from = process.argv.find(arg => arg.startsWith('--from='))?.split('=')[1];
if (from) {
  const index = scripts.indexOf(from);
  if (index < 0) throw new Error('Unknown test: ' + from);
  scripts = scripts.slice(index);
}
const { spawnSync } = await import('node:child_process');
for (const script of scripts) {
  const result = spawnSync(godot, ['--headless', '--path', project, '--script', `res://tests/${script}.gd`], {cwd:root, encoding:'utf8', timeout:180000});
  process.stdout.write(result.stdout ?? '');
  process.stderr.write(result.stderr ?? '');
  if (result.error || result.status !== 0 || /SCRIPT ERROR:/.test((result.stdout ?? '') + (result.stderr ?? ''))) throw new Error(`${script} failed`, {cause:result.error});
}
if (suite !== 'unit') run(process.execPath, [join(root, 'scripts/test-device.mjs')]);
