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
var stick_center = Vector2.ZERO
const STICK_RADIUS = 76.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(reset_input)

func active() -> bool:
	return game != null and game.playing and not game.paused and not game.dead and not game.finished

func world_blocked() -> bool:
	return game.room.connected and not game.room.is_host and game.room.world_paused

func _process(_delta: float) -> void:
	if not active() or world_blocked() or last_in_car != game.in_car or last_size != size:
		reset_input()
	last_in_car = game.in_car
	last_size = size
	_layout()
	game.mobile_sidebar.visible = active() and map_open
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		reset_input()

func _layout() -> void:
	buttons.clear()
	var edge = maxf(36, size.x * 0.055)
	stick_center = Vector2(edge + 82, size.y - 150)
	if not active():
		return
	var actions: Array[Array] = []
	if world_blocked():
		actions = []
	elif game.placement_kind != "":
		actions = [["Поставить", "placement_confirm", false], ["Повернуть", "placement_rotate", false], ["Отмена", "placement_cancel", false]]
	elif game.in_car:
		actions = [["Выйти", "interact", false], ["Вернуть", "recover", false], ["Поляна", "random_spot", false], ["Назад", "back", true], ["Тормоз", "brake", true], ["Газ", "forward", true]]
		if game.tow_target != null or game.nearby_tow_racer():
			actions[1] = ["Трос", "tow", true]
	else:
		actions = [["Сесть", "interact", false], ["Поляна", "random_spot", false]]
		actions.append(["Стол", "table", false])
		actions.append(["Стул", "chairs", false])
		if game.camp != null and game.has_chairs:
			actions.append(["Мангал", "grill", false])
		if game.cook_time >= 35:
			actions.append(["Есть", "eat", false])
		if game.near_camp():
			actions.append(["Пиво", "beer", false])
		if game.tow_target != null or game.nearby_tow_racer():
			actions.append(["Трос", "tow", true])
	var width = 100.0
	var height = 84.0
	var gap = 12.0
	var rows = ceili(actions.size() / 3.0)
	var origin = Vector2(size.x - edge - 3 * width - 2 * gap, size.y - 60 - rows * (height + gap))
	for i in range(actions.size()):
		buttons.append({"label": actions[i][0], "action": actions[i][1], "hold": actions[i][2], "rect": Rect2(origin + Vector2((i % 3) * (width + gap), (i / 3) * (height + gap)), Vector2(width, height))})
	buttons.append({"label": "Пауза", "action": "pause_demo", "hold": false, "rect": Rect2(Vector2(size.x - edge - 212, 64), Vector2(100, 70))})
	buttons.append({"label": "Карта", "action": "map", "hold": false, "rect": Rect2(Vector2(size.x - edge - 100, 64), Vector2(100, 70))})

func _input(event: InputEvent) -> void:
	if not active():
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
	if fingers.has(index):
		touch_end(index)
	for button in buttons:
		if button.rect.has_point(pos):
			fingers[index] = {"kind": "button", "button": button, "pressed": true}
			if button.hold:
				_hold(button.action)
			elif button.action == "map":
				map_open = not map_open
			else:
				var action = InputEventAction.new()
				action.action = button.action
				action.pressed = true
				game._unhandled_input(action)
			return
	if world_blocked():
		return
	if pos.distance_to(stick_center) < 115 and not _has_role("stick"):
		fingers[index] = {"kind": "stick"}
		_move_stick(pos)
	elif not game.in_car and pos.x > size.x * 0.32 and not _has_role("look"):
		if map_open and game.mobile_sidebar.get_global_rect().has_point(pos):
			return
		fingers[index] = {"kind": "look"}

func touch_drag(index: int, pos: Vector2, relative: Vector2) -> void:
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
	draw_circle(stick_center, STICK_RADIUS, Color("25352baa"))
	draw_arc(stick_center, STICK_RADIUS, 0, TAU, 40, Color("dfb270"), 3, true)
	draw_circle(stick_center + stick * 48, 28, Color("e3b16bdd"))
	var text = "РУЛЬ" if game.in_car else "ИДТИ"
	draw_string(font, stick_center + Vector2(-42, 108), text, HORIZONTAL_ALIGNMENT_CENTER, 84, 23, Color("f3e8cd"))
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
		draw_string(font, button.rect.position + Vector2(0, button.rect.size.y / 2 + 8), button.label, HORIZONTAL_ALIGNMENT_CENTER, button.rect.size.x, 23, Color("f6ead1"))
