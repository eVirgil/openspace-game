class_name TutorialCard
extends CanvasLayer
## T-89's tutorial page (issue #58): a small card at the side of the screen, not a
## menu. Nothing is locked while it is up: you walk, jump and try the thing it
## describes. Enter turns the page, Backspace ends the tutorial (Esc is the
## mouse's, so it is left alone). ShipSalesman owns the pages and when to drop it.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const CARD_W := 300.0              ## narrower on a small screen
const MARGIN := 24.0               ## from the left edge
const PAD := 10.0                  ## between the card's edge and its text

var panel: PanelContainer
var title_label: Label
var body_label: Label
var hint_label: Label
signal next_pressed
signal end_pressed


func _init() -> void:
	name = "TutorialCard"
	layer = 7


func _ready() -> void:
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, int(PAD))
	panel.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	pad.add_child(box)
	title_label = _label(15, AMBER)
	body_label = _label(14, INK)
	hint_label = _label(12, Color(INK, 0.6))
	box.add_child(title_label)
	box.add_child(body_label)
	box.add_child(hint_label)
	panel.visible = false
	panel.minimum_size_changed.connect(_refit)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func is_open() -> bool:
	return panel != null and panel.visible


## Put a page up: the title line, the page, and the keys line.
func show_page(title: String, body: String, hint: String) -> void:
	if panel == null:
		return
	title_label.text = title
	body_label.text = body
	hint_label.text = hint
	_fit()
	panel.visible = true


func close() -> void:
	if panel != null:
		panel.visible = false


## The page's height is only known once the labels have wrapped at the card's
## width (and RetroSkin has swapped the font in), which can take more than one
## layout pass; until then the panel measures each label one word to a line, and
## a card sized from that is taller than the screen with its text off the top.
## So fit again every time the panel's minimum size changes.
func _refit() -> void:
	if is_open():
		_fit.call_deferred()


## Size to the screen: a fixed width on the left edge, as tall as the page needs,
## and narrower when the screen is small (a big text size).
func _fit() -> void:
	if panel == null:
		return
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var w := minf(CARD_W, vp.x * 0.4)
	panel.offset_left = MARGIN
	panel.offset_right = MARGIN + w
	for l in [title_label, body_label, hint_label]:
		l.custom_minimum_size.x = w - 2.0 * PAD
		l.size.x = w - 2.0 * PAD     # wrap at this width now, not after the next layout pass
	panel.reset_size()
	var h := panel.get_combined_minimum_size().y
	panel.offset_top = -h * 0.5
	panel.offset_bottom = h * 0.5


## _input, not _unhandled_input: a focused Control would otherwise take Enter first.
func _input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k in [KEY_ENTER, KEY_KP_ENTER]:
		next_pressed.emit()
		get_viewport().set_input_as_handled()
	elif k == KEY_BACKSPACE:
		end_pressed.emit()
		get_viewport().set_input_as_handled()
