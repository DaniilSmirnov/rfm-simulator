import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const BUILD_SECRET_NAMES = [
  'VK_APP_SECRET',
  'VK_SERVICE_TOKEN',
  'VK_SESSION_SECRET',
];

export function collectBuildSecrets(env = process.env) {
  const appSecret = env.VK_APP_SECRET;
  if (typeof appSecret !== 'string' || appSecret.trim() === '') {
    throw new Error(
      'VK_APP_SECRET is missing from Cloudflare Build variables and secrets. ' +
      'Add it as a build secret for the production trigger.'
    );
  }

  return Object.fromEntries(
    BUILD_SECRET_NAMES
      .filter(name => typeof env[name] === 'string' && env[name].length > 0)
      .map(name => [name, env[name]])
  );
}

export async function deployWithBuildSecrets(env = process.env) {
  // Outside Workers Builds, preserve the normal Wrangler workflow: runtime
  // secrets can be managed with `wrangler secret put`.
  if (env.WORKERS_CI !== '1') {
    const result = spawnSync('npx', ['wrangler', 'deploy'], {
      stdio: 'inherit',
      env,
      shell: process.platform === 'win32',
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`wrangler deploy exited with status ${result.status ?? 'unknown'}`);
    return;
  }

  const secrets = collectBuildSecrets(env);
  const directory = await mkdtemp(join(tmpdir(), 'rfm-worker-secrets-'));
  const secretsFile = join(directory, 'secrets.json');

  try {
    await writeFile(secretsFile, JSON.stringify(secrets), { mode: 0o600 });
    console.log(`Deploying with build secrets: ${Object.keys(secrets).join(', ')}`);

    const result = spawnSync('npx', ['wrangler', 'deploy', '--secrets-file', secretsFile], {
      stdio: 'inherit',
      env,
      shell: process.platform === 'win32',
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`wrangler deploy exited with status ${result.status ?? 'unknown'}`);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await deployWithBuildSecrets();
}
