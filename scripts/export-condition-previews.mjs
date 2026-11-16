// Stage card previews under every time of day and weather: runs each preview
// tool with `--conditions` (game/tools/screenshots/condition_previews.gd), which
// re-renders the card's camera for night and for rain or snow and fog and writes
// game/textures/previews/conditions/stage_<N>_<time>_<weather>.webp.
// Needs a real renderer: on Linux without a display it runs under xvfb-run.
//   node scripts/export-condition-previews.mjs [stage-id ...]
import { readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { getGodot, root, run } from './godot.mjs';

// The tool that frames each stage's card; forest and provence share the menu tool.
const TOOLS = [
  ['forest', 'export_menu_previews.gd', ['--stage-ids=forest']],
  ['winter', 'export_winter_screenshots.gd'],
  ['provence', 'export_menu_previews.gd', ['--stage-ids=provence']],
  ['canyon', 'export_canyon_screenshots.gd'],
  ['lakes', 'export_finnish_forest_screenshots.gd'],
  ['mineshaft', 'export_mineshaft_screenshots.gd'],
  ['sever', 'export_sever_screenshots.gd'],
  ['quarry', 'export_quarry_screenshots.gd'],
];

const wanted = process.argv.slice(2);
const godot = await getGodot();
const headless = process.platform === 'linux' && !process.env.DISPLAY;
for (const [id, tool, extra = []] of TOOLS) {
  if (wanted.length && !wanted.includes(id)) continue;
  const args = ['--path', 'game', '--rendering-driver', 'opengl3', '--script', `res://tools/screenshots/${tool}`, '--', '--conditions', ...extra];
  console.log(`[conditions] ${id}: ${tool}`);
  if (headless) run('xvfb-run', ['-a', '-s', '-screen 0 1280x720x24', godot, ...args], { timeout: 900000 });
  else run(godot, args, { timeout: 900000 });
}
const files = (await readdir(join(root, 'game/textures/previews/conditions'))).filter((name) => name.endsWith('.webp'));
console.log(`[conditions] ${files.length} previews in game/textures/previews/conditions`);
