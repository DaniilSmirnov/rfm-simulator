extends Node3D

var interaction = preload("res://scripts/interaction.gd").new()
var seated = false
var jump_height = 0.0
var jump_velocity = 0.0
const WALK_SPEED = 4.3
const RUN_SPEED = 7.2
const JUMP_SPEED = 5.5
const WALK_GRAVITY = 18.0
var seat_exit = Vector3.ZERO
var crosshair: Label

const Props = preload("res://scripts/props.gd")
const Stage = preload("res://scripts/stage.gd")
const Spectators = preload("res://scripts/spectators.gd")
var spectators: Node3D
const MiniMap = preload("res://scripts/minimap.gd")
var stage: RallyStage
var selected_stage = 0
var selected_car = 0
var selection_controls: VBoxContainer
var car_choice: HBoxContainer
var stage_choice: HBoxContainer
var stage_caption: Label
var world_environment: WorldEnvironment
var sunlight: DirectionalLight3D
var car: Node3D
var camera: Camera3D
var camp: Node3D
var grill: Node3D
var smoke: GPUParticles3D
var meat_prop: Node3D
var eat_time = -1.0
var eat_committed = false
const EAT_DURATION = 3.6
var beer_prop: Node3D
var avatar_variant = 0
var rope_mesh: MeshInstance3D
var recovery_ropes: Array = []
var recovery_links: Array = []
var recovery_helpers = 0
const Recovery = preload("res://scripts/recovery.gd")
var in_car = true
var heading = 0.0
var view_yaw = 0.0
var view_pitch = -0.12
var speed = 0.0
var condition = 100.0
var rock_impact_timer = 0.0
var last_pothole = -1
var walker = Vector3.ZERO
var playing = false
var dead = false
var finished = false
var paused = false
var has_chairs = false
var personal_chairs: Dictionary = {}
var personal_flags: Dictionary = {}
const FLAGS_PER_PLAYER = 3
var placement_kind = ""
var placement_preview: Node3D
var placement_yaw = 0.0
var placement_valid = false
var placement_material: StandardMaterial3D

func chair_owner() -> String:
	return room.player_id if room != null and room.connected else "local"

func has_personal_chair() -> bool:
	return personal_chairs.has(chair_owner())

func flag_owner() -> String:
	return chair_owner()

func flag_count(owner: String = "") -> int:
	var key = flag_owner() if owner == "" else owner
	return personal_flags.get(key, []).size()

func valid_furniture_spot(spot: Vector3, kind: String, ignored_owner: String = "") -> bool:
	if spectators != null and spectators.occupied(spot):
		return false
	if stage.road_distance(spot) < 6.0:
		return false
	if stage.urban and not stage.city.hit(spot, spot, 0.8, false).is_empty():
		return false
	if not stage.rock_hit(spot, spot, 0.8, false).is_empty():
		return false
	if stage.obstacle_hit(spot, spot, 0.8) >= 0:
		return false
	if kind != "table" and camp != null and spot.distance_to(camp.position) < 1.5:
		return false
	if kind != "grill" and grill != null and spot.distance_to(grill.position) < 1.4:
		return false
	for owner in personal_chairs:
		if kind == "chairs" and owner == (chair_owner() if ignored_owner == "" else ignored_owner):
			continue
		if spot.distance_to(personal_chairs[owner].position) < 1.1:
			return false
	for owner in personal_flags:
		for flag in personal_flags[owner]:
			if spot.distance_to(flag.position) < 1.0:
				return false
	return true

func begin_placement(kind: String) -> void:
	if seated:
		stand_up()
	if in_car or beers >= 30:
		toast("Для размещения выйди из машины и встань на ноги.")
		return
	cancel_placement()
	if kind == "flag" and flag_count() >= FLAGS_PER_PLAYER:
		toast("Можно поставить только три флага.")
		return
	placement_kind = kind
	placement_yaw = view_yaw
	placement_preview = Node3D.new()
	add_child(placement_preview)
	match kind:
		"table": Props.table(placement_preview)
		"chairs": Props.chair(placement_preview, Vector3.ZERO)
		"grill": Props.grill(placement_preview)
		"flag": Props.rally_fan_flag(placement_preview, Vector3.ZERO, 0.0, flag_count())
	placement_material = Props.material(Color("82c991"))
	for child in placement_preview.find_children("*", "MeshInstance3D", true, false):
		child.material_override = placement_material
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_placement()
	toast("Выбери место: WASD и обзор. Q — повернуть, F — поставить, Esc — отменить.")

func _update_placement() -> void:
	if placement_preview == null:
		return
	var spot = walker + Vector3(-sin(view_yaw), 0, -cos(view_yaw)) * 2.5
	spot.y = stage.ground(spot)
	placement_preview.position = spot
	placement_preview.rotation.y = placement_yaw
	placement_valid = spot.distance_to(walker) <= 5.0 and valid_furniture_spot(spot, placement_kind)
	placement_material.albedo_color = Color("82c991") if placement_valid else Color("d75e53")

func cancel_placement() -> void:
	if is_instance_valid(placement_preview):
		placement_preview.queue_free()
	placement_preview = null
	placement_kind = ""

func confirm_placement() -> void:
	_update_placement()
	if placement_preview == null or not placement_valid:
		toast("Здесь поставить нельзя. Отойди от трассы, деревьев и мебели.")
		return
	var kind = placement_kind
	var spot = placement_preview.position
	var yaw = placement_yaw
	if room.connected and not room.is_host:
		room.submit(kind, {"pos": room.a(spot), "yaw": yaw})
	else:
		match kind:
			"table": place_table(spot, yaw)
			"chairs": place_chairs(spot, yaw)
			"grill": start_grill(spot, yaw)
			"flag": place_flag(spot, yaw)
	cancel_placement()

var cooking = false
var cook_time = 0.0
var grill_servings = 16
var eat_source_group = -2
var eat_kind = "meat"
var forage_source = -2
var foraging = preload("res://scripts/foraging.gd").new()
var eaten = false
var drunk_phase = 0.0
var drunk_strength = 0.0
const DRUNK_FADE_SECONDS = 60.0
var collapse_time = 0.0
var tree_requests: Dictionary = {}
var lamp_requests: Dictionary = {}
var beers = 0
var beer_timer = 0.0
const DRINK_DURATION = 3.3
var drink_time = -1.0
var drink_committed = false
var can_opened = false
var beer_audio: AudioStreamPlayer
const RALLY_CREW_LIMIT = 10
var rally_spawn_count = 0
var course = preload("res://scripts/course_schedule.gd").new()
var course_label: Label
var racing = false
var race_clock = 0.0
var spawn_clock = 12.0
var passed = 0
var helped = 0
var target_clearing = 0
var elapsed = 0.0
var toast_time = 0.0
var tow_target: Node3D
var tow_progress = 0.0
var racers: Array[Dictionary] = []
var rng = RandomNumberGenerator.new()
var title_label: Label
var info_label: Label
var quest_label: Label
var hint_label: Label
var toast_label: Label
var status_label: Label
var menu: PanelContainer
var menu_title: Label
var menu_text: Label
var start_button: Button
var minimap: Control
var engine_audio: AudioStreamPlayer
var rally_audio: AudioStreamPlayer3D
var wind_audio: AudioStreamPlayer
var fire_audio: AudioStreamPlayer3D
var capture_mode = false
var hud_panels: Array[Control] = []
var room: Node
var mobile_mode = false
var mobile_controls: Control
var mobile_sidebar: PanelContainer
var mobile_top: PanelContainer
var mobile_bottom: PanelContainer
var menu_help: Label

func enable_mobile() -> void:
	if mobile_mode:
		return
	mobile_mode = true
	get_window().content_scale_size = Vector2i(720, 480)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title_label.text = "РАЛЛИЙНЫЙ ОВОЩ"
	title_label.add_theme_font_size_override("font_size", 22)
	mobile_top.get_child(0).get_child(1).hide()
	mobile_top.position = Vector2(36, 64)
	mobile_top.size = Vector2.ZERO
	mobile_bottom.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mobile_bottom.offset_left = 36
	mobile_bottom.offset_right = -36
	mobile_bottom.offset_top = 150
	mobile_bottom.offset_bottom = 220
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.hide()
	quest_label.hide()
	mobile_sidebar.get_child(0).get_child(0).hide()
	mobile_sidebar.offset_left = -280
	mobile_sidebar.offset_right = -36
	mobile_sidebar.offset_top = 230
	mobile_sidebar.offset_bottom = 410
	minimap.custom_minimum_size = Vector2(204, 110)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_left = 36
	toast_label.offset_right = -36
	toast_label.offset_top = -330
	toast_label.offset_bottom = -265
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.offset_left = -310
	menu.offset_right = 310
	menu.offset_top = -195
	menu.offset_bottom = 195
	menu.get_child(0).add_theme_constant_override("separation", 6)
	menu.get_child(0).get_child(0).hide()
	menu_title.add_theme_font_size_override("font_size", 26)
	menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_text.add_theme_font_size_override("font_size", 18)
	menu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_text.text = "Доедь до поляны, разложи лагерь и посмотри ралли. Жарь шашлык, помогай экипажам и береги себя."
	menu_help.text = "Стик — движение и руль. Газ — справа.\nОбзор пешком — свайп по свободной части экрана."
	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	mobile_controls = preload("res://scripts/mobile_controls.gd").new()
	mobile_controls.game = self
	layer.add_child(mobile_controls)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not mobile_mode:
		enable_mobile()

const Traffic = preload("res://scripts/rally_traffic.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
var vehicle_motion = Motion.new()
var stones: Array[Dictionary] = []
var stone_serial = 0
var impact_serials: Dictionary = {}
var impact_shake = 0.0
var stone_clock = 0.0

func _ready() -> void:
	foraging.game = self
	interaction.game = self
	rng.randomize()
	_setup_input()
	stage = Stage.new()
	add_child(stage)
	stage.build()
	_build_environment()
	spectators = Spectators.new()
	spectators.game = self
	add_child(spectators)
	spectators.rebuild()
	car = Props.player_car(0)
	add_child(car)
	car.position = stage.at(12)
	heading = atan2(-stage.direction(12).x, -stage.direction(12).z)
	car.rotation.y = heading
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 68
	camera.far = 1100
	camera.current = true
	camera.position = stage.at(45) + Vector3(22, 15, 12)
	camera.look_at(stage.at(70))
	_build_ui()
	_setup_audio()
	room = preload("res://scripts/room.gd").new()
	room.game = self
	add_child(room)
	if OS.has_feature("mobile") or "--mobile-controls" in OS.get_cmdline_user_args():
		enable_mobile()
	if "--capture" in OS.get_cmdline_user_args():
		capture_mode = true
		start_game()
		_prepare_capture()
	elif "--capture-menu" in OS.get_cmdline_user_args():
		_capture_menu()
	elif "--smoke-test" in OS.get_cmdline_user_args():
		start_game()

func _setup_input() -> void:
	var bindings = {"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "brake": [KEY_SPACE], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_F], "table": [KEY_Z], "flag": [KEY_V], "chairs": [KEY_C], "grill": [KEY_G], "beer": [KEY_B], "eat": [], "collect": [], "mount_mushroom": [], "eat_mushroom": [], "eat_berries": [KEY_K], "rally": [KEY_R], "tow": [KEY_T], "random_spot": [KEY_Q], "map": [KEY_M], "recover": [KEY_HOME], "pause_demo": [KEY_ESCAPE], "placement_confirm": [KEY_ENTER], "placement_rotate": [], "placement_cancel": []}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var e = InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)

func _build_environment() -> void:
	var world = WorldEnvironment.new()
	world_environment = world
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("6f949f")
	sky_mat.sky_horizon_color = Color("ddd9be")
	sky_mat.ground_bottom_color = Color("64765b")
	sky_mat.ground_horizon_color = Color("ddd9be")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6c9ae")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("9ea995")
	env.fog_density = 0.0018
	if stage.winter:
		sky_mat.sky_top_color = Color("779bbd")
		sky_mat.sky_horizon_color = Color("cbdde7")
		sky_mat.ground_horizon_color = Color("dce8eb")
		env.ambient_light_color = Color("c7d9ed")
		env.ambient_light_energy = 0.27
		env.fog_light_color = Color("c8dae6")
		env.fog_density = 0.0012
	elif stage.urban:
		sky_mat.sky_top_color = Color("7e9eae")
		sky_mat.sky_horizon_color = Color("d7d0bd")
		sky_mat.ground_bottom_color = Color("727873")
		sky_mat.ground_horizon_color = Color("d7d0bd")
		env.ambient_light_color = Color("d2cfc2")
		env.ambient_light_energy = 0.45
		env.fog_light_color = Color("c4c5bc")
		env.fog_density = 0.0015
	world.environment = env
	add_child(world)
	var sun = DirectionalLight3D.new()
	sunlight = sun
	sun.rotation_degrees = Vector3(-36, -32, 0)
	sun.light_color = Color("ffe3b2")
	sun.light_energy = 0.85
	if stage.winter:
		sun.light_color = Color("d5e3f0")
		sun.light_energy = 0.52
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	add_child(sun)

func _panel(color: Color) -> StyleBoxFlat:
	var p = StyleBoxFlat.new()
	p.bg_color = color
	p.set_corner_radius_all(12)
	p.content_margin_left = 20
	p.content_margin_right = 20
	p.content_margin_top = 14
	p.content_margin_bottom = 14
	return p

func _label(parent: Node, text: String, font_size: int, color: Color = Color("f2e8d0")) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _build_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	var ui = Control.new()
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair = _label(ui, "·", 24, Color("fff0cb"))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -16
	crosshair.offset_right = 16
	crosshair.offset_top = -16
	crosshair.offset_bottom = 16
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.hide()
	var top = PanelContainer.new()
	mobile_top = top
	ui.add_child(top)
	top.position = Vector2(28, 24)
	top.add_theme_stylebox_override("panel", _panel(Color("25352be8")))
	var vb = VBoxContainer.new()
	top.add_child(vb)
	title_label = _label(vb, "СИМУЛЯТОР РАЛЛИЙНОГО ОВОЩА", 22)
	stage_caption = _label(vb, Stage.STAGES[selected_stage] + "  /  ДЕМО " + str(ProjectSettings.get_setting("application/config/version")), 12, Color("b2bea1"))
	course_label = _label(vb, "", 16, Color("ffe4a5"))
	course_label.hide()
	var sidebar = PanelContainer.new()
	mobile_sidebar = sidebar
	ui.add_child(sidebar)
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sidebar.offset_left = -332
	sidebar.offset_right = -28
	sidebar.offset_top = 24
	sidebar.offset_bottom = 390
	sidebar.hide()
	hud_panels.append(sidebar)
	sidebar.add_theme_stylebox_override("panel", _panel(Color("25352be8")))
	var sv = VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	sidebar.add_child(sv)
	_label(sv, "ПЛАН НА ВЫЕЗД", 15, Color("e4b56b"))
	quest_label = _label(sv, "", 16)
	minimap = MiniMap.new()
	minimap.game = self
	minimap.custom_minimum_size = Vector2(264, 205)
	sv.add_child(minimap)
	status_label = _label(sv, "", 13, Color("b2bea1"))
	var bottom = PanelContainer.new()
	mobile_bottom = bottom
	ui.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 28
	bottom.offset_right = -28
	bottom.offset_top = -136
	bottom.offset_bottom = -24
	bottom.hide()
	hud_panels.append(bottom)
	bottom.add_theme_stylebox_override("panel", _panel(Color("25352bf2")))
	var bv = VBoxContainer.new()
	bottom.add_child(bv)
	info_label = _label(bv, "", 24, Color("e4b56b"))
	hint_label = _label(bv, "", 15)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label = _label(ui, "", 21, Color("fff0cb"))
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.offset_left = -530
	toast_label.offset_right = 530
	toast_label.offset_top = -204
	toast_label.offset_bottom = -150
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_shadow_color", Color("182820"))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	menu = PanelContainer.new()
	ui.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -350
	menu.offset_right = 350
	menu.offset_top = -270
	menu.offset_bottom = 270
	menu.add_theme_stylebox_override("panel", _panel(Color("23342bf5")))
	var mv = VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	menu.add_child(mv)
	_label(mv, "ПЕРЕВАЛ. РАЛЛИ. ШАШЛЫК.", 14, Color("dfb270"))
	menu_title = _label(mv, "Симулятор\nраллийного овоща", 42)
	menu_text = _label(mv, "Выбери машину и спецучасток. Доедь до места,\nдо открытия СУ — 3 минуты. Успей разложить лагерь.", 19)
	selection_controls = VBoxContainer.new()
	selection_controls.add_theme_constant_override("separation", 8)
	mv.add_child(selection_controls)
	for kind in ["МАШИНА", "СПЕЦУЧАСТОК"]:
		var row = HBoxContainer.new()
		selection_controls.add_child(row)
		var caption = _label(row, kind, 16)
		caption.custom_minimum_size.x = 145
		var choice = preload("res://scripts/menu_choice.gd").new()
		choice.custom_minimum_size.y = 40
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.add_theme_font_size_override("font_size", 18)
		row.add_child(choice)
		if kind == "МАШИНА":
			car_choice = choice
			for model in Props.PLAYER_MODELS:
				choice.add_item(model.name)
			choice.item_selected.connect(select_player_car)
		else:
			stage_choice = choice
			for title in Stage.STAGES:
				choice.add_item(title)
			choice.item_selected.connect(select_stage)
	stage_choice.tooltip_text = "В комнате СУ выбирает создатель. Все участники играют на одной трассе."
	start_button = Button.new()
	start_button.text = "ПОЕХАЛИ"
	start_button.custom_minimum_size.y = 54
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.add_theme_color_override("font_color", Color("25352b"))
	start_button.add_theme_stylebox_override("normal", _panel(Color("e3b16b")))
	start_button.add_theme_stylebox_override("hover", _panel(Color("f1c687")))
	start_button.add_theme_stylebox_override("pressed", _panel(Color("c78f4a")))
	start_button.pressed.connect(_menu_action)
	mv.add_child(start_button)
	menu_help = _label(mv, "WASD — движение   ·   F — выйти   ·   Esc — пауза\nНа ногах: мышь — обзор   ·   Z/C/G — лагерь", 14, Color("b2bea1"))

func _setup_audio() -> void:
	engine_audio = AudioStreamPlayer.new()
	engine_audio.stream = load("res://audio/engine.wav")
	engine_audio.volume_db = -22
	add_child(engine_audio)
	_play_audio(engine_audio)
	wind_audio = AudioStreamPlayer.new()
	wind_audio.stream = load("res://audio/forest.wav")
	wind_audio.volume_db = -20
	add_child(wind_audio)
	_play_audio(wind_audio)
	rally_audio = AudioStreamPlayer3D.new()
	rally_audio.stream = load("res://audio/engine.wav")
	rally_audio.unit_size = 18
	rally_audio.max_distance = 180
	rally_audio.volume_db = -6
	add_child(rally_audio)
	fire_audio = AudioStreamPlayer3D.new()
	fire_audio.stream = load("res://audio/fire.wav")
	fire_audio.max_distance = 24
	fire_audio.volume_db = -12
	add_child(fire_audio)
	beer_audio = AudioStreamPlayer.new()
	beer_audio.volume_db = -10
	add_child(beer_audio)

func start_game() -> void:
	if playing:
		return
	playing = true
	course.apply_snapshot({})
	racing = false
	selection_controls.hide()
	menu.hide()
	course_label.show()
	course_label.text = course.caption()
	for panel in hud_panels:
		panel.show()
	mobile_sidebar.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mobile_mode or (room.connected and OS.has_feature("web")) else Input.MOUSE_MODE_CAPTURED
	toast("Доедь до любой парковки. Q — выбрать случайную на карте." if stage.urban else "Доедь до любой поляны. Q — выбрать случайную на карте.")

func _menu_action() -> void:
	if (dead or finished) and room.connected:
		room.leave()
		return
	if dead or finished:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().reload_current_scene()
	elif paused:
		paused = false
		menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mobile_mode else Input.MOUSE_MODE_CAPTURED
	else:
		start_game()

func _unhandled_input(event: InputEvent) -> void:
	if placement_kind != "":
		if event.is_action_pressed("pause_demo") or event.is_action_pressed("placement_cancel"):
			cancel_placement()
			return
		if not paused and not dead and not finished and not (room.connected and not room.is_host and room.world_paused):
			if event.is_action_pressed("interact") or event.is_action_pressed("placement_confirm") or event.is_action_pressed(placement_kind):
				confirm_placement()
				return
			if event.is_action_pressed("random_spot") or event.is_action_pressed("placement_rotate"):
				placement_yaw += PI / 8
				return
		else:
			return
	if event.is_action_pressed("map") and playing and not dead and not finished:
		mobile_sidebar.visible = not mobile_sidebar.visible
		return
	if event.is_action_pressed("pause_demo") and playing and not dead and not finished:
		paused = not paused
		menu.visible = paused
		menu_title.text = "Перерыв на природе"
		menu_text.text = "Пауза. Ралли, мангал и таймеры остановлены.\n\nHome — вернуть машину на дорогу.\nF8 / F9 — показать застревание / вылет.\n\nПродолжить — кнопкой или Esc."
		start_button.text = "ПРОДОЛЖИТЬ"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused or mobile_mode else Input.MOUSE_MODE_CAPTURED
		return
	if not playing or paused or dead or finished:
		return
	if event is InputEventMouseButton and event.pressed and not mobile_mode and room.connected:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and not mobile_mode:
		view_yaw -= event.relative.x * 0.0025
		view_pitch = clampf(view_pitch - event.relative.y * 0.0025, -1.15, 1.1)
	if drink_time >= 0 or eat_time >= 0 or (room.connected and not room.is_host and room.world_paused):
		return
	if event.is_action_pressed("jump") and not in_car:
		jump()
		return
	for furniture_action in ["table", "chairs", "grill", "flag"]:
		if event.is_action_pressed(furniture_action):
			begin_placement(furniture_action)
			return
	if event.is_action_pressed("interact"):
		interaction.activate()
		return
	if event.is_action_pressed("eat_berries"):
		eat_foraged("berries")
		return
	for shared_action in room.SHARED_ACTIONS:
		if shared_action != "eat" and event.is_action_pressed(shared_action) and room.submit(shared_action):
			return
	if event.is_action_pressed("interact"):
		_toggle_car()
	elif event.is_action_pressed("table"):
		place_table()
	elif event.is_action_pressed("chairs"):
		place_chairs()
	elif event.is_action_pressed("grill"):
		start_grill()
	elif event.is_action_pressed("flag"):
		begin_placement("flag")
	elif event.is_action_pressed("beer"):
		drink_beer()
	elif event.is_action_pressed("eat"):
		eat_meat()
	elif event.is_action_pressed("rally"):
		start_rally()
	elif event.is_action_pressed("random_spot"):
		target_clearing = rng.randi_range(0, stage.clearings.size() - 1)
		toast(("Выбрана парковка %d. Оранжевая точка на карте." if stage.urban else "Выбрана поляна %d. Оранжевая точка на карте.") % (target_clearing + 1))
	elif event.is_action_pressed("recover"):
		if not racing:
			car.position = stage.at(stage.road_s(car.position))
			heading = atan2(-stage.direction(stage.road_s(car.position)).x, -stage.direction(stage.road_s(car.position)).z)
			speed = 0
			vehicle_motion = Motion.new()
			toast("Машина возвращена на СУ.")
		else:
			toast("Возврат на СУ недоступен во время заездов.")
	elif event is InputEventKey and event.pressed and not event.echo:
		if room.connected and not room.is_host:
			return
		if event.physical_keycode == KEY_F8:
			spawn_racer("stuck")
		elif event.physical_keycode == KEY_F9:
			spawn_racer("crash")

func _process(delta: float) -> void:
	if not playing or paused or dead or finished or (room.connected and not room.is_host and room.world_paused):
		return
	if not room.connected or room.is_host:
		elapsed += delta
		course.update(self, delta)
	elif course.phase == "countdown":
		course.remaining = maxf(0, course.remaining - delta)
	stage.update_fallen(delta)
	_update_intoxication(delta)
	if in_car:
		_drive(delta)
	else:
		_walk(delta)
	_update_drinking(delta)
	_update_eating(delta)
	_update_camera(delta)
	_update_placement()
	spectators.update(elapsed, delta, room.connected and not room.is_host)
	stage.officials.update(self, delta, room.connected and not room.is_host)
	foraging.update_visuals()
	if not room.connected or room.is_host:
		_update_racers(delta)
		_update_stones(delta)
		_update_cooking(delta)
		if room.connected:
			room.update_tow(delta)
			room.check_remote_collisions()
		else:
			_update_tow(delta)
	if beer_timer > 0:
		beer_timer = maxf(0, beer_timer - delta)
	toast_time = maxf(0, toast_time - delta)
	toast_label.visible = toast_time > 0 and not mobile_mode
	_update_hud()
	engine_audio.pitch_scale = 0.75 + absf(speed) / 18.0
	engine_audio.volume_db = -21 if in_car else -35
	if not room.connected or room.is_host:
		_check_finish()
	if capture_mode and elapsed > 1.3:
		capture_mode = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../preview.png")
		await _shutdown_audio()
		get_tree().quit()

func _update_intoxication(delta: float) -> void:
	drunk_strength = maxf(0.0, drunk_strength - delta / DRUNK_FADE_SECONDS)
	if drunk_strength > 0:
		drunk_phase = fposmod(drunk_phase + delta * 1.25, TAU)
	else:
		drunk_phase = 0.0

func player_position() -> Vector3:
	return car.position if in_car else walker

func _drive(delta: float) -> void:
	var steps = maxi(1, int(ceil(delta / (1.0 / 120.0))))
	var dt = delta / steps
	for step in range(steps):
		var throttle = Input.get_axis("back", "forward")
		var steer = Input.get_axis("left", "right")
		var offroad = stage.road_distance(car.position) > 4.1
		var max_speed = 7.0 if offroad else 19.0
		var braking = Input.is_action_pressed("brake")
		var previous_heading = heading
		# Bicycle steering with limited gravel adhesion. Velocity keeps its direction in a slide.
		heading -= steer * dt * clampf(absf(speed) / 6, 0, 1) * signf(speed) * 1.15
		var forward = Vector3(-sin(heading), 0, -cos(heading))
		var right = forward.cross(Vector3.UP)
		var longitudinal = vehicle_motion.velocity.dot(forward)
		if absf(speed - longitudinal) > 3:
			vehicle_motion.velocity = forward * speed
			longitudinal = speed
		longitudinal = move_toward(longitudinal, throttle * max_speed * (0.4 if throttle < 0 else 1.0), (7.0 if throttle != 0 else 2.7) * dt)
		if braking:
			longitudinal = move_toward(longitudinal, 0, 19 * dt)
		var lateral = vehicle_motion.velocity.dot(right)
		var friction = stage.grip(car.position) * (3.5 if braking else 8.5) * (1.0 if vehicle_motion.grounded else 0.08)
		lateral = move_toward(lateral, 0, friction * dt)
		vehicle_motion.velocity = forward * longitudinal + right * lateral
		speed = longitudinal
		rock_impact_timer = maxf(0.0, rock_impact_timer - dt)
		var previous = car.position
		var next = previous + vehicle_motion.velocity * dt
		next.x = clampf(next.x, -185, 185)
		next.z = clampf(next.z, -Stage.LENGTH + 5, 10)
		var rock_hit = stage.rock_hit(previous, next, 0.85)
		if not rock_hit.is_empty():
			next = rock_hit.position
			var closing = vehicle_motion.rock_impulse(rock_hit.normal, heading)
			speed = vehicle_motion.velocity.dot(forward)
			if closing > 1.0 and rock_impact_timer <= 0:
				condition = maxf(0, condition - minf(14.0, closing * 0.65))
				impact_shake = minf(0.8, closing * 0.055)
				rock_impact_timer = 0.4
				toast("Удар о камень! Можно отъехать назад.")
		if stage.urban:
			var city_hit = stage.city.hit(previous, next, 0.85)
			if not city_hit.is_empty():
				next = city_hit.position
				var impact_speed = vehicle_motion.velocity.length()
				knock_city(city_hit, vehicle_motion.velocity)
				var closing = vehicle_motion.rock_impulse(city_hit.normal, heading)
				speed = vehicle_motion.velocity.dot(forward)
				if closing > 1 and rock_impact_timer <= 0:
					condition = maxf(0, condition - minf(20.0, closing * 0.85))
					impact_shake = minf(0.8, impact_speed * 0.055)
					rock_impact_timer = 0.4
					toast("Столкновение с городским объектом!")
		var tree_index = stage.obstacle_hit(previous, next, 0.95, true)
		var hit = tree_index >= 0
		if hit and vehicle_motion.velocity.length() > 5 and not stage.fallen.has(tree_index):
			knock_tree(tree_index, vehicle_motion.velocity)
		if contact_blocked(previous, next, true):
			hit = true
		if hit:
			condition = maxf(0, condition - vehicle_motion.velocity.length() * 1.4)
			vehicle_motion.velocity *= -0.25
			speed = vehicle_motion.velocity.dot(forward)
			toast("Удар! Сбавь скорость.")
		else:
			car.position = next
		vehicle_motion.suspension(car, stage, dt, heading, (heading - previous_heading) / dt * speed)
		if offroad and absf(speed) > 5:
			condition = maxf(0, condition - dt * 0.15)
	if condition <= 0:
		die("Легковушка сдалась раньше тебя.\nРазбитый СУ победил подвеску.")

func knock_tree(index: int, direction_hint: Vector3) -> void:
	if stage.fell(index, direction_hint):
		if room.connected and not room.is_host:
			tree_requests[index] = direction_hint.normalized()
		toast("Дерево падает!")

func contact_blocked(start: Vector3, end: Vector3, driving: bool) -> bool:
	var cars = []
	var people = []
	if not driving:
		cars.append(car.position)
	for group in spectators.groups:
		cars.append(group.car.position)
	for person in spectators.people:
		cars.append(person.avatar.position) # Solid spectators without affecting player-owned chair counts.
	for racer in racers:
		cars.append(racer.node.position)
	for peer in room.peers.values():
		if peer.state == null:
			continue
		cars.append(room.v(peer.state.car))
		if not peer.state.in_car:
			people.append(room.v(peer.state.pos))
	for other in cars:
		if Motion.swept_hit(start + Vector3(0, 0.65, 0), end + Vector3(0, 0.65, 0), other + Vector3(0, 0.65, 0), 2.5 if driving else 1.75):
			# Let an initially overlapping walker move out of the volume.
			if end.distance_to(other) <= start.distance_to(other):
				return true
	for person in people:
		if Motion.swept_hit(start + Vector3(0, 0.7, 0), end + Vector3(0, 0.7, 0), person + Vector3(0, 0.7, 0), 1.55 if driving else 0.6):
			if end.distance_to(person) <= start.distance_to(person):
				if driving and absf(speed) > 5 and (not room.connected or room.is_host):
					die("Легковушка сбила участника вашей компании.")
				return true
	return false

func _walk(delta: float) -> void:
	if beers >= 30 or seated:
		return
	var motion = Vector2(Input.get_axis("left", "right"), Input.get_axis("forward", "back"))
	if motion.length() > 1:
		motion = motion.normalized()
	var dir = Vector3(motion.x, 0, motion.y).rotated(Vector3.UP, view_yaw)
	var next = walker + dir * delta * (1.4 if drink_time >= 0 or eat_time >= 0 else (RUN_SPEED if running() else WALK_SPEED))
	next.x = clampf(next.x, -185, 185)
	next.z = clampf(next.z, -Stage.LENGTH + 5, 10)
	var hit = (stage.urban and not stage.city.hit(walker, next, 0.3).is_empty()) or not stage.rock_hit(walker, next, 0.3).is_empty() or stage.obstacle_hit(walker, next, 0.3, true) >= 0 or contact_blocked(walker, next, false)
	if not hit:
		walker = next
	var remaining = maxf(0, delta)
	while remaining > 0.000001:
		var step = minf(remaining, 1.0 / 120.0)
		jump_height += jump_velocity * step - WALK_GRAVITY * step * step * 0.5
		jump_velocity -= WALK_GRAVITY * step
		if jump_height <= 0:
			jump_height = 0
			jump_velocity = 0
		remaining -= step
	walker.y = stage.ground(walker) + jump_height

func running() -> bool:
	return not in_car and not seated and beers < 30 and not paused and not dead and not finished and drink_time < 0 and eat_time < 0 and Input.is_action_pressed("sprint") and (absf(Input.get_axis("left", "right")) + absf(Input.get_axis("forward", "back"))) > 0.01

func jump() -> bool:
	if not playing or in_car or seated or beers >= 30 or paused or dead or finished or drink_time >= 0 or eat_time >= 0 or jump_height > 0.01 or jump_velocity > 0:
		return false
	jump_velocity = JUMP_SPEED
	return true

func _update_camera(delta: float) -> void:
	if capture_mode:
		return
	impact_shake = maxf(0, impact_shake - delta)
	collapse_time = minf(0.8, collapse_time + delta) if beers >= 30 else 0.0
	var collapse = smoothstep(0, 0.8, collapse_time)
	if in_car:
		var orbit = view_yaw
		var behind = Vector3(sin(orbit), 0, cos(orbit))
		var desired = car.position + behind * 8.2 + Vector3(0, 4.4, 0)
		desired.y = maxf(desired.y, stage.ground(desired) + 1.1)
		camera.position = camera.position.lerp(desired, 1 - exp(-delta * 7))
		camera.look_at(car.position + Vector3(0, 1.1, 0) - behind * 1.5)
	else:
		camera.position = walker + Vector3(0, lerpf(1.12 if seated else 1.72, 0.36, collapse) + sin(elapsed * 12) * 0.015, 0)
		var sip = sin(clampf((drink_time - 1.3) / 1.2, 0, 1) * PI) if drink_time >= 0 else 0.0
		camera.rotation = Vector3(view_pitch + sip * 0.035, view_yaw, 0.0)
		camera.fov = 68 - sip * 2.0

	# Bounded gentle sway, with an envelope that fades between sips.
	camera.rotation.z += sin(drunk_phase) * deg_to_rad(3.0) * drunk_strength + PI / 2 * collapse
	camera.rotation.x += sin(drunk_phase * 2.0) * deg_to_rad(0.6) * drunk_strength
	camera.position += Vector3(sin(elapsed * 91), cos(elapsed * 73), 0) * impact_shake * 0.12

func _toggle_car() -> void:
	if jump_height > 0.01 or jump_velocity > 0:
		return
	if beers >= 30:
		toast("Ты лежишь. На сегодня поездки закончились.")
		return
	if drink_time >= 0 or eat_time >= 0:
		toast("Сначала закончи есть или пить и освободи руки.")
		return
	if in_car:
		if absf(speed) > 1:
			toast("Сначала остановись: Space — тормоз.")
			return
		in_car = false
		vehicle_motion.velocity = Vector3.ZERO
		speed = 0
		walker = car.position + Vector3(-2.1, 0, 0).rotated(Vector3.UP, heading)
		walker.y = stage.ground(walker)
		view_yaw = heading
		toast("Z — стол, C — стулья, G — мангал. Устанавливай вне СУ.")
	elif walker.distance_to(car.position) < 4:
		in_car = true
		view_yaw = heading
		speed = 0
	else:
		toast("Подойди к своей машине, чтобы сесть.")

func near_camp() -> bool:
	return camp != null and player_position().distance_to(camp.position) < 7

func nearby_drink_source() -> bool:
	return near_camp() or (spectators != null and spectators.nearby_table(player_position()) >= 0)

func food_source_group() -> int:
	if not in_car and near_camp() and grill != null:
		return -1 if cook_time >= 35 and grill_servings > 0 else -2
	if not in_car and spectators != null:
		return spectators.nearby_grill(player_position())
	return -2

func can_eat_meat() -> bool:
	return playing and not paused and not dead and not finished and not in_car and eat_time < 0 and drink_time < 0 and food_source_group() != -2

func place_table(spot: Vector3 = Vector3.INF, yaw: float = 0.0) -> bool:
	if in_car:
		return false
	var moving = spot != Vector3.INF
	if camp != null and not moving:
		return false
	if not moving:
		spot = walker + Vector3(-sin(view_yaw), 0, -cos(view_yaw)) * 2.5
	if not valid_furniture_spot(spot, "table"):
		return false
	if camp == null:
		camp = Node3D.new()
		add_child(camp)
		Props.table(camp)
	camp.position = spot
	camp.position.y = stage.ground(spot)
	camp.rotation.y = yaw
	toast("Стол установлен.")
	return true

func place_chairs(spot: Vector3 = Vector3.INF, yaw: float = 0.0, owner: String = "") -> bool:
	if in_car:
		return false
	if owner == "":
		owner = chair_owner()
	if spot == Vector3.INF:
		if personal_chairs.has(owner) or not near_camp():
			return false
		spot = camp.position + Vector3(-1.6, 0, 0.7)
	if not valid_furniture_spot(spot, "chairs", owner):
		return false
	apply_chair(owner, spot, yaw)
	toast("Твой стул установлен.")
	return true

func apply_chair(owner: String, spot: Vector3, yaw: float) -> void:
	if not personal_chairs.has(owner):
		var chair = Node3D.new()
		add_child(chair)
		Props.chair(chair, Vector3.ZERO)
		personal_chairs[owner] = chair
	personal_chairs[owner].position = spot
	personal_chairs[owner].position.y = stage.ground(spot)
	personal_chairs[owner].rotation.y = yaw
	has_chairs = not personal_chairs.is_empty()

func place_flag(spot: Vector3 = Vector3.INF, yaw: float = 0.0, owner: String = "", replicated: bool = false) -> bool:
	var moving = spot != Vector3.INF
	if owner == "":
		owner = flag_owner()
	if not replicated and (in_car or not moving or flag_count(owner) >= FLAGS_PER_PLAYER):
		return false
	if not valid_furniture_spot(spot, "flag"):
		return false
	var flags: Array = personal_flags.get(owner, [])
	var node = Props.rally_fan_flag(self, spot, yaw, flags.size())
	node.position.y = stage.ground(spot)
	flags.append(node)
	personal_flags[owner] = flags
	return true

func start_grill(spot: Vector3 = Vector3.INF, yaw: float = 0.0, replicated: bool = false) -> bool:
	var moving = spot != Vector3.INF
	if not replicated and (in_car or camp == null or not has_chairs):
		toast("Сначала поставь стол и стул.")
		return false
	if cooking and not moving:
		return false
	if not moving:
		spot = camp.position + Vector3(0.3, 0, -2.4)
	if not replicated and not valid_furniture_spot(spot, "grill"):
		return false
	if grill != null:
		grill.position = spot
		grill.position.y = stage.ground(spot)
		grill.rotation.y = yaw
		fire_audio.position = grill.position
		return true
	grill = Props.grill(self)
	grill_servings = 16
	grill.position = spot
	grill.position.y = stage.ground(spot)
	grill.rotation.y = yaw
	cooking = true
	smoke = GPUParticles3D.new()
	grill.add_child(smoke)
	smoke.position = Vector3(0, 1.1, 0)
	smoke.amount = 20
	smoke.lifetime = 3.0
	var process = ParticleProcessMaterial.new()
	process.direction = Vector3(0.2, 1, 0)
	process.spread = 20
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0, 0.35, 0)
	process.scale_min = 0.15
	process.scale_max = 0.4
	process.color = Color("bfc1ab")
	smoke.process_material = process
	var mesh = SphereMesh.new()
	mesh.radial_segments = 5
	mesh.rings = 3
	var mat = Props.material(Color("bfc1ab"))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.2
	mesh.material = mat
	smoke.draw_pass_1 = mesh
	fire_audio.position = grill.global_position
	_play_audio(fire_audio)
	toast("Угли разгорелись. Шашлык готовится 35 секунд. Следи за таймером СУ.")
	return true

func _update_cooking(delta: float) -> void:
	if cooking and cook_time < 35:
		cook_time = minf(35, cook_time + delta)
		if cook_time >= 35:
			toast("Шашлык готов! Подойди к лагерю и нажми X.")

func drink_beer() -> bool:
	if not playing or paused or dead or finished:
		return false
	if in_car or not nearby_drink_source():
		toast("Подойди к своему или соседскому столу пешком.")
		return false
	if eat_time >= 0 or drink_time >= 0 or beer_timer > 0:
		toast("Пока хватит. Лучше посмотри ралли.")
		return false
	drink_time = 0.0
	drink_committed = false
	can_opened = false
	beer_prop = Props.beer_hand(avatar_variant)
	camera.add_child(beer_prop)
	_update_drinking(0)
	toast("Открываем банку. За хороший выезд!")
	return true

func _update_drinking(delta: float) -> void:
	if drink_time < 0:
		return
	drink_time = minf(DRINK_DURATION, drink_time + delta)
	var rest = Vector3(0.4, -0.72, -0.7)
	var raised = Vector3(0.29, -0.18, -0.64)
	var mouth = Vector3(0.13, -0.11, -0.46)
	if drink_time < 0.55:
		beer_prop.position = rest.lerp(raised, smoothstep(0.0, 0.55, drink_time))
		beer_prop.rotation = Vector3(0.0, 0.0, -0.1)
	elif drink_time < 1.25:
		beer_prop.position = raised.lerp(mouth, smoothstep(0.8, 1.25, drink_time))
		beer_prop.rotation.x = 0.18 * smoothstep(0.8, 1.25, drink_time)
	elif drink_time < 2.5:
		var tilt = smoothstep(1.25, 1.65, drink_time)
		beer_prop.position = mouth + Vector3(0, sin(drink_time * 16) * 0.004, 0)
		beer_prop.rotation.x = 0.18 + tilt * 0.95
		beer_prop.rotation.z = -0.1 + sin(drink_time * 7) * 0.016
	else:
		var lower = smoothstep(2.5, DRINK_DURATION, drink_time)
		beer_prop.position = mouth.lerp(rest, lower)
		beer_prop.rotation.x = lerpf(1.13, 0, lower)
	if not can_opened and drink_time >= 0.65:
		can_opened = true
		beer_prop.get_node("PullTab").rotation.x = -0.7
		beer_prop.get_node("Opening").show()
		beer_audio.stream = load("res://audio/can-open.wav")
		_play_audio(beer_audio)
	if not drink_committed and drink_time >= 1.8:
		drink_committed = true
		beers += 1
		if beers >= 3:
			drunk_strength = minf(1.0, drunk_strength + 0.45)
		beer_timer = 1.0
		if beers >= 30:
			if in_car:
				in_car = false
				walker = car.position
				walker.y = stage.ground(walker)
			vehicle_motion.velocity = Vector3.ZERO
			speed = 0
			toast("Тридцатая банка. Ты упал и больше не можешь ходить.")
		beer_audio.stream = load("res://audio/beer-sip.wav")
		_play_audio(beer_audio)
	if drink_time >= DRINK_DURATION:
		_cancel_drink()
		toast("За хороший выезд! X — готовый шашлык. Заезды начнутся автоматически.")

func _cancel_drink() -> void:
	drink_time = -1.0
	if is_instance_valid(beer_prop):
		beer_prop.queue_free()
	beer_prop = null
	camera.fov = 68
	if beer_audio != null:
		beer_audio.stop()

func select_player_car(variant: int) -> void:
	selected_car = posmod(variant, Props.PLAYER_MODELS.size())
	if car_choice != null:
		car_choice.select(selected_car)
	var transform_before = car.transform
	car.queue_free()
	car = Props.player_car(selected_car)
	add_child(car)
	car.transform = transform_before

func select_stage(variant: int) -> void:
	if playing:
		return
	variant = clampi(variant, 0, Stage.STAGES.size() - 1)
	if variant == selected_stage:
		return
	jump_height = 0
	jump_velocity = 0
	selected_stage = variant
	stage_caption.text = Stage.STAGES[variant] + "  /  ДЕМО " + str(ProjectSettings.get_setting("application/config/version"))
	stage_choice.select(variant)
	stage.free()
	stage = Stage.new(variant)
	add_child(stage)
	stage.build()
	spectators.rebuild()
	world_environment.free()
	sunlight.free()
	_build_environment()
	car.position = stage.at(12)
	heading = atan2(-stage.direction(12).x, -stage.direction(12).z)
	car.rotation = Vector3(0, heading, 0)
	vehicle_motion = Motion.new()
	speed = 0
	camera.position = stage.at(45) + Vector3(22, 15, 12)
	camera.look_at(stage.at(70))

func eat_meat(source_group: int = -2) -> bool:
	if not playing or paused or dead or finished or eat_time >= 0 or drink_time >= 0:
		return false
	eat_source_group = food_source_group() if source_group == -2 else source_group
	if eat_source_group == -2:
		toast("Шашлык не готов или рядом нет мангала с порциями.")
		return false
	eat_kind = "meat"
	eat_time = 0
	eat_committed = false
	meat_prop = Props.meat_hand(avatar_variant)
	camera.add_child(meat_prop)
	_update_eating(0)
	toast("Шампур горячий. Приятного аппетита!")
	return true

func eat_foraged(kind: String, source: int = -2) -> bool:
	if source == -2 and not foraging.can_eat(kind):
		return false
	eat_kind = kind
	forage_source = (foraging.nearby_source() if source == -2 else source) if kind == "mushroom" else -2
	if kind == "mushroom" and (foraging.grill_node(forage_source) == null or player_position().distance_to(foraging.grill_node(forage_source).position) > 4 or foraging.ready_index(forage_source) < 0):
		return false
	eat_time = 0
	eat_committed = false
	meat_prop = Props.meat_hand(avatar_variant, kind)
	camera.add_child(meat_prop)
	_update_eating(0)
	toast("Едим ягоды." if kind == "berries" else "Едим гриб с шампура.")
	return true

func commit_meat(source_group: int = -2) -> bool:
	if in_car:
		return false
	var source = source_group
	if source == -2:
		source = eat_source_group if eat_source_group != -2 else food_source_group()
	if source == -1:
		if grill == null or (not near_camp() and player_position().distance_to(grill.position) > 4) or cook_time < 35 or grill_servings <= 0:
			return false
		grill_servings -= 1
		Props.set_grill_servings(grill, grill_servings)
	elif spectators == null or source < 0 or source >= spectators.groups.size() or player_position().distance_to(spectators.groups[source].grill.position) > 4 or not spectators.consume_serving(source):
		return false
	eaten = true
	toast("Шашлык удался. Осталось %d шампуров." % grill_servings if source == -1 else "У NPC нашлась порция шашлыка. Приятного аппетита!")
	eat_source_group = -2
	return true

func _update_eating(delta: float) -> void:
	if eat_time < 0:
		return
	eat_time = minf(EAT_DURATION, eat_time + delta)
	var lift = Props.food_lift(eat_time)
	meat_prop.position = Vector3(0.34, -0.72, -0.70).lerp(Vector3(0.10, -0.43, -0.39), lift)
	meat_prop.rotation = Vector3(-0.18 * lift, 0.15, -0.25 + lift * 0.17)
	Props.pose_food(meat_prop, eat_time, eat_kind)
	if not eat_committed and eat_time >= 2.6:
		eat_committed = true
		if not room.connected or room.is_host:
			if eat_kind == "meat":
				commit_meat()
			else:
				foraging.consume(eat_kind, "", forage_source)
		else:
			room.submit("eat" if eat_kind == "meat" else "eat_" + eat_kind, {"source": eat_source_group if eat_kind == "meat" else forage_source})
	if eat_time >= EAT_DURATION:
		_cancel_eat()

func _cancel_eat() -> void:
	eat_time = -1
	eat_kind = "meat"
	forage_source = -2
	eat_source_group = -2
	if is_instance_valid(meat_prop):
		meat_prop.queue_free()
	meat_prop = null

func start_rally() -> bool:
	# R is an information shortcut; it cannot bypass the safety convoy.
	toast(course.caption())
	return course.phase == "racing"

func spawn_course_car(role: String, id: int, zero_index: int = 0) -> void:
	if dead or finished or (room.connected and not room.is_host):
		return
	var node = Props.course_car(role, zero_index)
	var racer = _add_course_vehicle(node, id, "pass", 0, role, zero_index)
	racer.pace = 0.72
	racer.drive_speed = stage.rally_speed(0) * racer.pace
	racer.bias = 0.0
	racer.phase = 0.0
	toast(course.caption())

func _add_course_vehicle(node: Node3D, id: int, kind: String, variant: int, role: String = "racer", zero_index: int = 0) -> Dictionary:
	var focus = clampf(stage.road_s(player_position()), 45, Stage.LENGTH - 80)
	add_child(node)
	var s = 0.0 if stage.urban or role != "racer" else maxf(0, focus - 115)
	node.position = stage.at(s)
	node.set_meta("room_id", id)
	var driver = Traffic.profile(id)
	var racer = {"bias": driver.bias, "phase": driver.phase, "pace": driver.pace, "line": 0.0, "drive_speed": stage.rally_speed(s) * driver.pace, "avoiding": false, "avoid_line": 0.0, "role": role, "zero_index": zero_index, "id": id, "node": node, "s": s, "focus": focus, "kind": kind, "state": "racing", "offset": 0.0, "age": 0.0, "counted": false, "start": Vector3.ZERO, "target": Vector3.ZERO, "variant": variant, "motion": Motion.new(), "previous": node.position, "slide": 0.0, "slide_speed": 0.0}
	racers.append(racer)
	return racer

func spawn_racer(forced: String = "") -> void:
	if course.phase != "racing" or rally_spawn_count >= RALLY_CREW_LIMIT or dead or finished or (room.connected and not room.is_host):
		return
	racing = true
	var kind = forced
	if kind == "":
		var roll = rng.randf()
		kind = "crash" if roll < 0.25 else ("stuck" if roll < 0.45 else "pass")
	# Keep at most one stranded car, so the stage cannot clog permanently.
	for existing in racers:
		if existing.state == "stranded" and kind in ["stuck", "crash"]:
			kind = "pass"
	var variant = [5, 0, 1, 2, 3, 4][rally_spawn_count % Props.RALLY_MODELS.size()]
	rally_spawn_count += 1
	var node = Props.car(Color.WHITE, true, variant)
	_add_course_vehicle(node, rally_spawn_count, kind, variant)
	toast("Приближается %s, номер %d!" % [node.get_meta("model"), node.get_meta("number")])

func _update_racers(delta: float) -> void:
	var to_remove: Array[Dictionary] = []
	var nearest: Node3D = null
	var nearest_d = 9999.0
	for racer in racers:
		var node: Node3D = racer.node
		racer.previous = node.position
		var moving_before = racer.state in ["racing", "offroad"]
		racer.age += delta
		var service = racer.get("role", "racer") != "racer"
		if service:
			Props.update_course_lights(node, elapsed)
		if racer.state == "racing":
			var traffic = Traffic.plan(self, racer)
			racer.avoiding = traffic.avoiding
			racer.avoid_line = traffic.line
			var actual_speed = move_toward(float(racer.get("drive_speed", stage.rally_speed(racer.s))), float(traffic.speed), delta * (Traffic.BRAKE if traffic.speed < racer.get("drive_speed", 0) else 8.0))
			# The braking envelope is also a hard speed cap for long frame gaps.
			actual_speed = minf(actual_speed, float(traffic.speed)) if traffic.speed < actual_speed else actual_speed
			actual_speed = minf(actual_speed, float(traffic.get("advance", INF)) / maxf(delta, 0.001))
			racer.drive_speed = actual_speed
			var race_speed = maxf(actual_speed, 0.1)
			racer.s += delta * actual_speed
			racer.line = move_toward(float(racer.get("line", 0.0)), float(traffic.line), delta * minf(2.8, actual_speed * 0.14))

			var s: float = racer.s
			var road_yaw = atan2(-stage.direction(s).x, -stage.direction(s).z)
			var ahead = stage.direction(s + 7)
			var bend = wrapf(atan2(-ahead.x, -ahead.z) - road_yaw, -PI, PI) / 7.0
			# Lateral inertia fights the tyres until countersteering catches the slide.
			var substeps = maxi(1, int(ceil(delta / (1.0 / 120.0))))
			var dt = delta / substeps
			for step in range(substeps):
				racer.slide_speed += ((0.0 if service else bend * race_speed * race_speed) - racer.slide * 14.0 - racer.slide_speed * stage.grip(node.position) * 5.0) * dt
				racer.slide = clampf(racer.slide + racer.slide_speed * dt, -2.6, 2.6)
			var height = node.position.y
			node.position = stage.at(s) + stage.side(s) * racer.line
			node.position.y = height
			var countersteer = clampf(racer.slide_speed / race_speed + racer.slide * 0.035, -0.32, 0.32)
			var movement = node.position - racer.previous
			var path_yaw = atan2(-movement.x, -movement.z) if Vector2(movement.x, movement.z).length() > 0.02 else road_yaw
			racer.motion.suspension(node, stage, delta, path_yaw + countersteer, bend * race_speed * race_speed)
			if s >= racer.focus and racer.kind != "pass":
				racer.state = "offroad"
				racer.age = 0
				racer.start = node.position
				var side_sign = signf((player_position() - node.position).dot(stage.side(s)))
				if side_sign == 0:
					side_sign = 1
				racer.target = stage.at(s + 7) + stage.side(s) * side_sign * (15 if racer.kind == "crash" else 6)
				racer.target.y = stage.ground(racer.target)
				toast("ВЫЛЕТ! Отойди с траектории!" if racer.kind == "crash" else "Экипаж застрял. Нужен трос — T рядом с машиной.")
			elif s > racer.focus + 45 and not racer.counted:
				count_racer(racer)
			if s >= Stage.LENGTH - 1 or (not stage.urban and not service and s > racer.focus + 150):
				to_remove.append(racer)
		elif racer.state == "offroad":
			var t = minf(1, racer.age / (0.7 if racer.kind == "crash" else 1.1))
			node.position = racer.start.lerp(racer.target, t)
			node.rotation.y += delta * 0.6
			node.rotation.z = sin(t * PI) * 0.2
			if t >= 1:
				racer.state = "stranded"
				racer.age = 0
				count_racer(racer)
		elif racer.state == "rock_bounce":
			var steps = maxi(1, int(ceil(delta / (1.0 / 120.0))))
			var dt = delta / steps
			for step in range(steps):
				var next: Vector3 = node.position + racer.motion.velocity * dt
				var contact = stage.city.hit(node.position, next, 0.85) if stage.urban else stage.rock_hit(node.position, next, 0.85)
				if not contact.is_empty():
					next = contact.position
					racer.motion.rock_impulse(contact.normal, node.rotation.y)
				node.position = next
				racer.motion.velocity = racer.motion.velocity.move_toward(Vector3.ZERO, dt * 16.0)
				racer.motion.suspension(node, stage, dt, node.rotation.y)
			if racer.age >= 0.8:
				racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
				racer.age = 0.0
		elif racer.state in ["stopped", "stranded"]:
			racer.motion.suspension(node, stage, delta, node.rotation.y)
			if racer.state == "stopped" and not service and racer.age > 18 and racer.node != tow_target and float(racer.get("recovery_progress", 0)) <= 0 and int(racer.get("recovery_helpers", 0)) == 0:
				to_remove.append(racer)
		if moving_before:
			var contact = stage.rock_hit(racer.previous, node.position, 0.85)
			if not contact.is_empty():
				racer.motion.velocity = (node.position - racer.previous) / maxf(delta, 0.001)
				racer.motion.velocity.y = 0
				node.position = contact.position
				racer.motion.rock_impulse(contact.normal, node.rotation.y)
				racer.state = "rock_bounce"
				racer.age = 0.0
				count_racer(racer)
		if stage.urban and moving_before:
			var city_hit = stage.city.hit(racer.previous, node.position, 0.85)
			if not city_hit.is_empty():
				var velocity: Vector3 = (node.position - racer.previous) / maxf(delta, 0.001)
				knock_city(city_hit, velocity)
				node.position = city_hit.position
				racer.motion.velocity = velocity
				racer.motion.velocity.y = 0
				racer.motion.rock_impulse(city_hit.normal, node.rotation.y)
				racer.state = "rock_bounce"
				racer.age = 0.0
				count_racer(racer)
		if racer.state in ["racing", "offroad", "rock_bounce"]:
			var tree_hit = stage.obstacle_hit(racer.previous, node.position, 0.95)
			if tree_hit >= 0:
				if not stage.fallen.has(tree_hit):
					knock_tree(tree_hit, node.position - racer.previous)
				else:
					racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
					racer.age = 0
			if Motion.swept_hit(racer.previous + Vector3(0, 0.7, 0), node.position + Vector3(0, 0.7, 0), player_position() + Vector3(0, 0.7, 0), 2.6 if in_car else 1.65):
				die("Раллийная машина попала в тебя.\nНа этом выезд закончился.")
				return
		if racer.state in ["racing", "offroad", "rock_bounce"]:
			var blockers = [car.position]
			for peer in room.peers.values():
				if peer.state != null:
					blockers.append(room.v(peer.state.car))
			for other in racers:
				if other.id < racer.id or other.state in ["stopped", "stranded"]:
					blockers.append(other.node.position)
			for blocker in blockers:
				if Motion.swept_hit(racer.previous + Vector3(0, 0.65, 0), node.position + Vector3(0, 0.65, 0), blocker + Vector3(0, 0.65, 0), 2.5):
					node.position = racer.previous
					racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
					racer.age = 0
					toast("Столкновение машин! Экипаж остановился.")
					break
		if racer.state in ["stranded", "stopped"]:
			count_racer(racer)
		var d = node.position.distance_to(player_position())
		if d < nearest_d and racer.state in ["racing", "offroad"]:
			nearest = node
			nearest_d = d
	for racer in to_remove:
		racer.node.queue_free()
		racers.erase(racer)
		if racer.get("role", "racer") != "racer":
			course.vehicle_finished(self, racer.id)
	if nearest != null:
		rally_audio.position = nearest.position
		rally_audio.pitch_scale = 1.8
		if not rally_audio.playing:
			_play_audio(rally_audio)
	else:
		rally_audio.stop()

func stone_impact(id: String) -> void:
	impact_serials[id] = int(impact_serials.get(id, 0)) + 1
	if id == room.player_id or id == "local":
		impact_shake = 0.8
		if in_car:
			condition = maxf(0, condition - 0.8)
		toast("Гравий из-под колёс! Отойди дальше от края СУ.")

func _update_stones(delta: float) -> void:
	stone_clock -= delta
	if stone_clock <= 0:
		stone_clock = 0.09
		for racer in racers:
			if racer.state != "racing" or racer.get("drive_speed", 27.0) < 4 or not racer.motion.grounded or stones.size() >= 48:
				continue
			if stage.urban and stage.road_distance(racer.node.position) < Stage.WIDTH * 0.7:
				continue # Clean asphalt does not throw a constant stream of gravel.
			var s: float = racer.s
			var direction = stage.direction(s)
			var side = stage.side(s) * (-1.0 if rng.randf() < 0.5 else 1.0)
			var node = Props.box(self, Vector3.ZERO, Vector3.ONE * rng.randf_range(0.07, 0.14), Color("9b9079"))
			node.position = racer.node.position - direction * 1.6 + side * 0.65 + Vector3(0, 0.25, 0)
			stone_serial += 1
			stones.append({"id": stone_serial, "node": node, "velocity": direction * rng.randf_range(-5, 3) + side * rng.randf_range(5, 12) + Vector3(0, rng.randf_range(3, 7), 0), "life": 2.0, "bounces": 0})
	for stone in stones.duplicate():
		var previous: Vector3 = stone.node.position
		var alive = _advance_gravel(stone, delta)
		stone.life -= delta
		stone.node.rotation += Vector3(7, 4, 6) * delta
		var hit = Motion.swept_hit(previous, stone.node.position, player_position() + Vector3(0, 1.0, 0), 1.2 if in_car else 0.55)
		if hit:
			stone_impact(room.player_id if room.connected else "local")
		if room.connected:
			for peer in room.peers.values():
				if peer.state != null and Motion.swept_hit(previous, stone.node.position, room.v(peer.state.pos) + Vector3(0, 1.0, 0), 1.2 if peer.state.in_car else 0.55):
					stone_impact(peer.id)
					hit = true
		if hit or stone.life <= 0 or not alive:
			stone.node.queue_free()
			stones.erase(stone)

func walking_intent() -> Vector3:
	if in_car or seated or jump_height > 0.01 or paused or dead or finished or beers >= 30 or drink_time >= 0 or eat_time >= 0:
		return Vector3.ZERO
	var input = Vector2(Input.get_axis("left", "right"), Input.get_axis("forward", "back")).limit_length(1)
	return Vector3(input.x, 0, input.y).rotated(Vector3.UP, view_yaw)

func _update_tow(delta: float) -> void:
	Recovery.update(self, {"local": room.local_state()}, delta)

func _clear_recovery_ropes() -> void:
	for rope in recovery_ropes:
		if is_instance_valid(rope):
			rope.queue_free()
	recovery_ropes.clear()
	rope_mesh = null

func draw_recovery_ropes() -> void:
	_clear_recovery_ropes()
	for link in recovery_links:
		for racer in racers:
			if racer.id != int(link.racer):
				continue
			var origin = room.v(link.pos)
			if link.player == room.player_id or (not room.connected and link.player == "local"):
				origin = walker
			elif room.peers.has(link.player) and room.peers[link.player].has("avatar"):
				origin = room.peers[link.player].avatar.position
			var rope = Props.rope(self, origin + Vector3(0, 1, 0), racer.node.position + Vector3(0, 0.5, 0))
			recovery_ropes.append(rope)
			if rope_mesh == null:
				rope_mesh = rope

func _cancel_tow() -> void:
	tow_target = null
	tow_progress = 0
	recovery_links.clear()
	recovery_helpers = 0
	_clear_recovery_ropes()

func toast(message: String) -> void:
	if mobile_mode:
		var labels = {"Q —": "Поляна —", "Space —": "Тормоз —", "F —": "Действие —", "Z —": "Стол —", "C —": "Стулья —", "G —": "Мангал —", "X —": "Есть —", "R —": "Заезды —", "— T": "— Трос", ": E.": ": Выйти.", "нажми X": "нажми Есть", "Удерживай T": "Удерживай Трос"}
		for key in labels:
			message = message.replace(key, labels[key])
	if toast_label != null:
		toast_label.text = message
		toast_label.visible = not mobile_mode
		toast_time = 5

func _update_hud() -> void:
	course_label.text = course.caption()
	var distance = int(player_position().distance_to(stage.clearings[target_clearing]))
	quest_label.text = "%s Найти место  ·  %d м\n%s Разложить стол\n%s Поставить стулья\n%s Пожарить и съесть шашлык\n%s Посмотреть %d экипажей" % ["[x]" if camp != null else "[ ]", distance, "[x]" if camp != null else "[ ]", "[x]" if has_chairs else "[ ]", "[x]" if eaten else "[ ]", "[x]" if passed >= RALLY_CREW_LIMIT else "[ ]", RALLY_CREW_LIMIT]
	status_label.text = "ЭКИПАЖИ %d/%d   ·   ПОМОЩЬ %d\nПИВО %d   ·   ВЫЕЗД %02d:%02d" % [passed, RALLY_CREW_LIMIT, helped, beers, int(elapsed) / 60, int(elapsed) % 60]
	if in_car:
		info_label.text = "%02d КМ/Ч    ·    ЛЕГКОВУШКА %d%%    ·    %s" % [int(absf(speed) * 3.6), int(condition), "ОБОЧИНА" if stage.road_distance(car.position) > 4 else "ГРАВИЙ / КОЛЕЯ"]
		hint_label.text = "WASD / стрелки — газ и руль   ·   Space — тормоз   ·   F — выйти   ·   Q — случайная поляна   ·   Home — вернуть на СУ"
	else:
		var cook_status = "ШАШЛЫК ГОТОВ" if cook_time >= 35 else ("ШАШЛЫК %d%%" % int(cook_time / 35 * 100) if cooking else "МАНГАЛ НЕ РАЗОЖЖЁН")
		info_label.text = "ЗРИТЕЛЬ    ·    %s · ШАМПУРЫ %d/16    ·    %s" % [cook_status, grill_servings, course.caption()]
		hint_label.text = "WASD — идти   ·   Shift — бег   ·   Space — прыжок   ·   мышь — смотреть   ·   F — действие   ·   Z — стол   ·   C — стулья   ·   G — мангал   ·   R — статус СУ"
		if drink_time >= 0:
			info_label.text = "ОТКРЫВАЕМ БАНКУ" if drink_time < 1.25 else "ЗА ХОРОШИЙ ВЫЕЗД!"
		if eat_time >= 0:
			info_label.text = "ЕДИМ ЯГОДЫ" if eat_kind == "berries" else ("ЕДИМ ГРИБЫ" if eat_kind == "mushroom" else "ЕДИМ ШАШЛЫК")
		if beers >= 30:
			info_label.text = "ТЫ ЛЕЖИШЬ · ХОДИТЬ БОЛЬШЕ НЕ ПОЛУЧИТСЯ"
		if tow_target != null:
			info_label.text = "ПОМОЩЬ %d%% · УЧАСТНИКОВ %d" % [int(tow_progress * 100), recovery_helpers]
	if tow_target != null:
		info_label.text = "ВЫТАСКИВАЕМ ЭКИПАЖ   ·   %d%%   ·   УДЕРЖИВАЙ T" % int(tow_progress * 100)
	elif nearby_tow_racer():
		hint_label.text += "   ·   Иди в машину, чтобы толкать · T — тяни пешком со стороны дороги"
	if not in_car:
		var bag = foraging.stock()
		status_label.text += "\nГРИБЫ %d · ЯГОДЫ %d" % [bag.mushrooms, bag.berries]
		var target = interaction.current()
		if not target.is_empty():
			hint_label.text = "F — " + target.label + "   ·   Z/C/G/V — поставить предмет"
		elif seated:
			hint_label.text = "F — встать со стула"
		if foraging.can_eat("berries"):
			hint_label.text += " · K — съесть ягоды"
	if mobile_mode:
		if in_car and tow_target == null:
			info_label.text = "%02d КМ/Ч · МАШИНА %d%% · %s %d м" % [int(absf(speed) * 3.6), int(condition), "ПАРКОВКА" if stage.urban else "ПОЛЯНА", distance]
		else:
			info_label.text = info_label.text.replace("ЗРИТЕЛЬ    ·    ", "").replace("УДЕРЖИВАЙ T", "УДЕРЖИВАЙ ТРОС")
		if toast_time > 0:
			info_label.text += "\n" + toast_label.text
		elif not in_car and not interaction.current().is_empty():
			info_label.text += "\nF — " + interaction.current().label
	if mobile_mode and not in_car:
		var bag = foraging.stock()
		info_label.text += "\nГрибы %d · Ягоды %d" % [bag.mushrooms, bag.berries]
	crosshair.visible = playing and not in_car and not paused and not dead and not finished and placement_kind == ""
	crosshair.text = "+" if not interaction.current().is_empty() else "·"
	minimap.queue_redraw()

func _check_finish() -> void:
	if dead:
		return
	if camp != null and has_chairs and eaten and eat_time < 0 and passed >= RALLY_CREW_LIMIT and course.phase == "complete":
		finished = true
		_show_result("Идеальный раллийный овощ", "Шашлык съеден. Ралли посмотрено. Ты выжил.\n\nЭкипажи: %d  ·  Помощь тросом: %d\nПиво: %d  ·  Машина: %d%%\n\nРаллийный выезд удался." % [passed, helped, beers, condition])

func die(reason: String) -> void:
	dead = true
	_show_result("Выезд окончен", reason + "\n\nЭкипажи: %d  ·  Помощь тросом: %d\nШашлык: %s" % [passed, helped, "съеден" if eaten else "не съеден"])

func _show_result(title: String, body: String) -> void:
	cancel_placement()
	_cancel_drink()
	_cancel_eat()
	menu.show()
	menu_title.text = title
	menu_text.text = body
	start_button.text = "НОВЫЙ ВЫЕЗД"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	engine_audio.stop()
	rally_audio.stop()
	fire_audio.stop()

func _prepare_capture() -> void:
	target_clearing = 1
	car.position = stage.clearings[1] + Vector3(5, 0, 2)
	car.position.y = stage.ground(car.position)
	heading = -0.3
	car.rotation.y = heading
	in_car = false
	walker = stage.clearings[1] + Vector3(0, 0, 3)
	walker.y = stage.ground(walker)
	view_yaw = 0
	place_table()
	place_chairs()
	start_grill()
	course.phase = "racing" # Explicit visual capture fixture, outside normal gameplay.
	start_rally()
	spawn_racer("pass")
	var racer = racers[0]
	racer.s = 270.0
	racer.focus = 360.0
	camera.position = camp.position + Vector3(10, 5, 12)
	camera.look_at(camp.position + Vector3(-5, 0.8, -3))
	_update_hud()

func _capture_menu() -> void:
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../preview-menu.png")
	await _shutdown_audio()
	get_tree().quit()

func _shutdown_audio() -> void:
	for audio in [engine_audio, rally_audio, wind_audio, fire_audio, beer_audio]:
		audio.stop()
	await get_tree().create_timer(0.15).timeout

func _play_audio(audio: Node) -> void:
	if DisplayServer.get_name() != "headless":
		audio.play()

# Also used by guests for prediction between authoritative room snapshots.
func _advance_gravel(stone: Dictionary, delta: float) -> bool:
	var previous: Vector3 = stone.node.position
	var next: Vector3 = previous + stone.velocity * delta + Vector3(0, -4.9 * delta * delta, 0)
	stone.velocity.y -= 9.8 * delta
	var contact = stage.city.hit(previous, next, 0.06, true, Vector3.ZERO) if stage.urban else stage.rock_hit(previous, next, 0.06)
	if not contact.is_empty():
		next = contact.position
		var normal: Vector3 = contact.normal
		var closing = stone.velocity.dot(normal)
		if closing < 0:
			stone.velocity -= normal * closing * 1.4
			stone.velocity *= 0.7
			stone.bounces = int(stone.get("bounces", 0)) + 1
	var floor_height = stage.ground(next) + 0.05
	var alive = true
	if next.y <= floor_height:
		next.y = floor_height
		if stone.velocity.y < 0:
			stone.bounces = int(stone.get("bounces", 0)) + 1
			alive = stone.bounces <= 2 and absf(stone.velocity.y) > 1.0
			stone.velocity = Vector3(stone.velocity.x * 0.58, -stone.velocity.y * 0.4, stone.velocity.z * 0.58)
	stone.node.position = next
	return alive and int(stone.get("bounces", 0)) <= 2

func can_tow_racer(racer: Dictionary) -> bool:
	return racer.state in ["stranded", "stopped"] and is_instance_valid(racer.node)

func nearby_tow_racer() -> bool:
	for racer in racers:
		if not in_car and can_tow_racer(racer) and walker.distance_to(racer.node.position) < 6:
			return true
	return false

func recover_racer(racer: Dictionary) -> void:
	# Restart ahead of the impact, with no old slide/impulse or swept crash path.
	racer.s = clampf(stage.road_s(racer.node.position) + 12.0, 0, Stage.LENGTH - 2)
	racer.node.position = stage.at(racer.s)
	var direction = stage.direction(racer.s)
	racer.node.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	racer.previous = racer.node.position
	racer.start = racer.node.position
	racer.target = racer.node.position
	racer.motion = Motion.new()
	racer.slide = 0.0
	racer.slide_speed = 0.0
	racer.line = 0.0
	racer.avoiding = false
	racer.avoid_line = 0.0
	racer.drive_speed = stage.rally_speed(racer.s) * racer.get("pace", 1.0)
	racer.state = "racing"
	racer.kind = "pass"
	count_racer(racer)
	racer.age = 0.0
	for key in ["recovery_start", "recovery_goal", "recovery_progress", "recovery_helpers"]:
		racer.erase(key)
	helped += 1

func count_racer(racer: Dictionary) -> void:
	if racer.get("role", "racer") != "racer" or racer.get("counted", false):
		return
	racer.counted = true
	passed = mini(RALLY_CREW_LIMIT, passed + 1)

func knock_city(contact: Dictionary, velocity: Vector3) -> void:
	if contact.get("kind", "") != "lamp" or velocity.length() <= 5:
		return
	if room.connected and not room.is_host:
		lamp_requests[int(contact.id)] = velocity
	else:
		stage.city.knock_lamp(int(contact.id), velocity)

func sit_down() -> void:
	var owner = chair_owner()
	if not personal_chairs.has(owner) or in_car or beers >= 30 or jump_height > 0.01 or jump_velocity > 0:
		return
	seat_exit = walker
	var chair: Node3D = personal_chairs[owner]
	walker = chair.position
	view_yaw = chair.rotation.y
	seated = true
	toast("F — встать. Мышь — смотреть.")

func stand_up() -> void:
	seated = false
	walker = seat_exit
	walker.y = stage.ground(walker)
