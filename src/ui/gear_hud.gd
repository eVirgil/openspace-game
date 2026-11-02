class_name GearHud
extends CanvasLayer
## Gear HUD (M13): an interaction prompt ("[E] Pick up Jetpack") and a short
## toast. No game logic: GearController sets what it shows. Jetpack fuel lives in
## the RetroHud footer.

const INK := Color(0.95, 0.92, 0.85, 0.95)

var prompt: Label
var toast_label: Label
var _toast_left := 0.0
var _queued: Array = []          ## [{ text, secs }] tips waiting for the toast on screen to finish


func _init() -> void:
	name = "GearHud"
	layer = 4


func _ready() -> void:
	prompt = _label(-210.0)
	RetroUI.prompt(prompt)
	toast_label = _label(-250.0)
	toast_label.visible = false


func _label(from_bottom: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-300, from_bottom)
	l.size = Vector2(600, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_prompt(text: String) -> void:
	if prompt != null:
		prompt.text = text
		prompt.visible = text != ""


func toast(text: String, secs: float = 3.0) -> void:
	if toast_label == null or text == "":
		return
	_queued.clear()
	_show(text, secs)


## A tip that follows the toast on screen (a pickup, then what to press); with none
## up it shows at once. A fresh toast() drops whatever was waiting.
func toast_after(text: String, secs: float = 4.0) -> void:
	if toast_label == null or text == "":
		return
	if _toast_left > 0.0:
		_queued.append({ "text": text, "secs": secs })
	else:
		_show(text, secs)


func _show(text: String, secs: float) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_left = secs


func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			if _queued.is_empty():
				toast_label.visible = false
			else:
				var next: Dictionary = _queued.pop_front()
				_show(str(next.text), float(next.secs))
