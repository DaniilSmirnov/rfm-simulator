extends RefCounted
const Hitbox = preload("res://scripts/cars/car_hitbox.gd")
# A prop is hit once per contact episode, even while a car crosses its collider.
const SMALL_MASS = 15.0
const BLOCKING_MASS = 500.0
const RELEASE_TIME = 0.25

static func resolve(stage, motion, start: Vector3, end: Vector3, delta: float, car: Dictionary = {}) -> Dictionary:
	if car.is_empty(): car = Hitbox.shape(Hitbox.player(0), 0)
	for key in motion.prop_contacts.keys():
		motion.prop_contacts[key] -= delta
		if motion.prop_contacts[key] <= 0:
			motion.prop_contacts.erase(key)
	var result = {"position": end, "hits": [], "closing": 0.0, "blocked": false}
	var ignored: Array = []
	while true:
		var hit: Dictionary = Hitbox.solids(stage.solids, start, end, car, ignored)
		if hit.is_empty():
			return result
		var prop: Dictionary = {}
		if hit.get("prop", "") != "":
			for candidate in stage.solids.movables:
				if candidate.key == hit.prop and is_instance_valid(candidate.node):
					prop = candidate
					break
		var velocity: Vector3 = motion.velocity
		var anchored = not prop.is_empty() and bool(prop.node.get_meta("prop_anchored", prop.anchored))
		if prop.is_empty() or float(prop.mass) >= BLOCKING_MASS or (anchored and velocity.length() < 5.0):
			result.position = hit.position
			result.blocked = true
			result.closing = maxf(result.closing, velocity.length())
			if velocity.length() > 0.001:
				result.hits.append({"hit": hit, "velocity": velocity})
			motion.velocity = Vector3.ZERO
			return result
		ignored.append(prop.node)
		var key: String = prop.key
		if not motion.prop_contacts.has(key):
			var small = float(prop.mass) <= SMALL_MASS and maxf(prop.box.size.x, prop.box.size.z) <= 1.4
			var loss = 0.0 if small else clampf(float(prop.mass) / 1500.0, 0.02, 0.15)
			motion.velocity *= 1.0 - loss
			result.closing = maxf(result.closing, velocity.length() * loss)
			result.hits.append({"hit": hit, "velocity": velocity})
		motion.prop_contacts[key] = RELEASE_TIME
	return result
