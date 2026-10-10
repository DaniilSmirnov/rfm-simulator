# Lightweight menu, resource reuse and staged preparation

Normal Web/VK and desktop clients open the menu without building the terrain,
forest, stage objects, spectators or player car. Menu cards load the selected
480×240 WebP image; they no longer allocate SubViewports or preview cameras.
There is one image per car and per stage (`car_N`, `stage_N`, `backdrop_N`), generated from the actual game.
The menu background uses a separately captured 1280×720 panorama of the selected
stage, scaled to cover desktop/mobile viewports. Only the selected image is held;
it is released when play begins. It does not intercept input or appear over the
pause/gameplay view. Regenerate with `res://tools/export_stage_backdrops.gd`.

Selecting locked content still shows its image; existing entitlement checks block
starting it. A guest can still borrow the host's stage.

On successful room creation/join, `start_game()` awaits world preparation before
positioning the assigned car and publishing multiplayer state. Existing browser
room heartbeats continue while construction runs. Preparation reports terrain,
road, forest/environment, stage objects, officials/signs, spectators/camp, car and
completion. Percentages are stage milestones, not byte or time estimates.
Terrain rows, forest/detail loops, village construction and camp creation yield
frames; stage transitions yield two frames for UI layout and drawing. Selection
and duplicate starts are blocked while preparation is active.

`RallyProps` shares immutable materials by exact colour and primitive meshes by
exact dimensions/tessellation. Each of the four caches holds at most 256 resources;
additional unique resources are uncached. Static caches survive scene reloads but
cannot grow beyond their limits. `material()` still creates a private material;
`unique_material()` copies a primitive's material before independent mutation.
Police/judge beacons, city windows, flames and cooking surfaces use private copies.
Future code must copy a shared primitive material before changing it and must not
mutate a cached mesh. This change preserves scene detail and seeded geometry.

Headless tests and native `--script`, `--capture`, `--smoke-test` fixtures retain
synchronous construction. Tests and preview tools can set `defer_world = true`
before adding the scene to exercise the normal deferred path.

## Verification

- `test_resource_cache.gd`: reuse identity, precise shape keys, independent cooking
  colours and hard limits under hundreds of unique dimensions/colours.
- `test_world_loading.gd`: no world allocations/render targets in menu, all
  thumbnails, locked entry, actual yielded frames, stage reporting, duplicate
  start guards, deterministic forest/village collision/collectible geometry and
  guest handshake with borrowed stage and assigned lane.
- Existing lobby, VK access, room, cooking, officials, city/vineyard and trunk
  tests cover interactions affected by sharing and staged construction.
- `memory_preview.gd`: desktop/mobile menu and loading screenshots in CI's
  `visual-previews` artifact.
- Combined standalone/VK build and platform isolation checks.

No browser process-RAM reduction percentage has been measured. Follow-up profiling
should compare menu, each stage, repeated entry/return and peak preparation memory
on the same browser/device. Engine heap reservation and terrain's temporary
SurfaceTool buffers are separate remaining sources of memory consumption.

## Regenerate thumbnails

After changes to car or stage appearance, run with a graphical Godot 4.4.1 renderer:

```sh
godot --path game --script res://tools/export_menu_previews.gd
```

The generator renders offscreen from the game geometry and overwrites
`game/textures/previews/*.webp`; it is excluded from Web exports.
