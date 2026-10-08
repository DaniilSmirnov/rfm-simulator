extends SceneTree
const Granta = preload("res://scripts/granta_model.gd")

# Reproducible baked 3D asset for inspection and editing in Godot/Blender.
# Run: godot --headless --path game --script res://tools/export_granta.gd
func _initialize() -> void:
	var car = Granta.build()
	var state = GLTFState.new()
	var document = GLTFDocument.new()
	var err = document.append_from_scene(car, state)
	if err == OK:
		err = document.write_to_filesystem(state, "res://models/cars/granta/granta_black_blue.glb")
	if err != OK:
		push_error("Granta GLB export failed: %s" % err)
	car.free()
	quit(0 if err == OK else 1)
