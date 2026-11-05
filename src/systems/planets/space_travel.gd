class_name SpaceTravel
extends Node3D
## Flying to another planet (issue #45). Every neighbour the planet generator
## lists hangs in this planet's sky where its config says ("at", metres from the
## port). A marker on screen names each one and how far it is.
##
## Issue #99: one map, no cutaway. Every planet's scene is the same space shifted
## to its own port (PlanetGen.neighbours), so the sun and the stars agree. A
## planet whose type has a space.handoff (the asteroid) is drawn here as its real
## ball (the same rock, coarse) with its station on top; fly within handoff metres
## of its surface and its own scene takes over on the spot, the ship exactly where
## it was, same heading and speed, nothing faded. Climb more than that far off it
## and its parent's scene takes over the same way. A planet with no handoff is
## still flown into and faded to, as before (GameFlow.travel).
##
## Issue #573: open space is its own place. Every planet with a handoff has a
## bubble (its radius plus handoff); climb hysteresis metres past it and open
## space's scene (PlanetGen.open_space_id, no planet loaded) takes over the same
## way; from open space, cross a planet's bubble and its scene takes over. There
## are no siblings or parents to fly through any more: every scene places the
## other planets from one system frame (PlanetGen.neighbours). A ball planet with
## a bubble is drawn as its real coarse ball only within real_ball_within metres
## (types.json "space"); further off it is the cheap ball, swapped on the way in.
##
## No input of its own: ShipPilot owns the ship. This only watches where it is.

signal travel_started(to: String)

const CAPTURE := 400.0               ## metres outside a body's radius that count as "arrived"
const HYSTERESIS := 300.0            ## issue #99: leaving needs this much more than arriving
const GAS_SHADER := preload("res://src/systems/look/shaders/gas_giant.gdshader")
const RING_SHADER := preload("res://src/systems/look/shaders/gas_ring.gdshader")
const HAZE_SHADER := preload("res://src/systems/look/shaders/gas_haze.gdshader")
const PREWARM := 1500.0              ## this far before a handoff, its scene's far mesh starts on worker threads

var pilot                            ## ShipPilot
var bodies: Array = []               ## { id, name, at, radius, node }
var traveling := ""                  ## the planet a fade is taking us to ("" = none)
var change := true                   ## false: decide but do not change scene (tests)
var _layer: CanvasLayer
var _labels: Dictionary = {}         ## id -> Label
var _sand_bodies: Array = []         ## sand ShaderMaterials of ball neighbours (the sun is tracked)
var _gas_mats: Array = []            ## the ringed giant's ball, haze and ring materials (sun, daylight, haze)
var _look = null                     ## the scene's LookEnvironment, once ready
var self_radius := 0.0               ## issue #99: this planet's ball, and how far up its scene still holds
var self_handoff := 0.0
var handoffs := 0                    ## seamless switches started (traces, tests)
var staged := false                  ## issue #121: built during a staged handoff (balls refine over frames)
var _prechecks: Array = []           ## issue #121: worker tasks checking the neighbours' towns
var prewarmed: Array = []            ## planets whose handoff scene was prewarmed (PlanetTerrain.prewarm_far)
var here_id := ""                    ## issue #573: the place this scene is (a planet, or open space)
var open := false                    ## issue #573: this scene is open space
var _open_body: Dictionary = {}      ## open space as a handoff target: its origin here (offset)
var _with_looks := false


func setup(ship_pilot, neighbours: Array, with_looks: bool) -> void:
	pilot = ship_pilot
	name = "SpaceTravel"
	_with_looks = with_looks
	var me: Dictionary = pilot.demo.planet if pilot != null and "planet" in pilot.demo else {}
	if not me.is_empty():
		here_id = str(me.get("id", ""))
		open = str(me.get("ground", "")) == "none"
		if not open:
			self_radius = PlanetGen.ball_radius(me.get("cfg", {}), null) if not me.get("world", {}).get("terrain", {}).has("sphere_radius") \
				else float(me.world.terrain.sphere_radius)
			self_handoff = PlanetGen.handoff_altitude(str(me.get("type", "")))
		var here := PlanetGen.system_port(here_id)
		if here != Vector3.INF:
			_open_body = { "id": PlanetGen.open_space_id(), "offset": -here, "name": "", "at": -here, "radius": 0.0 }
	var eye := _eye()
	var near_ok := float(PlanetGen.space_cfg().get("real_ball_within", 6000.0))
	for n in neighbours:
		var b := { "id": str(n.id), "at": n.at, "radius": float(n.radius), "type": str(n.type), "node": null,
			"name": PlanetGen.display_name(PlanetGen.build(str(n.id))),
			"offset": n.get("offset", n.at), "child": bool(n.get("child", true)),
			"handoff": PlanetGen.handoff_altitude(str(n.type)), "n": n, "real": false }
		if with_looks:
			# Issue #573: the real ball only when close; else the cheap one, upgraded on the way in.
			var close := eye.distance_to(n.at) - float(n.radius) <= near_ok
			b.node = _body(n, close)
			b.real = close or not _wants_real(n)
		bodies.append(b)


func _ready() -> void:
	for b in bodies:
		if b.node != null:
			add_child(b.node)
	# Issue #121: check every neighbour's town now, off the main thread, so the
	# scene that takes over on arrival does not spend its first frame on it.
	for b in bodies:
		var town: Dictionary = PlanetGen.build(str(b.id)).get("town", {})
		var task := TownCheck.precheck(str(b.id), town)
		if task >= 0:
			_prechecks.append(task)
	var look = pilot.demo.get("look") if pilot != null and pilot.get("demo") != null else null
	if look != null:
		for m in _sand_bodies:
			look.track_material(m)     # the sun, so the ball's night side is dusk
		for m in _gas_mats:
			look.track_material(m)
		_look = look
		_share_parent_sky(look)
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	for b in bodies:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color("#9fe8ff"))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.visible = false
		_layer.add_child(l)
		_labels[b.id] = l


func _exit_tree() -> void:
	for task in _prechecks:
		WorkerThreadPool.wait_for_task_completion(task)
	_prechecks.clear()


## How far the ship is from a body's surface (metres; < 0 inside its capture).
func distance_to(id: String) -> float:
	for b in bodies:
		if b.id == id:
			return (pilot.atmo.position() as Vector3).distance_to(b.at) - float(b.radius) - CAPTURE
	return INF


## The real ringed giant fades into the daylight sky the way its painting did
## (LookEnvironment.planet_visibility, which AltitudeSky raises in space).
func _process(_dt: float) -> void:
	if traveling == "":
		_build_step()
	if _gas_mats.is_empty() or _look == null or _look.sky_mat == null:
		return
	var haze: Color = (_look.sky_mat.get_shader_parameter("horizon_color") as Color).lerp(
		_look.sky_mat.get_shader_parameter("zenith_color") as Color, 0.5)
	for m in _gas_mats:
		m.set_shader_parameter("visibility", _look.planet_visibility)
		m.set_shader_parameter("haze", haze)


func _physics_process(_dt: float) -> void:
	if pilot == null or traveling != "":
		return
	var flying: bool = pilot.piloting and pilot.atmo.state in [AtmoFlight.State.FLYING, AtmoFlight.State.LIFTOFF]
	_update_labels(flying)
	if not flying:
		return
	var pos: Vector3 = pilot.atmo.position()
	_upgrade_near(pos)
	if not open and self_handoff > 0.0 and not _open_body.is_empty():
		# Issue #573: far enough off this ball: open space's scene, seamlessly.
		var out := self_radius + self_handoff + PlanetGen.hysteresis() - pos.distance_to(Vector3(0, -self_radius, 0))
		if out <= PREWARM:
			_prewarm(str(_open_body.id))
			if _with_looks:
				_prebuild_self()
		if out <= 0.0:
			handoff(str(_open_body.id))
			return
	for b in bodies:
		if float(b.handoff) > 0.0:
			if not open:
				continue          # issue #573: a bubble is entered from open space only (they never touch)
			# Issue #99: close enough to its ball: its scene, seamlessly.
			var gap := pos.distance_to(b.at) - float(b.radius) - float(b.handoff)
			if gap <= PREWARM:
				_prewarm(b.id)
			if gap <= 0.0:
				handoff(b.id)
				return
		elif distance_to(b.id) <= 0.0:
			go(b.id)
			return


## Issue #99: switch to planet `id`'s scene now, with no fade: the ship carries on
## from the same point (in that planet's coordinates), heading, speed and throttle.
func handoff(id: String) -> void:
	var b: Dictionary = _open_body if not _open_body.is_empty() and id == str(_open_body.id) else {}
	for x in bodies:
		if x.id == id:
			b = x
	if b.is_empty() or traveling != "":
		return
	traveling = id
	handoffs += 1
	if pilot.fight != null:
		pilot.end_fight("left", true)    # broken off without a word: the music plays on
	travel_started.emit(id)
	var look = pilot.demo.get("look")
	var xf: Transform3D = pilot.atmo.transform()
	var extra := {
		"handoff": { "position": pilot.atmo.position() - (b.offset as Vector3), "basis": pilot.atmo.flight.basis,
			"speed": pilot.atmo.speed(), "throttle": pilot._throttle,
			"camera": xf.affine_inverse() * pilot.chase.xform, "camera_mode": pilot.chase.mode },
		"hour": float(look.hour) if look != null else -1.0,
		"preset": str(look.current) if look != null else "",
	}
	if not change:
		last_handoff = extra
		return
	_finish_own()
	_pool_leaving()            # issue #573: the next scene draws what this one built
	GameFlow.flown_key = pilot.berth_key()        # issue #368: which of your ships it is
	GameFlow.travel(get_tree() if is_inside_tree() else null, id, pilot.ship_id, str(b.name), extra)


## Leaving with this planet's own ball still part built: the rest now.
func _finish_own() -> void:
	for job in _builds.duplicate():
		if not bool(job.own):
			continue
		while not (job.queue as Array).is_empty():
			var more = ((job.queue as Array).pop_front() as Callable).call()
			if more is Array:
				job.queue = (more as Array) + (job.queue as Array)
		_builds.erase(job)
		_own = job.root


var last_handoff: Dictionary = {}     ## what the last handoff carried (tests, with change = false)


## A handoff to `id` is close: start its scene's slow first-frame work now.
func _prewarm(id: String) -> void:
	if prewarmed.has(id):
		return
	prewarmed.append(id)
	if pilot != null and bool(pilot.demo.get("use_look")):
		PlanetTerrain.prewarm_far(PlanetGen.build(id))
		prewarm_bodies(id)


## Leave for planet `id` now (a running space fight is broken off first).
func go(id: String) -> void:
	var b: Dictionary = {}
	for x in bodies:
		if x.id == id:
			b = x
	if b.is_empty():
		return
	traveling = id
	if pilot.fight != null:
		pilot.end_fight("left")
	pilot.hud.toast(GameFlow.label("travel_enter") % str(b.name), 3.0)
	travel_started.emit(id)
	if not change:
		return
	GameFlow.flown_key = pilot.berth_key()        # issue #368: which of your ships it is
	if not is_inside_tree():
		GameFlow.travel(null, id, pilot.ship_id, str(b.name))
		return
	var tw := create_tween()
	tw.tween_method(pilot.hud.set_fade, 0.0, 1.0, float(GameFlow.setting("fade_time", 0.6)))
	tw.tween_callback(func(): GameFlow.travel(get_tree(), id, pilot.ship_id, str(b.name)))


func _update_labels(flying: bool) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for b in bodies:
		var l: Label = _labels.get(b.id)
		if l == null:
			continue
		if cam == null or not flying or cam.is_position_behind(b.at):
			l.visible = false
			continue
		var d := maxf(0.0, distance_to(b.id) + CAPTURE)
		l.text = GameFlow.label("travel_to") % ["◇ " + str(b.name), "%.1f km" % (d / 1000.0)]
		var sp := cam.unproject_position(b.at)
		l.position = sp + Vector2(14, -10)
		l.visible = true


## Issue #573: one sky for the whole system. Up in space every scene but the home
## planet's draws its sky the way the home scene does at that point (the home
## ball's up there; LookEnvironment.space_frame), so the sky is the same on both
## sides of any switch, open space included.
func _share_parent_sky(look) -> void:
	var home_id := PlanetGen.home_id()
	if here_id == "" or here_id == home_id:
		return
	var home_port := PlanetGen.system_port(home_id) - PlanetGen.system_port(here_id)
	if not home_port.is_finite():
		return
	var pt := PlanetTerrain.for_planet(PlanetGen.build(home_id))
	if pt == null:
		return
	var home_ball: PlanetSphere = pt.sphere
	pt.free()
	look.space_frame = func(p: Vector3) -> Basis: return home_ball.tilt_at(p - home_port)


## Where the eye starts in this scene: the ship carried in by a handoff, else the port.
func _eye() -> Vector3:
	var a: Dictionary = pilot.demo.get("_arrival") if pilot != null and pilot.get("demo") != null and pilot.demo.get("_arrival") is Dictionary else GameFlow.arrival
	var h: Dictionary = a.get("handoff", {}) if str(a.get("mode", "")) == "handoff" else {}
	return h.get("position", Vector3.ZERO)


## A neighbour that is drawn as its real ball when close (a ball planet with a bubble).
static func _wants_real(n: Dictionary) -> bool:
	return float(n.get("bands", 0.0)) <= 0.0 and bool(n.get("ball", false)) and _real_ball(n)


## Issue #573: a cheap ball within real_ball_within metres of the ship becomes its
## real coarse ball, built a step a frame (or taken from the pool), well before
## its bubble, so the switch changes only the detail.
func _upgrade_near(pos: Vector3) -> void:
	if not _with_looks:
		return
	var near_ok := float(PlanetGen.space_cfg().get("real_ball_within", 6000.0))
	for b in bodies:
		if bool(b.real) or pos.distance_to(b.at) - float(b.radius) > near_ok:
			continue
		b.real = true
		var pooled := _take_pooled(b.n)
		if pooled != null:
			add_child(pooled)
			if b.node != null:
				b.node.queue_free()
			b.node = pooled
		else:
			_start_build(b.n, false)
		return


## A neighbour as seen from here: a rock for a small body, a planet for a big one.
## Issue #99: a ball type with a handoff (the asteroid) is its real ball and
## station, coarse, so arriving changes only the detail.
func _body(n: Dictionary, real_ok := true) -> Node3D:
	if float(n.get("bands", 0.0)) > 0.0:
		return _gas_body(n)          # the ringed giant: its banded ball and its ring
	if real_ok and bool(n.get("ball", false)) and _real_ball(n):
		var real := _ball_body(n)
		if real != null:
			return real
	var r := float(n.radius)
	var mi := MeshInstance3D.new()
	mi.name = "Planet_" + str(n.id)
	var rocky := _rocky(n)
	mi.mesh = body_mesh(n)
	if bool(n.get("ball", false)) and str(n.type) == "sand":
		# Issue #77: the home planet seen from space is the same sand you walk on:
		# its dunes' colours and the dusk side of one real sun (and its noise, which
		# that scene already made: nothing new on a handoff's first frame).
		var sand := ShaderMaterial.new()
		sand.shader = DesertTerrain.SAND_SHADER
		sand.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(512, 3, 0.01))
		sand.set_shader_parameter("planet_center", n.at)
		sand.set_shader_parameter("planet_radius", r)
		sand.set_shader_parameter("glitter", 0.0)
		if str(n.get("relief", "")) != "":
			# Its dunes as a flat print on a smooth ball (not a lumpy faceted rock).
			sand.set_shader_parameter("relief_tex", relief_tex(str(n.relief)))
			sand.set_shader_parameter("relief", 1.0)
			sand.set_shader_parameter("relief_tilt", float(n.get("relief_tilt", 1.0)))
			sand.set_shader_parameter("relief_crest", float(n.get("relief_crest", 0.12)))
		mi.material_override = sand
		_sand_bodies.append(sand)
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = n.color
		m.albedo_texture = LookEnvironment.make_noise_texture(256, 3, 0.02)
		m.roughness = 0.95
		m.rim_enabled = not rocky
		m.rim = 0.6
		m.rim_tint = 0.4
		mi.material_override = m
	mi.position = n.at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = r
	return mi


## A banded gas ball with its ring (the ringed giant): the sky painting's look,
## real. The ring lies in the plane normal to ring.normal, from ring.inner to
## ring.outer planet radii; it is a look, not solid.
func _gas_body(n: Dictionary) -> Node3D:
	var r := float(n.radius)
	var root := Node3D.new()
	root.name = "Planet_" + str(n.id)
	root.position = n.at
	var ring: Dictionary = n.get("ring", {})
	var rn := GameFlow.vec(ring.get("normal", [0.25, 0.95, 0.2])).normalized()
	var mi := MeshInstance3D.new()
	mi.name = "Ball"
	var seen := n.duplicate()
	seen.radius = float(n.get("cloud_radius", r))    # a gas ball's cloud tops, as its own scene draws them
	mi.mesh = body_mesh(seen)
	var m := ShaderMaterial.new()
	m.shader = GAS_SHADER
	m.set_shader_parameter("color_a", n.color)
	m.set_shader_parameter("color_b", n.dark)
	m.set_shader_parameter("bands", float(n.bands))
	m.set_shader_parameter("ring_normal", rn)
	set_gas_fog(m, n.get("haze", {}), seen.radius)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = r
	root.add_child(mi)
	_gas_mats.append(m)
	var hz := make_haze(n.at, seen.radius, n.get("haze", {}))
	if hz != null:
		root.add_child(hz)
		hz.position = Vector3.ZERO
		_gas_mats.append(hz.material_override)
	if not ring.is_empty():
		var rmi := make_ring(n.at, r, ring)
		root.add_child(rmi)
		rmi.position = Vector3.ZERO
		_gas_mats.append(rmi.material_override)
	return root


## A gas giant's air (gas_haze.gdshader): a shell `haze.top` metres over its cloud
## tops (radius cloud_r) round `center`, thickening down to them: a soft glowing
## edge from space, and fog over the clouds up close. The same in its neighbours'
## sky and its own scene, so nothing jumps at the handoff. null when the planet's
## body has no haze. Placed at `center` in world space (its parent at the origin).
static func make_haze(center: Vector3, cloud_r: float, haze: Dictionary) -> MeshInstance3D:
	if haze.is_empty():
		return null
	var top := float(haze.get("top", 3000.0))
	var sm := SphereMesh.new()
	sm.radius = cloud_r + top
	sm.height = 2.0 * (cloud_r + top)
	sm.radial_segments = 96
	sm.rings = 48
	var mi := MeshInstance3D.new()
	mi.name = "Haze"
	mi.mesh = sm
	mi.position = center
	var m := ShaderMaterial.new()
	m.shader = HAZE_SHADER
	m.render_priority = -1              # under the ring, the station's glass and shields
	m.set_shader_parameter("center", center)
	m.set_shader_parameter("cloud_r", cloud_r)
	m.set_shader_parameter("top", top)
	for k in ["low_density", "low_height", "high_density", "high_height"]:
		if haze.has(k):
			m.set_shader_parameter(k, float(haze[k]))
	m.set_shader_parameter("day_color", Color(str(haze.get("day", "#ecdccf"))))
	m.set_shader_parameter("night_color", Color(str(haze.get("night", "#463a56"))))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = cloud_r + top
	return mi


## The ball's close-up fog (gas_giant.gdshader): its colours from the planet's
## body.haze, and the cloud tops' radius for the billows' scale.
static func set_gas_fog(m: ShaderMaterial, haze: Dictionary, cloud_r: float) -> void:
	m.set_shader_parameter("radius_m", cloud_r)
	if haze.is_empty():
		return
	m.set_shader_parameter("fog_color", Color(str(haze.get("day", "#ecdccf"))))
	m.set_shader_parameter("night_color", Color(str(haze.get("night", "#463a56"))))
	m.set_shader_parameter("fog_near", float(haze.get("fog_near", 1600.0)))


## A gas giant's ring round `center` (radius r): a flat band in the plane normal
## to ring.normal, from ring.inner to ring.outer radii (gas_ring.gdshader). A
## look only, not solid. Placed at `center` in world space (its parent at the origin).
static func make_ring(center: Vector3, r: float, ring: Dictionary) -> MeshInstance3D:
	var rn := GameFlow.vec(ring.get("normal", [0.25, 0.95, 0.2])).normalized()
	var outer := float(ring.get("outer", 2.5))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (2.0 * outer * r)
	var rmi := MeshInstance3D.new()
	rmi.name = "Ring"
	rmi.mesh = plane
	var side := rn.cross(Vector3.FORWARD if absf(rn.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	rmi.basis = Basis(side, rn, side.cross(rn)).orthonormalized()
	rmi.position = center
	var rm := ShaderMaterial.new()
	rm.shader = RING_SHADER
	rm.set_shader_parameter("ring_color", Color(str(ring.get("color", "#e8d6c0"))))
	rm.set_shader_parameter("center", center)
	rm.set_shader_parameter("radius", r)
	rm.set_shader_parameter("inner", float(ring.get("inner", 1.35)))
	rm.set_shader_parameter("outer", outer)
	rmi.material_override = rm
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rmi.extra_cull_margin = outer * r
	return rmi


## A neighbour's ball mesh (a noisy rock for a small body, a plain sphere for a
## big one), made once a session: ~25 ms of noise per ball, which a handoff's scene
## would otherwise spend on its first frame. prewarm_bodies() makes them on a
## worker thread before the switch.
static var _body_meshes := {}          ## "id/radius" -> Mesh, or { task, out } while a worker makes it
## A real ball's seated sphere (_ball_body), made once a session too (~14 ms of
## craters). Read only once seated, so scenes can share it.
static var _ball_spheres := {}         ## "id/radius" -> AsteroidSphere


## Issue #573: a ball's relief print (a cubemap from disk, ~30 ms), kept for the
## session so a switch never loads it again; prewarm_bodies starts it on a thread.
static var _reliefs := {}              ## path -> Texture


static func relief_tex(path: String) -> Texture:
	if not _reliefs.has(path):
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_reliefs[path] = ResourceLoader.load_threaded_get(path)
		else:
			_reliefs[path] = load(path)
	return _reliefs[path]


static func body_mesh(n: Dictionary) -> Mesh:
	var key := "%s/%d" % [str(n.id), int(n.radius)]
	var got = _body_meshes.get(key)
	if got is Dictionary:
		WorkerThreadPool.wait_for_task_completion(int(got.task))
		got = (got.out as Array)[0]
		_body_meshes[key] = got
	if got == null:
		got = _make_body_mesh(n)
		_body_meshes[key] = got
	return got


static func _make_body_mesh(n: Dictionary) -> Mesh:
	var r := float(n.radius)
	var noise := FastNoiseLite.new()
	noise.seed = NameEngine.fnv(str(n.id)) % 1000
	noise.frequency = 1.4 / r
	noise.fractal_octaves = 3
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var rocky := _rocky(n)
	if float(n.get("bands", 0.0)) > 0.0:
		return sphere           # a gas ball is smooth
	if str(n.get("relief", "")) != "":
		sphere.radial_segments = 192    # smooth: the dunes are in the print (sand.gdshader relief_tex)
		sphere.rings = 96
		return sphere
	return LookMeshKit.rock(sphere, noise, 0.3 if rocky else 0.012, 0.0, 3.0, 0.85 if rocky else 1.0) if rocky or r < 20000.0 else sphere


## The ball meshes planet `id`'s scene will draw in its sky, made on worker threads.
static func prewarm_bodies(id: String) -> void:
	for n in PlanetGen.build(id).get("neighbours", []):
		var rp := str(n.get("relief", ""))
		if rp != "" and not _reliefs.has(rp):
			ResourceLoader.load_threaded_request(rp)
		var key := "%s/%d" % [str(n.id), int(n.radius)]
		if _body_meshes.has(key):
			continue
		var out := [null]
		var nn: Dictionary = n
		var task := WorkerThreadPool.add_task(func(): out[0] = _make_body_mesh(nn), false, "planet body prewarm")
		_body_meshes[key] = { "task": task, "out": out }


## Issue #99: the neighbour's own ball (its AsteroidSphere, seated on its own
## station's footprint) at far detail, in its rock, and its station on top: the
## very shapes its own scene builds, placed at its port's offset here.
## Issue #573: taken from the session's pool when another scene built it already.
func _ball_body(n: Dictionary) -> Node3D:
	var pooled := _take_pooled(n)
	if pooled != null:
		return pooled
	var b := _ball_steps(n, staged)
	if b.is_empty():
		return null
	var queue: Array = b.steps
	while not queue.is_empty():
		var more = (queue.pop_front() as Callable).call()
		if more is Array:
			queue = (more as Array) + queue
	return b.root


## The real ball as steps (issue #573): the terrain's coarse far mesh, then the
## station's exterior a piece at a time (a step may return more steps). `coarse`:
## the far mesh starts coarse and refines itself over the frames after.
func _ball_steps(n: Dictionary, coarse: bool) -> Dictionary:
	var p := PlanetGen.build(str(n.id))
	var tcfg: Dictionary = p.get("type_cfg", {})
	var surf: Dictionary = tcfg.get("surface", {})
	if p.is_empty() or str(tcfg.get("ground", "")) != "ball":
		return {}
	var root := Node3D.new()
	root.name = "Planet_" + str(n.id)
	root.position = n.get("offset", n.at)
	var steps: Array = []
	steps.append(func():
		var key := "%s/%d" % [str(n.id), int(n.radius)]
		var sp: AsteroidSphere = _ball_spheres.get(key)
		if sp == null:
			sp = AsteroidSphere.new(float(n.radius), surf)
			var site := site_of(p.town)
			sp.configure_site(site.floor, site.walls, site.sunken, 0.0)
			_ball_spheres[key] = sp
		var pt := PlanetTerrain.new()
		pt.name = "Terrain"
		pt.use_sphere(sp)
		pt.cache_key = "body/" + key
		pt.keep_far = true
		pt.use_surface(surf)                 # issue #272: and its lava, if any
		pt.far_chunks = 3
		pt.far_cells = 40
		root.add_child(pt)
		pt.build_far_only(n.at, coarse)      # issue #121: coarse first on a handoff
		_track(pt.material))
	if pilot != null and pilot.demo != null and bool(tcfg.get("enclosed", false)):
		var mats: LookMaterials = pilot.demo._flat_mats()
		steps.append(func():
			var ext := AsteroidWorld.new()
			root.add_child(ext)
			return ext.exterior_steps(p.town.get("station", {}), mats))
	return { "root": root, "steps": steps }


## The sun on a ball's ground material (now, or once this travel is ready).
func _track(m: Material) -> void:
	if m == null:
		return
	if _look != null:
		_look.track_material(m)
	else:
		_sand_bodies.append(m)


# ------------------------------------------------------------------ real balls across scenes (issue #573)

## Real balls built by one scene and handed to the next (planet id -> its root,
## out of the tree): leaving a moon, open space draws the moon its scene already
## built, and nothing is built twice in a session.
static var _pool := {}
var _builds: Array = []              ## { id, n, root, queue, own }: real balls built a step a frame
var _own: Node3D                     ## this planet's own real ball, built for the scene after it


static func _pool_put(id: String, root: Node3D) -> void:
	if root == null or not is_instance_valid(root):
		return
	var old: Node3D = _pool.get(id)
	if old != null and is_instance_valid(old) and old != root:
		old.queue_free()
	if root.get_parent() != null:
		root.get_parent().remove_child(root)
	root.visible = true
	_pool[id] = root


## A pooled real ball for neighbour `n`, placed here, or null.
func _take_pooled(n: Dictionary) -> Node3D:
	var root: Node3D = _pool.get(str(n.id))
	_pool.erase(str(n.id))
	if root == null or not is_instance_valid(root):
		return null
	root.position = n.get("offset", n.at)
	var pt := root.get_node_or_null("Terrain") as PlanetTerrain
	if pt != null and pt.material != null:
		pt.material.set_shader_parameter("planet_center", n.at)
		_track(pt.material)
	return root


## Start building neighbour `id`'s real ball (or this planet's own: `own`) a step a frame.
func _start_build(n: Dictionary, own: bool) -> void:
	for x in _builds:
		if str(x.id) == str(n.id):
			return
	var b := _ball_steps(n, true)
	if b.is_empty():
		return
	(b.root as Node3D).visible = not own
	_builds.append({ "id": str(n.id), "n": n, "root": b.root, "queue": b.steps, "own": own })


## One build step a frame; a finished neighbour's ball takes the cheap one's place.
func _build_step() -> void:
	if _builds.is_empty():
		return
	var job: Dictionary = _builds[0]
	var root: Node3D = job.root
	if root.get_parent() == null:
		add_child(root)
	if not (job.queue as Array).is_empty():
		var more = ((job.queue as Array).pop_front() as Callable).call()
		if more is Array:
			job.queue = (more as Array) + (job.queue as Array)
		return
	_builds.pop_front()
	if bool(job.own):
		_own = root
		return
	for b in bodies:
		if str(b.id) == str(job.id):
			if b.node != null and is_instance_valid(b.node):
				b.node.queue_free()
			b.node = root


## This planet's own real ball as its neighbours draw it (at its port, here the
## origin), started on the way out so open space has it ready.
func _prebuild_self() -> void:
	if _own != null or here_id == "" or open or _pool.has(here_id):
		return
	var cfg: Dictionary = PlanetGen.build(here_id).get("cfg", {})
	var n := PlanetGen._neighbour(cfg, Vector3(0, -self_radius, 0), null)
	n["offset"] = Vector3.ZERO
	if not _wants_real(n):
		return
	_start_build(n, true)


## Leaving: the real balls built here go to the pool for the scene after.
func _pool_leaving() -> void:
	if _own != null:
		_pool_put(here_id, _own)
		_own = null
	for b in bodies:
		if bool(b.real) and b.node != null and _wants_real(b.n):
			_pool_put(str(b.id), b.node)
			b.node = null


## A ball neighbour drawn as its own ball (_ball_body): one whose scene takes over
## in mid-flight, so the scene before draws the same shapes and nothing changes
## but the detail. Issue #573: only a ball type (the moons); the home planet is a
## sand ball seen from far off, never flown into from close to its edge.
static func _real_ball(n: Dictionary) -> bool:
	return _rocky(n) and PlanetGen.handoff_altitude(str(n.type)) > 0.0


## A small rocky ball (the asteroid, the lava moon: any "ball" type), not a planet.
static func _rocky(n: Dictionary) -> bool:
	return str(PlanetGen.types().get("types", {}).get(str(n.type), {}).get("ground", "")) == "ball"


## A town's footprint for seating a ball (town_demo.desert_site, from data).
static func site_of(town: Dictionary) -> Dictionary:
	var floor_rect := Rect2()
	var sunken := []
	var first := true
	for b in town.get("boxes", []):
		if str(b.kind) != "floor":
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if float(b.max[1]) < -0.1:
			sunken.append({ "rect": r, "y": float(b.min[1]) })
			continue
		floor_rect = r if first else floor_rect.merge(r)
		first = false
	var bd: Dictionary = town.get("bounds", {})
	var walls := floor_rect
	if not bd.is_empty():
		walls = Rect2(float(bd.min[0]), float(bd.min[1]), float(bd.max[0]) - float(bd.min[0]), float(bd.max[1]) - float(bd.min[1]))
	return { "floor": floor_rect, "walls": walls, "sunken": sunken }
