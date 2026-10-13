extends Node
# Main menu presentation: car and stage cards with their own purchase buttons,
# site and support links, volume, host-pause banner and the menu backdrop.
# Ownership remains in PlatformService and the backend.
const NetProtocol = preload("res://scripts/net_protocol.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Loc = preload("res://scripts/loc.gd")
const SUPPORT_EMAIL = "rallyfansmap@yandex.com"
const AUDIO_SETTINGS_PATH = "user://audio_settings.cfg"
const KINDS = ["МАШИНА", "СПЕЦУЧАСТОК"]
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
var help_button: Button
var language_button: Button
var help_dialog: Control
var about_button: Button
var about_dialog: Control
var audio_controls: VBoxContainer
var volume_label: Label
var volume_slider: HSlider
var master_base_db = 0.0
var last_size = Vector2.ZERO
var last_playing = false

func _is_vk_family() -> bool:
	return OS.has_feature("vk") or (game.platform_service != null and game.platform_service.profile.get("platform", "") in ["vk", "vk-prototype"])

# Text assembled in code is rebuilt in the new language; labels and buttons
# translate themselves when the locale changes.
func _switch_language() -> void:
	Loc.set_language(Loc.other())
	retranslate()

func retranslate() -> void:
	language_button.text = Loc.other_name()
	help_button.tooltip_text = Loc.t("Написать в поддержку: %s") % SUPPORT_EMAIL
	about_button.tooltip_text = Loc.t("Сайт Rally Fans Map: %s") % UiKit.BRAND_URL
	help_dialog.find_child("Message", true, false).text = _help_message()
	about_dialog.find_child("Message", true, false).text = _about_message()
	game.hud.footer.text = Loc.t("Версия %s") % ProjectSettings.get_setting("application/config/version")
	game.stage_caption.text = game.StageRegistry.caption(game.selected_stage) if game.playing else game.StageRegistry.caption(game.selected_stage).to_upper()
	game.room.ui.refresh_language()
	if game.mobile_controls != null:
		game.mobile_controls.layout_state = []
	refresh()

func _help_message() -> String:
	return Loc.t("Если с игрой что-то не так, напиши нам:\n%s\n\nСкопируй адрес и отправь письмо из удобной почты.") % SUPPORT_EMAIL

func _about_message() -> String:
	return Loc.t("Rally Fans Simulator сделан командой Rally Fans Map. Подробнее о проекте — на сайте:\n%s") % UiKit.BRAND_URL

func _is_vk_platform() -> bool:
	return game.platform_service != null and game.platform_service.profile.get("platform", "") == "vk"

# ---------------------------------------------------------------- selection

func build_selection(parent: Control) -> void:
	var cards = UiKit.hbox(parent, 14)
	for kind in KINDS:
		var card = UiKit.expand(UiKit.card(cards, UiKit.SURFACE_RAISED, Vector2(12, 12)))
		card.name = "CarCard" if kind == "МАШИНА" else "StageCard"
		var column = UiKit.vbox(card, 8)
		UiKit.label(column, kind, "caption")
		add_preview(column, kind)
		var choice = preload("res://scripts/menu_choice.gd").new()
		choice.custom_minimum_size.y = 42
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(choice)
		var state = UiKit.label(column, "", "muted")
		states.append(state)
		var buy = UiKit.button(column, "", "secondary", 40)
		buy.add_theme_font_size_override("font_size", 15)
		buy.hide()
		if kind == "МАШИНА":
			game.car_choice = choice
			for model in game.Props.PLAYER_MODELS:
				choice.add_item(model.name)
			choice.item_selected.connect(game.select_player_car)
			car_purchase_button = buy
			buy.pressed.connect(func(): game.platform_service.buy(game.platform_service.product("car", game.car_choice.selected).get("sku", "")))
		else:
			game.stage_choice = choice
			for title in game.Stage.STAGES:
				choice.add_item(title.get_slice("·", 0).strip_edges())
			choice.item_selected.connect(game.select_stage)
			choice.tooltip_text = "В комнате СУ выбирает создатель. Все участники играют на одной трассе."
			purchase_button = buy
			buy.pressed.connect(func(): game.platform_service.buy(game.platform_service.product("stage", game.stage_choice.selected).get("sku", "")))
	# VK purchases: one status line with a re-check, under both cards.
	purchase_actions = UiKit.hbox(parent, 12)
	purchase_actions.name = "PurchaseStatus"
	purchase_actions.alignment = BoxContainer.ALIGNMENT_END
	purchase_status = UiKit.expand(UiKit.wrap(UiKit.label(purchase_actions, "", "muted")))
	purchase_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check_purchase = UiKit.button(purchase_actions, "ПРОВЕРИТЬ ПОКУПКУ", "ghost", 40)
	check_purchase.add_theme_font_size_override("font_size", 15)
	check_purchase.pressed.connect(func(): game.platform_service.refresh_store())
	purchase_actions.hide()

func add_preview(parent: Control, kind: String) -> void:
	var image = TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size = Vector2(220, 140)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.tooltip_text = "Превью машины" if kind == "МАШИНА" else "Превью спецучастка"
	parent.add_child(image)
	images.append(image)

# ---------------------------------------------------------------- links

func build_links(parent: Control) -> void:
	about_button = UiKit.button(parent, "О НАС", "ghost", 40)
	about_button.name = "AboutButton"
	about_button.tooltip_text = Loc.t("Сайт Rally Fans Map: %s") % UiKit.BRAND_URL
	about_button.add_theme_font_size_override("font_size", 15)
	about_button.pressed.connect(_open_about)
	help_button = UiKit.button(parent, "ПОМОЩЬ", "ghost", 40)
	help_button.name = "HelpButton"
	help_button.tooltip_text = Loc.t("Написать в поддержку: %s") % SUPPORT_EMAIL
	help_button.add_theme_font_size_override("font_size", 15)
	help_button.pressed.connect(_open_help)
	# The button names the language it switches to, in that language. VK is Russian only.
	language_button = UiKit.button(parent, Loc.other_name(), "ghost", 40)
	language_button.name = "LanguageButton"
	language_button.add_theme_font_size_override("font_size", 15)
	language_button.pressed.connect(_switch_language)
	language_button.visible = not _is_vk_family()

# A small window with an address and two actions; used where the WebView may
# not open mailto: or external links (VK clients).
func _link_dialog(name: String, title: String, message: String, actions: Array) -> Control:
	var modal = UiKit.modal(game.hud.dialog_layer, name)
	UiKit.label(modal.content, title, "heading")
	var text = UiKit.wrap(UiKit.label(modal.content, message, "body"))
	text.name = "Message"
	var row = UiKit.hbox(modal.content, 10)
	row.name = "Actions"
	for action in actions:
		var button = UiKit.expand(UiKit.button(row, action[0], action[1], 44))
		button.pressed.connect(action[2])
	var close = UiKit.expand(UiKit.button(row, "ЗАКРЫТЬ", "ghost", 44))
	close.name = "Close"
	close.pressed.connect(modal.root.hide)
	return modal.root

func _open_help() -> void:
	# mailto: is not reliably handled inside the VK client WebView.
	if _is_vk_platform() or OS.shell_open("mailto:" + SUPPORT_EMAIL) != OK:
		help_dialog.show()

func _open_about() -> void:
	# External links can be swallowed by the VK WebView: offer the address too.
	if _is_vk_platform() or not UiKit.open_url(UiKit.BRAND_URL):
		about_dialog.show()

func _copy(text: String, message: String) -> void:
	if OS.has_feature("web"):
		# Bridge copy is supported inside VK mobile WebViews where Clipboard APIs
		# and mailto handlers can be restricted. Catch rejection explicitly.
		var script = "(function(){var text=" + JSON.stringify(text) + ";if(window.vkBridge && typeof window.vkBridge.send==='function'){window.vkBridge.send('VKWebAppCopyText',{text:text}).catch(function(){if(navigator.clipboard)navigator.clipboard.writeText(text).catch(function(){});});return true;}if(navigator.clipboard){navigator.clipboard.writeText(text).catch(function(){});return true;}return false;})()"
		if JavaScriptBridge.eval(script, true) == true:
			game.toast(message)
			return
	DisplayServer.clipboard_set(text)
	game.toast(message)

func _copy_support_email() -> void:
	_copy(SUPPORT_EMAIL, Loc.t("Адрес поддержки: %s") % SUPPORT_EMAIL)

# ---------------------------------------------------------------- settings

func build_audio(parent: Control) -> void:
	master_base_db = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	var settings = ConfigFile.new()
	var percent = 100.0
	if settings.load(AUDIO_SETTINGS_PATH) == OK:
		var saved = settings.get_value("audio", "volume", 100.0)
		if (saved is float or saved is int) and is_finite(float(saved)):
			percent = clampf(float(saved), 0.0, 100.0)
	audio_controls = UiKit.vbox(parent, 4)
	audio_controls.name = "AudioSettings"
	volume_label = UiKit.label(audio_controls, "", "caption")
	volume_slider = HSlider.new()
	volume_slider.name = "MasterVolume"
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.custom_minimum_size = Vector2(0, 40)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.tooltip_text = "Громкость всех звуков. 0 — без звука."
	audio_controls.add_child(volume_slider)
	volume_slider.value = percent
	_apply_volume(percent)
	volume_slider.value_changed.connect(func(value: float):
		_apply_volume(value)
		var config = ConfigFile.new()
		config.set_value("audio", "volume", value)
		if config.save(AUDIO_SETTINGS_PATH) != OK:
			game.toast("Не удалось сохранить громкость.")
	)

func _apply_volume(percent: float) -> void:
	var master = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, percent <= 0)
	AudioServer.set_bus_volume_db(master, master_base_db + linear_to_db(maxf(percent / 100.0, 0.0001)))
	volume_label.text = Loc.t("ЗВУК ВЫКЛЮЧЕН") if percent <= 0 else Loc.t("ГРОМКОСТЬ · %d%%") % roundi(percent)

# ---------------------------------------------------------------- assembly

func finish(parent: Control) -> void:
	return_button = UiKit.button(parent, "В ГЛАВНОЕ МЕНЮ", "ghost", 44)
	return_button.name = "ReturnButton"
	return_button.pressed.connect(game.return_to_main_menu)
	return_button.hide()
	help_dialog = _link_dialog("SupportDialog", "Помощь и поддержка", _help_message(), [["СКОПИРОВАТЬ АДРЕС", "primary", _copy_support_email]])
	about_dialog = _link_dialog("AboutDialog", UiKit.BRAND_NAME, _about_message(), [["ОТКРЫТЬ САЙТ", "primary", func(): UiKit.open_url(UiKit.BRAND_URL)], ["СКОПИРОВАТЬ", "secondary", func(): _copy(UiKit.BRAND_URL, Loc.t("Ссылка скопирована: %s") % UiKit.BRAND_URL)]])
	# Backdrop fills the viewport independently of the inset HUD root.
	background = TextureRect.new()
	background.name = "StageBackdrop"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.modulate = Color(0.72, 0.72, 0.72, 1)
	var canvas = game.mobile_ui.get_parent()
	var backdrop_root = Control.new()
	backdrop_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(backdrop_root)
	canvas.move_child(backdrop_root, 0)
	backdrop_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host_pause = PanelContainer.new()
	host_pause.name = "HostPause"
	host_pause.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.SURFACE, Vector2(22, 14)))
	game.mobile_ui.add_child(host_pause)
	host_pause.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	host_pause.offset_left = -240
	host_pause.offset_right = 240
	host_pause.offset_top = 96
	host_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pause_box = UiKit.vbox(host_pause, 4)
	UiKit.label(pause_box, "ПАУЗА", "caption").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text = UiKit.wrap(UiKit.label(pause_box, "Создатель выезда поставил игру на паузу.\nЖдём продолжения.", "body"))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_pause.hide()
	refresh.call_deferred()

func allowed(kind: String, index: int) -> bool:
	return game.platform_service == null or game.platform_service.can_use(kind, index)

func refresh() -> void:
	if images.size() < 2:
		return
	# The VK profile can arrive after the menu was built.
	if _is_vk_family():
		language_button.visible = false
		if Loc.current != "ru":
			Loc.force("ru")
			language_button.text = Loc.other_name()
	var service = game.platform_service
	var product = service.product("stage", game.stage_choice.selected) if service != null else {}
	var can_buy: bool = product.get("purchase_enabled", false) and not allowed("stage", game.stage_choice.selected)
	var car_product = service.product("car", game.car_choice.selected) if service != null else {}
	var can_buy_car: bool = car_product.get("purchase_enabled", false) and not allowed("car", game.car_choice.selected)
	car_purchase_button.visible = can_buy_car and not game.playing
	car_purchase_button.disabled = service.busy if service != null else true
	car_purchase_button.text = ("ТЕСТ: " if car_product.get("payment_mode") == "test" else "") + Loc.t("КУПИТЬ МАШИНУ · %s") % vote_price(int(car_product.get("price", 0)))
	purchase_button.visible = can_buy and not game.playing
	purchase_button.disabled = service.busy if service != null else true
	purchase_button.text = ("ТЕСТ: " if product.get("payment_mode") == "test" else "") + Loc.t("ОТКРЫТЬ СУ · %s") % vote_price(int(product.get("price", 0)))
	check_purchase.visible = service != null and service.profile.get("platform") == "vk" and (can_buy or can_buy_car or not service.purchase_message.is_empty()) and not game.playing
	check_purchase.disabled = service.busy if service != null else true
	purchase_status.text = service.purchase_message if service != null else ""
	purchase_status.visible = not purchase_status.text.is_empty() and not game.playing
	purchase_actions.visible = check_purchase.visible or purchase_status.visible
	var car_ok = allowed("car", game.car_choice.selected)
	var stage_ok = allowed("stage", game.stage_choice.selected)
	for i in range(2):
		var ok = car_ok if i == 0 else stage_ok
		var bought = service != null and service.owns("car" if i == 0 else "stage", game.car_choice.selected if i == 0 else game.stage_choice.selected)
		var purchasable = (i == 1 and can_buy) or (i == 0 and can_buy_car)
		# Free and available needs no note; only ownership and locks are shown.
		states[i].text = ("Куплено" if bought else "") if ok else ("Закрыто · можно открыть" if purchasable else "Закрыто · скоро в продаже")
		# A visible purchase button already says the content is closed.
		states[i].visible = not states[i].text.is_empty() and not (car_purchase_button if i == 0 else purchase_button).visible
		states[i].add_theme_color_override("font_color", UiKit.MUTED if ok else UiKit.WARNING)
	background.visible = not game.playing
	background.texture = null if game.playing else load("res://textures/previews/backdrop_%d.webp" % game.selected_stage)
	images[0].texture = load("res://textures/previews/car_%d.webp" % game.selected_car)
	images[1].texture = load("res://textures/previews/stage_%d.webp" % game.selected_stage)
	if game.room != null:
		game.room.ui.create_button.disabled = game.room.busy or not car_ok or not stage_ok
		# A guest borrows the host's stage. Only their personal car is required.
		game.room.ui.join_button.disabled = game.room.busy or not car_ok or game.room.ui.id_input.text.strip_edges().length() != NetProtocol.room_id_length()

func _process(_delta: float) -> void:
	var size = game.get_viewport().get_visible_rect().size
	if size != last_size or game.playing != last_playing:
		last_size = size
		last_playing = game.playing
		var compact = game.mobile_mode or size.y < 650
		for image in images:
			image.custom_minimum_size.y = (72 if game.mobile_mode else 100) if compact else 140
		refresh()
	game.hud.layout_menu()
	var result = game.dead or game.finished
	if game.room != null:
		# Phones keep the entry block short: the status line shows only news.
		game.room.ui.status.visible = not (game.mobile_mode and game.room.ui.status.text == game.room.ui.default_hint)
		host_pause.visible = game.room.is_guest() and game.room.world_paused and not game.paused and not result
	return_button.visible = game.playing
	if not game.mobile_mode:
		game.mobile_top.visible = game.playing
	else:
		var active_hud = game.playing and not game.paused and not result and not host_pause.visible
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
