# Camping hatchback model

The camping hatchback (player car 8, a low-poly wedge five-door with an inflatable boat on the roof) has no model files. It is built at load time by `game/scripts/cars/camping_hatchback_model.gd` from cross-sections, lamps, trim and boat geometry written by hand for this project, and is called from `player_car_camping_hatchback()` in `game/scripts/core/props.gd`.

Provenance: original work for Rally Fans Simulator. No third-party mesh, texture or measurement file was used, and the model carries no logos, badges or trademarks. It replaces an earlier OBJ conversion of a user-supplied third-party model, which has been removed together with its license obligation.

Body, glass, trim and rear lamps are separate single-surface meshes so `RallyProps.add_player_trunk()` can cut the rear hatch (from `trunk_lid_start_z = 1.20`) out of each one. Wheels use `CarParts.wheel()` and roll about `LEFT`; the roof rack and boat stay fixed under `CarModelDetails`.
