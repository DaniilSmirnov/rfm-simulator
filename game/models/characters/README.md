# Reference-style spectators

Four editable GLB variants used by players, multiplayer peers, spectators and officials.
Body geometry: 11172 / 9900 / 11628 / 10884 triangles. Visual fidelity takes priority over a polygon budget.
Smooth shading, rounded capsule head and torso, large eyes, thin limbs and rounded fingers follow the supplied cartoon reference; all original skin, clothing and hair profiles are retained.
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
