class_name SystemView
extends Control
## The F11 Map page's system view: every planet you can get to, seen from above
## (map -z up, as the globe's port faces you), each where it really hangs
## (GlobeMap.system: one frame for them all, the home planet's), drawn its true
## size against the distances, with a faint orbit round the planet it is near.
## The Remnant cruiser too, over its planet. You show as on the globe (a green
## triangle pointing the way you look), wherever you are: on a planet, in its
## sky or out between them; the other LAN players as blue dots.
##
## Hover names a planet (its kind, and how far it is from you); a click opens its
## own map (`body_clicked`, "cruiser" for the cruiser). The planet the waypoint
## leads to has the waypoint's ring. Drag moves the chart, the wheel or the + / -
## buttons zoom. Colours: content/look/map.json "system".

signal body_clicked(id: String)

const ZOOM_MIN := 1.0
const ZOOM_MAX := 40.0
const ZOOM_STEP := 1.25
const BUTTON_STEP := 2.0
const HIT := 8.0                         ## px past a planet's disc a click still counts
const DRAG := 4.0
const MARGIN := 34.0                     ## px kept clear round the fitted chart (the names under the edge planets)

var bodies: Array = []                  ## GlobeMap.system
var cruiser := Vector3.INF              ## the Remnant cruiser (system frame), INF = none
var cruiser_label := ""
var player := Vector3.INF               ## you (system frame), INF = not known
var heading := Vector2.ZERO             ## the way you look, (x, z) in the system frame (ZERO = none)
var others: Array = []                  ## LAN: the other players, [{ id, pos (system frame), name }]
var goal := ""                          ## the planet id the waypoint leads to, "cruiser", or ""
var here := ""                          ## the planet whose scene you are in
var pan := Vector2.ZERO                 ## the chart's (x, z) at the view's centre, metres
var zoom := 1.0
var hover := ""                         ## the body under the mouse ("cruiser" too), "" = none

var _press := Vector2.INF
var _dragged := false
var _stars: PackedVector3Array = PackedVector3Array()   ## (x, y) 0..1 across the view, z brightness


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(220, 220)
	var zb := VBoxContainer.new()
	zb.position = Vector2(8, 8)
	zb.add_theme_constant_override("separation", 4)
	add_child(zb)
	for z in [["+", BUTTON_STEP], ["-", 1.0 / BUTTON_STEP]]:
		var b := Button.new()
		b.name = "ZoomIn" if z[0] == "+" else "ZoomOut"
		b.text = z[0]
		b.custom_minimum_size = Vector2(28, 28)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): set_zoom(zoom * z[1]))
		zb.add_child(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in int(look().get("stars", 160)):
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.25, 1.0)))


func _process(_dt: float) -> void:
	if is_visible_in_tree() and (player != Vector3.INF or goal != "" or not others.is_empty()):
		queue_redraw()


static func look() -> Dictionary:
	return GlobeMap.look().get("system", {})


# ------------------------------------------------------------------ the frame

## The box (x, z) every planet (with its ring) and the cruiser fit in.
func extents() -> Rect2:
	var box := Rect2()
	var first := true
	for b in bodies:
		var c := Vector2((b.centre as Vector3).x, (b.centre as Vector3).z)
		var r := float(b.radius) * maxf(1.0, float((b.ring as Dictionary).get("outer", 1.0)))
		var bb := Rect2(c - Vector2.ONE * r, Vector2.ONE * r * 2.0)
		box = bb if first else box.merge(bb)
		first = false
	if cruiser != Vector3.INF:
		box = box.expand(Vector2(cruiser.x, cruiser.z))
	return box


## The chart's centre with nothing moved: the middle of extents().
func home_pan() -> Vector2:
	return extents().get_center()


## Pixels per metre.
func scale_px() -> float:
	var e := extents()
	var half := maxf(maxf(e.size.x, e.size.y) * 0.5, 1.0)
	return maxf(minf(size.x, size.y) * 0.5 - MARGIN, 10.0) / half * zoom


## Screen position of a point in the system frame (seen from above).
func project(p: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(p.x, p.z) - pan) * scale_px()


## The chart's (x, z) under a screen point.
func unproject(s: Vector2) -> Vector2:
	return pan + (s - size * 0.5) / scale_px()


## A planet's disc on screen (px): its true size, never smaller than min_px.
func disc_px(b: Dictionary) -> float:
	return maxf(float(b.radius) * scale_px(), float(look().get("min_px", 5.0)))


## Back to the whole system: nothing moved, nothing zoomed.
func reset() -> void:
	zoom = 1.0
	pan = home_pan()
	queue_redraw()


## Centre the chart on a point (system frame).
func focus(p: Vector3) -> void:
	pan = Vector2(p.x, p.z)
	queue_redraw()


func set_zoom(z: float, about := Vector2.INF) -> void:
	var at := about if about != Vector2.INF else size * 0.5
	var before := unproject(at)
	zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	pan += before - unproject(at)            # the point under the mouse stays put
	queue_redraw()


## The body under screen point `s` (a planet's id, or "cruiser"), or "".
func body_at(s: Vector2) -> String:
	var best := ""
	var best_d := INF
	for b in bodies:
		var d := s.distance_to(project(b.centre)) - disc_px(b)
		if d < HIT and d < best_d:
			best_d = d
			best = str(b.id)
	if cruiser != Vector3.INF and s.distance_to(project(cruiser)) < HIT + 6.0 and best_d > 0.0:
		best = "cruiser"
	return best


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(zoom * ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(zoom / ZOOM_STEP, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_dragged = false
			else:
				if not _dragged and _press != Vector2.INF:
					var id := body_at(mb.position)
					if id != "":
						body_clicked.emit(id)
				_press = Vector2.INF
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press != Vector2.INF and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if _dragged or mm.position.distance_to(_press) > DRAG:
				_dragged = true
				pan -= mm.relative / scale_px()
		var h := body_at(mm.position)
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
		queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != "":
		hover = ""
		queue_redraw()
	elif what == NOTIFICATION_RESIZED and zoom == 1.0:
		pan = home_pan()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var lk := look()
	draw_rect(Rect2(Vector2.ZERO, size), Color(str(lk.get("space", "#07070b"))))
	var sa := float(lk.get("star_alpha", 0.35))
	for st in _stars:
		draw_rect(Rect2(Vector2(st.x * size.x, st.y * size.y), Vector2.ONE * (1.0 + float(st.z > 0.9))), Color(1, 1, 1, sa * st.z))
	var ink := GlobeView.ink_color()
	var font := get_theme_default_font()
	_draw_orbits(Color(ink, float(lk.get("orbit_alpha", 0.2))))
	var t := GlobeView.pulse()
	var goal_col := Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))
	for b in bodies:
		var at := project(b.centre)
		var r := disc_px(b)
		if not Rect2(Vector2.ZERO, size).grow(r * 3.0).has_point(at):
			continue
		_draw_body(at, r, b, ink)
		if str(b.id) == goal:
			draw_arc(at, r + 6.0 + 8.0 * (1.0 - t), 0.0, TAU, 48, Color(goal_col, 0.3 + 0.6 * t), 2.0, true)
		if str(b.id) == hover:
			draw_arc(at, r + 4.0, 0.0, TAU, 48, Color(ink, 0.9), 1.5, true)
		_draw_name(at + Vector2(0, r + 15.0), b, font, str(b.id) == hover)
	if cruiser != Vector3.INF:
		var at := project(cruiser)
		var col := Color(str(GlobeMap.look().get("pins", {}).get("cruiser", {}).get("color", "#e0573a")))
		if goal == "cruiser":
			draw_arc(at, 12.0 + 8.0 * (1.0 - t), 0.0, TAU, 32, Color(goal_col, 0.3 + 0.6 * t), 2.0, true)
		GlobeView.draw_shape(self, at, "cruiser", col.lightened(0.3) if hover == "cruiser" else col, 7.0)
		if hover == "cruiser" and font != null:
			_tag(at + Vector2(0, -14), cruiser_label, font, 13, Color(0.96, 0.92, 0.84))
	for o in others:
		var at := project(o.pos)
		var col := NetSession.mark_color()
		draw_circle(at, 5.0, col)
		draw_arc(at, 5.0, 0.0, TAU, 24, Color(0, 0, 0, 0.9), 1.5, true)
		if font != null:
			draw_string_outline(font, at + Vector2(10, 5), str(o.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
			draw_string(font, at + Vector2(10, 5), str(o.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	if player != Vector3.INF:
		_draw_player(project(player), t)


## A faint circle round the planet each one is near, through it (seen from above).
func _draw_orbits(col: Color) -> void:
	for b in bodies:
		var near := str(b.get("near", ""))
		if near == "":
			continue
		for p in bodies:
			if str(p.id) == near:
				var c := project(p.centre)
				var r := c.distance_to(project(b.centre))
				var n := clampi(int(r * 0.25), 48, 256)
				for k in n:                          # dashed: every other stroke
					if k % 2 == 0:
						draw_arc(c, r, TAU * k / n, TAU * (k + 1) / n, 3, col, 1.0, true)


## A planet: its disc in its colour, lit from the top left, its rim in its dark
## colour (the lava moon's glows), the ringed giant's bands and ring.
func _draw_body(at: Vector2, r: float, b: Dictionary, ink: Color) -> void:
	var col: Color = b.color
	var dark: Color = b.dark
	var ring: Dictionary = b.get("ring", {})
	var tilt := float(look().get("ring_tilt", 0.32))
	var ring_pts := func(k: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(at + Vector2(cos(a) * r * k, sin(a) * r * k * tilt).rotated(-0.35))
		return pts
	var ring_col := Color(str(ring.get("color", "#e8d6c0"))) if not ring.is_empty() else Color.WHITE
	var ring_ks: Array = []
	if not ring.is_empty():
		var inner := float(ring.get("inner", 1.4))
		var outer := float(ring.get("outer", 2.4))
		for i in 4:
			ring_ks.append(lerpf(inner, outer, i / 3.0))
		for k in ring_ks:                      # the back half, behind the ball
			var pts: PackedVector2Array = ring_pts.call(k)
			draw_polyline(pts.slice(24, 49), Color(ring_col, 0.55), 1.5, true)
	draw_circle(at, r + 1.5, Color(0, 0, 0, 0.8))
	draw_circle(at, r, col)
	if float(b.get("bands", 0.0)) > 0.0 and r > 6.0:
		var n := mini(int(b.bands * 0.5), int(r / 3.0))
		for i in n:
			var y := -r + (i + 0.5) * 2.0 * r / n
			var w := sqrt(maxf(r * r - y * y, 0.0))
			if i % 2 == 0:
				draw_line(at + Vector2(-w, y), at + Vector2(w, y), Color(dark, 0.22), 2.0 * r / n * 0.6)
	draw_circle(at + Vector2(-0.28, -0.28) * r, r * 0.55, Color(col.lightened(0.35), float(look().get("highlight", 0.28))))
	draw_arc(at, r - 0.75, PI * 0.05, PI * 1.05, 48, Color(0, 0, 0, 0.35), maxf(r * 0.35, 1.5), true)   # the night side, lower right
	draw_arc(at, r, 0.0, TAU, 64, Color(dark, 0.9), 1.5, true)
	if not ring.is_empty():
		for k in ring_ks:                      # the front half, over it
			var pts: PackedVector2Array = ring_pts.call(k)
			draw_polyline(pts.slice(0, 25), Color(ring_col, 0.75), 1.5, true)


## A planet's name under it, its kind under that; hovered: how far it is from you.
func _draw_name(at: Vector2, b: Dictionary, font: Font, hot: bool) -> void:
	if font == null:
		return
	var lk := look()
	var col := Color(str(lk.get("label", "#e8dcc0")))
	var title := str(b.label)
	if str(b.id) == here:
		title = GlobeMap.line("system_here") % title
	_text(at, title, font, 14, col if not hot else Color.WHITE)
	var sub := str(b.get("kind", ""))
	if hot and player != Vector3.INF and str(b.id) != here:
		var d := maxf(player.distance_to(b.centre) - float(b.radius), 0.0) / 1000.0
		sub = GlobeMap.line("system_away") % [sub, d]
	if sub != "":
		_text(at + Vector2(0, 15), sub, font, 12, Color(col, float(lk.get("kind_alpha", 0.6))))


func _text(at: Vector2, s: String, font: Font, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(clampf(at.x - w * 0.5, 4.0, maxf(size.x - w - 4.0, 4.0)), at.y)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _tag(at: Vector2, s: String, font: Font, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(clampf(at.x - w * 0.5, 4.0, maxf(size.x - w - 4.0, 4.0)), maxf(at.y, fs + 4.0))
	draw_rect(Rect2(p + Vector2(-4, -fs - 1), Vector2(w + 8, fs + 7)), Color(0, 0, 0, 0.7))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## You: the globe's green triangle, pointing the way you look.
func _draw_player(at: Vector2, t: float) -> void:
	var col := Color(str(GlobeMap.look().get("player", {}).get("color", "#4dff88")))
	draw_circle(at, 12.0 + 4.0 * t, Color(col, 0.12 + 0.12 * t))
	draw_arc(at, 12.0 + 4.0 * t, 0.0, TAU, 32, Color(col, 0.5 + 0.4 * t), 1.5, true)
	var fwd := heading.normalized() if heading.length() > 0.001 else Vector2.UP
	var side := Vector2(-fwd.y, fwd.x)
	var r := 8.0 + 1.5 * t
	var pts := PackedVector2Array([at + fwd * r * 1.45, at - fwd * r * 0.75 + side * r * 0.7, at - fwd * r * 0.75 - side * r * 0.7])
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.9), 1.5, true)
