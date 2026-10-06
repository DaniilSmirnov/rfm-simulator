import { join } from 'node:path';
import { getGodot, root, run } from './godot.mjs';
const godot = await getGodot();
const project = join(root, 'game');
run(godot, ['--headless', '--editor', '--path', project, '--import']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_demo.gd']);

run(process.execPath, [join(root, 'scripts/test-device.mjs')]);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_mobile.gd']);

run(process.execPath, ['--test', join(root, 'tests/room-core.test.mjs'), join(root, 'tests/room-session.test.mjs')]);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_room.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_physics.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_food_fleet.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_party.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_selection.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_network_motion.gd']);

run(godot, ['--headless', '--path', project, '--script', 'res://tests/test_furniture.gd']);
