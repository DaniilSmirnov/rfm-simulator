extends Node3D

var cargo = preload("res://scripts/car_cargo.gd").new()
var camp_cooking = preload("res://scripts/camp_cooking.gd").new()
var packing = preload("res://scripts/camp_packing.gd").new()
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

const RallyHandling = preload("res://scripts/rally_handling.gd")
const Props = preload("res://scripts/props.gd")
const Stage = preload("res://scripts/stage.gd")
const Spectators = preload("res://scripts/spectators.gd")
var spectators: Node3D
const MiniMap = preload("res://scripts/minimap.gd")
var stage: RallyStage
var menu_content: VBoxContainer
var platform_service: Node
var selected_stage = 0
var selected_car = 0
# Headless fixtures may construct synchronously; real clients enter a lightweight menu.
var defer_world = DisplayServer.get_name() != "headless" and not ("--script" in OS.get_cmdline_args() or "--capture" in OS.get_cmdline_user_args() or "--smoke-test" in OS.get_cmdline_user_args())
var world_ready = false
var loading_world = false
var loading_screen: Node

var lobby_ui: Node
var selection_controls: VBoxContainer
var car_choice: HBoxContainer
var stage_choice: HBoxContainer
var fps_label: Label
var fps_clock = 0.0
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
	if kind not in ["firewood", "cauldron"] and camp_cooking.fire != null and spot.distance_to(camp_cooking.fire.position) < 1.5:
		return false
	if kind not in ["firewood", "cauldron"] and camp_cooking.pot != null and spot.distance_to(camp_cooking.pot.position) < 1.5:
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
	if packing.active():
		toast("Выезд завершён. Соберите предметы через F.")
		return
	if seated:
		stand_up()
	if in_car or beers >= 30:
		toast("Для размещения выйди из машины и встань на ноги.")
		return
	if kind in cargo.KINDS and not cargo.take(kind):
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
		"firewood": Props.campfire(placement_preview)
		"cauldron": Props.cauldron(placement_preview)
		"flag": Props.rally_fans_map_flag(placement_preview, Vector3.ZERO, 0.0, flag_count())
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
	if placement_kind == "cauldron" and camp_cooking.fire != null and spot.distance_to(camp_cooking.fire.position) < 1.5:
		spot = camp_cooking.fire.position
	if placement_kind == "firewood" and camp_cooking.pot != null and spot.distance_to(camp_cooking.pot.position) < 1.5:
		spot = camp_cooking.pot.position
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
			"table", "chairs", "grill", "firewood", "cauldron": cargo.deploy(kind, spot, yaw)
			"flag": place_flag(spot, yaw)
	soundscape.placement()
	cancel_placement()

var cooking = false
var cook_time = 0.0
var grill_servings = Props.FOOD_PORTIONS
var eat_source_group = -2
var eat_kind = "meat"
var food_species = "edible"
var mushroom_effect = preload("res://scripts/mushroom_effect.gd").new()
var forage_source = -2
var foraging = preload("res://scripts/foraging.gd").new()
var eaten = false
var drunk_phase = 0.0
var drunk_strength = 0.0
const DRUNK_FADE_SECONDS = 60.0
var collapse_time = 0.0
const SOBER_SECONDS = 180.0
var sober_remaining = 0.0
var sobriety_panel: PanelContainer
var sobriety_label: Label
var sobriety_bar: ProgressBar
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
var soundscape: Node
var capture_mode = false
var hud_panels: Array[Control] = []
var room: Node
var mobile_mode = false
var mobile_controls: Control
var mobile_sidebar: PanelContainer
var mobile_top: PanelContainer
var mobile_bottom: PanelContainer
var mobile_ui: Control
var mobile_safe_rect = Rect2()
var mobile_safe_timer = 0.0
var mobile_safe_http: HTTPRequest

func enable_mobile() -> void:
	if mobile_mode:
		return
	mobile_mode = true
	get_window().content_scale_size = Vector2i(960, 540)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	print("[RFM] Мобильный интерфейс: масштаб окна готов")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title_label.text = "Rally Fans Simulator"
	title_label.hide()
	# These HUD labels start empty. Let wrapping calculate their lines on draw
	# rather than recalculating visible lines before the Web text server shapes them.
	course_label.add_theme_font_size_override("font_size", 14)
	course_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mobile_top.get_child(0).get_child(1).hide()
	mobile_top.position = Vector2(24, 20)
	mobile_top.size = Vector2(360, 0)
	mobile_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mobile_bottom.offset_left = 200
	mobile_bottom.offset_right = -224
	mobile_bottom.offset_top = -148
	mobile_bottom.offset_bottom = -24
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.max_lines_visible = 4
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.hide()
	quest_label.hide()
	mobile_sidebar.get_child(0).get_child(0).hide()
	mobile_sidebar.offset_left = -280
	mobile_sidebar.offset_right = -36
	mobile_sidebar.offset_top = 96
	mobile_sidebar.offset_bottom = 282
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
	menu_content.add_theme_constant_override("separation", 6)
	menu_content.get_child(0).hide()
	menu_title.add_theme_font_size_override("font_size", 26)
	menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_text.add_theme_font_size_override("font_size", 18)
	menu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_text.text = "Доедь до поляны, разложи лагерь и посмотри ралли. Жарь шашлык, помогай экипажам и береги себя."
	print("[RFM] Мобильный интерфейс: панели готовы")
	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	mobile_controls = preload("res://scripts/mobile_controls.gd").new()
	mobile_controls.game = self
	layer.add_child(mobile_controls)
	print("[RFM] Мобильный интерфейс: контроллы готовы")

func apply_mobile_safe_rect(rect: Rect2) -> void:
	if rect == mobile_safe_rect:
		return
	mobile_safe_rect = rect
	mobile_controls.reset_input()
	# Insets move anchors; they must never shrink gameplay buttons or text.
	for control in [mobile_ui, mobile_controls]:
		control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		control.position = rect.position
		control.scale = Vector2.ONE
		control.size = rect.size
	# The world still fills the canvas and aiming stays at the camera centre.
	crosshair.position = get_viewport().get_visible_rect().size / 2 - rect.position - crosshair.size / 2
	fit_mobile_dialogs()

func fit_mobile_dialogs() -> void:
	if not mobile_mode or not mobile_safe_rect.has_area():
		return
	for dialog in [menu]:
		var minimum = dialog.get_combined_minimum_size()
		var extent = Vector2(maxf(620, minimum.x), maxf(390, minimum.y))
		var factor = minf(1.0, minf((mobile_ui.size.x - 24) / extent.x, (mobile_ui.size.y - 24) / extent.y))
		dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		dialog.offset_left = -extent.x / 2
		dialog.offset_right = extent.x / 2
		dialog.offset_top = -extent.y / 2
		dialog.offset_bottom = extent.y / 2
		dialog.pivot_offset = extent / 2
		dialog.scale = Vector2.ONE * factor

func update_mobile_safe_area(delta: float) -> void:
	if not mobile_mode or not OS.has_feature("web"):
		return
	if mobile_safe_http == null:
		mobile_safe_http = HTTPRequest.new()
		mobile_safe_http.accept_gzip = false
		mobile_safe_http.timeout = 2.0
		mobile_safe_http.body_size_limit = 1024
		add_child(mobile_safe_http)
		mobile_safe_http.request_completed.connect(_mobile_safe_response)
	mobile_safe_timer -= delta
	if mobile_safe_timer > 0.0 or mobile_safe_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	mobile_safe_timer = 0.25
	# Like profile bootstrap, this is intercepted locally by the browser shell.
	# The minimal engine has neither eval nor JavaScript object interfaces.
	mobile_safe_http.request(room.server + "/__rally_viewport")

func _mobile_safe_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.has_all(["width", "height", "left", "right", "top", "bottom"]):
		return
	var extent = get_viewport().get_visible_rect().size
	var ratio = extent / Vector2(maxf(float(data.width), 1.0), maxf(float(data.height), 1.0))
	var origin = Vector2(float(data.left), float(data.top)) * ratio
	var end = extent - Vector2(float(data.right), float(data.bottom)) * ratio
	apply_mobile_safe_rect(Rect2(origin, end - origin))

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not mobile_mode:
		enable_mobile()

const Traffic = preload("res://scripts/rally_traffic.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
var vehicle_motion = Motion.new()
var stones: Array[Dictionary] = []
var gravel_pool: Array[MeshInstance3D] = []
var stone_serial = 0
var impact_serials: Dictionary = {}
var impact_shake = 0.0
var stone_clock = 0.0

func _ready() -> void:
	print("[RFM] Подготовка игрового мира")
	foraging.game = self
	interaction.game = self
	packing.game = self
	cargo.game = self
	camp_cooking.game = self
	rng.randomize()
	_setup_input()
	stage = Stage.new()
	add_child(stage)
	if not defer_world:
		stage.build()
		world_ready = true
	print("[RFM] Лёгкое меню: карта будет подготовлена при входе" if defer_world else "[RFM] Рельеф и объекты карты готовы")
	_build_environment()
	spectators = Spectators.new()
	spectators.game = self
	add_child(spectators)
	if world_ready:
		spectators.rebuild()
	print("[RFM] Зрители и машина готовы к созданию")
	car = Node3D.new() if defer_world else Props.player_car(0)
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
	if lobby_ui != null:
		lobby_ui.refresh()
	_build_ui()
	loading_screen = preload("res://scripts/loading_screen.gd").new()
	loading_screen.game = self
	add_child(loading_screen)
	mushroom_effect.setup(self)
	print("[RFM] Интерфейс готов; подготовка звука")
	_setup_audio()
	print("[RFM] Звук подготовлен; создание интерфейса комнаты")
	room = preload("res://scripts/room.gd").new()
	room.game = self
	add_child(room)
	print("[RFM] Интерфейс комнаты готов")
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
	platform_service = preload("res://scripts/platform_service.gd").new()
	platform_service.profile_ready.connect(func(profile):
		if profile.get("platform", "standalone") != "standalone":
			room.name_input.text = str(profile.get("nickname", ""))
			room.name_input.editable = false
		for i in range(car_choice.items.size()):
			car_choice.items[i] = Props.PLAYER_MODELS[i].name
		for i in range(stage_choice.items.size()):
			stage_choice.items[i] = Stage.STAGES[i].get_slice("·", 0).strip_edges()
		car_choice.select(selected_car)
		stage_choice.select(selected_stage)
		lobby_ui.refresh()
	)
	platform_service.purchase_changed.connect(func(): lobby_ui.refresh())
	platform_service.failed.connect(func(message): push_error(message))
	add_child(platform_service)
	print("[RFM] Запуск завершён")

func _setup_input() -> void:
	var bindings = {"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "brake": [KEY_SPACE], "jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "interact": [KEY_F], "table": [KEY_Z], "flag": [KEY_V], "chairs": [KEY_C], "grill": [KEY_G], "firewood": [KEY_J], "cauldron": [KEY_H], "beer": [KEY_B], "eat": [], "collect": [], "mount_mushroom": [], "eat_mushroom": [], "eat_berries": [KEY_K], "rally": [KEY_R], "tow": [KEY_T], "map": [KEY_M], "recover": [KEY_HOME], "pause_demo": [KEY_ESCAPE], "placement_confirm": [KEY_ENTER], "placement_rotate": [KEY_Q], "placement_cancel": []}
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
	mobile_ui = ui
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
	title_label = _label(vb, "Rally Fans Simulator", 22)
	stage_caption = _label(vb, Stage.STAGES[selected_stage], 12, Color("b2bea1"))
	fps_label = _label(vb, "v%s · — FPS" % ProjectSettings.get_setting("application/config/version"), 12, Color("b2bea1"))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	sobriety_panel = PanelContainer.new()
	ui.add_child(sobriety_panel)
	sobriety_panel.anchor_left = 0.25
	sobriety_panel.anchor_right = 0.75
	sobriety_panel.offset_top = 150
	sobriety_panel.offset_bottom = 245
	sobriety_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sobriety_panel.add_theme_stylebox_override("panel", _panel(Color("25352bf2")))
	var recovery_box = VBoxContainer.new()
	recovery_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sobriety_panel.add_child(recovery_box)
	sobriety_label = _label(recovery_box, "", 22, Color("fff0cb"))
	sobriety_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sobriety_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sobriety_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sobriety_bar = ProgressBar.new()
	sobriety_bar.max_value = SOBER_SECONDS
	sobriety_bar.custom_minimum_size.y = 24
	sobriety_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var recovery_fill = StyleBoxFlat.new()
	recovery_fill.bg_color = Color("ee531b")
	sobriety_bar.add_theme_stylebox_override("fill", recovery_fill)
	recovery_box.add_child(sobriety_bar)
	sobriety_panel.hide()
	menu = PanelContainer.new()
	ui.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -350
	menu.offset_right = 350
	menu.offset_top = -270
	menu.offset_bottom = 270
	menu.add_theme_stylebox_override("panel", _panel(Color("23342bf5")))
	var mv = VBoxContainer.new()
	menu_content = mv
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_theme_constant_override("separation", 12)
	menu.add_child(mv)
	_label(mv, "ПЕРЕВАЛ. РАЛЛИ. ШАШЛЫК.", 14, Color("dfb270"))
	menu_title = _label(mv, "", 34)
	menu_text = _label(mv, "", 17)
	menu_title.hide()
	menu_text.hide()
	selection_controls = VBoxContainer.new()
	selection_controls.add_theme_constant_override("separation", 8)
	mv.add_child(selection_controls)
	lobby_ui = preload("res://scripts/lobby_ui.gd").new()
	lobby_ui.game = self
	add_child(lobby_ui)
	var cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	selection_controls.add_child(cards)
	for kind in ["МАШИНА", "СПЕЦУЧАСТОК"]:
		var card = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		_label(card, kind, 14, Color("dfb270"))
		lobby_ui.add_preview(card, kind)
		var row = HBoxContainer.new()
		card.add_child(row)
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
				choice.add_item(title.get_slice("·", 0).strip_edges())
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
	start_button.hide()
	lobby_ui.finish(mv)

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
	# 20% of the previous cooking/fire linear gain (about -14 dB).
	fire_audio.volume_db = -26
	add_child(fire_audio)
	beer_audio = AudioStreamPlayer.new()
	beer_audio.volume_db = -10
	add_child(beer_audio)
	soundscape = preload("res://scripts/soundscape.gd").new()
	soundscape.game = self
	add_child(soundscape)

func prepare_world() -> void:
	if world_ready or loading_world:
		return
	loading_world = true
	loading_screen.show_loading()
	await stage.build_async(loading_screen.stage_progress)
	await loading_screen.stage_progress("Зрители и лагерь", 85)
	await spectators.rebuild(true)
	await loading_screen.stage_progress("Машина", 95)
	var previous = car.transform
	car.free()
	car = Props.player_car(selected_car)
	add_child(car)
	car.transform = previous
	await loading_screen.stage_progress("Готово", 100)
	world_ready = true
	loading_world = false
	loading_screen.hide_loading()

func start_game() -> void:
	if platform_service != null and (not platform_service.can_use("car", car_choice.selected) or not platform_service.can_use("stage", stage_choice.selected, room.connected and not room.is_host)):
		toast("Выбранный контент недоступен в VK. Дождитесь загрузки прав или выберите бесплатный вариант.")
		return
	if playing:
		return
	if loading_world:
		return
	if not world_ready:
		await prepare_world()
	playing = true
	soundscape.repair()
	course.apply_snapshot({})
	racing = false
	selection_controls.hide()
	room.lobby.hide()
	start_button.show()
	menu.hide()
	course_label.show()
	course_label.text = course.caption()
	for panel in hud_panels:
		panel.show()
	mobile_sidebar.show()
	# Automated startup has no browser user gesture. Pointer lock is tested separately.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mobile_mode or "--smoke-test" in OS.get_cmdline_user_args() or (room.connected and OS.has_feature("web")) else Input.MOUSE_MODE_CAPTURED
	toast("Найди подходящее место и разложи лагерь. Установка стола засчитывает выбор места.")

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
		room.connect_room("")

func return_to_main_menu() -> void:
	lobby_ui.return_button.disabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if room.connected:
		room.leave()
	else:
		get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if placement_kind != "":
		if event.is_action_pressed("pause_demo") or event.is_action_pressed("placement_cancel"):
			cancel_placement()
			return
		if not paused and not dead and not finished and not (room.connected and not room.is_host and room.world_paused):
			if event.is_action_pressed("interact") or event.is_action_pressed("placement_confirm") or event.is_action_pressed(placement_kind):
				confirm_placement()
				return
			if event.is_action_pressed("placement_rotate"):
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
		menu_text.text = "Выезд приостановлен. Продолжить или вернуться в меню." if not room.connected or room.is_host else "Твоя пауза. Остальные игроки продолжают выезд."
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
	for furniture_action in ["table", "chairs", "grill", "flag", "firewood", "cauldron"]:
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
		if shared_action not in ["eat", "eat_plov", "plov_cook", "pack", "trunk", "take_gear", "return_gear"] and event.is_action_pressed(shared_action) and room.submit(shared_action):
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
	elif event.is_action_pressed("recover"):
		if not racing:
			if room.connected and room.recover_drive():
				return
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

func _update_fps_counter(delta: float) -> void:
	fps_clock += delta
	if fps_clock < 0.5 or fps_label == null:
		return
	fps_clock = fmod(fps_clock, 0.5)
	var fps = Engine.get_frames_per_second()
	if fps > 0:
		_set_hud_text(fps_label, "v%s · %d FPS" % [ProjectSettings.get_setting("application/config/version"), fps])

func _process(delta: float) -> void:
	_update_fps_counter(delta)
	if soundscape != null:
		soundscape.update(delta)
	camp_cooking.animate_flames(Time.get_ticks_msec() / 1000.0)
	if not playing or paused or dead or finished or (room.connected and not room.is_host and room.world_paused):
		return
	if not room.connected or room.is_host:
		elapsed += delta
		course.update(self, delta)
	elif course.phase in ["countdown", "intermission"]:
		course.remaining = maxf(0, course.remaining - delta)
	stage.update_fallen(delta)
	_update_sobriety(delta)
	_update_intoxication(delta)
	if in_car:
		_drive(delta)
	else:
		_walk(delta)
	_update_drinking(delta)
	mushroom_effect.update(delta)
	_update_eating(delta)
	_update_camera(delta)
	if room.connected and room.prediction_enabled:
		camera.position += room.prediction.visual_offset
	room.smooth_car_visuals()
	_update_placement()
	cargo.update(delta)
	camp_cooking.update(delta, room.connected and not room.is_host)
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

func _update_sobriety(delta: float) -> void:
	if not playing or paused or dead or finished or (room.connected and not room.is_host and room.world_paused):
		return
	if beers < 30:
		sober_remaining = 0.0
		return
	if sober_remaining <= 0:
		sober_remaining = SOBER_SECONDS
	sober_remaining = maxf(0, sober_remaining - delta)
	if sober_remaining <= 0:
		beers = 0
		drunk_strength = 0
		drunk_phase = 0
		collapse_time = 0
		beer_timer = 0
		sobriety_panel.hide()
		toast("Ты протрезвел. Можно встать, собрать вещи и вернуться в машину.")

func _update_intoxication(delta: float) -> void:
	drunk_strength = maxf(0.0, drunk_strength - delta / DRUNK_FADE_SECONDS)
	if drunk_strength > 0:
		drunk_phase = fposmod(drunk_phase + delta * 1.25, TAU)
	else:
		drunk_phase = 0.0

func player_position() -> Vector3:
	return car.position if in_car else walker

func _drive(delta: float) -> void:
	if room.connected and room.predict_drive(delta):
		return
	# Carry fractional ticks across render frames; cap long stalls at one second.
	vehicle_motion.drive_clock += clampf(delta, 0, 1.0)
	var dt: float = vehicle_motion.handling.STEP
	var steps = int(floor((vehicle_motion.drive_clock + 0.000001) / dt))
	vehicle_motion.drive_clock = maxf(0, vehicle_motion.drive_clock - steps * dt)
	var initial_forward = Vector3(-sin(heading), 0, -cos(heading))
	var initial_speed: float = vehicle_motion.velocity.dot(initial_forward)
	# Support explicit resets/recovery without discarding tangential momentum.
	if absf(speed - initial_speed) > 3:
		vehicle_motion.velocity += initial_forward * (speed - initial_speed)
	for step in range(steps):
		var throttle = Input.get_axis("back", "forward")
		var steer = Input.get_axis("left", "right")
		var offroad = stage.road_distance(car.position) > 4.1
		var max_speed = 7.0 if offroad else 19.0
		var braking = Input.is_action_pressed("brake")
		var previous_heading = heading
		heading = vehicle_motion.handling.advance(vehicle_motion, heading, throttle, steer, braking, stage.grip(car.position), max_speed, selected_car, dt)
		var forward = Vector3(-sin(heading), 0, -cos(heading))
		speed = vehicle_motion.velocity.dot(forward)
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
		var travel_yaw = heading + (PI if speed < -0.5 else 0.0)
		view_yaw = lerp_angle(view_yaw, travel_yaw, 1.0 - exp(-delta * 2.8))
		var behind = Vector3(sin(view_yaw), 0, cos(view_yaw))
		var elevation = clampf(atan2(4.4, 8.2) - (view_pitch + 0.12), 0.14, 1.25)
		var distance = Vector2(8.2, 4.4).length()
		var desired = car.position + behind * cos(elevation) * distance + Vector3.UP * sin(elevation) * distance
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
	if not in_car and cargo.held.has(chair_owner()):
		toast("Сначала поставь предмет или верни коробку в багажник.")
		return
	if jump_height > 0.01 or jump_velocity > 0:
		return
	if beers >= 30:
		toast("Ты лежишь. Дождись восстановления — три минуты.")
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
		camp.set_meta("gear_owner", cargo.actor())
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
		if personal_chairs.has(owner):
			return false
		spot = camp.position + Vector3(-1.6, 0, 0.7) if near_camp() else walker + Vector3(-sin(view_yaw), 0, -cos(view_yaw)) * 2.5
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
	var node = Props.rally_fans_map_flag(self, spot, yaw, flags.size())
	node.position.y = stage.ground(spot)
	flags.append(node)
	personal_flags[owner] = flags
	return true

func start_grill(spot: Vector3 = Vector3.INF, yaw: float = 0.0, replicated: bool = false) -> bool:
	var moving = spot != Vector3.INF
	if not replicated and in_car:
		return false
	if cooking and not moving:
		return false
	if not moving:
		spot = camp.position + Vector3(0.3, 0, -2.4) if camp != null else walker + Vector3(-sin(view_yaw), 0, -cos(view_yaw)) * 2.5
	if not replicated and not valid_furniture_spot(spot, "grill"):
		return false
	if grill != null:
		grill.position = spot
		grill.position.y = stage.ground(spot)
		grill.rotation.y = yaw
		fire_audio.position = grill.position
		return true
	grill = Props.grill(self)
	grill.set_meta("gear_owner", cargo.actor())
	grill_servings = Props.FOOD_PORTIONS
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
	# Fire crackle is scheduled sparsely by Soundscape instead of looping continuously.
	toast("Угли разгорелись. Шашлык готовится 35 секунд. Следи за таймером СУ.")
	return true

func _update_cooking(delta: float) -> void:
	if cooking and cook_time < 35:
		cook_time = minf(35, cook_time + delta)
		if cook_time >= 35:
			toast("Шашлык готов! Подойди к лагерю и нажми X.")

func drink_beer() -> bool:
	if beers >= 30:
		return false
	if cargo.held.has(chair_owner()):
		return false
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
			sober_remaining = SOBER_SECONDS
			cancel_placement()
			if seated:
				stand_up()
			jump_height = 0
			jump_velocity = 0
			if in_car:
				in_car = false
				walker = car.position
				walker.y = stage.ground(walker)
			walker.y = stage.ground(walker)
			vehicle_motion.velocity = Vector3.ZERO
			speed = 0
			toast("Тридцатая банка. Ты упал. Восстановление займёт три минуты.")
		beer_audio.stream = load("res://audio/beer-sip.wav")
		_play_audio(beer_audio)
	if drink_time >= DRINK_DURATION:
		_cancel_drink()
		if beers < 30:
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
	if loading_world:
		return
	if playing and platform_service != null and not platform_service.can_use("car", posmod(variant, Props.PLAYER_MODELS.size())):
		return
	selected_car = posmod(variant, Props.PLAYER_MODELS.size())
	if car_choice != null:
		car_choice.select(selected_car)
	if defer_world and not world_ready:
		if lobby_ui != null:
			lobby_ui.refresh()
		return
	var transform_before = car.transform
	car.queue_free()
	car = Props.player_car(selected_car)
	add_child(car)
	car.transform = transform_before
	if lobby_ui != null:
		lobby_ui.refresh()

func select_stage(variant: int, hosted_guest: bool = false) -> void:
	if playing or loading_world:
		return
	variant = clampi(variant, 0, Stage.STAGES.size() - 1)
	if variant == selected_stage:
		return
	jump_height = 0
	jump_velocity = 0
	selected_stage = variant
	stage_caption.text = Stage.STAGES[variant]
	stage_choice.select(variant)
	stage.free()
	stage = Stage.new(variant)
	add_child(stage)
	if not defer_world:
		stage.build()
		spectators.rebuild()
	else:
		world_ready = false
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
	if lobby_ui != null:
		lobby_ui.refresh()

func eat_meat(source_group: int = -2) -> bool:
	if cargo.held.has(chair_owner()):
		return false
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

func eat_plov() -> bool:
	if cargo.held.has(chair_owner()) or not camp_cooking.can_eat() or eat_time >= 0 or drink_time >= 0:
		return false
	eat_kind = "plov"
	eat_time = 0
	eat_committed = false
	meat_prop = Props.meat_hand(avatar_variant, "plov")
	camera.add_child(meat_prop)
	_update_eating(0)
	toast("Едим плов из миски. Приятного аппетита!")
	return true

func eat_foraged(kind: String, source: int = -2) -> bool:
	if cargo.held.has(chair_owner()):
		return false
	if source == -2 and not foraging.can_eat(kind):
		return false
	eat_kind = kind
	forage_source = (foraging.nearby_source() if source == -2 else source) if kind == "mushroom" else -2
	if kind == "mushroom" and (foraging.grill_node(forage_source) == null or player_position().distance_to(foraging.grill_node(forage_source).position) > 4 or foraging.ready_index(forage_source) < 0):
		return false
	food_species = foraging.ready_species(forage_source) if kind == "mushroom" else "edible"
	eat_time = 0
	eat_committed = false
	meat_prop = Props.meat_hand(avatar_variant, kind)
	Props.style_mushrooms(meat_prop, food_species)
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
			elif eat_kind == "plov":
				camp_cooking.consume()
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
	racer.pace = 1.0 if role == "zero" else 0.72
	racer.drive_speed = Traffic.speed_limit(self, racer, 0.0)
	racer.bias = 0.0
	racer.phase = 0.0
	toast(course.caption())

func race_station(point: Vector3) -> float:
	var station = stage.road_s(point)
	return Stage.LENGTH - station if course.pass_index == 2 else station

func race_at(progress: float) -> Vector3:
	var station = clampf(progress, 0, Stage.LENGTH)
	return stage.at(Stage.LENGTH - station if course.pass_index == 2 else station)

func race_direction(progress: float) -> Vector3:
	var station = clampf(progress, 0, Stage.LENGTH)
	return -stage.direction(Stage.LENGTH - station) if course.pass_index == 2 else stage.direction(station)

func race_side(progress: float) -> Vector3:
	return race_direction(progress).cross(Vector3.UP).normalized()

func race_speed(progress: float) -> float:
	return stage.rally_speed(Stage.LENGTH - progress if course.pass_index == 2 else progress)

func _add_course_vehicle(node: Node3D, id: int, kind: String, variant: int, role: String = "racer", zero_index: int = 0) -> Dictionary:
	var focus = clampf(race_station(player_position()), 45, Stage.LENGTH - 80)
	add_child(node)
	var s = 0.0
	node.position = race_at(s)
	var direction = race_direction(s)
	node.rotation.y = atan2(-direction.x, -direction.z)
	node.set_meta("room_id", id)
	var driver = Traffic.profile(id)
	var racer = {"bias": driver.bias, "phase": driver.phase, "pace": driver.pace, "line": 0.0, "drive_speed": race_speed(s) * driver.pace, "avoiding": false, "avoid_line": 0.0, "role": role, "zero_index": zero_index, "id": id, "node": node, "s": s, "focus": focus, "kind": kind, "state": "racing", "offset": 0.0, "age": 0.0, "counted": false, "start": Vector3.ZERO, "target": Vector3.ZERO, "variant": variant, "motion": Motion.new(), "previous": node.position, "slide": 0.0, "slide_speed": 0.0}
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
	var racer = _add_course_vehicle(node, rally_spawn_count + (course.pass_index - 1) * 200, kind, variant)
	racer.drive_speed = Traffic.speed_limit(self, racer, 0.0)
	toast("Приближается %s, номер %d!" % [node.get_meta("model"), node.get_meta("number")])

func _update_racers(delta: float) -> void:
	var to_remove: Array[Dictionary] = []
	var nearest: Node3D = null
	var nearest_d = 9999.0
	for racer in racers:
		var node: Node3D = racer.node
		racer.previous = node.position
		var was_racing = racer.state == "racing"
		racer.age += delta
		var service = racer.get("role", "racer") != "racer"
		if service:
			Props.update_course_lights(node, elapsed)
		if racer.state == "racing":
			var traffic = Traffic.plan(self, racer)
			racer.avoiding = traffic.avoiding
			racer.avoid_line = traffic.line
			var actual_speed = move_toward(float(racer.get("drive_speed", race_speed(racer.s))), float(traffic.speed), delta * (Traffic.BRAKE if traffic.speed < racer.get("drive_speed", 0) else 8.0))
			# The braking envelope is also a hard speed cap for long frame gaps.
			actual_speed = minf(actual_speed, float(traffic.speed)) if traffic.speed < actual_speed else actual_speed
			actual_speed = minf(actual_speed, float(traffic.get("advance", INF)) / maxf(delta, 0.001))
			racer.drive_speed = actual_speed
			var race_speed = maxf(actual_speed, 0.1)
			racer.s += delta * actual_speed
			# A crew braking just short of lateral clearance must finish its slow
			# manoeuvre; tying all steering motion to zero forward speed deadlocks it.
			var lateral_rate = minf(2.8, actual_speed * 0.14)
			if traffic.get("can_pass", false):
				lateral_rate = maxf(lateral_rate, 0.6)
			racer.line = move_toward(float(racer.get("line", 0.0)), float(traffic.line), delta * lateral_rate)

			var s: float = racer.s
			var road_yaw = atan2(-race_direction(s).x, -race_direction(s).z)
			var ahead = race_direction(s + 7)
			var bend = wrapf(atan2(-ahead.x, -ahead.z) - road_yaw, -PI, PI) / 7.0
			var lateral_accel = 0.0
			if not service:
				lateral_accel = RallyHandling.slide(racer, bend, race_speed, stage.grip(node.position), delta)
			var height = node.position.y
			node.position = race_at(s) + race_side(s) * (racer.line + racer.slide)
			node.position.y = height
			var movement = node.position - racer.previous
			var path_yaw = atan2(-movement.x, -movement.z) if Vector2(movement.x, movement.z).length() > 0.02 else road_yaw
			racer.motion.suspension(node, stage, delta, path_yaw + float(racer.get("drift_yaw", 0.0)), lateral_accel)
			if not service and ((s >= racer.focus and racer.kind != "pass") or absf(racer.slide) > 3.4 or absf(racer.line + racer.slide) > Stage.WIDTH * 0.5 + 0.6):
				racer.state = "offroad"
				racer.age = 0
				if racer.kind == "pass":
					racer.kind = "crash"
				RallyHandling.departure(racer, movement / maxf(delta, 0.001), race_side(s), bend)
				toast("ВЫЛЕТ! Отойди с траектории!")
			elif s > racer.focus + 45 and not racer.counted:
				count_racer(racer)
			if s >= Stage.LENGTH - 1:
				to_remove.append(racer)
		elif racer.state in ["offroad", "rock_bounce"]:
			var steps = maxi(1, int(ceil(delta / RallyHandling.STEP)))
			var dt = delta / steps
			for step in range(steps):
				var previous: Vector3 = node.position
				RallyHandling.free_step(racer, stage, dt)
				var contact = stage.rock_hit(previous, node.position, 0.85)
				var city_contact = stage.city.hit(previous, node.position, 0.85) if stage.urban else {}
				if not city_contact.is_empty() and (contact.is_empty() or previous.distance_squared_to(city_contact.position) < previous.distance_squared_to(contact.position)):
					contact = city_contact
				if not contact.is_empty():
					if contact.has("kind"):
						knock_city(contact, racer.motion.velocity)
					node.position = contact.position
					racer.motion.rock_impulse(contact.normal, node.rotation.y)
					racer.state = "rock_bounce"
					count_racer(racer)
			if racer.motion.grounded and racer.motion.velocity.length() < 0.65:
				racer.motion.velocity = Vector3.ZERO
				racer.state = "stranded" if racer.kind in ["stuck", "crash"] else "stopped"
				racer.age = 0.0
				if racer.state == "stranded":
					toast("Экипаж застрял. Нужен трос — T рядом с машиной.")
		elif racer.state in ["stopped", "stranded"]:
			racer.motion.suspension(node, stage, delta, node.rotation.y)
			if racer.state == "stopped" and not service and racer.age > 18 and racer.node != tow_target and float(racer.get("recovery_progress", 0)) <= 0 and int(racer.get("recovery_helpers", 0)) == 0:
				to_remove.append(racer)
		if was_racing:
			var contact = stage.rock_hit(racer.previous, node.position, 0.85)
			if not contact.is_empty():
				racer.motion.velocity = (node.position - racer.previous) / maxf(delta, 0.001)
				racer.motion.velocity.y = 0
				node.position = contact.position
				racer.motion.rock_impulse(contact.normal, node.rotation.y)
				racer.state = "rock_bounce"
				racer.age = 0.0
				count_racer(racer)
		if stage.urban and was_racing:
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
	if room.is_host and room.host_drives.has(id) and room.peers.has(id) and room.peers[id].state.in_car:
		room.host_drives[id].condition = maxf(0, room.host_drives[id].condition - 0.8)
	if id == room.player_id or id == "local":
		impact_shake = 0.8
		if in_car:
			condition = maxf(0, condition - 0.8)
		toast("Гравий из-под колёс! Отойди дальше от края СУ.")

func _acquire_gravel(size: float) -> MeshInstance3D:
	var node: MeshInstance3D
	while not gravel_pool.is_empty() and not is_instance_valid(gravel_pool.back()):
		gravel_pool.pop_back()
	if gravel_pool.is_empty():
		node = Props.box(self, Vector3.ZERO, Vector3.ONE, Color("9b9079"))
	else:
		node = gravel_pool.pop_back()
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE * size
	node.show()
	return node

func _release_gravel(node: MeshInstance3D) -> void:
	node.hide()
	if gravel_pool.size() < 48:
		gravel_pool.append(node)
	else:
		node.queue_free()

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
			var direction = race_direction(s)
			var side = race_side(s) * (-1.0 if rng.randf() < 0.5 else 1.0)
			var node = _acquire_gravel(rng.randf_range(0.07, 0.14))
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
			_release_gravel(stone.node)
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
		var labels = {"Space —": "Тормоз —", "F —": "Действие —", "Z —": "Стол —", "C —": "Стулья —", "G —": "Мангал —", "X —": "Есть —", "R —": "Заезды —", "— T": "— Трос", ": E.": ": Выйти.", "нажми X": "нажми Есть", "Удерживай T": "Удерживай Трос"}
		for key in labels:
			message = message.replace(key, labels[key])
	if toast_label != null:
		toast_label.text = message
		toast_label.visible = not mobile_mode
		toast_time = 5

var hud_state: Array = []
var hud_revision = 0
var hud_target: Dictionary = {}
var hud_target_frame = -1
var minimap_redraw_at = 0

func _set_hud_text(label: Label, value: String) -> void:
	if label.text != value:
		label.text = value

func _update_hud() -> void:
	# Resolve once after camera/world movement; actions still resolve a fresh target.
	var target = interaction.current()
	hud_target = target
	hud_target_frame = Engine.get_process_frames()
	crosshair.visible = playing and not in_car and not paused and not dead and not finished and placement_kind == ""
	_set_hud_text(crosshair, "+" if not target.is_empty() else "·")
	var now = Time.get_ticks_msec()
	if minimap.is_visible_in_tree() and now >= minimap_redraw_at:
		minimap.queue_redraw()
		minimap_redraw_at = now + 100
	var near_tow = nearby_tow_racer() if tow_target == null else false
	var remaining_items = packing.remaining() if packing.active() else -1
	var bag = foraging.stock() if not in_car else {}
	var pot = camp_cooking.pot != null
	var state: Array = [mobile_mode, in_car, playing, paused, dead, finished,
		int(absf(speed) * 3.6), int(condition),
		stage.road_distance(car.position) > 4 if in_car and not mobile_mode else false,
		course.phase, course.pass_index, course.zero_index,
		ceili(course.remaining) if course.phase in ["countdown", "intermission"] else 0,
		int(elapsed) if not mobile_mode else 0, camp != null, has_chairs, eaten, passed, helped, beers,
		cook_time >= 35, int(cook_time / 35 * 100) if cooking and cook_time < 35 else 0,
		cooking, grill_servings, drink_time >= 0, drink_time >= 1.25, eat_time >= 0, eat_kind,
		tow_target != null, int(tow_progress * 100), recovery_helpers, near_tow,
		remaining_items, seated, stage.urban, bag.get("mushrooms", 0), bag.get("berries", 0),
		foraging.can_eat("berries"), pot, camp_cooking.phase if pot else "",
		camp_cooking.servings if pot else 0,
		int(camp_cooking.cook_time / camp_cooking.COOK_SECONDS * 100) if pot else 0,
		int(camp_cooking.cook_time / 45 * 100) if pot and mobile_mode else 0,
		target.get("label", ""), toast_label.text if mobile_mode and toast_time > 0 else "",
		toast_time > 0 if mobile_mode else false, sober_remaining if beers >= 30 else 0]
	if state == hud_state:
		return
	hud_state = state
	hud_revision += 1
	var course_text = ""
	var quest_text = ""
	var status_text = ""
	var info_text = ""
	var hint_text = ""
	sobriety_panel.visible = beers >= 30 and playing and not dead and not finished
	if sobriety_panel.visible:
		var seconds = ceili(sober_remaining if sober_remaining > 0 else SOBER_SECONDS)
		_set_hud_text(sobriety_label, "ПРОТРЕЗВЛЕНИЕ · ВСТАНЕШЬ ЧЕРЕЗ %02d:%02d" % [seconds / 60, seconds % 60])
		sobriety_bar.value = SOBER_SECONDS - (sober_remaining if sober_remaining > 0 else SOBER_SECONDS)
	course_text = course.caption()
	quest_text = "%s Выбрать место для лагеря\n%s Разложить стол\n%s Поставить стулья\n%s Пожарить и съесть шашлык\n%s Посмотреть %d экипажей" % ["[x]" if camp != null else "[ ]", "[x]" if camp != null else "[ ]", "[x]" if has_chairs else "[ ]", "[x]" if eaten else "[ ]", "[x]" if passed >= RALLY_CREW_LIMIT else "[ ]", RALLY_CREW_LIMIT]
	if packing.active():
		quest_text = "Оба прохода завершены\nВернуть вещи в багажники: осталось %d\nБагажник открывается при подходе\nF — взять предмет / вернуть коробку\nЗатем все возвращаются в свои машины" % remaining_items
	status_text = "ПРОХОД %d/2 · ЭКИПАЖИ %d/%d · ПОМОЩЬ %d\nПИВО %d · ВЫЕЗД %02d:%02d" % [course.pass_index, passed, RALLY_CREW_LIMIT, helped, beers, int(elapsed) / 60, int(elapsed) % 60]
	if in_car:
		info_text = "%02d КМ/Ч    ·    ЛЕГКОВУШКА %d%%    ·    %s" % [int(absf(speed) * 3.6), int(condition), "ОБОЧИНА" if stage.road_distance(car.position) > 4 else "ГРАВИЙ / КОЛЕЯ"]
		hint_text = "WASD / стрелки — газ и руль   ·   Space — тормоз   ·   F — выйти   ·   Home — вернуть на СУ"
	else:
		var cook_status = "ШАШЛЫК ГОТОВ" if cook_time >= 35 else ("ШАШЛЫК %d%%" % int(cook_time / 35 * 100) if cooking else "МАНГАЛ НЕ РАЗОЖЖЁН")
		info_text = "ЗРИТЕЛЬ    ·    %s · ШАМПУРЫ %d/10    ·    %s" % [cook_status, grill_servings, course.caption()]
		hint_text = "WASD — идти   ·   Shift — бег   ·   Space — прыжок   ·   мышь — смотреть   ·   F — действие   ·   Z — стол   ·   C — стулья   ·   G — мангал   ·   R — статус СУ"
		if drink_time >= 0:
			info_text = "ОТКРЫВАЕМ БАНКУ" if drink_time < 1.25 else "ЗА ХОРОШИЙ ВЫЕЗД!"
		if eat_time >= 0:
			info_text = "ЕДИМ ПЛОВ" if eat_kind == "plov" else ("ЕДИМ ЯГОДЫ" if eat_kind == "berries" else ("ЕДИМ ГРИБЫ" if eat_kind == "mushroom" else "ЕДИМ ШАШЛЫК"))
		if beers >= 30:
			info_text = "ТЫ ЛЕЖИШЬ · ОТДОХНИ ДО ВОССТАНОВЛЕНИЯ"
		if tow_target != null:
			info_text = "ПОМОЩЬ %d%% · УЧАСТНИКОВ %d" % [int(tow_progress * 100), recovery_helpers]
	if tow_target != null:
		info_text = "ВЫТАСКИВАЕМ ЭКИПАЖ   ·   %d%%   ·   УДЕРЖИВАЙ T" % int(tow_progress * 100)
	elif near_tow:
		hint_text += "   ·   Иди в машину, чтобы толкать · T — тяни пешком со стороны дороги"
	if not in_car:
		status_text += ("\nГРИБЫ %d · ЯГОДЫ/ВИНОГРАД %d" if stage.urban else "\nГРИБЫ %d · ЯГОДЫ %d") % [bag.mushrooms, bag.berries]
		if not target.is_empty():
			hint_text = "F — " + target.label + ("" if packing.active() else "   ·   Z/C/G/V — поставить предмет")
		elif seated:
			hint_text = "F — встать со стула"
		if foraging.can_eat("berries"):
			hint_text += " · K — съесть ягоды"
	if camp_cooking.pot != null:
		status_text += "\nПЛОВ %s · %d/10" % [("ГОТОВ" if camp_cooking.phase == "ready" else ("ГОТОВИМ %d%%" % int(camp_cooking.cook_time / camp_cooking.COOK_SECONDS * 100) if camp_cooking.phase == "cooking" else "КАЗАН ПУСТ")), camp_cooking.servings]
	if packing.active() and remaining_items == 0:
		hint_text = "Лагерь собран. Садитесь в свои машины через F; ждём всех друзей." if in_car else "Лагерь собран. Подойди к своей машине и нажми F."
	if mobile_mode:
		course_text = course.caption().replace("ПРОХОД ", "СУ ").replace(" · ПРЯМО", "").replace(" · ОБРАТНО", "").replace("ДО ОТКРЫТИЯ СУ", "СТАРТ ЧЕРЕЗ")
		if in_car and tow_target == null:
			info_text = "%02d КМ/Ч · МАШИНА %d%%" % [int(absf(speed) * 3.6), int(condition)]
		elif not in_car and drink_time < 0 and eat_time < 0 and beers < 30 and tow_target == null:
			if packing.active():
				info_text = "ВЕРНУТЬ ВЕЩИ В БАГАЖНИК · ОСТАЛОСЬ %d" % remaining_items
			else:
				var cook_status = "ГОТОВ" if cook_time >= 35 else ("%d%%" % int(cook_time / 35 * 100) if cooking else "НЕТ ОГНЯ")
				info_text = "ШАШЛЫК %s · %d/10 · ПИВО %d" % [cook_status, grill_servings, beers]
				if camp_cooking.pot != null:
					info_text += " · ПЛОВ %d/10" % camp_cooking.servings if camp_cooking.phase == "ready" else (" · ПЛОВ %d%%" % int(camp_cooking.cook_time / 45 * 100) if camp_cooking.phase == "cooking" else " · КАЗАН ПУСТ")
		else:
			info_text = info_text.replace("УДЕРЖИВАЙ T", "УДЕРЖИВАЙ ТРОС")
		if toast_time > 0:
			info_text += "\n" + toast_label.text
		elif not in_car and not target.is_empty():
			info_text += "\n" + target.label
	_set_hud_text(course_label, course_text)
	_set_hud_text(quest_label, quest_text)
	_set_hud_text(status_label, status_text)
	_set_hud_text(info_label, info_text)
	_set_hud_text(hint_label, hint_text)

func _check_finish() -> void:
	cargo.release_departed()
	if dead or finished or not packing.active() or packing.remaining() > 0 or not in_car or eat_time >= 0 or drink_time >= 0:
		return
	# In a room, wait for every connected spectator to get back in their car.
	for peer in room.peers.values():
		if peer.state == null or not peer.state.in_car:
			return
	finished = true
	_show_result("Раллийный выезд завершён", "Оба прохода посмотрены. Лагерь собран. Все вернулись в машины.\n\nЭкипажи: %d  ·  Помощь: %d\nПиво: %d  ·  Машина: %d%%\n\nДо следующего ралли!" % [RALLY_CREW_LIMIT + passed, helped, beers, condition])

func die(reason: String) -> void:
	dead = true
	_show_result("Выезд окончен", reason + "\n\nЭкипажи: %d  ·  Помощь тросом: %d\nШашлык: %s" % [passed, helped, "съеден" if eaten else "не съеден"])

func _show_result(title: String, body: String) -> void:
	mushroom_effect.clear()
	sobriety_panel.hide()
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
	if soundscape != null:
		soundscape.shutting_down = true
		for player in [soundscape.birds, soundscape.effects, soundscape.steps]:
			player.stop()
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
	racer.s = clampf(race_station(racer.node.position) + 12.0, 0, Stage.LENGTH - 2)
	racer.node.position = race_at(racer.s)
	var direction = race_direction(racer.s)
	racer.node.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	racer.previous = racer.node.position
	racer.start = racer.node.position
	racer.target = racer.node.position
	racer.motion = Motion.new()
	racer.slide = 0.0
	racer.slide_speed = 0.0
	racer.drift_yaw = 0.0
	racer.yaw_rate = 0.0
	racer.line = 0.0
	racer.avoiding = false
	racer.avoid_line = 0.0
	racer.drive_speed = Traffic.speed_limit(self, racer, racer.s)
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
