/* Radio voice transport. The game owns room membership and forwards only
 * signaling envelopes here; audio tracks never enter the game DataChannel or
 * the room Worker. This module is intentionally browser-only. */
(() => {
  const QUALITY = Object.freeze({ clean: 30, light: 100, noisy: 250, weak: 500 });
  const state = { enabled: false, muted: new Set(), peers: new Map(), stream: null, pressed: false };
  let api = null;

  function quality(distance) {
    const d = Math.max(0, Number(distance) || 0);
    if (d <= QUALITY.clean) return { level: 1, volume: 1, noise: 0 };
    if (d <= QUALITY.light) return { level: 2, volume: 0.92, noise: 0.05 };
    if (d <= QUALITY.noisy) return { level: 3, volume: 0.72, noise: 0.22 };
    if (d <= QUALITY.weak) return { level: 4, volume: 0.42, noise: 0.5 };
    return { level: 5, volume: 0.08, noise: 0.8 };
  }

  async function enable(options = {}) {
    if (!navigator.mediaDevices?.getUserMedia || !window.RTCPeerConnection) throw new Error('voice_unavailable');
    if (!state.stream) state.stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    state.enabled = true;
    api?.onStatus?.('ready');
    return true;
  }

  function setPtt(pressed) {
    state.pressed = Boolean(pressed) && state.enabled;
    for (const peer of state.peers.values()) for (const sender of peer.pc.getSenders()) if (sender.track) sender.track.enabled = state.pressed;
    api?.onPtt?.(state.pressed);
  }

  function setDistance(id, distance) {
    const peer = state.peers.get(id); if (!peer) return quality(distance);
    const q = quality(distance); peer.gain.gain.setTargetAtTime(state.muted.has(id) ? 0 : q.volume, peer.audio.context.currentTime, 0.08);
    return q;
  }

  function mute(id, value = true) { value ? state.muted.add(id) : state.muted.delete(id); const peer = state.peers.get(id); if (peer) peer.gain.gain.value = value ? 0 : 1; }
  function disable() { setPtt(false); state.enabled = false; for (const id of state.peers.keys()) close(id); state.stream?.getTracks().forEach(t => t.stop()); state.stream = null; api?.onStatus?.('disabled'); }
  function close(id) { const peer = state.peers.get(id); if (!peer) return; peer.pc.close(); peer.audio.remove(); peer.audio.srcObject = null; peer.audio.context.close(); state.peers.delete(id); }

  function attach(host) { api = host; return { enable, disable, setPtt, setDistance, mute, quality, close }; }
  window.RallyVoice = { attach, quality, state };
})();
