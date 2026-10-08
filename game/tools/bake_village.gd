extends SceneTree
const Stage = preload("res://scripts/stage.gd")
const BakedVillage = preload("res://scripts/baked_village.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var started = Time.get_ticks_msec()
	var stage = Stage.new(2)
	stage.capture_bake_buffers = true
	root.add_child(stage)
	stage.build(false)
	DirAccess.make_dir_recursive_absolute("res://generated")
	var error = BakedVillage.save(stage, "res://generated/village.scn")
	stage.free()
	if error != OK:
		push_error("Village bake failed: %s" % error_string(error))
		quit(1)
		return
	print("VILLAGE_BAKED elapsed_ms=", Time.get_ticks_msec() - started, " bytes=", FileAccess.get_file_as_bytes("res://generated/village.scn").size())
	quit()
