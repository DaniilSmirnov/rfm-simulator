import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const BUILD_SECRET_NAMES = [
  'VK_APP_SECRET',
  'VK_SERVICE_TOKEN',
  'VK_SESSION_SECRET',
];

export const DEPLOY_SECRETS_FILE = join('.cache', 'deploy-secrets.json');

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

export async function persistBuildSecrets(env = process.env, path = DEPLOY_SECRETS_FILE) {
  // Local builds must not suddenly require production secrets. Workers Builds
  // always exposes WORKERS_CI=1 during the build command.
  if (env.WORKERS_CI !== '1') return false;

  const secrets = collectBuildSecrets(env);
  await mkdir(join(path, '..'), { recursive: true });
  await writeFile(path, JSON.stringify(secrets), { mode: 0o600 });
  console.log(`Prepared deploy secrets file with: ${Object.keys(secrets).join(', ')}`);
  return true;
}

async function fileExists(path) {
  try {
    await stat(path);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

export async function deployWithBuildSecrets(env = process.env, path = DEPLOY_SECRETS_FILE) {
  let secretsFile = path;
  let cleanup = false;

  // In Workers Builds the secret values exist during the build command only, so
  // build-all.mjs persists a temporary file for the deploy command.
  if (env.WORKERS_CI === '1') {
    if (!await fileExists(secretsFile)) {
      throw new Error(
        `Cloudflare deploy secrets file is missing: ${secretsFile}. ` +
        'Ensure the Build command runs npm run build before npm run deploy.'
      );
    }

    // Parse once before invoking Wrangler so a truncated/corrupt build artifact
    // never reaches the deploy command.
    const parsed = JSON.parse(await readFile(secretsFile, 'utf8'));
    if (!parsed.VK_APP_SECRET) {
      throw new Error('Cloudflare deploy secrets file does not contain VK_APP_SECRET.');
    }
    cleanup = true;
  } else if (typeof env.VK_APP_SECRET === 'string' && env.VK_APP_SECRET.trim() !== '') {
    // Handy for non-Workers CI where secrets are available during deploy itself.
    await mkdir(join(secretsFile, '..'), { recursive: true });
    await writeFile(secretsFile, JSON.stringify(collectBuildSecrets(env)), { mode: 0o600 });
    cleanup = true;
  } else {
    // Manual local deploy keeps the regular Wrangler workflow and can use
    // secrets already configured with `wrangler secret put`.
    secretsFile = null;
  }

  try {
    const args = ['wrangler', 'deploy'];
    if (secretsFile) {
      args.push('--secrets-file', secretsFile);
      console.log(`Deploying with secrets file: ${secretsFile}`);
    }

    const result = spawnSync('npx', args, {
      stdio: 'inherit',
      env,
      shell: process.platform === 'win32',
    });
    if (result.error) throw result.error;
    if (result.status !== 0) {
      throw new Error(`wrangler deploy exited with status ${result.status ?? 'unknown'}`);
    }
  } finally {
    if (cleanup) await rm(secretsFile, { force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await deployWithBuildSecrets();
}
