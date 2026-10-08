import { join } from 'node:path';
import { getGodot, root, run } from './godot.mjs';
const godot = await getGodot();
const project = join(root, 'game');
run(process.execPath, ['--test',
  join(root,'tests/platform.test.mjs'),
  join(root,'tests/auth-vk.test.mjs'),
  join(root,'tests/payments-vk.test.mjs'),
  join(root,'tests/store.test.mjs'),
  join(root,'tests/deploy-cloudflare.test.mjs'),
  join(root,'tests/fullscreen.test.mjs'),
  join(root,'tests/mobile-viewport.test.mjs'),
]);
run(process.execPath, ['--test', join(root, 'tests/branding.test.mjs'), join(root, 'tests/boot-diagnostics.test.mjs'), join(root, 'tests/audio-recovery.test.mjs')]);
run(godot, ['--headless', '--editor', '--path', project, '--import']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_character_asset.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_player_handling.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_cargo_selection_order.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_camp_cooking.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_trunk.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_packing.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_course_schedule.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_crowd_navigation.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_run_jump_npc.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_course_officials.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_city_physics.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_vineyard.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_rally_handling.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_rally_traffic.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_demo.gd']);

run(process.execPath, [join(root, 'scripts/test-device.mjs')]);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_mobile.gd']);

run(process.execPath, ['--test', join(root, 'tests/room-core.test.mjs'), join(root, 'tests/room-session.test.mjs')]);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_room.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_physics.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_food_fleet.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_foraging.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_poison_mushrooms.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_party.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_selection.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_vk_access.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_lobby_ui.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_resource_cache.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_world_loading.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_network_motion.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_furniture.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_spectators.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_rocks.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_tow_recovery.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_woodland.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_crew_limit.gd']);


run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_interaction.gd']);


run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_drive_prediction.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_soundscape.gd']);
