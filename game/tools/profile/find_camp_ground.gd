extends SceneTree
# Diagnostic: NPC camp gear (tables, grills, chairs, cars) whose feet are sunk
# into or hang above the drawn ground, and gear that moves or stays awake once
# play starts. Gaps are of the lowest and the highest foot, in metres.
# --headless --path game --script res://tools/profile/find_camp_ground.gd -- --stage=N [--frames=600] [--all=1]
const CampSite = preload("res://scripts/people/camp_site.gd")
# A lowest foot this far into or above the ground reads as sunk or floating.
const TOLERANCE = 0.05
# Gear left alone must not creep further than this once play starts.
const DRIFT = 0.05

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.split("=")[1]
	return fallback

func scan(game) -> Dictionary:
	var result = {}
	for record in game.stage.solids.movables:
		if not is_instance_valid(record.node) or not str(record.key).begins_with("npc:"): continue
		var body = record.node.get_node_or_null("PropBody")
		result[record.key] = {"gap": CampSite.clearance(game.stage, record.node), "at": record.node.global_position, "awake": body != null and not body.freeze and not body.sleeping}
	return result

func run() -> void:
	var index = int(arg("stage", "0"))
	var game = load("res://scripts/core/game.gd").new()
	game.defer_world = false
	root.add_child(game)
	await process_frame
	game.select_stage(index)
	game.rng.seed = 20261008
	await game.start_game()
	var before = scan(game)
	game.paused = false
	for i in range(int(arg("frames", "600"))):
		await physics_frame
	var after = scan(game)
	var bad_count = 0
	print("STAGE %d camp gear=%d" % [index, before.size()])
	for key in before:
		var a: Dictionary = before[key]
		var b: Dictionary = after.get(key, a)
		var moved: float = a.at.distance_to(b.at)
		var bad = absf(a.gap.x) > TOLERANCE or absf(b.gap.x) > TOLERANCE or moved > DRIFT or b.awake
		bad_count += int(bad)
		if bad or arg("all", "") != "":
			print("  %s %s start[%+.3f %+.3f] settled[%+.3f %+.3f] moved=%.3f awake=%s" % ["BAD" if bad else "ok ", key, a.gap.x, a.gap.y, b.gap.x, b.gap.y, moved, b.awake])
	print("STAGE %d bad=%d" % [index, bad_count])
	quit()
