import { cp, mkdir, readFile, readdir, rm, stat, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';
import { checkTemplate, getGodot, root, run } from './godot.mjs';

const version = JSON.parse(await readFile(join(root, 'package.json'), 'utf8')).version;
const target = process.argv.find(arg => arg.startsWith('--target='))?.split('=')[1] ?? 'standalone';
if (!['standalone','vk','vk-prototype'].includes(target)) throw new Error('Unknown build target: ' + target);
const platformFiles = target === 'vk' ? ['vk-bridge.js','platform/vk.js','platform/transport.js'] : [`platform/${target}.js`,'platform/transport.js'];
const godot = await getGodot();
const template = await checkTemplate();
const project = join(root, '.cache', target === 'standalone' ? 'export-project' : 'export-project-' + target);
const output = join(root, target === 'standalone' ? 'dist' : target === 'vk' ? 'dist-vk' : 'dist-vk-prototype');
const rawOutput = join(root, '.cache', target === 'standalone' ? 'web-raw' : 'web-raw-' + target);
await rm(project, { recursive: true, force: true });
await rm(rawOutput, { recursive: true, force: true });
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await mkdir(rawOutput, { recursive: true });
await cp(join(root, 'game'), project, {
  recursive: true,
  filter: path => !path.split(/[\\/]/).includes('.godot'),
});
const presetPath = join(project, 'export_presets.cfg');
const preset = await readFile(presetPath, 'utf8');
if (!preset.includes('custom_template/release=""')) throw new Error('Unexpected export preset.');
await writeFile(presetPath, preset.replace('custom_features=""', 'custom_features="' + (target === 'vk' ? 'vk' : '') + '"').replace('custom_template/release=""', `custom_template/release=${JSON.stringify(template)}`));
// Import source assets, then generate the spatially partitioned village scene.
run(godot, ['--headless', '--editor', '--path', project, '--import']);
run(godot, ['--headless', '--path', project, '--script', 'res://tools/bake_village.gd']);
run(godot, ['--headless', '--path', project, '--export-release', 'Web', join(rawOutput, 'index.html')]);
await cp(rawOutput, output, {
  recursive: true,
  filter: path => !['index.wasm', 'index.js', 'index.html'].includes(path.split(/[\\/]/).at(-1)),
});

const wasmPath = join(rawOutput, 'index.wasm');
const wasm = await readFile(wasmPath);
if (!WebAssembly.validate(wasm)) throw new Error('Exported WebAssembly is invalid.');
const packed = gzipSync(wasm, { level: 9 });
await writeFile(join(output, 'index.wasm.gz'), packed);
const pck = await readFile(join(output, 'index.pck'));
if (pck.subarray(0, 4).toString() !== 'GDPC') throw new Error('Missing or invalid Godot pack.');

const jsPath = join(output, 'index.js');
const js = await readFile(join(rawOutput, 'index.js'), 'utf8');
const needle = 'return fetch(file).then(function (response) {';
if (js.split(needle).length !== 2) throw new Error('Unexpected Godot preloader version.');
await writeFile(jsPath, js.replace(needle, 'return RallyMini.fetch(file).then(function (response) {'));
const htmlPath = join(output, 'index.html');
const html = await readFile(join(rawOutput, 'index.html'), 'utf8');
if (!html.includes('const engine = new Engine(GODOT_CONFIG);')) throw new Error('Unexpected HTML engine config.');
await cp(join(root, 'game/branding/rfm-icon.svg'), join(output, 'favicon.svg'));
const platformScripts = platformFiles.map(name => `<script src="${name}"></script>`).join('\n');
const brandedHtml = html.replaceAll('$RFM_VERSION', version).replace(/<link\b[^>]*\brel=["'](?:shortcut )?icon["'][^>]*>/gi, '')
  .replace('</head>', '<meta name="rally-platform" content="' + target + '">\n<link rel="icon" type="image/svg+xml" href="favicon.svg">\n</head>');
await writeFile(htmlPath, brandedHtml.replace('engine.startGame({ onProgress: loadingProgress })', 'Promise.resolve().then(() => RallyPlatform.ready()).then(() => engine.startGame({ onProgress: loadingProgress }))').replace('<script src="index.js"></script>', '<script src="boot-diagnostics.js"></script>\n<script src="mini-loader.js"></script>\n<script src="audio-recovery.js"></script>\n<script src="mobile-device.js"></script>\n<script src="mobile-viewport.js"></script>\n<script src="fullscreen.js"></script>\n<script src="room-session.js"></script>\n' + platformScripts + '\n<script src="index.js"></script>').replace('const engine = new Engine(GODOT_CONFIG);', 'RallyDevice.configure(GODOT_CONFIG);\nconst engine = new Engine(GODOT_CONFIG);'));
await cp(join(root, 'web'), output, { recursive: true, filter:path => !path.split(/[\\/]/).includes('platform') });
await mkdir(join(output,'platform'), {recursive:true});
for (const name of platformFiles.filter(name => name.startsWith('platform/'))) await cp(join(root,'web',name),join(output,name));
if (target === 'vk') await cp(join(root,'node_modules/@vkontakte/vk-bridge/dist/browser.min.js'),join(output,'vk-bridge.js'));
await mkdir(join(output, 'licenses'), { recursive: true });
if (target === 'vk') await cp(join(root,'node_modules/@vkontakte/vk-bridge/LICENSE'),join(output,'licenses/VK_BRIDGE_LICENSE.txt'));
for (const name of ['GODOT_LICENSE.txt', 'GODOT_COPYRIGHT.txt']) {
  await cp(join(root, 'engine', name), join(output, 'licenses', name));
}
await cp(join(root, 'LICENSE'), join(output, 'licenses', 'GAME_LICENSE.txt'));
for (const entry of await readdir(output, { recursive: true, withFileTypes: true })) {
  if (!entry.isFile()) continue;
  const size = (await stat(join(entry.parentPath, entry.name))).size;
  if (size >= 25 * 1024 * 1024) throw new Error(`${entry.name} exceeds Cloudflare's asset limit.`);
}
console.log(`Web ready: WASM ${(packed.length / 1048576).toFixed(2)} MiB compressed, ${(wasm.length / 1048576).toFixed(2)} MiB decoded.`);
