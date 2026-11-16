extends SceneTree
# Ground height inside each village shop and furnished house relative to its
# floor: anything above ~0.1 m pokes through the floor.
#   godot --headless --path game --script res://tools/profile/shop_ground_probe.gd
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.select_stage(2)
	game.start_game()
	for node in game.stage.find_children("*", "Node3D", true, false):
		if not node.has_meta("shop_room") and not node.get_meta("room", false):
			continue
		var worst = -99.0
		for x in [-2.5, 0.0, 2.5]:
			for z in [1.0, 3.0, 5.0, 7.5]:
				var p = node.global_transform * Vector3(x, 0, z)
				worst = maxf(worst, game.stage.ground(p) - node.global_position.y)
		print("%s %s max ground above base: %.2f" % [node.name, node.get_meta("shop_room", "room"), worst])
	quit()
