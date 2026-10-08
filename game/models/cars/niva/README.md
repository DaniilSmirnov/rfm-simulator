# Niva v6 — asset staging for Rally Fans Simulator

This directory stages the repaired low-poly Niva model **without replacing the existing playable vehicle yet**. The source is the user-provided `lada_niva_1600.glb`, reworked into version 6.

## Model files

The following v6 files have been committed to this directory (the preview is optional):

- `niva_low_poly.obj` — model, 15,504 triangles, 38 named object groups
- `niva_low_poly.mtl` — flat game-style materials (21 materials)
- `niva_geometry_v6_preview.png` — optional visual reference

Reference SHA-256 checksums (for verifying the exact approved v6 geometry):

```text
niva_low_poly.obj  330843ef21a09f4255f31b9fbb438992d28a802bf993b5c318890872eae23647
niva_low_poly.mtl  6ec585900a845baeda825c8b374db507a62f9fea368cb7a9a2cb0de84940419e
```

**Coordinates:** forward = `-Z`, up = `+Y`, center approximately at the origin. Keep OBJ and MTL together so Godot can import their material references.

## Acceptance checklist before replacing vehicle 2

1. Confirm the committed OBJ and MTL still match the SHA-256 hashes above.
2. Run the Godot editor import and then `godot --headless --path game --script res://tools/verify_niva_asset.gd`. The script must exit 0, confirm face counts/bounds, and find the materials file.
3. Inspect a preview using `NivaAsset.create_preview()` from `res://scripts/niva_asset.gd`: round lamps face forward, front is `-Z`, side/rear window material is opaque, no hood cargo.
4. Convert the rear door into a separately animated part, without rotating the rear row, side panels, roof, or spare wheel. Validate opened/closed trunk and cargo placement.
5. Recheck wheel motion, car dimensions, camera framing, selection, multiplayer replication, and collision against the current variant 2.
6. Only after these checks: route `RallyProps.player_car(2)` to the imported Niva and cover it with regression tests. Do not remove the procedural fallback prematurely.

No gameplay code is switched in this preparatory branch.
