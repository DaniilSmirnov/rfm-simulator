import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BUILD_SECRET_NAMES,
  collectBuildSecrets,
  persistBuildSecrets,
} from '../scripts/deploy-cloudflare.mjs';

test('deploy secret allowlist contains only VK runtime secrets', () => {
  assert.deepEqual(BUILD_SECRET_NAMES, [
    'VK_APP_SECRET',
    'VK_SERVICE_TOKEN',
    'VK_SESSION_SECRET',
  ]);
});

test('build deploy requires VK_APP_SECRET', () => {
  assert.throws(() => collectBuildSecrets({}), /VK_APP_SECRET is missing/);
  assert.throws(() => collectBuildSecrets({ VK_APP_SECRET: '   ' }), /VK_APP_SECRET is missing/);
});

test('build deploy includes only allowlisted VK secrets', () => {
  assert.deepEqual(
    collectBuildSecrets({
      VK_APP_SECRET: 'app-secret',
      VK_SERVICE_TOKEN: 'service-token',
      VK_SESSION_SECRET: 'session-secret',
      CLOUDFLARE_API_TOKEN: 'must-not-be-uploaded',
      GITHUB_TOKEN: 'must-not-be-uploaded',
    }),
    {
      VK_APP_SECRET: 'app-secret',
      VK_SERVICE_TOKEN: 'service-token',
      VK_SESSION_SECRET: 'session-secret',
    }
  );
});

test('optional VK secrets may be omitted', () => {
  assert.deepEqual(
    collectBuildSecrets({ VK_APP_SECRET: 'app-secret' }),
    { VK_APP_SECRET: 'app-secret' }
  );
});

test('Workers Build persists an ephemeral deploy secrets file', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'rfm-secret-test-'));
  const path = join(directory, 'nested', 'secrets.json');
  try {
    assert.equal(await persistBuildSecrets({
      WORKERS_CI: '1',
      VK_APP_SECRET: 'app-secret',
      VK_SERVICE_TOKEN: 'service-token',
      SOMETHING_ELSE: 'nope',
    }, path), true);
    assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), {
      VK_APP_SECRET: 'app-secret',
      VK_SERVICE_TOKEN: 'service-token',
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('local build does not create or require production secrets', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'rfm-secret-test-'));
  const path = join(directory, 'secrets.json');
  try {
    assert.equal(await persistBuildSecrets({}, path), false);
    await assert.rejects(readFile(path, 'utf8'), error => error.code === 'ENOENT');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
