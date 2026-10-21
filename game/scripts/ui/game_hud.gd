extends RefCounted
# The in-game interface: HUD cards, toasts, the menu window (main menu, pause,
# result), mobile safe area, draw distance and invite buttons. Every control is
# styled by ui_kit.gd. The nodes stay on game (menu, toast_label, ...) where
# other scripts and tests use them.
const MiniMap = preload("res://scripts/ui/minimap.gd")
const Props = preload("res://scripts/core/props.gd")
const Stage = preload("res://scripts/stages/stage.gd")
const StageRegistry = preload("res://scripts/stages/stage_registry.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const Demo = preload("res://scripts/core/demo.gd")

var game
# Menu window parts that change with the screen (main menu / pause / result).
var dialog_layer: Control
var dialog_area: Control
var menu_dim: ColorRect
var header: HBoxContainer
var brand: HBoxContainer
var links: HBoxContainer
var entry_slot: VBoxContainer
var settings: PanelContainer
var footer: Label
var top_box: VBoxContainer
var guide_button: Button
var secondary_row: HBoxContainer
var plan_title: Label

func request_game_mouse_capture() -> void:
	game.pointer.request()

func panel(color: Color) -> StyleBoxFlat:
	return UiKit.panel_style(color)

func label(parent: Node, text: String, font_size: int, color: Color = UiKit.TEXT) -> Label:
	var l = UiKit.label(parent, text)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func build_ui() -> void:
	var canvas = CanvasLayer.new()
	game.add_child(canvas)
	var ui = Control.new()
	ui.name = "Hud"
	ui.theme = UiKit.theme()
	game.mobile_ui = ui
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_crosshair(ui)
	build_top(ui)
	build_sidebar(ui)
	build_bottom(ui)
	build_notices(ui)
	game.pointer = preload("res://scripts/platform/pointer_capture.gd").new()
	game.pointer.game = game
	game.pointer.build(ui)
	build_menu(canvas)

func hud_card(parent: Control) -> PanelContainer:
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.HUD, Vector2(18, 12)))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	return card

func build_crosshair(ui: Control) -> void:
	game.crosshair = label(ui, "·", 24, Color("fff0cb"))
	game.crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game.crosshair.offset_left = -16
	game.crosshair.offset_right = 16
	game.crosshair.offset_top = -16
	game.crosshair.offset_bottom = 16
	game.crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.crosshair.hide()

# Top left: stage, phase of the stage and (in a room) the room line.
func build_top(ui: Control) -> void:
	var top = hud_card(ui)
	top.name = "StageCard"
	game.mobile_top = top
	top.position = Vector2(24, 24)
	top_box = UiKit.vbox(top, 4)
	game.stage_caption = UiKit.label(top_box, StageRegistry.caption(game.selected_stage).to_upper(), "caption")
	game.course_label = UiKit.label(top_box, "", "hud")
	game.course_label.hide()
	game.fps_label = UiKit.label(top_box, "v%s · — FPS" % ProjectSettings.get_setting("application/config/version"), "muted")
	game.fps_label.add_theme_font_size_override("font_size", 12)
	game.fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

# Top right: the plan for the trip, minimap and counters.
func build_sidebar(ui: Control) -> void:
	var sidebar = hud_card(ui)
	sidebar.name = "PlanCard"
	game.mobile_sidebar = sidebar
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sidebar.offset_left = -320
	sidebar.offset_right = -24
	sidebar.offset_top = 24
	sidebar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sidebar.hide()
	game.hud_panels.append(sidebar)
	var sv = UiKit.vbox(sidebar, 10)
	plan_title = UiKit.label(sv, "ПЛАН НА ВЫЕЗД", "caption")
	game.quest_label = UiKit.label(sv, "", "body")
	game.quest_label.add_theme_font_size_override("font_size", 15)
	game.minimap = MiniMap.new()
	game.minimap.game = game
	game.minimap.custom_minimum_size = Vector2(264, 200)
	sv.add_child(game.minimap)
	game.status_label = UiKit.label(sv, "", "muted")

# Bottom: what the player is doing now and the controls for it.
func build_bottom(ui: Control) -> void:
	var bottom = hud_card(ui)
	bottom.name = "ActionCard"
	game.mobile_bottom = bottom
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -112
	bottom.offset_bottom = -24
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.hide()
	game.hud_panels.append(bottom)
	var bv = UiKit.vbox(bottom, 4)
	game.info_label = UiKit.label(bv, "", "hud")
	game.info_label.add_theme_font_size_override("font_size", 21)
	game.hint_label = UiKit.wrap(UiKit.label(bv, "", "muted"))
	game.hint_label.add_theme_font_size_override("font_size", 14)

# Toast, recovery timer and the health warning float over the scene.
func build_notices(ui: Control) -> void:
	game.toast_label = UiKit.label(ui, "", "body")
	game.toast_label.name = "Toast"
	game.toast_label.add_theme_font_size_override("font_size", 19)
	game.toast_label.add_theme_stylebox_override("normal", UiKit.box(UiKit.SHADOW.lerp(Color.TRANSPARENT, 0.15), Color.TRANSPARENT, 20, Vector2(20, 8)))
	game.toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	game.toast_label.offset_top = -168
	game.toast_label.offset_bottom = -128
	game.toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	game.toast_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	game.toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.toast_label.hide()
	game.sobriety_panel = hud_card(ui)
	game.sobriety_panel.anchor_left = 0.25
	game.sobriety_panel.anchor_right = 0.75
	game.sobriety_panel.offset_top = 150
	game.sobriety_panel.offset_bottom = 245
	var recovery_box = UiKit.vbox(game.sobriety_panel, 10)
	recovery_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sobriety_label = UiKit.wrap(UiKit.label(recovery_box, "", "hud"))
	game.sobriety_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.sobriety_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sobriety_bar = ProgressBar.new()
	game.sobriety_bar.max_value = game.SOBER_SECONDS
	game.sobriety_bar.custom_minimum_size.y = 20
	game.sobriety_bar.show_percentage = false
	game.sobriety_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recovery_box.add_child(game.sobriety_bar)
	game.sobriety_panel.hide()
	game.consumption_warning = hud_card(ui)
	game.consumption_warning.name = "ConsumptionWarning"
	game.consumption_warning.add_theme_stylebox_override("panel", UiKit.panel_style(Color("2b2a1e"), Vector2(18, 12)))
	game.consumption_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	game.consumption_warning.offset_left = -330
	game.consumption_warning.offset_right = 330
	game.consumption_warning.offset_top = 24
	game.consumption_warning_text = UiKit.wrap(UiKit.label(game.consumption_warning, "", "body"))
	game.consumption_warning_text.add_theme_color_override("font_color", UiKit.HIGHLIGHT)
	game.consumption_warning_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game.consumption_warning_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.consumption_warning.hide()

# One window for the main menu, pause and result. Its parts are shown per
# screen in update_menu(): header, text, selection, entry, actions, settings.
func build_menu(canvas: CanvasLayer) -> void:
	dialog_layer = Control.new()
	dialog_layer.name = "Dialogs"
	dialog_layer.theme = UiKit.theme()
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(dialog_layer)
	dialog_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_dim = ColorRect.new()
	menu_dim.name = "MenuDim"
	menu_dim.color = UiKit.DIM
	dialog_layer.add_child(menu_dim)
	menu_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_dim.hide()
	dialog_area = Control.new()
	dialog_area.name = "SafeArea"
	dialog_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog_layer.add_child(dialog_area)
	dialog_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.menu = PanelContainer.new()
	game.menu.name = "Menu"
	dialog_area.add_child(game.menu)
	game.menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game.menu_content = UiKit.vbox(game.menu, 16)
	game.menu_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.lobby_ui = preload("res://scripts/ui/lobby_ui.gd").new()
	game.lobby_ui.game = game
	game.add_child(game.lobby_ui)
	build_menu_header(game.menu_content)
	game.menu_text = UiKit.wrap(UiKit.label(game.menu_content, "", "body"))
	game.menu_text.hide()
	game.selection_controls = UiKit.vbox(game.menu_content, 10)
	game.selection_controls.name = "Selection"
	game.lobby_ui.build_selection(game.selection_controls)
	entry_slot = UiKit.vbox(game.menu_content, 0)
	entry_slot.name = "Entry"
	build_menu_actions(game.menu_content)
	footer = UiKit.label(game.menu_content, Loc.t("Версия %s") % ProjectSettings.get_setting("application/config/version"), "muted")
	footer.add_theme_font_size_override("font_size", 12)
	game.lobby_ui.finish(game.menu_content)
	game.how_to_play = preload("res://scripts/ui/how_to_play.gd").new()
	game.how_to_play.game = game
	game.how_to_play.build(dialog_layer)
	game.how_to_play.finished.connect(open_stage_safety_gate)

# Brand (main menu) or the window title (pause, result) on the left; site and
# support links on the right.
func build_menu_header(parent: Control) -> void:
	header = UiKit.hbox(parent, 16)
	header.name = "Header"
	brand = UiKit.brand(header)
	game.title_label = brand.get_node("Names/Title")
	game.menu_title = UiKit.wrap(UiKit.label(header, "", "title"))
	game.menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.menu_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	game.menu_title.hide()
	var spacer = Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	links = UiKit.hbox(header, 8)
	links.name = "Links"
	links.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	game.lobby_ui.build_links(links)

func build_menu_actions(parent: Control) -> void:
	game.start_button = UiKit.button(parent, "ИГРАТЬ", "primary", 54)
	game.start_button.name = "StartButton"
	game.start_button.add_theme_font_size_override("font_size", 19)
	game.start_button.pressed.connect(Demo.start_pressed.bind(game))
	game.start_button.hide()
	# Pause: «Как играть» and the VK invitation share one row.
	secondary_row = UiKit.hbox(parent, 10)
	secondary_row.name = "SecondaryActions"
	guide_button = UiKit.expand(UiKit.button(secondary_row, "КАК ИГРАТЬ"))
	guide_button.name = "HowToPlayButton"
	guide_button.pressed.connect(func(): game.how_to_play.open())
	guide_button.hide()
	game.invite_button = UiKit.expand(UiKit.button(secondary_row, "ПРИГЛАСИТЬ ДРУЗЕЙ"))
	game.invite_button.name = "VKInviteFriends"
	game.invite_button.pressed.connect(game._invite_friends)
	game.invite_button.hide()
	game.invite_status = UiKit.wrap(UiKit.label(parent, "", "muted"))
	game.invite_status.hide()
	settings = UiKit.card(parent, UiKit.SURFACE_SUNKEN, Vector2(16, 14))
	settings.name = "Settings"
	var column = UiKit.vbox(settings, 10)
	game.draw_distance_controls = UiKit.vbox(column, 8)
	game.draw_distance_controls.name = "DrawDistanceSettings"
	UiKit.label(game.draw_distance_controls, "ГРАФИКА", "caption")
	var distance_row = UiKit.hbox(game.draw_distance_controls, 8)
	# Listed cheapest first; draw_distance_buttons stays indexed by mode.
	game.draw_distance_buttons.resize(game.draw_distance.LABELS.size())
	for index in game.draw_distance.ORDER:
		var button = UiKit.expand(UiKit.button(distance_row, game.draw_distance.LABELS[index], "toggle", 42))
		button.set_pressed_no_signal(index == game.draw_distance.mode)
		button.pressed.connect(set_draw_distance.bind(index))
		game.draw_distance_buttons[index] = button
	game.lobby_ui.build_audio(column)
	settings.hide()
	game.draw_distance_controls.hide()

# Which parts of the menu window this screen shows.
func update_menu() -> void:
	var main = not game.playing
	var result = game.dead or game.finished
	var pause = game.playing and game.paused and not result
	brand.visible = main and not result
	game.menu_title.visible = not brand.visible
	game.menu_text.visible = game.menu_title.visible and not game.menu_text.text.is_empty()
	links.visible = main or pause
	settings.visible = pause
	guide_button.visible = pause
	secondary_row.visible = guide_button.visible or game.invite_button.visible
	game.draw_distance_controls.visible = pause
	footer.visible = main and not game.mobile_mode
	if game.room != null:
		game.room.ui.caption.visible = not game.mobile_mode
	menu_dim.visible = game.menu.visible and game.playing
	Demo.trim_menu(game, self, pause)
	game.lobby_ui.help_button.visible = links.visible

func layout_menu() -> void:
	if dialog_area == null:
		return
	update_menu()
	var area = dialog_area.size
	var main = not game.playing
	var width = (1100.0 if main and not Demo.active() else 560.0) if not game.mobile_mode else (1100.0 if main else 600.0)
	game.menu.custom_minimum_size.x = width
	var extent = game.menu.get_combined_minimum_size()
	var factor = minf(1.0, minf(maxf(area.x - 24, 1) / extent.x, maxf(area.y - 24, 1) / extent.y))
	game.menu.set_anchors_preset(Control.PRESET_CENTER)
	game.menu.offset_left = -extent.x / 2
	game.menu.offset_right = extent.x / 2
	game.menu.offset_top = -extent.y / 2
	game.menu.offset_bottom = extent.y / 2
	game.menu.pivot_offset = extent / 2
	game.menu.scale = Vector2.ONE * factor
	for modal in dialog_layer.get_children():
		if modal.has_node("Center/Panel") and modal.visible:
			fit_modal(modal)

# Small windows (help, about, how to play) are centred in the safe area and
# scaled down only when they do not fit it.
func fit_modal(modal: Control) -> void:
	var center: Control = modal.get_node("Center")
	var dialog: Control = center.get_node("Panel")
	center.set_anchors_preset(Control.PRESET_TOP_LEFT)
	center.position = dialog_area.position
	center.size = dialog_area.size
	var extent = dialog.get_combined_minimum_size()
	dialog.pivot_offset = extent / 2
	dialog.scale = Vector2.ONE * minf(1.0, minf(maxf(dialog_area.size.x - 24, 1) / extent.x, maxf(dialog_area.size.y - 24, 1) / extent.y))

func update_fps_counter(delta: float) -> void:
	# Auto quality: a slow machine steps the graphics down while driving.
	if game.playing and not game.paused and game.stage != null:
		var message: String = game.draw_distance.watch(delta)
		if message != "":
			game.draw_distance.apply(game.stage)
			update_draw_distance_buttons()
			toast(message)
	game.fps_clock += delta
	if game.fps_clock < 0.5 or game.fps_label == null:
		return
	game.fps_clock = fmod(game.fps_clock, 0.5)
	var fps = Engine.get_frames_per_second()
	if fps > 0:
		set_hud_text(game.fps_label, "v%s · %d FPS" % [ProjectSettings.get_setting("application/config/version"), fps])

func show_consumption_warning(kind: String) -> void:
	game.consumption_warning_text.text = "Употребление алкоголя вредит здоровью. Не управляйте транспортом после употребления." if kind == "beer" else "Употребление неизвестных и ядовитых грибов может привести к тяжёлому отравлению и смерти. Не ешьте грибы, в безопасности которых не уверены."
	game.consumption_warning_time = 8.0
	game.consumption_warning.show()

func toast(message: String) -> void:
	message = Loc.t(message)
	if game.mobile_mode:
		var labels = {"Space —": Loc.t("Тормоз —"), "F —": Loc.t("Действие —"), "Z —": Loc.t("Стол —"), "C —": Loc.t("Стулья —"), "G —": Loc.t("Мангал —"), "X —": Loc.t("Есть —"), "R —": Loc.t("Заезды —"), "— T": Loc.t("— Трос"), ": E.": Loc.t(": Выйти."), Loc.t("нажми X"): Loc.t("нажми Есть"), Loc.t("Удерживай T"): Loc.t("Удерживай Трос")}
		for key in labels:
			message = message.replace(key, labels[key])
	if game.toast_label != null:
		game.toast_label.text = message
		game.toast_label.visible = not game.mobile_mode
		game.toast_time = 5

func set_hud_text(label: Label, value: String) -> void:
	if label.text != value:
		label.text = value

func update_hud() -> void:
	# Resolve once after camera/world movement; actions still resolve a fresh target.
	var target = game.interaction.current()
	game.hud_target = target
	game.hud_target_frame = Engine.get_process_frames()
	game.crosshair.visible = game.playing and not game.in_car and not game.paused and not game.dead and not game.finished and game.placement_kind == ""
	set_hud_text(game.crosshair, "+" if not target.is_empty() else "·")
	var now = Time.get_ticks_msec()
	if game.minimap.is_visible_in_tree() and now >= game.minimap_redraw_at:
		game.minimap.queue_redraw()
		game.minimap_redraw_at = now + 100
	var near_tow = game.nearby_tow_target() if game.tow_target == null else false
	var near_prop = not game.in_car and game.movable_props.nearby()
	var injury = game.injuries.hud_line()
	var remaining_items = game.packing.remaining() if game.packing.active() else -1
	var bag = game.foraging.stock() if not game.in_car else {}
	var pot = game.camp_cooking.pot != null
	var state: Array = [game.mobile_mode, game.in_car, game.playing, game.paused, game.dead, game.finished,
		int(absf(game.speed) * 3.6), int(game.condition),
		game.stage.road_distance(game.car.position) > 4 if game.in_car and not game.mobile_mode else false,
		game.course.phase, game.course.pass_index, game.course.zero_index,
		ceili(game.course.remaining) if game.course.phase in ["countdown", "intermission"] else 0,
		int(game.elapsed) if not game.mobile_mode else 0, game.camp != null, game.has_chairs, game.eaten, game.passed, game.helped, game.beers,
		game.camp_grill.phase(), int(game.camp_grill.progress() * 100),
		game.cooking, game.camp_grill.servings, game.drink_time >= 0, game.drink_time >= 1.25, game.eat_time >= 0, game.eat_kind,
		game.tow_target != null, ceili(game.tow_distance), game.recovery_helpers, near_tow, near_prop, game.crews.car_towed, injury,
		remaining_items, game.seated, game.stage.variant, bag.get("mushrooms", 0), bag.get("berries", 0),
		game.foraging.can_eat("berries"), pot, game.camp_cooking.phase if pot else "",
		game.camp_cooking.servings if pot else 0,
		int(game.camp_cooking.cook_time / game.camp_cooking.COOK_SECONDS * 100) if pot else 0,
		int(game.camp_cooking.cook_time / 45 * 100) if pot and game.mobile_mode else 0,
		target.get("label", ""), game.toast_label.text if game.mobile_mode and game.toast_time > 0 else "",
		game.toast_time > 0 if game.mobile_mode else false, game.sober_remaining if game.beers >= 30 else 0, game.rides.hud_state()]
	if state == game.hud_state:
		return
	game.hud_state = state
	game.hud_revision += 1
	var course_text = ""
	var quest_text = ""
	var status_text = ""
	var info_text = ""
	var hint_text = ""
	game.sobriety_panel.visible = game.beers >= 30 and game.playing and not game.dead and not game.finished
	if game.sobriety_panel.visible:
		var seconds = ceili(game.sober_remaining if game.sober_remaining > 0 else game.SOBER_SECONDS)
		set_hud_text(game.sobriety_label, Loc.t("ПРОТРЕЗВЛЕНИЕ · ВСТАНЕШЬ ЧЕРЕЗ %02d:%02d") % [seconds / 60, seconds % 60])
		game.sobriety_bar.value = game.SOBER_SECONDS - (game.sober_remaining if game.sober_remaining > 0 else game.SOBER_SECONDS)
	course_text = game.course.caption()
	quest_text = Loc.t("%s Выбрать место для лагеря\n%s Разложить стол\n%s Поставить стулья\n%s Пожарить и съесть шашлык\n%s Посмотреть %d экипажей") % ["[x]" if game.camp != null else "[ ]", "[x]" if game.camp != null else "[ ]", "[x]" if game.has_chairs else "[ ]", "[x]" if game.eaten else "[ ]", "[x]" if game.passed >= game.RALLY_CREW_LIMIT else "[ ]", game.RALLY_CREW_LIMIT]
	if game.packing.active():
		quest_text = Loc.t("Оба прохода завершены\nВернуть вещи в багажники: осталось %d\nБагажник открывается при подходе\nF — взять предмет / вернуть коробку\nЗатем все садятся в машины, свои или к друзьям") % remaining_items
	status_text = Loc.t("ПРОХОД %d/2 · ЭКИПАЖИ %d/%d · ПОМОЩЬ %d\nВЫЕЗД %02d:%02d") % [game.course.pass_index, game.passed, game.RALLY_CREW_LIMIT, game.helped, int(game.elapsed) / 60, int(game.elapsed) % 60]
	if game.rides.riding():
		info_text = Loc.t("ПАССАЖИР    ·    МАШИНА: %s    ·    %02d КМ/Ч") % [game.rides.name_of(game.rides.ride).to_upper(), int(absf(game.rides.speed()) * 3.6)]
		hint_text = Loc.t("Мышь — смотреть   ·   F — выйти, когда машина стоит")
	elif game.in_car:
		info_text = Loc.t("%02d КМ/Ч    ·    ЛЕГКОВУШКА %d%%    ·    %s") % [int(absf(game.speed) * 3.6), int(game.condition), Loc.t("ОБОЧИНА") if game.stage.road_distance(game.car.position) > 4 else Loc.t("ГРАВИЙ / КОЛЕЯ")]
		hint_text = Loc.t("WASD / стрелки — газ и руль   ·   Space — тормоз   ·   F — выйти   ·   Home — вернуть на СУ")
		if game.rides.hitch_candidate() != "" and game.rides.hitch == "":
			hint_text += Loc.t("   ·   T — взять друга на трос")
		if game.condition <= 0:
			info_text = Loc.t("МАШИНА СЛОМАНА    ·    САДИСЬ К ДРУГУ ИЛИ ЖДИ ТРОС")
	else:
		info_text = Loc.t("ЗРИТЕЛЬ    ·    %s · ШАМПУРЫ %d/10    ·    %s") % [game.camp_grill.status(false), game.camp_grill.servings, game.course.caption()]
		hint_text = Loc.t("WASD — идти   ·   Shift — бег   ·   Space — прыжок   ·   мышь — смотреть   ·   F — действие   ·   Z — стол   ·   C — стулья   ·   G — мангал   ·   R — статус СУ")
		if game.drink_time >= 0:
			info_text = Loc.t("ОТКРЫВАЕМ БАНКУ") if game.drink_time < 1.25 else Loc.t("ЗА ХОРОШИЙ ВЫЕЗД!")
		if game.eat_time >= 0:
			info_text = Loc.t("ЕДИМ ПЛОВ") if game.eat_kind == "plov" else (Loc.t("ЕДИМ ЯГОДЫ") if game.eat_kind == "berries" else (Loc.t("ЕДИМ ГРИБЫ") if game.eat_kind == "mushroom" else Loc.t("ЕДИМ ШАШЛЫК")))
		if game.beers >= 30:
			info_text = Loc.t("ТЫ ЛЕЖИШЬ · ОТДОХНИ ДО ВОССТАНОВЛЕНИЯ")
	if game.crews.car_towed and game.tow_target == null:
		info_text = Loc.t("ТВОЮ МАШИНУ ТЯНУТ НА ТРОСЕ")
	if game.tow_target != null:
		info_text = tow_text()
	if injury != "":
		info_text = injury
		if game.injuries.down:
			hint_text = Loc.t("Лежи и жди скорую · мышь — осмотреться")
	elif near_prop:
		hint_text += Loc.t("   ·   Удерживай T и иди — тащить предмет")
	elif near_tow:
		hint_text += Loc.t("   ·   T — тянуть тросом в любую сторону · иди на машину — толкать")
	if not game.in_car:
		status_text += Loc.t("\nГРИБЫ %d · %s %d") % [bag.mushrooms, Loc.t(StageRegistry.value(game.stage.variant, "berries_hud")), bag.berries]
		if not target.is_empty():
			hint_text = "F — " + target.label + ("" if game.packing.active() else Loc.t("   ·   Z/C/G/V — поставить предмет"))
		elif game.seated:
			hint_text = Loc.t("F — встать со стула")
		if game.foraging.can_eat("berries"):
			hint_text += Loc.t(" · K — съесть ягоды")
	if game.camp_cooking.pot != null:
		status_text += Loc.t("\nПЛОВ %s · %d/10") % [(Loc.t("ГОТОВ") if game.camp_cooking.phase == "ready" else (Loc.t("ГОТОВИМ %d%%") % int(game.camp_cooking.cook_time / game.camp_cooking.COOK_SECONDS * 100) if game.camp_cooking.phase == "cooking" else Loc.t("КАЗАН ПУСТ"))), game.camp_cooking.servings]
	if game.packing.active() and remaining_items == 0:
		hint_text = Loc.t("Лагерь собран. Езжай в парк сервиса на старте или финише СУ; ждём всех друзей.") if game.in_car else Loc.t("Лагерь собран. Садись в машину, свою или к другу (F), и езжай в парк сервиса.")
	if game.mobile_mode:
		course_text = game.course.short_caption()
		if injury != "" or game.crews.car_towed or game.tow_target != null:
			info_text = info_text.replace(Loc.t("УДЕРЖИВАЙ T"), Loc.t("УДЕРЖИВАЙ ТРОС")).replace(Loc.t("T — ОТЦЕПИТЬ"), Loc.t("«ТРОС» — ОТЦЕПИТЬ"))
		elif game.rides.riding():
			info_text = Loc.t("ПАССАЖИР · %02d КМ/Ч") % int(absf(game.rides.speed()) * 3.6)
		elif game.in_car:
			info_text = Loc.t("%02d КМ/Ч · МАШИНА %d%%") % [int(absf(game.speed) * 3.6), int(game.condition)] if game.condition > 0 else Loc.t("МАШИНА СЛОМАНА · САДИСЬ К ДРУГУ")
		elif game.drink_time < 0 and game.eat_time < 0 and game.beers < 30:
			if game.packing.active():
				info_text = Loc.t("ВЕРНУТЬ ВЕЩИ В БАГАЖНИК · ОСТАЛОСЬ %d") % remaining_items
			else:
				info_text = "%s · %d/10" % [game.camp_grill.status(true), game.camp_grill.servings]
				if game.camp_cooking.pot != null:
					info_text += Loc.t(" · ПЛОВ %d/10") % game.camp_cooking.servings if game.camp_cooking.phase == "ready" else (Loc.t(" · ПЛОВ %d%%") % int(game.camp_cooking.cook_time / 45 * 100) if game.camp_cooking.phase == "cooking" else Loc.t(" · КАЗАН ПУСТ"))
		else:
			info_text = info_text.replace(Loc.t("УДЕРЖИВАЙ T"), Loc.t("УДЕРЖИВАЙ ТРОС"))
		if game.toast_time > 0:
			info_text += "\n" + game.toast_label.text
		elif not game.in_car and not target.is_empty():
			info_text += "\n" + target.label
	set_hud_text(game.course_label, course_text)
	set_hud_text(game.quest_label, quest_text)
	set_hud_text(game.status_label, status_text)
	set_hud_text(game.info_label, info_text)
	set_hud_text(game.hint_label, hint_text)

# The rope the local player holds: how far the crew still has to the road, or
func tow_text() -> String:
	var helpers = Loc.t(" · ВМЕСТЕ: %d") % game.recovery_helpers if game.recovery_helpers > 1 else ""
	if game.rides.hitch != "" and game.tow_target != game.car:
		return Loc.t("%02d КМ/Ч · ТЯНЕМ МАШИНУ ДРУГА НА ТРОСЕ   ·   T — ОТЦЕПИТЬ") % int(absf(game.speed) * 3.6)
	if game.tow_distance < 0:
		var whose = Loc.t("СВОЮ МАШИНУ") if game.tow_target == game.car else Loc.t("МАШИНУ ДРУГА")
		return Loc.t("ТЯНЕМ %s%s   ·   УДЕРЖИВАЙ T") % [whose, helpers]
	return Loc.t("ВЫТАСКИВАЕМ ЭКИПАЖ · ДО ДОРОГИ %d М%s   ·   УДЕРЖИВАЙ T") % [ceili(game.tow_distance), helpers]

func set_paused(value: bool) -> void:
	game.paused = value
	game.menu.visible = value
	game.menu_title.text = "Пауза"
	game.menu_text.text = "Ралли, мангал и таймеры остановлены. Продолжи выезд или вернись в главное меню." if game.room.is_authority() else "Пауза только у тебя: остальные фанаты продолжают выезд."
	game.start_button.text = "ПРОДОЛЖИТЬ"
	update_invite_button()
	layout_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value or game.mobile_mode else Input.MOUSE_MODE_CAPTURED

func show_result(title: String, body: String) -> void:
	game.mushroom_effect.clear()
	game.sobriety_panel.hide()
	game.cancel_placement()
	game._cancel_drink()
	game._cancel_eat()
	game.menu.show()
	update_invite_button()
	game.menu_title.text = title
	game.menu_text.text = body
	game.start_button.text = "НОВЫЙ ВЫЕЗД"
	layout_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.soundscape.vehicles.silence()
	game.fire_audio.stop()

func die(reason: String) -> void:
	game.dead = true
	show_result(Loc.t("Выезд окончен"), reason + Loc.t("\n\nЭкипажи: %d  ·  Помощь тросом: %d\nШашлык: %s") % [game.passed, game.helped, Loc.t("съеден") if game.eaten else Loc.t("не съеден")])

func enable_mobile() -> void:
	if game.mobile_mode:
		return
	game.mobile_mode = true
	game.draw_distance.apply_device_default(true)
	game.draw_distance.apply(game.stage)
	update_draw_distance_buttons()
	game.get_window().content_scale_size = Vector2i(960, 540)
	game.get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	print("[RFM] Мобильный интерфейс: масштаб окна готов")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.title_label.text = "Rally Fans Simulator"
	compact_hud()
	print("[RFM] Мобильный интерфейс: панели готовы")
	var layer = CanvasLayer.new()
	layer.layer = 10
	game.add_child(layer)
	game.mobile_controls = preload("res://scripts/ui/mobile_controls.gd").new()
	game.mobile_controls.game = game
	layer.add_child(game.mobile_controls)
	print("[RFM] Мобильный интерфейс: контроллы готовы")

# Phone layout: sticks own the bottom corners and the action buttons sit above
# the right stick (mobile_controls.gd), so cards stay small and out of the way.
# These labels start empty; wrapping is calculated on draw rather than before
# the Web text server shapes them.
func compact_hud() -> void:
	game.fps_label.hide()
	game.stage_caption.hide()
	game.course_label.add_theme_font_size_override("font_size", 15)
	game.course_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.custom_minimum_size.x = 280
	game.mobile_top.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.HUD, Vector2(14, 8)))
	game.mobile_top.position = Vector2(24, 24)
	game.mobile_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	game.mobile_bottom.offset_left = 180
	game.mobile_bottom.offset_right = -180
	game.mobile_bottom.offset_top = -76
	game.mobile_bottom.offset_bottom = -20
	game.mobile_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	game.mobile_bottom.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.HUD, Vector2(14, 8)))
	game.info_label.add_theme_font_size_override("font_size", 15)
	game.info_label.max_lines_visible = 3
	game.info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.hint_label.hide()
	game.quest_label.hide()
	plan_title.hide()
	game.mobile_sidebar.offset_left = -268
	game.mobile_sidebar.offset_right = -24
	game.mobile_sidebar.offset_top = 96
	game.minimap.custom_minimum_size = Vector2(212, 120)
	game.consumption_warning.offset_left = -270
	game.consumption_warning.offset_right = 270
	game.consumption_warning.offset_top = 96
	game.sobriety_panel.anchor_left = 0.2
	game.sobriety_panel.anchor_right = 0.8
	game.sobriety_panel.offset_top = 96
	game.sobriety_panel.offset_bottom = 180
	game.menu_content.add_theme_constant_override("separation", 10)
	brand.get_node("Logo").custom_minimum_size = Vector2.ONE * 44

func apply_mobile_safe_rect(rect: Rect2) -> void:
	if rect == game.mobile_safe_rect:
		return
	game.mobile_safe_rect = rect
	game.mobile_controls.reset_input()
	# Insets move anchors; they must never shrink gameplay buttons or text.
	for control in [game.mobile_ui, game.mobile_controls, dialog_area]:
		control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		control.position = rect.position
		control.scale = Vector2.ONE
		control.size = rect.size
	# The world still fills the canvas and aiming stays at the camera centre.
	game.crosshair.position = game.get_viewport().get_visible_rect().size / 2 - rect.position - game.crosshair.size / 2
	layout_menu()

func fit_mobile_dialogs() -> void:
	layout_menu()

func update_mobile_safe_area(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	if game.mobile_safe_http == null:
		game.mobile_safe_http = HTTPRequest.new()
		game.mobile_safe_http.accept_gzip = false
		game.mobile_safe_http.timeout = 2.0
		game.mobile_safe_http.body_size_limit = 1024
		game.add_child(game.mobile_safe_http)
		game.mobile_safe_http.request_completed.connect(mobile_safe_response)
	game.mobile_safe_timer -= delta
	if game.mobile_safe_timer > 0.0 or game.mobile_safe_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	game.mobile_safe_timer = 0.25
	# Like profile bootstrap, this is intercepted locally by the browser shell.
	# The minimal engine has neither eval nor JavaScript object interfaces.
	game.mobile_safe_http.request(game.room.transport.server + "/__rally_viewport")

func mobile_safe_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.has_all(["width", "height", "left", "right", "top", "bottom"]):
		return
	var lifecycle = data.get("lifecycle", {})
	if lifecycle is Dictionary:
		var sequence = int(lifecycle.get("pause_sequence", 0))
		if sequence > game.lifecycle_pause_sequence or lifecycle.get("hidden", false):
			game.lifecycle_pause_sequence = sequence
			if game.playing and not game.dead and not game.finished and game.safety_gate == null and not game.how_to_play.is_open():
				game._set_paused(true)
	var extent = game.get_viewport().get_visible_rect().size
	var ratio = extent / Vector2(maxf(float(data.width), 1.0), maxf(float(data.height), 1.0))
	var origin = Vector2(float(data.left), float(data.top)) * ratio
	var end = extent - Vector2(float(data.right), float(data.bottom)) * ratio
	game.safety_safe_insets = Vector4(origin.x, origin.y, extent.x-end.x, extent.y-end.y)
	if game.safety_gate != null and is_instance_valid(game.safety_gate):
		game.safety_gate.set_safe_insets(game.safety_safe_insets)
	if not game.mobile_mode:
		return
	apply_mobile_safe_rect(Rect2(origin, end - origin))

func update_invite_button() -> void:
	if game.invite_button == null:
		return
	game.invite_button.visible = game.playing and not game.dead and not game.finished and game.platform_service != null and game.platform_service.profile.get("platform", "") == "vk"
	if game.invite_status != null:
		game.invite_status.visible = game.invite_button.visible and not game.invite_status.text.is_empty()

func set_draw_distance(index: int) -> void:
	game.draw_distance.mode = clampi(index, game.draw_distance.NEAR, game.draw_distance.LOW)
	game.draw_distance.apply(game.stage)
	update_draw_distance_buttons()
	if game.draw_distance.save_settings() != OK:
		push_warning("Не удалось сохранить настройку графики")

func update_draw_distance_buttons() -> void:
	for index in range(game.draw_distance_buttons.size()):
		game.draw_distance_buttons[index].set_pressed_no_signal(index == game.draw_distance.mode)

# Stage entry: «Как играть» comes before the memo on the first VK and every demo entry.
func show_stage_safety_gate() -> void:
	if game.safety_gate != null and is_instance_valid(game.safety_gate):
		return
	game.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game.how_to_play.is_open():
		return
	if (Demo.active() or game.platform_service != null and game.platform_service.profile.get("platform", "") == "vk") and game.how_to_play.open_first_time(Demo.active()):
		layout_menu()
		return
	open_stage_safety_gate()

func open_stage_safety_gate() -> void:
	if game.safety_gate != null and is_instance_valid(game.safety_gate):
		return
	game.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.safety_gate = preload("res://scripts/ui/stage_safety_gate.gd").new()
	game.add_child(game.safety_gate)
	game.safety_gate.set_safe_insets(game.safety_safe_insets)
	game.safety_gate.accepted.connect(accept_stage_safety_gate)

func accept_stage_safety_gate() -> void:
	game.safety_gate = null
	game.paused = false
	game._request_game_mouse_capture()
