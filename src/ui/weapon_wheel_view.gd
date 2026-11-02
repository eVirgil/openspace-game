class_name WeaponWheelView
extends Control
## Draws a WeaponWheel (issue #410): eight wedges round the middle of the screen,
## the one under the pointer lit, the weapon in hand marked, empty ones dimmed.
## No logic: PlayerWeapons owns the wheel and tells this what to say about an id.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")

var wheel: WeaponWheel
var info: Callable = Callable()     ## (id) -> { name: String, detail: String }
var current_id := ""
var radius := 190.0
var inner := 70.0
var gap := 0.045                    ## radians left between wedges


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_dt: float) -> void:
	visible = wheel != null and wheel.is_open
	if visible:
		queue_redraw()


func _draw() -> void:
	if wheel == null or not wheel.is_open:
		return
	var mid := get_viewport_rect().size * 0.5      # the screen's middle, whatever the anchors have settled to
	var font := ThemeDB.fallback_font
	var step := TAU / WeaponWheel.SLOTS
	var hot := wheel.highlighted()
	draw_circle(mid, radius + 10.0, Color(0, 0, 0, 0.35))
	for i in WeaponWheel.SLOTS:
		var id := wheel.id_at(i)
		var live := wheel.selectable(i)
		var col := Color(0.12, 0.1, 0.08, 0.55)
		if live:
			col = Color(0.3, 0.22, 0.12, 0.8)
		if i == hot and live:
			col = Color(0.88, 0.63, 0.31, 0.92)
		elif i == hot:
			col = Color(0.35, 0.18, 0.16, 0.7)
		var a0 := step * i - step * 0.5 + gap
		var a1 := step * i + step * 0.5 - gap
		draw_colored_polygon(_wedge(mid, a0, a1), col)
		if id == current_id and id != "":
			draw_polyline(_arc(mid, radius - 3.0, a0, a1), AMBER, 3.0)
		var at := mid + WeaponWheel.slot_dir(i) * (inner + radius) * 0.5
		var text_col := INK if live else Color(INK, 0.3)
		if i == hot and live:
			text_col = Color(0.1, 0.07, 0.04)
		_text(font, str(i + 1), at + Vector2(0, -16), 15, text_col)
		if id != "":
			var d: Dictionary = info.call(id) if info.is_valid() else {}
			_text(font, str(d.get("name", id)), at + Vector2(0, 6), 14, text_col)
			var det := str(d.get("detail", ""))
			if det != "":
				_text(font, det, at + Vector2(0, 24), 13, text_col)
	# The middle: what letting go would do.
	draw_circle(mid, inner - 8.0, Color(0, 0, 0, 0.5))
	var pick := wheel.choice()
	var shown := pick if pick != "" else current_id
	var line := "Keep" if pick == "" else "Draw"
	_text(font, line, mid + Vector2(0, -8), 14, AMBER)
	var name := "Hands free"
	if shown != "" and info.is_valid():
		name = str((info.call(shown) as Dictionary).get("name", shown))
	_text(font, name, mid + Vector2(0, 12), 14, INK)
	# The pointer.
	draw_circle(mid + wheel.pointer * (inner - 20.0), 5.0, AMBER)


func _wedge(mid: Vector2, a0: float, a1: float) -> PackedVector2Array:
	var pts := _arc(mid, radius, a0, a1)
	var back := _arc(mid, inner, a0, a1)
	back.reverse()
	pts.append_array(back)
	return pts


func _arc(mid: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 8
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		pts.append(mid + Vector2(sin(a), -cos(a)) * r)
	return pts


func _text(font: Font, text: String, centre: Vector2, fsize: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := centre - Vector2(w * 0.5, 0)
	if col.v > 0.4:          # light ink gets a dark edge; dark ink on the lit wedge needs none
		draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.6))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
