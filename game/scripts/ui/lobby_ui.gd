extends Node
# Main menu presentation: car, stage and character cards with their own purchase buttons,
# site and support links, settings and quit icons, host-pause banner and the menu backdrop.
# Ownership remains in PlatformService and the backend.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const SUPPORT_EMAIL = "rallyfansmap@yandex.com"
const CharacterProfiles = preload("res://scripts/people/character_profiles.gd")
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
var quit_dialog: Control
var quit_text: Label
var leave_dialog: Control
var quit_button: Button
var host_pause: PanelContainer
var help_button: Button
var language_button: Button
var help_dialog: Control
var about_button: Button
var about_dialog: Control
var settings_button: Button
var memory = preload("res://scripts/ui/menu_memory.gd").new()
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
	game.stage_caption.text = game.StageRegistry.caption(game.selected_stage).to_upper()
	game.hud.settings_screen.retranslate()
	game.room.ui.refresh_language()
	if game.mobile_controls != null:
		game.mobile_controls.layout_state = []
	refresh()
	# The HUD under the pause menu is rebuilt only while playing.
	if game.playing:
		game.hud.update_hud()

func _help_message() -> String:
	return Loc.t("Если с игрой что-то не так, напиши нам:\n%s\n\nСкопируй адрес и отправь письмо из удобной почты.") % SUPPORT_EMAIL

func _about_message() -> String:
	return Loc.t("Rally Fans Simulator сделан командой Rally Fans Map. Подробнее о проекте — на сайте:\n%s") % UiKit.BRAND_URL

func _is_vk_platform() -> bool:
	return game.platform_service != null and game.platform_service.profile.get("platform", "") == "vk"

# ---------------------------------------------------------------- selection

# One card per choice, in menu order: what it is, its catalog type, the
# purchase label and the preview tooltip. The character card shows the pick
# in the clothes of the selected stage (summer or winter).
const CARDS = [
	{"title": "МАШИНА", "kind": "car", "node": "CarCard", "buy": "КУПИТЬ МАШИНУ · %s", "preview": "Превью машины"},
	{"title": "СПЕЦУЧАСТОК", "kind": "stage", "node": "StageCard", "buy": "ОТКРЫТЬ СУ · %s", "preview": "Превью спецучастка"},
	{"title": "ПЕРСОНАЖ", "kind": "character", "node": "CharacterCard", "buy": "КУПИТЬ ПЕРСОНАЖА · %s", "preview": "Превью персонажа"},
]
var choices: Array[HBoxContainer] = []
var buy_buttons: Array[Button] = []
var character_choice: HBoxContainer

func build_selection(parent: Control) -> void:
	var cards = UiKit.hbox(parent, 14)
	for spec in CARDS:
		var card = UiKit.expand(UiKit.card(cards, UiKit.SURFACE_RAISED, Vector2(12, 12)))
		card.name = spec.node
		var column = UiKit.vbox(card, 8)
		UiKit.label(column, spec.title, "caption")
		add_preview(column, spec.preview)
		var choice = preload("res://scripts/ui/menu_choice.gd").new()
		choice.custom_minimum_size.y = 42
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(choice)
		choices.append(choice)
		var state = UiKit.label(column, "", "muted")
		states.append(state)
		var buy = UiKit.button(column, "", "secondary", 40)
		buy.add_theme_font_size_override("font_size", 15)
		buy.hide()
		buy_buttons.append(buy)
		var kind: String = spec.kind
		buy.pressed.connect(func(): game.platform_service.buy(game.platform_service.product(kind, selected(kind)).get("sku", "")))
	game.car_choice = choices[0]
	for model in game.Props.PLAYER_MODELS:
		game.car_choice.add_item(model.name)
	game.car_choice.item_selected.connect(game.select_player_car)
	car_purchase_button = buy_buttons[0]
	game.stage_choice = choices[1]
	for title in game.Stage.STAGES:
		game.stage_choice.add_item(title.get_slice("·", 0).strip_edges())
	game.stage_choice.item_selected.connect(game.select_stage)
	game.stage_choice.tooltip_text = "В комнате СУ выбирает создатель. Все участники играют на одной трассе."
	purchase_button = buy_buttons[1]
	character_choice = choices[2]
	for variant in CharacterProfiles.playable():
		character_choice.add_item(CharacterProfiles.SPECTATOR_MODELS[variant].name)
	character_choice.item_selected.connect(func(index: int): select_character(CharacterProfiles.playable()[index]))
	character_choice.select(CharacterProfiles.playable().find(game.avatar_variant))
	# VK purchases: one status line with a re-check, under the cards.
	purchase_actions = UiKit.hbox(parent, 12)
	purchase_actions.name = "PurchaseStatus"
	purchase_actions.alignment = BoxContainer.ALIGNMENT_END
	purchase_actions.custom_minimum_size.y = 40
	purchase_status = UiKit.expand(UiKit.wrap(UiKit.label(purchase_actions, "", "muted")))
	purchase_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check_purchase = UiKit.button(purchase_actions, "ПРОВЕРИТЬ ПОКУПКУ", "ghost", 40)
	check_purchase.add_theme_font_size_override("font_size", 15)
	check_purchase.pressed.connect(func(): game.platform_service.refresh_store())
	purchase_actions.hide()

func add_preview(parent: Control, tooltip: String) -> void:
	var image = TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size = Vector2(180, 140)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.tooltip_text = tooltip
	parent.add_child(image)
	images.append(image)

# The look the player walks as (its catalog content_id). Picked in the menu
# only: a room learns it on joining, so it does not change while playing.
func select_character(variant: int) -> void:
	if game.playing or game.loading_world:
		return
	var looks = CharacterProfiles.playable()
	game.avatar_variant = variant if variant in looks else looks[0]
	character_choice.select(looks.find(game.avatar_variant))
	refresh()

# The content_id selected on a card of this catalog type.
func selected(kind: String) -> int:
	return game.car_choice.selected if kind == "car" else game.stage_choice.selected if kind == "stage" else game.avatar_variant

# ---------------------------------------------------------------- links

func build_links(parent: Control) -> void:
	about_button = UiKit.button(parent, "О НАС", "ghost", 40)
	about_button.name = "AboutButton"
	about_button.tooltip_text = Loc.t("Сайт Rally Fans Map: %s") % UiKit.BRAND_URL
	about_button.add_theme_font_size_override("font_size", 15)
	about_button.pressed.connect(_open_about)
	# Hidden everywhere for now: VK Play forbids links that lead players to other sites.
	about_button.hide()
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
	settings_button = UiKit.icon_button(parent, "res://textures/ui/menu/settings.svg", "Настройки")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(func(): game.hud.settings_screen.open())
	# Only a desktop window has nowhere else to close the game from.
	quit_button = UiKit.icon_button(parent, "res://textures/ui/menu/quit.svg", "Выйти из игры")
	quit_button.name = "QuitButton"
	quit_button.pressed.connect(_confirm_quit)
	quit_button.visible = OS.has_feature("pc") and not OS.has_feature("web")

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
	# In a browser shell_open("mailto:") reports OK even with no mail client,
	# so the web build always shows the address (same as inside VK).
	if OS.has_feature("web") or _is_vk_platform() or OS.shell_open("mailto:" + SUPPORT_EMAIL) != OK:
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

# ---------------------------------------------------------------- assembly

func finish(parent: Control) -> void:
	return_button = UiKit.button(parent, "В ГЛАВНОЕ МЕНЮ", "ghost", 44)
	return_button.name = "ReturnButton"
	return_button.pressed.connect(_confirm_leave)
	return_button.hide()
	_build_quit_dialog()
	_build_leave_dialog()
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
	# The room entry (nickname) is built after the menu, so the picks come back a frame later.
	_restore_choice.call_deferred()

func _restore_choice() -> void:
	memory.setup(game)
	memory.restore()

func allowed(kind: String, index: int) -> bool:
	return game.platform_service == null or game.platform_service.can_use(kind, index)

func refresh() -> void:
	if images.size() < CARDS.size():
		return
	# The VK profile can arrive after the menu was built.
	if _is_vk_family():
		language_button.visible = false
		if Loc.current != "ru":
			Loc.force("ru")
			language_button.text = Loc.other_name()
	var service = game.platform_service
	var any_purchase = false
	for variant in range(game.car_choice.item_count):
		game.car_choice.set_skipped(variant, not game.Props.CarRegistry.offered(variant, game.selected_stage))
	for i in range(CARDS.size()):
		var kind: String = CARDS[i].kind
		var index = selected(kind)
		var product = service.product(kind, index) if service != null else {}
		var ok = allowed(kind, index)
		var can_buy: bool = product.get("purchase_enabled", false) and not ok
		any_purchase = any_purchase or can_buy
		var buy = buy_buttons[i]
		buy.visible = can_buy and not game.playing
		buy.disabled = service.busy if service != null else true
		buy.text = ("ТЕСТ: " if product.get("payment_mode") == "test" else "") + Loc.t(CARDS[i].buy) % vote_price(int(product.get("price", 0)))
		var bought = service != null and service.owns(kind, index)
		# Free and available needs no note; only ownership and locks are shown.
		states[i].text = ("Куплено" if bought else "") if ok else ("Закрыто · можно открыть" if can_buy else "Закрыто · скоро в продаже")
		# A visible purchase button already says the content is closed.
		states[i].visible = not states[i].text.is_empty() and not buy.visible
		states[i].add_theme_color_override("font_color", UiKit.MUTED if ok else UiKit.WARNING)
	check_purchase.visible = service != null and service.profile.get("platform") == "vk" and (any_purchase or not service.purchase_message.is_empty()) and not game.playing
	check_purchase.disabled = service.busy if service != null else true
	purchase_status.text = service.purchase_message if service != null else ""
	# Store messages only mean something in VK. Elsewhere the startup «Проверяем
	# доступ…» line vanished a moment later and the menu jumped under the first click.
	var vk_store = OS.has_feature("vk") or (service != null and service.profile.get("platform") == "vk")
	purchase_status.visible = vk_store and not purchase_status.text.is_empty() and not game.playing
	# The VK build keeps the row's height while the store loads for the same reason.
	purchase_actions.visible = check_purchase.visible or purchase_status.visible or (OS.has_feature("vk") and not game.playing)
	var car_ok = allowed("car", game.car_choice.selected)
	var stage_ok = allowed("stage", game.stage_choice.selected)
	var character_ok = allowed("character", game.avatar_variant)
	background.visible = not game.playing
	background.texture = null if game.playing else load("res://textures/previews/backdrop_%d.webp" % game.selected_stage)
	images[0].texture = load("res://textures/previews/car_%d.webp" % game.selected_car)
	images[1].texture = load("res://textures/previews/stage_%d.webp" % game.selected_stage)
	images[2].texture = load(CharacterProfiles.preview_path(game.avatar_variant, game.stage.outfit if game.stage != null else ""))
	if game.room != null:
		game.room.ui.create_button.disabled = game.room.busy or not car_ok or not stage_ok or not character_ok
		# A guest borrows the host's stage. Only their own car and character are required.
		game.room.ui.join_button.disabled = game.room.busy or not car_ok or not character_ok or game.room.ui.id_input.text.strip_edges().length() != NetProtocol.room_id_length()

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
	# Results already lead back to the menu through «НОВЫЙ ВЫЕЗД»; only the pause needs its own way out.
	return_button.visible = game.playing and game.paused and not result
	if not game.mobile_mode:
		game.mobile_top.visible = game.playing
	else:
		var active_hud = game.playing and not game.paused and not result and not host_pause.visible
		game.mobile_top.visible = active_hud
		game.mobile_bottom.visible = active_hud and not game.info_label.text.is_empty()

func _build_quit_dialog() -> void:
	var modal = UiKit.modal(game.hud.dialog_layer, "QuitDialog")
	quit_dialog = modal.root
	UiKit.label(modal.content, "Выйти из игры?", "heading")
	quit_text = UiKit.wrap(UiKit.label(modal.content, "", "body"))
	var row = UiKit.hbox(modal.content, 10)
	var cancel = UiKit.expand(UiKit.button(row, "ОСТАТЬСЯ", "secondary", 44))
	cancel.name = "CancelQuit"
	cancel.pressed.connect(func():
		quit_dialog.hide()
		quit_button.grab_focus()
	)
	var confirm = UiKit.expand(UiKit.button(row, "ВЫЙТИ ИЗ ИГРЫ", "primary", 44))
	confirm.name = "ConfirmQuit"
	confirm.pressed.connect(_quit_game)

func _confirm_quit() -> void:
	quit_text.text = "Игра закроется, и ты покинешь выезд. Прогресс выезда не сохраняется — в следующий раз он начнётся заново." if game.playing else "Игра закроется."
	quit_dialog.show()
	game.hud.fit_modal(quit_dialog)
	quit_dialog.find_child("CancelQuit", true, false).grab_focus()

# The outing lives only as long as the room: VK Play asks to say so before leaving.
func _build_leave_dialog() -> void:
	var modal = UiKit.modal(game.hud.dialog_layer, "LeaveDialog")
	leave_dialog = modal.root
	UiKit.label(modal.content, "Вернуться в главное меню?", "heading")
	UiKit.wrap(UiKit.label(modal.content, "Ты покинешь выезд. Прогресс выезда не сохраняется — в следующий раз он начнётся заново.", "body"))
	var row = UiKit.hbox(modal.content, 10)
	var cancel = UiKit.expand(UiKit.button(row, "ОСТАТЬСЯ", "secondary", 44))
	cancel.name = "CancelLeave"
	cancel.pressed.connect(func():
		leave_dialog.hide()
		return_button.grab_focus()
	)
	var confirm = UiKit.expand(UiKit.button(row, "В ГЛАВНОЕ МЕНЮ", "primary", 44))
	confirm.name = "ConfirmLeave"
	confirm.pressed.connect(func():
		leave_dialog.hide()
		game.return_to_main_menu()
	)

func _confirm_leave() -> void:
	leave_dialog.show()
	game.hud.fit_modal(leave_dialog)
	leave_dialog.find_child("CancelLeave", true, false).grab_focus()

# Leaving tells the room right away instead of waiting for it to time out.
func _quit_game() -> void:
	quit_button.disabled = true
	if game.room != null and game.room.connected:
		game.room.leave()
	await game._shutdown_audio()
	game.get_tree().quit()

func vote_price(price: int) -> String:
	var ending = "ГОЛОСОВ"
	if price % 100 < 11 or price % 100 > 14:
		if price % 10 == 1:
			ending = "ГОЛОС"
		elif price % 10 >= 2 and price % 10 <= 4:
			ending = "ГОЛОСА"
	return "%d %s" % [price, ending]
