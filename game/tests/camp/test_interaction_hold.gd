extends "res://tests/harness.gd"
const Hold = preload("res://scripts/player/interaction_hold.gd")

class Packing extends RefCounted:
	var calls = 0
	func pack(_spot: Vector3, _remote: bool, rearrange: bool) -> bool:
		calls += int(rearrange)
		return true

class World extends RefCounted:
	var packing = Packing.new()

class Interaction extends RefCounted:
	var game = World.new()
	var node: Node3D
	var available = true
	var taps = 0
	func hold_target() -> Dictionary:
		return {"value": node} if available else {}
	func activate() -> void:
		taps += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
	var node = Node3D.new()
	root.add_child(node)
	var interaction = Interaction.new()
	interaction.node = node
	var hold = Hold.new()
	Input.action_press("interact")
	hold.press(interaction)
	hold.update(interaction, 0.2)
	Input.action_release("interact")
	hold.update(interaction, 0.01)
	check(interaction.taps == 1 and interaction.game.packing.calls == 0, "short release performs only the ordinary action")
	Input.action_press("interact")
	hold.press(interaction)
	hold.update(interaction, 0.7)
	hold.update(interaction, 1.0)
	Input.action_release("interact")
	hold.update(interaction, 0.01)
	check(interaction.taps == 1 and interaction.game.packing.calls == 1, "long hold picks up exactly once without triggering the short action")
	Input.action_press("interact")
	hold.press(interaction)
	interaction.available = false
	hold.update(interaction, 1.0)
	Input.action_release("interact")
	check(not hold.pending and interaction.game.packing.calls == 1, "losing the target cancels the gesture")
	node.queue_free()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	game.start_game()
	game.in_car = false
	game.stage.trees.clear()
	game.stage.rocks.clear()
	var spot: Vector3 = game.stage.clearings[0]
	game.walker = spot
	game.camp = Node3D.new()
	game.add_child(game.camp)
	game.camp.position = spot
	game.camp.set_meta("gear_owner", game.chair_owner())
	check(not game.packing.active() and game.packing.pack(spot, false, true), "long action can collect equipment before cleanup")
	check(game.camp == null and game.cargo.can_redeploy(), "pickup leaves exactly one redeployable item in hand")
	check(game.cargo.deploy("table", spot, 0), "picked up equipment can be placed again without visiting trunk")
	check(game.camp != null and not game.cargo.held.has(game.chair_owner()), "redeploy consumes carried item")
	check(game.packing.pack(spot, false, true), "same equipment can be picked up again")
	game.begin_placement("table")
	game.cancel_placement()
	check(game.cargo.can_redeploy(), "canceling placement does not lose carried equipment")
	game.cargo.held.clear()
	game.room.connected = true
	game.room.player_id = "guest"
	game.room.is_host = false
	game.camp = Node3D.new()
	game.add_child(game.camp)
	game.camp.position = spot
	check(game.packing.pack(spot, false, true) and game.camp != null and game.room.commands[-1].action == "rearrange", "guest requests pickup without speculative deletion")
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	finish()
