extends Node3D

const Props = preload("res://scripts/props.gd")
const Stage = preload("res://scripts/stage.gd")
const MiniMap = preload("res://scripts/minimap.gd")
var stage: RallyStage
var car: Node3D
var camera: Camera3D
var camp: Node3D
var grill: Node3D
var smoke: GPUParticles3D
var beer_prop: Node3D
var rope_mesh: MeshInstance3D
var in_car = true
var heading = 0.0
var view_yaw = 0.0
var view_pitch = -0.12
var speed = 0.0
var condition = 100.0
var last_pothole = -1
var walker = Vector3.ZERO
var playing = false
var dead = false
var finished = false
var paused = false
var has_chairs = false
var cooking = false
var cook_time = 0.0
var eaten = false
var beers = 0
var beer_timer = 0.0
const DRINK_DURATION = 3.3
var drink_time = -1.0
var drink_committed = false
var can_opened = false
var beer_audio: AudioStreamPlayer
var rally_spawn_count = 0
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
	menu.get_child(0).add_theme_constant_override("separation", 10)
	menu_title.add_theme_font_size_override("font_size", 30)
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

func _ready() -> void:
	rng.randomize()
	_setup_input()
	stage = Stage.new()
	add_child(stage)
	stage.build()
	_build_environment()
	car = Props.car(Color("c8884c"))
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
	var bindings = {"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "brake": [KEY_SPACE], "interact": [KEY_E], "table": [KEY_F], "chairs": [KEY_C], "grill": [KEY_G], "beer": [KEY_B], "eat": [KEY_X], "rally": [KEY_R], "tow": [KEY_T], "random_spot": [KEY_Q], "recover": [KEY_HOME], "pause_demo": [KEY_ESCAPE]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var e = InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)

func _build_environment() -> void:
	var world = WorldEnvironment.new()
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
	world.environment = env
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -32, 0)
	sun.light_color = Color("ffe3b2")
	sun.light_energy = 0.85
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
	var top = PanelContainer.new()
	mobile_top = top
	ui.add_child(top)
	top.position = Vector2(28, 24)
	top.add_theme_stylebox_override("panel", _panel(Color("25352be8")))
	var vb = VBoxContainer.new()
	top.add_child(vb)
	title_label = _label(vb, "СИМУЛЯТОР РАЛЛИЙНОГО ОВОЩА", 22)
	_label(vb, "DYFI-INSPIRED  /  ГОРНЫЙ ЛЕС  /  ДЕМО 0.3", 12, Color("b2bea1"))
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
	mv.add_theme_constant_override("separation", 20)
	menu.add_child(mv)
	_label(mv, "ЛЕС. ГРАВИЙ. ШАШЛЫК.", 14, Color("dfb270"))
	menu_title = _label(mv, "Симулятор\nраллийного овоща", 42)
	menu_text = _label(mv, "Твоя легковушка. Разбитый спецучасток.\nОдна поляна и целый день ралли.\n\nДоедь до лесной поляны, разложи стол и стулья,\nпожарь шашлык и посмотри шесть экипажей.\nЭкипажи могут вылететь или попросить трос.", 19)
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
	menu_help = _label(mv, "WASD — движение   ·   E — выйти   ·   Esc — пауза\nНа ногах: мышь — обзор   ·   F/C/G — лагерь", 14, Color("b2bea1"))

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
	playing = true
	menu.hide()
	for panel in hud_panels:
		panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mobile_mode else Input.MOUSE_MODE_CAPTURED
	toast("Доедь до любой поляны. Q — выбрать случайную на карте.")

func _menu_action() -> void:
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
	if event is InputEventMouseMotion and not in_car and not mobile_mode:
		view_yaw -= event.relative.x * 0.0025
		view_pitch = clampf(view_pitch - event.relative.y * 0.0025, -1.15, 1.1)
	if drink_time >= 0:
		return
	if event.is_action_pressed("interact"):
		_toggle_car()
	elif event.is_action_pressed("table"):
		place_table()
	elif event.is_action_pressed("chairs"):
		place_chairs()
	elif event.is_action_pressed("grill"):
		start_grill()
	elif event.is_action_pressed("beer"):
		drink_beer()
	elif event.is_action_pressed("eat"):
		eat_meat()
	elif event.is_action_pressed("rally"):
		start_rally()
	elif event.is_action_pressed("random_spot"):
		target_clearing = rng.randi_range(0, stage.clearings.size() - 1)
		toast("Выбрана поляна %d. Оранжевая точка на карте." % (target_clearing + 1))
	elif event.is_action_pressed("recover"):
		if not racing:
			car.position = stage.at(stage.road_s(car.position))
			heading = atan2(-stage.direction(stage.road_s(car.position)).x, -stage.direction(stage.road_s(car.position)).z)
			speed = 0
			toast("Машина возвращена на СУ.")
		else:
			toast("Возврат на СУ недоступен во время заездов.")
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F8:
			spawn_racer("stuck")
		elif event.physical_keycode == KEY_F9:
			spawn_racer("crash")

func _process(delta: float) -> void:
	if not playing or paused or dead or finished:
		return
	elapsed += delta
	if in_car:
		_drive(delta)
	else:
		_walk(delta)
	_update_drinking(delta)
	_update_camera(delta)
	_update_racers(delta)
	_update_cooking(delta)
	_update_tow(delta)
	if beer_timer > 0:
		beer_timer = maxf(0, beer_timer - delta)
	toast_time = maxf(0, toast_time - delta)
	toast_label.visible = toast_time > 0 and not mobile_mode
	if racing:
		race_clock += delta
		spawn_clock -= delta
		if spawn_clock <= 0:
			spawn_racer()
			spawn_clock = rng.randf_range(17, 23)
	_update_hud()
	engine_audio.pitch_scale = 0.75 + absf(speed) / 18.0
	engine_audio.volume_db = -21 if in_car else -35
	_check_finish()
	if capture_mode and elapsed > 1.3:
		capture_mode = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../preview.png")
		await _shutdown_audio()
		get_tree().quit()

func player_position() -> Vector3:
	return car.position if in_car else walker

func _drive(delta: float) -> void:
	var throttle = Input.get_axis("back", "forward")
	var steer = Input.get_axis("left", "right")
	var offroad = stage.road_distance(car.position) > 4.1
	var max_speed = 7.0 if offroad else 19.0
	var acceleration = 5.0 if offroad else 7.0
	var road_index = int(stage.road_s(car.position) / Stage.STEP)
	var puddle = not offroad and road_index % 13 == 7
	if puddle:
		max_speed = 9.0
		if road_index != last_pothole and absf(speed) > 11:
			condition = maxf(0, condition - 1.4)
			toast("Удар в колее. Перед лужами лучше сбрасывать скорость.")
		last_pothole = road_index
	if throttle != 0:
		speed = move_toward(speed, throttle * max_speed * (0.4 if throttle < 0 else 1.0), acceleration * delta)
	else:
		speed = move_toward(speed, 0, delta * 2.7)
	if Input.is_action_pressed("brake"):
		speed = move_toward(speed, 0, delta * 19)
	heading -= steer * delta * clampf(absf(speed) / 6, 0, 1.0) * signf(speed) * 1.15
	var forward = Vector3(-sin(heading), 0, -cos(heading))
	var next = car.position + forward * speed * delta
	next.x = clampf(next.x, -185, 185)
	next.z = clampf(next.z, -Stage.LENGTH + 5, 10)
	var hit = false
	for p in stage.trees:
		if Vector2(p.x - next.x, p.z - next.z).length_squared() < 2.6:
			hit = true
			break
	if hit:
		condition = maxf(0, condition - absf(speed) * 1.4)
		speed *= -0.25
		toast("Дерево крепче твоего бампера.")
	else:
		var rise = stage.ground(next) - stage.ground(car.position)
		speed = move_toward(speed, 0, maxf(0, rise) * 1.7)
		car.position = next
		car.position.y = stage.ground(next) + 0.06
	car.rotation.y = heading
	var bumps = sin(elapsed * 27) * minf(absf(speed) * 0.003, 0.045)
	car.rotation.z = lerpf(car.rotation.z, steer * speed * 0.003 + bumps, delta * 8)
	car.rotation.x = lerpf(car.rotation.x, -forward.dot(stage.direction(stage.road_s(car.position))) * stage.direction(stage.road_s(car.position)).y + bumps, delta * 5)
	if offroad and absf(speed) > 5:
		condition = maxf(0, condition - delta * 0.15)
	if condition <= 0:
		die("Легковушка сдалась раньше тебя.\nРазбитый СУ победил подвеску.")

func _walk(delta: float) -> void:
	var motion = Vector2(Input.get_axis("left", "right"), Input.get_axis("forward", "back"))
	if motion.length() > 1:
		motion = motion.normalized()
	var dir = Vector3(motion.x, 0, motion.y).rotated(Vector3.UP, view_yaw)
	var next = walker + dir * delta * (1.4 if drink_time >= 0 else 4.3)
	next.x = clampf(next.x, -185, 185)
	next.z = clampf(next.z, -Stage.LENGTH + 5, 10)
	var hit = false
	for p in stage.trees:
		if Vector2(p.x - next.x, p.z - next.z).length_squared() < 0.4:
			hit = true
			break
	if not hit:
		walker = next
	walker.y = stage.ground(walker)

func _update_camera(delta: float) -> void:
	if capture_mode:
		return
	if in_car:
		var behind = Vector3(sin(heading), 0, cos(heading))
		var desired = car.position + behind * 8.2 + Vector3(0, 4.4, 0)
		desired.y = maxf(desired.y, stage.ground(desired) + 1.1)
		camera.position = camera.position.lerp(desired, 1 - exp(-delta * 7))
		camera.look_at(car.position + Vector3(0, 1.1, 0))
	else:
		camera.position = walker + Vector3(0, 1.72 + sin(elapsed * 12) * 0.015, 0)
		var sip = sin(clampf((drink_time - 1.3) / 1.2, 0, 1) * PI) if drink_time >= 0 else 0.0
		camera.rotation = Vector3(view_pitch + sip * 0.035, view_yaw, sin(elapsed * 1.7) * 0.012 if beer_timer > 0 else 0)
		camera.fov = 68 - sip * 2.0

func _toggle_car() -> void:
	if drink_time >= 0:
		toast("Сначала допей и освободи руки.")
		return
	if in_car:
		if absf(speed) > 1:
			toast("Сначала остановись: Space — тормоз.")
			return
		in_car = false
		walker = car.position + Vector3(-2.1, 0, 0).rotated(Vector3.UP, heading)
		walker.y = stage.ground(walker)
		view_yaw = heading
		toast("F — стол, C — стулья, G — мангал. Устанавливай вне СУ.")
	elif walker.distance_to(car.position) < 4:
		in_car = true
		speed = 0
	else:
		toast("Подойди к своей машине, чтобы сесть.")

func near_camp() -> bool:
	return camp != null and player_position().distance_to(camp.position) < 7

func place_table() -> bool:
	if in_car:
		toast("Сначала выйди из машины: E.")
		return false
	if camp != null:
		toast("Стол уже стоит. C — стулья, G — мангал.")
		return false
	var spot = walker + Vector3(-sin(view_yaw), 0, -cos(view_yaw)) * 2.5
	if stage.road_distance(walker) < 6 or stage.road_distance(spot) < 6:
		toast("На самой дороге стол не поставить. Отойди на обочину.")
		return false
	camp = Node3D.new()
	add_child(camp)
	camp.position = spot
	camp.position.y = stage.ground(camp.position)
	Props.table(camp)
	toast("Стол установлен. Можно раскладываться!")
	return true

func place_chairs() -> bool:
	if in_car or not near_camp():
		toast("Подойди к столу пешком.")
		return false
	if has_chairs:
		return false
	Props.chair(camp, Vector3(-1.6, 0, 0.7))
	Props.chair(camp, Vector3(1.6, 0, 0.7))
	has_chairs = true
	toast("Два стула готовы. G — разжечь мангал.")
	return true

func start_grill() -> bool:
	if in_car or not near_camp() or not has_chairs:
		toast("Нужны стол и стулья. Подойди к лагерю пешком.")
		return false
	if cooking:
		toast("Шашлык уже на углях: осталось %d секунд." % maxi(0, int(35 - cook_time)))
		return false
	grill = Props.grill(camp)
	grill.position = Vector3(0.3, 0, -2.4)
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
	toast("Угли разгорелись. Шашлык готовится 35 секунд. R — открыть СУ.")
	return true

func _update_cooking(delta: float) -> void:
	if cooking and cook_time < 35:
		cook_time = minf(35, cook_time + delta)
		if cook_time >= 35:
			toast("Шашлык готов! Подойди к лагерю и нажми X.")

func drink_beer() -> bool:
	if not playing or paused or dead or finished:
		return false
	if in_car or not near_camp():
		toast("Пиво осталось у стола. Подойди к лагерю пешком.")
		return false
	if drink_time >= 0 or beer_timer > 0 or beers >= 3:
		toast("Пока хватит. Лучше посмотри ралли.")
		return false
	drink_time = 0.0
	drink_committed = false
	can_opened = false
	beer_prop = Props.beer_hand()
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
		beer_timer = 12
		beer_audio.stream = load("res://audio/beer-sip.wav")
		_play_audio(beer_audio)
	if drink_time >= DRINK_DURATION:
		_cancel_drink()
		toast("За хороший выезд! X — готовый шашлык, R — заезды.")

func _cancel_drink() -> void:
	drink_time = -1.0
	if is_instance_valid(beer_prop):
		beer_prop.queue_free()
	beer_prop = null
	camera.fov = 68
	if beer_audio != null:
		beer_audio.stop()

func eat_meat() -> bool:
	if in_car or not near_camp() or cook_time < 35:
		toast("Шашлык ещё не готов или ты далеко от лагеря.")
		return false
	if not eaten:
		eaten = true
		toast("Шашлык удался. Осталось насмотреться на ралли.")
	return true

func start_rally() -> bool:
	if in_car:
		toast("Припаркуйся и выйди из машины перед открытием СУ.")
		return false
	if not racing:
		racing = true
		spawn_clock = 5
		toast("СУ открыт. Первый экипаж через несколько секунд!")
	return true

func spawn_racer(forced: String = "") -> void:
	if not racing:
		if in_car:
			return
		racing = true
	var kind = forced
	if kind == "":
		var roll = rng.randf()
		kind = "crash" if roll < 0.25 else ("stuck" if roll < 0.45 else "pass")
	# Keep at most one stranded car, so the stage cannot clog permanently.
	for existing in racers:
		if existing.kind == "stuck" and kind == "stuck":
			kind = "pass"
	var focus = clampf(stage.road_s(player_position()), 45, Stage.LENGTH - 80)
	var variant = rally_spawn_count % Props.RALLY_MODELS.size()
	rally_spawn_count += 1
	var node = Props.car(Color.WHITE, true, variant)
	add_child(node)
	var s = maxf(0, focus - 115)
	node.position = stage.at(s)
	racers.append({"node": node, "s": s, "focus": focus, "kind": kind, "state": "racing", "offset": 0.0, "age": 0.0, "counted": false, "start": Vector3.ZERO, "target": Vector3.ZERO, "variant": variant})
	toast("Приближается %s, номер %d!" % [node.get_meta("model"), node.get_meta("number")])

func _update_racers(delta: float) -> void:
	var to_remove: Array[Dictionary] = []
	var nearest: Node3D = null
	var nearest_d = 9999.0
	for racer in racers:
		var node: Node3D = racer.node
		racer.age += delta
		if racer.state == "racing":
			racer.s += delta * 27
			var s: float = racer.s
			node.position = stage.at(s)
			node.rotation.y = atan2(-stage.direction(s).x, -stage.direction(s).z)
			node.rotation.z = sin(elapsed * 20) * 0.045
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
				racer.counted = true
				passed += 1
			if s >= Stage.LENGTH - 1 or s > racer.focus + 150:
				to_remove.append(racer)
		elif racer.state == "offroad":
			var t = minf(1, racer.age / (0.7 if racer.kind == "crash" else 1.1))
			node.position = racer.start.lerp(racer.target, t)
			node.rotation.y += delta * 0.6
			node.rotation.z = sin(t * PI) * 0.2
			if t >= 1:
				racer.state = "stranded" if racer.kind == "stuck" else "stopped"
				racer.age = 0
				passed += 1
		elif racer.state == "stopped" and racer.age > 18:
			to_remove.append(racer)
		if racer.state in ["racing", "offroad"]:
			var distance = Vector2(node.position.x - player_position().x, node.position.z - player_position().z).length()
			if distance < (2.6 if in_car else 1.65):
				die("Раллийная машина попала в тебя.\nНа этом выезд закончился.")
				return
		var d = node.position.distance_to(player_position())
		if d < nearest_d and racer.state in ["racing", "offroad"]:
			nearest = node
			nearest_d = d
	for racer in to_remove:
		racer.node.queue_free()
		racers.erase(racer)
	if nearest != null:
		rally_audio.position = nearest.position
		rally_audio.pitch_scale = 1.8
		if not rally_audio.playing:
			_play_audio(rally_audio)
	else:
		rally_audio.stop()

func _update_tow(delta: float) -> void:
	if tow_target == null and Input.is_action_pressed("tow"):
		for racer in racers:
			if racer.state == "stranded" and player_position().distance_to(racer.node.position) < 5:
				if car.position.distance_to(racer.node.position) > 24:
					toast("Подгони свою машину ближе: трос длиной 24 метра.")
					return
				tow_target = racer.node
				tow_progress = 0
				toast("Трос закреплён. Удерживай T рядом с экипажем или в своей машине.")
				break
	if tow_target == null:
		return
	var length = car.position.distance_to(tow_target.position)
	if length > 26:
		_cancel_tow()
		toast("Трос сорвался: машины слишком далеко друг от друга.")
		return
	if rope_mesh != null:
		rope_mesh.queue_free()
	rope_mesh = Props.rope(self, car.position + Vector3(0, 0.5, 0), tow_target.position + Vector3(0, 0.5, 0))
	if Input.is_action_pressed("tow") and (in_car or walker.distance_to(tow_target.position) < 6):
		tow_progress += delta / 6
		if tow_progress >= 1:
			for racer in racers:
				if racer.node == tow_target:
					racer.state = "racing"
					racer.kind = "pass"
					racer.counted = true
					racer.s += 10
					helped += 1
					break
			_cancel_tow()
			toast("Вытащили! Экипаж благодарит и продолжает СУ.")

func _cancel_tow() -> void:
	tow_target = null
	tow_progress = 0
	if rope_mesh != null:
		rope_mesh.queue_free()
		rope_mesh = null

func toast(message: String) -> void:
	if mobile_mode:
		var labels = {"Q —": "Поляна —", "Space —": "Тормоз —", "F —": "Стол —", "C —": "Стулья —", "G —": "Мангал —", "X —": "Есть —", "R —": "Заезды —", "— T": "— Трос", ": E.": ": Выйти.", "нажми X": "нажми Есть", "Удерживай T": "Удерживай Трос"}
		for key in labels:
			message = message.replace(key, labels[key])
	if toast_label != null:
		toast_label.text = message
		toast_label.visible = not mobile_mode
		toast_time = 5

func _update_hud() -> void:
	var distance = int(player_position().distance_to(stage.clearings[target_clearing]))
	quest_label.text = "%s Найти место  ·  %d м\n%s Разложить стол\n%s Поставить стулья\n%s Пожарить и съесть шашлык\n%s Посмотреть 6 экипажей" % ["[x]" if camp != null else "[ ]", distance, "[x]" if camp != null else "[ ]", "[x]" if has_chairs else "[ ]", "[x]" if eaten else "[ ]", "[x]" if passed >= 6 else "[ ]"]
	status_label.text = "ЭКИПАЖИ %d/6   ·   ПОМОЩЬ %d\nПИВО %d/3   ·   ВЫЕЗД %02d:%02d" % [passed, helped, beers, int(elapsed) / 60, int(elapsed) % 60]
	if in_car:
		info_label.text = "%02d КМ/Ч    ·    ЛЕГКОВУШКА %d%%    ·    %s" % [int(absf(speed) * 3.6), int(condition), "ОБОЧИНА" if stage.road_distance(car.position) > 4 else "ГРАВИЙ / КОЛЕЯ"]
		hint_label.text = "WASD / стрелки — газ и руль   ·   Space — тормоз   ·   E — выйти   ·   Q — случайная поляна   ·   Home — вернуть на СУ"
	else:
		var cook_status = "ШАШЛЫК ГОТОВ" if cook_time >= 35 else ("ШАШЛЫК %d%%" % int(cook_time / 35 * 100) if cooking else "МАНГАЛ НЕ РАЗОЖЖЁН")
		info_label.text = "ЗРИТЕЛЬ    ·    %s    ·    %s" % [cook_status, "СУ ОТКРЫТ" if racing else "ДО СТАРТА"]
		hint_label.text = "WASD — идти   ·   мышь — смотреть   ·   E — сесть   ·   F — стол   ·   C — стулья   ·   G — мангал   ·   B — пиво   ·   X — есть   ·   R — заезды"
		if drink_time >= 0:
			info_label.text = "ОТКРЫВАЕМ БАНКУ" if drink_time < 1.25 else "ЗА ХОРОШИЙ ВЫЕЗД!"
		if tow_target != null:
			info_label.text = "ВЫТАСКИВАЕМ ЭКИПАЖ   ·   %d%%   ·   УДЕРЖИВАЙ T" % int(tow_progress * 100)
	if mobile_mode:
		if in_car:
			info_label.text = "%02d КМ/Ч · МАШИНА %d%% · ПОЛЯНА %d м" % [int(absf(speed) * 3.6), int(condition), distance]
		else:
			info_label.text = info_label.text.replace("ЗРИТЕЛЬ    ·    ", "").replace("УДЕРЖИВАЙ T", "УДЕРЖИВАЙ ТРОС")
		if toast_time > 0:
			info_label.text += "\n" + toast_label.text
	minimap.queue_redraw()

func _check_finish() -> void:
	if dead:
		return
	if camp != null and has_chairs and eaten and passed >= 6:
		finished = true
		_show_result("Идеальный раллийный овощ", "Шашлык съеден. Ралли посмотрено. Ты выжил.\n\nЭкипажи: %d  ·  Помощь тросом: %d\nПиво: %d  ·  Машина: %d%%\n\nДень в лесу удался." % [passed, helped, beers, condition])

func die(reason: String) -> void:
	dead = true
	_show_result("Выезд окончен", reason + "\n\nЭкипажи: %d  ·  Помощь тросом: %d\nШашлык: %s" % [passed, helped, "съеден" if eaten else "не съеден"])

func _show_result(title: String, body: String) -> void:
	_cancel_drink()
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
