# Rally native voice extension

This is the native audio backend for the radio feature. It is intentionally a
separate GDExtension: browser builds continue to use `web/voice-chat.js`, while
desktop/mobile builds use `RallyVoicePeer` with the same room signaling
envelopes (`space=voice`, offer/answer/candidate/bye).

Build with a Godot 4.4-compatible `godot-cpp` checkout:

```sh
cmake -S native/voice -B native/voice/build -DGODOT_CPP_DIR=/path/to/godot-cpp
cmake --build native/voice/build --config Release
```

The checked-in C++ surface is deliberately small. The next implementation
step is wiring libdatachannel's Opus media transport and Godot's microphone
capture/playback callbacks; no browser APIs or JavaScriptBridge are used by
this backend.
