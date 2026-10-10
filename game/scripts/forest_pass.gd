extends "res://scripts/stage_biome.gd"
# «Лесной перевал»: a gravel stage climbing gently through a conifer forest,
# with four spectator clearings above the road reached by short switchback
# trails. Most defaults of stage_biome.gd describe this stage.

func route(s: float) -> Vector3:
	return Vector3(sin(s / 90.0) * 38.0 + sin(s / 38.0) * 9.0, 5.0 + s * 0.024 + sin(s / 58.0) * 3.7, -s)

func configure() -> void:
	for s in [140.0, 310.0, 505.0, 690.0]:
		var direction_sign = 1.0 if s < 500 else -1.0
		var lookout = stage.at(s) + stage.side(s) * direction_sign * 27.0
		# The spectator clearings sit above the road. A short switchback makes
		# them reachable on foot without opening a large treeless corridor.
		lookout.y = stage.at(s).y + 5.2 + sin(s * 0.03) * 0.8
		stage.clearings.append(lookout)
		var road_entry = stage.at(s) + stage.side(s) * direction_sign * (stage.WIDTH * 0.5 + 1.8)
		var first_turn = stage.at(s - 9.0) + stage.side(s) * direction_sign * 10.5
		first_turn.y = stage.at(s - 9.0).y + 1.7
		var second_turn = stage.at(s + 7.0) + stage.side(s) * direction_sign * 19.0
		second_turn.y = stage.at(s + 7.0).y + 3.3
		stage.trails.append({"points": [road_entry, first_turn, second_turn, lookout], "width": 2.2})

# Broad crests plus broken ruts; deterministic across all room members.
func roughness(s: float) -> float:
	return sin(s * 0.46) * 0.075 + sin(s * 1.13) * 0.035 + pow(maxf(0, cos((s - 32.0) * TAU / 46.0)), 10) * 0.55

# Forest hills and a roadside drainage ditch, interrupted where trails cross.
func land_relief(pos: Vector3, distance: float) -> float:
	var hills = (sin(pos.x * 0.043 + pos.z * 0.017) * 1.5 + sin(pos.z * 0.063 - pos.x * 0.031) * 0.85 + sin(pos.x * 0.115) * sin(pos.z * 0.087) * 0.55) * smoothstep(10.0, 24.0, distance)
	var ditch = (1.0 - smoothstep(0.45, 1.9, absf(distance - 6.4))) * 0.85
	ditch *= smoothstep(2.2, 4.0, stage.trail_distance(pos, 4.0))
	return hills - ditch

func terrain_tile_step(p: Vector3) -> float:
	return 2.0 if stage.road_distance(p) < 12.0 else 4.0

func terrain_color(v: Vector3) -> Color:
	var patch = (sin(v.x * 0.065) * sin(v.z * 0.041) + 1.0) * 0.5
	var color = Color("514a32").lerp(Color("485c36"), patch)
	if stage.road_distance(v) > 4.5 and stage.road_distance(v) < 8:
		color = color.darkened(0.16)
	return color

func road_ruts(_s: float) -> bool:
	return true

func forest_tree_count() -> int:
	return 7600

func build_details(cooperative: bool) -> void:
	await stage.build_woodland(cooperative)

func build_horizon() -> void:
	stage.build_ridges()
