extends Control
class_name RallyMobileControls

var game: Node
var fingers: Dictionary = {}
var held: Dictionary = {}
var stick = Vector2.ZERO
var buttons: Array[Dictionary] = []
var layout_state: Array = []
var layout_revision = 0
var last_size = Vector2.ZERO
var last_in_car = true
var map_open = false
var gear_open = false
var gear_rect = Rect2()
var button_styles: Array[StyleBoxFlat] = []
var stick_center = Vector2.ZERO
const STICK_RADIUS = 62.0
const LOOK_RADIUS = STICK_RADIUS
var look_center = Vector2.ZERO
var look = Vector2.ZERO
var icons: Dictionary = {}
const ICON_NAMES = {"forward": "gas", "brake": "brake", "back": "reverse", "interact": "hand", "sprint": "run", "jump": "jump", "map": "map", "pause_demo": "pause", "gear": "bag", "recover": "recover", "table": "table", "chairs": "chair", "grill": "grill", "firewood": "wood", "cauldron": "pot", "flag": "flag", "eat_berries": "berries", "tow": "tow", "placement_confirm": "check", "placement_rotate": "rotate", "placement_cancel": "cancel"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(reset_input)
	for name in ICON_NAMES.values() + ["door", "eye"]:
		icons[name] = load("res://textures/ui/mobile/" + name + ".svg")
	for color in [Color("22342bd9"), Color("dfa963f2"), Color("dfb270e6")]:
		var style = StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = Color("d7b479")
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		button_styles.append(style)

func active() -> bool:
	return game != null and game.playing and not game.paused and not game.dead and not game.finished

func world_blocked() -> bool:
	return game.room.is_guest() and game.room.world_paused

func _process(_delta: float) -> void:
	game.fit_mobile_dialogs()
	if not active() or world_blocked() or last_in_car != game.in_car or last_size != size or not landscape():
		reset_input()
	last_in_car = game.in_car
	last_size = size
	_layout()
	game.mobile_sidebar.visible = active() and map_open
	if active() and landscape() and not world_blocked() and not map_open and not gear_open:
		game.view_yaw -= look.x * 2.4 * _delta
		game.view_pitch = clampf(game.view_pitch - look.y * 1.8 * _delta, -1.15, 1.1)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		reset_input()

func landscape() -> bool:
	return size.x >= size.y

func add_button(label: String, action: String, hold: bool, rect: Rect2) -> void:
	buttons.append({"label": label, "action": action, "hold": hold, "rect": rect})

func _layout() -> void:
	var edge = 24.0
	if not _has_role("stick"):
		stick_center = Vector2(edge + 84, size.y - edge - 80)
	var target: Dictionary = {}
	if active() and not game.in_car:
		target = game.hud_target if game.hud_target_frame == Engine.get_process_frames() else game.interaction.current()
	var state: Array = [size, active(), landscape(), world_blocked(), game.in_car, game.placement_kind,
		gear_open, game.seated, game.beers < 30, game.packing.active(), game.flag_count(),
		game.foraging.can_eat("berries"), game.tow_target != null, game.nearby_tow_racer(), target.get("label", "")]
	if state == layout_state:
		return
	layout_state = state
	layout_revision += 1
	buttons.clear()
	gear_rect = Rect2()
	if not active() or not landscape():
		return
	look_center = Vector2(size.x - edge - 84, size.y - edge - 80)
	var gear: Array[Array] = []
	if not world_blocked():
		if game.placement_kind != "":
			var actions = [["Поставить", "placement_confirm"], ["Повернуть", "placement_rotate"], ["Отмена", "placement_cancel"]]
			for i in range(actions.size()):
				add_button(actions[i][0], actions[i][1], false, Rect2(Vector2(size.x / 2 - 158 + i * 108, size.y - edge - 64), Vector2(100, 64)))
		elif game.in_car:
			# Two large pedals under the right thumb; reverse is a separate hold.
			add_button("Выйти", "interact", false, Rect2(Vector2(size.x - edge - 280, size.y - edge - 188), Vector2(88, 64)))
			add_button("Назад", "back", true, Rect2(Vector2(size.x - edge - 280, size.y - edge - 256), Vector2(88, 56)))
			add_button("Тормоз", "brake", true, Rect2(Vector2(size.x - edge - 184, size.y - edge - 256), Vector2(88, 112)))
			add_button("Газ", "forward", true, Rect2(Vector2(size.x - edge - 88, size.y - edge - 256), Vector2(88, 112)))
			gear = [["Вернуть", "recover"]]
		else:
			var label = "Действие"
			if not target.is_empty():
				label = str(target.label).replace("Вернуть коробку в багажник", "Вернуть").replace("Собрать казан с подставкой", "Убрать казан").replace("Потушить и собрать костёр", "Убрать костёр").replace("Сесть в машину", "В машину").replace("Сесть на стул", "На стул").replace("Встать со стула", "Встать").replace("Собрать гриб", "Собрать").replace("Собрать ягоды", "Собрать").replace("Собрать виноград", "Виноград").replace("Насадить гриб", "Насадить").replace("Съесть шашлык", "Шашлык").replace("Съесть гриб", "Есть гриб").replace("Выпить пиво", "Пиво").replace("Потушить и собрать мангал", "Убрать мангал").replace("Поставить казан на костёр", "На костёр").replace("Добавить ингредиенты и готовить плов", "Готовить плов").replace("Съесть плов", "Плов").replace("Собрать ", "Убрать ")
			add_button(label, "interact", false, Rect2(Vector2(size.x - edge - 96, size.y - edge - 256), Vector2(96, 100)))
			if not game.seated and game.beers < 30:
				add_button("Бег", "sprint", true, Rect2(Vector2(size.x - edge - 280, size.y - edge - 256), Vector2(64, 72)))
				add_button("Прыжок", "jump", false, Rect2(Vector2(size.x - edge - 204, size.y - edge - 256), Vector2(96, 64)))
			gear = []
			if not game.packing.active():
				gear.append(["Стол", "table"])
				gear.append(["Стул", "chairs"])
				gear.append(["Мангал", "grill"])
				gear.append(["Дрова", "firewood"])
				gear.append(["Казан", "cauldron"])
				if game.flag_count() < game.FLAGS_PER_PLAYER:
					gear.append(["Флаг", "flag"])
			if game.foraging.can_eat("berries"):
				gear.append(["Виноград" if game.stage.provence else "Ягоды", "eat_berries"])
			if game.tow_target != null or game.nearby_tow_racer():
				add_button("Трос", "tow", true, Rect2(Vector2(size.x - edge - 360, size.y - edge - 256), Vector2(68, 68)))
		if not gear.is_empty():
			add_button("Лагерь", "gear", false, Rect2(Vector2(size.x - edge - 216, edge), Vector2(64, 56)))
		if gear_open and game.placement_kind == "":
			var rows = ceili(gear.size() / 3.0)
			var origin = Vector2(size.x / 2 - 154, size.y - edge - rows * 64 - 12)
			gear_rect = Rect2(origin - Vector2(8, 8), Vector2(316, rows * 64 + 8))
			for i in range(gear.size()):
				add_button(gear[i][0], gear[i][1], false, Rect2(origin + Vector2((i % 3) * 104, (i / 3) * 64), Vector2(96, 56)))
	add_button("Пауза", "pause_demo", false, Rect2(Vector2(size.x - edge - 64, edge), Vector2(64, 56)))
	add_button("Карта", "map", false, Rect2(Vector2(size.x - edge - 140, edge), Vector2(64, 56)))

func _input(event: InputEvent) -> void:
	if not active() or not landscape():
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			var point = get_global_transform().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, size).has_point(point):
				return
			touch_begin(event.index, point)
		else:
			touch_end(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		touch_drag(event.index, get_global_transform().affine_inverse() * event.position, event.relative / scale)
		get_viewport().set_input_as_handled()

func touch_begin(index: int, pos: Vector2) -> void:
	_layout()
	if not active() or not landscape():
		return
	if fingers.has(index):
		touch_end(index)
	if map_open and game.mobile_sidebar.get_global_rect().has_point(get_global_transform() * pos):
		return
	for button in buttons:
		if button.rect.has_point(pos):
			fingers[index] = {"kind": "button", "button": button, "pressed": true}
			if button.hold:
				_hold(button.action)
			elif button.action == "map":
				reset_input()
				map_open = not map_open
				gear_open = false
			elif button.action == "gear":
				reset_input()
				gear_open = not gear_open
				map_open = false
			else:
				var action = InputEventAction.new()
				action.action = button.action
				action.pressed = true
				game._unhandled_input(action)
				if not button.hold:
					gear_open = false
			return
	if gear_open:
		# Drawer gaps/outside taps never turn into camera or movement input.
		if not gear_rect.has_point(pos):
			gear_open = false
		return
	if world_blocked():
		return
	if pos.x < size.x * 0.5 and pos.y > size.y * 0.28 and not _has_role("stick"):
		if pos.distance_to(stick_center) > STICK_RADIUS * 1.6:
			stick_center = Vector2(clampf(pos.x, STICK_RADIUS + 24, size.x * 0.5 - STICK_RADIUS), clampf(pos.y, size.y * 0.28 + STICK_RADIUS, size.y - STICK_RADIUS - 24))
		fingers[index] = {"kind": "stick"}
		_move_stick(pos)
	elif not map_open and pos.distance_to(look_center) <= LOOK_RADIUS and not _has_role("look"):
		fingers[index] = {"kind": "look"}
		_move_look(pos)

func touch_drag(index: int, pos: Vector2, _relative: Vector2) -> void:
	if not active() or not landscape() or world_blocked():
		reset_input()
		return
	if not fingers.has(index):
		return
	var finger: Dictionary = fingers[index]
	if finger.kind == "stick":
		_move_stick(pos)
	elif finger.kind == "look":
		_move_look(pos)
	elif finger.button.hold:
		var inside: bool = finger.button.rect.has_point(pos)
		if inside != finger.pressed:
			_hold(finger.button.action) if inside else _release(finger.button.action)
			finger.pressed = inside

func touch_end(index: int) -> void:
	if not fingers.has(index):
		return
	var finger: Dictionary = fingers[index]
	if finger.kind == "stick":
		stick = Vector2.ZERO
		_set_axis("left", "right", 0)
		_set_axis("forward", "back", 0)
	elif finger.kind == "look":
		look = Vector2.ZERO
	elif finger.kind == "button" and finger.button.hold and finger.pressed:
		_release(finger.button.action)
	fingers.erase(index)

func _has_role(role: String) -> bool:
	for finger in fingers.values():
		if finger.kind == role:
			return true
	return false

func _move_look(pos: Vector2) -> void:
	look = ((pos - look_center) / LOOK_RADIUS).limit_length(1.0)
	if look.length() < 0.12:
		look = Vector2.ZERO

func button_icon(button: Dictionary) -> Texture2D:
	var name: String = ICON_NAMES.get(button.action, "hand")
	if button.action == "interact" and (game.in_car or button.label == "В машину"):
		name = "door"
	return icons.get(name)

func _move_stick(pos: Vector2) -> void:
	var delta = (pos - stick_center) / STICK_RADIUS
	# Full circular joystick: steering on X, gas and brake on separate buttons.
	stick = delta.limit_length(1.0)
	if stick.length() < 0.12:
		stick = Vector2.ZERO
	_set_axis("left", "right", stick.x)
	if not game.in_car:
		_set_axis("forward", "back", stick.y)

func _set_axis(negative: String, positive: String, value: float) -> void:
	# Stick axes own one reference; pedal buttons can hold a separate action.
	for action in [negative, positive]:
		if held.get("axis_" + action, false):
			_release(action)
			held.erase("axis_" + action)
	if not is_zero_approx(value):
		var action = negative if value < 0 else positive
		_hold(action, absf(value))
		held["axis_" + action] = true

func _hold(action: String, strength: float = 1.0) -> void:
	held[action] = int(held.get(action, 0)) + 1
	Input.action_press(action, strength)

func _release(action: String) -> void:
	var count = int(held.get(action, 0)) - 1
	if count <= 0:
		held.erase(action)
		Input.action_release(action)
	else:
		held[action] = count

func reset_input() -> void:
	for action in held.keys():
		if not str(action).begins_with("axis_"):
			Input.action_release(action)
	held.clear()
	fingers.clear()
	stick = Vector2.ZERO
	look = Vector2.ZERO

func _draw() -> void:
	if not active():
		return
	var font = ThemeDB.fallback_font
	if not landscape():
		draw_string(font, Vector2(0, size.y / 2), "Поверните устройство горизонтально", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
		return
	if gear_open and gear_rect.has_area():
		draw_style_box(button_styles[0], gear_rect)
	draw_circle(stick_center, STICK_RADIUS, Color("25352baa"))
	draw_arc(stick_center, STICK_RADIUS, 0, TAU, 40, Color("dfb270"), 3, true)
	# Circular driving joystick; pedals independently control throttle and brake.
	draw_circle(stick_center + stick * 48, 28, Color("e3b16bdd"))
	var text = "ДЖОЙСТИК" if game.in_car else "ИДТИ"
	draw_string(font, stick_center + Vector2(-42, 94), text, HORIZONTAL_ALIGNMENT_CENTER, 84, 18, Color("f3e8cd"))
	if not map_open and not gear_open and not world_blocked():
		draw_circle(look_center, LOOK_RADIUS, Color("25352baa"))
		draw_arc(look_center, LOOK_RADIUS, 0, TAU, 40, Color("dfb270"), 3, true)
		draw_circle(look_center + look * 48, 28, Color("e3b16bdd"))
		draw_texture_rect(icons["eye"], Rect2(look_center + look * 48 - Vector2(14, 14), Vector2(28, 28)), false, Color("22342b"))
	for button in buttons:
		var pressed = false
		for finger in fingers.values():
			if finger.kind == "button" and finger.button.action == button.action and finger.pressed:
				pressed = true
		var emphasized = button.action == "forward" or (button.action == "interact" and not game.in_car)
		var style = button_styles[1 if pressed else (2 if emphasized else 0)]
		draw_style_box(style, button.rect)
		var text_color = Color("22342b") if pressed or emphasized else Color("f6ead1")
		var icon = button_icon(button)
		if icon != null:
			var extent = 36.0 if button.rect.size.y < 80 else 44.0
			draw_texture_rect(icon, Rect2(button.rect.get_center() - Vector2.ONE * extent / 2, Vector2.ONE * extent), false, text_color)
