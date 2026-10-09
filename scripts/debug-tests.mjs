// Temporary CI helper: run selected Godot tests and expose their output as annotations.
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';
import {getGodot, root} from './godot.mjs';
const godot = await getGodot();
const project = join(root, 'game');
const run = (args, timeout = 180000) => spawnSync(godot, args, {cwd: root, encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024});
run(['--headless', '--editor', '--path', project, '--import']);
run(['--headless', '--path', project, '--script', 'res://tools/bake_village.gd']);
const escape = text => text.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
for (const test of process.env.TESTS.split(/\s+/).filter(Boolean)) {
  const result = run(['--headless', '--path', project, '--script', 'res://tests/' + test]);
  const lines = ((result.stdout || '') + '\n' + (result.stderr || '')).split('\n')
    .filter(line => !/^\s*$|Godot Engine v|OpenGL API|^WARNING: .*deprecated/.test(line));
  const keep = lines.filter(line => /FAIL|ERROR|Error|error|RESULT|DEBUG|OVERTAKE|at: /.test(line)).slice(-80);
  const body = keep.join('\n');
  for (let i = 0; i < Math.min(4, Math.ceil(body.length / 5000)); i++)
    console.log(`::warning title=${test} status=${result.status} part ${i + 1}::` + escape(body.slice(i * 5000, (i + 1) * 5000)));
  if (!body) console.log(`::warning title=${test} status=${result.status}::` + escape(lines.slice(-30).join('\n')));
}
