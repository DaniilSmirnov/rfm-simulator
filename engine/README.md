# Mini Web template

`web-template.zip` is the Godot 4.4.1 release Web template compiled for this demo.
It is checked against `manifest.json` before every export.
The exported WASM is 30.14 MiB decoded and 5.55 MiB in gzip.
Only the gzip file is deployed; `web/mini-loader.js` decodes it in the browser.
Do not set `Content-Encoding: gzip` for that file.

To rebuild the engine, use Godot's `4.4.1-stable` source, Emscripten 3.1.64,
copy `custom.py` into the source root, and run:

```sh
scons platform=web target=template_release lto=thin -j6
```

Copy `bin/godot.web.template_release.wasm32.nothreads.zip` here and update
the hashes in `manifest.json`. Full 3D and WAV audio are preserved; unused
modules and advanced text/GUI components are disabled.
Godot and third-party license notices are included alongside the template.
