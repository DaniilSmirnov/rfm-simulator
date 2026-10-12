extends RefCounted
# Desktop mouse look owns the pointer while playing. A browser drops pointer
# lock on Esc or a window switch without passing that Esc to the game, and
# locks again only in answer to a click (and not within about a second after
# the player left the lock). So:
# - losing the lock during play opens the pause menu, as Esc does natively;
# - mouse look turns the camera only while the pointer is locked, so moving
#   a free cursor towards a button never spins the view;
# - while play runs without the lock, a hint asks for a click, which
#   game._unhandled_input turns into a new capture request.
const UiKit = preload("res://scripts/ui_kit.gd")
var game
var hint: Label
var was_captured = false

func build(ui: Control) -> void:
	hint = UiKit.label(ui, "Кликни по экрану, чтобы управлять камерой мышью", "body")
	hint.name = "PointerHint"
	hint.add_theme_stylebox_override("normal", UiKit.box(Color(UiKit.SHADOW, 0.85), Color.TRANSPARENT, 20, Vector2(20, 8)))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	hint.offset_top = 40
	hint.offset_bottom = 80
	hint.hide()

# Gameplay on a desktop, with no window or memo over it.
func wanted() -> bool:
	return game.playing and not game.paused and not game.dead and not game.finished and not game.mobile_mode \
		and (game.safety_gate == null or not is_instance_valid(game.safety_gate)) and not game.how_to_play.is_open()

func request() -> void:
	if game.mobile_mode or "--smoke-test" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func update(is_captured: bool = captured()) -> void:
	if was_captured and not is_captured and wanted():
		game._set_paused(true)
	was_captured = is_captured
	if hint != null:
		hint.visible = wanted() and not is_captured
