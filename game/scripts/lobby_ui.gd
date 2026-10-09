extends Node
# Shared presentation only: ownership remains in PlatformService and the backend.
var game: Node3D
var background: TextureRect
var images: Array[TextureRect] = []
var states: Array[Label] = []
var purchase_actions: HBoxContainer
var car_purchase_button: Button
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
	var state = game._label(parent, "", 15)
	states.append(state)
	image.tooltip_text = "Превью машины" if kind == "МАШИНА" else "Превью спецучастка"

func finish(parent: Control) -> void:
	background = TextureRect.new()
	background.name = "StageBackdrop"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.modulate = Color(0.8, 0.8, 0.8, 1)
	var ui = game.menu.get_parent()
	# Backdrop fills the viewport independently of the inset HUD root.
	var backdrop_root = Control.new()
	backdrop_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.get_parent().add_child(backdrop_root)
	ui.get_parent().move_child(backdrop_root, 0)
	backdrop_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	purchase_button.pressed.connect(func(): game.platform_service.buy(game.platform_service.product("stage", game.stage_choice.selected).get("sku", "")))
	purchase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purchase_button.add_theme_font_size_override("font_size", 14)
	actions.add_child(purchase_button)
	car_purchase_button = Button.new()
	car_purchase_button.custom_minimum_size.y = 40
	car_purchase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_purchase_button.add_theme_font_size_override("font_size", 14)
	car_purchase_button.pressed.connect(func(): game.platform_service.buy(game.platform_service.product("car", game.car_choice.selected).get("sku", "")))
	actions.add_child(car_purchase_button)
	check_purchase = Button.new()
	check_purchase.text = "ПРОВЕРИТЬ ПОКУПКУ"
	check_purchase.custom_minimum_size.y = 40
	check_purchase.pressed.connect(func(): game.platform_service.refresh_store())
	check_purchase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_purchase.add_theme_font_size_override("font_size", 14)
	actions.add_child(check_purchase)
	purchase_status = game._label(parent, "", 14)
	purchase_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	car_purchase_button.hide()
	purchase_button.hide()
	check_purchase.hide()
	purchase_status.hide()
	refresh.call_deferred()

func allowed(kind: String, index: int) -> bool:
	return game.platform_service == null or game.platform_service.can_use(kind, index)

func refresh() -> void:
	if images.size() < 2:
		return
	var service = game.platform_service
	var product = service.product("stage", game.stage_choice.selected) if service != null else {}
	var can_buy: bool = product.get("purchase_enabled", false) and not allowed("stage", game.stage_choice.selected)
	var car_product = service.product("car", game.car_choice.selected) if service != null else {}
	var can_buy_car: bool = car_product.get("purchase_enabled", false) and not allowed("car", game.car_choice.selected)
	car_purchase_button.visible = can_buy_car and not game.playing
	car_purchase_button.disabled = service.busy if service != null else true
	car_purchase_button.text = ("ТЕСТ: " if car_product.get("payment_mode") == "test" else "") + "КУПИТЬ МАШИНУ · " + vote_price(int(car_product.get("price", 0)))
	purchase_button.visible = can_buy and not game.playing
	purchase_button.disabled = service.busy if service != null else true
	purchase_button.text = ("ТЕСТ: " if product.get("payment_mode") == "test" else "") + "ОТКРЫТЬ СУ · " + vote_price(int(product.get("price", 0)))
	check_purchase.visible = service != null and service.profile.get("platform") == "vk" and (can_buy or can_buy_car or not service.purchase_message.is_empty()) and not game.playing
	purchase_actions.visible = purchase_button.visible or car_purchase_button.visible or check_purchase.visible
	check_purchase.disabled = service.busy if service != null else true
	purchase_status.text = service.purchase_message if service != null else ""
	purchase_status.visible = not purchase_status.text.is_empty() and not game.playing
	var car_ok = allowed("car", game.car_choice.selected)
	var stage_ok = allowed("stage", game.stage_choice.selected)
	for i in range(2):
		var ok = car_ok if i == 0 else stage_ok
		var bought = service != null and service.owns("car" if i == 0 else "stage", game.car_choice.selected if i == 0 else game.stage_choice.selected)
		states[i].text = ("Куплено · доступно для выезда" if bought else "Доступно для выезда") if ok else ("Закрыто · доступна покупка" if ((i == 1 and can_buy) or (i == 0 and can_buy_car)) else "Закрыто · продажи ещё не открыты")
		states[i].add_theme_color_override("font_color", Color("b2bea1") if ok else Color("ffbc83"))
	background.visible = not game.playing
	background.texture = null if game.playing else load("res://textures/previews/backdrop_%d.webp" % game.selected_stage)
	images[0].texture = load("res://textures/previews/car_%d.webp" % game.selected_car)
	images[1].texture = load("res://textures/previews/stage_%d.webp" % game.selected_stage)
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
		for image in images:
			image.custom_minimum_size.y = 90 if compact else 130
		game.menu_title.add_theme_font_size_override("font_size", 25 if compact else 34)
		refresh()
	# Main menu has no duplicate heading or instructions; game dialogs retain theirs.
	game.menu_title.visible = game.playing or game.dead or game.finished
	game.menu_text.visible = game.menu_title.visible
	if not game.mobile_mode:
		var minimum = game.menu.get_combined_minimum_size()
		var extent = Vector2(maxf(minf(size.x - 48, 600 if game.playing else 920), minimum.x), maxf(minf(size.y - 40, 220 if game.playing else 630), minimum.y))
		var factor = minf(1.0, minf(maxf(size.x - 48, 1) / extent.x, maxf(size.y - 40, 1) / extent.y))
		game.menu.offset_left = -extent.x / 2
		game.menu.offset_right = extent.x / 2
		game.menu.offset_top = -extent.y / 2
		game.menu.offset_bottom = extent.y / 2
		game.menu.pivot_offset = extent / 2
		game.menu.scale = Vector2.ONE * factor
	if game.room != null:
		host_pause.visible = game.room.connected and not game.room.is_host and game.room.world_paused and not game.paused and not game.dead and not game.finished
	return_button.visible = game.playing
	if game.mobile_mode:
		var active_hud = game.playing and not game.paused and not game.dead and not game.finished and not host_pause.visible
		game.mobile_top.visible = active_hud
		game.mobile_bottom.visible = active_hud and not game.info_label.text.is_empty()

func vote_price(price: int) -> String:
	var ending = "ГОЛОСОВ"
	if price % 100 < 11 or price % 100 > 14:
		if price % 10 == 1:
			ending = "ГОЛОС"
		elif price % 10 >= 2 and price % 10 <= 4:
			ending = "ГОЛОСА"
	return "%d %s" % [price, ending]
