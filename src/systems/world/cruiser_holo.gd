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
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = radius * 0.95
	cone.bottom_radius = radius * 0.55
	cone.height = float(spec.get("lift", 1.75)) - radius * 0.6
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	beam.material_override = _mat(col, 0.35, 0.05, 0.6, 0.0, 0.0)
	beam.position = Vector3(0, -radius * 0.6 - cone.height * 0.5, 0)     # from the table top up to the ball
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var lamp := OmniLight3D.new()
	lamp.light_color = col
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	add_child(lamp)
	# The port, at the top of the ball (the map's origin), and the Remnant's
	# outposts, each coloured by who holds it.
	_place(Territory.BARRACKS, _pin(sphere.map_dir(0.0, 0.0), owner_color(Territory.BARRACKS), 0.28, str(names.get("town", "")), true))
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
	# The cruiser in its orbit, and the orbit itself.
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
	var here_line := str(spec.get("lines", {}).get("here", "%s"))
	_turn.add_child(_label(ship.position + here.normalized() * 0.2, here_line % str(names.get("cruiser", "")), ccol))
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
## colour: the Remnant's, the locals', or the locals' running short.
func owner_color(id: String) -> Color:
	var cols: Dictionary = spec.get("owner_colors", {})
	var key := Territory.owner(id)
	if key == Territory.LOCALS and Territory.short_shown(id):
		key = "short"
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
