# Rally native voice extension

Native backend of the room radio for desktop, Android and iOS. Browser builds use
`web/voice-chat.js`. Both backends speak the same WebRTC (Opus over SRTP) and
the same room signaling (`space: "voice"`, offer/answer/candidate/bye), so
browser and native players hear each other.

## Classes

- `RallyVoiceLink`: one connection to another member, built on libdatachannel.
  It handles SDP and ICE, the Opus audio line, an RTP jitter buffer with FEC/PLC,
  and the radio colouring (band-pass, volume, hiss) for an `AudioStreamGenerator`.
  libdatachannel calls back on its own threads, and Godot drains events with `poll()`.
- `RallyDataLink`: the room's direct link (`game/scripts/net/direct_link.gd`)
  on native builds. It opens the same negotiated unordered data channel
  without retransmits that browser builds open with Godot's WebRTC, so native
  and browser players link directly. `direct_native.gd` adapts it to the
  WebRTCPeerConnection API that the link code uses. The library loads when a
  room starts linking, not only on the first radio join.
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
node scripts/build-voice.mjs --target=ios-arm64        # on macOS with Xcode
```

The script clones the pinned sources from `deps.json` into `.cache/voice`. It
builds Mbed TLS (with `MBEDTLS_SSL_DTLS_SRTP`) and Opus as static libraries, then
links libdatachannel and godot-cpp into one library in
`game/addons/rally_voice/bin`. That directory is not committed: CI builds every
platform in the `native-voice` job and passes the libraries to the export jobs.
The job caches each built library under a key made from `native/voice/**` and
`scripts/build-voice.mjs`, so a run that changes neither restores the library
and skips the toolchain and the build. Bump `VOICE_BUILD_EPOCH` in
`.github/workflows/check.yml` to force a rebuild after a toolchain change.

## Packaging

Exports carry the library inside the pack as a plain file (`include_filter` in
`export_presets.cfg`). There is no `.gdextension` in the project. On the first
radio join, `voice_native.gd` copies the library to `user://rally_voice/<md5>/`,
writes a `.gdextension` next to it and loads it with
`GDExtensionManager.load_extension()`. This keeps three things true:

- Windows builds stay one standalone exe.
- Builds without the library (the web, tests) start without extension errors.
- The library loads only when it is needed: the radio or a room's direct link.

iOS is the exception: an app may only run code signed inside its bundle. For
the iOS export `build-desktop.mjs` writes `addons/rally_voice/rally_voice.gdextension`
into its copy of the project, Godot turns the dylib into an embedded framework,
and the extension loads at startup.

The microphone plays into the `RadioMic` bus from `game/default_bus_layout.tres`
(an `AudioEffectCapture` before a -80 dB fader). The bus is never added at
runtime, because `AudioServer.add_bus()` does not lock the mixer. The input
closes 1.5 s after the key is released and opens again on the next press.

Microphone access: `audio/driver/enable_input` (off on the web), `RECORD_AUDIO`
on Android (asked on the first press), and `NSMicrophoneUsageDescription`, the
audio-input entitlement and disabled library validation on macOS. On iOS the
audio session is Play and Record (`audio/general/ios/session_category`, sound
stays on the speaker) and the system asks for the microphone on the first press.

## Tests

- `game/tests/net/test_voice_native.gd`: mesh rules on fake links. With the
  library it also runs two real links over loopback (Opus tone, distance volume,
  silence, hiss). It is required in CI with `RFM_REQUIRE_NATIVE_VOICE=1`.
- `scripts/test-voice-interop.mjs`: a headless Godot client and two Chromium
  pages in one room. It covers both offer directions and audio both ways.
