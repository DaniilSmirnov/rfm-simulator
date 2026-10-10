extends Node3D
const NetProtocol = preload("res://scripts/net_protocol.gd")

var cargo = preload("res://scripts/car_cargo.gd").new()
var camp_cooking = preload("res://scripts/camp_cooking.gd").new()
var packing = preload("res://scripts/camp_packing.gd").new()
var interaction = preload("res://scripts/interaction.gd").new()
# Game systems; game.gd keeps the shared state and one-line entry points.
var crews = preload("res://scripts/rally_crews.gd").new()
var player = preload("res://scripts/player_motion.gd").new()
var camp_actions = preload("res://scripts/camp_actions.gd").new()
var hud = preload("res://scripts/game_hud.gd").new()
var seated = false
var jump_height = 0.0
var jump_velocity = 0.0
const WALK_SPEED = 4.3
const RUN_SPEED = 7.2
const DeepSnowRules = preload("res://scripts/deep_snow.gd")
# Wading through a full drift halves walking speed; hint once per drift entry.
const SNOW_WADE_SPEED = 0.5
const SNOW_HINT_DEPTH = 0.25
const SNOW_HINT_COOLDOWN = 20.0
var snow_hint_clock = 0.0
var snow_stuck = false
const JUMP_SPEED = 5.5
const WALK_GRAVITY = 18.0
var seat_exit = Vector3.ZERO
var crosshair: Label

const RallyRejoin = preload("res://scripts/rally_rejoin.gd")
const RallyHandling = preload("res://scripts/rally_handling.gd")
const RallyTracks = preload("res://scripts/rally_tracks.gd")
const Props = preload("res://scripts/props.gd")
const Stage = preload("res://scripts/stage.gd")
const StageRegistry = preload("res://scripts/stage_registry.gd")
const Spectators = preload("res://scripts/spectators.gd")
var spectators: Node3D
const MiniMap = preload("res://scripts/minimap.gd")
var stage: RallyStage
var menu_content: VBoxContainer
var platform_service: Node
var invite_button: Button
var invite_status: Label
var invite_after_room_create = false
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
# Shared actions a guest triggers straight from the keyboard (the rest need a
# target and go through placement or the interaction prompt).
const GUEST_KEY_ACTIONS = ["table", "chairs", "grill", "flag", "rally", "collect", "mount_mushroom", "eat_mushroom", "eat_berries", "firewood", "cauldron", "church_bell", "dig_snow"]
const EAT_ACTIONS = {"meat": "eat", "mushroom": "eat_mushroom", "berries": "eat_berries", "plov": "eat_plov"}
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
var safety_gate: CanvasLayer
var safety_safe_insets = Vector4.ZERO
var has_chairs = false
var personal_chairs: Dictionary = {}
var personal_flags: Dictionary = {}
const FLAGS_PER_PLAYER = 3
var placement_kind = ""
var placement_preview: Node3D
var placement_yaw = 0.0
var placement_valid = false
var placement_material: StandardMaterial3D

# The player an action is performed for: the local player, or a guest whose
# command the host is running (shared_actions.gd sets `acting`).
var acting = null

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
var consumption_warning: PanelContainer
var consumption_warning_text: Label
var consumption_warning_time = 0.0
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
var tow_distance = -1.0 # metres the towed crew has to the road; -1: a friend's car
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
var draw_distance = preload("res://scripts/draw_distance.gd").new()
var draw_distance_controls: VBoxContainer
var draw_distance_buttons: Array[Button] = []
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
var lifecycle_pause_sequence = 0
var mobile_safe_http: HTTPRequest
const Traffic = preload("res://scripts/rally_traffic.gd")
const Motion = preload("res://scripts/vehicle_motion.gd")
var vehicle_motion = Motion.new()
var stones: Array[Dictionary] = []
var gravel_pool: Array[MeshInstance3D] = []
var stone_serial = 0
var impact_serials: Dictionary = {}
var impact_shake = 0.0
var stone_clock = 0.0
var hud_state: Array = []
var hud_revision = 0
var hud_target: Dictionary = {}
var hud_target_frame = -1
var minimap_redraw_at = 0

func _init() -> void:
	for system in [crews, player, camp_actions, hud]:
		system.game = self

func actor_pos() -> Vector3:
	return acting.pos if acting != null else walker

func actor_in_car() -> bool:
	return acting.in_car if acting != null else in_car

func actor_beers() -> int:
	return acting.beers if acting != null else beers

func actor_yaw() -> float:
	return acting.yaw if acting != null else view_yaw

func actor_position() -> Vector3:
	return acting.position() if acting != null else player_position()

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
	return camp_actions.valid_furniture_spot(spot, kind, ignored_owner)

func dig_snow(spot: Vector3) -> void:
	camp_actions.dig_snow(spot)

func begin_placement(kind: String) -> void:
	camp_actions.begin_placement(kind)

func _update_placement() -> void:
	camp_actions.update_placement()

func cancel_placement() -> void:
	camp_actions.cancel_placement()

func confirm_placement() -> void:
	camp_actions.confirm_placement()

func enable_mobile() -> void:
	hud.enable_mobile()

func apply_mobile_safe_rect(rect: Rect2) -> void:
	hud.apply_mobile_safe_rect(rect)

func fit_mobile_dialogs() -> void:
	hud.fit_mobile_dialogs()

func update_mobile_safe_area(delta: float) -> void:
	hud.update_mobile_safe_area(delta)

func _mobile_safe_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	hud.mobile_safe_response(result, code, _headers, body)

func _set_paused(value: bool) -> void:
	paused = value
	menu.visible = paused
	menu_title.text = "Перерыв на природе"
	menu_text.text = "Пауза. Ралли, мангал и таймеры остановлены.\n\nHome — вернуть машину на дорогу.\nF8 / F9 — показать застревание / вылет.\n\nПродолжить — кнопкой или Esc."
	start_button.text = "ПРОДОЛЖИТЬ"
	menu_text.text = "Выезд приостановлен. Продолжить или вернуться в меню." if room.is_authority() else "Твоя пауза. Остальные игроки продолжают выезд."
	_update_invite_button()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused or mobile_mode else Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not mobile_mode:
		enable_mobile()

func _ready() -> void:
	print("[RFM] Подготовка игрового мира")
	foraging.game = self
	interaction.game = self
	packing.game = self
	cargo.game = self
	camp_cooking.game = self
	rng.randomize()
	draw_distance.load_settings(OS.has_feature("mobile") or "--mobile-controls" in OS.get_cmdline_user_args())
	_setup_input()
	stage = Stage.new()
	add_child(stage)
	if not defer_world:
		stage.build()
		draw_distance.apply(stage)
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
			room.ui.name_input.text = str(profile.get("nickname", ""))
			room.ui.name_input.editable = false
		for i in range(car_choice.items.size()):
			car_choice.items[i] = Props.PLAYER_MODELS[i].name
		for i in range(stage_choice.items.size()):
			stage_choice.items[i] = Stage.STAGES[i].get_slice("·", 0).strip_edges()
		car_choice.select(selected_car)
		stage_choice.select(selected_stage)
		lobby_ui.refresh()
		_update_invite_button()
		if platform_service.invite_room != "":
			call_deferred("_join_invited_room")
	)
	platform_service.invite_feedback.connect(func(message: String):
		invite_status.text = message
		invite_status.visible = not message.is_empty() and playing and platform_service.profile.get("platform", "") == "vk"
		invite_button.disabled = false
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

# Sky, fog, ambient light and sun of the selected stage (res://data/stages.json).
func _build_environment() -> void:
	var world = WorldEnvironment.new()
	world_environment = world
	var look = StageRegistry.section(stage.variant, "environment")
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(look.sky_top)
	sky_mat.sky_horizon_color = Color(look.sky_horizon)
	sky_mat.ground_bottom_color = Color(look.ground_bottom)
	sky_mat.ground_horizon_color = Color(look.ground_horizon)
	if look.has("sky_curve"):
		sky_mat.sky_curve = float(look.sky_curve)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(look.ambient)
	env.ambient_light_energy = float(look.ambient_energy)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(look.fog)
	env.fog_density = float(look.fog_density)
	if look.has("fog_sky_affect"):
		env.fog_sky_affect = float(look.fog_sky_affect)
	world.environment = env
	add_child(world)
	var light = StageRegistry.section(stage.variant, "sun")
	var sun = DirectionalLight3D.new()
	sunlight = sun
	sun.rotation_degrees = Vector3(light.rotation[0], light.rotation[1], light.rotation[2])
	sun.light_color = Color(light.color)
	sun.light_energy = float(light.energy)
	sun.shadow_enabled = true
	draw_distance.apply_shadows(sun)
	add_child(sun)

func _panel(color: Color) -> StyleBoxFlat:
	return hud.panel(color)

func _label(parent: Node, text: String, font_size: int, color: Color = Color("f2e8d0")) -> Label:
	return hud.label(parent, text, font_size, color)

func _build_ui() -> void:
	hud.build_ui()

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
	draw_distance.apply(stage)
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
	if platform_service != null and (not platform_service.can_use("car", car_choice.selected) or not platform_service.can_use("stage", stage_choice.selected, room.is_guest())):
		toast("Выбранный контент недоступен в VK. Дождитесь загрузки прав или выберите бесплатный вариант.")
		return
	if playing:
		return
	if loading_world:
		return
	if not world_ready:
		await prepare_world()
	playing = true
	_update_invite_button()
	soundscape.repair()
	course.apply_snapshot({})
	racing = false
	selection_controls.hide()
	room.ui.panel.hide()
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
	if not ("--script" in OS.get_cmdline_args() or "--smoke-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--capture-menu" in OS.get_cmdline_user_args()):
		_show_stage_safety_gate()

func _show_stage_safety_gate() -> void:
	hud.show_stage_safety_gate()

func _update_invite_button() -> void:
	hud.update_invite_button()

func _join_invited_room() -> void:
	if platform_service == null or playing or room.connected or room.busy or loading_world:
		return
	var requested: String = platform_service.invite_room
	platform_service.invite_room = ""
	if not NetProtocol.valid_room_id(requested.to_upper()):
		return
	room.ui.id_input.text = requested
	room.connect_room(requested)

func _invite_friends() -> void:
	# Always acknowledge a press before branching into room/network/Bridge state.
	# Previously failures were visible only in the hidden lobby.
	print("[VK invite] button pressed; playing=", playing, " room=", room.room_id, " connected=", room.connected)
	if platform_service == null or platform_service.profile.get("platform", "") != "vk" or not playing:
		toast("Приглашения доступны после входа на СУ через VK.")
		return
	if platform_service.invite_busy or room.busy or loading_world:
		invite_status.text = "Подожди: уже идёт подключение или отправка приглашения."
		invite_status.show()
		toast(invite_status.text)
		return
	if not room.connected:
		# Create a session on this stage without resetting solo camp/vehicle.
		invite_after_room_create = true
		invite_status.text = "Создаём комнату для друзей…"
		invite_status.show()
		toast(invite_status.text)
		room.connect_room("")
		if not room.busy:
			invite_after_room_create = false
			invite_status.text = "Не удалось создать комнату: " + room.ui.status.text
			invite_status.show()
			toast(invite_status.text)
		return
	if room.room_id.is_empty():
		invite_status.text = "У комнаты отсутствует ID. Переподключись к комнате."
		invite_status.show()
		toast(invite_status.text)
		return
	invite_status.text = "Открываем приглашение VK для комнаты " + room.room_id + "…"
	invite_status.show()
	toast(invite_status.text)
	invite_button.disabled = true
	platform_service.invite_friend(room.room_id)

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
	consumption_warning_time = 0
	lobby_ui.return_button.disabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if room.connected:
		room.leave()
	else:
		get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if safety_gate != null and is_instance_valid(safety_gate):
		return
	if placement_kind != "":
		if event.is_action_pressed("pause_demo") or event.is_action_pressed("placement_cancel"):
			cancel_placement()
			return
		if not paused and not dead and not finished and not (room.is_guest() and room.world_paused):
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
		_set_paused(not paused)
		return
	if not playing or paused or dead or finished:
		return
	if event is InputEventMouseButton and event.pressed and not mobile_mode and room.connected:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and not mobile_mode:
		view_yaw -= event.relative.x * 0.0025
		view_pitch = clampf(view_pitch - event.relative.y * 0.0025, -1.15, 1.1)
	if drink_time >= 0 or eat_time >= 0 or (room.is_guest() and room.world_paused):
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
	# A guest's key press becomes a command the host performs for them.
	for shared_action in GUEST_KEY_ACTIONS:
		if InputMap.has_action(shared_action) and event.is_action_pressed(shared_action) and room.submit(shared_action):
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
		if room.is_guest():
			return
		if event.physical_keycode == KEY_F8:
			spawn_racer("stuck")
		elif event.physical_keycode == KEY_F9:
			spawn_racer("crash")

func _update_fps_counter(delta: float) -> void:
	hud.update_fps_counter(delta)

func show_consumption_warning(kind: String) -> void:
	hud.show_consumption_warning(kind)

func _process(delta: float) -> void:
	consumption_warning_time = maxf(0, consumption_warning_time - delta)
	consumption_warning.visible = consumption_warning_time > 0 and playing and not paused and not dead and not finished
	update_mobile_safe_area(delta)
	_update_fps_counter(delta)
	if soundscape != null:
		soundscape.update(delta)
	camp_cooking.animate_flames(Time.get_ticks_msec() / 1000.0)
	if not playing or paused or dead or finished or (room.is_guest() and room.world_paused):
		return
	if room.is_authority():
		elapsed += delta
		course.update(self, delta)
	elif course.phase in ["countdown", "intermission"]:
		course.remaining = maxf(0, course.remaining - delta)
	stage.snow.authoritative = room.is_authority()
	if stage.has_snow:
		stage.snow.update(delta)
	stage.update_fallen(delta)
	if stage.water != null:
		stage.water.update(delta)
	stage.update_life(delta, player_position())
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
	Props.animate_wheels(car)
	cargo.update(delta)
	camp_cooking.update(delta, room.is_guest())
	spectators.update(elapsed, delta, room.is_guest())
	stage.officials.update(self, delta, room.is_guest())
	foraging.update_visuals()
	if room.is_authority():
		_update_racers(delta)
		for racer in racers:
			Props.animate_wheels(racer.node)
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
	if room.is_authority():
		_check_finish()
	if capture_mode and elapsed > 1.3:
		capture_mode = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../preview.png")
		await _shutdown_audio()
		get_tree().quit()

func _update_sobriety(delta: float) -> void:
	player.update_sobriety(delta)

func _update_intoxication(delta: float) -> void:
	player.update_intoxication(delta)

func player_position() -> Vector3:
	return car.position if in_car else walker

func _drive(delta: float) -> void:
	player.drive(delta)

func knock_tree(index: int, direction_hint: Vector3) -> void:
	player.knock_tree(index, direction_hint)

func contact_blocked(start: Vector3, end: Vector3, driving: bool) -> bool:
	return player.contact_blocked(start, end, driving)

func _walk(delta: float) -> void:
	player.walk(delta)

func snow_wading() -> float:
	return player.snow_wading()

func _snow_hint(delta: float) -> void:
	player.snow_hint(delta)

func running() -> bool:
	return player.running()

func jump() -> bool:
	return player.jump()

func _update_camera(delta: float) -> void:
	player.update_camera(delta)

func _toggle_car() -> void:
	player.toggle_car()

func nearby_drink_source() -> bool:
	return camp_actions.nearby_drink_source()

func can_eat_meat() -> bool:
	return camp_actions.can_eat_meat()

func place_table(spot: Vector3 = Vector3.INF, yaw: float = 0.0) -> bool:
	return camp_actions.place_table(spot, yaw)

func place_chairs(spot: Vector3 = Vector3.INF, yaw: float = 0.0, owner: String = "") -> bool:
	return camp_actions.place_chairs(spot, yaw, owner)

func apply_chair(owner: String, spot: Vector3, yaw: float) -> void:
	camp_actions.apply_chair(owner, spot, yaw)

func place_flag(spot: Vector3 = Vector3.INF, yaw: float = 0.0, owner: String = "", replicated: bool = false) -> bool:
	return camp_actions.place_flag(spot, yaw, owner, replicated)

func start_grill(spot: Vector3 = Vector3.INF, yaw: float = 0.0, replicated: bool = false) -> bool:
	return camp_actions.start_grill(spot, yaw, replicated)

func _update_cooking(delta: float) -> void:
	camp_actions.update_cooking(delta)

func drink_beer() -> bool:
	return camp_actions.drink_beer()

func _update_drinking(delta: float) -> void:
	camp_actions.update_drinking(delta)

func _cancel_drink() -> void:
	camp_actions.cancel_drink()

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
		draw_distance.apply(stage)
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
	return camp_actions.eat_meat(source_group)

func eat_plov() -> bool:
	return camp_actions.eat_plov()

func eat_foraged(kind: String, source: int = -2) -> bool:
	return camp_actions.eat_foraged(kind, source)

func commit_meat(source_group: int = -2) -> bool:
	return camp_actions.commit_meat(source_group)

func _update_eating(delta: float) -> void:
	camp_actions.update_eating(delta)

func _cancel_eat() -> void:
	camp_actions.cancel_eat()

func start_rally() -> bool:
	# R is an information shortcut; it cannot bypass the safety convoy.
	toast(course.caption())
	return course.phase == "racing"

func spawn_course_car(role: String, id: int, zero_index: int = 0) -> void:
	crews.spawn_course_car(role, id, zero_index)

func race_station(point: Vector3) -> float:
	return crews.race_station(point)

func race_at(progress: float) -> Vector3:
	return crews.race_at(progress)

func race_direction(progress: float) -> Vector3:
	return crews.race_direction(progress)

func race_side(progress: float) -> Vector3:
	return crews.race_side(progress)

func race_speed(progress: float) -> float:
	return crews.race_speed(progress)

func _add_course_vehicle(node: Node3D, id: int, kind: String, variant: int, role: String = "racer", zero_index: int = 0) -> Dictionary:
	return crews.add_course_vehicle(node, id, kind, variant, role, zero_index)

func spawn_racer(forced: String = "") -> void:
	crews.spawn_racer(forced)

func _update_racers(delta: float) -> void:
	crews.update_racers(delta)

func stone_impact(id: String) -> void:
	crews.stone_impact(id)

func _acquire_gravel(size: float) -> MeshInstance3D:
	return crews.acquire_gravel(size)

func _release_gravel(node: MeshInstance3D) -> void:
	crews.release_gravel(node)

func _update_stones(delta: float) -> void:
	crews.update_stones(delta)

func walking_intent() -> Vector3:
	return player.walking_intent()

func _update_tow(delta: float) -> void:
	crews.update_tow(delta)

func _clear_recovery_ropes() -> void:
	crews.clear_recovery_ropes()

func draw_recovery_ropes() -> void:
	crews.draw_recovery_ropes()

func _cancel_tow() -> void:
	crews.cancel_tow()

func toast(message: String) -> void:
	hud.toast(message)

func _update_hud() -> void:
	hud.update_hud()

func _check_finish() -> void:
	cargo.release_departed()
	if dead or finished or not packing.active() or packing.remaining() > 0 or not in_car or eat_time >= 0 or drink_time >= 0:
		return
	# In a room, wait for every connected spectator to get back in their car.
	for peer in room.peers.values():
		if peer.state == null or not peer.state.in_car:
			return
	finished = true
	_show_result("Раллийный выезд завершён", "Оба прохода посмотрены. Лагерь собран. Все вернулись в машины.\n\nЭкипажи: %d  ·  Помощь: %d\nМашина: %d%%\n\nДо следующего ралли!" % [RALLY_CREW_LIMIT + passed, helped, condition])

func die(reason: String) -> void:
	hud.die(reason)

func _show_result(title: String, body: String) -> void:
	hud.show_result(title, body)

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

func _advance_gravel(stone: Dictionary, delta: float) -> bool:
	return crews.advance_gravel(stone, delta)

func can_tow_racer(racer: Dictionary) -> bool:
	return crews.can_tow_racer(racer)

func nearby_tow_target() -> bool:
	return crews.nearby_tow_target()

func recover_racer(racer: Dictionary) -> void:
	crews.recover_racer(racer)

func count_racer(racer: Dictionary) -> void:
	crews.count_racer(racer)

func knock_solid(contact: Dictionary, velocity: Vector3) -> void:
	if contact.get("kind", "") != "lamp" or velocity.length() <= 5:
		return
	if room.is_guest():
		lamp_requests[int(contact.id)] = velocity
	else:
		stage.solids.knock_lamp(int(contact.id), velocity)

func sit_down() -> void:
	player.sit_down()

func stand_up() -> void:
	player.stand_up()

