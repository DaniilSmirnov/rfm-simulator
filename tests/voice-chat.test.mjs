import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
import { resolve } from 'node:path';
function load() { const sandbox = { window: {}, navigator: {}, document: { addEventListener: () => {} }, addEventListener: () => {}, RTCPeerConnection: class {}, console }; sandbox.window = sandbox; runInNewContext(readFileSync(new URL('../web/voice-chat.js', import.meta.url), 'utf8'), sandbox); return sandbox; }
test('radio quality follows distance bands', () => { const q = load().RallyVoice.quality; assert.equal(q(0).level, 1); assert.equal(q(31).level, 2); assert.equal(q(101).level, 3); assert.equal(q(251).level, 4); assert.equal(q(501).level, 5); });
test('voice module exposes signaling queue and PTT API', () => { const voice = load().RallyVoice.attach({ session: 'session-12345678' }); assert.equal(typeof voice.onSignal, 'function'); assert.equal(typeof voice.drainSignals, 'function'); assert.equal(voice.drainSignals().length, 0); });

test('native voice backend does not depend on browser globals', () => {
  const source = readFileSync(resolve('game/scripts/net/voice_chat.gd'), 'utf8');
  assert.match(source, /native-webrtc/); assert.match(source, /backend != "web"/);
});
