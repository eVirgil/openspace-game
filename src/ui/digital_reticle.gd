extends Control
## The sniper rifle's scope reticle, drawn on screen (its 3D scope has none:
## hand_weapons scope "digital"). Aimed in, the screen centre is the scope's centre
## line, so this lands where the scope's own reticle would. A display, not etched
## glass: dashed arms in hard pixels with range ticks, corner brackets round a
## centre dot, and readouts for the range to the target and the zoom. No logic:
## PlayerWeapons sets the numbers each frame.

var color := Color("#ff3a1e")
var reach := 120.0                  ## pixels from the centre to the end of an arm
var meters := -1.0                  ## range to what is under the centre; < 0 = nothing
var mag := 2.5
var _font: SystemFont


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE


## An axis-aligned bar snapped to whole pixels, with a soft glow round it.
func _bar(r: Rect2) -> void:
	r = Rect2(r.position.round(), r.size.round().max(Vector2.ONE))
	draw_rect(r.grow(1.5), Color(color, 0.18))
	draw_rect(r, color)


## A bar along axis `d` (a unit axis vector) from `from` to `from + length` past
## `at`, `t` thick across it.
func _segment(at: Vector2, d: Vector2, from: float, length: float, t: float) -> void:
	var a := at + d * from
	var b := at + d * (from + length)
	var lo := a.min(b)
	if absf(d.x) > 0.5:
		_bar(Rect2(lo.x, lo.y - t * 0.5, absf(b.x - a.x), t))
	else:
		_bar(Rect2(lo.x - t * 0.5, lo.y, t, absf(b.y - a.y)))


func _draw() -> void:
	var mid := (get_viewport_rect().size * 0.5).round()
	var t := maxf(2.0, round(reach / 70.0))         # line thickness
	var gap := reach * 0.16
	var dash := maxf(4.0, reach * 0.07)
	# Arms: dashes from the gap out to the reach, a tick across every quarter of it.
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var along := gap
		while along < reach:
			_segment(mid, d, along, minf(dash, reach - along), t)
			along += dash * 1.6
		for k in range(1, 5):
			var p: Vector2 = mid + d * lerpf(gap, reach, k / 4.0)
			var tick := reach * (0.07 if k % 2 == 0 else 0.04)
			_segment(p, Vector2(d.y, d.x), -tick, tick * 2.0, t)
	# Corner brackets round the centre and the dot in it.
	var bx := gap * 0.7
	var arm := gap * 0.32
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := mid + Vector2(sx, sy) * bx
			_bar(Rect2(Vector2(minf(c.x, c.x - sx * arm), c.y - t * 0.5), Vector2(arm, t)))
			_bar(Rect2(Vector2(c.x - t * 0.5, minf(c.y, c.y - sy * arm)), Vector2(t, arm)))
	_bar(Rect2(mid - Vector2(t, t), Vector2(t, t) * 2.0))
	# Readouts: the range under the lower right bracket, the zoom under the left.
	var size_px := int(clampf(reach * 0.13, 14.0, 34.0))
	var range_text := "---- M" if meters < 0.0 else "%04d M" % int(round(meters))
	var at := mid + Vector2(bx + arm * 0.2, bx + size_px * 1.4)
	draw_string_outline(_font, at, range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.55))
	draw_string(_font, at, range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
	var zoom_text := "%.1fX" % mag
	var w := _font.get_string_size(zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var zat := mid + Vector2(-bx - arm * 0.2 - w, bx + size_px * 1.4)
	draw_string_outline(_font, zat, zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.55))
	draw_string(_font, zat, zoom_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(color, 0.8))
