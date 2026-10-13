import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { join } from 'node:path';
import { getGodot, root, run } from './godot.mjs';

// Desktop exports for Steam. Usage: node scripts/build-desktop.mjs --platform=macos
// The official 4.4.1 export templates are downloaded once into .cache/templates and
// checked against a pinned SHA-256; only the one platform archive is unpacked.
const platforms = {
  macos: { preset: 'macOS', template: 'macos.zip', output: 'Rally Fans Simulator.zip', patch: macosPatch },
};
const name = process.argv.find(arg => arg.startsWith('--platform='))?.split('=')[1] ?? 'macos';
const platform = platforms[name];
if (!platform) throw new Error('Unknown desktop platform: ' + name);
const version = JSON.parse(await readFile(join(root, 'package.json'), 'utf8')).version;
const tpzSha = '7a8d14ade489fd4d22f178193021fe8a876a9e51068ed4dde26dac3ae4c59a88';
const tpzUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz';
const cache = join(root, '.cache', 'templates');

function sha256(path) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    createReadStream(path).on('data', chunk => hash.update(chunk)).on('end', () => resolve(hash.digest('hex'))).on('error', reject);
  });
}

async function exists(path) { try { await stat(path); return true; } catch { return false; } }

async function getTemplate() {
  const target = join(cache, `${name}-4.4.1.zip`);
  if (await exists(target)) return target;
  await mkdir(cache, { recursive: true });
  const archive = join(cache, 'templates.tpz');
  if (!await exists(archive)) {
    const response = await fetch(tpzUrl);
    if (!response.ok) throw new Error(`Template download failed: ${response.status}`);
    const { Readable } = await import('node:stream');
    const { pipeline } = await import('node:stream/promises');
    const { createWriteStream } = await import('node:fs');
    await pipeline(Readable.fromWeb(response.body), createWriteStream(archive));
  }
  if (await sha256(archive) !== tpzSha) throw new Error('Export templates failed their SHA-256 check.');
  run('python3', ['-c', 'import zipfile,sys; open(sys.argv[3],"wb").write(zipfile.ZipFile(sys.argv[1]).read("templates/"+sys.argv[2]))', archive, platform.template, target]);
  return target;
}

function macosPatch(preset) {
  return preset
    .replaceAll('application/short_version="0.10.29"', `application/short_version=${JSON.stringify(version)}`)
    .replaceAll('application/version="0.10.29"', `application/version=${JSON.stringify(version)}`);
}

const godot = await getGodot();
const template = await getTemplate();
const project = join(root, '.cache', 'export-project-' + name);
const output = join(root, 'dist-' + name);
await rm(project, { recursive: true, force: true });
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(join(root, 'game'), project, { recursive: true, filter: path => !path.split(/[\\/]/).includes('.godot') });
const presetPath = join(project, 'export_presets.cfg');
let preset = await readFile(presetPath, 'utf8');
// The preset block for this platform is edited in place; the template path is local to the build machine.
const block = preset.indexOf(`name="${platform.preset}"`);
if (block < 0) throw new Error(`Export preset ${platform.preset} is missing.`);
for (const kind of ['debug', 'release']) {
  const marker = `custom_template/${kind}=""`;
  const at = preset.indexOf(marker, block);
  if (at < 0) throw new Error('Unexpected export preset.');
  preset = preset.slice(0, at) + `custom_template/${kind}=${JSON.stringify(template)}` + preset.slice(at + marker.length);
}
await writeFile(presetPath, platform.patch(preset));
// Apple Silicon needs ETC2/ASTC textures; the Web project does not, so only this copy enables them.
const settingsPath = join(project, 'project.godot');
const settings = await readFile(settingsPath, 'utf8');
if (!settings.includes('\n[rendering]\n')) throw new Error('Unexpected project settings.');
await writeFile(settingsPath, settings.replace('\n[rendering]\n', '\n[rendering]\n\ntextures/vram_compression/import_etc2_astc=true\n'));
// Same generated scenes as the Web build: village and rally tracks are baked before export.
run(godot, ['--headless', '--editor', '--path', project, '--import']);
run(godot, ['--headless', '--path', project, '--script', 'res://tools/bake_rally_tracks.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tools/bake_village.gd']);
run(godot, ['--headless', '--path', project, '--export-release', platform.preset, join(output, platform.output)]);
const size = (await stat(join(output, platform.output))).size;
if (size < 1024 * 1024) throw new Error('Exported archive is suspiciously small.');
console.log(`${platform.preset} ready: ${join(output, platform.output)} (${(size / 1048576).toFixed(1)} MiB).`);
