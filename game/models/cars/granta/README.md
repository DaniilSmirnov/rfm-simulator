# Black-blue compact sedan

The Granta-inspired sedan is defined in `res://scripts/granta_model.gd`, independently of the shared vehicle factory. It is an original low-poly reinterpretation without logos or trademark details.

To bake an editable asset, run from the repository root:

```sh
godot --headless --path game --script res://tools/export_granta.gd
```

The output is `granta_black_blue.glb` in this folder. Gameplay currently uses the source model directly to preserve compatibility with `RallyProps.add_player_trunk` and per-part trunk clipping. The exporter does not replace the live source automatically.
