import hashlib
import json
from pathlib import Path
import zipfile

path = Path("engine/web-template.zip")
with zipfile.ZipFile(path) as archive:
    names = [name for name in archive.namelist() if name.endswith(".wasm")]
    if len(names) != 1:
        raise RuntimeError("Expected exactly one WebAssembly engine")
    wasm = archive.read(names[0])
manifest_path = Path("engine/manifest.json")
manifest = json.loads(manifest_path.read_text())
manifest["template_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
manifest["wasm_sha256"] = hashlib.sha256(wasm).hexdigest()
manifest["physics_3d"] = True
custom = Path("engine/custom.py").read_text()
manifest["websocket"] = any(line.replace(" ", "") == "module_websocket_enabled=True" for line in custom.splitlines())
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Physics-enabled mini engine: {len(wasm) / 1048576:.2f} MiB decoded, {path.stat().st_size / 1048576:.2f} MiB ZIP")
