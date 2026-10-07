# Low-poly spectators

Four editable GLB variants used by players, multiplayer peers, spectators and officials.
Body geometry: 948 / 900 / 996 / 1068 triangles (previously 2460 / 2584 / 2564 / 2840).
Each body has six mesh nodes: torso, head, two arms and two legs.
Beer and food are gameplay props attached separately at runtime.

Import into Blender for editing. Preserve direct child pivots `Head`, `LeftArm`,
`RightArm`, `LeftLeg`, `RightLeg`, dimensions and origin; forward is -Z, up is +Y.
Existing Godot gameplay animates these pivots, so no skeleton or baked clips are required.
Mesh resources are shared across instances; transforms are independent.

Optional reproducible source: `game/tools/character_source.gd`.
Regenerate with Godot 4.4.1:

```sh
Godot --headless --path game --script res://tools/export_characters.gd
Godot --headless --editor --path game --import
```

The generator is excluded from the Web export. Models are pre-imported by Godot;
no GLTF parsing or body geometry generation runs per character during gameplay.
