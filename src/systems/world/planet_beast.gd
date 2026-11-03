class_name PlanetBeast
extends StaticBody3D
## A planet's beast (issue #220; a monstrosity since #266): a giant armoured
## beetle-centipede that crawls about the desert, its long body of legged
## segments following its head's own path over the dunes. Every planet may have one, named in its own file
## (content/core/planets/<id>.json, a "beast" block: name, home, what the locals
## say of it); the numbers every beast shares are content/core/hazards/beast.json,
## and the planet's block may override any of them.
##
##   wander   it has nowhere to be: it crawls in long, lazy curves (never tighter
##            than min_turn_radius_m, so its body never coils over itself) and its
##            pace changes now and then, with no pull toward or away from the town;
##            only a loose leash round its own home spot turns it back if it strays.
##            If it still ends up milling about one spot (stuck_window_s spent
##            covering less than stuck_net_frac of the ground it walked), it picks
##            the way out, away from where it has been, and holds it for a while
##   touch    dead on the spot, whatever your health (on foot, or a speeder into it)
##   hurt     it has hp (1000) and takes bolts and blades like anything else. Hurt
##            by the player, it chases them, faster than a run, until they are
##            chase_give_up_m (1 km) away or dead, then goes back to wandering
##   dead     it sinks into a puddle and stays dead: WorldState flag
##            beast_slain_<planet id>, so it is not built again and the locals know
##
## Now and then it farts: a sound and a puff from its tail end.
##
## Its shell is weathered desert rock (beast_shell.gdshader: strata, cracks, sand
## on its back) and its eyes glow, brighter when it chases, out when it dies.
##
## It rides the ground (WorldGround: the home planet's ball), moved here rather
## than by physics. Its head and every segment are solid to bolts and blades
## (layer 4, "enemies") but nothing collides with it: touching any of it kills.
##
## Issue #402: in a LAN guest's game on the host's planet it is a copy of the
## host's (net_copy): its head goes where the host's goes (net_hear) and its body
## follows the trail as ever; touching it still kills you in your own game. Hits
## from you go to the host's (net_hit) and it dies when the host's does (net_die).

signal killed_player
signal farted
signal provoked
signal gave_up
signal slain
signal unstuck

const DATA := "res://content/core/hazards/beast.json"
const SHELL := preload("res://src/systems/look/shaders/beast_shell.gdshader")
const LAYER_ENEMIES := 1 << 3
const TRAIL_STEP := 0.5

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var planet_id := ""
var cfg: Dictionary = {}              ## the species defaults with the planet's block laid over
var beast_name := "the beast"
var radius := 3.6
var hp := 1000.0
var max_hp := 1000.0
var dead := false
var chasing := false
var home := Vector3.ZERO
var heading := Vector3.FORWARD        ## along the ground
var speed := 2.0
var kills := 0
var farts := 0
var hits_taken := 0
var travelled := 0.0                  ## metres crawled (traces)
var unsticks := 0                     ## times it found itself milling about and walked out
var _rng := RandomNumberGenerator.new()
var _ball: Node3D                     ## the head
var _mat: Material                    ## the carapace (armour plates): stone, or plain chitin with the look off
var _shell_mat: Material
var _leg_mat: Material
var _eye_mat: StandardMaterial3D
var _eye_core_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _curve := 0.0                     ## 1/m: how hard it is turning now (+ = to its left)
var _curve_want := 0.0
var _curve_left := 0.0
var _unstick_left := 0.0
var _unstick_dir := Vector3.ZERO
var _track: Array = []                ## [ground point, travelled] once a second, oldest first (stuck check)
var _track_left := 0.0
var segments: Array = []              ## { node, r, shape }: the body, head to tail
var _legs: Array = []                 ## every leg's hip
var _mandibles: Array = []
var _antennae: Array = []
var _trail: Array[Vector3] = []       ## ground points the head has walked, newest first
var _head_ground := Vector3.ZERO
var _sink := 0.0                      ## 0 alive .. 1 slumped dead
var _shape: CollisionShape3D
var _speed_left := 0.0
var _fart_left := 10.0
var _squash := 0.0
var _t := 0.0
var _wake_left := -1.0
var _sfx: AudioStreamPlayer3D
var net_copy := false                 ## issue #402: a LAN guest's copy of the host's beast
var net_hit: Callable                 ## (amount) -> your hit on the copy, for the host's game
var _net_at := Vector3.INF            ## where the host's head is on the ground
var _net_vel := Vector3.ZERO
var _net_t := 0.0


static func defaults() -> Dictionary:
	var f := FileAccess.open(DATA, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


## The planet's beast (a built planet, PlanetGen.build): the defaults with its
## "beast" block laid over, or {} if it has none.
static func config(planet: Dictionary) -> Dictionary:
	var own: Dictionary = planet.get("beast", {})
	if own.is_empty():
		return {}
	var c := defaults()
	for k in own:
		if k == "lines" and c.get("lines") is Dictionary:
			var l: Dictionary = (c.lines as Dictionary).duplicate()
			l.merge(own.lines, true)
			c.lines = l
		else:
			c[k] = own[k]
	return c


static func slain_flag(id: String) -> String:
	return "beast_slain_" + id


static func is_slain(id: String) -> bool:
	return WorldState.has_flag(slain_flag(id))


## Whether the planet has a beast still alive to build.
static func lives_on(planet: Dictionary) -> bool:
	return not config(planet).is_empty() and not is_slain(str(planet.get("id", "")))


## What the locals say of the planet's beast (its "lore", or "lore_slain" once it
## is dead), [] if it has none.
static func lore(planet: Dictionary) -> Array:
	var c := config(planet)
	if c.is_empty():
		return []
	var key := "lore_slain" if is_slain(str(planet.get("id", ""))) else "lore"
	return c.get(key, c.get("lore", []))


## One line for an AI character's briefing: the beast, by name, and what is said of it.
static func brief(planet: Dictionary) -> String:
	var c := config(planet)
	if c.is_empty():
		return ""
	var nm := str(c.get("name", "the beast"))
	var said := " ".join(PackedStringArray(lore(planet)))
	if is_slain(str(planet.get("id", ""))):
		return "THIS PLANET'S BEAST: %s, a giant armoured beetle-centipede that crawled about the desert and killed anyone it touched. Word is someone killed it. What people say: %s" % [nm, said]
	return "THIS PLANET'S BEAST: %s, a giant armoured beetle-centipede, long as a street, that crawls about the desert on dozens of legs. Anyone it touches dies; hurt it and it chases you a long way. Everyone here knows of it. What people say: %s" % [nm, said]


func setup(town_demo, world_ground: WorldGround, planet: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	player = demo._player
	planet_id = str(planet.get("id", ""))
	cfg = config(planet)
	beast_name = str(cfg.get("name", cfg.get("label", "the beast")))
	radius = float(cfg.get("radius", 3.6))
	max_hp = float(cfg.get("hp", 1000))
	hp = max_hp
	_rng.seed = 220
	name = "PlanetBeast"
	collision_layer = LAYER_ENEMIES
	collision_mask = 0


func _ready() -> void:
	var h: Array = cfg.get("home", [520, 720])
	home = _surface(Vector2(float(h[0]), float(h[1])))
	heading = _flat(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), home).normalized()
	_new_pace()
	_fart_left = _range("fart_every_s", 9.0, 26.0)
	_build_look()
	_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	_shape.shape = sph
	add_child(_shape)
	_place(home)
	_pose()
	var path := str(cfg.get("fart_sound", ""))
	_sfx = AudioStreamPlayer3D.new()
	if path != "" and ResourceLoader.exists(path):
		_sfx.stream = load(path)
	_sfx.unit_size = 16.0
	_sfx.max_distance = 220.0
	add_child(_sfx)


func _range(key: String, a: float, b: float) -> float:
	var r: Array = cfg.get(key, [a, b])
	return _rng.randf_range(float(r[0]), float(r[1]))


## A line from the data with its name put in ("" if there is none).
func line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, "")).replace("{name}", beast_name)


# ------------------------------------------------------------------ ground

func _surface(m: Vector2) -> Vector3:
	var sp := ground.sphere() if ground != null else null
	if sp != null:
		return sp.surface_at(m.x, m.y)
	var hgt := ground.terrain.height_at(m.x, m.y) if ground != null and ground.terrain != null else 0.0
	return Vector3(m.x, hgt, m.y)


func _up(p: Vector3) -> Vector3:
	return ground.up_at(p) if ground != null else Vector3.UP


func _flat(v: Vector3, at: Vector3) -> Vector3:
	var u := _up(at)
	return v - u * v.dot(u)


## The ground point under (about) `at`.
func _ground_at(at: Vector3) -> Vector3:
	return ground.surface_below(at + _up(at) * 6.0) if ground != null else Vector3(at.x, 0.0, at.z)


# ------------------------------------------------------------------ look

## Issue #266: a giant armoured beetle-centipede. A beetle's head (horn, curved
## mandibles, antennae, glowing eyes) and a long body of armoured segments, each
## with a pair of walking legs, that follows the head's own path over the dunes.
func _build_look() -> void:
	var lk: Dictionary = cfg.get("look", {})
	_mat = _stone("carapace", Color(str(lk.get("carapace", cfg.get("color", "#5a4632")))), 0.3, 0.35)
	_shell_mat = _stone("shell", Color(str(lk.get("shell", "#a07f55"))), 0.0, 0.7)
	_leg_mat = _stone("legs", Color(str(lk.get("legs", "#3a2d22"))), 0.2, 0.45)
	var bone := _stone("mandibles", Color(str(lk.get("mandibles", "#d8c7a0"))), 0.0, 0.3)
	var eyes: Dictionary = lk.get("eyes", {})
	var glow := Color(str(cfg.get("glow", "#c07aff")))
	_eye_mat = _glow_mat(glow, float(eyes.get("energy", 4.0)))
	_eye_core_mat = _glow_mat(glow.lerp(Color.WHITE, float(eyes.get("core_white", 0.6))), float(eyes.get("core_energy", 9.0)))
	var pupil := StandardMaterial3D.new()
	pupil.albedo_color = Color(str(eyes.get("pupil", "#120a06")))
	pupil.roughness = 0.2
	var r := radius
	# ---- the head (forward is -Z)
	_ball = Node3D.new()
	_ball.name = "Head"
	add_child(_ball)
	_ball.top_level = true
	_sphere(_ball, r * 0.95, Vector3(1.15, 0.75, 1.0), Vector3.ZERO, _mat)
	_sphere(_ball, r * 0.62, Vector3(1.2, 0.8, 1.0), Vector3(0, -0.2 * r, -0.62 * r), _shell_mat)
	for sx in [-1.0, 1.0]:
		# Eyes: a glowing orb with a white-hot core and a slit pupil; a smaller pair above.
		for e in [[0.17, Vector3(sx * 0.5 * r, 0.12 * r, -0.72 * r)], [0.1, Vector3(sx * 0.3 * r, 0.3 * r, -0.8 * r)]]:
			var er: float = r * float(e[0])
			var at: Vector3 = e[1]
			var out := Vector3(sx * 0.45, 0.15, -1.0).normalized()
			_sphere(_ball, er, Vector3.ONE, at, _eye_mat)
			_sphere(_ball, er * 0.54, Vector3.ONE, at + out * er * 0.5, _eye_core_mat)
			var slit := _sphere(_ball, er * 0.5, Vector3.ONE, at + out * er * 0.98, pupil)
			slit.basis = Basis.looking_at(out, Vector3.UP) * Basis.from_scale(Vector3(0.16, 1.5, 0.3))
		# Mandibles: curved pincers that open and close.
		var m := Node3D.new()
		m.name = "Mandible"
		m.position = Vector3(sx * 0.45 * r, -0.35 * r, -0.85 * r)
		_ball.add_child(m)
		_mandibles.append(m)
		var pts := [Vector3.ZERO, Vector3(sx * 0.35 * r, 0, -0.6 * r), Vector3(sx * 0.18 * r, 0, -1.2 * r), Vector3(-sx * 0.25 * r, -0.05 * r, -1.5 * r)]
		for i in 3:
			_limb(m, pts[i], pts[i + 1], r * (0.16 - 0.045 * i), r * (0.12 - 0.045 * i), bone)
		for i in 3:
			var at: Vector3 = (pts[1] as Vector3).lerp(pts[2], i / 2.0)
			_limb(m, at, at + Vector3(-sx * 0.22 * r, 0, -0.05 * r), r * 0.05, 0.0, bone)
		# Antennae: long, jointed, swaying.
		var a := Node3D.new()
		a.name = "Antenna"
		a.position = Vector3(sx * 0.35 * r, 0.45 * r, -0.6 * r)
		_ball.add_child(a)
		_antennae.append(a)
		var ap := [Vector3.ZERO, Vector3(sx * 0.5 * r, 0.9 * r, -0.6 * r), Vector3(sx * 1.1 * r, 1.4 * r, -1.6 * r), Vector3(sx * 1.6 * r, 1.3 * r, -2.6 * r)]
		for i in 3:
			_limb(a, ap[i], ap[i + 1], r * (0.06 - 0.015 * i), r * (0.045 - 0.015 * i), _leg_mat)
	_limb(_ball, Vector3(0, 0.45 * r, -0.5 * r), Vector3(0, 1.3 * r, -1.5 * r), r * 0.2, 0.0, bone)   # the horn
	if _looks():
		# The eyes light what is in front of them (the jaws, the sand) at dusk and night.
		_eye_light = OmniLight3D.new()
		_eye_light.name = "EyeGlow"
		_eye_light.light_color = glow
		_eye_light.light_energy = float(eyes.get("light", 1.6))
		_eye_light.omni_range = r * float(eyes.get("light_range_r", 3.5))
		_eye_light.shadow_enabled = false
		_eye_light.position = Vector3(0, 0.15 * r, -1.2 * r)
		_ball.add_child(_eye_light)
	# ---- the body: segments, each with a pair of legs
	var n := int(cfg.get("segments", 14))
	for i in n:
		var f := float(i) / maxf(1.0, n - 1.0)
		var sr := r * lerpf(0.85, float(cfg.get("tail_scale", 0.45)), f)
		var seg := Node3D.new()
		seg.name = "Seg%d" % i
		add_child(seg)
		seg.top_level = true
		_sphere(seg, sr, Vector3(1.35, 0.7, 1.15), Vector3.ZERO, _shell_mat)
		_sphere(seg, sr * 1.05, Vector3(1.4, 0.4, 0.95), Vector3(0, 0.32 * sr, 0.1 * sr), _mat)
		for sx in [-0.45, 0.45]:
			_limb(seg, Vector3(sx * sr, 0.6 * sr, 0), Vector3(sx * sr * 1.2, 1.15 * sr, 0.45 * sr), sr * 0.12, 0.0, _mat)
		for sx in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.name = "Leg%d" % (0 if sx < 0 else 1)
			hip.position = Vector3(sx * 1.1 * sr, -0.1 * sr, 0)
			hip.set_meta("side", sx)
			seg.add_child(hip)
			var knee := Vector3(sx * 0.8 * sr, 0.75 * sr, 0)
			var foot := Vector3(sx * 1.35 * sr, -0.9 * sr, -0.15 * sr)
			_limb(hip, Vector3.ZERO, knee, sr * 0.13, sr * 0.1, _leg_mat)
			_limb(hip, knee, foot, sr * 0.1, sr * 0.03, _leg_mat)
			_legs.append(hip)
		if i == n - 1:
			for sx in [-1.0, 1.0]:     # tail spikes
				_limb(seg, Vector3(sx * 0.3 * sr, 0.1 * sr, 0.6 * sr), Vector3(sx * 0.9 * sr, 0.4 * sr, 2.4 * sr), sr * 0.12, 0.0, _mat)
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = sr * 1.1
		cs.shape = sph
		add_child(cs)
		segments.append({ "node": seg, "r": sr, "shape": cs })
	_seed_trail()


func _looks() -> bool:
	return demo != null and bool(demo.get("use_look"))


## One part's shell: weathered stone (beast_shell.gdshader) in the part's colour,
## with its strata, cracks and lumps from the data's look.stone block; plain
## chitin where the look is off (headless runs), as cheap as it was.
func _stone(part: String, c: Color, metal: float, rough: float) -> Material:
	if not _looks():
		return _chitin(c, metal, rough)
	var st: Dictionary = cfg.get("look", {}).get("stone", {})
	var p: Dictionary = st.get(part, {})
	var dust := Color(str(st.get("dust", "#d3ad78")))
	var m := ShaderMaterial.new()
	m.shader = SHELL
	m.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(512, 7, 0.012))
	m.set_shader_parameter("rock_a", c.darkened(0.25))
	m.set_shader_parameter("rock_b", c.lerp(dust, 0.35))
	m.set_shader_parameter("rock_dark", c.darkened(0.62))
	m.set_shader_parameter("dust", dust)
	m.set_shader_parameter("strata", float(p.get("strata", 3.0)))
	m.set_shader_parameter("cracks", float(p.get("cracks", 1.0)))
	m.set_shader_parameter("bump", float(p.get("bump", 1.0)))
	m.set_shader_parameter("dust_amount", float(p.get("dust", 1.0)))
	var sp := ground.sphere() if ground != null else null
	if sp != null:
		m.set_shader_parameter("planet_center", sp.center)
		m.set_shader_parameter("planet_radius", sp.radius)
	return m


## Lit, with a dark body: unshaded would drop the emission, so it would never
## get bright enough for the glow to bloom.
static func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.7)
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.set_meta("energy", energy)
	return m


static func _chitin(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.4
	return m


static func _sphere(parent: Node3D, r: float, sc: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	mi.scale = sc
	parent.add_child(mi)
	return mi


## A tapered rod from a to b (r0 at a, r1 at b).
static func _limb(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = maxf(d.length(), 0.001)
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	if d.length() > 0.0001:
		var dir := d.normalized()
		mi.basis = Basis(Quaternion(Vector3.UP, dir)) if dir.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ the body follows the head

## The path the head has walked (ground points, newest first), straight out
## behind it at the start.
func _seed_trail() -> void:
	_trail.clear()
	for i in int(_body_len() / TRAIL_STEP) + 6:
		_trail.append(_ground_at(home - heading * (i + 1) * TRAIL_STEP))
	_head_ground = home


func _body_len() -> float:
	return float(cfg.get("segment_gap", 3.2)) * (int(cfg.get("segments", 14)) + 1) + radius


func _push_trail(g: Vector3) -> void:
	_head_ground = g
	if _trail.is_empty() or g.distance_to(_trail[0]) >= TRAIL_STEP:
		_trail.push_front(g)
		var keep := int(_body_len() / TRAIL_STEP) + 6
		if _trail.size() > keep:
			_trail.resize(keep)


## Lay the segments along the trail, legs stepping in a wave; the head turns to
## its heading, mandibles working, antennae swaying.
func _pose() -> void:
	if _ball == null:
		return
	var up := _up(global_position)
	var pitch := 0.08 * sin(_t * 1.7) - 0.5 * _sink
	var fwd := (heading * cos(pitch) + up * sin(pitch)).normalized()
	_ball.global_transform = Transform3D(Basis.looking_at(fwd, up), global_position)
	var open := 1.0 if dead else 0.5 + 0.5 * sin(_t * (3.0 if chasing else 1.3))
	for m in _mandibles:
		(m as Node3D).rotation = Vector3(0, signf((m as Node3D).position.x) * (-0.15 + 0.55 * open), 0)
	for i in _antennae.size():
		(_antennae[i] as Node3D).rotation = Vector3(0.2 * sin(_t * 1.1 + i), 0.15 * sin(_t * 0.7 + i * 2.0), 0) * (1.0 - _sink)
	# The eyes smoulder, flare when it chases, and go out as it dies.
	var eyes: Dictionary = cfg.get("look", {}).get("eyes", {})
	var glow := (1.0 + float(eyes.get("pulse", 0.15)) * sin(_t * 2.3)) * (float(eyes.get("chase", 1.7)) if chasing else 1.0) * (1.0 - _sink)
	for em in [_eye_mat, _eye_core_mat]:
		if em != null:
			(em as StandardMaterial3D).emission_energy_multiplier = float(em.get_meta("energy", 1.0)) * glow
	if _eye_light != null:
		_eye_light.light_energy = float(eyes.get("light", 1.6)) * glow
	# Walk the trail once, placing each segment its gap further back.
	var gap := float(cfg.get("segment_gap", 3.2))
	var want := radius * 0.9
	var prev := _head_ground
	var acc := 0.0
	var ti := 0
	var pts: Array[Vector3] = []
	for s in segments:
		var p := prev
		while ti < _trail.size():
			var q: Vector3 = _trail[ti]
			var d := prev.distance_to(q)
			if acc + d >= want:
				p = prev.lerp(q, (want - acc) / maxf(d, 0.0001))
				break
			acc += d
			prev = q
			p = q
			ti += 1
		pts.append(p + _up(p) * float(s.r) * (1.0 - 0.65 * _sink))
		want += gap
	var stride := float(cfg.get("stride_m", 4.0))
	for i in segments.size():
		var s: Dictionary = segments[i]
		var ahead: Vector3 = global_position if i == 0 else pts[i - 1]
		var tan := ahead - pts[i]
		var u := _up(pts[i])
		var node: Node3D = s.node
		if tan.length() < 0.01 or absf(tan.normalized().dot(u)) > 0.95:
			# Bunched up (or the body runs straight up): keep facing the way it was,
			# rather than snapping round to the head's heading every frame.
			tan = _flat(-node.global_basis.z, pts[i])
			if tan.length() < 0.01:
				tan = heading
		node.global_transform = Transform3D(Basis.looking_at(tan.normalized(), u), pts[i])
		if i == segments.size() - 1:
			node.scale = Vector3.ONE * (1.0 + 0.25 * _squash)
		(s.shape as CollisionShape3D).position = pts[i] - global_position
		for leg in node.get_children():
			if str(leg.name).begins_with("Leg"):
				var side: float = leg.get_meta("side", 1.0)
				var ph := travelled / stride * TAU + i * 0.9 + (PI if side < 0 else 0.0)
				var lift := side * (0.18 * maxf(0.0, cos(ph)) + 0.9 * _sink)
				(leg as Node3D).rotation = Vector3(0, 0.4 * sin(ph) * (1.0 - _sink), lift)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_t += dt
	_tick_wake(dt)
	if dead:
		_place(_head_ground)
		_pose()
		return
	if net_copy:
		_follow(dt)
		_squash = move_toward(_squash, 0.0, dt * 1.6)
		_pose()
		_touch()
		return
	_wander(dt)
	_squash = move_toward(_squash, 0.0, dt * 1.6)
	_pose()
	_touch()
	_tick_fart(dt)


## Aimless: it crawls in long curves that bend one way, then another, now and
## then; the pace changes now and then. Only a loose leash round its own home
## turns it back if it strays very far. Chasing, it steers at the player instead,
## at its chase speed. Either way it turns along a curve (radius at least
## min_turn_radius_m, chase_turn_radius_m in a chase), never on the spot.
func _wander(dt: float) -> void:
	var at := global_position - _up(global_position) * radius
	_speed_left -= dt
	if _speed_left <= 0.0:
		_new_pace()
	var pace := float(cfg.get("chase_speed", 5.5)) if chasing else speed
	if chasing:
		_chase(at)
	else:
		_roam(at, dt)
	heading = _flat(heading.rotated(_up(at), _curve * pace * dt), at).normalized()
	var step := heading * pace * dt
	var next := _ground_at(at + step)
	travelled += step.length()
	_place(next)
	_push_trail(next)
	if not chasing:
		_watch(at, dt)


## The tightest it bends its path, as a curvature (1/m).
func _max_curve() -> float:
	return 1.0 / maxf(0.5, float(cfg.get("chase_turn_radius_m", 6.0) if chasing else cfg.get("min_turn_radius_m", 14.0)))


## The curvature that brings its heading round to `dir`: as tight as it may while
## far off, easing out as it lines up (so it doesn't swing past and back).
func _toward(at: Vector3, dir: Vector3) -> float:
	var d := _flat(dir, at)
	if d.length() < 0.001:
		return 0.0
	var ang := heading.signed_angle_to(d.normalized(), _up(at))
	return _max_curve() * clampf(ang / 0.6, -1.0, 1.0)


## Wandering: now and then it settles on a new bend (most gentle, some tight,
## left or right) and eases into it. The leash and walking out of a muddle
## override that bend while they last.
func _roam(at: Vector3, dt: float) -> void:
	var kmax := _max_curve()
	_curve_left -= dt
	if _curve_left <= 0.0:
		_curve_left = _range("turn_change_s", 4.0, 12.0)
		_curve_want = clampf(_rng.randfn() / maxf(1.0, float(cfg.get("turn_radius_m", 40.0))), -kmax, kmax)
	var want := _curve_want
	if _unstick_left > 0.0:
		_unstick_left -= dt
		want = _toward(at, _unstick_dir)
	elif at.distance_to(home) > float(cfg.get("leash_m", 1400.0)):
		want = _toward(at, home - at)
	_curve = move_toward(_curve, want, dt * kmax / maxf(0.1, float(cfg.get("turn_ease_s", 2.0))))


## Is it milling about? Once a second, note where it is; if over the last
## stuck_window_s it has ended up less than stuck_net_frac of the way it walked
## from where it started (going round in circles, or caught on something and
## treading sand), it walks out.
func _watch(at: Vector3, dt: float) -> void:
	_track_left -= dt
	if _track_left > 0.0:
		return
	_track_left = 1.0
	_track.append([at, travelled])
	var win := maxi(2, int(cfg.get("stuck_window_s", 20.0)))
	if _track.size() > win + 1:
		_track.pop_front()
	if _unstick_left > 0.0 or _track.size() <= win:
		return
	var walked := travelled - float(_track[0][1])
	if walked > 4.0 and at.distance_to(_track[0][0]) < walked * float(cfg.get("stuck_net_frac", 0.3)):
		_unstick(at)


## Out of the muddle: away from the middle of where it has been milling about
## and of its own (likely coiled) body, held for unstick_s before it wanders again.
func _unstick(at: Vector3) -> void:
	unsticks += 1
	var mid := Vector3.ZERO
	for p in _track:
		mid += p[0] as Vector3
	for s in segments:
		mid += (s.node as Node3D).global_position
	mid /= maxf(1.0, _track.size() + segments.size())
	var away := _flat(at - mid, at)
	if away.length() < 0.5:
		away = heading.rotated(_up(at), PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0))
	_unstick_dir = away.normalized()
	_unstick_left = _range("unstick_s", 15.0, 25.0)
	_curve_want = 0.0
	_track.clear()
	unstuck.emit()


## After the player: steer at them; give up once they are far enough away (or dead).
func _chase(at: Vector3) -> void:
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		_calm()
		return
	var to := _flat(player.global_position - at, at)
	if to.length() > float(cfg.get("chase_give_up_m", 1000.0)):
		_calm()
		_toast(line("gave_up"))
		return
	_curve = _toward(at, to)


func _calm() -> void:
	if not chasing:
		return
	chasing = false
	_curve = clampf(_curve, -_max_curve(), _max_curve())
	_curve_left = 0.0
	_unstick_left = 0.0
	_track.clear()
	_new_pace()
	gave_up.emit()


func _new_pace() -> void:
	speed = _range("speed", 1.2, 3.4)
	_speed_left = _range("speed_change_s", 3.0, 8.0)


# ------------------------------------------------------------------ LAN copy (issue #402)

## The host's beast now: its head on the ground, its heading, chasing, its health.
func net_hear(at: Vector3, head: Vector3, chase: bool, health: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _net_at != Vector3.INF and now - _net_t > 0.03:
		_net_vel = (at - _net_at) / (now - _net_t)
	if _net_at == Vector3.INF or at.distance_to(_head_ground) > float(cfg.get("net_snap_m", 25.0)):
		home = at                  # first word, or far off: it is there, body and all
		heading = _flat(head, at).normalized()
		_seed_trail()
		_place(at)
	_net_at = at
	_net_t = now
	heading = _flat(head, at).normalized() if head.length() > 0.01 else heading
	chasing = chase
	hp = health


## Crawl after the host's head, a little ahead of where it was last heard.
func _follow(dt: float) -> void:
	if _net_at == Vector3.INF:
		return
	var since := clampf(Time.get_ticks_msec() / 1000.0 - _net_t, 0.0, 0.3)
	var want := _ground_at(_net_at + _net_vel * since)
	var step := (want - _head_ground) * (1.0 - exp(-8.0 * dt))
	travelled += step.length()
	var next := _ground_at(_head_ground + step)
	_place(next)
	_push_trail(next)


## The host's beast died: so does this one, slumping as it does.
func net_die() -> void:
	if not dead:
		_die()


func _place(ground_point: Vector3) -> void:
	var u := _up(ground_point)
	global_position = ground_point + u * radius * (1.0 - 0.6 * _sink)


# ------------------------------------------------------------------ hurt, dead

## Bolts call this (bolt.gd). Only the player (on foot, or in what they ride)
## sets it chasing; a stray bolt from anyone else just hurts.
func apply_damage_from(amount: float, shooter: Node) -> void:
	_hurt(amount, _is_player(shooter))


## Blades and anything that does not say who: only the player swings a blade here.
func apply_damage(amount: float) -> void:
	_hurt(amount, true)


func apply_blade_hit(amount: float, _dir: Vector3) -> void:
	_hurt(amount, true)


func _is_player(shooter: Node) -> bool:
	if shooter == null or player == null or not is_instance_valid(shooter):
		return shooter == null
	if shooter == player:
		return true
	var v = player.get("vehicle") if bool(player.get("piloting")) else null
	return v is Node and is_instance_valid(v) and (shooter == v or (v as Node).is_ancestor_of(shooter))


func _hurt(amount: float, by_player: bool) -> void:
	if dead or amount <= 0.0:
		return
	if net_copy:
		_squash = maxf(_squash, 0.5)
		if by_player and net_hit.is_valid():
			net_hit.call(amount)           # the host's game says what it did
		return
	hits_taken += 1
	hp -= amount
	_squash = maxf(_squash, 0.5)
	if hp <= 0.0:
		_die()
		return
	if by_player and not chasing:
		chasing = true
		_toast(line("provoked"))
		provoked.emit()


## It slumps, legs curling, and stays dead (the flag keeps it from being built
## again, and the locals hear of it).
func _die() -> void:
	hp = 0.0
	dead = true
	chasing = false
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if planet_id != "":
		WorldState.set_flag(slain_flag(planet_id))
	WorldState.log_event("Killed %s, the beast." % beast_name)
	_toast(line("slain"))
	for s in segments:
		(s.shape as CollisionShape3D).set_deferred("disabled", true)
	create_tween().tween_property(self, "_sink", 1.0, 2.5)       # it slumps and its legs curl
	slain.emit()


# ------------------------------------------------------------------ touch = death

func _touch() -> void:
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		return
	var parts := [[global_position, radius]]          # the head, then every segment
	for s in segments:
		parts.append([(s.node as Node3D).global_position, float(s.r) * 1.2])
	if bool(player.get("piloting")):
		var v = player.get("vehicle")
		if v is SpeederNode:
			var at: Vector3 = (v as SpeederNode).model.position
			for p in parts:
				if at.distance_to(p[0]) <= float(p[1]) + float(cfg.get("speeder_margin", 1.4)):
					(v as SpeederNode).dismount()
					_kill()
					return
		return
	var chest := player.global_position + _up(player.global_position) * 0.9
	for p in parts:
		if chest.distance_to(p[0]) <= float(p[1]) + float(cfg.get("kill_margin", 0.35)):
			_kill()
			return


## Dead on the spot. Whoever handles a downed player (the town's garrison) wakes
## them; if nobody does in a few seconds, the beast does it, in the pit.
func _kill() -> void:
	kills += 1
	if "invulnerable_left" in player:
		player.invulnerable_left = 0.0
	player.apply_damage_from(float(player.health.hp) + 9999.0, self)
	_toast(line("killed"))
	_wake_left = 4.0
	_calm()
	killed_player.emit()


func _tick_wake(dt: float) -> void:
	if _wake_left < 0.0:
		return
	if not bool(player.get("is_downed")):
		_wake_left = -1.0
		return
	_wake_left -= dt
	if _wake_left <= 0.0:
		_wake_left = -1.0
		player.global_position = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
		if player.has_method("align_to_ground"):
			player.call("align_to_ground", true)
		player.revive()
		player.locked = false
		_toast(line("woke"))
		var pl = demo.get("pilot")
		if pl != null and is_instance_valid(pl):
			pl.woke_in_pit()             # issue #368: your primary ship is on the pad


func _toast(text: String) -> void:
	var gear = demo.get("gear") if demo != null else null
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 4.0)


# ------------------------------------------------------------------ farts

func _tick_fart(dt: float) -> void:
	_fart_left -= dt
	if _fart_left <= 0.0:
		fart()


## Pfffrt: a sound, a puff from its tail end and a twitch of the tail.
func fart() -> void:
	farts += 1
	_fart_left = _range("fart_every_s", 9.0, 26.0)
	_squash = 1.0
	if _sfx != null and _sfx.stream != null:
		_sfx.pitch_scale = _rng.randf_range(0.8, 1.2)
		_sfx.play()
	if demo != null and bool(demo.get("use_look")):
		_puff()
	farted.emit()


func _puff() -> void:
	var c := Color(str(cfg.get("puff", "#9a8a4a")))
	var tail: Node3D = segments[-1].node if not segments.is_empty() else self
	var base := tail.global_position + tail.global_basis.z * (float(segments[-1].r) * 1.4 if not segments.is_empty() else radius)
	for i in 6:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		sm.radial_segments = 10
		sm.rings = 6
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 0.55)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		demo.add_child(mi)
		var drift := (-heading * _rng.randf_range(0.5, 2.5) + _up(base) * _rng.randf_range(0.3, 1.6)
			+ heading.cross(_up(base)) * _rng.randf_range(-1.2, 1.2))
		mi.global_position = base + drift * 0.3
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", base + drift * 2.2, 2.2)
		tw.tween_property(mi, "scale", Vector3.ONE * _rng.randf_range(2.5, 4.0), 2.2)
		tw.tween_property(m, "albedo_color:a", 0.0, 2.2)
		tw.chain().tween_callback(mi.queue_free)
