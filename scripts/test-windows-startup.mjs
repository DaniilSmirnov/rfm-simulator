import assert from 'node:assert/strict';
import { copyFile, mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { verifyWindowsBuild } from './verify-windows-build.mjs';

assert.equal(process.platform, 'win32', 'Run this smoke test on Windows');
const directory = resolve(process.argv[2] ?? 'dist-windows');
await verifyWindowsBuild(directory);
for (const arch of ['x86', 'x64']) {
  // No checkout, .pck, DLLs, or other architecture's exe in the working directory.
  const isolated = await mkdtemp(join(tmpdir(), `rfm-${arch}-`));
  try {
    const name = `Rally_Fans_Simulator_${arch}.exe`;
    const exe = join(isolated, name);
    const logPath = join(isolated, 'startup.log');
    await copyFile(join(directory, name), exe);
    const result = spawnSync(exe, ['--headless', '--quit-after', '180', '--log-file', logPath], {
      cwd: isolated, encoding: 'utf8', timeout: 120_000,
    });
    const log = await readFile(logPath, 'utf8').catch(() => '');
    console.log(`${name}\n${result.stdout ?? ''}${result.stderr ?? ''}${log}`);
    assert.ifError(result.error);
    assert.equal(result.status, 0, `${name}: startup failed (${result.signal})`);
    assert.match(log, /Godot Engine v4\.4\.1/, `${name}: no engine startup log`);
    assert.match(log, /\[RFM\] Запуск завершён/, `${name}: game initialization did not finish`);
    assert.doesNotMatch(`${result.stdout ?? ''}${result.stderr ?? ''}${log}`, /SCRIPT ERROR:|ERROR:|Couldn't load project data|Failed to load/i, `${name}: startup errors`);
    console.log(`PASS: ${name} starts from an isolated directory containing only its exe`);
  } finally {
    await rm(isolated, { recursive: true, force: true });
  }
}
