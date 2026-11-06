class_name CheckpointHud
extends CanvasLayer
## The gate checkpoint's screen bits (M15): what a guard just said (a subtitle),
## the choice card (Show papers / Bribe / Mouth off / Walk away, also on keys 1-4
## while it is open), the player's health bar (only while hurt), and the knockout
## fade. No game logic: Garrison tells it what to show and hears the pick.

signal chosen(choice_id: String)

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const HP := Color(0.85, 0.32, 0.25, 0.95)
const TRACK := Color(0.08, 0.07, 0.06, 0.6)

var subtitle: Label
var card: PanelContainer
var card_title: Label
var card_box: VBoxContainer
var fade: ColorRect
var toast_label: Label
var hp_bar: Control
var hp := 1.0
var hp_visible_left := 0.0
var choices: Array = []
var _sub_left := 0.0
var _toast_left := 0.0
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	name = "CheckpointHud"
	layer = 6


func _ready() -> void:
	subtitle = _label(Control.PRESET_CENTER_BOTTOM, -118.0, 22)
	subtitle.visible = false
	toast_label = _label(Control.PRESET_CENTER_TOP, ObjectiveHud.BELOW + 6.0, 20)   # under the objective arrow
	toast_label.visible = false

	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.offset_left = -230
	card.offset_right = 230
	card.offset_top = -330
	card.offset_bottom = -140
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.86)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	card.visible = false
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	card_title = Label.new()
	card_title.add_theme_font_size_override("font_size", 19)
	card_title.add_theme_color_override("font_color", AMBER)
	v.add_child(card_title)
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 4)
	v.add_child(card_box)

	hp_bar = Control.new()
	hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_bar.position = Vector2(24, -46)
	hp_bar.size = Vector2(220, 18)
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.visible = false
	hp_bar.draw.connect(_draw_hp)
	add_child(hp_bar)

	fade = ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


func _label(preset: int, y: float, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.offset_left = -420
	l.offset_right = 420
	l.offset_top = y
	l.offset_bottom = y + 34
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func say(who: String, text: String, seconds: float = 3.0) -> void:
	subtitle.text = "%s:  %s" % [who.to_upper(), text]
	subtitle.visible = true
	_sub_left = seconds


func toast(text: String, seconds: float = 3.0) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_left = seconds


func show_card(title: String, list: Array) -> void:
	choices = list
	card_title.text = title
	for ch in card_box.get_children():
		ch.queue_free()
	for i in list.size():
		var c: Dictionary = list[i]
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, str(c.label)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not bool(c.get("enabled", true))
		b.focus_mode = Control.FOCUS_NONE
		var id := str(c.id)
		b.pressed.connect(func(): chosen.emit(id))
		card_box.add_child(b)
	if not card.visible:
		_mouse_before = Input.mouse_mode
	card.visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_card() -> void:
	if not card.visible:
		return
	card.visible = false
	choices = []
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_before


## Keys 1-4 pick while the card is open. _input runs before the weapons'
## _unhandled_input, so 1/2/3 do not also swap guns.
func _input(event: InputEvent) -> void:
	if not card.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).keycode
	var i := k - KEY_1
	if i >= 0 and i < choices.size():
		if bool(choices[i].get("enabled", true)):
			chosen.emit(str(choices[i].id))
		get_viewport().set_input_as_handled()


func set_hp(frac: float, hurt: bool) -> void:
	hp = clampf(frac, 0.0, 1.0)
	if hurt:
		hp_visible_left = 4.0
	# Issue #80: the 80s HUD's footer is the health bar; this red one only stands in
	# when that HUD is off (the CI greybox), never both in the same spot.
	hp_bar.visible = RetroSkin.current == null and (hp < 0.999 or hp_visible_left > 0.0)
	hp_bar.queue_redraw()


func _draw_hp() -> void:
	var r := Rect2(Vector2.ZERO, hp_bar.size)
	hp_bar.draw_rect(r, TRACK)
	hp_bar.draw_rect(Rect2(Vector2(2, 2), Vector2((hp_bar.size.x - 4) * hp, hp_bar.size.y - 4)), HP)


func _process(dt: float) -> void:
	if _sub_left > 0.0:
		_sub_left -= dt
		if _sub_left <= 0.0:
			subtitle.visible = false
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			toast_label.visible = false
	hp_visible_left = maxf(0.0, hp_visible_left - dt)
