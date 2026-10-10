extends RefCounted
# The in-game interface: menu panels, HUD lines, toasts, result screen, FPS,
# mobile safe area, draw distance and invite buttons. The nodes stay on game
# (menu, toast_label, ...) where other scripts and tests use them.
const MiniMap = preload("res://scripts/minimap.gd")
const Props = preload("res://scripts/props.gd")
const Stage = preload("res://scripts/stage.gd")
const StageRegistry = preload("res://scripts/stage_registry.gd")

var game

func panel(color: Color) -> StyleBoxFlat:
	var p = StyleBoxFlat.new()
	p.bg_color = color
	p.set_corner_radius_all(12)
	p.content_margin_left = 20
	p.content_margin_right = 20
	p.content_margin_top = 14
	p.content_margin_bottom = 14
	return p

func label(parent: Node, text: String, font_size: int, color: Color = Color("f2e8d0")) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func build_ui() -> void:
	var canvas = CanvasLayer.new()
	game.add_child(canvas)
	var ui = Control.new()
	game.mobile_ui = ui
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.crosshair = label(ui, "·", 24, Color("fff0cb"))
	game.crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game.crosshair.offset_left = -16
	game.crosshair.offset_right = 16
	game.crosshair.offset_top = -16
	game.crosshair.offset_bottom = 16
	game.crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.crosshair.hide()
	var top = PanelContainer.new()
	game.mobile_top = top
	ui.add_child(top)
	top.position = Vector2(28, 24)
	top.add_theme_stylebox_override("panel", panel(Color("25352be8")))
	var vb = VBoxContainer.new()
	top.add_child(vb)
	game.title_label = label(vb, "Rally Fans Simulator", 22)
	game.stage_caption = label(vb, Stage.STAGES[game.selected_stage], 12, Color("b2bea1"))
	game.fps_label = label(vb, "v%s · — FPS" % ProjectSettings.get_setting("application/config/version"), 12, Color("b2bea1"))
	game.fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.course_label = label(vb, "", 16, Color("ffe4a5"))
	game.course_label.hide()
	var sidebar = PanelContainer.new()
	game.mobile_sidebar = sidebar
	ui.add_child(sidebar)
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	sidebar.offset_left = -332
	sidebar.offset_right = -28
	sidebar.offset_top = 24
	sidebar.offset_bottom = 390
	sidebar.hide()
	game.hud_panels.append(sidebar)
	sidebar.add_theme_stylebox_override("panel", panel(Color("25352be8")))
	var sv = VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	sidebar.add_child(sv)
	label(sv, "ПЛАН НА ВЫЕЗД", 15, Color("e4b56b"))
	game.quest_label = label(sv, "", 16)
	game.minimap = MiniMap.new()
	game.minimap.game = game
	game.minimap.custom_minimum_size = Vector2(264, 205)
	sv.add_child(game.minimap)
	game.status_label = label(sv, "", 13, Color("b2bea1"))
	var bottom = PanelContainer.new()
	game.mobile_bottom = bottom
	ui.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 28
	bottom.offset_right = -28
	bottom.offset_top = -136
	bottom.offset_bottom = -24
	bottom.hide()
	game.hud_panels.append(bottom)
	bottom.add_theme_stylebox_override("panel", panel(Color("25352bf2")))
	var bv = VBoxContainer.new()
	bottom.add_child(bv)
	game.info_label = label(bv, "", 24, Color("e4b56b"))
	game.hint_label = label(bv, "", 15)
	game.hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.toast_label = label(ui, "", 21, Color("fff0cb"))
	game.toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	game.toast_label.offset_left = -530
	game.toast_label.offset_right = 530
	game.toast_label.offset_top = -204
	game.toast_label.offset_bottom = -150
	game.toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.toast_label.add_theme_color_override("font_shadow_color", Color("182820"))
	game.toast_label.add_theme_constant_override("shadow_offset_x", 2)
	game.toast_label.add_theme_constant_override("shadow_offset_y", 2)
	game.sobriety_panel = PanelContainer.new()
	ui.add_child(game.sobriety_panel)
	game.sobriety_panel.anchor_left = 0.25
	game.sobriety_panel.anchor_right = 0.75
	game.sobriety_panel.offset_top = 150
	game.sobriety_panel.offset_bottom = 245
	game.sobriety_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sobriety_panel.add_theme_stylebox_override("panel", panel(Color("25352bf2")))
	var recovery_box = VBoxContainer.new()
	recovery_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sobriety_panel.add_child(recovery_box)
	game.sobriety_label = label(recovery_box, "", 22, Color("fff0cb"))
	game.sobriety_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.sobriety_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.sobriety_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sobriety_bar = ProgressBar.new()
	game.sobriety_bar.max_value = game.SOBER_SECONDS
	game.sobriety_bar.custom_minimum_size.y = 24
	game.sobriety_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var recovery_fill = StyleBoxFlat.new()
	recovery_fill.bg_color = Color("ee531b")
	game.sobriety_bar.add_theme_stylebox_override("fill", recovery_fill)
	recovery_box.add_child(game.sobriety_bar)
	game.sobriety_panel.hide()
	game.consumption_warning = PanelContainer.new()
	game.consumption_warning.name = "ConsumptionWarning"
	ui.add_child(game.consumption_warning)
	game.consumption_warning.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	game.consumption_warning.offset_left = 24
	game.consumption_warning.offset_right = -24
	game.consumption_warning.offset_top = -120
	game.consumption_warning.offset_bottom = -12
	game.consumption_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.consumption_warning.add_theme_stylebox_override("panel", panel(Color("23342b")))
	game.consumption_warning_text = label(game.consumption_warning, "", 18, Color("ffe4a5"))
	game.consumption_warning_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.consumption_warning_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game.consumption_warning_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.consumption_warning.hide()
	game.menu = PanelContainer.new()
	ui.add_child(game.menu)
	game.menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game.menu.offset_left = -350
	game.menu.offset_right = 350
	game.menu.offset_top = -270
	game.menu.offset_bottom = 270
	game.menu.add_theme_stylebox_override("panel", panel(Color("23342bf5")))
	var mv = VBoxContainer.new()
	game.menu_content = mv
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_theme_constant_override("separation", 12)
	game.menu.add_child(mv)
	label(mv, "ПЕРЕВАЛ. РАЛЛИ. ШАШЛЫК.", 14, Color("dfb270"))
	game.menu_title = label(mv, "", 34)
	game.menu_text = label(mv, "", 17)
	game.menu_title.hide()
	game.menu_text.hide()
	game.draw_distance_controls = VBoxContainer.new()
	game.draw_distance_controls.name = "DrawDistanceSettings"
	mv.add_child(game.draw_distance_controls)
	label(game.draw_distance_controls, "Дальность прорисовки", 17, Color("dfb270"))
	var distance_row = HBoxContainer.new()
	distance_row.add_theme_constant_override("separation", 8)
	game.draw_distance_controls.add_child(distance_row)
	for index in range(game.draw_distance.LABELS.size()):
		var button = Button.new()
		button.text = game.draw_distance.LABELS[index]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 17)
		button.set_pressed_no_signal(index == game.draw_distance.mode)
		button.pressed.connect(set_draw_distance.bind(index))
		distance_row.add_child(button)
		game.draw_distance_buttons.append(button)
	game.draw_distance_controls.hide()
	game.selection_controls = VBoxContainer.new()
	game.selection_controls.add_theme_constant_override("separation", 8)
	mv.add_child(game.selection_controls)
	game.lobby_ui = preload("res://scripts/lobby_ui.gd").new()
	game.lobby_ui.game = game
	game.add_child(game.lobby_ui)
	var cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	game.selection_controls.add_child(cards)
	for kind in ["МАШИНА", "СПЕЦУЧАСТОК"]:
		var card = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		label(card, kind, 14, Color("dfb270"))
		game.lobby_ui.add_preview(card, kind)
		var row = HBoxContainer.new()
		card.add_child(row)
		var choice = preload("res://scripts/menu_choice.gd").new()
		choice.custom_minimum_size.y = 40
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.add_theme_font_size_override("font_size", 18)
		row.add_child(choice)
		if kind == "МАШИНА":
			game.car_choice = choice
			for model in Props.PLAYER_MODELS:
				choice.add_item(model.name)
			choice.item_selected.connect(game.select_player_car)
		else:
			game.stage_choice = choice
			for title in Stage.STAGES:
				choice.add_item(title.get_slice("·", 0).strip_edges())
			choice.item_selected.connect(game.select_stage)
	game.stage_choice.tooltip_text = "В комнате СУ выбирает создатель. Все участники играют на одной трассе."
	game.start_button = Button.new()
	game.start_button.text = "ПОЕХАЛИ"
	game.start_button.custom_minimum_size.y = 54
	game.start_button.add_theme_font_size_override("font_size", 20)
	game.start_button.add_theme_color_override("font_color", Color("25352b"))
	game.start_button.add_theme_stylebox_override("normal", panel(Color("e3b16b")))
	game.start_button.add_theme_stylebox_override("hover", panel(Color("f1c687")))
	game.start_button.add_theme_stylebox_override("pressed", panel(Color("c78f4a")))
	game.start_button.pressed.connect(game._menu_action)
	mv.add_child(game.start_button)
	game.start_button.hide()
	game.invite_button = Button.new()
	game.invite_button.text = "ПРИГЛАСИТЬ ДРУЗЕЙ"
	game.invite_button.name = "VKInviteFriends"
	game.invite_button.custom_minimum_size.y = 48
	game.invite_button.add_theme_font_size_override("font_size", 19)
	game.invite_button.add_theme_stylebox_override("normal", panel(Color("38516a")))
	game.invite_button.add_theme_stylebox_override("hover", panel(Color("4c6888")))
	game.invite_button.pressed.connect(game._invite_friends)
	mv.add_child(game.invite_button)
	game.invite_button.hide()
	game.invite_status = label(mv, "", 14, Color("dce7ee"))
	game.invite_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.invite_status.hide()
	game.lobby_ui.finish(mv)

func update_fps_counter(delta: float) -> void:
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
	if game.mobile_mode:
		var labels = {"Space —": "Тормоз —", "F —": "Действие —", "Z —": "Стол —", "C —": "Стулья —", "G —": "Мангал —", "X —": "Есть —", "R —": "Заезды —", "— T": "— Трос", ": E.": ": Выйти.", "нажми X": "нажми Есть", "Удерживай T": "Удерживай Трос"}
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
	var remaining_items = game.packing.remaining() if game.packing.active() else -1
	var bag = game.foraging.stock() if not game.in_car else {}
	var pot = game.camp_cooking.pot != null
	var state: Array = [game.mobile_mode, game.in_car, game.playing, game.paused, game.dead, game.finished,
		int(absf(game.speed) * 3.6), int(game.condition),
		game.stage.road_distance(game.car.position) > 4 if game.in_car and not game.mobile_mode else false,
		game.course.phase, game.course.pass_index, game.course.zero_index,
		ceili(game.course.remaining) if game.course.phase in ["countdown", "intermission"] else 0,
		int(game.elapsed) if not game.mobile_mode else 0, game.camp != null, game.has_chairs, game.eaten, game.passed, game.helped, game.beers,
		game.cook_time >= 35, int(game.cook_time / 35 * 100) if game.cooking and game.cook_time < 35 else 0,
		game.cooking, game.grill_servings, game.drink_time >= 0, game.drink_time >= 1.25, game.eat_time >= 0, game.eat_kind,
		game.tow_target != null, ceili(game.tow_distance), game.recovery_helpers, near_tow, game.crews.car_towed,
		remaining_items, game.seated, game.stage.variant, bag.get("mushrooms", 0), bag.get("berries", 0),
		game.foraging.can_eat("berries"), pot, game.camp_cooking.phase if pot else "",
		game.camp_cooking.servings if pot else 0,
		int(game.camp_cooking.cook_time / game.camp_cooking.COOK_SECONDS * 100) if pot else 0,
		int(game.camp_cooking.cook_time / 45 * 100) if pot and game.mobile_mode else 0,
		target.get("label", ""), game.toast_label.text if game.mobile_mode and game.toast_time > 0 else "",
		game.toast_time > 0 if game.mobile_mode else false, game.sober_remaining if game.beers >= 30 else 0]
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
		set_hud_text(game.sobriety_label, "ПРОТРЕЗВЛЕНИЕ · ВСТАНЕШЬ ЧЕРЕЗ %02d:%02d" % [seconds / 60, seconds % 60])
		game.sobriety_bar.value = game.SOBER_SECONDS - (game.sober_remaining if game.sober_remaining > 0 else game.SOBER_SECONDS)
	course_text = game.course.caption()
	quest_text = "%s Выбрать место для лагеря\n%s Разложить стол\n%s Поставить стулья\n%s Пожарить и съесть шашлык\n%s Посмотреть %d экипажей" % ["[x]" if game.camp != null else "[ ]", "[x]" if game.camp != null else "[ ]", "[x]" if game.has_chairs else "[ ]", "[x]" if game.eaten else "[ ]", "[x]" if game.passed >= game.RALLY_CREW_LIMIT else "[ ]", game.RALLY_CREW_LIMIT]
	if game.packing.active():
		quest_text = "Оба прохода завершены\nВернуть вещи в багажники: осталось %d\nБагажник открывается при подходе\nF — взять предмет / вернуть коробку\nЗатем все возвращаются в свои машины" % remaining_items
	status_text = "ПРОХОД %d/2 · ЭКИПАЖИ %d/%d · ПОМОЩЬ %d\nВЫЕЗД %02d:%02d" % [game.course.pass_index, game.passed, game.RALLY_CREW_LIMIT, game.helped, int(game.elapsed) / 60, int(game.elapsed) % 60]
	if game.in_car:
		info_text = "%02d КМ/Ч    ·    ЛЕГКОВУШКА %d%%    ·    %s" % [int(absf(game.speed) * 3.6), int(game.condition), "ОБОЧИНА" if game.stage.road_distance(game.car.position) > 4 else "ГРАВИЙ / КОЛЕЯ"]
		hint_text = "WASD / стрелки — газ и руль   ·   Space — тормоз   ·   F — выйти   ·   Home — вернуть на СУ"
	else:
		var cook_status = "ШАШЛЫК ГОТОВ" if game.cook_time >= 35 else ("ШАШЛЫК %d%%" % int(game.cook_time / 35 * 100) if game.cooking else "МАНГАЛ НЕ РАЗОЖЖЁН")
		info_text = "ЗРИТЕЛЬ    ·    %s · ШАМПУРЫ %d/10    ·    %s" % [cook_status, game.grill_servings, game.course.caption()]
		hint_text = "WASD — идти   ·   Shift — бег   ·   Space — прыжок   ·   мышь — смотреть   ·   F — действие   ·   Z — стол   ·   C — стулья   ·   G — мангал   ·   R — статус СУ"
		if game.drink_time >= 0:
			info_text = "ОТКРЫВАЕМ БАНКУ" if game.drink_time < 1.25 else "ЗА ХОРОШИЙ ВЫЕЗД!"
		if game.eat_time >= 0:
			info_text = "ЕДИМ ПЛОВ" if game.eat_kind == "plov" else ("ЕДИМ ЯГОДЫ" if game.eat_kind == "berries" else ("ЕДИМ ГРИБЫ" if game.eat_kind == "mushroom" else "ЕДИМ ШАШЛЫК"))
		if game.beers >= 30:
			info_text = "ТЫ ЛЕЖИШЬ · ОТДОХНИ ДО ВОССТАНОВЛЕНИЯ"
	if game.crews.car_towed and game.tow_target == null:
		info_text = "ТВОЮ МАШИНУ ТЯНУТ НА ТРОСЕ"
	if game.tow_target != null:
		info_text = tow_text()
	elif near_tow:
		hint_text += "   ·   T — тянуть тросом в любую сторону · иди на машину — толкать"
	if not game.in_car:
		status_text += "\nГРИБЫ %d · %s %d" % [bag.mushrooms, StageRegistry.value(game.stage.variant, "berries_hud"), bag.berries]
		if not target.is_empty():
			hint_text = "F — " + target.label + ("" if game.packing.active() else "   ·   Z/C/G/V — поставить предмет")
		elif game.seated:
			hint_text = "F — встать со стула"
		if game.foraging.can_eat("berries"):
			hint_text += " · K — съесть ягоды"
	if game.camp_cooking.pot != null:
		status_text += "\nПЛОВ %s · %d/10" % [("ГОТОВ" if game.camp_cooking.phase == "ready" else ("ГОТОВИМ %d%%" % int(game.camp_cooking.cook_time / game.camp_cooking.COOK_SECONDS * 100) if game.camp_cooking.phase == "cooking" else "КАЗАН ПУСТ")), game.camp_cooking.servings]
	if game.packing.active() and remaining_items == 0:
		hint_text = "Лагерь собран. Садитесь в свои машины через F; ждём всех друзей." if game.in_car else "Лагерь собран. Подойди к своей машине и нажми F."
	if game.mobile_mode:
		course_text = game.course.caption().replace("ПРОХОД ", "СУ ").replace(" · ПРЯМО", "").replace(" · ОБРАТНО", "").replace("ДО ОТКРЫТИЯ СУ", "СТАРТ ЧЕРЕЗ")
		if game.crews.car_towed or game.tow_target != null:
			info_text = info_text.replace("УДЕРЖИВАЙ T", "УДЕРЖИВАЙ ТРОС")
		elif game.in_car:
			info_text = "%02d КМ/Ч · МАШИНА %d%%" % [int(absf(game.speed) * 3.6), int(game.condition)]
		elif game.drink_time < 0 and game.eat_time < 0 and game.beers < 30:
			if game.packing.active():
				info_text = "ВЕРНУТЬ ВЕЩИ В БАГАЖНИК · ОСТАЛОСЬ %d" % remaining_items
			else:
				var cook_status = "ГОТОВ" if game.cook_time >= 35 else ("%d%%" % int(game.cook_time / 35 * 100) if game.cooking else "НЕТ ОГНЯ")
				info_text = "ШАШЛЫК %s · %d/10" % [cook_status, game.grill_servings]
				if game.camp_cooking.pot != null:
					info_text += " · ПЛОВ %d/10" % game.camp_cooking.servings if game.camp_cooking.phase == "ready" else (" · ПЛОВ %d%%" % int(game.camp_cooking.cook_time / 45 * 100) if game.camp_cooking.phase == "cooking" else " · КАЗАН ПУСТ")
		else:
			info_text = info_text.replace("УДЕРЖИВАЙ T", "УДЕРЖИВАЙ ТРОС")
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
# whose car is being towed, and how many people help.
func tow_text() -> String:
	var helpers = " · ВМЕСТЕ: %d" % game.recovery_helpers if game.recovery_helpers > 1 else ""
	if game.tow_distance < 0:
		return "ТЯНЕМ МАШИНУ ДРУГА%s   ·   УДЕРЖИВАЙ T" % helpers
	return "ВЫТАСКИВАЕМ ЭКИПАЖ · ДО ДОРОГИ %d М%s   ·   УДЕРЖИВАЙ T" % [ceili(game.tow_distance), helpers]

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.engine_audio.stop()
	game.rally_audio.stop()
	game.fire_audio.stop()

func die(reason: String) -> void:
	game.dead = true
	show_result("Выезд окончен", reason + "\n\nЭкипажи: %d  ·  Помощь тросом: %d\nШашлык: %s" % [game.passed, game.helped, "съеден" if game.eaten else "не съеден"])

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
	game.title_label.hide()
	# These HUD labels start empty. Let wrapping calculate their lines on draw
	# rather than recalculating visible lines before the Web text server shapes them.
	game.course_label.add_theme_font_size_override("font_size", 14)
	game.course_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.mobile_top.get_child(0).get_child(1).hide()
	game.mobile_top.position = Vector2(24, 20)
	game.mobile_top.size = Vector2(360, 0)
	game.mobile_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	game.mobile_bottom.offset_left = 200
	game.mobile_bottom.offset_right = -224
	game.mobile_bottom.offset_top = -148
	game.mobile_bottom.offset_bottom = -24
	game.info_label.add_theme_font_size_override("font_size", 16)
	game.info_label.max_lines_visible = 4
	game.info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.hint_label.hide()
	game.quest_label.hide()
	game.mobile_sidebar.get_child(0).get_child(0).hide()
	game.mobile_sidebar.offset_left = -280
	game.mobile_sidebar.offset_right = -36
	game.mobile_sidebar.offset_top = 96
	game.mobile_sidebar.offset_bottom = 282
	game.minimap.custom_minimum_size = Vector2(204, 110)
	game.toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	game.toast_label.offset_left = 36
	game.toast_label.offset_right = -36
	game.toast_label.offset_top = -330
	game.toast_label.offset_bottom = -265
	game.toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.menu.offset_left = -310
	game.menu.offset_right = 310
	game.menu.offset_top = -195
	game.menu.offset_bottom = 195
	game.menu_content.add_theme_constant_override("separation", 6)
	game.menu_content.get_child(0).hide()
	game.menu_title.add_theme_font_size_override("font_size", 26)
	game.menu_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.menu_text.add_theme_font_size_override("font_size", 18)
	game.menu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.menu_text.text = "Доедь до поляны, разложи лагерь и посмотри ралли. Жарь шашлык, помогай экипажам и береги себя."
	print("[RFM] Мобильный интерфейс: панели готовы")
	var layer = CanvasLayer.new()
	layer.layer = 10
	game.add_child(layer)
	game.mobile_controls = preload("res://scripts/mobile_controls.gd").new()
	game.mobile_controls.game = game
	layer.add_child(game.mobile_controls)
	print("[RFM] Мобильный интерфейс: контроллы готовы")

func apply_mobile_safe_rect(rect: Rect2) -> void:
	if rect == game.mobile_safe_rect:
		return
	game.mobile_safe_rect = rect
	game.mobile_controls.reset_input()
	# Insets move anchors; they must never shrink gameplay buttons or text.
	for control in [game.mobile_ui, game.mobile_controls]:
		control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		control.position = rect.position
		control.scale = Vector2.ONE
		control.size = rect.size
	# The world still fills the canvas and aiming stays at the camera centre.
	game.crosshair.position = game.get_viewport().get_visible_rect().size / 2 - rect.position - game.crosshair.size / 2
	fit_mobile_dialogs()

func fit_mobile_dialogs() -> void:
	if not game.mobile_mode or not game.mobile_safe_rect.has_area():
		return
	for dialog in [game.menu]:
		var minimum = dialog.get_combined_minimum_size()
		var extent = Vector2(maxf(620, minimum.x), maxf(390, minimum.y))
		var factor = minf(1.0, minf((game.mobile_ui.size.x - 24) / extent.x, (game.mobile_ui.size.y - 24) / extent.y))
		dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		dialog.offset_left = -extent.x / 2
		dialog.offset_right = extent.x / 2
		dialog.offset_top = -extent.y / 2
		dialog.offset_bottom = extent.y / 2
		dialog.pivot_offset = extent / 2
		dialog.scale = Vector2.ONE * factor

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
			if game.playing and not game.dead and not game.finished and game.safety_gate == null:
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
	game.draw_distance.mode = clampi(index, game.draw_distance.NEAR, game.draw_distance.FAR)
	game.draw_distance.apply(game.stage)
	update_draw_distance_buttons()
	if game.draw_distance.save_settings() != OK:
		push_warning("Не удалось сохранить дальность прорисовки")

func update_draw_distance_buttons() -> void:
	for index in range(game.draw_distance_buttons.size()):
		game.draw_distance_buttons[index].set_pressed_no_signal(index == game.draw_distance.mode)

func show_stage_safety_gate() -> void:
	if game.safety_gate != null and is_instance_valid(game.safety_gate):
		return
	game.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.safety_gate = preload("res://scripts/stage_safety_gate.gd").new()
	game.add_child(game.safety_gate)
	game.safety_gate.set_safe_insets(game.safety_safe_insets)
	game.safety_gate.accepted.connect(accept_stage_safety_gate)

func accept_stage_safety_gate() -> void:
	game.safety_gate = null
	game.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if game.mobile_mode or game.room.connected and OS.has_feature("web") else Input.MOUSE_MODE_CAPTURED
