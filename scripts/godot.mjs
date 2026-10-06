import { mkdir, readFile, writeFile, chmod, access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const zipSha = 'd6e382fb531019f85630c1f485a561a0d20c4a2344b6c3847735cfee7da812aa';
const filename = 'Godot_v4.4.1-stable_linux.x86_64';

export function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', timeout: 180000 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.signal})`);
}

export async function getGodot() {
  if (process.env.GODOT_BIN) return resolve(process.env.GODOT_BIN);
  if (process.platform !== 'linux' || process.arch !== 'x64') {
    throw new Error('Set GODOT_BIN to the absolute path of your Godot 4.4.1 executable.');
  }
  const directory = join(root, '.cache', 'godot');
  const executable = join(directory, filename);
  try { await access(executable); return executable; } catch {}
  await mkdir(directory, { recursive: true });
  const archive = join(directory, 'godot.zip');
  const response = await fetch(`https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/${filename}.zip`);
  if (!response.ok) throw new Error(`Godot download failed: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (createHash('sha256').update(bytes).digest('hex') !== zipSha) {
    throw new Error('Downloaded Godot archive failed its SHA-256 check.');
  }
  await writeFile(archive, bytes);
  run('python3', ['-c', 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])', archive, directory]);
  await chmod(executable, 0o755);
  return executable;
}

export async function checkTemplate() {
  const manifest = JSON.parse(await readFile(join(root, 'engine', 'manifest.json'), 'utf8'));
  const template = join(root, 'engine', 'web-template.zip');
  const hash = createHash('sha256').update(await readFile(template)).digest('hex');
  if (hash !== manifest.template_sha256) throw new Error('Web export template SHA-256 mismatch.');
  return template;
}
