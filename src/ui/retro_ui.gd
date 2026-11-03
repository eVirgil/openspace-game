class_name RetroUI
extends RefCounted
## Issue #52: the 80s HUD look. One phosphor colour (the player's favourite, set
## in F11 > HUD), a monospaced font, dark glass panels with a glowing rim. Text is
## the bold cut with a crisp dark edge and a tight glow in its own colour (a wide
## pale glow over a black outline fogged the letters: legible() says how).
##
## Nothing builds its UI differently for this: RetroSkin (one node in the town)
## calls skin() on every Control as it appears and again when the colour changes.
## skin() keeps colours that mean something (her lines, warnings) and only swaps
## the neutral ones (white, cream, grey) for the phosphor colour.
##
## Font: Anonymous Pro (SIL OFL, assets/fonts/OFL.txt).

const SETTINGS_PATH := "user://settings/ui.cfg"
const FONT_DIR := "res://assets/fonts/"
const PRESETS := {
	"Amber": Color("#ffb347"),
	"Phosphor green": Color("#4dff88"),
	"Cyan": Color("#3fe0ff"),
	"Magenta": Color("#ff4fd8"),
	"Red alert": Color("#ff5a4a"),
	"Ice white": Color("#dfefff"),
}
const DEFAULT := Color("#ffb347")
const PROMPT_SIZE := 34              ## "[E] Talk to ..." and the like
const UI_PATH := "res://content/look/ui.json"   ## issue #71: text_scale and the base font sizes

static var accent := DEFAULT
## Issue #71: the one number every UI element is sized by (the window's UI scale).
## F11 > HUD sets it; saved per machine with the colour.
static var text_scale := -1.0
static var _ui: Dictionary = {}
static var _loaded := false
static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


## The player's colour, read once from the settings file.
static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		accent = cfg.get_value("hud", "color", DEFAULT)
		text_scale = float(cfg.get_value("hud", "text_scale", -1.0))
	if text_scale <= 0.0:
		text_scale = float(ui().get("text_scale", 1.75))
	text_scale = clamp_scale(text_scale)


static func save_settings() -> void:
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("hud", "color", accent)
	cfg.set_value("hud", "text_scale", text_scale)
	cfg.save(SETTINGS_PATH)


# ------------------------------------------------------------------ size (issue #71)

static func ui() -> Dictionary:
	if _ui.is_empty():
		var f := FileAccess.open(UI_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_ui = d if d is Dictionary else {}
	return _ui


static func clamp_scale(v: float) -> float:
	return clampf(v, float(ui().get("min", 0.75)), float(ui().get("max", 2.0)))


## A base font size from content/look/ui.json ("dialogue_line", "flight_readout").
## The window's UI scale (text_scale) multiplies it on screen.
static func size(key: String, fallback: int) -> int:
	return int(ui().get("sizes", {}).get(key, fallback))


## Size every UI element in `tree` by text_scale. Not headless: the CI traces and
## tests measure the UI at 1.0.
static func apply_scale(tree: SceneTree) -> void:
	load_settings()
	if tree == null or DisplayServer.get_name() == "headless":
		return
	tree.root.content_scale_factor = text_scale


static func set_text_scale(tree: SceneTree, v: float) -> void:
	load_settings()
	text_scale = clamp_scale(v)
	save_settings()
	apply_scale(tree)


static func font(style: String = "Regular") -> Font:
	if not _fonts.has(style):
		var path := FONT_DIR + "AnonymousPro-%s.ttf" % style
		_fonts[style] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[style]


## Dark glass with a glowing rim in the phosphor colour.
static func box(fill_alpha: float = 0.9, rim: int = 2, pad: float = 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.darkened(0.92), fill_alpha)
	sb.border_color = accent
	sb.set_border_width_all(rim)
	sb.shadow_color = Color(accent, 0.25)
	sb.shadow_size = 6
	sb.set_content_margin_all(pad)
	return sb


static func _fill(c: Color, pad: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_content_margin_all(pad)
	return sb


## White, cream, grey: the colours that only meant "text". Coloured text keeps
## its colour (it says who is speaking, or that something is wrong).
static func is_neutral(c: Color) -> bool:
	return c.s < 0.3 and c.v > 0.55


## A big glowing interaction prompt ("[E] Ride speeder"). Widens the label so the
## bigger text still fits; they are all centred, so the centre does not move.
static func prompt(l: Label) -> void:
	l.set_meta("retro_prompt", true)
	l.add_theme_font_size_override("font_size", PROMPT_SIZE)
	l.offset_left -= 260.0
	l.offset_right += 260.0
	l.autowrap_mode = TextServer.AUTOWRAP_OFF


## Restyle one Control. Safe to call again (a colour change re-skins everything).
static func skin(c: Control) -> void:
	if c.has_meta("retro_off"):
		return
	var a := accent
	var bright := a.lightened(0.45)
	if c is RichTextLabel:
		for k in ["normal_font", "mono_font", "bold_font", "bold_italics_font"]:
			c.add_theme_font_override(k, font("Bold"))
		c.add_theme_font_override("italics_font", font("Italic"))
		_tint(c, "default_color", bright)
		legible(c, c.get_theme_color("default_color"), c.get_theme_font_size("normal_font_size"))
	elif c is Label:
		c.add_theme_font_override("font", font("Bold"))
		_tint(c, "font_color", a)
		legible(c, c.get_theme_color("font_color"), c.get_theme_font_size("font_size"))
	elif c is CheckBox or c is CheckButton:
		c.add_theme_font_override("font", font("Bold"))
		if c is CheckBox:
			for k in ["unchecked", "checked", "unchecked_disabled", "checked_disabled",
					"radio_unchecked", "radio_checked", "radio_unchecked_disabled", "radio_checked_disabled"]:
				c.add_theme_icon_override(k, check_icon(k))
		for k in ["font_color", "font_focus_color", "font_pressed_color"]:
			c.add_theme_color_override(k, a)
		c.add_theme_color_override("font_hover_color", bright)
		c.add_theme_color_override("font_hover_pressed_color", bright)
	elif c is Button:
		c.add_theme_font_override("font", font("Bold"))
		var normal := box(0.85, 1, 6.0)
		var hover := box(0.95, 2, 6.0)
		hover.bg_color = Color(a.darkened(0.6), 0.95)
		var pressed := _fill(a, 6.0)
		c.add_theme_stylebox_override("normal", normal)
		c.add_theme_stylebox_override("hover", hover)
		c.add_theme_stylebox_override("pressed", pressed)
		c.add_theme_stylebox_override("hover_pressed", pressed)
		c.add_theme_stylebox_override("focus", box(0.0, 2, 6.0))
		c.add_theme_stylebox_override("disabled", box(0.5, 1, 6.0))
		for k in ["font_color", "font_focus_color"]:
			c.add_theme_color_override(k, a)
		c.add_theme_color_override("font_hover_color", bright)
		c.add_theme_color_override("font_pressed_color", Color.BLACK)
		c.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
	elif c is LineEdit or c is TextEdit:
		c.add_theme_font_override("font", font())
		c.add_theme_stylebox_override("normal", box(0.92, 1, 8.0))
		c.add_theme_stylebox_override("focus", box(0.0, 2, 8.0))
		c.add_theme_stylebox_override("read_only", box(0.6, 1, 8.0))
		_tint(c, "font_color", bright)
		c.add_theme_color_override("caret_color", a)
		c.add_theme_color_override("selection_color", Color(a, 0.35))
		c.add_theme_color_override("font_placeholder_color", Color(a, 0.45))
	elif c is ProgressBar:
		c.add_theme_stylebox_override("background", box(0.8, 1, 0.0))
		c.add_theme_stylebox_override("fill", _fill(a, 0.0))
		c.add_theme_font_override("font", font())
	elif c is Slider:
		var track := box(0.9, 1, 0.0)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		c.add_theme_stylebox_override("slider", track)
		c.add_theme_stylebox_override("grabber_area", _fill(a, 3.0))
		c.add_theme_stylebox_override("grabber_area_highlight", _fill(bright, 3.0))
	elif c is TabContainer or c is TabBar:
		c.add_theme_font_override("font", font("Bold"))
		c.add_theme_stylebox_override("tab_selected", _fill(Color(a.darkened(0.55), 0.95), 8.0))
		c.add_theme_stylebox_override("tab_unselected", box(0.85, 1, 8.0))
		c.add_theme_stylebox_override("tab_hovered", box(0.95, 2, 8.0))
		c.add_theme_stylebox_override("panel", box(0.6, 1, 10.0))
		c.add_theme_color_override("font_selected_color", bright)
		c.add_theme_color_override("font_unselected_color", a.darkened(0.25))
		c.add_theme_color_override("font_hovered_color", bright)
	elif c is PanelContainer or c is Panel:
		var old := c.get_theme_stylebox("panel") if c.has_theme_stylebox_override("panel") else null
		if old is StyleBoxEmpty:
			return                       # a layout box, not a panel
		if old is StyleBoxFlat and old.bg_color.a < 0.05 and old.border_width_left == 0:
			return                       # see-through on purpose
		var pad := 12.0
		var alpha := 0.9
		if old is StyleBoxFlat:
			pad = maxf(old.content_margin_left, 0.0)
			alpha = clampf(old.bg_color.a, 0.75, 0.97)
		var sb := box(alpha, 2, pad)
		if old != null:
			for side in ["left", "right", "top", "bottom"]:
				sb.set("content_margin_" + side, old.get("content_margin_" + side))
		c.add_theme_stylebox_override("panel", sb)


## A checkbox's box. The default one is dark and vanishes on the dark glass, so
## an empty box is white, and a ticked one is the phosphor colour with a dark tick.
## SVG, so it stays sharp at any UI scale.
static func check_icon(key: String) -> Texture2D:
	var id := "%s_%s" % [key, accent.to_html()]
	if _icons.has(id):
		return _icons[id]
	var on := not key.contains("unchecked")
	var off_alpha := 0.45 if key.ends_with("_disabled") else 1.0
	var rim := accent.darkened(0.6).to_html(false)
	var fill := accent.to_html(false) if on else "ffffff"
	var shape := '<circle cx="9" cy="9" r="7.5"' if key.begins_with("radio") \
			else '<rect x="1.5" y="1.5" width="15" height="15" rx="2"'
	var mark := ""
	if on:
		mark = '<circle cx="9" cy="9" r="3.5" fill="#000"/>' if key.begins_with("radio") \
				else '<path d="M4.5 9.5l3 3 6-7" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><g opacity="%s">'
			+ '%s fill="#%s" stroke="#%s" stroke-width="1.5"/>%s</g></svg>') % [off_alpha, shape, fill, rim, mark]
	var tex := DPITexture.create_from_string(svg)
	_icons[id] = tex
	return tex


## Text that reads on anything: a dark edge right round each letter (the text's
## own colour, nearly black), and outside it a tight glow in that colour. Both
## scale with the font size, so small print is not swamped.
static func legible(c: Control, col: Color, font_size: int) -> void:
	var fs := maxi(font_size, 8)
	c.add_theme_color_override("font_outline_color", Color(col.darkened(0.88), 1.0))
	c.add_theme_constant_override("outline_size", clampi(roundi(fs * 0.22), 2, 6))
	c.add_theme_color_override("font_shadow_color", Color(col, 0.22))
	c.add_theme_constant_override("shadow_offset_x", 0)
	c.add_theme_constant_override("shadow_offset_y", 0)
	c.add_theme_constant_override("shadow_outline_size", clampi(roundi(fs * 0.42), 4, 12))


## Swap a neutral colour for the phosphor one (and remember that we did, so a
## later colour change swaps it again).
static func _tint(c: Control, key: String, to: Color) -> void:
	if c.has_meta("retro_tint_" + key) or not c.has_theme_color_override(key) \
			or is_neutral(c.get_theme_color(key)):
		c.set_meta("retro_tint_" + key, true)
		c.add_theme_color_override(key, to)


## Text bars: "[||||||||....]" (ASCII, so every font has the glyphs).
static func bar(frac: float, cells: int = 12) -> String:
	var n := clampi(roundi(clampf(frac, 0.0, 1.0) * cells), 0, cells)
	return "[" + "|".repeat(n) + ".".repeat(cells - n) + "]"
