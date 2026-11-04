class_name CruiserHolo
extends Node3D
## The bridge's holo table: the home planet as the cruiser sees it, floating over
## the table. A ball of light with the port, every crash site (the world's wreck
## landmarks) and the cruiser itself where they really are on it, the cruiser's
## orbit, and the moon (the planet's child neighbour) in its real direction. All of
## it is turned to the world, not the ship (north and east as on the ground), and
## spins slowly about the planet's up, so the map stays true as it turns.
##
## Issue #325: the port and the seven Remnant outposts are coloured by who holds
## them (Territory: the barracks for the port), and recoloured live while you
## watch (every refresh_s); an outpost's pin flashes for a few seconds when it
## changes hands. The outposts' pins have no names: they sit too close round the
## port for labels to read.
##
## Heights over the ball are squeezed (holo.squeeze) so the 7 km orbit fits over a
## five metre table; the moon keeps its true direction at a set distance. Numbers, colours and lines: the cruiser data's
## "holo" block (content/core/cruiser/remnant_cruiser.json).
##
## Issue #321: the barracks office's holo table shows the same map (BarracksLook),
## smaller, with "here_on": "town" (the port is "here", the cruiser just named);
## its parent is in the world's frame, so `cruiser_frame` is only where the cruiser is.
##
## Issue #327: a cruiser holding station by a space station (the belt cruiser,
## holo.kind "station") shows that station instead (setup_station): both towers
## floor by floor, the elevator shafts, the tunnels and the covered bay, built from
## the station's own config (StationHull), the belt of rocks round it, and the
## cruiser in its true direction from it.

const SHADER := preload("res://src/systems/look/shaders/holo.gdshader")

static var _noise: Texture2D

var spec: Dictionary = {}
var sphere: PlanetSphere
var radius := 1.1
var _spin := 0.0
var _turn: Node3D                      ## everything that spins, centred on the ball
var _to_world := Basis.IDENTITY        ## the parent's frame back to the world's axes
## Issue #325: place id (an outpost, or Territory.BARRACKS for the port) ->
## { owner, short, mats, label, flash }: the pin's materials to recolour.
var places: Dictionary = {}
var _refresh := 0.0


## `cruiser_frame` is the cruiser's frame in the world (the parent's), `anchor` the
## ball's centre in it; `world` the planet's world data (its landmarks), `moons`
## the planet's neighbours ({ id, at, radius, child }), `names` labels by key
## ("town", "cruiser", and each moon's id).
func setup(cfg: Dictionary, sp: PlanetSphere, cruiser_frame: Transform3D, anchor: Vector3, world: Dictionary,
		moons: Array, names: Dictionary) -> void:
	spec = cfg
	sphere = sp
	name = "HoloMap"
	radius = float(spec.get("radius", 1.1))
	position = anchor
	_to_world = cruiser_frame.basis.orthonormalized().inverse()
	basis = _to_world
	_turn = Node3D.new()
	_turn.name = "Turn"
	add_child(_turn)
	var col := Color(str(spec.get("color", "#3fc8ff")))
	# The ball, a fainter shell of grid over it, and the projector's beam under it.
	var ball := _sphere(radius, _mat(col, 0.8, 0.06, 1.0, 0.0, 0.3))
	_turn.add_child(ball)
	_turn.add_child(_sphere(radius * 1.004, _mat(col, 0.7, 0.0, 0.25, 9.0, 0.0)))
	_projector(col, radius * 0.95, radius * 0.6)
	# The port, at the top of the ball (the map's origin), and the Remnant's
	# outposts, each coloured by who holds it.
	var here_line := str(spec.get("lines", {}).get("here", "%s"))
	var here_town := str(spec.get("here_on", "cruiser")) == "town"
	var town_name := str(names.get("town", ""))
	if here_town and town_name != "":
		town_name = here_line % town_name
	_place(Territory.BARRACKS, _pin(sphere.map_dir(0.0, 0.0), owner_color(Territory.BARRACKS), 0.28, town_name, true))
	for lm in world.get("landmarks", []):
		var id := str(lm.get("id", ""))
		if Story.OUTPOSTS.has(id):
			var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
			_place(id, _pin(sphere.map_dir(at.x, at.z), owner_color(id), float(spec.get("outpost_stalk", 0.12)), "", false))
	# Every crash site on the world's map.
	var wreck_col := Color(str(spec.get("wreck_color", "#ff4a2a")))
	for lm in world.get("landmarks", []):
		if str(lm.get("kind", "")) != "wreck":
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		_pin(sphere.map_dir(at.x, at.z), wreck_col, 0.16, str(spec.get("lines", {}).get("wreck", "")), false)
	# The cruiser in its orbit, and the orbit itself (issue #321: not on a planet with none).
	if not bool(spec.get("no_cruiser", false)):
		var here := cruiser_frame.origin - sphere.center
		var ccol := Color(str(spec.get("cruiser_color", "#ff3030")))
		var ship := MeshInstance3D.new()
		ship.name = "Cruiser"
		var wedge := PrismMesh.new()
		wedge.size = Vector3(0.09, 0.26, 0.04)
		ship.mesh = wedge
		ship.material_override = _mat(ccol, 3.0, 1.0, 0.6, 0.0, 0.0)
		ship.position = here.normalized() * squeezed(here.length())
		_turn.add_child(ship)
		ship.look_at_from_position(ship.position, ship.position + _tangent(here), here.normalized())
		ship.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		_turn.add_child(_ring(here, squeezed(here.length()), ccol, 0.5))
		var ship_name := str(names.get("cruiser", ""))
		_turn.add_child(_label(ship.position + here.normalized() * 0.2, ship_name if here_town else here_line % ship_name, ccol))
	# The moon (any child neighbour): its real direction, its distance squeezed.
	var mcol := Color(str(spec.get("moon_color", "#a9b8ff")))
	for m in moons:
		if not bool(m.get("child", true)):
			continue
		var rel: Vector3 = (m.at as Vector3) - sphere.center
		var r := clampf(float(m.get("radius", 0.0)) / sphere.radius * radius, float(spec.get("moon_min_radius", 0.16)),
			float(spec.get("moon_max_radius", 0.24)))
		var moon := _sphere(r, _mat(mcol, 1.0, 0.2, 1.0, 5.0, 0.4))
		moon.name = "Moon_" + str(m.get("id", ""))
		moon.position = rel.normalized() * radius * float(spec.get("moon_at", 2.3))
		_turn.add_child(moon)
		_turn.add_child(_ring(rel, moon.position.length(), mcol, 0.3))
		_turn.add_child(_label(moon.position + Vector3(0, r + 0.08, 0), str(names.get(str(m.get("id", "")), "")), mcol))


## The projector under the map: a cone of light from the table top up to `under`
## metres below its middle, `top` wide there, and its lamp.
func _projector(col: Color, top: float, under: float) -> void:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = top
	cone.bottom_radius = top * 0.58
	cone.height = maxf(float(spec.get("lift", 1.75)) - under, 0.1)
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	beam.material_override = _mat(col, 0.35, 0.05, 0.6, 0.0, 0.0)
	beam.position = Vector3(0, -under - cone.height * 0.5, 0)     # from the table top up to the map
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	add_child(lamp)


# ------------------------------------------------------------------ issue #327: a station

## The map of a space station (`hull`, hanging at `station_frame`) for a cruiser at
## `cruiser_frame` holding station by it. `anchor` is the map's middle in the
## cruiser's frame; `names` labels by key ("station", "cruiser"). The station is
## turned as the real one is (its bay where it really is) and scaled so its length
## is holo.width; the cruiser keeps its true direction at holo.cruiser_at.
func setup_station(cfg: Dictionary, hull: StationHull, station_frame: Transform3D, cruiser_frame: Transform3D,
		anchor: Vector3, names: Dictionary) -> void:
	spec = cfg
	name = "HoloMap"
	position = anchor
	_to_world = cruiser_frame.basis.orthonormalized().inverse()
	basis = _to_world * station_frame.basis.orthonormalized()
	_turn = Node3D.new()
	_turn.name = "Turn"
	add_child(_turn)
	var col := Color(str(spec.get("color", "#3fc8ff")))
	# The station's footprint (its towers' widest floors and the bay) and height.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in hull.towers:
		var r := 0.0
		for f in t.floors:
			r = maxf(r, float(f.r))
		lo = lo.min((t.c as Vector2) - Vector2(r, r))
		hi = hi.max((t.c as Vector2) + Vector2(r, r))
	if not hull.bay.is_empty():
		var br := Vector2(float(hull.bay.r), float(hull.bay.r))
		lo = lo.min((hull.bay.c as Vector2) - br)
		hi = hi.max((hull.bay.c as Vector2) + br)
	var y0 := hull.bottom_y()
	var y1 := hull.top_y()
	var mid := Vector3((lo.x + hi.x) * 0.5, (y0 + y1) * 0.5, (lo.y + hi.y) * 0.5)
	var k := float(spec.get("width", 2.5)) / maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1.0)
	radius = maxf(hi.x - lo.x, hi.y - lo.y) * k * 0.5
	var at := func(p: Vector3) -> Vector3: return (p - mid) * k
	var shell := _mat(col, 1.0, 0.08, 1.1, 0.0, 0.0)
	var plate := _mat(col, 1.3, 0.35, 0.6, 0.0, 0.0)
	var glass := _mat(col.lightened(0.35), 1.8, 0.3, 0.8, 0.0, 0.0)
	# Each tower: its floors as drums of light with a brighter plate, and the shaft.
	for t in hull.towers:
		var c: Vector2 = t.c
		for f in t.floors:
			var r := float(f.r) * k
			var fy := float(f.y)
			_turn.add_child(_drum(r, hull.floor_h * k, shell, at.call(Vector3(c.x, fy + hull.floor_h * 0.5, c.y)), true))
			_turn.add_child(_drum(r * 0.995, maxf(hull.plate * k, 0.006), plate, at.call(Vector3(c.x, fy, c.y)), true))
		var fl: Array = t.floors
		if fl.size() >= 1:
			var b := float(fl[0].y)
			var top := float(fl[-1].y) + hull.floor_h
			_turn.add_child(_drum(hull.shaft_r * k, (top - b) * k, glass, at.call(Vector3(c.x, (b + top) * 0.5, c.y)), false))
	# The tunnels between the towers and out to the bay.
	for tn in hull.tunnels:
		var xf: Transform3D = tn.xf
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(tn.length), hull.tunnel_h, hull.tunnel_w) * k
		mi.mesh = bm
		mi.material_override = glass
		mi.basis = xf.basis
		mi.position = at.call(xf * Vector3(float(tn.length) * 0.5, hull.tunnel_h * 0.5, 0.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_turn.add_child(mi)
	# The covered bay: its wall open to space, its deck, and its pads.
	if not hull.bay.is_empty():
		var bc: Vector2 = hull.bay.c
		var bh := float(hull.bay.height)
		_turn.add_child(_drum(float(hull.bay.r) * k, bh * k, shell, at.call(Vector3(bc.x, bh * 0.5, bc.y)), false))
		_turn.add_child(_drum(float(hull.bay.r) * k, maxf(hull.plate * k, 0.006), plate, at.call(Vector3(bc.x, 0.0, bc.y)), true))
		for pd in hull.pads():
			var pa: Vector3 = pd.at
			_turn.add_child(_drum(float(pd.radius) * k * 0.8, 0.008, glass, at.call(pa + Vector3(0, 0.6, 0)), true))
	var station_line := str(spec.get("lines", {}).get("station", "%s"))
	_turn.add_child(_label(Vector3(0, (y1 - y0) * k * 0.5 + 0.16, 0), station_line % str(names.get("station", "")), col))
	_belt()
	_station_cruiser(station_frame.affine_inverse() * cruiser_frame, mid, names)
	_projector(col, radius * 0.55, (y1 - y0) * k * 0.5)


## The belt round the station: rocks scattered from holo.seed between belt_inner
## and belt_outer, one MultiMesh of faceted lumps.
func _belt() -> void:
	var n := int(spec.get("rocks", 160))
	if n <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 327))
	var lump := SphereMesh.new()
	lump.radius = 0.5
	lump.height = 1.0
	lump.radial_segments = 6
	lump.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lump
	mm.instance_count = n
	var r0 := float(spec.get("belt_inner", 1.6))
	var r1 := float(spec.get("belt_outer", 2.05))
	var thick := float(spec.get("belt_thick", 0.16))
	var s0 := float(spec.get("rock_min", 0.012))
	var s1 := float(spec.get("rock_max", 0.05))
	for i in n:
		var a := rng.randf() * TAU
		var r := lerpf(r0, r1, sqrt(rng.randf()))
		var y := (rng.randf() + rng.randf() - 1.0) * thick * 0.5
		var size := lerpf(s0, s1, pow(rng.randf(), 2.0))
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
		b = b.scaled(Vector3(size * rng.randf_range(0.7, 1.3), size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.8, 1.4)))
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * r, y, sin(a) * r)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Belt"
	mmi.multimesh = mm
	mmi.material_override = _mat(Color(str(spec.get("rock_color", "#86c4e0"))), 1.3, 0.5, 0.9, 0.0, 0.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_turn.add_child(mmi)


## The cruiser on the station's map: a wedge in its true direction from the
## station (`rel`: its frame in the station's) at holo.cruiser_at, its bow where
## the real bow points, a faint line back to the station, and its name.
func _station_cruiser(rel: Transform3D, mid: Vector3, names: Dictionary) -> void:
	var ccol := Color(str(spec.get("cruiser_color", "#ff3030")))
	var dir := (rel.origin - mid).normalized()
	var at := dir * float(spec.get("cruiser_at", 1.85))
	var ship := MeshInstance3D.new()
	ship.name = "Cruiser"
	var wedge := PrismMesh.new()
	wedge.size = Vector3(0.11, 0.32, 0.05)
	ship.mesh = wedge
	ship.material_override = _mat(ccol, 3.0, 1.0, 0.6, 0.0, 0.0)
	_turn.add_child(ship)
	var bow := -rel.basis.z.normalized()
	ship.look_at_from_position(at, at + bow, Vector3.UP)
	ship.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	var line := MeshInstance3D.new()
	line.name = "Bearing"
	var c := CylinderMesh.new()
	c.top_radius = 0.004
	c.bottom_radius = 0.004
	c.height = at.length()
	c.radial_segments = 6
	line.mesh = c
	line.material_override = _mat(ccol, 0.8, 1.0, 0.0, 0.0, 0.0)
	line.basis = PlanetSphere.tilt_to(dir)
	line.position = at * 0.5
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_turn.add_child(line)
	var here_line := str(spec.get("lines", {}).get("here", "%s"))
	_turn.add_child(_label(at + Vector3(0, 0.2, 0), here_line % str(names.get("cruiser", "")), ccol))


## A round drum of light `r` wide and `h` tall centred at `at` (caps or open).
func _drum(r: float, h: float, mat: Material, at: Vector3, caps: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 40
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	mi.mesh = c
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The ball's size for a distance from the planet's centre (metres): the surface
## at `radius`, heights over it squeezed by holo.squeeze.
func squeezed(d: float) -> float:
	var over := maxf(0.0, d / sphere.radius - 1.0)
	return radius * (1.0 + over * float(spec.get("squeeze", 0.3)))


func _process(dt: float) -> void:
	_spin = wrapf(_spin + deg_to_rad(float(spec.get("spin_deg_s", 5.0))) * dt, 0.0, TAU)
	_turn.basis = Basis(Vector3.UP, _spin)
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = float(spec.get("refresh_s", 0.5))
		refresh_owners()
	for id in places:
		var p: Dictionary = places[id]
		if float(p.flash) > 0.0:
			p.flash = maxf(0.0, float(p.flash) - dt)
			var t := 0.5 + 0.5 * sin(float(p.flash) * TAU * 2.0) if float(p.flash) > 0.0 else 0.0
			_paint(p, owner_color(str(id)).lerp(Color.WHITE, t * 0.7))


## Who holds `id` (an outpost, or Territory.BARRACKS for the port) as the holo's
## colour: the Remnant's, the locals', or either side running short (issue #425:
## the Remnant once the cruiser has fallen).
func owner_color(id: String) -> Color:
	var cols: Dictionary = spec.get("owner_colors", {})
	var key := Territory.owner(id)
	if key == Territory.LOCALS and Territory.short_shown(id):
		key = "short"
	elif key == Territory.REMNANT and Territory.short_shown(id):
		key = "remnant_short"
	return Color(str(cols.get(key, spec.get("town_color", "#ffc23a"))))


## Recolour every place whose owner (or shortage) changed since the last look;
## an outpost that changed hands flashes for holo.flash_s.
func refresh_owners() -> void:
	for id in places:
		var p: Dictionary = places[id]
		var who := Territory.owner(str(id))
		var is_short := Territory.short_shown(str(id))
		if who == p.owner and is_short == p.short:
			continue
		if who != p.owner:
			p.flash = float(spec.get("flash_s", 3.0))
		p.owner = who
		p.short = is_short
		_paint(p, owner_color(str(id)))


func _place(id: String, pin: Dictionary) -> void:
	pin["owner"] = Territory.owner(id)
	pin["short"] = Territory.short_shown(id)
	pin["flash"] = 0.0
	places[id] = pin


func _paint(p: Dictionary, col: Color) -> void:
	for m in p.mats:
		(m as ShaderMaterial).set_shader_parameter("color", col)
	if p.label != null:
		(p.label as Label3D).modulate = col.lightened(0.3)


## A marker on the ball at `dir`: a stalk of light out of the surface with a bead
## on top, and its name over it. Returns { mats, label } to recolour it by.
func _pin(dir: Vector3, col: Color, tall: float, text: String, big: bool) -> Dictionary:
	var out := { "mats": [], "label": null }
	var stalk := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.01
	c.bottom_radius = 0.02
	c.height = tall
	c.radial_segments = 8
	stalk.mesh = c
	stalk.material_override = _mat(col, 2.0, 0.8, 0.5, 0.0, 0.0)
	var up := dir.normalized()
	stalk.basis = PlanetSphere.tilt_to(up)
	stalk.position = up * (radius + tall * 0.5)
	_turn.add_child(stalk)
	var bead := _sphere(0.05 if big else 0.04, _mat(col, 3.0, 1.0, 0.6, 0.0, 0.0))
	bead.position = up * (radius + tall)
	_turn.add_child(bead)
	out.mats.append(stalk.material_override)
	out.mats.append(bead.material_override)
	if big:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.1
		t.outer_radius = 0.125
		ring.mesh = t
		ring.material_override = _mat(col, 2.0, 0.8, 0.3, 0.0, 0.0)
		ring.basis = PlanetSphere.tilt_to(up)
		ring.position = up * (radius + 0.005)
		_turn.add_child(ring)
		out.mats.append(ring.material_override)
	if text != "":
		out.label = _label(up * (radius + tall + 0.07), text, col)
		_turn.add_child(out.label)
	return out


## A thin ring round the ball's centre through `dir` at `r`: an orbit.
func _ring(dir: Vector3, r: float, col: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - 0.004
	t.outer_radius = r + 0.004
	t.rings = 96
	t.ring_segments = 4
	mi.mesh = t
	mi.material_override = _mat(col, energy, 1.0, 0.0, 0.0, 0.0)
	# The torus lies in its own xz plane: turn its up square to `dir`.
	var n := dir.normalized().cross(_tangent(dir)).normalized()
	mi.basis = PlanetSphere.tilt_to(n)
	return mi


## A direction along the ground at `dir`, toward the world's +x where it can.
func _tangent(dir: Vector3) -> Vector3:
	var u := dir.normalized()
	var t := Vector3.RIGHT - u * u.dot(Vector3.RIGHT)
	if t.length() < 0.01:
		t = Vector3.FORWARD - u * u.dot(Vector3.FORWARD)
	return t.normalized()


func _label(at: Vector3, text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0028
	l.font_size = 40
	l.outline_size = 6
	l.modulate = col.lightened(0.3)
	l.outline_modulate = Color(0, 0.05, 0.1, 0.8)
	l.shaded = false
	l.double_sided = true
	return l


func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 48
	s.rings = 24
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mat(col: Color, energy: float, fill: float, rim: float, grid: float, land: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("grid", grid)
	m.set_shader_parameter("land", land)
	m.set_shader_parameter("bands", 1.0 if grid > 0.0 or land > 0.0 else 0.0)
	if _noise == null:
		_noise = LookEnvironment.make_noise_texture(256, 3, 0.02)
	m.set_shader_parameter("noise_tex", _noise)
	return m
