extends HBoxContainer
# Time of day and weather on the stage card: two segmented groups of picture
# tiles, «День / Ночь» and «Солнце / Дождь or Снег / Туман». The middle
# weather tile is rain on summer stages and snow on snowy ones (sky_weather.gd),
# so the weather always offers three. The picked tile is filled with the
# accent colour. The strip sits in a corner of the stage preview, which shows
# the stage under the pick (lobby_ui.gd), so the card keeps the same rows as
# the others. In a room the creator's choice is everyone's.
signal changed(time: String, weather: String)

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const SkyWeather = preload("res://scripts/core/sky_weather.gd")
const ICON_DIR = "res://textures/ui/menu/"
const LABELS = {"day": "День", "night": "Ночь", "sun": "Солнце", "rain": "Дождь", "snow": "Снег", "fog": "Туман"}
const ICONS = {"day": "day", "night": "night", "sun": "weather_sun", "rain": "weather_rain", "snow": "weather_snow", "fog": "weather_fog"}
# Tile size on a desktop card and on a phone, where the preview is low.
const TILE = Vector2(36, 30)
const TILE_COMPACT = Vector2(30, 26)
const HOVER = Color("ffffff24")
# Dark glass over the picture: the tiles read on snow and on a night sky alike.
const GLASS = Color(0.063, 0.102, 0.078, 0.74)

var time = "day"
var weather = "sun"
var snowy = false
# value -> Button; the middle weather tile is stored under both rain and snow.
var tiles: Dictionary = {}

func _init() -> void:
	name = "Conditions"
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "В комнате время суток и погоду выбирает создатель."
	_group(["day", "night"])
	_group(["sun", "rain", "fog"])
	tiles.snow = tiles.rain

# A sunken rounded strip holding the tiles of one choice side by side.
func _group(values: Array) -> void:
	var strip = PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiKit.box(GLASS, Color(UiKit.LINE, 0.9), 8, Vector2(2, 2)))
	add_child(strip)
	var row = UiKit.hbox(strip, 2)
	for value in values:
		var tile = Button.new()
		tile.name = value.capitalize() + "Tile"
		tile.focus_mode = Control.FOCUS_NONE
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.custom_minimum_size = TILE
		row.add_child(tile)
		tiles[value] = tile
		tile.pressed.connect(func(): _pick(value))
		_style(tile, false)
	_dress_weather()

func _style(tile: Button, on: bool) -> void:
	var fill = UiKit.ACCENT if on else Color.TRANSPARENT
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color = UiKit.ACCENT_HOVER if on and state == "hover" else (HOVER if state == "hover" else fill)
		var style = UiKit.box(color, Color.TRANSPARENT, 6, Vector2(7, 5))
		tile.add_theme_stylebox_override(state, style)
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink = UiKit.ON_ACCENT if on else UiKit.TEXT
	for state in ["icon_normal_color", "icon_pressed_color", "icon_focus_color"]:
		tile.add_theme_color_override(state, ink)
	tile.add_theme_color_override("icon_hover_color", UiKit.ON_ACCENT if on else UiKit.HIGHLIGHT)
	tile.add_theme_color_override("icon_hover_pressed_color", UiKit.ON_ACCENT if on else UiKit.HIGHLIGHT)

# The middle weather tile: rain or snow, whichever the stage has.
func _dress_weather() -> void:
	if not tiles.has("rain"):
		return
	var wet = "snow" if snowy else "rain"
	for value in ["day", "night", "sun", wet, "fog"]:
		tiles[value].icon = load(ICON_DIR + ICONS[value] + ".svg")
		tiles[value].tooltip_text = LABELS[value]

func _pick(value: String) -> void:
	if value in SkyWeather.DAYTIMES:
		time = value
	else:
		# The middle tile means the stage's own wet weather.
		weather = ("snow" if snowy else "rain") if value in ["rain", "snow"] else value
	_show()
	changed.emit(time, weather)

# The conditions in force: a stage switch may have turned the weather to sun,
# and a guest sees the room's.
func show_conditions(new_time: String, new_weather: String, new_snowy: bool) -> void:
	time = new_time
	weather = new_weather
	snowy = new_snowy
	_dress_weather()
	_show()

func _show() -> void:
	for value in ["day", "night", "sun", "rain", "fog"]:
		var picked = value == time or value == weather or (value == "rain" and weather == "snow")
		_style(tiles[value], picked)

func set_compact(compact: bool) -> void:
	for value in ["day", "night", "sun", "rain", "fog"]:
		tiles[value].custom_minimum_size = TILE_COMPACT if compact else TILE
