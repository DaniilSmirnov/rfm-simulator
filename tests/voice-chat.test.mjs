import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';
import { RoomState } from '../server/room-core.mjs';

const source = readFileSync(new URL('../web/voice-chat.js', import.meta.url), 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));

// Just enough of RTCPeerConnection to exercise the signaling logic.
class FakePeer {
  constructor(config) { this.config = config; this.transceivers = []; this.signalingState = 'stable'; this.remoteDescription = null; this.localDescription = null; this.connectionState = 'new'; this.candidates = []; }
  transceiver(direction) {
    const t = { direction, stopped: false, receiver: { track: { kind: 'audio' } }, sender: { track: null } };
    t.sender.replaceTrack = async track => { t.sender.track = track; };
    this.transceivers.push(t);
    return t;
  }
  addTransceiver(_kind, { direction }) { const t = this.transceiver(direction); queueMicrotask(() => this.onnegotiationneeded?.()); return t; }
  getTransceivers() { return this.transceivers; }
  async setLocalDescription() {
    const type = this.signalingState === 'have-remote-offer' ? 'answer' : 'offer';
    this.localDescription = { type, sdp: type, toJSON: () => ({ type, sdp: type }) };
    this.signalingState = type === 'offer' ? 'have-local-offer' : 'stable';
  }
  async setRemoteDescription(description) {
    this.remoteDescription = description;
    if (description.type === 'offer') {
      this.signalingState = 'have-remote-offer';
      if (!this.transceivers.length) this.transceiver('recvonly');
    } else this.signalingState = 'stable';
  }
  async addIceCandidate(candidate) { this.candidates.push(candidate); }
  close() { this.connectionState = 'closed'; }
}

function load({ mic = 'grant', AudioContext } = {}) {
  const tracks = [];
  const listeners = () => {};
  const sandbox = {
    console, setTimeout, clearTimeout, queueMicrotask, JSON,
    RTCPeerConnection: FakePeer,
    MediaStream: class { constructor(t) { this.tracks = t; } },
    document: { hidden: false, addEventListener: listeners, body: { appendChild() {} }, createElement: () => ({ dataset: {}, style: {}, remove() {} }) },
    navigator: { mediaDevices: { getUserMedia: async () => {
      if (mic === 'deny') throw Object.assign(new Error('denied'), { name: 'NotAllowedError' });
      const track = { kind: 'audio', enabled: true, stopped: false, stop() { this.stopped = true; } };
      tracks.push(track);
      return { getAudioTracks: () => [track], getTracks: () => [track] };
    } } },
    addEventListener: listeners, AudioContext,
  };
  sandbox.window = sandbox;
  runInNewContext(source, sandbox);
  return { voice: sandbox.RallyVoice, tracks };
}

const tick = (voice, levels = []) => JSON.parse(voice.tick(JSON.stringify(levels)));

// Delivers queued signals between clients until nobody has anything to send.
async function relay(clients) {
  for (let round = 0; round < 10; round++) {
    await flush();
    let sent = 0;
    for (const [id, client] of Object.entries(clients)) {
      for (const envelope of tick(client.voice).signals) {
        sent++;
        assert.equal(envelope.data.space, 'voice');
        assert.ok(envelope.data.session.length >= 8);
        await clients[envelope.to].voice.onSignal(id, envelope.data);
      }
    }
    if (!sent) return;
  }
}

function room(ids, options) {
  const clients = {};
  for (const id of ids) {
    clients[id] = load(options);
    clients[id].voice.syncMembers(ids);
    assert.equal(clients[id].voice.join({ localId: id, session: `room-${id}-session`, iceServers: ['stun:example.org:3478'] }), true);
  }
  return clients;
}

// Records the Web Audio graph: which node feeds which.
class FakeAudio {
  constructor() { this.destination = { kind: 'destination' }; this.nodes = []; this.currentTime = 0; this.sampleRate = 8000; this.state = 'running'; }
  node(kind, params = []) {
    const node = { kind, outputs: [], connect: next => { node.outputs.push(next); return next; }, disconnect() {}, start() {}, stop() {} };
    for (const name of params) node[name] = { value: 0, setTargetAtTime(v) { this.value = v; } };
    this.nodes.push(node);
    return node;
  }
  createGain() { return this.node('gain', ['gain']); }
  createDynamicsCompressor() { return this.node('compressor', ['threshold', 'knee', 'ratio', 'attack', 'release']); }
  createBiquadFilter() { return this.node('filter', ['frequency']); }
  createBufferSource() { return this.node('noise'); }
  createMediaStreamSource() { return this.node('voice'); }
}

test('voices are boosted, limited and then follow the radio volume', () => {
  let ctx;
  const { voice } = load({ AudioContext: class extends FakeAudio { constructor() { super(); ctx = this; } } });
  voice.bridge([['setVolume', 0.25]]);
  voice.join({ localId: 'a', session: 'session-a' });
  voice.syncMembers(['a', 'b']);
  voice.state.peers.get('b').pc.ontrack({ streams: [{}] });
  const path = [];
  for (let node = ctx.nodes.find(n => n.kind === 'voice'); node && node !== ctx.destination; node = node.outputs[0]) path.push(node);
  assert.equal(path.at(-1).outputs[0], ctx.destination, 'the chain reaches the speakers');
  const [compressor, boost, limiter, fader] = path.slice(-4);
  assert.equal(compressor.kind, 'compressor');
  assert.ok(boost.gain.value > 2, 'quiet voices are raised');
  assert.ok(limiter.kind === 'compressor' && limiter.threshold.value <= -1 && limiter.ratio.value >= 20, 'a limiter keeps them below clipping');
  assert.equal(fader.gain.value, 0.25, 'the volume set before the first voice applies');
  voice.bridge([['setVolume', 0]]);
  assert.equal(fader.gain.value, 0);
  voice.setVolume('nonsense');
  assert.equal(fader.gain.value, 1);
  voice.leave();
});

test('every pair of members negotiates one audio line, the smaller id calls', async () => {
  const clients = room(['a', 'b', 'c']);
  await relay(clients);
  for (const [id, { voice }] of Object.entries(clients)) {
    assert.deepEqual([...voice.state.peers.keys()].sort(), ['a', 'b', 'c'].filter(x => x !== id), id);
    for (const peer of voice.state.peers.values()) {
      assert.equal(peer.pc.signalingState, 'stable');
      assert.equal(peer.pc.transceivers.length, 1);
      assert.equal(peer.pc.transceivers[0].direction, 'sendrecv');
      assert.equal(JSON.stringify(peer.pc.config.iceServers), JSON.stringify([{ urls: ['stun:example.org:3478'] }]));
    }
  }
});

test('push-to-talk asks for the microphone once and gates the shared track', async () => {
  const clients = room(['a', 'b']);
  await relay(clients);
  const { voice, tracks } = clients.a;
  assert.equal(voice.state.mic, 'idle');
  voice.setPtt(true);
  await flush();
  assert.equal(voice.state.mic, 'ready');
  assert.equal(tracks.length, 1);
  assert.equal(tracks[0].enabled, true);
  assert.equal(voice.state.peers.get('b').pc.transceivers[0].sender.track, tracks[0]);
  voice.setPtt(false);
  assert.equal(tracks[0].enabled, false);
  voice.setPtt(true);
  await flush();
  assert.equal(tracks.length, 1, 'the microphone is requested only once');
  assert.deepEqual(tick(voice).events, [{ type: 'mic', value: 'pending' }, { type: 'mic', value: 'ready' }]);
});

test('the engine bridge runs a batch of calls in order and returns every tick', async () => {
  const { voice, tracks } = load();
  const first = voice.bridge([['syncMembers', ['a', 'b']], ['join', { localId: 'a', session: 'room-a-session' }], ['setPtt', true], ['tick', []]]);
  assert.equal(first.joined, true);
  assert.equal(first.results.length, 1);
  assert.deepEqual(first.results[0].events, [{ type: 'mic', value: 'pending' }]);
  await flush();
  assert.equal(tracks.length, 1, 'push-to-talk through the bridge opens the microphone');
  const second = voice.bridge([['tick', [{ id: 'b', distance: 12 }]], ['unknown'], 'junk', ['tick']]);
  assert.equal(second.results.length, 2);
  assert.equal(second.results[0].signals[0].data.kind, 'offer');
  assert.equal(JSON.stringify(voice.bridge([['leave']])), '{"results":[],"joined":false}');
});

test('a refused microphone leaves the radio receive-only', async () => {
  const clients = room(['a', 'b'], { mic: 'deny' });
  await relay(clients);
  clients.b.voice.setPtt(true);
  await flush();
  assert.equal(clients.b.voice.state.mic, 'denied');
  assert.equal(clients.b.voice.state.peers.size, 1, 'incoming audio keeps working');
});

test('leaving says bye, releases the microphone and the other side drops the link', async () => {
  const clients = room(['a', 'b']);
  await relay(clients);
  clients.a.voice.setPtt(true);
  await flush();
  clients.a.voice.leave();
  assert.equal(clients.a.tracks[0].stopped, true);
  const signals = tick(clients.a.voice).signals;
  assert.deepEqual(signals.map(s => [s.to, s.data.kind]), [['b', 'bye']]);
  clients.b.voice.syncMembers(['b']);
  await clients.b.voice.onSignal('a', signals[0].data);
  assert.equal(clients.b.voice.state.peers.size, 0);
  assert.deepEqual([...clients.b.voice.state.members], [], 'a late bye does not put the member back on the roster');
  await clients.b.voice.onSignal('a', { space: 'voice', kind: 'candidate', session: 'room-a-session', candidate: {} });
  assert.equal(clients.b.voice.state.peers.size, 0, 'only an offer opens a link with an unlisted member');
  assert.equal(clients.a.voice.setPtt(true), false, 'no transmitting outside a room');
});

test('early candidates wait for the remote description; a new session restarts the link', async () => {
  const { voice } = load();
  voice.join({ localId: 'b', session: 'room-b-session' });
  voice.syncMembers(['a', 'b']);
  await voice.onSignal('a', { space: 'voice', kind: 'offer', session: 'session-one', description: { type: 'offer', sdp: 'x' } });
  const first = voice.state.peers.get('a');
  await voice.onSignal('a', { space: 'voice', kind: 'candidate', session: 'session-one', candidate: { candidate: 'c1' } });
  assert.deepEqual(first.pc.candidates, [{ candidate: 'c1' }]);
  await voice.onSignal('a', { space: 'voice', kind: 'offer', session: 'session-two', description: { type: 'offer', sdp: 'y' } });
  assert.notEqual(voice.state.peers.get('a'), first);
  assert.equal(first.pc.connectionState, 'closed');
});

test('distance and talking flags drive the receive levels', async () => {
  const clients = room(['a', 'b']);
  await relay(clients);
  const peer = clients.a.voice.state.peers.get('b');
  tick(clients.a.voice, [{ id: 'b', distance: 320, talking: true }]);
  assert.equal(peer.distance, 320);
  assert.equal(peer.talking, true);
});

test('the room server relays voice signaling between any two members', () => {
  const r = new RoomState();
  const h = r.add('Хозяин', 1000, true);
  const g1 = r.add('Друг', 1000);
  const g2 = r.add('Друг 2', 1000);
  const offer = { space: 'voice', kind: 'offer', session: 'session-1234', description: { type: 'offer', sdp: 'x' } };
  assert.deepEqual(r.signal(g1.token, g2.player, offer, 1100), { from: g1.player, to: g2.player });
  assert.throws(() => r.signal(g1.token, g2.player, { kind: 'offer' }, 1100), e => e.status === 404, 'game links stay host <-> guest');
  assert.throws(() => r.signal(g1.token, g1.player, offer, 1100), e => e.status === 404, 'not to oneself');
  assert.throws(() => r.signal(g1.token, h.player, { ...offer, kind: 'hello' }, 1100), e => e.status === 400);
  assert.throws(() => r.signal(g1.token, h.player, { ...offer, session: 'short' }, 1100), e => e.status === 400);
  assert.throws(() => r.signal(g1.token, h.player, { ...offer, description: { sdp: 'ж'.repeat(5000) } }, 1100), e => e.status === 400, 'UTF-8 size limit');
});

test('the radio flag reaches other members through the room server', () => {
  const r = new RoomState();
  const h = r.add('Хозяин', 1000, true);
  const g = r.add('Друг', 1000);
  const state = { pos: [0, 1, 2], car: [3, 4, 5], heading: 1, yaw: 2, pitch: 0, in_car: true, tow: false, beer: -1 };
  r.sync({ token: g.token, state: { ...state, radio: true } }, 1100);
  const reply = r.sync({ token: h.token, state }, 1200);
  assert.equal(reply.players.find(p => p.id === g.player).state.radio, true);
  assert.equal(reply.players.find(p => p.id === h.player).state.radio, false);
});

test('a far radio is as loud and clean as a near one, without hiss', () => {
  let ctx;
  const { voice } = load({ AudioContext: class extends FakeAudio { constructor() { super(); ctx = this; } } });
  voice.join({ localId: 'a', session: 'session-a' });
  voice.syncMembers(['a', 'b']);
  voice.state.peers.get('b').pc.ontrack({ streams: [{}] });
  voice.tick(JSON.stringify([{ id: 'b', distance: 5000, talking: true }]));
  assert.equal(voice.state.peers.get('b').audio.gain.gain.value, 1);
  assert.ok(!ctx.nodes.some(n => n.kind === 'noise'), 'no noise source is made');
  assert.deepEqual(ctx.nodes.filter(n => n.kind === 'filter').map(n => n.frequency.value), [300, 3400]);
  voice.mute('b');
  assert.equal(voice.state.peers.get('b').audio.gain.gain.value, 0);
  voice.leave();
});
