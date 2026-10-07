extends Control
class_name RallyMobileControls

var game: Node
var fingers: Dictionary = {}
var held: Dictionary = {}
var stick = Vector2.ZERO
var buttons: Array[Dictionary] = []
var last_size = Vector2.ZERO
var last_in_car = true
var map_open = false
var gear_open = false
var stick_center = Vector2.ZERO
const STICK_RADIUS = 62.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(reset_input)

func active() -> bool:
	return game != null and game.playing and not game.paused and not game.dead and not game.finished

func world_blocked() -> bool:
	return game.room.connected and not game.room.is_host and game.room.world_paused

func _process(_delta: float) -> void:
	if not active() or world_blocked() or last_in_car != game.in_car or last_size != size or not landscape():
		reset_input()
	last_in_car = game.in_car
	last_size = size
	_layout()
	game.mobile_sidebar.visible = active() and map_open
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		reset_input()

func landscape() -> bool:
	return size.x >= size.y

func add_button(label: String, action: String, hold: bool, rect: Rect2) -> void:
	buttons.append({"label": label, "action": action, "hold": hold, "rect": rect})

func _layout() -> void:
	buttons.clear()
	var edge = 24.0
	if not _has_role("stick"):
		stick_center = Vector2(edge + 84, size.y - edge - 80)
	if not active() or not landscape():
		return
	var primary = Vector2(size.x - edge - 120, size.y - edge - 136)
	var gear: Array[Array] = []
	if not world_blocked():
		if game.placement_kind != "":
			var actions = [["Поставить", "placement_confirm"], ["Повернуть", "placement_rotate"], ["Отмена", "placement_cancel"]]
			for i in range(actions.size()):
				add_button(actions[i][0], actions[i][1], false, Rect2(Vector2(size.x / 2 - 158 + i * 108, size.y - edge - 64), Vector2(100, 64)))
		elif game.in_car:
			add_button("Выйти", "interact", false, Rect2(primary - Vector2(-26, 100), Vector2(88, 64)))
			for i in range(3):
				add_button(["Назад", "Тормоз", "Газ"][i], ["back", "brake", "forward"][i], true, Rect2(Vector2(size.x - edge - 258 + i * 86, size.y - edge - 84), Vector2(78, 84)))
			gear = [["Вернуть", "recover"], ["Поляна", "random_spot"]]
		else:
			var target = game.interaction.current()
			var label = "Действие"
			if not target.is_empty():
				label = str(target.label).replace("Вернуть коробку в багажник", "Вернуть").replace("Собрать казан с подставкой", "Убрать казан").replace("Потушить и собрать костёр", "Убрать костёр").replace("Сесть в машину", "В машину").replace("Сесть на стул", "На стул").replace("Встать со стула", "Встать").replace("Собрать гриб", "Собрать").replace("Собрать ягоды", "Собрать").replace("Насадить гриб", "Насадить").replace("Съесть шашлык", "Шашлык").replace("Съесть гриб", "Есть гриб").replace("Выпить пиво", "Пиво").replace("Потушить и собрать мангал", "Убрать мангал").replace("Поставить казан на костёр", "На костёр").replace("Добавить ингредиенты и готовить плов", "Готовить плов").replace("Съесть плов", "Плов").replace("Собрать ", "Убрать ")
			add_button(label, "interact", false, Rect2(primary, Vector2(112, 96)))
			if not game.seated and game.beers < 30:
				add_button("Бег", "sprint", true, Rect2(primary + Vector2(-80, 54), Vector2(68, 68)))
				add_button("Прыжок", "jump", false, Rect2(primary + Vector2(34, -80), Vector2(70, 64)))
			gear = [["Поляна", "random_spot"]]
			if not game.packing.active():
				gear.append(["Стол", "table"])
				gear.append(["Стул", "chairs"])
				gear.append(["Мангал", "grill"])
				gear.append(["Дрова", "firewood"])
				gear.append(["Казан", "cauldron"])
				if game.flag_count() < game.FLAGS_PER_PLAYER:
					gear.append(["Флаг", "flag"])
			if game.foraging.can_eat("berries"):
				gear.append(["Ягоды", "eat_berries"])
			if game.tow_target != null or game.nearby_tow_racer():
				add_button("Трос", "tow", true, Rect2(primary + Vector2(-80, -26), Vector2(68, 68)))
		if not gear.is_empty():
			add_button("Вещи", "gear", false, Rect2(Vector2(size.x - edge - 210, edge), Vector2(66, 54)))
		if gear_open and game.placement_kind == "":
			var rows = ceili(gear.size() / 3.0)
			var origin = Vector2(size.x / 2 - 154, size.y - edge - rows * 56 - 12)
			for i in range(gear.size()):
				add_button(gear[i][0], gear[i][1], false, Rect2(origin + Vector2((i % 3) * 104, (i / 3) * 56), Vector2(96, 48)))
	add_button("Пауза", "pause_demo", false, Rect2(Vector2(size.x - edge - 66, edge), Vector2(66, 54)))
	add_button("Карта", "map", false, Rect2(Vector2(size.x - edge - 138, edge), Vector2(66, 54)))

func _input(event: InputEvent) -> void:
	if not active() or not landscape():
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			touch_begin(event.index, event.position)
		else:
			touch_end(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		touch_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()

func touch_begin(index: int, pos: Vector2) -> void:
	_layout()
	if not active() or not landscape():
		return
	if fingers.has(index):
		touch_end(index)
	if map_open and game.mobile_sidebar.get_global_rect().has_point(pos):
		return
	for button in buttons:
		if button.rect.has_point(pos):
			fingers[index] = {"kind": "button", "button": button, "pressed": true}
			if button.hold:
				_hold(button.action)
			elif button.action == "map":
				map_open = not map_open
				gear_open = false
			elif button.action == "gear":
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
	if world_blocked():
		return
	if pos.x < size.x * 0.5 and pos.y > size.y * 0.28 and not _has_role("stick"):
		if pos.distance_to(stick_center) > STICK_RADIUS * 1.6:
			stick_center = Vector2(clampf(pos.x, STICK_RADIUS + 24, size.x * 0.5 - STICK_RADIUS), clampf(pos.y, size.y * 0.28 + STICK_RADIUS, size.y - STICK_RADIUS - 24))
		fingers[index] = {"kind": "stick"}
		_move_stick(pos)
	elif pos.x >= size.x * 0.5 and not _has_role("look"):
		fingers[index] = {"kind": "look"}

func touch_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if not active() or not landscape() or world_blocked():
		reset_input()
		return
	if not fingers.has(index):
		return
	var finger: Dictionary = fingers[index]
	if finger.kind == "stick":
		_move_stick(pos)
	elif finger.kind == "look":
		game.view_yaw -= relative.x / maxf(size.x, 1) * 5.0
		game.view_pitch = clampf(game.view_pitch - relative.y / maxf(size.y, 480) * 3.0, -1.15, 1.1)
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
	elif finger.kind == "button" and finger.button.hold and finger.pressed:
		_release(finger.button.action)
	fingers.erase(index)

func _has_role(role: String) -> bool:
	for finger in fingers.values():
		if finger.kind == role:
			return true
	return false

func _move_stick(pos: Vector2) -> void:
	stick = ((pos - stick_center) / STICK_RADIUS).limit_length(1.0)
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

func _draw() -> void:
	if not active():
		return
	var font = ThemeDB.fallback_font
	if not landscape():
		draw_string(font, Vector2(0, size.y / 2), "Поверните устройство горизонтально", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
		return
	draw_string(font, Vector2(size.x * 0.62, size.y * 0.40), "ОБЗОР", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.30, 18, Color("f3e8cd70"))
	draw_circle(stick_center, STICK_RADIUS, Color("25352baa"))
	draw_arc(stick_center, STICK_RADIUS, 0, TAU, 40, Color("dfb270"), 3, true)
	draw_circle(stick_center + stick * 48, 28, Color("e3b16bdd"))
	var text = "РУЛЬ" if game.in_car else "ИДТИ"
	draw_string(font, stick_center + Vector2(-42, 94), text, HORIZONTAL_ALIGNMENT_CENTER, 84, 18, Color("f3e8cd"))
	for button in buttons:
		var pressed = false
		for finger in fingers.values():
			if finger.kind == "button" and finger.button.action == button.action and finger.pressed:
				pressed = true
		var style = StyleBoxFlat.new()
		style.bg_color = Color("d7a45eec") if pressed else Color("25352be6")
		style.border_color = Color("d7b479")
		style.set_border_width_all(2)
		style.set_corner_radius_all(16)
		draw_style_box(style, button.rect)
		draw_string(font, button.rect.position + Vector2(4, button.rect.size.y / 2 + 6), button.label, HORIZONTAL_ALIGNMENT_CENTER, button.rect.size.x - 8, 17, Color("f6ead1"))

