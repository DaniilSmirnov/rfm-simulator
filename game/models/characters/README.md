# Reference-style spectators

Four editable GLB variants used by players, multiplayer peers, spectators and officials,
plus the same four looks in each outfit of `scripts/people/character_profiles.gd`
(`spectator_winter_<n>.glb`: puffer jacket, scarf, mittens, insulated trousers, snow
boots and a warm hat; worn on snowy stages, see `stage_biome.gd` `outfit()`).
Body geometry: 11172 / 9900 / 11628 / 10884 triangles. Visual fidelity takes priority over a polygon budget.
Smooth shading, rounded capsule head and torso, large eyes, thin limbs and rounded fingers follow the supplied cartoon reference; all original skin, clothing and hair profiles are retained.
Each body has ten mesh nodes: torso, head, upper arms, forearms with hands,
thighs and shins with boots.
Beer and food are gameplay props attached separately at runtime.

Import into Blender for editing. Preserve the pivots `Head`, `LeftArm`, `RightArm`
(shoulders) with `LeftArm/LeftForearm`, `RightArm/RightForearm` (elbows, 0.22 m
below), `LeftLeg`, `RightLeg` (hips) with `LeftLeg/LeftShin`, `RightLeg/RightShin`
(knees, 0.33 m below), dimensions and origin; forward is -Z, up is +Y.
`scripts/people/character_rig.gd` poses these pivots, so no skeleton or baked clips are
required. Held items (beer, food, flag, clipboard) hang from the forearms.
Mesh resources are shared across instances; transforms are independent.

Optional reproducible source: `game/tools/assets/character_source.gd`.
Regenerate with Godot 4.4.1:

```sh
Godot --headless --path game --script res://tools/assets/export_characters.gd
Godot --headless --editor --path game --import
```

The generator is excluded from the Web export. Models are pre-imported by Godot;
no GLTF parsing or body geometry generation runs per character during gameplay.
