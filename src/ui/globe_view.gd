class_name GlobeView
extends Control
## The F11 Map page's globe: the planet as a ball seen from space, with a small
## icon at every place that stays put (GlobeMap.pins), you (a green triangle
## pointing the way the camera looks) and the waypoint, both pulsing. The
## waypoint flashes the pin it is at, or, out where no pin is (a drop in the
## desert, a marked spot), shows as its own marker. No people that move, but the
## other LAN players (`others`), on foot or in their ship (straight down on the
## ground under it, even out in space): a blue dot each, named; a click on one
## makes them the waypoint.
##
## Drag turns it, the wheel or the + / - buttons in its top left zoom (zoomed in past the data's town_zoom the
## port's pin opens into its own stops). Hover names a pin; a click sets the
## waypoint there (`pin_clicked`), a click on bare ground drops a marked spot
## (`spot_clicked`). Shapes and colours: content/look/map.json.
##
## Under the grid, faintly, the ground itself (`ground`, a GlobeTerrain bake of the
## ball's own heights): dunes, craters and mesas where they really are, lit from the
## top left. Until the bake is done the ball is the plain "sea" colour.
##
## Orthographic: a place's direction from the planet's centre (map coordinates,
## GlobeMap.dir) is turned by the view (yaw about the screen's vertical, then
## pitch) and drawn where it lands; the half facing away is not drawn.

signal pin_clicked(pin: Dictionary)
signal spot_clicked(map: Vector2)

const ZOOM_MIN := 1.0
const ZOOM_MAX := 48.0
const ZOOM_STEP := 1.25
const BUTTON_STEP := 2.0                 ## how far one press of the + / - buttons zooms
const HIT := 11.0                        ## px: how near a click has to land on a pin
const DRAG := 4.0                        ## px: further than this and a press is a drag, not a click
const PITCH_MAX := 1.45
## Turns the map's frame (the port at +Y) so the port faces the viewer and map -z is up.
const FACE := Basis(Vector3.RIGHT, PI / 2.0)
const GroundShader := preload("res://src/systems/look/shaders/globe_ground.gdshader")

var pins: Array = []                    ## GlobeMap.pins
var shapes: Array = []                  ## GlobeMap.station_shapes: a sealed station's domes, pit and tunnels
var radius_m := 5000.0                  ## the planet's radius (m)
var town_zoom := 14.0                   ## zoom past which the town's stops show instead of the port
var selected := ""                      ## the waypoint's pin id ("" = none)
var yaw := 0.0
var pitch := 0.0
var zoom := 1.0
var hover := -1                         ## index into pins under the mouse, -1 = none
var spot := Vector2.INF                 ## a marked spot's map position (drawn as a ring)
var player := Vector2.INF               ## where you are (map x, z), INF = not on this planet
var heading := Vector2.ZERO             ## the way you look, a map-space direction (ZERO = none)
var goal_pin := ""                      ## the pin the F11 map's waypoint is on (it flashes), "" = none
var others: Array = []                  ## LAN: the other players, on foot or in a ship, [{ id, map (x, z), name }]
var goal := Vector2.INF                 ## where the pointer is otherwise (map x, z): the nearest pin
										## showing within its arrive distance flashes, else its own marker
var ground: GlobeTerrain = null         ## the ball's ground, drawn under the grid once baked
var terrain: Dictionary = {}            ## how the ground is tinted (GlobeMap.terrain_look), {} = map.json's "terrain"

var _ground_layer: Control              ## draws `ground` behind this control's own lines and pins

var _press := Vector2.INF
var _dragged := false


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(220, 220)
	_ground_layer = Control.new()
	_ground_layer.name = "Ground"
	_ground_layer.show_behind_parent = true
	_ground_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_layer.visible = false
	_ground_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	_ground_layer.material = mat
	_ground_layer.draw.connect(func(): _ground_layer.draw_rect(Rect2(Vector2.ZERO, _ground_layer.size), Color.WHITE))
	add_child(_ground_layer)
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


## Pulse while the page shows: you and the waypoint. Finish the ground's bake.
func _process(_dt: float) -> void:
	if GlobeTerrain.busy():
		GlobeTerrain.poll_all()
		if ground != null and ground.texture != null and not _ground_layer.visible:
			queue_redraw()
	if is_visible_in_tree() and (player != Vector2.INF or goal_pin != "" or goal != Vector2.INF or not others.is_empty()):
		queue_redraw()


func _exit_tree() -> void:
	GlobeTerrain.finish_all()


## 0..1..0 about once a second.
static func pulse() -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.1)


func view() -> Basis:
	return Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw) * FACE


## Pixels per unit of the ball's radius.
func scale_px() -> float:
	return (minf(size.x, size.y) * 0.5 - 10.0) * zoom


## Screen position of map (x, z) and whether it faces the viewer: Vector3(x, y, facing).
func project(map: Vector2) -> Vector3:
	var v := view() * GlobeMap.dir(map, radius_m)
	var p := size * 0.5 + Vector2(v.x, -v.y) * scale_px()
	return Vector3(p.x, p.y, v.z)


## The map (x, z) under a screen point, or INF off the ball.
func unproject(p: Vector2) -> Vector2:
	var q := (p - size * 0.5) / scale_px()
	var r2 := q.length_squared()
	if r2 > 1.0:
		return Vector2.INF
	var v := Vector3(q.x, -q.y, sqrt(1.0 - r2))
	return GlobeMap.dir_map(view().inverse() * v, radius_m)


## Turn the globe so map (x, z) faces the viewer.
func focus(map: Vector2) -> void:
	var d := FACE * GlobeMap.dir(map, radius_m)
	yaw = -atan2(d.x, d.z)
	pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PITCH_MAX, PITCH_MAX)
	queue_redraw()


## Which pins show at this zoom: the port's stops only zoomed in, the port's own
## pin only zoomed out.
func shown(pin: Dictionary) -> bool:
	if bool(pin.get("town", false)):
		return zoom >= town_zoom
	if str(pin.get("kind", "")) == "port":
		return zoom < town_zoom
	return true


## The pin index nearest screen point `p` (within HIT px), or -1.
func pin_at(p: Vector2) -> int:
	var best := -1
	var best_d := HIT
	for i in pins.size():
		if not shown(pins[i]):
			continue
		var s := project(pins[i].map)
		if s.z <= 0.0:
			continue
		var d := p.distance_to(Vector2(s.x, s.y))
		if d < best_d:
			best_d = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_zoom(zoom * ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_zoom(zoom / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_dragged = false
			else:
				if not _dragged and _press != Vector2.INF:
					click(mb.position)
				_press = Vector2.INF
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press != Vector2.INF and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			if _dragged or mm.position.distance_to(_press) > DRAG:
				_dragged = true
				yaw += mm.relative.x / scale_px()
				pitch = clampf(pitch + mm.relative.y / scale_px(), -PITCH_MAX, PITCH_MAX)
		var h := pin_at(mm.position)
		if h != hover:
			hover = h
		queue_redraw()
		accept_event()


func set_zoom(z: float) -> void:
	zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	queue_redraw()


## A click at screen point `p`: another player or a pin sets the waypoint, bare
## ground marks a spot.
func click(p: Vector2) -> void:
	for o in others:
		var s := project(o.map)
		if s.z > 0.0 and p.distance_to(Vector2(s.x, s.y)) < HIT:
			pin_clicked.emit({ "id": "player_%d" % int(o.id), "kind": "player", "label": str(o.name),
				"target": "player:%d" % int(o.id), "map": o.map, "arrive": NetSession.n("waypoint_arrive_m", 10.0) })
			return
	var i := pin_at(p)
	if i >= 0:
		pin_clicked.emit(pins[i])
		return
	var m := unproject(p)
	if m != Vector2.INF:
		spot_clicked.emit(m)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
		hover = -1
		queue_redraw()


# ------------------------------------------------------------------ drawing

## The globe's own lines (map.json "ink"; null = the player's HUD colour).
static func ink_color() -> Color:
	var c = GlobeMap.look().get("ink", null)
	return Color(str(c)) if c != null else RetroUI.accent


func _draw() -> void:
	var lk := GlobeMap.look()
	var c := size * 0.5
	var r := scale_px()
	var ink := ink_color()
	if not _draw_ground(lk):
		draw_circle(c, r, Color(str(lk.get("sea", "#141009"))))
	_draw_grid(Color(ink, float(lk.get("grid_alpha", 0.14))))
	draw_arc(c, r, 0.0, TAU, 128, Color(ink, float(lk.get("rim_alpha", 0.85))), 1.5, true)
	_draw_station(lk.get("station", {}), ink)
	var font := get_theme_default_font()
	var fs := 13
	var flash := goal_pin_now()
	for i in pins.size():
		var pin: Dictionary = pins[i]
		if not shown(pin):
			continue
		var s := project(pin.map)
		if s.z <= 0.0:
			continue
		var at := Vector2(s.x, s.y)
		if not Rect2(Vector2.ZERO, size).grow(10.0).has_point(at):
			continue
		_draw_hold(at, pin, font)
		if i == flash:
			_draw_flash(at, pin)
		else:
			_draw_pin(at, pin, i == hover)
	var mark := goal if goal != Vector2.INF and flash < 0 else (spot if selected == "spot" else Vector2.INF)
	if mark != Vector2.INF:
		var s := project(mark)
		if s.z > 0.0:
			_draw_goal(Vector2(s.x, s.y))
	for o in others:
		var s := project(o.map)
		if s.z > 0.0:
			_draw_other(Vector2(s.x, s.y), str(o.name), font)
	if player != Vector2.INF:
		var s := project(player)
		if s.z > 0.0:
			_draw_player(Vector2(s.x, s.y))
	# the hovered (else the waypoint's) pin's name, on a dark tag over it
	var named := hover
	if named < 0:
		for i in pins.size():
			if (i == flash or str(pins[i].id) == selected) and shown(pins[i]):
				named = i
	if named >= 0 and font != null:
		var s := project(pins[named].map)
		if s.z > 0.0:
			var text := str(pins[named].label)
			if str(pins[named].get("status", "")) != "":
				text += " - " + str(pins[named].status)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(clampf(s.x - w * 0.5, 4.0, size.x - w - 4.0), maxf(s.y - 14.0, fs + 4.0))
			draw_rect(Rect2(at + Vector2(-4, -fs - 1), Vector2(w + 8, fs + 7)), Color(0, 0, 0, 0.7))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.92, 0.84))


## A sealed station's outline (shapes): each dome and the pit a faint disc with a
## rim, each tunnel a band between them. Only once a dome is big enough to see.
func _draw_station(sk: Dictionary, ink: Color) -> void:
	if shapes.is_empty():
		return
	var px_per_m := scale_px() / radius_m
	var fill := Color(ink, float(sk.get("fill", 0.08)))
	var edge := Color(ink, float(sk.get("line", 0.7)))
	for sh in shapes:
		if str(sh.kind) == "tunnel":
			var a := project(sh.a)
			var b := project(sh.b)
			if a.z > 0.0 and b.z > 0.0:
				draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), edge, maxf(1.5, float(sh.w) * px_per_m), true)
			continue
		if float(sh.r) * 2.0 * px_per_m < float(sk.get("min_px", 6.0)):
			continue
		var pts := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			var s := project((sh.map as Vector2) + Vector2(cos(a), sin(a)) * float(sh.r))
			if s.z <= 0.0:
				pts.clear()
				break
			pts.append(Vector2(s.x, s.y))
		if pts.size() < 3:
			continue
		draw_colored_polygon(pts, fill)
		draw_polyline(pts, edge, 1.5 if str(sh.kind) == "dome" else 1.0, true)


## The baked ground on the ball, under everything else; false while there is none.
func _draw_ground(lk: Dictionary) -> bool:
	var ready := ground != null and ground.texture != null
	_ground_layer.visible = ready
	if not ready:
		return false
	var t: Dictionary = terrain if not terrain.is_empty() else lk.get("terrain", {})
	var mat := _ground_layer.material as ShaderMaterial
	mat.set_shader_parameter("ground", ground.texture)
	mat.set_shader_parameter("centre", size * 0.5)
	mat.set_shader_parameter("radius_px", scale_px())
	mat.set_shader_parameter("view", view())
	mat.set_shader_parameter("slope_max", GlobeTerrain.SLOPE)
	mat.set_shader_parameter("relief", float(t.get("relief", 4.0)))
	mat.set_shader_parameter("shade", float(t.get("shade", 0.06)))
	mat.set_shader_parameter("texel_px", scale_px() * TAU / ground.size.x)
	var fade: Array = t.get("fade_px", [4.0, 12.0])
	mat.set_shader_parameter("fade_px", Vector2(float(fade[0]), float(fade[1])))
	for k in ["low", "high", "rock"]:
		mat.set_shader_parameter(k, Color(str(t.get(k, lk.get("sea", "#141009")))))
	return true


## Latitude and longitude lines every 30 degrees round the globe's own axis.
func _draw_grid(col: Color) -> void:
	var v := Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)
	var c := size * 0.5
	var r := scale_px()
	var lines: Array = []
	for lat_i in range(-2, 3):
		var lat := deg_to_rad(lat_i * 30.0)
		var ring: Array = []
		for k in 73:
			var lon := TAU * k / 72.0
			ring.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
		lines.append(ring)
	for lon_i in 12:
		var lon := deg_to_rad(lon_i * 30.0)
		var arc: Array = []
		for k in 37:
			var lat := -PI / 2.0 + PI * k / 36.0
			arc.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
		lines.append(arc)
	for pts in lines:
		var run := PackedVector2Array()
		for u in pts:
			var w: Vector3 = v * u
			if w.z > 0.0:
				run.append(c + Vector2(w.x, -w.y) * r)
			elif run.size() > 0:
				if run.size() > 1:
					draw_polyline(run, col, 1.0, true)
				run = PackedVector2Array()
		if run.size() > 1:
			draw_polyline(run, col, 1.0, true)


func _draw_pin(at: Vector2, pin: Dictionary, hot: bool) -> void:
	var lk := GlobeMap.look()
	var p := pin_look(pin)
	var size_px := float(lk.get("pin_size", 6.0)) * (1.35 if hot else 1.0)
	draw_shape(self, at, str(p.get("shape", "circle")), Color(str(p.get("color", "#f2e2b0"))), size_px)


## A held outpost's clock: a ring that drains clockwise from the top as the
## locals' hold runs down (or, issue #425, the Remnant's once the cruiser has
## fallen), and "Resupply needed" under it once they run short.
func _draw_hold(at: Vector2, pin: Dictionary, font: Font) -> void:
	var frac := float(pin.get("hold", -1.0))
	if frac < 0.0:
		return
	var ow: Dictionary = GlobeMap.look().get("owners", {})
	var col := Color(str(pin_look(pin).get("color", "#5fd35f")))
	var r := float(ow.get("ring_px", 11.0))
	draw_arc(at, r, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 4.0, true)
	draw_arc(at, r, 0.0, TAU, 32, Color(col, float(ow.get("ring_back_alpha", 0.25))), 2.0, true)
	if frac > 0.0:
		draw_arc(at, r, -PI / 2.0, -PI / 2.0 + TAU * frac, maxi(4, int(32 * frac)), Color(col, float(ow.get("ring_alpha", 0.9))), 2.0, true)
	if bool(pin.get("short", false)) and font != null:
		var fs := 11
		var text := GlobeMap.line("resupply")
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(at.x - w * 0.5, at.y + r + fs + 2.0)
		draw_rect(Rect2(p + Vector2(-3, -fs), Vector2(w + 6, fs + 4)), Color(0, 0, 0, 0.65))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A pin's look (content/look/map.json): its kind's shape and colour, recoloured
## when the locals hold the place (green, or yellow-green while their supplies run
## short), or the Remnant run short there (issue #425: orange).
static func pin_look(pin: Dictionary) -> Dictionary:
	var lk := GlobeMap.look()
	var key := str(pin.kind)
	if key == "camp" and bool(pin.get("hostile", false)):
		key = "camp_hostile"
	var p: Dictionary = lk.get("pins", {}).get(key, {})
	if str(pin.get("owner", "")) == Territory.LOCALS:
		p = p.duplicate()
		p["color"] = lk.get("owners", {}).get("short" if bool(pin.get("short", false)) else "locals", p.get("color", "#f2e2b0"))
	elif str(pin.get("owner", "")) == Territory.REMNANT and bool(pin.get("short", false)):
		p = p.duplicate()
		p["color"] = lk.get("owners", {}).get("remnant_short", p.get("color", "#f2e2b0"))
	return p


## The index of the pin the waypoint is at, at this zoom (-1 = none): the F11
## map's own pin, else the nearest pin showing within its arrive distance of goal,
## or close enough on screen to read as the same place (a stall in the port, zoomed out).
func goal_pin_now() -> int:
	var best := -1
	var best_d := INF
	var g := project(goal) if goal != Vector2.INF else Vector3.ZERO
	for i in pins.size():
		if not shown(pins[i]):
			continue
		if goal_pin != "":
			if str(pins[i].id) == goal_pin:
				return i
			continue
		if goal == Vector2.INF:
			return -1
		var d: float = (pins[i].map as Vector2).distance_to(goal)
		var sp := project(pins[i].map)
		var near := Vector2(sp.x, sp.y).distance_to(Vector2(g.x, g.y)) <= HIT
		if (d <= float(pins[i].get("arrive", 30.0)) or near) and d < best_d:
			best_d = d
			best = i
	return best


## The waypoint's pin: flashing between its colour and white, a ring going out.
func _draw_flash(at: Vector2, pin: Dictionary) -> void:
	var lk := GlobeMap.look()
	var t := pulse()
	var gl: Dictionary = lk.get("goal", {})
	var col := Color(str(gl.get("color", "#ffd84a")))
	draw_arc(at, 9.0 + 9.0 * (1.0 - t), 0.0, TAU, 32, Color(col, 0.25 + 0.6 * t), 2.0, true)
	var p := pin_look(pin)
	var base := Color(str(p.get("color", "#f2e2b0")))
	draw_shape(self, at, str(p.get("shape", "circle")), base.lerp(Color.WHITE, t), float(lk.get("pin_size", 6.0)) * (1.2 + 0.3 * t))


## The waypoint out where no pin is: its own marker (a pin standing on the spot)
## with a ring going out round its foot.
func _draw_goal(at: Vector2) -> void:
	var t := pulse()
	var col := Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))
	draw_arc(at, 4.0 + 10.0 * (1.0 - t), 0.0, TAU, 32, Color(col, 0.2 + 0.7 * t), 2.0, true)
	draw_shape(self, at, "goal", col.lerp(Color.WHITE, t * 0.5), 7.0)


## You: a green triangle pointing the way you look, breathing, with a soft ring.
func _draw_player(at: Vector2) -> void:
	var t := pulse()
	var col := Color(str(GlobeMap.look().get("player", {}).get("color", "#4dff88")))
	draw_circle(at, 12.0 + 4.0 * t, Color(col, 0.12 + 0.12 * t))
	draw_arc(at, 12.0 + 4.0 * t, 0.0, TAU, 32, Color(col, 0.5 + 0.4 * t), 1.5, true)
	var fwd := Vector2.UP
	if heading != Vector2.ZERO:
		var a := project(player)
		var b := project(player + heading.normalized() * 20.0)
		var d := Vector2(b.x - a.x, b.y - a.y)
		if d.length() > 0.001:
			fwd = d.normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var r := 8.0 + 1.5 * t
	var pts := PackedVector2Array([at + fwd * r * 1.45, at - fwd * r * 0.75 + side * r * 0.7, at - fwd * r * 0.75 - side * r * 0.7])
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.9), 1.5, true)


## Another LAN player: a blue dot with a soft pulsing ring, their name beside it.
func _draw_other(at: Vector2, nm: String, font: Font) -> void:
	var t := pulse()
	var col := NetSession.mark_color()
	draw_arc(at, 8.0 + 3.0 * t, 0.0, TAU, 32, Color(col, 0.4 + 0.4 * t), 1.5, true)
	draw_circle(at, 5.0, col)
	draw_arc(at, 5.0, 0.0, TAU, 24, Color(0, 0, 0, 0.9), 1.5, true)
	if font != null:
		draw_string_outline(font, at + Vector2(12, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		draw_string(font, at + Vector2(12, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


## A pin's shape on any canvas item (the legend draws with it too).
static func draw_shape(ci: CanvasItem, at: Vector2, shape: String, col: Color, r: float) -> void:
	var edge := Color(0, 0, 0, 0.85)
	var pts := PackedVector2Array()
	match shape:
		"triangle":
			pts = PackedVector2Array([at + Vector2(0, -r * 1.15), at + Vector2(r, r * 0.8), at + Vector2(-r, r * 0.8)])
		"square":
			var h := r * 0.8
			pts = PackedVector2Array([at + Vector2(-h, -h), at + Vector2(h, -h), at + Vector2(h, h), at + Vector2(-h, h)])
		"diamond":
			pts = PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
		"star":
			for k in 10:
				var a := -PI / 2.0 + PI * k / 5.0
				pts.append(at + Vector2(cos(a), sin(a)) * (r * 1.3 if k % 2 == 0 else r * 0.55))
		"cross":
			var h := r * 0.75
			ci.draw_line(at + Vector2(-h, -h), at + Vector2(h, h), edge, 4.5, true)
			ci.draw_line(at + Vector2(h, -h), at + Vector2(-h, h), edge, 4.5, true)
			ci.draw_line(at + Vector2(-h, -h), at + Vector2(h, h), col, 2.5, true)
			ci.draw_line(at + Vector2(h, -h), at + Vector2(-h, h), col, 2.5, true)
			return
		"goal":
			# a map pin standing on the spot: a head over a point, a dark eye in it
			var head := at + Vector2(0, -r * 1.7)
			var hp := PackedVector2Array()
			for k in 17:
				var a := PI * 0.15 + (TAU - PI * 0.3) * k / 16.0 + PI / 2.0
				hp.append(head + Vector2(cos(a), sin(a)) * r * 0.85)
			hp.append(at)
			ci.draw_colored_polygon(hp, col)
			ci.draw_polyline(hp + PackedVector2Array([hp[0]]), edge, 1.4, true)
			ci.draw_circle(head, r * 0.32, edge)
			return
		"you":
			pts = PackedVector2Array([at + Vector2(0, -r * 1.45), at + Vector2(r * 0.7, r * 0.75), at + Vector2(-r * 0.7, r * 0.75)])
		"ring":
			ci.draw_arc(at, r, 0.0, TAU, 24, edge, 4.0, true)
			ci.draw_arc(at, r, 0.0, TAU, 24, col, 2.0, true)
			return
		"planet":
			# a ball with a tilted ring round it: the ring's back half behind, front half over
			var ring := PackedVector2Array()
			for k in 33:
				var a := TAU * k / 32.0
				ring.append(at + Vector2(cos(a) * r * 1.5, sin(a) * r * 0.45).rotated(-0.35))
			ci.draw_polyline(ring.slice(16, 33), edge, 3.5, true)
			ci.draw_polyline(ring.slice(16, 33), col, 1.5, true)
			ci.draw_circle(at, r * 0.8 + 1.0, edge)
			ci.draw_circle(at, r * 0.8, col)
			ci.draw_polyline(ring.slice(0, 17), edge, 3.5, true)
			ci.draw_polyline(ring.slice(0, 17), col, 1.5, true)
			return
		"cruiser":
			# a long wedge, nose right, with a notch at the stern for the drives
			pts = PackedVector2Array([at + Vector2(r * 1.5, 0), at + Vector2(-r * 1.2, -r * 0.8),
				at + Vector2(-r * 0.7, 0), at + Vector2(-r * 1.2, r * 0.8)])
		_:
			ci.draw_circle(at, r * 0.85 + 1.0, edge)
			ci.draw_circle(at, r * 0.85, col)
			return
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.2, true)
