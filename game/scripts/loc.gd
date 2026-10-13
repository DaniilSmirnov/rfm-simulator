extends RefCounted
# Interface language: Russian (the source text of the game) and English.
# Every Russian string in the code is also the key of data/translations_en.json.
# Labels, buttons, tooltips and 3D labels translate themselves through the
# TranslationServer, so only text assembled from pieces needs Loc.t():
#   toast(Loc.t("Осталось %d шампуров.") % count)
# Russian has no translation entry, so the key is shown as it is.
#
# Which language is used:
#   1. VK builds are always Russian and offer no choice.
#   2. RFM_LANG=ru|en in the environment (tests, screenshots).
#   3. A choice made with the language button (user://language.cfg).
#   4. The system language: Russian stays Russian, anything else is English.
const TRANSLATIONS_PATH = "res://data/translations_en.json"
const SETTINGS_PATH = "user://language.cfg"
const LANGUAGES = ["ru", "en"]
const NAMES = {"ru": "РУССКИЙ", "en": "ENGLISH"}

static var current = "ru"
static var forced = ""
static var loaded = false
static var settings_path = SETTINGS_PATH

# Translated text; the same call works in static functions and in any node.
static func t(text: String) -> String:
	return TranslationServer.translate(text) if current != "ru" else text

# Called once at start; safe to call again.
static func setup() -> void:
	if not loaded:
		loaded = true
		var translation = Translation.new()
		translation.locale = "en"
		var data = JSON.parse_string(FileAccess.get_file_as_string(TRANSLATIONS_PATH))
		if data is Dictionary:
			for key in data:
				translation.add_message(key, str(data[key]))
		TranslationServer.add_translation(translation)
	set_language(detect(), false)

# The VK client is Russian-only; a platform that learns it is VK late (the
# prototype reports its profile asynchronously) calls this.
static func force(language: String) -> void:
	forced = language
	set_language(language, false)

static func is_forced() -> bool:
	return forced != "" or OS.has_feature("vk")

static func detect() -> String:
	if OS.has_feature("vk"):
		return "ru"
	if forced != "":
		return forced
	var override = OS.get_environment("RFM_LANG")
	if override in LANGUAGES:
		return override
	var saved = saved_language()
	if saved != "":
		return saved
	return from_system(OS.get_locale_language())

static func from_system(system_language: String) -> String:
	return "ru" if system_language.to_lower() == "ru" else "en"

static func saved_language() -> String:
	var config = ConfigFile.new()
	if config.load(settings_path) == OK:
		var value = str(config.get_value("language", "code", ""))
		if value in LANGUAGES:
			return value
	return ""

static func set_language(language: String, remember: bool = true) -> void:
	current = language if language in LANGUAGES else "en"
	TranslationServer.set_locale(current)
	# The page around the game (loading screen, rotate prompt) follows.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("globalThis.RallyI18n && RallyI18n.set('%s')" % current)
	if remember and not is_forced():
		var config = ConfigFile.new()
		config.set_value("language", "code", current)
		if config.save(settings_path) != OK:
			push_warning("Could not save the language")

static func other() -> String:
	return "en" if current == "ru" else "ru"

# Name of the language the button switches to, written in that language.
static func other_name() -> String:
	return NAMES[other()]
