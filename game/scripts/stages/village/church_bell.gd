extends Node3D
const Props = preload("res://scripts/core/props.gd")
const SoundBank = preload("res://scripts/core/sound_bank.gd")
var pivot: Node3D
var rope: MeshInstance3D
var handle: MeshInstance3D
var audio: AudioStreamPlayer3D
var elapsed = 4.0
var serial = 0
func build() -> void:
	set_meta("unbatched", true)
	pivot = Node3D.new()
	add_child(pivot)
	Props.cylinder(pivot, Vector3(0, -0.45, 0), 0.65, 0.3, 0.9, Color("a38a56"), 16)
	Props.cylinder(pivot, Vector3(0, -0.95, 0), 0.09, 0.09, 0.3, Color("554835"), 8)
	rope = Props.cylinder(self, Vector3(0.35, -1.45, 0), 0.018, 0.018, 2.7, Color("b7a47b"), 6)
	handle = Props.cylinder(self, Vector3(0.35, -2.7, 0), 0.06, 0.06, 0.18, Color("73513b"), 8)
	audio = AudioStreamPlayer3D.new()
	add_child(audio)
	audio.stream = SoundBank.stream("church-bell")
	audio.max_distance = 160
	audio.unit_size = 15
	audio.volume_db = -13
func handle_position() -> Vector3:
	return to_global(Vector3(0.35, -2.7, 0))
func pull(player: Vector3) -> bool:
	if elapsed < 2.5 or player.distance_to(handle_position()) > 2.0:
		return false
	serial += 1
	elapsed = 0
	audio.play()
	return true
func snapshot() -> Dictionary:
	return {"serial": serial, "elapsed": elapsed}
func apply_snapshot(data: Dictionary) -> void:
	var incoming = int(data.get("serial", 0))
	if incoming <= serial: return
	serial = incoming
	elapsed = clampf(float(data.get("elapsed", 4)), 0, 4)
	if elapsed < 2.5: audio.play(elapsed)
func _process(delta: float) -> void:
	elapsed = minf(4, elapsed + delta)
	if pivot == null: return
	pivot.rotation.z = sin(elapsed * 7) * 0.45 * exp(-elapsed * 1.2) if elapsed < 4 else 0.0
	var pull_offset = sin(minf(elapsed / 0.5, 1.0) * PI) * 0.25
	rope.position.y = -1.45 - pull_offset
	handle.position.y = -2.7 - pull_offset
