class_name CruiserMapView
extends Control
## The F11 Map page's view of the Remnant cruiser: a cutaway of the real ship seen
## from starboard (the bay side, bow to the right), rendered from its own parts
## (CruiserHull.parts, merged as RemnantCruiser merges them) into a SubViewport
## once per size. The hull, its walls and its trim are drawn as light
## (cruiser_xray.gdshader) so the decks, the ramps zig-zagging up the shaft, the
## racks in the rooms and the bridge's consoles show solid inside; the screens,
## the reactor and the engines glow. Stretched up (`stretch`) so a 10 m corridor
## is something you can click.
##
## Over it, the places you can set a waypoint on (GlobeMap.cruiser_pins: the
## landing bay, the corridor's armoury and crew room, the bridge) are marked with
## corner brackets and named on leader lines out past the hull; the stairs are
## drawn, not named. Hover lights a place; a click sets the waypoint there
## (`place_clicked`). You show when you are aboard; the waypoint's place flashes.
## Colours: content/look/map.json "cruiser".

signal place_clicked(pin: Dictionary)

const PAD := Vector2(24.0, 46.0)        ## px round the ship: the names go above and below
const XRAY := preload("res://src/systems/look/shaders/cruiser_xray.gdshader")
const GHOST := ["hull", "wall", "trim", "glass"]          ## drawn as light
const LIT := ["screen", "glow", "reactor", "beacon"]       ## glowing, unshaded

var pins: Array = []                    ## GlobeMap.cruiser_pins
var selected := ""                      ## the waypoint's pin id ("" = none)
var player := Vector3.INF               ## you, in the cruiser's frame (INF = not aboard)
var hover := -1

var _bounds := Rect2()                  ## the ship's (z, y) extent, metres
var _vp: SubViewport
var _cam: Camera3D
var _ship: Node3D


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(240, 180)
	var hz := CruiserHull.HOUSING_Z
	var z0 := float(CruiserHull.STATIONS[0][0])
	var keel := (CruiserHull.HULL[6] as Vector2).y
	_bounds = Rect2(z0, keel, hz.y + CruiserHull.BELL_LENGTH - z0, CruiserHull.TOWER_TOP - keel)


func _cfg() -> Dictionary:
	return GlobeMap.look().get("cruiser", {})


func stretch() -> float:
	return float(_cfg().get("stretch", 1.8))


func _process(_dt: float) -> void:
	if is_visible_in_tree() and (selected != "" or player != Vector3.INF):
		queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			if hover != -1:
				hover = -1
				queue_redraw()
		NOTIFICATION_RESIZED, NOTIFICATION_VISIBILITY_CHANGED:
			if is_visible_in_tree() and size.x > 1.0 and size.y > 1.0:
				_render()


# ------------------------------------------------------------------ placing

## Pixels per metre along the ship, fitted to the control.
func scale_px() -> float:
	return maxf(0.01, minf((size.x - PAD.x * 2.0) / _bounds.size.x, (size.y - PAD.y * 2.0) / (_bounds.size.y * stretch())))


## Screen point of (z, y) in the cruiser's frame: bow to the right, up up.
func to_px(z: float, y: float) -> Vector2:
	var s := scale_px()
	var c := _bounds.get_center()
	return size * 0.5 + Vector2(-(z - c.x), -(y - c.y) * stretch()) * s


## A (z, y) rect on screen.
func rect_px(r: Rect2) -> Rect2:
	var a := to_px(r.position.x, r.position.y)
	var b := to_px(r.end.x, r.end.y)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


## The pin index under screen point `p`, or -1.
func place_at(p: Vector2) -> int:
	for i in pins.size():
		if rect_px(pins[i].rect).grow(4.0).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := place_at((event as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var i := place_at(mb.position)
			if i >= 0:
				place_clicked.emit(pins[i])
		accept_event()


# ------------------------------------------------------------------ the render

## The ship rendered at this size: built the first time, then only the camera and
## the viewport's size change. One frame's render, not one a frame.
func _render() -> void:
	if _vp == null:
		_build()
	_vp.size = Vector2i(size)
	_ship.scale = Vector3(1.0, stretch(), 1.0)
	var c := _bounds.get_center()
	_cam.size = size.y / scale_px()
	_cam.transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(600.0, c.y * stretch(), c.x))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _build() -> void:
	var lk := _cfg()
	var fin: Dictionary = lk.get("finishes", {})
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(str(lk.get("space", "#0b0a08")))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(lk.get("ambient", "#5a5048")))
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.transform = Transform3D(Basis.looking_at(Vector3(-1.0, -1.4, 0.35).normalized(), Vector3.UP), Vector3.ZERO)
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 1.0
	_cam.far = 1200.0
	_vp.add_child(_cam)
	_ship = Node3D.new()
	_vp.add_child(_ship)
	var groups := {}
	for p in CruiserHull.parts():
		var f := str(p.finish)
		if f == "hidden":
			continue
		if not groups.has(f):
			groups[f] = []
		groups[f].append(p)
	var ink := GlobeView.ink_color()
	for f: String in groups:
		var mi := MeshInstance3D.new()
		mi.mesh = RemnantCruiser._merged(f, groups[f])
		mi.material_override = _material(f, fin, ink)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ship.add_child(mi)
	_bells(fin, ink)


## A finish's look here: light for the hull and its walls, a glow for the screens
## and lamps, plain lit paint for everything you stand on or by.
func _material(f: String, fin: Dictionary, ink: Color) -> Material:
	var col := Color(str(fin.get(f, "#6a6058")))
	if f in GHOST:
		var m := ShaderMaterial.new()
		m.shader = XRAY
		m.set_shader_parameter("tint", ink if f != "glass" else col)
		var ghost: Dictionary = _cfg().get("ghost", {}).get(f, {})
		m.set_shader_parameter("fill", float(ghost.get("fill", 0.05)))
		m.set_shader_parameter("rim", float(ghost.get("rim", 0.55)))
		return m
	var s := StandardMaterial3D.new()
	if f in LIT:
		s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s.albedo_color = col
		return s
	s.albedo_color = col
	s.roughness = 0.9
	return s


## The engines' bells (RemnantCruiser draws them round, they are not parts): a
## flared cylinder each, as light, and a glow in its mouth.
func _bells(fin: Dictionary, ink: Color) -> void:
	var shell := ShaderMaterial.new()
	shell.shader = XRAY
	shell.set_shader_parameter("tint", ink)
	var mouth := StandardMaterial3D.new()
	mouth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mouth.albedo_color = Color(str(fin.get("engine", "#7cc4ff")))
	var aft := Basis(Vector3.RIGHT, PI * 0.5)
	for e in CruiserHull.engines():
		var c: Vector3 = e.at
		var r := float(e.radius)
		var length := CruiserHull.BELL_LENGTH * (0.5 if bool(e.aux) else 1.0)
		var bell := CylinderMesh.new()
		bell.top_radius = r
		bell.bottom_radius = r * 0.55
		bell.height = length
		bell.cap_top = false
		bell.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = bell
		mi.material_override = shell
		mi.transform = Transform3D(aft, c - Vector3(0, 0, length * 0.5))
		_ship.add_child(mi)
		var glow := CylinderMesh.new()
		glow.top_radius = r * 0.9
		glow.bottom_radius = r * 0.9
		glow.height = 0.4
		var gi := MeshInstance3D.new()
		gi.mesh = glow
		gi.material_override = mouth
		gi.transform = Transform3D(aft, c)
		_ship.add_child(gi)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if _vp != null:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	var ink := GlobeView.ink_color()
	var goal := Color(str(GlobeMap.look().get("goal", {}).get("color", "#ffd84a")))
	var t := GlobeView.pulse()
	var font := get_theme_default_font()
	_outline(Color(ink, float(_cfg().get("outline_alpha", 0.9))))
	var top := to_px(0.0, _bounds.end.y).y
	var bottom := to_px(0.0, _bounds.position.y).y
	var tags: Array = []
	for i in pins.size():
		var pin: Dictionary = pins[i]
		var r := rect_px(pin.rect)
		var hot := i == hover
		var on := str(pin.id) == selected
		var col := goal.lerp(Color.WHITE, t * 0.4) if on else (Color.WHITE if hot else Color(ink, 0.85))
		if on or hot:
			draw_rect(r, Color(col, (0.12 + 0.12 * t) if on else 0.12))
		_brackets(r, col, 2.0 if on or hot else 1.5)
		if font == null:
			continue
		# The name on a leader line: up past the tower for the bridge, down past the
		# keel for the rest, stepped further out when it would cross another.
		var up := (pin.rect as Rect2).position.y > 0.0
		var fs := 14
		var text := str(pin.label).to_upper()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := clampf(r.get_center().x - w * 0.5, 4.0, size.x - w - 4.0)
		var y := (top - 12.0) if up else (bottom + fs + 10.0)
		var tag := Rect2(x - 6.0, y - fs - 2.0, w + 12.0, fs + 8.0)
		for k in 3:
			var clash := false
			for o: Rect2 in tags:
				clash = clash or o.intersects(tag.grow(2.0))
			if not clash:
				break
			tag.position.y += (-1.0 if up else 1.0) * (fs + 10.0)
			y += (-1.0 if up else 1.0) * (fs + 10.0)
		tags.append(tag)
		var anchor := Vector2(r.get_center().x, r.position.y if up else r.end.y)
		var foot := Vector2(clampf(anchor.x, tag.position.x + 4.0, tag.end.x - 4.0), tag.end.y if up else tag.position.y)
		draw_line(anchor, foot, Color(col, 0.7), 1.0, true)
		draw_circle(anchor, 2.5, col)
		draw_rect(tag, Color(0, 0, 0, 0.7))
		draw_rect(tag, Color(col, 0.6), false, 1.0)
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if player != Vector3.INF:
		var at := to_px(player.z, player.y + 1.0)
		var you := Color(str(GlobeMap.look().get("player", {}).get("color", "#4dff88")))
		draw_circle(at, 10.0 + 3.0 * t, Color(you, 0.15 + 0.15 * t))
		GlobeView.draw_shape(self, at, "you", you, 6.0)


## The hull's silhouette, crisp over the render: the keel stations' top and bottom
## (the same numbers the hull is built from), the bridge tower, the engine housings.
func _outline(col: Color) -> void:
	var hull_top := (CruiserHull.HULL[2] as Vector2).y
	var keel := (CruiserHull.HULL[6] as Vector2).y
	var hz := CruiserHull.HOUSING_Z
	var line := PackedVector2Array()
	for st in CruiserHull.STATIONS:
		line.append(to_px(float(st[0]), hull_top * float(st[2])))
	var tz := CruiserHull.TOWER_Z
	line.append(to_px(tz.x, hull_top))
	line.append(to_px(tz.x, CruiserHull.TOWER_TOP))
	line.append(to_px(tz.y, CruiserHull.TOWER_TOP))
	line.append(to_px(tz.y, hull_top))
	line.append(to_px(hz.x, hull_top))
	line.append(to_px(hz.x, keel))
	var stations: Array = CruiserHull.STATIONS.duplicate()
	stations.reverse()
	for st in stations:
		line.append(to_px(float(st[0]), keel * float(st[2])))
	line.append(line[0])
	draw_polyline(line, col, 1.5, true)
	for e in CruiserHull.engines():
		var c: Vector3 = e.at
		var h := float(e.radius) * 1.18
		var box := rect_px(Rect2(hz.x, c.y - h, hz.y - hz.x, h * 2.0))
		draw_rect(box, Color(col, col.a * 0.7), false, 1.0)


## Corner brackets round a place: four L's, a quarter of the shorter side each.
func _brackets(r: Rect2, col: Color, width: float) -> void:
	var l := clampf(minf(r.size.x, r.size.y) * 0.3, 4.0, 14.0)
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		draw_polyline(PackedVector2Array([c + Vector2(sx * l, 0), c, c + Vector2(0, sy * l)]), col, width, true)
