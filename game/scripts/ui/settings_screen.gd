extends Node
# The settings window, opened by the gear in the menu header (main menu and
# pause): draw distance, game sound and radio volume and, in a desktop window, the window
# mode and resolution. Every choice applies at once and is kept between
# launches. The browser page has its own fullscreen button and no window to
# resize, so the screen section is shown only by native desktop builds.
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const MenuChoice = preload("res://scripts/ui/menu_choice.gd")
const SoundBank = preload("res://scripts/core/sound_bank.gd")
const AUDIO_SETTINGS_PATH = "user://audio_settings.cfg"
const DISPLAY_SETTINGS_PATH = "user://display_settings.cfg"
# Window sizes offered in windowed mode; ones larger than the screen are left out.
const RESOLUTIONS = [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const WINDOWED = 0
const FULLSCREEN = 1
const WINDOW_MODES = ["В ОКНЕ", "ВО ВЕСЬ ЭКРАН"]
var game: Node3D
var root: Control
var audio_path = AUDIO_SETTINGS_PATH
var display_path = DISPLAY_SETTINGS_PATH
var volume_label: Label
var volume_slider: HSlider
var radio_label: Label
var radio_slider: HSlider
var display_controls: VBoxContainer
var window_mode_buttons: Array[Button] = []
var resolution_choice: HBoxContainer
var resolution_note: Label
var resolutions: Array[Vector2i] = []
var window_mode = FULLSCREEN
var resolution = Vector2i.ZERO

static func has_display_settings() -> bool:
	return OS.has_feature("pc") and not OS.has_feature("web")

func build(layer: Control) -> void:
	var modal = UiKit.modal(layer, "SettingsDialog", 520)
	root = modal.root
	UiKit.label(modal.content, "Настройки", "heading")
	_build_draw_distance(modal.content)
	_build_audio(modal.content)
	_build_display(modal.content)
	var close = UiKit.button(modal.content, "ГОТОВО", "primary", 46)
	close.name = "Close"
	close.pressed.connect(close_screen)

func is_open() -> bool:
	return root != null and root.visible

func open() -> void:
	update_draw_distance_buttons()
	# A VK profile can switch the language to Russian without a retranslate.
	retranslate()
	root.show()
	game.hud.fit_modal(root)
	# Wrapped hints settle their height a frame later.
	game.hud.fit_modal.call_deferred(root)

func close_screen() -> void:
	root.hide()

# Resuming play (or the result window) takes the settings away with the pause menu.
func _process(_delta: float) -> void:
	if is_open() and game.playing and (not game.paused or game.dead or game.finished):
		close_screen()

# Esc closes this window before the game sees it (and resumes or pauses).
func _unhandled_input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("pause_demo") or event.is_action_pressed("ui_cancel")):
		close_screen()
		get_viewport().set_input_as_handled()

func retranslate() -> void:
	_show_volume(volume_slider.value)
	_show_radio_volume(radio_slider.value)
	_show_display()

func _section(parent: Control, title: String, node_name: String) -> VBoxContainer:
	var card = UiKit.card(parent, UiKit.SURFACE_SUNKEN, Vector2(16, 12))
	var column = UiKit.vbox(card, 8)
	column.name = node_name
	UiKit.label(column, title, "caption")
	return column

# ---------------------------------------------------------------- graphics

func _build_draw_distance(parent: Control) -> void:
	game.draw_distance_controls = _section(parent, "ДАЛЬНОСТЬ ПРОРИСОВКИ", "DrawDistanceSettings")
	var row = UiKit.hbox(game.draw_distance_controls, 8)
	# Listed cheapest first; draw_distance_buttons stays indexed by mode.
	game.draw_distance_buttons.resize(game.draw_distance.LABELS.size())
	for index in game.draw_distance.ORDER:
		var button = UiKit.expand(UiKit.button(row, game.draw_distance.LABELS[index], "toggle", 42))
		button.set_pressed_no_signal(index == game.draw_distance.mode)
		button.pressed.connect(set_draw_distance.bind(index))
		game.draw_distance_buttons[index] = button
	var hint = UiKit.wrap(UiKit.label(game.draw_distance_controls, "Чем ближе, тем выше FPS. В браузере и на телефоне лучше «Средне» или «Минимум».", "muted"))
	hint.add_theme_font_size_override("font_size", 13)

func set_draw_distance(index: int) -> void:
	game.draw_distance.mode = clampi(index, game.draw_distance.NEAR, game.draw_distance.LOW)
	game.draw_distance.apply(game.stage)
	update_draw_distance_buttons()
	if game.draw_distance.save_settings() != OK:
		push_warning("Не удалось сохранить настройку графики")

func update_draw_distance_buttons() -> void:
	for index in range(game.draw_distance_buttons.size()):
		game.draw_distance_buttons[index].set_pressed_no_signal(index == game.draw_distance.mode)

# ---------------------------------------------------------------- sound

func _build_audio(parent: Control) -> void:
	var settings = ConfigFile.new()
	var loaded = settings.load(audio_path) == OK
	var column = _section(parent, "ЗВУК", "AudioSettings")
	volume_label = UiKit.label(column, "", "body")
	volume_slider = _volume_slider(column, "MasterVolume", "Громкость звуков игры, кроме рации. 0 — без звука.", _saved_percent(settings, "volume") if loaded else 100.0)
	radio_label = UiKit.label(column, "", "body")
	radio_slider = _volume_slider(column, "RadioVolume", "Громкость голосов в рации. 0 — рация молчит.", _saved_percent(settings, "radio_volume") if loaded else 100.0)
	_apply_volume(volume_slider.value)
	_apply_radio_volume(radio_slider.value)
	volume_slider.value_changed.connect(func(value: float):
		_apply_volume(value)
		_save_audio()
	)
	radio_slider.value_changed.connect(func(value: float):
		_apply_radio_volume(value)
		_save_audio()
	)

func _saved_percent(settings: ConfigFile, key: String) -> float:
	var saved = settings.get_value("audio", key, 100.0)
	return clampf(float(saved), 0.0, 100.0) if (saved is float or saved is int) and is_finite(float(saved)) else 100.0

func _volume_slider(column: Control, node_name: String, tooltip: String, percent: float) -> HSlider:
	var slider = HSlider.new()
	slider.name = node_name
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(0, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = tooltip
	column.add_child(slider)
	slider.value = percent
	return slider

func _save_audio() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "volume", volume_slider.value)
	config.set_value("audio", "radio_volume", radio_slider.value)
	if config.save(audio_path) != OK:
		game.toast("Не удалось сохранить громкость.")

# The general slider is the Sounds bus, not Master: the radio sends to Master
# too, and it has its own slider.
func _apply_volume(percent: float) -> void:
	var sounds = AudioServer.get_bus_index(SoundBank.BUS)
	AudioServer.set_bus_mute(sounds, percent <= 0)
	AudioServer.set_bus_volume_db(sounds, linear_to_db(maxf(percent / 100.0, 0.0001)))
	_show_volume(percent)

# The Radio bus (default_bus_layout.tres) carries every voice, native and, as
# a gain sent to the page, browser ones; its boost and limiter stay as they are.
func _apply_radio_volume(percent: float) -> void:
	var radio = AudioServer.get_bus_index("Radio")
	if radio >= 0:
		AudioServer.set_bus_mute(radio, percent <= 0)
		AudioServer.set_bus_volume_db(radio, linear_to_db(maxf(percent / 100.0, 0.0001)))
	_show_radio_volume(percent)

func _show_volume(percent: float) -> void:
	volume_label.text = Loc.t("ЗВУК ВЫКЛЮЧЕН") if percent <= 0 else Loc.t("ГРОМКОСТЬ · %d%%") % roundi(percent)

func _show_radio_volume(percent: float) -> void:
	radio_label.text = Loc.t("РАЦИЯ ВЫКЛЮЧЕНА") if percent <= 0 else Loc.t("ГРОМКОСТЬ РАЦИИ · %d%%") % roundi(percent)

# ---------------------------------------------------------------- screen

func _build_display(parent: Control) -> void:
	_load_display()
	display_controls = _section(parent, "ЭКРАН", "DisplaySettings")
	var modes = UiKit.hbox(display_controls, 8)
	modes.name = "WindowMode"
	for index in range(WINDOW_MODES.size()):
		var button = UiKit.expand(UiKit.button(modes, WINDOW_MODES[index], "toggle", 42))
		button.pressed.connect(set_window_mode.bind(index))
		window_mode_buttons.append(button)
	var row = UiKit.hbox(display_controls, 10)
	var caption = UiKit.label(row, "Разрешение", "body")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resolution_choice = UiKit.expand(MenuChoice.new())
	resolution_choice.name = "Resolution"
	resolution_choice.custom_minimum_size.y = 42
	row.add_child(resolution_choice)
	for size in resolutions:
		resolution_choice.add_item("%d × %d" % [size.x, size.y])
	resolution_choice.item_selected.connect(func(index: int): set_resolution(resolutions[index]))
	resolution_note = UiKit.wrap(UiKit.label(display_controls, "", "muted"))
	resolution_note.add_theme_font_size_override("font_size", 13)
	display_controls.get_parent().visible = has_display_settings()
	if has_display_settings():
		apply_display()
	_show_display()

# The sizes that fit the screen, with the saved one (or the start-up window)
# selected. Without a saved choice the game keeps the project's fullscreen start.
func _load_display() -> void:
	var screen = DisplayServer.screen_get_size()
	resolutions.clear()
	for size in RESOLUTIONS:
		if screen.x <= 0 or (size.x <= screen.x and size.y <= screen.y):
			resolutions.append(size)
	if resolutions.is_empty():
		resolutions.append(RESOLUTIONS[0])
	window_mode = FULLSCREEN
	resolution = Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"), ProjectSettings.get_setting("display/window/size/window_height_override"))
	var config = ConfigFile.new()
	if config.load(display_path) == OK:
		window_mode = WINDOWED if config.get_value("display", "mode", "fullscreen") == "windowed" else FULLSCREEN
		var saved = config.get_value("display", "resolution", resolution)
		if saved is Vector2i:
			resolution = saved
	if not resolution in resolutions:
		resolution = resolutions[_closest(resolution)]

func _closest(size: Vector2i) -> int:
	var best = 0
	for i in range(resolutions.size()):
		if absi(resolutions[i].x * resolutions[i].y - size.x * size.y) < absi(resolutions[best].x * resolutions[best].y - size.x * size.y):
			best = i
	return best

func set_window_mode(mode: int) -> void:
	window_mode = clampi(mode, WINDOWED, FULLSCREEN)
	apply_display()
	_save_display()
	_show_display()

func set_resolution(size: Vector2i) -> void:
	resolution = size
	apply_display()
	_save_display()
	_show_display()

# Fullscreen uses the screen's own resolution; the chosen size is the window's.
func apply_display() -> void:
	if not has_display_settings():
		return
	var window = game.get_window()
	if window_mode == FULLSCREEN:
		if window.mode != Window.MODE_FULLSCREEN and window.mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
			window.mode = Window.MODE_FULLSCREEN
		return
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	window.size = resolution
	var screen = DisplayServer.screen_get_usable_rect(window.current_screen)
	if screen.size.x > 0:
		window.position = screen.position + (screen.size - resolution) / 2

func _save_display() -> void:
	var config = ConfigFile.new()
	config.set_value("display", "mode", "windowed" if window_mode == WINDOWED else "fullscreen")
	config.set_value("display", "resolution", resolution)
	if config.save(display_path) != OK:
		push_warning("Не удалось сохранить настройки экрана")

func _show_display() -> void:
	if resolution_choice == null:
		return
	for index in range(window_mode_buttons.size()):
		window_mode_buttons[index].set_pressed_no_signal(index == window_mode)
	resolution_choice.select(resolutions.find(resolution))
	for child in resolution_choice.get_children():
		if child is Button:
			child.disabled = window_mode == FULLSCREEN
	resolution_choice.modulate.a = 0.5 if window_mode == FULLSCREEN else 1.0
	var screen = DisplayServer.screen_get_size()
	resolution_note.text = Loc.t("Во весь экран игра идёт в разрешении экрана: %d × %d.") % [screen.x, screen.y] if window_mode == FULLSCREEN else Loc.t("Размер окна. Его можно менять и мышью.")
