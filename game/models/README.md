# Camping hatchback OBJ asset for Rally Fans Simulator

Source: user-supplied `vaz-2112_low-poly.glb`, with unbranded flat materials and low-poly inflatable roof boat.

All eight OBJ files are in metres, Y up, vehicle front toward -Z (Godot orientation). Materials are in `camping_hatchback.mtl`. Place ALL files under:

`game/models/cars/camping_hatchback/`

The loader is `game/scripts/camping_hatchback_asset.gd`, invoked by the updated `player_car_camping_hatchback()` factory in `game/scripts/props.gd`. When models are absent, the existing procedural asset remains in use.

Parts: body, glass, lights, trim, wheels_rubber, wheels_metal, boat, rack. The boat model is separate and sits above the roof, with visible seats and cross-tube edges. Truck compartment remains driven by the existing `add_player_trunk` implementation.

Check import using Godot 4.4 and verify model orientation / roof clearance in the selection screen. The original license for the user-provided model still applies.
