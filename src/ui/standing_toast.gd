class_name StandingToast
extends Control
## The standing toast (StandingNews): when a faction's standing moves, a small
## panel high on the screen, under the top banner, reads "Remnant standing +10", the change green
## for up and red for down, over a gauge from -100 to +100. The gauge has a tick
## every 25, and a finer tick for every point the standing moved, drawn in the
## change's colour as the marker sweeps from where it was to where it is.
## Each faction has its own row (the Remnant and the locals; the smugglers
## are not shown), so a fight that moves both shows two side by side; a second change to a faction whose row is still up adds to
## it and holds it a while longer. Under the arrival titles' line, over the
## world, never takes the mouse.

const GREEN := Color("#6fd16f")
const RED := Color("#e0584f")
const INK := Color(0.95, 0.92, 0.85, 0.95)
const BAND := Color(0.05, 0.04, 0.03, 0.6)
const EDGE := Color(0.88, 0.63, 0.31, 0.6)
const Y := 0.07                        ## the stack's top, as a share of the screen's height: just under the top banner
const IN := 0.15                       ## seconds to come up
const HOLD := 2.6                      ## seconds fully up
const OUT := 0.45                      ## seconds to fade
const SWEEP := 0.6                     ## seconds the marker takes to move
const GAUGE := Vector2(250, 16)

var stack: HBoxContainer
var rows: Dictionary = {}              ## faction -> Row


func _init() -> void:
	name = "StandingToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	stack = HBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 6)
	add_child(stack)


func _process(dt: float) -> void:
	for e in StandingNews.take_all():
		show_change(str(e.faction), int(e.from), int(e.to))
	for f in rows.keys():
		var r: Row = rows[f]
		r.tick(dt)
		if r.done():
			rows.erase(f)
			stack.remove_child(r)
			r.queue_free()
	_place()


## Put a change of `faction`'s standing up now. Its row, if still up, takes it on.
func show_change(faction: String, from_v: int, to_v: int) -> void:
	if from_v == to_v:
		return
	if rows.has(faction):
		rows[faction].add(to_v)
		return
	var r := Row.new(faction, from_v, to_v)
	rows[faction] = r
	stack.add_child(r)


func _place() -> void:
	var view := get_viewport_rect().size
	stack.reset_size()
	var sz := stack.get_combined_minimum_size()
	stack.size = sz
	stack.position = Vector2((view.x - sz.x) * 0.5, maxf(view.y * Y, ObjectiveHud.BELOW))  # under the objective arrow


## One faction's panel: "Remnant standing" and the change, over the gauge.
class Row extends PanelContainer:
	var faction: String
	var from_v: int                     ## where the standing was when the row came up
	var to_v: int                       ## where it is now
	var shown := 0.0                    ## where the marker is, on its way to to_v
	var title: Label
	var amount: Label
	var gauge: Control
	var _t := 0.0                       ## seconds since it came up, or since the last change

	func _init(f: String, from_value: int, to_value: int) -> void:
		faction = f
		from_v = from_value
		to_v = to_value
		shown = float(from_value)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = StandingToast.BAND
		sb.border_color = StandingToast.EDGE
		sb.set_border_width_all(1)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 4
		sb.content_margin_bottom = 6
		add_theme_stylebox_override("panel", sb)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		add_child(box)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		box.add_child(line)
		title = _label(18, StandingToast.INK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		amount = _label(20, StandingToast.GREEN)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(title)
		line.add_child(amount)
		gauge = Control.new()
		gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gauge.custom_minimum_size = GAUGE
		gauge.draw.connect(_draw_gauge)
		box.add_child(gauge)
		modulate.a = 0.0
		_paint()

	func _label(size: int, color: Color) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		return l

	## The standing moved again while the row is up: the change adds to it.
	func add(new_to: int) -> void:
		to_v = new_to
		_t = StandingToast.IN
		_paint()

	## The change so far, new standing minus the standing when the row came up.
	func delta() -> int:
		return to_v - from_v

	func tick(dt: float) -> void:
		_t += dt
		var a := 1.0
		if _t < StandingToast.IN:
			a = _t / StandingToast.IN
		elif _t > StandingToast.IN + StandingToast.HOLD:
			a = 1.0 - (_t - StandingToast.IN - StandingToast.HOLD) / StandingToast.OUT
		modulate.a = clampf(a, 0.0, 1.0)
		shown = move_toward(shown, float(to_v), absf(float(to_v - from_v)) / StandingToast.SWEEP * dt + 0.001)
		gauge.queue_redraw()

	func done() -> bool:
		return _t >= StandingToast.IN + StandingToast.HOLD + StandingToast.OUT

	func _paint() -> void:
		title.text = "%s standing" % StandingNews.faction_name(faction)
		amount.text = "%+d" % delta()
		amount.add_theme_color_override("font_color", change_color())

	func change_color() -> Color:
		return StandingToast.GREEN if delta() >= 0 else StandingToast.RED

	func _x(v: float) -> float:
		return (v + 100.0) / 200.0 * StandingToast.GAUGE.x

	func _draw_gauge() -> void:
		var w := StandingToast.GAUGE.x
		var mid := StandingToast.GAUGE.y * 0.5
		gauge.draw_rect(Rect2(0, mid - 3, w, 6), Color(1, 1, 1, 0.12))
		# a tick every 25, the middle one (neutral) taller
		for v in range(-100, 101, 25):
			var h := 8.0 if v == 0 else 5.0
			gauge.draw_line(Vector2(_x(v), mid - h), Vector2(_x(v), mid + h), Color(StandingToast.INK, 0.55), 1.0)
		# a fine tick for every point the standing has moved so far, in the change's colour
		var c := change_color()
		var step := 1 if to_v >= from_v else -1
		var v := from_v
		while v != to_v and (v < shown if step > 0 else v > shown):
			v += step
			gauge.draw_line(Vector2(_x(v), mid - 3), Vector2(_x(v), mid + 3), c, 1.0)
		gauge.draw_rect(Rect2(minf(_x(from_v), _x(shown)), mid - 3, absf(_x(shown) - _x(from_v)), 6), Color(c, 0.35))
		# the marker
		var mx := _x(shown)
		gauge.draw_rect(Rect2(mx - 2, mid - 10, 4, 20), Color.WHITE)
		gauge.draw_rect(Rect2(mx - 3, mid - 11, 6, 22), c, false, 1.0)
