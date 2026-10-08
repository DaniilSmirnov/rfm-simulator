# Nature meshes

These are standalone Godot mesh resources for procedural nature scenery.
The geometry previously created in `stage.gd` and `vineyard.gd` is now
loaded from these files. Placement, per-instance coloration, instancing,
collision, and harvesting remain in the gameplay scripts.

- `tree_trunk.tres`, `tree_crown_*.tres`: four shared low-poly tree layers
- `thuja_*.tres`: the village hedge/conifer layers
- `grass.obj`: the original five-blade grass geometry as a text 3D model
- `stone.tres`, `boulder.tres`: small and large low-poly rocks
- `bush.tres`, `roadside_bush.tres`, `bush_stem.tres`, `berry.tres`: shrubs and berries
- `mushroom_cap.tres`, `mushroom_stem.tres`: edible and poisonous mushroom geometry

The resources deliberately contain geometry only. Materials and instance colors
are still applied by Godot MultiMesh so one asset can be reused on all stages.

Unlike NPC character models, these objects are not pre-baked GLB scenes:
`.tres` meshes and the OBJ grass model are editor-readable source assets,
which keep instanced runtime meshes and harvesting indices unchanged.
