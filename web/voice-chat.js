/* Browser radio: push-to-talk voice between room members over WebRTC audio.
 * The room server only relays signaling (`space: "voice"`); audio never enters
 * the game socket. Godot drives this module through JavaScriptBridge and reads
 * results back as JSON strings (eval only returns primitives):
 *   join({localId, session, iceServers}) / leave()
 *   syncMembers(ids)       open/close one connection per other member
 *   onSignal(from, data)   relayed offer/answer/candidate/bye
 *   setPtt(pressed)        first press asks for the microphone
 *   tick(json)             [{id, distance, talking}] -> JSON {signals, mic, events}
 */
(() => {
  // Distance bands (metres): farther radios are quieter, narrower and noisier.
  const BANDS = Object.freeze([
    { max: 30, volume: 1, noise: 0, cutoff: 3400 },
    { max: 100, volume: 0.92, noise: 0.04, cutoff: 3200 },
    { max: 250, volume: 0.72, noise: 0.12, cutoff: 2700 },
    { max: 500, volume: 0.45, noise: 0.24, cutoff: 2100 },
    { max: Infinity, volume: 0.15, noise: 0.4, cutoff: 1500 },
  ]);
  // The first redial is quick (a reload), later ones back off like the direct link.
  const FIRST_RETRY_MS = 1000;
  const RETRY_MS = 20000;
  const LOST_MS = 5000;
  const DIAL_MS = 15000;
  const MAX_ATTEMPTS = 3;
  const MAX_QUEUE = 128;
  const state = {
    joined: false, localId: '', session: '', iceServers: [], members: [],
    peers: new Map(), attempts: new Map(), muted: new Set(),
    stream: null, mic: 'idle', pressed: false,
  };
  const outgoing = [];
  const events = [];
  let context = null, master = null, noiseBuffer = null;

  function quality(distance) {
    const d = Math.max(0, Number(distance) || 0);
    const level = BANDS.findIndex(band => d <= band.max);
    return { level: level + 1, ...BANDS[level] };
  }

  function send(to, data) {
    if (outgoing.length >= MAX_QUEUE) outgoing.shift();
    outgoing.push({ to, data: { ...data, space: 'voice', session: state.session } });
  }

  function micTrack() { return state.stream?.getAudioTracks()[0] || null; }

  // ------------------------------------------------------------- audio out

  function audioContext() {
    if (context) return context;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return null;
    context = new Ctx();
    master = context.createGain();
    master.connect(context.destination);
    noiseBuffer = context.createBuffer(1, context.sampleRate, context.sampleRate);
    const samples = noiseBuffer.getChannelData(0);
    for (let i = 0; i < samples.length; i++) samples[i] = Math.random() * 2 - 1;
    return context;
  }

  function resumeAudio() { if (context && context.state === 'suspended') context.resume().catch(() => {}); }

  function playRemote(peer, stream) {
    const ctx = audioContext();
    if (!ctx || peer.audio) return;
    // Chrome only feeds a remote WebRTC stream into Web Audio while a media
    // element also holds it; the element itself stays muted.
    const element = document.createElement('audio');
    element.muted = true;
    element.autoplay = true;
    element.playsInline = true;
    element.srcObject = stream;
    element.dataset.voicePeer = peer.id;
    element.style.display = 'none';
    document.body?.appendChild(element);
    const source = ctx.createMediaStreamSource(stream);
    const highpass = ctx.createBiquadFilter();
    highpass.type = 'highpass';
    highpass.frequency.value = 300;
    const lowpass = ctx.createBiquadFilter();
    lowpass.type = 'lowpass';
    const gain = ctx.createGain();
    gain.gain.value = 0;
    source.connect(highpass).connect(lowpass).connect(gain).connect(master);
    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuffer;
    noise.loop = true;
    const hiss = ctx.createBiquadFilter();
    hiss.type = 'bandpass';
    hiss.frequency.value = 2000;
    const noiseGain = ctx.createGain();
    noiseGain.gain.value = 0;
    noise.connect(hiss).connect(noiseGain).connect(master);
    noise.start();
    peer.audio = { element, source, lowpass, gain, noise, noiseGain };
    applyLevels(peer);
  }

  function applyLevels(peer) {
    const audio = peer.audio;
    if (!audio || !context) return;
    const q = quality(peer.distance);
    const silent = state.muted.has(peer.id);
    const now = context.currentTime;
    audio.gain.gain.setTargetAtTime(silent ? 0 : q.volume, now, 0.05);
    audio.lowpass.frequency.setTargetAtTime(q.cutoff, now, 0.05);
    audio.noiseGain.gain.setTargetAtTime(silent || !peer.talking ? 0 : q.noise * 0.25, now, 0.03);
  }

  // ------------------------------------------------------------- connections

  function ensurePeer(id, initiator) {
    let peer = state.peers.get(id);
    if (peer) return peer;
    const pc = new RTCPeerConnection({ iceServers: state.iceServers });
    peer = { id, pc, polite: state.localId > id, makingOffer: false, ignoreOffer: false,
      candidates: [], remoteSession: '', audio: null, distance: 9999, talking: false, connected: false };
    state.peers.set(id, peer);
    pc.onicecandidate = event => { if (event.candidate) send(id, { kind: 'candidate', candidate: event.candidate.toJSON() }); };
    pc.onnegotiationneeded = async () => {
      try {
        peer.makingOffer = true;
        await pc.setLocalDescription();
        send(id, { kind: 'offer', description: pc.localDescription.toJSON() });
      } catch (error) { report('negotiation', error); } finally { peer.makingOffer = false; }
    };
    pc.ontrack = event => playRemote(peer, event.streams[0] || new MediaStream([event.track]));
    pc.onconnectionstatechange = () => {
      const s = pc.connectionState;
      peer.connected = s === 'connected';
      clearTimeout(peer.lost);
      if (s === 'connected') { state.attempts.delete(id); clearTimeout(peer.dialing); }
      // A member who reloaded the page never says bye: give a silent link a
      // few seconds, then dial again.
      if (s === 'disconnected') peer.lost = setTimeout(() => { if (state.peers.get(id) === peer) { drop(id, false); noteFailure(id); } }, LOST_MS);
      if (s === 'failed') { drop(id, false); noteFailure(id); }
    };
    // A lost offer or answer would leave the link waiting forever.
    peer.dialing = setTimeout(() => {
      if (state.peers.get(id) === peer && !peer.connected) { drop(id, false); noteFailure(id); }
    }, DIAL_MS);
    // One side adds the audio line; the other side answers on the line the offer created.
    if (initiator) attachMic(pc.addTransceiver('audio', { direction: 'sendrecv' }));
    return peer;
  }

  function attachMic(transceiver) {
    const track = micTrack();
    transceiver.sender.replaceTrack(track).catch(error => report('track', error));
  }

  function noteFailure(id) {
    const entry = state.attempts.get(id) || { count: 0, retryAt: 0 };
    entry.count++;
    entry.retryAt = Date.now() + (entry.count === 1 ? FIRST_RETRY_MS : RETRY_MS);
    state.attempts.set(id, entry);
  }

  function canDial(id) {
    const entry = state.attempts.get(id);
    return !entry || (entry.count < MAX_ATTEMPTS && Date.now() >= entry.retryAt);
  }

  function drop(id, notify) {
    const peer = state.peers.get(id);
    if (!peer) return;
    if (notify) send(id, { kind: 'bye' });
    clearTimeout(peer.lost);
    clearTimeout(peer.dialing);
    state.peers.delete(id);
    peer.pc.onnegotiationneeded = peer.pc.onicecandidate = peer.pc.ontrack = peer.pc.onconnectionstatechange = null;
    peer.pc.close();
    if (peer.audio) {
      peer.audio.noise.stop();
      peer.audio.source.disconnect();
      peer.audio.gain.disconnect();
      peer.audio.noiseGain.disconnect();
      peer.audio.element.srcObject = null;
      peer.audio.element.remove();
    }
  }

  function syncMembers(ids) {
    state.members = (Array.isArray(ids) ? ids : []).map(String).filter(id => id && id !== state.localId);
    if (!state.joined) return;
    for (const id of [...state.peers.keys()]) if (!state.members.includes(id)) drop(id, true);
    for (const id of state.members) {
      // The member with the smaller id calls; the other waits for the offer.
      if (!state.peers.has(id) && state.localId < id && canDial(id)) ensurePeer(id, true);
    }
  }

  async function onSignal(from, data) {
    if (!state.joined || !data || data.space !== 'voice' || typeof data.kind !== 'string') return;
    const id = String(from);
    if (data.kind === 'bye') { drop(id, false); return; }
    // The server only relays between members of this room, so an offer from
    // someone the roster does not list yet is a newcomer: the roster lags.
    if (!state.members.includes(id)) {
      if (data.kind !== 'offer') return;
      state.members.push(id);
    }
    let peer = state.peers.get(id);
    // A new session from a known member means they reloaded: start over.
    if (peer && data.kind === 'offer' && peer.remoteSession && data.session !== peer.remoteSession) { drop(id, false); peer = null; }
    if (!peer) {
      if (data.kind !== 'offer') return;
      peer = ensurePeer(id, false);
    }
    const pc = peer.pc;
    try {
      if (data.kind === 'candidate') {
        if (pc.remoteDescription) await pc.addIceCandidate(data.candidate);
        else peer.candidates.push(data.candidate);
        return;
      }
      if (data.kind !== 'offer' && data.kind !== 'answer') return;
      const offer = data.kind === 'offer';
      const collision = offer && (peer.makingOffer || pc.signalingState !== 'stable');
      peer.ignoreOffer = !peer.polite && collision;
      if (peer.ignoreOffer) return;
      if (offer) peer.remoteSession = String(data.session || '');
      await pc.setRemoteDescription(data.description);
      for (const candidate of peer.candidates.splice(0)) await pc.addIceCandidate(candidate).catch(() => {});
      if (offer) {
        for (const transceiver of pc.getTransceivers()) {
          if (transceiver.receiver.track?.kind === 'audio' && transceiver.direction === 'recvonly') {
            transceiver.direction = 'sendrecv';
            attachMic(transceiver);
          }
        }
        await pc.setLocalDescription();
        send(id, { kind: 'answer', description: pc.localDescription.toJSON() });
      }
    } catch (error) {
      if (!peer.ignoreOffer) report('signal', error);
    }
  }

  // ------------------------------------------------------------- microphone

  async function requestMic() {
    if (state.mic !== 'idle') return;
    if (!navigator.mediaDevices?.getUserMedia) { setMic('unavailable'); return; }
    setMic('pending');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      });
      if (!state.joined) { stream.getTracks().forEach(track => track.stop()); setMic('idle'); return; }
      state.stream = stream;
      const track = micTrack();
      track.enabled = state.pressed;
      for (const peer of state.peers.values()) {
        for (const transceiver of peer.pc.getTransceivers()) {
          if (transceiver.direction === 'sendrecv' && !transceiver.stopped) attachMic(transceiver);
        }
      }
      setMic('ready');
    } catch (error) {
      setMic(error?.name === 'NotAllowedError' || error?.name === 'SecurityError' ? 'denied' : 'unavailable');
    }
  }

  function setMic(value) {
    if (state.mic === value) return;
    state.mic = value;
    events.push({ type: 'mic', value });
  }

  function setPtt(pressed) {
    state.pressed = Boolean(pressed) && state.joined;
    resumeAudio();
    if (state.pressed && state.mic === 'idle') requestMic();
    const track = micTrack();
    if (track) track.enabled = state.pressed;
    return state.pressed;
  }

  function releasePtt() { setPtt(false); }

  // ------------------------------------------------------------- room lifecycle

  function join(options = {}) {
    if (!window.RTCPeerConnection) return false;
    if (state.joined) leave();
    state.localId = String(options.localId || '');
    state.session = String(options.session || '');
    state.iceServers = (Array.isArray(options.iceServers) ? options.iceServers : []).map(url => ({ urls: [String(url)] }));
    state.attempts.clear();
    state.joined = state.localId !== '' && state.session.length >= 8;
    if (state.joined) syncMembers(state.members);
    return state.joined;
  }

  function leave() {
    releasePtt();
    for (const id of [...state.peers.keys()]) drop(id, true);
    state.joined = false;
    state.stream?.getTracks().forEach(track => track.stop());
    state.stream = null;
    if (state.mic !== 'denied' && state.mic !== 'unavailable') setMic('idle');
  }

  function update(list) {
    for (const entry of Array.isArray(list) ? list : []) {
      const peer = state.peers.get(String(entry.id));
      if (!peer) continue;
      peer.distance = Number(entry.distance) || 0;
      peer.talking = entry.talking === true;
      applyLevels(peer);
    }
  }

  function mute(id, value = true) {
    id = String(id);
    if (value) state.muted.add(id); else state.muted.delete(id);
    const peer = state.peers.get(id);
    if (peer) applyLevels(peer);
  }

  function poll() {
    let connected = 0;
    for (const peer of state.peers.values()) if (peer.connected) connected++;
    return { signals: outgoing.splice(0), mic: state.mic, events: events.splice(0), connected };
  }

  function tick(json) {
    let list = [];
    try { list = JSON.parse(json || '[]'); } catch {}
    update(list);
    syncMembers(state.members);
    return JSON.stringify(poll());
  }

  function report(stage, error) { events.push({ type: 'error', stage, message: String(error?.message || error) }); }

  addEventListener('blur', releasePtt);
  addEventListener('pagehide', releasePtt);
  document.addEventListener('visibilitychange', () => { if (document.hidden) releasePtt(); });
  for (const name of ['pointerdown', 'keydown', 'touchend']) addEventListener(name, resumeAudio, { capture: true, passive: true });

  window.RallyVoice = { join, leave, syncMembers, onSignal, setPtt, update, mute, poll, tick, quality, state };
})();
