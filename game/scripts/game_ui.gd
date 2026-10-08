extends RefCounted
# UI construction and HUD presentation; gameplay does not live here.
var game: Node3D

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
	game.add_child(canvas)
	var ui = Control.new()
	game.mobile_ui = ui
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.crosshair = _label(ui, "·", 24, Color("fff0cb"))
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
	top.add_theme_stylebox_override("panel", _panel(Color("25352be8")))
	var vb = VBoxContainer.new()
	top.add_child(vb)
	game.title_label = _label(vb, "Rally Fans Simulator", 22)
	game.stage_caption = _label(vb, game.Stage.STAGES[game.selected_stage], 12, Color("b2bea1"))
	game.fps_label = _label(vb, "v%s · — FPS" % ProjectSettings.get_setting("application/config/version"), 12, Color("b2bea1"))
	game.fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.course_label = _label(vb, "", 16, Color("ffe4a5"))
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
	sidebar.add_theme_stylebox_override("panel", _panel(Color("25352be8")))
	var sv = VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	sidebar.add_child(sv)
	_label(sv, "ПЛАН НА ВЫЕЗД", 15, Color("e4b56b"))
	game.quest_label = _label(sv, "", 16)
	game.minimap = game.MiniMap.new()
	game.minimap.game = game
	game.minimap.custom_minimum_size = Vector2(264, 205)
	sv.add_child(game.minimap)
	game.status_label = _label(sv, "", 13, Color("b2bea1"))
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
	bottom.add_theme_stylebox_override("panel", _panel(Color("25352bf2")))
	var bv = VBoxContainer.new()
	bottom.add_child(bv)
	game.info_label = _label(bv, "", 24, Color("e4b56b"))
	game.hint_label = _label(bv, "", 15)
	game.hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.toast_label = _label(ui, "", 21, Color("fff0cb"))
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
	game.sobriety_panel.add_theme_stylebox_override("panel", _panel(Color("25352bf2")))
	var recovery_box = VBoxContainer.new()
	recovery_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sobriety_panel.add_child(recovery_box)
	game.sobriety_label = _label(recovery_box, "", 22, Color("fff0cb"))
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
	game.menu = PanelContainer.new()
	ui.add_child(game.menu)
	game.menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game.menu.offset_left = -350
	game.menu.offset_right = 350
	game.menu.offset_top = -270
	game.menu.offset_bottom = 270
	game.menu.add_theme_stylebox_override("panel", _panel(Color("23342bf5")))
	var mv = VBoxContainer.new()
	game.menu_content = mv
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_theme_constant_override("separation", 12)
	game.menu.add_child(mv)
	_label(mv, "ПЕРЕВАЛ. РАЛЛИ. ШАШЛЫК.", 14, Color("dfb270"))
	game.menu_title = _label(mv, "", 34)
	game.menu_text = _label(mv, "", 17)
	game.menu_title.hide()
	game.menu_text.hide()
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
		_label(card, kind, 14, Color("dfb270"))
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
			for model in game.Props.PLAYER_MODELS:
				choice.add_item(model.name)
			choice.item_selected.connect(game.select_player_car)
		else:
			game.stage_choice = choice
			for title in game.Stage.STAGES:
				choice.add_item(title.get_slice("·", 0).strip_edges())
			choice.item_selected.connect(game.select_stage)
	game.stage_choice.tooltip_text = "В комнате СУ выбирает создатель. Все участники играют на одной трассе."
	game.start_button = Button.new()
	game.start_button.text = "ПОЕХАЛИ"
	game.start_button.custom_minimum_size.y = 54
	game.start_button.add_theme_font_size_override("font_size", 20)
	game.start_button.add_theme_color_override("font_color", Color("25352b"))
	game.start_button.add_theme_stylebox_override("normal", _panel(Color("e3b16b")))
	game.start_button.add_theme_stylebox_override("hover", _panel(Color("f1c687")))
	game.start_button.add_theme_stylebox_override("pressed", _panel(Color("c78f4a")))
	game.start_button.pressed.connect(game._menu_action)
	mv.add_child(game.start_button)
	game.start_button.hide()
	game.lobby_ui.finish(mv)

func _set_hud_text(label: Label, value: String) -> void:
	if label.text != value:
		label.text = value

func _update_hud() -> void:
	# Resolve once after camera/world movement; actions still resolve a fresh target.
	var target = game.interaction.current()
	game.hud_target = target
	game.hud_target_frame = Engine.get_process_frames()
	game.crosshair.visible = game.playing and not game.in_car and not game.paused and not game.dead and not game.finished and game.placement_kind == ""
	_set_hud_text(game.crosshair, "+" if not target.is_empty() else "·")
	var now = Time.get_ticks_msec()
	if game.minimap.is_visible_in_tree() and now >= game.minimap_redraw_at:
		game.minimap.queue_redraw()
		game.minimap_redraw_at = now + 100
	var near_tow = game.nearby_tow_racer() if game.tow_target == null else false
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
		game.tow_target != null, int(game.tow_progress * 100), game.recovery_helpers, near_tow,
		remaining_items, game.seated, game.stage.urban, bag.get("mushrooms", 0), bag.get("berries", 0),
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
		_set_hud_text(game.sobriety_label, "ПРОТРЕЗВЛЕНИЕ · ВСТАНЕШЬ ЧЕРЕЗ %02d:%02d" % [seconds / 60, seconds % 60])
		game.sobriety_bar.value = game.SOBER_SECONDS - (game.sober_remaining if game.sober_remaining > 0 else game.SOBER_SECONDS)
	course_text = game.course.caption()
	quest_text = "%s Выбрать место для лагеря\n%s Разложить стол\n%s Поставить стулья\n%s Пожарить и съесть шашлык\n%s Посмотреть %d экипажей" % ["[x]" if game.camp != null else "[ ]", "[x]" if game.camp != null else "[ ]", "[x]" if game.has_chairs else "[ ]", "[x]" if game.eaten else "[ ]", "[x]" if game.passed >= game.RALLY_CREW_LIMIT else "[ ]", game.RALLY_CREW_LIMIT]
	if game.packing.active():
		quest_text = "Оба прохода завершены\nВернуть вещи в багажники: осталось %d\nБагажник открывается при подходе\nF — взять предмет / вернуть коробку\nЗатем все возвращаются в свои машины" % remaining_items
	status_text = "ПРОХОД %d/2 · ЭКИПАЖИ %d/%d · ПОМОЩЬ %d\nПИВО %d · ВЫЕЗД %02d:%02d" % [game.course.pass_index, game.passed, game.RALLY_CREW_LIMIT, game.helped, game.beers, int(game.elapsed) / 60, int(game.elapsed) % 60]
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
		if game.tow_target != null:
			info_text = "ПОМОЩЬ %d%% · УЧАСТНИКОВ %d" % [int(game.tow_progress * 100), game.recovery_helpers]
	if game.tow_target != null:
		info_text = "ВЫТАСКИВАЕМ ЭКИПАЖ   ·   %d%%   ·   УДЕРЖИВАЙ T" % int(game.tow_progress * 100)
	elif near_tow:
		hint_text += "   ·   Иди в машину, чтобы толкать · T — тяни пешком со стороны дороги"
	if not game.in_car:
		status_text += ("\nГРИБЫ %d · ЯГОДЫ/ВИНОГРАД %d" if game.stage.urban else "\nГРИБЫ %d · ЯГОДЫ %d") % [bag.mushrooms, bag.berries]
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
		if game.in_car and game.tow_target == null:
			info_text = "%02d КМ/Ч · МАШИНА %d%%" % [int(absf(game.speed) * 3.6), int(game.condition)]
		elif not game.in_car and game.drink_time < 0 and game.eat_time < 0 and game.beers < 30 and game.tow_target == null:
			if game.packing.active():
				info_text = "ВЕРНУТЬ ВЕЩИ В БАГАЖНИК · ОСТАЛОСЬ %d" % remaining_items
			else:
				var cook_status = "ГОТОВ" if game.cook_time >= 35 else ("%d%%" % int(game.cook_time / 35 * 100) if game.cooking else "НЕТ ОГНЯ")
				info_text = "ШАШЛЫК %s · %d/10 · ПИВО %d" % [cook_status, game.grill_servings, game.beers]
				if game.camp_cooking.pot != null:
					info_text += " · ПЛОВ %d/10" % game.camp_cooking.servings if game.camp_cooking.phase == "ready" else (" · ПЛОВ %d%%" % int(game.camp_cooking.cook_time / 45 * 100) if game.camp_cooking.phase == "cooking" else " · КАЗАН ПУСТ")
		else:
			info_text = info_text.replace("УДЕРЖИВАЙ T", "УДЕРЖИВАЙ ТРОС")
		if game.toast_time > 0:
			info_text += "\n" + game.toast_label.text
		elif not game.in_car and not target.is_empty():
			info_text += "\n" + target.label
	_set_hud_text(game.course_label, course_text)
	_set_hud_text(game.quest_label, quest_text)
	_set_hud_text(game.status_label, status_text)
	_set_hud_text(game.info_label, info_text)
	_set_hud_text(game.hint_label, hint_text)
