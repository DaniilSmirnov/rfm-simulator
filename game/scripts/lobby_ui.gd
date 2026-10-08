extends Node
# Shared presentation only: ownership remains in PlatformService and the backend.
var game: Node3D
var previews: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var images: Array[TextureRect] = []
var states: Array[Label] = []
var purchase_actions: HBoxContainer
var purchase_button: Button
var check_purchase: Button
var purchase_status: Label
var return_button: Button
var host_pause: PanelContainer
var last_size = Vector2.ZERO
var last_playing = false

func add_preview(parent: Control, kind: String) -> void:
	var image = TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size = Vector2(220, 150)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(image)
	images.append(image)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(480, 240)
	viewport.world_3d = game.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var camera = Camera3D.new()
	camera.fov = 48
	camera.far = 60 if kind == "МАШИНА" else 160
	viewport.add_child(camera)
	camera.current = true
	previews.append(viewport)
	cameras.append(camera)
	image.texture = viewport.get_texture()
	var state = game._label(parent, "", 15)
	states.append(state)
	image.tooltip_text = "Превью машины" if kind == "МАШИНА" else "Превью спецучастка"

func finish(parent: Control) -> void:
	return_button = Button.new()
	return_button.text = "В ГЛАВНОЕ МЕНЮ"
	return_button.custom_minimum_size.y = 44
	return_button.pressed.connect(game.return_to_main_menu)
	parent.add_child(return_button)
	return_button.hide()
	host_pause = PanelContainer.new()
	game.menu.get_parent().add_child(host_pause)
	host_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	host_pause.offset_left = -270
	host_pause.offset_right = 270
	host_pause.offset_top = 110
	host_pause.add_theme_stylebox_override("panel", game._panel(Color("23342bf5")))
	var text = game._label(host_pause, "Хозяин поставил игру на паузу\nЖдём продолжения выезда", 20, Color("ffe4a5"))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host_pause.hide()
	var actions = HBoxContainer.new()
	purchase_actions = actions
	parent.add_child(actions)
	purchase_button = Button.new()
	purchase_button.custom_minimum_size.y = 40
	purchase_button.pressed.connect(func(): game.platform_service.buy("stage_02"))
	purchase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purchase_button.add_theme_font_size_override("font_size", 14)
	actions.add_child(purchase_button)
	check_purchase = Button.new()
	check_purchase.text = "ПРОВЕРИТЬ ПОКУПКУ"
	check_purchase.custom_minimum_size.y = 40
	check_purchase.pressed.connect(func(): game.platform_service.refresh_store())
	check_purchase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_purchase.add_theme_font_size_override("font_size", 14)
	actions.add_child(check_purchase)
	purchase_status = game._label(parent, "", 14)
	purchase_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purchase_button.hide()
	check_purchase.hide()
	purchase_status.hide()
	refresh.call_deferred()

func allowed(kind: String, index: int) -> bool:
	return game.platform_service == null or game.platform_service.can_use(kind, index)

func refresh() -> void:
	if previews.size() < 2:
		return
	var service = game.platform_service
	var product = service.product("stage", game.stage_choice.selected) if service != null else {}
	var can_buy: bool = product.get("purchase_enabled", false) and not allowed("stage", game.stage_choice.selected)
	purchase_button.visible = can_buy and not game.playing
	purchase_button.disabled = service.busy if service != null else true
	purchase_button.text = "ТЕСТ: ОТКРЫТЬ СУ · %s ГОЛОС(ОВ)" % str(product.get("price", ""))
	check_purchase.visible = service != null and service.profile.get("platform") == "vk" and (can_buy or not service.purchase_message.is_empty()) and not game.playing
	purchase_actions.visible = purchase_button.visible or check_purchase.visible
	check_purchase.disabled = service.busy if service != null else true
	purchase_status.text = service.purchase_message if service != null else ""
	purchase_status.visible = not purchase_status.text.is_empty() and not game.playing
	var car_ok = allowed("car", game.car_choice.selected)
	var stage_ok = allowed("stage", game.stage_choice.selected)
	for i in range(2):
		var ok = car_ok if i == 0 else stage_ok
		states[i].text = "Доступно для выезда" if ok else ("Закрыто · доступна тестовая покупка" if i == 1 and can_buy else "Закрыто · продажи ещё не открыты")
		states[i].add_theme_color_override("font_color", Color("b2bea1") if ok else Color("ffbc83"))
	var car_target = game.car.position + Vector3(0, 0.9, 0)
	cameras[0].position = car_target + Vector3(4.8, 2.2, 5.6)
	cameras[0].look_at(car_target)
	var position_on_stage = 390.0 if game.stage.urban else 200.0
	var stage_target = game.stage.at(position_on_stage)
	cameras[1].position = stage_target + Vector3(28, 20, 30)
	cameras[1].look_at(stage_target)
	for viewport in previews:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if game.room != null:
		game.room.create_button.disabled = game.room.busy or not car_ok or not stage_ok
		# A guest borrows the host's stage. Only their personal car is required.
		game.room.join_button.disabled = game.room.busy or not car_ok or game.room.id_input.text.strip_edges().length() != 6

func _process(_delta: float) -> void:
	var size = game.get_viewport().get_visible_rect().size
	if size != last_size or game.playing != last_playing:
		last_size = size
		last_playing = game.playing
		var compact = game.mobile_mode or size.y < 650
		var width = minf(size.x - 48, 600 if game.playing else 920)
		game.menu.offset_left = -width / 2
		game.menu.offset_right = width / 2
		var height = 220.0 if game.playing else minf(size.y - 40, 630)
		game.menu.offset_top = -height / 2
		game.menu.offset_bottom = height / 2
		if not game.playing:
			game.menu_text.text = "Твой выезд · до 8 игроков в общем лагере"
		for image in images:
			image.custom_minimum_size.y = 100 if compact else 170
		game.menu_title.add_theme_font_size_override("font_size", 25 if compact else 34)
		game.menu_help.visible = not compact and not game.playing
		refresh()
	if game.room != null:
		host_pause.visible = game.room.connected and not game.room.is_host and game.room.world_paused and not game.paused and not game.dead and not game.finished
	return_button.visible = game.playing
	if game.mobile_mode:
		var active_hud = game.playing and not game.paused and not game.dead and not game.finished and not host_pause.visible
		game.mobile_top.visible = active_hud
		game.mobile_bottom.visible = active_hud and not game.info_label.text.is_empty()
