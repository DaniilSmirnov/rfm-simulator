#!/usr/bin/env node
// Builds the native radio extension (native/voice) for one platform into
// game/addons/rally_voice/bin. Exports carry the library inside the pack as a
// plain file (include_filter in export_presets.cfg); voice_native.gd copies it
// to user:// and loads it on the first radio join, so Windows stays a single
// exe and platforms without the library start without extension errors.
//
//   node scripts/build-voice.mjs --target=linux-x86_64
//   node scripts/build-voice.mjs --target=windows-x86_64   (MinGW cross build)
//   node scripts/build-voice.mjs --target=macos-universal  (on macOS)
//   node scripts/build-voice.mjs --target=android-arm64    (ANDROID_NDK_ROOT)
//   node scripts/build-voice.mjs --target=ios-arm64        (on macOS with Xcode)
//   node scripts/build-voice.mjs --install                 list installed libraries
//
// Sources are pinned in native/voice/deps.json and cached in .cache/voice.
// Mbed TLS (with DTLS-SRTP) and Opus are built static into a per-target
// prefix first, then libdatachannel and godot-cpp are compiled into the
// extension itself, so the game ships one library per platform.
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, copyFileSync, readdirSync, writeFileSync} from 'node:fs';
import {join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const deps = JSON.parse(readFileSync(join(root, 'native/voice/deps.json'), 'utf8'));
const cache = join(root, '.cache/voice');
const addon = join(root, 'game/addons/rally_voice');
const arg = name => process.argv.find(a => a.startsWith(`--${name}=`))?.split('=')[1];

export const TARGETS = {
  'linux-x86_64': {suffix: 'linux.x86_64', ext: 'so', args: []},
  'windows-x86_64': {suffix: 'windows.x86_64', ext: 'dll', mingw: 'x86_64-w64-mingw32'},
  'windows-x86_32': {suffix: 'windows.x86_32', ext: 'dll', mingw: 'i686-w64-mingw32'},
  'macos-universal': {suffix: 'macos.universal', ext: 'dylib', args: ['-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15'],
    // One configure for two architectures: Opus cannot pick SSE and NEON at once.
    opus: ['-DOPUS_DISABLE_INTRINSICS=ON']},
  'android-arm64': {suffix: 'android.arm64', ext: 'so', abi: 'arm64-v8a'},
  'android-arm32': {suffix: 'android.arm32', ext: 'so', abi: 'armeabi-v7a'},
  // The iOS export embeds this dylib in the app as a framework (see build-desktop.mjs).
  'ios-arm64': {suffix: 'ios.arm64', ext: 'dylib', sdk: 'iphoneos', args: ['-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0']},
};

function run(command, args, cwd = root) {
  console.log('$', command, args.join(' '));
  const result = spawnSync(command, args, {cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024});
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
  process.stdout.write(output);
  if (result.status !== 0) {
    // CI logs are not always at hand: surface the cause as an annotation.
    if (process.env.GITHUB_ACTIONS) {
      const lines = output.split('\n');
      const relevant = lines.filter(l => /error|Error|undefined reference|not found|No such|FAILED/.test(l)).slice(-30);
      const text = [`$ ${command} ${args.slice(0, 6).join(' ')}`, ...(relevant.length ? relevant : lines.slice(-30))].join('\n').slice(-6000);
      console.log(`::error title=build-voice ${command} failed::${text.replace(/%/g, '%25').replace(/\r/g, '').replace(/\n/g, '%0A')}`);
    }
    throw new Error(`${command} failed (${result.status ?? result.error?.message})`);
  }
}

function fetchSources() {
  mkdirSync(cache, {recursive: true});
  for (const [name, dep] of Object.entries(deps.sources)) {
    const dir = join(cache, name);
    if (existsSync(join(dir, '.git'))) continue;
    run('git', ['clone', '--depth', '1', '--branch', dep.ref, ...(dep.submodules ? ['--recurse-submodules', '--shallow-submodules'] : []), dep.url, dir]);
  }
  // libdatachannel needs DTLS-SRTP from Mbed TLS; set it in the config header
  // itself so every consumer of the headers sees the same structures.
  run('python3', [join(cache, 'mbedtls/scripts/config.py'), '-f', join(cache, 'mbedtls/include/mbedtls/mbedtls_config.h'), 'set', 'MBEDTLS_SSL_DTLS_SRTP']);
}

function toolchain(target, prefix) {
  const t = TARGETS[target];
  // CMake 4 refuses plog's and usrsctp's cmake_minimum_required below 3.5.
  const args = ['-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5', ...(t.args || [])];
  if (t.mingw) {
    // The posix thread model provides std::thread/std::mutex for libdatachannel.
    const posix = suffix => existsSync(`/usr/bin/${t.mingw}-${suffix}-posix`) ? `${t.mingw}-${suffix}-posix` : `${t.mingw}-${suffix}`;
    args.push('-DCMAKE_SYSTEM_NAME=Windows', `-DCMAKE_C_COMPILER=${posix('gcc')}`, `-DCMAKE_CXX_COMPILER=${posix('g++')}`,
      `-DCMAKE_RC_COMPILER=${t.mingw}-windres`, `-DCMAKE_FIND_ROOT_PATH=/usr/${t.mingw};${prefix}`,
      '-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER', '-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY', '-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY',
      '-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH');
  }
  if (t.sdk) {
    // godot-cpp's macos.cmake resets CMAKE_OSX_SYSROOT to $SDKROOT and requires Cocoa,
    // which the iOS SDK lacks; it only links Cocoa for macOS, so point it anywhere.
    const sdk = spawnSync('xcrun', ['--sdk', t.sdk, '--show-sdk-path'], {encoding: 'utf8'}).stdout.trim();
    if (!sdk) throw new Error(`xcrun found no ${t.sdk} SDK. Install Xcode.`);
    process.env.SDKROOT = sdk;
    args.push(`-DCMAKE_OSX_SYSROOT=${sdk}`, `-DCOCOA_LIBRARY=${sdk}/System/Library/Frameworks/Foundation.framework`);
  }
  if (t.abi) {
    const ndk = process.env.ANDROID_NDK_ROOT || process.env.ANDROID_NDK_LATEST_HOME || process.env.ANDROID_NDK_HOME || process.env.ANDROID_NDK;
    if (!ndk) throw new Error('Set ANDROID_NDK_ROOT for Android builds.');
    args.push(`-DCMAKE_TOOLCHAIN_FILE=${join(ndk, 'build/cmake/android.toolchain.cmake')}`, `-DANDROID_ABI=${t.abi}`, '-DANDROID_PLATFORM=android-24', '-DANDROID_STL=c++_static',
      // The NDK confines find_*() to its sysroot; our prefix lives outside it.
      `-DCMAKE_FIND_ROOT_PATH=${prefix}`, '-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH', '-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH', '-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH');
  }
  return args;
}

function cmakeProject(source, build, prefix, args) {
  run('cmake', ['-S', source, '-B', build, `-DCMAKE_INSTALL_PREFIX=${prefix}`, `-DCMAKE_PREFIX_PATH=${prefix}`, ...args]);
  run('cmake', ['--build', build, '--parallel']);
  run('cmake', ['--install', build]);
}

export function installedLibraries() {
  mkdirSync(join(addon, 'bin'), {recursive: true});
  const libs = readdirSync(join(addon, 'bin')).filter(name => name.startsWith('librally_voice.'));
  console.log(`Radio libraries in game/addons/rally_voice/bin: ${libs.join(', ') || 'none'}`);
  return libs;
}

function build(target) {
  const t = TARGETS[target];
  if (!t) throw new Error(`Unknown --target. Use one of: ${Object.keys(TARGETS).join(', ')}`);
  fetchSources();
  const work = join(cache, 'build', target);
  const prefix = join(work, 'prefix');
  const args = toolchain(target, prefix);
  if (!existsSync(join(prefix, '.deps-' + deps.revision))) {
    cmakeProject(join(cache, 'mbedtls'), join(work, 'mbedtls'), prefix, [...args, '-DENABLE_PROGRAMS=OFF', '-DENABLE_TESTING=OFF',
      '-DMBEDTLS_FATAL_WARNINGS=OFF', '-DUSE_SHARED_MBEDTLS_LIBRARY=OFF', '-DUSE_STATIC_MBEDTLS_LIBRARY=ON']);
    cmakeProject(join(cache, 'opus'), join(work, 'opus'), prefix, [...args, '-DOPUS_BUILD_PROGRAMS=OFF', '-DOPUS_BUILD_TESTING=OFF',
      '-DOPUS_BUILD_SHARED_LIBRARY=OFF', ...(t.opus || [])]);
    writeFileSync(join(prefix, '.deps-' + deps.revision), '');
  }
  cmakeProject(join(root, 'native/voice'), join(work, 'extension'), join(work, 'out'), [...args,
    `-DGODOT_CPP_DIR=${join(cache, 'godot-cpp')}`, `-DLIBDATACHANNEL_DIR=${join(cache, 'libdatachannel')}`,
    `-DVOICE_PREFIX=${prefix}`, `-DVOICE_SUFFIX=${t.suffix}`]);
  const name = `librally_voice.${t.suffix}.${t.ext}`;
  mkdirSync(join(addon, 'bin'), {recursive: true});
  copyFileSync(join(work, 'out/bin', name), join(addon, 'bin', name));
  installedLibraries();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--install')) installedLibraries();
  else build(arg('target') || 'linux-x86_64');
}
