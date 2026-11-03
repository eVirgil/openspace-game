class_name ExplosionFx
extends RefCounted
## Explosions, built from code: no textures and no models. Each one is a handful of
## one-shot CPUParticles3D under a Node3D that frees itself when the last of them is
## done, plus a short orange light so the ground and walls catch the flash.
##
##   small(): a droid going pop. A blue-white flash, a spray of sparks, a few bits
##            of casing and a wisp of smoke. About a second.
##   bolt():  a blaster bolt or a blade landing. small()'s flash and sparks with a
##            smaller lick of fire that burns out red rather than to soot; no bits
##            of casing and no smoke.
##   clash(): two energy blades meeting in a parry. A white-hot flash, a little
##            shock ring and a spray of sparks, no fire, smoke or bits. Half a second.
##   big():   a ship or speeder going up. A white flash and a shock ring, a fireball
##            that boils from white through orange to soot, embers and hull chunks
##            thrown out on arcs, then a column of dark smoke. About four seconds.
##
## The fireball and smoke puffs are explosion_puff.gdshader (noise discs that erode
## from the rim as they age); the flash, ring and sparks are explosion_glow.gdshader.

## Loaded at the first explosion, not with the script (every system that can blow
## something up refers to this class).
const PUFF_SHADER := "res://src/systems/look/shaders/explosion_puff.gdshader"
const GLOW_SHADER := "res://src/systems/look/shaders/explosion_glow.gdshader"

static var _m: Dictionary = {}      ## shared meshes, materials, ramps and curves (built once)


## Builds every shared mesh, material, ramp and curve now, so the first explosion
## does not (FxWarmup, as a town is built).
static func warm() -> void:
	_quad()
	_spark_mesh()
	_chunk_mesh()
	for k in ["fire", "smoke", "flash", "ring", "spark", "chunk"]:
		_mat(k)
	for k in ["fire", "fire_clean", "smoke_dark", "smoke_light", "flash_hot", "flash_cold", "ring", "spark_hot", "spark_cold"]:
		_ramp(k)
	for k in ["pop", "ring", "billow", "rise", "shrink"]:
		_curve(k)


## A droid going pop at `at` (its middle).
static func small(parent: Node, at: Vector3) -> Node3D:
	var r := _pop(parent, at, "fire")
	if r == null:
		return null
	_emit(r, _quad(), _mat("smoke"), 4, 1.5, { "delay": 0.1, "radius": 0.15, "speed": Vector2(0.5, 1.1), "dir": Vector3.UP, "spread": 25.0,
		"gravity": Vector3(0, 0.4, 0), "damping": Vector2(0.3, 0.6), "scale": Vector2(0.7, 1.1), "grow": _curve("rise"), "ramp": _ramp("smoke_light"), "spin": 15.0 })
	_free_after(r, 1.7)
	return r


## A blaster bolt (any gun's) or a blade landing at `at`: small()'s flash and
## sparks with a smaller lick of fire that burns out red instead of cooling to
## soot. No bits of casing fly and no smoke hangs about: a clean pop.
static func bolt(parent: Node, at: Vector3) -> Node3D:
	var r := _pop(parent, at, "fire_clean", 0.55, false)
	if r == null:
		return null
	_free_after(r, 1.0)
	return r


## Two blades meeting in a parry at `at` (where they crossed): a small burst of
## sparks. `tint`: the light's colour (the blades' glow).
static func clash(parent: Node, at: Vector3, tint := Color("#ffd2a0")) -> Node3D:
	var r := _root(parent, at)
	if r == null:
		return null
	_light(r, tint, 9.0, 6.0, 0.25)
	_emit(r, _quad(), _mat("flash"), 1, 0.1, { "scale": Vector2(1.6, 1.6), "grow": _curve("pop"), "ramp": _ramp("flash_hot"), "radius": 0.01, "speed": Vector2.ZERO })
	_emit(r, _quad(), _mat("ring"), 1, 0.22, { "scale": Vector2(2.2, 2.2), "grow": _curve("ring"), "ramp": _ramp("ring"), "radius": 0.01, "speed": Vector2.ZERO })
	_emit(r, _spark_mesh(), _mat("spark"), 40, 0.5, { "radius": 0.05, "speed": Vector2(5.0, 12.0), "gravity": Vector3(0, -9.8, 0), "damping": Vector2(2.0, 4.0),
		"scale": Vector2(0.25, 0.45), "grow": _curve("shrink"), "ramp": _ramp("spark_hot"), "streak": true, "spin": 0.0, "life_rand": 0.5 })
	_free_after(r, 0.7)
	return r


## The flash, fire and sparks small() and bolt() share. `fire`: the fire's ramp.
## `smoke`: how much fire there is, 1 being a droid's worth (fewer, smaller puffs
## below that). `bits`: whether hot bits of casing fly out too.
static func _pop(parent: Node, at: Vector3, fire: String, smoke := 1.0, bits := true) -> Node3D:
	var r := _root(parent, at)
	if r == null:
		return null
	_light(r, Color("#bfe0ff"), 6.0, 7.0, 0.3)
	_emit(r, _quad(), _mat("flash"), 1, 0.12, { "scale": Vector2(2.4, 2.4), "grow": _curve("pop"), "ramp": _ramp("flash_cold"), "radius": 0.01, "speed": Vector2.ZERO })
	var puffs := maxi(1, roundi(7.0 * smoke))
	var puff_scale := lerpf(0.75, 1.0, clampf(smoke, 0.0, 1.0))
	_emit(r, _quad(), _mat("fire"), puffs, 0.5, { "radius": 0.2, "speed": Vector2(1.0, 2.6), "damping": Vector2(5.0, 7.0),
		"gravity": Vector3(0, 1.0, 0), "scale": Vector2(0.9, 1.4) * puff_scale, "grow": _curve("billow"), "ramp": _ramp(fire) })
	_emit(r, _spark_mesh(), _mat("spark"), 26, 0.6, { "speed": Vector2(4.0, 9.0), "gravity": Vector3(0, -9.8, 0), "damping": Vector2(1.0, 2.0),
		"scale": Vector2(0.3, 0.5), "grow": _curve("shrink"), "ramp": _ramp("spark_cold"), "streak": true, "spin": 0.0, "life_rand": 0.5 })
	if bits:
		_emit(r, _chunk_mesh(), _mat("chunk"), 6, 0.9, { "speed": Vector2(2.5, 5.5), "dir": Vector3.UP, "spread": 70.0, "gravity": Vector3(0, -12.0, 0),
			"scale": Vector2(0.06, 0.12), "grow": _curve("shrink"), "spin_speed": 540.0 })
	return r


## A ship or speeder going up at `at`. `size` 1 is a ship (a fireball some 5 m
## across); a speeder is about 0.6. `space`: nothing falls and no smoke hangs about.
static func big(parent: Node, at: Vector3, size := 1.0, space := false) -> Node3D:
	var r := _root(parent, at)
	if r == null:
		return null
	var s := maxf(0.1, size)
	var t := pow(s, 0.35)            # bigger burns a little longer, not proportionally
	var fall := Vector3.ZERO if space else Vector3(0, -14.0, 0)
	_light(r, Color("#ffb060"), 14.0, 32.0 * s, 0.8 * t)
	_emit(r, _quad(), _mat("flash"), 1, 0.18 * t, { "scale": Vector2(9.0, 9.0) * s, "grow": _curve("pop"), "ramp": _ramp("flash_hot"), "radius": 0.01, "speed": Vector2.ZERO })
	_emit(r, _quad(), _mat("ring"), 1, 0.4 * t, { "scale": Vector2(20.0, 20.0) * s, "grow": _curve("ring"), "ramp": _ramp("ring"), "radius": 0.01, "speed": Vector2.ZERO })
	_emit(r, _quad(), _mat("fire"), 18, 1.2 * t, { "radius": 1.2 * s, "speed": Vector2(3.0, 9.0) * s, "damping": Vector2(5.0, 8.0) * s,
		"gravity": Vector3(0, 0.0 if space else 1.8, 0) * s, "scale": Vector2(3.2, 5.6) * s, "grow": _curve("billow"), "ramp": _ramp("fire") })
	# A second, later knot of fire inside the first: the burst does not peak all at once.
	_emit(r, _quad(), _mat("fire"), 7, 0.9 * t, { "delay": 0.12, "radius": 0.8 * s, "speed": Vector2(1.5, 4.0) * s, "damping": Vector2(3.0, 5.0) * s,
		"gravity": Vector3(0, 0.0 if space else 2.5, 0) * s, "scale": Vector2(2.0, 3.2) * s, "grow": _curve("billow"), "ramp": _ramp("fire") })
	_emit(r, _spark_mesh(), _mat("spark"), 48, 1.3 * t, { "radius": 0.5 * s, "speed": Vector2(12.0, 30.0) * s, "gravity": fall, "damping": Vector2(2.0, 4.0) * s,
		"scale": Vector2(0.6, 1.3) * s, "grow": _curve("shrink"), "ramp": _ramp("spark_hot"), "streak": true, "spin": 0.0, "life_rand": 0.5 })
	_emit(r, _chunk_mesh(), _mat("chunk"), 12, 1.8 * t, { "radius": 0.6 * s, "speed": Vector2(7.0, 17.0) * s, "dir": Vector3.UP, "spread": 180.0 if space else 75.0,
		"gravity": fall, "scale": Vector2(0.25, 0.6) * s, "grow": _curve("shrink"), "spin_speed": 400.0 })
	if not space:
		_emit(r, _quad(), _mat("smoke"), 12, 3.4 * t, { "delay": 0.3, "burst": 0.7, "radius": 1.4 * s, "speed": Vector2(1.5, 3.5) * s, "dir": Vector3.UP,
			"spread": 30.0, "gravity": Vector3(0, 0.6, 0) * s, "damping": Vector2(0.4, 0.8), "scale": Vector2(3.4, 5.6) * s, "grow": _curve("rise"),
			"ramp": _ramp("smoke_dark"), "spin": 20.0 })
	_free_after(r, (4.0 if not space else 2.2) * t)
	return r


# ------------------------------------------------------------------ building

static func _root(parent: Node, at: Vector3) -> Node3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var r := Node3D.new()
	r.name = "Explosion"
	parent.add_child(r)
	r.global_position = at
	return r


## One one-shot emitter under `r`. `o`: radius, dir, spread (degrees), speed and
## damping (min, max), gravity, scale (min, max), grow (a Curve over its life),
## ramp (a Gradient over its life), spin (start angle range, degrees), spin_speed
## (degrees/s), streak (stretch along its flight), burst (explosiveness), life_rand,
## delay (seconds before it fires).
static func _emit(r: Node3D, mesh: Mesh, mat: Material, amount: int, life: float, o: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = float(o.get("burst", 1.0))
	p.lifetime_randomness = float(o.get("life_rand", 0.3))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.01, float(o.get("radius", 0.1)))
	p.direction = o.get("dir", Vector3.UP)
	p.spread = float(o.get("spread", 180.0))
	p.gravity = o.get("gravity", Vector3.ZERO)
	var v: Vector2 = o.get("speed", Vector2(1.0, 2.0))
	p.initial_velocity_min = v.x
	p.initial_velocity_max = v.y
	var d: Vector2 = o.get("damping", Vector2.ZERO)
	p.damping_min = d.x
	p.damping_max = d.y
	var sc: Vector2 = o.get("scale", Vector2.ONE)
	p.scale_amount_min = sc.x
	p.scale_amount_max = sc.y
	if o.has("grow"):
		p.scale_amount_curve = o.grow
	if o.has("ramp"):
		p.color_ramp = o.ramp
	var spin := float(o.get("spin", 180.0))
	p.angle_min = -spin
	p.angle_max = spin
	var spin_speed := float(o.get("spin_speed", 30.0))
	p.angular_velocity_min = -spin_speed
	p.angular_velocity_max = spin_speed
	# A steady random number per particle for the puff shader's noise (INSTANCE_CUSTOM.z).
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.particle_flag_align_y = bool(o.get("streak", false))
	p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.emitting = false
	r.add_child(p)
	var delay := float(o.get("delay", 0.0))
	if delay > 0.0:
		r.create_tween().tween_callback(p.set.bind("emitting", true)).set_delay(delay)
	else:
		p.emitting = true
	return p


static func _light(r: Node3D, color: Color, energy: float, reach: float, life: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	r.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


static func _free_after(r: Node3D, seconds: float) -> void:
	r.create_tween().tween_callback(r.queue_free).set_delay(seconds)


# ------------------------------------------------------------------ shared resources

static func _quad() -> Mesh:
	if not _m.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_m.quad = q
	return _m.quad


## A spark: a thin box along its Y, which the emitter turns along its flight.
static func _spark_mesh() -> Mesh:
	if not _m.has("spark_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(0.05, 1.0, 0.05)
		_m.spark_mesh = b
	return _m.spark_mesh


static func _chunk_mesh() -> Mesh:
	if not _m.has("chunk_mesh"):
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 0.45, 0.7)
		_m.chunk_mesh = b
	return _m.chunk_mesh


static func _mat(key: String) -> Material:
	var k := "mat_" + key
	if _m.has(k):
		return _m[k]
	var m: Material
	match key:
		"fire":
			m = _puff({ "erode": 0.8, "soft": 0.06, "energy": 2.2, "heat": 1.2, "shade": 0.0, "lumps": 2.4 })
		"smoke":
			m = _puff({ "erode": 0.7, "soft": 0.12, "energy": 1.0, "heat": 0.0, "shade": 1.0, "lumps": 2.0 })
		"flash":
			m = _glow(0, 6.0)
		"ring":
			m = _glow(1, 4.0)
		"spark":
			m = _glow(2, 5.0)
		"chunk":
			var c := StandardMaterial3D.new()
			c.albedo_color = Color("#2b2723")
			c.roughness = 0.85
			c.metallic = 0.3
			# A dull hot glow: fresh off the fire.
			c.emission_enabled = true
			c.emission = Color("#ff5a1e")
			c.emission_energy_multiplier = 0.2
			m = c
	_m[k] = m
	return m


static func _puff(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PUFF_SHADER)
	for p in params:
		m.set_shader_parameter(p, params[p])
	return m


static func _glow(shape: int, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GLOW_SHADER)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("energy", energy)
	return m


## Colour over a particle's life. Values stay in 0..1; the shaders add the HDR.
static func _ramp(key: String) -> Gradient:
	var k := "ramp_" + key
	if _m.has(k):
		return _m[k]
	var stops: Array = []
	match key:
		"fire":
			stops = [[0.0, "#fff3d6"], [0.12, "#ffc35a"], [0.3, "#ff7a1c"], [0.5, "#c2340f"], [0.68, "#3a2620e8"], [0.85, "#221a16a0"], [1.0, "#1a141100"]]
		"fire_clean":    # fire that fades out hot, never going to soot
			stops = [[0.0, "#fff3d6"], [0.15, "#ffc35a"], [0.4, "#ff7a1c"], [0.7, "#c2340fa0"], [1.0, "#80200000"]]
		"smoke_dark":
			stops = [[0.0, "#2a221c00"], [0.1, "#2a221cd8"], [0.5, "#3a322ab0"], [1.0, "#5a524a00"]]
		"smoke_light":
			stops = [[0.0, "#5a524a00"], [0.15, "#5a524ab0"], [1.0, "#8a827800"]]
		"flash_hot":
			stops = [[0.0, "#fffaf0"], [0.5, "#ffd890c0"], [1.0, "#ff9a4a00"]]
		"flash_cold":
			stops = [[0.0, "#ffffff"], [0.5, "#bfe4ffc0"], [1.0, "#7fc8ff00"]]
		"ring":
			stops = [[0.0, "#fff1d8"], [1.0, "#ffb06000"]]
		"spark_hot":
			stops = [[0.0, "#fff6d8"], [0.35, "#ffb040"], [0.8, "#ff5a1ca0"], [1.0, "#c0300000"]]
		"spark_cold":
			stops = [[0.0, "#ffffff"], [0.25, "#a8dcff"], [0.6, "#ffb040c0"], [1.0, "#ff5a1c00"]]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(st): return float(st[0])))
	g.colors = PackedColorArray(stops.map(func(st): return Color(str(st[1]))))
	_m[k] = g
	return g


## Size over a particle's life (0..1).
static func _curve(key: String) -> Curve:
	var k := "curve_" + key
	if _m.has(k):
		return _m[k]
	var pts: Array = []
	match key:
		"pop":       # the flash: there at once, swells a little
			pts = [[0.0, 0.55], [0.4, 1.0], [1.0, 0.85]]
		"ring":      # the shock ring races out and slows
			pts = [[0.0, 0.1], [0.35, 0.75], [1.0, 1.0]]
		"billow":    # fire swells fast, then keeps creeping out
			pts = [[0.0, 0.3], [0.2, 0.8], [1.0, 1.0]]
		"rise":      # smoke spreads as it climbs
			pts = [[0.0, 0.45], [1.0, 1.0]]
		"shrink":    # sparks and chunks: whole most of the way, gone at the end
			pts = [[0.0, 1.0], [0.75, 0.85], [1.0, 0.0]]
	var c := Curve.new()
	for pt in pts:
		c.add_point(Vector2(float(pt[0]), float(pt[1])))
	_m[k] = c
	return c
