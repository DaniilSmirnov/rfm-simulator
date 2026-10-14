extends RefCounted
# Living details of «Майншафт» (mineshaft.gd): mobs of kangaroos grazing in the
# grass that bound away from people, flocks of white cockatoos wheeling over
# the gum trees and the homestead windmill turning in the wind. Local scenery
# only: gameplay state stays in stage.gd and is the same for every client.
const Props = preload("res://scripts/core/props.gd")
const LIFE_RANGE = 110.0
const FLEE_DISTANCE = 15.0
const KangarooModel = preload("res://scripts/stages/mineshaft/kangaroo_model.gd")
# Station, side and distance from the road of each kangaroo mob.
const MOBS = [[90.0, 1.0, 46.0], [260.0, -1.0, 38.0], [400.0, 1.0, 42.0], [540.0, 1.0, 52.0], [690.0, 1.0, 46.0], [790.0, -1.0, 40.0]]

var stage
var biome
var root: Node3D
var rng = RandomNumberGenerator.new()
var clock = 0.0
var kangaroos: Array[Dictionary] = []
var cockatoos: Array[Dictionary] = []
var rotor: Node3D
var hops = 0

func build(owner_stage, owner_biome) -> void:
	stage = owner_stage
	biome = owner_biome
	rng.seed = 26101320
	root = Node3D.new()
	root.name = "OutbackLife"
	stage.add_child(root)
	_build_kangaroos()
	_build_cockatoos()
	rotor = stage.get_node_or_null("Homestead/WindmillRotor")

func _build_kangaroos() -> void:
	for mob in MOBS:
		var s: float = mob[0]
		var home = stage.at(s) + stage.side(s) * float(mob[1]) * float(mob[2])
		# Graze away from spectators and buildings: step further out if needed.
		for step in range(4):
			if biome.scenery.open_ground(home, 18.0, 10.0):
				break
			home += stage.side(s) * float(mob[1]) * 12.0
		for i in range(rng.randi_range(3, 5)):
			var roo = KangarooModel.build(i == 0)
			root.add_child(roo)
			var p = home + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
			p.y = stage.ground(p)
			roo.position = p
			var heading = rng.randf() * TAU
			roo.rotation.y = heading
			kangaroos.append({"node": roo, "home": home, "target": p, "heading": heading, "wait": rng.randf_range(0.0, 6.0), "phase": 0.0, "speed": 0.0, "afraid": false})

func _build_cockatoos() -> void:
	for flock in range(3):
		var s = 150.0 + flock * 250.0
		var center = stage.at(s) + stage.side(s) * (36.0 if flock % 2 == 0 else -40.0)
		center.y = stage.ground(center) + 18.0 + flock * 4.0
		for i in range(7):
			var bird = Node3D.new()
			bird.name = "Cockatoo"
			Props.faceted(bird, Vector3.ZERO, Vector3(0.14, 0.12, 0.38), Color("f3f1ea"), 5, 2)
			Props.box(bird, Vector3(0, 0.1, -0.15), Vector3(0.03, 0.1, 0.06), Color("f2cf3a"))
			var wings: Array = []
			for side in [-1.0, 1.0]:
				var hinge = Node3D.new()
				bird.add_child(hinge)
				Props.box(hinge, Vector3(side * 0.3, 0, 0), Vector3(0.55, 0.02, 0.18), Color("ece9df"))
				hinge.set_meta("side", side)
				wings.append(hinge)
			root.add_child(bird)
			cockatoos.append({"node": bird, "wings": wings, "center": center, "radius": rng.randf_range(12.0, 26.0), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.2, 0.3) * (1.0 if flock % 2 == 0 else -1.0), "height": rng.randf_range(-2.5, 2.5)})

func update(delta: float, focus: Vector3) -> void:
	var dt = clampf(delta, 0.0, 0.1)
	clock += dt
	for roo in kangaroos:
		_update_kangaroo(roo, dt, focus)
	_update_cockatoos()
	if rotor != null:
		rotor.rotation.z = fmod(clock * 1.6, TAU)

func _update_kangaroo(roo: Dictionary, dt: float, focus: Vector3) -> void:
	var node: Node3D = roo.node
	var offset = node.position - focus
	offset.y = 0.0
	if offset.length() > LIFE_RANGE:
		return
	roo.afraid = offset.length() < FLEE_DISTANCE
	roo.wait = float(roo.wait) - dt
	if roo.afraid:
		roo.target = node.position + offset.normalized() * 12.0
	elif roo.wait <= 0.0 or node.position.distance_to(roo.target) < 0.8:
		roo.wait = rng.randf_range(4.0, 12.0)
		roo.target = roo.home + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
	var to_target: Vector3 = roo.target - node.position
	to_target.y = 0.0
	var desired = (7.5 if roo.afraid else 2.2) if to_target.length() > 0.8 else 0.0
	roo.speed = move_toward(float(roo.speed), desired, dt * 6.0)
	if to_target.length() > 0.05:
		roo.heading = lerp_angle(float(roo.heading), atan2(to_target.x, to_target.z), 1.0 - exp(-dt * 4.0))
	var forward = Vector3(sin(roo.heading), 0, cos(roo.heading))
	var ground: float = stage.ground(node.position)
	var hop = 0.0
	if float(roo.speed) > 0.05:
		node.position += forward * float(roo.speed) * dt
		ground = stage.ground(node.position)
		var before = float(roo.phase)
		roo.phase = before + dt * (1.6 + float(roo.speed) * 0.25)
		if int(roo.phase) != int(before):
			hops += 1
		hop = absf(sin(float(roo.phase) * PI)) * (0.25 + float(roo.speed) * 0.08)
	else:
		roo.phase = 0.0
	node.position.y = ground + hop
	KangarooModel.pose(node, hop > 0.12)
	# Models face -z: turn them to the heading.
	node.rotation = Vector3(0, float(roo.heading) + PI, 0)

func _update_cockatoos() -> void:
	for bird in cockatoos:
		var node: Node3D = bird.node
		var angle = float(bird.phase) + clock * float(bird.speed)
		var center: Vector3 = bird.center
		node.position = center + Vector3(cos(angle) * float(bird.radius), float(bird.height) + sin(clock * 0.7 + float(bird.phase)) * 1.2, sin(angle) * float(bird.radius))
		var tangent = Vector3(-sin(angle), 0, cos(angle)) * signf(float(bird.speed))
		node.rotation.y = atan2(-tangent.x, -tangent.z)
		node.rotation.z = -0.3 * signf(float(bird.speed))
		var flap = sin(clock * 11.0 + float(bird.phase) * 3.0)
		for wing in bird.wings:
			wing.rotation.z = float(wing.get_meta("side")) * flap * 0.6
