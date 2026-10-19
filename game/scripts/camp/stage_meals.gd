extends RefCounted
# Fixed, already-cooked shared meals. Inventory lives on the stage nodes so
# rebuilding a stage starts a fresh batch; moving/repacking personal gear cannot refill it.
const Props = preload("res://scripts/core/props.gd")
const Model = preload("res://scripts/camp/cauldron_model.gd")
const Merge = preload("res://scripts/core/mesh_merge.gd")
const Loc = preload("res://scripts/ui/loc.gd")

static func build(parent: Node3D) -> Node3D:
	var pot = Model.build(parent, "kuyrdak")
	pot.name = "YurtKuyrdak"
	pot.add_to_group("stage_meals")
	pot.set_meta("servings", Props.FOOD_PORTIONS)
	Model.pose(pot, "ready", 1, Props.FOOD_PORTIONS, 0)
	# Keep the fill and steam independent of the baked yurt scenery.
	for portion in pot.get_node("Rice").get_children():
		if portion is Node3D and not portion is MeshInstance3D:
			Merge.bake(portion)
	Merge.bake(pot, "", ["Rice", "Steam", "Bubbles"])
	var fire = Props.campfire(pot)
	fire.name = "Fire"
	Merge.bake(fire, "", ["Flames"])
	pot.set_meta("unbatched", true)
	for mesh in pot.find_children("*", "GeometryInstance3D", true, false):
		mesh.visibility_range_end = 90
	return pot

func pots(game) -> Array:
	if game.stage == null or not game.stage.is_inside_tree():
		return []
	var result = game.get_tree().get_nodes_in_group("stage_meals").filter(func(node): return game.stage.is_ancestor_of(node))
	result.sort_custom(func(a, b): return str(a.get_path()) < str(b.get_path()))
	return result

func can_eat(game, source: int) -> bool:
	var sources = pots(game)
	return source >= 0 and source < sources.size() and int(sources[source].get_meta("servings", 0)) > 0 and game.actor_pos().distance_to(sources[source].global_position) <= 3.5

func consume(game, source: int) -> bool:
	if not can_eat(game, source):
		return false
	var pot = pots(game)[source]
	var remaining = int(pot.get_meta("servings")) - 1
	Model.pose(pot, "ready" if remaining else "exhausted", 1, remaining, game.elapsed)
	game.eaten = true
	game.toast(Loc.t("Куырдак удался. Осталось порций: %d/10.") % remaining)
	return true

func offers(game, items: Array, interaction) -> void:
	var sources = pots(game)
	for i in range(sources.size()):
		var remaining = int(sources[i].get_meta("servings", 0))
		interaction.offer(items, sources[i].global_position + Vector3.UP * 1.3, 0.65, 3.5, "plov" if remaining > 0 else "", Loc.t("Съесть куырдак · %d/10") % remaining if remaining > 0 else "Казан пуст", i)

func animate(game, time: float) -> void:
	for pot in pots(game):
		# Steam is animated only close enough to see it.
		if game.player_position().distance_squared_to(pot.global_position) > 10000:
			continue
		var remaining = int(pot.get_meta("servings", 0))
		Model.pose(pot, "ready" if remaining else "exhausted", 1, remaining, time)
		var flames = pot.get_node("Fire/Flames")
		for i in range(flames.get_child_count()):
			flames.get_child(i).scale.y = 0.85 + sin(time * 7 + i * 2) * 0.2

func snapshot(game) -> Array:
	return pots(game).map(func(pot): return int(pot.get_meta("servings", 0)))

func apply_snapshot(game, data: Array) -> void:
	var sources = pots(game)
	for i in range(mini(sources.size(), data.size())):
		var remaining = clampi(int(data[i]), 0, Props.FOOD_PORTIONS)
		Model.pose(sources[i], "ready" if remaining else "exhausted", 1, remaining, game.elapsed)
