import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { verifyWindowsBuild } from './verify-windows-build.mjs';
import { getGodot, root, run } from './godot.mjs';

// Native exports (Steam desktop, Android). Usage: node scripts/build-desktop.mjs --platform=macos|linux|windows|android
// The official 4.4.1 export templates are downloaded once into .cache/templates and
// checked against a pinned SHA-256; only the selected platform templates are unpacked.
// Linux exports a separate .pck; Windows embeds all game data into each executable.
const platforms = {
  macos: { preset: 'macOS', template: 'macos.zip', output: 'Rally Fans Simulator.zip', patch: macosPatch, mobileTextures: true },
  linux: { preset: 'Linux', template: 'linux_release.x86_64', output: 'RallyFansSimulator.x86_64', pck: 'RallyFansSimulator.pck', patch: preset => preset },
  windows: { targets: [
    { preset: 'Windows x86', template: 'windows_release_x86_32.exe', output: 'Rally_Fans_Simulator_x86.exe' },
    { preset: 'Windows x64', template: 'windows_release_x86_64.exe', output: 'Rally_Fans_Simulator_x64.exe' },
  ], patch: windowsPatch, prepare: prepareWindows },
  android: { preset: 'Android', template: 'android_release.apk', output: 'Rally Fans Simulator.apk', patch: androidPatch, prepare: prepareAndroid, mobileTextures: true },
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

async function getTemplate(filename) {
  const target = join(cache, `4.4.1-${filename}`);
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
  run('python3', ['-c', 'import zipfile,sys; open(sys.argv[3],"wb").write(zipfile.ZipFile(sys.argv[1]).read("templates/"+sys.argv[2]))', archive, filename, target]);
  return target;
}

function macosPatch(preset) {
  return preset
    .replaceAll('application/short_version="0.10.29"', `application/short_version=${JSON.stringify(version)}`)
    .replaceAll('application/version="0.10.29"', `application/version=${JSON.stringify(version)}`);
}

// Windows file properties need four numeric parts: 0.10.29 -> 0.10.29.0.
function windowsPatch(preset) {
  return preset
    .replaceAll('application/file_version="0.10.29.0"', `application/file_version=${JSON.stringify(version + '.0')}`)
    .replaceAll('application/product_version="0.10.29.0"', `application/product_version=${JSON.stringify(version + '.0')}`);
}

// 0.10.29 -> versionCode 10029; Google Play and RuStore need it to grow with every release.
function androidPatch(preset) {
  const [major = 0, minor = 0, patch = 0] = version.split('.').map(Number);
  return preset
    .replaceAll('version/code=1', `version/code=${major * 1000000 + minor * 1000 + patch}`)
    .replaceAll('version/name="0.10.29"', `version/name=${JSON.stringify(version)}`);
}

// Godot reads the SDK and JDK locations from its editor settings, not from the preset.
async function setEditorSetting(key, value) {
  const config = process.env.XDG_CONFIG_HOME || join(homedir(), '.config');
  const file = join(config, 'godot', 'editor_settings-4.4.tres');
  let text = await exists(file) ? await readFile(file, 'utf8') : '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n';
  const line = `${key} = ${JSON.stringify(value)}`;
  const pattern = new RegExp(`^${key} = .*$`, 'm');
  text = pattern.test(text) ? text.replace(pattern, line) : text.replace('[resource]\n', `[resource]\n${line}\n`);
  await mkdir(join(config, 'godot'), { recursive: true });
  await writeFile(file, text);
}

// Release signing comes from the environment (GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD);
// without it a throwaway key is made so that the APK still installs, but it cannot go to a store.
async function prepareAndroid() {
  const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (!sdk || !await exists(join(sdk, 'build-tools'))) throw new Error('Set ANDROID_HOME to an Android SDK with build-tools 34, platform 34 and cmdline-tools.');
  const java = process.env.JAVA_HOME;
  if (!java) throw new Error('Set JAVA_HOME to JDK 17 or newer.');
  await setEditorSetting('export/android/android_sdk_path', sdk);
  await setEditorSetting('export/android/java_sdk_path', java);
  if (process.env.GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
    for (const key of ['USER', 'PASSWORD']) if (!process.env[`GODOT_ANDROID_KEYSTORE_RELEASE_${key}`]) throw new Error(`GODOT_ANDROID_KEYSTORE_RELEASE_${key} is missing.`);
    return 'Signed with the release keystore.';
  }
  const keystore = join(root, '.cache', 'android', 'throwaway.keystore');
  await mkdir(join(root, '.cache', 'android'), { recursive: true });
  if (!await exists(keystore)) {
    const made = spawnSync(join(java, 'bin', 'keytool'), ['-genkeypair', '-keystore', keystore, '-alias', 'rfm', '-storepass', 'throwaway', '-keypass', 'throwaway', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=Rally Fans Simulator test build'], { stdio: 'inherit' });
    if (made.status !== 0) throw new Error('keytool failed to make a test keystore.');
  }
  process.env.GODOT_ANDROID_KEYSTORE_RELEASE_PATH = keystore;
  process.env.GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'rfm';
  process.env.GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = 'throwaway';
  return 'WARNING: signed with a throwaway key. Set GODOT_ANDROID_KEYSTORE_RELEASE_* for a store release.';
}

// The exe icon and file properties are written by rcedit, which runs under Wine on Linux.
// Without Wine the build still works but keeps the stock Godot icon and properties.
const rceditSha = '3e7801db1a5edbec91b49a24a094aad776cb4515488ea5a4ca2289c400eade2a';
async function prepareWindows() {
  const wine = spawnSync('sh', ['-c', 'command -v wine'], { encoding: 'utf8' }).stdout.trim();
  if (!wine) return 'WARNING: Wine not found, so the exe keeps the stock Godot icon and file properties.';
  const rcedit = join(root, '.cache', 'rcedit-x64-2.0.0.exe');
  if (!await exists(rcedit)) {
    const response = await fetch('https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe');
    if (!response.ok) throw new Error(`rcedit download failed: ${response.status}`);
    await writeFile(rcedit, Buffer.from(await response.arrayBuffer()));
  }
  if (await sha256(rcedit) !== rceditSha) throw new Error('rcedit failed its SHA-256 check.');
  await setEditorSetting('export/windows/rcedit', rcedit);
  await setEditorSetting('export/windows/wine', wine);
  return 'Icon and file properties set with rcedit.';
}

const godot = await getGodot();
const targets = platform.targets ?? [platform];
const templates = [];
for (const target of targets) templates.push(await getTemplate(target.template));
const project = join(root, '.cache', 'export-project-' + name);
const output = join(root, 'dist-' + name);
await rm(project, { recursive: true, force: true });
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(join(root, 'game'), project, { recursive: true, filter: path => !path.split(/[\\/]/).includes('.godot') });
const presetPath = join(project, 'export_presets.cfg');
let preset = await readFile(presetPath, 'utf8');
// Patch each complete preset independently so the two architectures never share templates.
for (const [index, target] of targets.entries()) {
  const pattern = /\[preset\.(\d+)\]\r?\n[\s\S]*?(?=\[preset\.\d+\]\r?\n|$)/g;
  let found = false;
  preset = preset.replace(pattern, section => {
    if (!section.includes(`name="${target.preset}"`)) return section;
    found = true;
    for (const kind of ['debug', 'release']) {
      const marker = `custom_template/${kind}=""`;
      if (!section.includes(marker)) throw new Error('Unexpected export preset.');
      section = section.replace(marker, `custom_template/${kind}=${JSON.stringify(templates[index])}`);
    }
    return platform.patch(section);
  });
  if (!found) throw new Error(`Export preset ${target.preset} is missing.`);
}
await writeFile(presetPath, preset);
// Apple Silicon and Android need ETC2/ASTC textures; the Web and PC builds do not, so only those copies enable them.
if (platform.mobileTextures) {
  const settingsPath = join(project, 'project.godot');
  const settings = await readFile(settingsPath, 'utf8');
  if (!settings.includes('\n[rendering]\n')) throw new Error('Unexpected project settings.');
  await writeFile(settingsPath, settings.replace('\n[rendering]\n', '\n[rendering]\n\ntextures/vram_compression/import_etc2_astc=true\n'));
}
// Same generated scenes as the Web build: village and rally tracks are baked before export.
run(godot, ['--headless', '--editor', '--path', project, '--import']);
const note = platform.prepare ? await platform.prepare() : '';
run(godot, ['--headless', '--path', project, '--script', 'res://tools/bake/bake_rally_tracks.gd']);
run(godot, ['--headless', '--path', project, '--script', 'res://tools/bake/bake_village.gd']);
for (const target of targets) {
  run(godot, ['--headless', '--path', project, '--export-release', target.preset, join(output, target.output)]);
  const size = (await stat(join(output, target.output))).size;
  if (size < 1024 * 1024) throw new Error('Exported archive is suspiciously small.');
  if (target.pck && (await stat(join(output, target.pck))).size < 1024 * 1024) throw new Error('Exported game data (.pck) is suspiciously small.');
  console.log(`${target.preset} ready: ${join(output, target.output)} (${(size / 1048576).toFixed(1)} MiB). ${note}`);
}
if (name === 'windows') await verifyWindowsBuild(output);
