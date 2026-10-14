import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { getGodot, root, run } from './godot.mjs';

// Native exports (Steam desktop, Android, iOS Xcode project). Usage:
//   node scripts/build-desktop.mjs --platform=macos|linux|windows|android|ios
// The official 4.4.1 export templates are downloaded once into .cache/templates and
// checked against a pinned SHA-256; only the one platform archive is unpacked.
// Linux and Windows export the executable next to its .pck, the usual layout of a Steam depot.
// iOS exports an unsigned Xcode project (export_project_only) for CI and local signing.
const platforms = {
  macos: { preset: 'macOS', template: 'macos.zip', output: 'Rally Fans Simulator.zip', patch: macosPatch, mobileTextures: true },
  linux: { preset: 'Linux', template: 'linux_release.x86_64', output: 'RallyFansSimulator.x86_64', pck: 'RallyFansSimulator.pck', patch: preset => preset },
  windows: { preset: 'Windows', template: 'windows_release_x86_64.exe', output: 'Rally Fans Simulator.exe', pck: 'Rally Fans Simulator.pck', patch: windowsPatch, prepare: prepareWindows },
  android: { preset: 'Android', template: 'android_release.apk', output: 'Rally Fans Simulator.apk', patch: androidPatch, prepare: prepareAndroid, mobileTextures: true },
  ios: { preset: 'iOS', template: 'ios.zip', output: 'RallyFansSimulator', archive: 'RallyFansSimulator-ios-xcode.zip', patch: iosPatch, prepare: prepareIos, mobileTextures: true, directory: true },
};
const name = process.argv.find(arg => arg.startsWith('--platform='))?.split('=')[1] ?? 'macos';
const platform = platforms[name];
if (!platform) throw new Error('Unknown native platform: ' + name);
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
  const target = join(cache, `4.4.1-${platform.template}`);
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

function iosPatch(preset) {
  return preset
    .replaceAll('application/short_version="0.10.29"', `application/short_version=${JSON.stringify(version)}`)
    .replaceAll('application/version="0.10.29"', `application/version=${JSON.stringify(version)}`);
}

// Export method enum in Godot: App Store=0, Development=1, Ad-Hoc=2, Enterprise=3.
function iosExportMethod() {
  const name = (process.env.IOS_EXPORT_METHOD || 'app-store').toLowerCase().replace(/_/g, '-');
  return ({ 'app-store': 0, development: 1, 'ad-hoc': 2, enterprise: 3 })[name] ?? 0;
}

function iosSigningSecrets() {
  const keys = ['IOS_CERTIFICATE_BASE64', 'IOS_CERTIFICATE_PASSWORD', 'IOS_PROVISIONING_PROFILE_BASE64', 'IOS_TEAM_ID'];
  const present = keys.filter(key => process.env[key]);
  if (present.length === 0) return null;
  if (present.length !== keys.length) {
    throw new Error(`Partial iOS signing secrets: set all of ${keys.join(', ')} (missing ${keys.filter(k => !process.env[k]).join(', ')}).`);
  }
  return {
    certificate: process.env.IOS_CERTIFICATE_BASE64,
    password: process.env.IOS_CERTIFICATE_PASSWORD,
    profile: process.env.IOS_PROVISIONING_PROFILE_BASE64,
    teamId: process.env.IOS_TEAM_ID,
    identity: process.env.IOS_CODE_SIGN_IDENTITY || 'iPhone Distribution',
  };
}

// Install the distribution certificate and provisioning profile into a temporary keychain,
// then point the Godot preset at them so export produces a signed .ipa.
async function prepareIos() {
  if (process.platform !== 'darwin') {
    throw new Error('iOS export requires macOS with Xcode. Run this job on a macos-* GitHub runner.');
  }
  const xcode = spawnSync('xcodebuild', ['-version'], { encoding: 'utf8' });
  if (xcode.status !== 0) throw new Error('xcodebuild is missing. Install Xcode and accept the license.');
  const secrets = iosSigningSecrets();
  if (!secrets) {
    return `Xcode project only (unsigned). Set IOS_CERTIFICATE_BASE64, IOS_CERTIFICATE_PASSWORD, IOS_PROVISIONING_PROFILE_BASE64 and IOS_TEAM_ID for a signed IPA. ${xcode.stdout.trim().split('\n')[0]}.`;
  }

  const dir = join(root, '.cache', 'ios-signing');
  await mkdir(dir, { recursive: true });
  const certPath = join(dir, 'certificate.p12');
  const profilePath = join(dir, 'profile.mobileprovision');
  await writeFile(certPath, Buffer.from(secrets.certificate, 'base64'));
  await writeFile(profilePath, Buffer.from(secrets.profile, 'base64'));

  const keychain = join(dir, 'signing.keychain-db');
  const keychainPassword = 'rfm-ios-ci';
  for (const args of [
    ['delete-keychain', keychain],
    ['create-keychain', '-p', keychainPassword, keychain],
    ['set-keychain-settings', '-lut', '21600', keychain],
    ['unlock-keychain', '-p', keychainPassword, keychain],
    ['import', certPath, '-P', secrets.password, '-A', '-t', 'cert', '-f', 'pkcs12', '-k', keychain],
    ['set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', keychainPassword, keychain],
  ]) {
    // delete-keychain fails when the keychain does not exist yet; ignore that.
    const result = spawnSync('security', args, { encoding: 'utf8' });
    if (result.status !== 0 && args[0] !== 'delete-keychain') {
      throw new Error(`security ${args[0]} failed: ${(result.stderr || result.stdout || '').trim()}`);
    }
  }
  const listed = spawnSync('security', ['list-keychain', '-d', 'user'], { encoding: 'utf8' });
  const existing = (listed.stdout || '').split('\n').map(line => line.trim().replace(/^"|"$/g, '')).filter(Boolean);
  spawnSync('security', ['list-keychain', '-d', 'user', '-s', keychain, ...existing], { stdio: 'inherit' });

  // UUID is embedded in the profile plist.
  const decoded = spawnSync('security', ['cms', '-D', '-i', profilePath], { encoding: 'utf8' });
  if (decoded.status !== 0) throw new Error('Failed to decode the provisioning profile.');
  const uuidMatch = decoded.stdout.match(/<key>UUID<\/key>\s*<string>([^<]+)<\/string>/);
  if (!uuidMatch) throw new Error('Provisioning profile has no UUID.');
  const profileUuid = uuidMatch[1];
  const profilesDir = join(homedir(), 'Library', 'MobileDevice', 'Provisioning Profiles');
  await mkdir(profilesDir, { recursive: true });
  await writeFile(join(profilesDir, `${profileUuid}.mobileprovision`), await readFile(profilePath));

  // prepare runs after the preset is written: rewrite signing fields and switch to IPA output.
  const presetPath = join(root, '.cache', 'export-project-' + name, 'export_presets.cfg');
  let preset = await readFile(presetPath, 'utf8');
  const replacements = [
    ['application/app_store_team_id=""', `application/app_store_team_id=${JSON.stringify(secrets.teamId)}`],
    ['application/export_project_only=true', 'application/export_project_only=false'],
    ['application/code_sign_identity_release=""', `application/code_sign_identity_release=${JSON.stringify(secrets.identity)}`],
    ['application/provisioning_profile_uuid_release=""', `application/provisioning_profile_uuid_release=${JSON.stringify(profileUuid)}`],
    ['application/export_method_release=1', `application/export_method_release=${iosExportMethod()}`],
  ];
  for (const [from, to] of replacements) {
    if (!preset.includes(from)) throw new Error(`iOS preset marker missing: ${from}`);
    preset = preset.replace(from, to);
  }
  await writeFile(presetPath, preset);

  platform.directory = false;
  platform.output = 'Rally Fans Simulator.ipa';
  return `Signed IPA (${secrets.identity}, team ${secrets.teamId}, profile ${profileUuid}).`;
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
run(godot, ['--headless', '--path', project, '--export-release', platform.preset, join(output, platform.output)], { timeout: 600000 });
const product = join(output, platform.output);
if (platform.directory) {
  // iOS writes an Xcode project tree; pack it so the CI artifact is a single file.
  const { readdir } = await import('node:fs/promises');
  const entries = await readdir(product).catch(() => []);
  if (!entries.length) throw new Error('iOS export produced an empty directory.');
  const archive = join(output, platform.archive);
  run('python3', ['-c', 'import shutil,sys; shutil.make_archive(sys.argv[2].removesuffix(".zip"), "zip", sys.argv[1])', product, archive]);
  const size = (await stat(archive)).size;
  if (size < 1024 * 1024) throw new Error('Exported iOS project archive is suspiciously small.');
  console.log(`${platform.preset} ready: ${archive} (${(size / 1048576).toFixed(1)} MiB). ${note}`);
} else {
  const size = (await stat(product)).size;
  if (size < 1024 * 1024) throw new Error('Exported archive is suspiciously small.');
  if (platform.pck && (await stat(join(output, platform.pck))).size < 1024 * 1024) throw new Error('Exported game data (.pck) is suspiciously small.');
  console.log(`${platform.preset} ready: ${product} (${(size / 1048576).toFixed(1)} MiB). ${note}`);
}
