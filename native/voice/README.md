# Rally native voice extension

Native backend of the room radio for desktop and Android. Browser builds use
`web/voice-chat.js`. Both backends speak the same WebRTC (Opus over SRTP) and
the same room signaling (`space: "voice"`, offer/answer/candidate/bye), so
browser and native players hear each other.

## Classes

- `RallyVoiceLink`: one connection to another member, built on libdatachannel.
  It handles SDP and ICE, the Opus audio line, an RTP jitter buffer with FEC/PLC,
  and the radio colouring (band-pass, volume, hiss) for an `AudioStreamGenerator`.
  libdatachannel calls back on its own threads, and Godot drains events with `poll()`.
- `RallyVoiceEncoder`: turns the microphone (`AudioEffectCapture` frames at the
  mix rate) into 20 ms mono Opus packets at 24 kbit/s with in-band FEC.

The mesh rules match the browser module: the smaller id calls, a bye drops the
link, a new session restarts it, and a silent link is dialled again. They live
in `game/scripts/net/voice_native.gd`.

## Build

```sh
node scripts/build-voice.mjs --target=linux-x86_64     # host build
node scripts/build-voice.mjs --target=windows-x86_64   # MinGW cross build (also windows-x86_32)
node scripts/build-voice.mjs --target=macos-universal  # on macOS
node scripts/build-voice.mjs --target=android-arm64    # ANDROID_NDK_ROOT (also android-arm32)
```

The script clones the pinned sources from `deps.json` into `.cache/voice`. It
builds Mbed TLS (with `MBEDTLS_SSL_DTLS_SRTP`) and Opus as static libraries, then
links libdatachannel and godot-cpp into one library in
`game/addons/rally_voice/bin`. That directory is not committed: CI builds every
platform in the `native-voice` job and passes the libraries to the export jobs.

## Packaging

Exports carry the library inside the pack as a plain file (`include_filter` in
`export_presets.cfg`). There is no `.gdextension` in the project. On the first
radio join, `voice_native.gd` copies the library to `user://rally_voice/<md5>/`,
writes a `.gdextension` next to it and loads it with
`GDExtensionManager.load_extension()`. This keeps three things true:

- Windows builds stay one standalone exe.
- Builds without the library (the web, tests) start without extension errors.
- The library loads only when someone uses the radio.

Microphone access: `audio/driver/enable_input` (off on the web), `RECORD_AUDIO`
on Android (asked on the first press), and `NSMicrophoneUsageDescription`, the
audio-input entitlement and disabled library validation on macOS.

## Tests

- `game/tests/net/test_voice_native.gd`: mesh rules on fake links. With the
  library it also runs two real links over loopback (Opus tone, distance volume,
  silence, hiss). It is required in CI with `RFM_REQUIRE_NATIVE_VOICE=1`.
- `scripts/test-voice-interop.mjs`: a headless Godot client and two Chromium
  pages in one room. It covers both offer directions and audio both ways.
