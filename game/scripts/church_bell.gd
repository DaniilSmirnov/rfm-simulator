extends Node3D
const Props = preload("res://scripts/props.gd")
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
	audio.stream = bell_sound()
	audio.max_distance = 160
	audio.unit_size = 15
	audio.volume_db = -10
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
func bell_sound() -> AudioStreamWAV:
	# Original additive synthesis: no third-party sound assets.
	var rate = 22050
	var bytes = PackedByteArray()
	bytes.resize(rate * 4 * 2)
	for i in range(rate * 4):
		var t = float(i) / rate
		var sample = 0.0
		for partial in [1.0, 2.03, 2.71, 4.14]:
			sample += sin(TAU * 360 * partial * t) * exp(-t * (0.9 + partial * 0.3)) * 0.16
		bytes.encode_s16(i * 2, int(sample * minf(t * 120, 1.0) * 32767))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
