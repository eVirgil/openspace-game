class_name WeaponWheelView
extends Control
## Draws a WeaponWheel (issue #410): eight wedges round the middle of the screen,
## the one under the pointer lit, the weapon in hand marked, empty ones dimmed.
## No logic: PlayerWeapons owns the wheel and tells this what to say about an id.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const ICON_DIR := "res://assets/ui/weapon_icons/"      ## white silhouettes, tools/lookdev/weapon_icons.gd
const ICON_BOX := Vector2(104, 42)                       ## the most an icon takes of a slot

var wheel: WeaponWheel
var info: Callable = Callable()     ## (id) -> { name: String, detail: String }
var current_id := ""
var radius := 230.0
var inner := 80.0
var gap := 0.045                    ## radians left between wedges
var _icons: Dictionary = {}         ## id -> Texture2D, or null when there is none


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
			col = Color(0.66, 0.44, 0.17, 0.94)         # dark enough for white ink
		elif i == hot:
			col = Color(0.35, 0.18, 0.16, 0.7)
		var a0 := step * i - step * 0.5 + gap
		var a1 := step * i + step * 0.5 - gap
		draw_colored_polygon(_wedge(mid, a0, a1), col)
		if id == current_id and id != "":
			draw_polyline(_arc(mid, radius - 3.0, a0, a1), AMBER, 3.0)
		var at := mid + WeaponWheel.slot_dir(i) * (inner + radius) * 0.5
		var text_col := INK if live else Color(INK, 0.3)
		_text(font, str(i + 1), at + Vector2(0, -56), 14, text_col)
		if id != "":
			var d: Dictionary = info.call(id) if info.is_valid() else {}
			_icon(id, at + Vector2(0, -28), Color.WHITE if live else Color(1, 1, 1, 0.3))
			_text(font, str(d.get("name", id)), at + Vector2(0, 12), 14, text_col)
			var det := str(d.get("detail", ""))
			if det != "":
				_text(font, det, at + Vector2(0, 30), 13, text_col)
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


## A weapon's silhouette, fitted into ICON_BOX round `centre`.
func _icon(id: String, centre: Vector2, tint: Color) -> void:
	if not _icons.has(id):
		var path := ICON_DIR + id + ".png"
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	var tex: Texture2D = _icons[id]
	if tex == null:
		return
	var sz := tex.get_size()
	var k := minf(ICON_BOX.x / sz.x, ICON_BOX.y / sz.y)
	var box := sz * k
	draw_texture_rect(tex, Rect2(centre - box * 0.5, box), false, tint)


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
