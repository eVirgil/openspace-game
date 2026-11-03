class_name SandPig
extends CharacterBody3D
## Issue #96: a wild animal of the desert (content/core/fauna/<id>.json; the sand
## pig is the first). It roams alone round its home spot, bolts when hurt or when
## you come close at a run, and dies to bolts or a blade like anything else
## (apply_damage). Dead, it is a carcass: [E] beside it (NativesDirector asks
## butcher()) cuts food from it, once.
##
## It rides the ground (WorldGround: the ball's or the flat world's), moved here
## rather than by physics, so it never needs a collider under it far out in the
## desert. Its own box is solid to bolts and blades.

signal killed(pig: SandPig)

var cfg: Dictionary = {}
var ground: WorldGround
var home := Vector3.ZERO
var hp := 30
var dead := false
var butchered := false
var target: Node3D                ## the player (to flee from)
var _goal := Vector3.INF
var _rest := 0.0
var _flee := 0.0
var _rng := RandomNumberGenerator.new()
var _look: Node3D
var _t := 0.0
var _heading := Vector3.FORWARD
## Far from the player and calm, it moves once every `lod_stride` ticks with the
## time of the ticks in between (nobody can see it, and each step costs a ground query).
var lod_stride := 4
var _lod_dt := 0.0
var _lod_n := 0
var _lod_slot := 0
## Issue #402: a LAN guest's copy of the host's animal. It goes where the host's
## goes (net_hear), its hits go to net_hit (amount, shooter) instead of hurting it,
## and it dies when the host's does (net_die).
var net_copy := false
var net_hit: Callable
var _net_at := Vector3.INF
var _net_run := false


func setup(fauna_cfg: Dictionary, world_ground: WorldGround, at: Vector3, rng_seed: int, mats: LookMaterials = null) -> void:
	cfg = fauna_cfg
	ground = world_ground
	home = at
	hp = int(cfg.get("hp", 30))
	_rng.seed = rng_seed
	_lod_slot = absi(rng_seed) % maxi(1, lod_stride)
	name = "SandPig"
	var sz: Array = cfg.get("size", [0.9, 0.7, 1.5])
	var size := Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5 + 0.1, 0)
	add_child(cs)
	_look = _build_look(size, mats)
	add_child(_look)
	_place(at)


## The look's "scene" (a Hyper3D boar), or a blocky pig when there is none: body,
## head, snout, ears, four legs and a tail (look only).
func _build_look(size: Vector3, mats: LookMaterials) -> Node3D:
	var root := Node3D.new()
	root.name = "Look"
	var lk: Dictionary = cfg.get("look", {})
	if _build_model(root, str(lk.get("scene", "")), float(lk.get("yaw_deg", 0.0)), size):
		return root
	var hide := _mat(mats, Color(str(lk.get("hide", "#b08a62"))))
	var belly := _mat(mats, Color(str(lk.get("belly", "#d2b48c"))))
	var snout := _mat(mats, Color(str(lk.get("snout", "#7a4e3a"))))
	var dark := _mat(mats, Color(str(lk.get("dark", "#3a2a20"))))
	var leg_h := size.y * 0.35
	_box(root, Vector3(size.x, size.y * 0.65, size.z * 0.8), hide, Vector3(0, leg_h + size.y * 0.32, 0))
	_box(root, Vector3(size.x * 0.8, size.y * 0.2, size.z * 0.7), belly, Vector3(0, leg_h + size.y * 0.05, 0))
	_box(root, Vector3(size.x * 0.7, size.y * 0.55, size.z * 0.3), hide, Vector3(0, leg_h + size.y * 0.45, -size.z * 0.5))
	_box(root, Vector3(size.x * 0.4, size.y * 0.25, size.z * 0.12), snout, Vector3(0, leg_h + size.y * 0.35, -size.z * 0.68))
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.12, 0.18, 0.06), dark, Vector3(sx * size.x * 0.25, leg_h + size.y * 0.78, -size.z * 0.5))
		for sz2 in [-1.0, 1.0]:
			_box(root, Vector3(0.16, leg_h, 0.16), dark, Vector3(sx * size.x * 0.32, leg_h * 0.5, sz2 * size.z * 0.28))
	_box(root, Vector3(0.06, 0.06, 0.3), dark, Vector3(0, leg_h + size.y * 0.5, size.z * 0.45))
	return root


## The model at `path`, turned by yaw_deg so its snout faces -Z, scaled so it
## stands size.y tall, centred over the feet. False (nothing added) without one.
static func _build_model(root: Node3D, path: String, yaw_deg: float, size: Vector3) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	var res = ModelCache.scene(path)
	var inst = (res as PackedScene).instantiate() if res is PackedScene else null
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return false
	var m := inst as Node3D
	m.name = "Model"
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or box.size.y <= 0.0:
		m.free()
		return false
	var s := size.y / box.size.y
	var turn := Node3D.new()
	turn.name = "Turn"
	turn.rotation.y = deg_to_rad(yaw_deg)
	turn.scale = Vector3.ONE * s
	root.add_child(turn)
	turn.add_child(m)
	m.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	return true


static func _mat(mats: LookMaterials, c: Color) -> Material:
	if mats != null:
		return mats.flat(c, 0.95)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _box(root: Node3D, size: Vector3, mat: Material, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_t += dt
	if dead:
		return
	if net_copy:
		_net_step(dt)
		return
	var speed := float(cfg.get("walk_speed", 1.4))
	if target != null and is_instance_valid(target) and not bool(target.get("piloting")):
		var d := target.global_position.distance_to(global_position)
		var tv: Vector3 = (target as CharacterBody3D).velocity if target is CharacterBody3D else Vector3.ZERO
		if d < float(cfg.get("flee_range", 18.0)) and tv.length() > 4.0:
			_spook(target.global_position)
		if d > float(cfg.get("lod_m", 120.0)) and _flee <= 0.0 and lod_stride > 1:
			_lod_dt += dt
			_lod_n += 1
			if (_lod_n + _lod_slot) % lod_stride != 0:
				return
			dt = _lod_dt
			_lod_dt = 0.0
		else:
			_lod_dt = 0.0
	else:
		_lod_dt = 0.0
	if _flee > 0.0:
		_flee -= dt
		speed = float(cfg.get("run_speed", 6.5))
	elif _rest > 0.0:
		_rest -= dt
		return
	if _goal == Vector3.INF or global_position.distance_to(_goal) < 1.0:
		if _flee <= 0.0:
			_rest = _rng.randf_range(1.0, 5.0)
		_goal = _wander_point()
		return
	var up := ground.up_at(global_position) if ground != null else Vector3.UP
	var to := _goal - global_position
	to -= up * to.dot(up)
	if to.length() < 0.01:
		return
	_heading = _heading.lerp(to.normalized(), minf(1.0, dt * 4.0)).normalized()
	_place(global_position + _heading * speed * dt)


## Put it on the ground at (about) `at`, standing along up, facing its heading.
func _place(at: Vector3) -> void:
	var p := at
	if ground != null:
		p = ground.surface_below(at + (ground.up_at(at) * 3.0))
	var up := ground.up_at(p) if ground != null else Vector3.UP
	var fwd := _heading - up * _heading.dot(up)
	if fwd.length() < 0.01:
		fwd = up.cross(Vector3.RIGHT)
	global_transform = Transform3D(Basis.looking_at(fwd.normalized(), up), p)
	if _look != null:
		_look.position.y = 0.03 * absf(sin(_t * 9.0)) if _flee > 0.0 else 0.0


func _wander_point() -> Vector3:
	var r := float(cfg.get("wander_radius", 40.0))
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(r * 0.3, r)
	var up := ground.up_at(home) if ground != null else Vector3.UP
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	return home + (side * cos(a) + fwd * sin(a)) * d


func _spook(from: Vector3) -> void:
	var away := global_position - from
	var up := ground.up_at(global_position) if ground != null else Vector3.UP
	away -= up * away.dot(up)
	if away.length() < 0.01:
		away = up.cross(Vector3.RIGHT)
	_goal = global_position + away.normalized() * 30.0
	_flee = float(cfg.get("flee_s", 6.0))
	_rest = 0.0


## A copy: trot (or run) to where the host's one was heard; jump there when far off.
func _net_step(dt: float) -> void:
	if _net_at == Vector3.INF:
		return
	var up := ground.up_at(global_position) if ground != null else Vector3.UP
	var to := _net_at - global_position
	to -= up * to.dot(up)
	if to.length() > NetSession.n("pig_snap_m", 12.0):
		_place(_net_at)
		return
	if to.length() < 0.3:
		_flee = 0.0
		return
	_flee = 1.0 if _net_run else 0.0     # (the trot in _place)
	var speed := float(cfg.get("run_speed" if _net_run else "walk_speed", 1.4)) * NetSession.n("pig_catch_up", 1.15)
	_heading = _heading.lerp(to.normalized(), minf(1.0, dt * 4.0)).normalized()
	_place(global_position + _heading * minf(speed * dt, to.length()))


## Issue #402: where the host's one is now, and whether it is running.
func net_hear(at: Vector3, running: bool) -> void:
	net_copy = true
	_net_at = at
	_net_run = running


## Whether it is bolting now (what a LAN host sends).
func fleeing() -> bool:
	return _flee > 0.0


## Issue #402: the host's one died: so does this one, its own way (`count`: it was
## this game's player's kill, so it counts here too).
func net_die(count: bool) -> void:
	if dead:
		return
	hp = 0
	dead = true
	if _look != null:
		_look.rotation.z = PI * 0.5
		_look.position.y = 0.35
	if count:
		killed.emit(self)


# ------------------------------------------------------------------ hurt, dead, food

func apply_damage_from(amount: float, shooter: Node) -> void:
	if net_hit.is_valid():
		if not dead:
			net_hit.call(amount, shooter)
		return
	apply_damage(amount)
	if not dead and shooter is Node3D:
		_spook((shooter as Node3D).global_position)


func apply_damage(amount: float) -> void:
	if dead:
		return
	if net_hit.is_valid():
		net_hit.call(amount, null)
		return
	hp -= int(ceil(amount))
	if hp <= 0:
		dead = true
		if _look != null:
			_look.rotation.z = PI * 0.5
			_look.position.y = 0.35
		killed.emit(self)


## Cut food from the carcass: the items and how many, once. {} if alive or done.
func butcher() -> Dictionary:
	if not dead or butchered:
		return {}
	butchered = true
	var f: Dictionary = cfg.get("food", { "item": "food", "count": 2 })
	if _look != null:
		_look.scale = Vector3(1, 0.4, 1)
	return { "item": str(f.get("item", "food")), "count": int(f.get("count", 2)) }
