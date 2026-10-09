extends Resource
# Offline reference runs. Each row: lateral position, m/s, body slip, metre scale.
@export var schema = 1
@export var route_signature = ""
@export var sample_step = 1.0
@export var cuts = PackedFloat32Array()
@export var blends = PackedFloat32Array()
@export var reverse_blends = PackedFloat32Array()
@export var reverse_cuts = PackedFloat32Array()
@export var runs: Array[PackedFloat32Array] = []
@export var labels = PackedStringArray()
