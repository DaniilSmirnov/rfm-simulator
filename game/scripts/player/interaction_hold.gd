extends RefCounted
# Only equipment defers its ordinary action until release. Long presses never
# also drink/eat/sit, and changing the target cancels the gesture.
const SECONDS = 0.65
var node: Node3D
var elapsed = 0.0
var pending = false
var origin = Vector3.ZERO

func cancel() -> void:
	pending = false
	node = null
	elapsed = 0.0

func press(interaction) -> void:
	if pending:
		return
	var target: Dictionary = interaction.hold_target()
	if target.is_empty():
		interaction.activate()
		return
	node = target.value
	origin = node.global_position
	elapsed = 0.0
	pending = true

func update(interaction, delta: float) -> void:
	if not pending:
		return
	var target: Dictionary = interaction.hold_target()
	if not is_instance_valid(node) or target.get("value") != node or node.global_position.distance_to(origin) > 0.15:
		cancel()
		return
	if not Input.is_action_pressed("interact"):
		cancel()
		interaction.activate()
		return
	elapsed += delta
	if elapsed >= SECONDS:
		var spot = node.global_position
		cancel()
		interaction.game.packing.pack(spot, false, true)
