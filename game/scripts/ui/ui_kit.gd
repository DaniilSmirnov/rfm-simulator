extends RefCounted
# One look for every screen: palette, type scale, button kinds and modal
# windows. Screens ask for a role ("primary" button, "caption" label), never
# for a colour or a font size, so menus, HUD and VK dialogs stay consistent.
#   var theme = UiKit.theme()             # set once on each UI root
#   UiKit.label(box, "Спецучасток", "caption")
#   UiKit.button(row, "ПОЕХАЛИ", "primary")
#   var modal = UiKit.modal(layer, "SupportDialog")   # modal.panel / modal.content
const Loc = preload("res://scripts/ui/loc.gd")

const BRAND_URL = "https://rallyfansmap.ru/"
const BRAND_NAME = "Rally Fans Map"
const GAME_NAME = "Rally Fans Simulator"
const LOGO = "res://branding/rfm-icon.svg"
const BRAND_FONT = preload("res://branding/fonts/RallySansExtended-Black.ttf")

# Palette: deep forest surfaces, warm amber action, Rally Fans Map orange
# only for the logo.
const SURFACE = Color("1d2b23f5")
const SURFACE_RAISED = Color("2a3c31")
const SURFACE_SUNKEN = Color("16221b")
const HUD = Color("1d2b23e0")
const LINE = Color("43594b")
const TEXT = Color("f2e8d0")
const MUTED = Color("aebb9e")
const ACCENT = Color("e3b16b")
const ACCENT_HOVER = Color("f1c687")
const ACCENT_PRESSED = Color("c78f4a")
const ON_ACCENT = Color("22342b")
const HIGHLIGHT = Color("ffe4a5")
const WARNING = Color("ffbc83")
const DIM = Color("0b130ea6")
const SHADOW = Color("101a14")

# Type scale in canvas units. Every label in the game uses one of these.
const SIZES = {"title": 28, "heading": 20, "body": 16, "caption": 13, "hud": 18, "button": 17}
const COLORS = {"title": TEXT, "heading": HIGHLIGHT, "body": TEXT, "caption": ACCENT, "muted": MUTED, "warning": WARNING, "hud": HIGHLIGHT}
const RADIUS = 10
const GAP = 12
const CONTROL_HEIGHT = 46

static var cached_theme: Theme

static func box(color: Color, border: Color = Color.TRANSPARENT, radius: int = RADIUS, pad: Vector2 = Vector2(16, 10)) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if border.a > 0:
		style.border_color = border
		style.set_border_width_all(1)
	style.content_margin_left = pad.x
	style.content_margin_right = pad.x
	style.content_margin_top = pad.y
	style.content_margin_bottom = pad.y
	return style

static func panel_style(color: Color = SURFACE, pad: Vector2 = Vector2(22, 18)) -> StyleBoxFlat:
	return box(color, Color.TRANSPARENT, 14, pad)

static func theme() -> Theme:
	if cached_theme != null:
		return cached_theme
	var t = Theme.new()
	t.default_font_size = SIZES.body
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	_button_kind(t, "Button", SURFACE_RAISED, LINE, TEXT, Color("34493c"))
	t.set_type_variation("PrimaryButton", "Button")
	_button_kind(t, "PrimaryButton", ACCENT, Color.TRANSPARENT, ON_ACCENT, ACCENT_HOVER, ACCENT_PRESSED)
	t.set_type_variation("GhostButton", "Button")
	_button_kind(t, "GhostButton", Color.TRANSPARENT, LINE, TEXT, Color("ffffff14"))
	t.set_type_variation("ToggleButton", "Button")
	_button_kind(t, "ToggleButton", SURFACE_SUNKEN, LINE, MUTED, Color("223229"))
	t.set_stylebox("pressed", "ToggleButton", box(ACCENT, Color.TRANSPARENT))
	t.set_color("font_pressed_color", "ToggleButton", ON_ACCENT)
	t.set_color("font_hover_pressed_color", "ToggleButton", ON_ACCENT)
	for state in ["normal", "focus", "read_only"]:
		t.set_stylebox(state, "LineEdit", box(SURFACE_SUNKEN, LINE if state != "focus" else ACCENT, RADIUS, Vector2(14, 8)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("font_uneditable_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", SIZES.button)
	t.set_stylebox("background", "ProgressBar", box(SURFACE_SUNKEN, Color.TRANSPARENT, 6, Vector2.ZERO))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 6, Vector2.ZERO))
	t.set_color("font_color", "ProgressBar", ON_ACCENT)
	t.set_stylebox("slider", "HSlider", box(SURFACE_SUNKEN, Color.TRANSPARENT, 4, Vector2(0, 3)))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, Color.TRANSPARENT, 4, Vector2(0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT_HOVER, Color.TRANSPARENT, 4, Vector2(0, 3)))
	cached_theme = t
	return t

static func _button_kind(t: Theme, kind: String, color: Color, border: Color, font: Color, hover: Color, pressed: Color = Color.TRANSPARENT) -> void:
	t.set_stylebox("normal", kind, box(color, border))
	t.set_stylebox("hover", kind, box(hover, border))
	t.set_stylebox("pressed", kind, box(pressed if pressed.a > 0 else hover, border))
	t.set_stylebox("focus", kind, StyleBoxEmpty.new())
	t.set_stylebox("disabled", kind, box(Color(color, color.a * 0.45), Color(border, border.a * 0.5)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, kind, font)
	t.set_color("font_disabled_color", kind, Color(font, 0.45))
	t.set_font_size("font_size", kind, SIZES.button)

static func label(parent: Node, text: String, role: String = "body") -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", SIZES.get(role, SIZES.body))
	l.add_theme_color_override("font_color", COLORS.get(role, TEXT))
	if parent != null:
		parent.add_child(l)
	return l

static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# kind: "primary" (one per screen), "secondary" (default) or "ghost".
static func button(parent: Node, text: String, kind: String = "secondary", height: float = CONTROL_HEIGHT) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = height
	b.focus_mode = Control.FOCUS_NONE
	if kind == "primary":
		b.theme_type_variation = "PrimaryButton"
	elif kind == "ghost":
		b.theme_type_variation = "GhostButton"
	elif kind == "toggle":
		b.theme_type_variation = "ToggleButton"
		b.toggle_mode = true
	if parent != null:
		parent.add_child(b)
	return b

static func vbox(parent: Node, separation: int = GAP) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	parent.add_child(v)
	return v

static func hbox(parent: Node, separation: int = GAP) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	parent.add_child(h)
	return h

static func card(parent: Node, color: Color = SURFACE_RAISED, pad: Vector2 = Vector2(14, 12)) -> PanelContainer:
	var c = PanelContainer.new()
	c.add_theme_stylebox_override("panel", panel_style(color, pad))
	parent.add_child(c)
	return c

static func expand(control: Control) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control

# Logo with the game name and "от Rally Fans Map" underneath.
static func brand(parent: Node, logo_size: float = 56) -> HBoxContainer:
	var row = hbox(parent, 14)
	row.name = "Brand"
	var logo = TextureRect.new()
	logo.name = "Logo"
	logo.texture = load(LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2.ONE * logo_size
	logo.tooltip_text = BRAND_NAME
	row.add_child(logo)
	var names = vbox(row, 0)
	names.name = "Names"
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var title = label(names, GAME_NAME, "title")
	title.name = "Title"
	title.add_theme_font_override("font", BRAND_FONT)
	var by = label(names, Loc.t("от %s") % BRAND_NAME, "muted")
	by.name = "Byline"
	by.add_theme_font_override("font", BRAND_FONT)
	return row

# A modal window: full-screen dim that swallows input, a panel centred in the
# safe area and a content column. Hide/show the returned root.
static func modal(layer: Control, name: String, width: float = 460) -> Dictionary:
	var root = Control.new()
	root.name = name
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center = CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size.x = width
	center.add_child(panel)
	var content = vbox(panel, 14)
	content.name = "Content"
	root.hide()
	return {"root": root, "panel": panel, "content": content}

# Opens a web page. In VK and other WebViews the call may be swallowed, so
# callers also offer the address to copy.
static func open_url(url: String) -> bool:
	return OS.shell_open(url) == OK
