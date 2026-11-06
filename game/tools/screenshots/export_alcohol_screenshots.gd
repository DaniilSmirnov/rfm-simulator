extends SceneTree
# Screenshots of every piece of alcohol / tobacco content, for the age-rating
# questionnaire. One stage per run:
#   xvfb-run godot --path game --rendering-driver opengl3 --resolution 1280x720 \
#     --script res://tools/screenshots/export_alcohol_screenshots.gd -- --stage=0 --out=/tmp/shots
const CharacterRig = preload("res://scripts/people/character_rig.gd")
var out = "/tmp"
var game: Node

func _initialize() -> void:
	call_deferred("run")

func arg(name: String, fallback: String = "") -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--" + name + "="):
			return value.trim_prefix("--" + name + "=")
	return fallback

func snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("saved ", name)

func labels(node: Node, found: Array) -> void:
	if node is Label3D:
		found.append(node)
	for child in node.get_children():
		labels(child, found)

func run() -> void:
	out = arg("out", "/tmp")
	root.size = Vector2i(1280, 720)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.room.set_process(false)
	var stage = int(arg("stage", "0"))
	game.select_stage(stage)
	await game.start_game()
	var mode = arg("mode", "camp")
	if mode == "camp":
		await camp()
	elif mode == "village":
		await village()
	await game._shutdown_audio()
	game.queue_free()
	await process_frame
	quit()

func camp() -> void:
	game.in_car = false
	game.walker = game.stage.clearings[0]
	game.walker.y = game.stage.ground(game.walker)
	game.view_yaw = 0
	game.place_table()
	game.place_chairs()
	game.toast_label.hide()
	# Stand at the table, looking at it: the "Выпить пиво" prompt.
	var table: Node3D = game.camp
	game.walker = table.position + Vector3(0, 0, 1.3)
	game.walker.y = game.stage.ground(game.walker)
	game.view_yaw = 0
	game.view_pitch = -0.45
	game._update_camera(1.0)
	game._update_hud()
	await snap("01-table-drink-prompt")
	# Drinking a beer: can in hand, health warning on screen.
	game.drink_beer()
	game._update_drinking(0.8)
	game._update_camera(0.1)
	game._update_hud()
	await snap("02-drinking-beer-warning")
	game._update_drinking(1.1)
	game._update_camera(0.1)
	game._update_hud()
	await snap("03-drinking-beer-sip")
	game._update_drinking(5.0)
	game.toast_label.show()
	# Thirty beers: the player collapses and has to wait three minutes.
	game.beers = 29
	game.drink_time = -1
	game.beer_timer = 0
	game.drink_beer()
	game._update_drinking(3.0)
	game.sober_remaining = game.SOBER_SECONDS
	game.collapse_time = 0.8
	game._update_camera(0.1)
	game._update_hud()
	await snap("04-heavy-intoxication-collapse")
	game.beers = 0
	game.drunk_strength = 0
	game.sober_remaining = 0
	game.collapse_time = 0
	game.sobriety_panel.hide()
	game.consumption_warning.hide()
	game._update_hud()
	# Not alcohol: a poisonous mushroom from the grill inverts the colours
	# for ten seconds, with its own warning.
	game.view_pitch = -0.2
	game._update_camera(0.1)
	game.mushroom_effect.trigger(1)
	game.show_consumption_warning("mushroom")
	game.toast_label.show()
	game.toast("Отравление! Движение замедлено на 10 секунд.")
	game._update_hud()
	await snap("09-poison-mushroom-warning")
	game.mushroom_effect.update(20.0)
	game.consumption_warning.hide()
	game._update_hud()
	for panel in game.hud_panels: panel.hide()
	game.title_label.hide()
	game.toast_label.hide()
	game.crosshair.hide()
	# NPC spectators drinking beer.
	var people: Array = game.spectators.people
	var shown = 0
	for person in people:
		if shown >= 2:
			break
		person.can.visible = true
		CharacterRig.pose(person.avatar, {"gait": 0, "time": 0.0, "seed": float(person.id), "arms": "drink", "lift": 0.85})
		shown += 1
	if not people.is_empty():
		var a: Node3D = people[0].avatar
		var fwd = -a.global_transform.basis.z
		game.camera.position = a.global_position + fwd * 3.2 + Vector3(1.2, 1.7, 0)
		game.camera.look_at(a.global_position + Vector3(0, 1.4, 0))
		await snap("05-spectators-drinking-beer")

func village() -> void:
	for panel in game.hud_panels: panel.hide()
	game.title_label.hide()
	game.toast_label.hide()
	game.crosshair.hide()
	game.camera.fov = 65
	var found = []
	labels(game.stage, found)
	for l in found:
		print("LABEL ", l.text, " ", l.global_position)
	var wanted = {"TABAC · PRESSE": "06-village-tabac-shop", "CAVE À VINS": "07-village-wine-shop", "CAVE COOPÉRATIVE": "08-village-winery"}
	for l in found:
		if wanted.has(l.text):
			var b: Basis = l.global_transform.basis
			# Labels face +Z after the PI turn; stand in front of the sign.
			var front = b.z.normalized()
			var dist = 9.0 if l.text != "CAVE COOPÉRATIVE" else 22.0
			game.camera.position = l.global_position + front * dist + Vector3(0, -0.6, 0) + b.x * 2.0
			game.camera.look_at(l.global_position + Vector3(0, -1.2, 0))
			await snap(wanted[l.text])
			wanted.erase(l.text)
