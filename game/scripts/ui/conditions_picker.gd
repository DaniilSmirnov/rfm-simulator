extends HBoxContainer
# Time of day and weather on the stage card: two segmented groups of picture
# tiles, «День / Ночь» and «Солнце / Дождь or Снег / Туман». The middle
# weather tile is rain on summer stages and snow on snowy ones (sky_weather.gd),
# so the weather always offers three. The picked tile is filled with the
# accent colour; the card's preview shows the stage under the pick and names it
# (lobby_ui.gd). In a room the creator's choice is everyone's.
signal changed(time: String, weather: String)

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Loc = preload("res://scripts/ui/loc.gd")
const SkyWeather = preload("res://scripts/core/sky_weather.gd")
const ICON_DIR = "res://textures/ui/menu/"
const LABELS = {"day": "День", "night": "Ночь", "sun": "Солнце", "rain": "Дождь", "snow": "Снег", "fog": "Туман"}
const ICONS = {"day": "day", "night": "night", "sun": "weather_sun", "rain": "weather_rain", "snow": "weather_snow", "fog": "weather_fog"}
const TILE_HEIGHT = 38
const HOVER = Color("ffffff14")

var time = "day"
var weather = "sun"
var snowy = false
# value -> Button; the middle weather tile is stored under both rain and snow.
var tiles: Dictionary = {}

func _init() -> void:
	name = "Conditions"
	add_theme_constant_override("separation", 8)
	tooltip_text = "В комнате время суток и погоду выбирает создатель."
	_group(["day", "night"], 2)
	_group(["sun", "rain", "fog"], 3)
	tiles.snow = tiles.rain

# A sunken rounded strip holding the tiles of one choice side by side.
func _group(values: Array, weight: int) -> void:
	var strip = PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiKit.box(UiKit.SURFACE_SUNKEN, UiKit.LINE, UiKit.RADIUS, Vector2(3, 3)))
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.size_flags_stretch_ratio = weight
	add_child(strip)
	var row = UiKit.hbox(strip, 3)
	for value in values:
		var tile = Button.new()
		tile.name = value.capitalize() + "Tile"
		tile.focus_mode = Control.FOCUS_NONE
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.custom_minimum_size = Vector2(34, TILE_HEIGHT)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tile)
		tiles[value] = tile
		tile.pressed.connect(func(): _pick(value))
		_style(tile, false)
	_dress_weather()

func _style(tile: Button, on: bool) -> void:
	var fill = UiKit.ACCENT if on else Color.TRANSPARENT
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color = UiKit.ACCENT_HOVER if on and state == "hover" else (HOVER if state == "hover" else fill)
		var style = UiKit.box(color, Color.TRANSPARENT, UiKit.RADIUS - 3, Vector2(0, 8))
		tile.add_theme_stylebox_override(state, style)
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink = UiKit.ON_ACCENT if on else UiKit.MUTED
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

# «Ночь · Дождь»: the badge over the stage preview.
func caption() -> String:
	return "%s · %s" % [Loc.t(LABELS[time]), Loc.t(LABELS[weather])]
