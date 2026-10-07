import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BUILD_SECRET_NAMES, collectBuildSecrets } from '../scripts/deploy-cloudflare.mjs';

test('deploy secret allowlist contains only VK runtime secrets', () => {
  assert.deepEqual(BUILD_SECRET_NAMES, [
    'VK_APP_SECRET',
    'VK_SERVICE_TOKEN',
    'VK_SESSION_SECRET',
  ]);
});

test('build deploy requires VK_APP_SECRET', () => {
  assert.throws(
    () => collectBuildSecrets({}),
    /VK_APP_SECRET is missing/
  );
  assert.throws(
    () => collectBuildSecrets({ VK_APP_SECRET: '   ' }),
    /VK_APP_SECRET is missing/
  );
});

test('build deploy includes required and optional VK secrets without unrelated environment', () => {
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
