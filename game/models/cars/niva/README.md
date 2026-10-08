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

## Integration

The original `niva_low_poly.obj` and `.mtl` remain as the approved reference.
Two additional generated files provide moving-part geometry:

- `niva_body_static.obj` — static shell, lights, glass and trim; excludes tailgate and rotating wheels
- `niva_tailgate.obj` — only the upper rear door panel with opaque rear window and lower seal
- `niva_wheels.obj` — four rubber wheels and matching hubs, split into rotating pivots at runtime

`game/scripts/niva_asset.gd` creates `PlayerCar_2` with a separate `TrunkHinge/NivaTailgate_Lid` while reusing the standard inventory and auto-open behavior. The source mesh uses forward `-Z`. The body and wheels remain stationary with respect to the hinge; wheels rotate as the vehicle moves.

## Verification

Run Godot import, then `npm test` to execute `verify_niva_asset.gd`, `test_niva_integration.gd`, and existing `test_trunk.gd`. The tests assert that only the rear door rotates, all cargo is accessible, and wheels animate with driving. Visually inspect the rear panel's seams and alignment in a renderer before publishing a release.
