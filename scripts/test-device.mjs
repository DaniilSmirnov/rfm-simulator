import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import assert from 'node:assert/strict';
const device = runInNewContext(readFileSync(new URL('../web/mobile-device.js', import.meta.url), 'utf8') + '\nRallyDevice');
const detect = (userAgent, maxTouchPoints, coarse = false, mobile = false) => device.isMobile({ userAgent, maxTouchPoints, userAgentData: { mobile } }, () => ({ matches: coarse }));
assert.equal(detect('Windows Chrome', 0), false);
assert.equal(detect('Windows Chrome', 10, false), false);
assert.equal(detect('Android Chrome', 5, true), true);
assert.equal(detect('iPhone Safari', 5), true);
assert.equal(detect('Macintosh Safari', 5), true);
assert.equal(detect('Macintosh Safari', 0), false);
assert.equal(detect('Unknown', 2, true), true);
assert.equal(detect('Unknown', 0, false, true), true);
console.log('PASS: 8 mobile browser detection checks');

const orientationCalls = [];
const orientation = runInNewContext(readFileSync(new URL('../web/mobile-device.js', import.meta.url), 'utf8') + '\nRallyDevice', {
  document: { fullscreenElement: null, documentElement: { async requestFullscreen() { orientationCalls.push('fullscreen'); } } },
  screen: { orientation: { async lock(mode) { orientationCalls.push(mode); } } },
  RallyFullscreen: { isActive: () => false, async enter() { orientationCalls.push('fullscreen'); } }
});
await orientation.requestLandscape();
assert.deepEqual(orientationCalls, ['fullscreen', 'landscape']);
const unsupported = runInNewContext(readFileSync(new URL('../web/mobile-device.js', import.meta.url), 'utf8') + '\nRallyDevice', {
  document: { fullscreenElement: null, documentElement: { async requestFullscreen() { throw new Error('Denied'); } } },
  screen: { orientation: { async lock() { throw new Error('Unsupported'); } } },
  RallyFullscreen: { isActive: () => false, async enter() { throw new Error('Denied'); } }
});
await unsupported.requestLandscape();
console.log('PASS: mobile orientation requests and unsupported browser fallback');

const activeCalls = [];
const active = runInNewContext(readFileSync(new URL('../web/mobile-device.js', import.meta.url), 'utf8') + '\nRallyDevice', {
  screen: { orientation: { async lock(mode) { activeCalls.push(mode); } } },
  RallyFullscreen: { isActive: () => true, async enter() { throw new Error('Already fullscreen'); } }
});
await active.requestLandscape();
assert.deepEqual(activeCalls, ['landscape']);
console.log('PASS: active fullscreen still requests landscape without entering again');
