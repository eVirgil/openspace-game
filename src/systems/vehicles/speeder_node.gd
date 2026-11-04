class_name SpeederNode
extends Node3D
## A speeder in the world (issue #42): the look, the hull bolts can hit, riding it,
## and its twin lasers. HoverModel decides how it moves; this node reads the keys
## (or a bot's command), draws it and drives the camera.
##
##   E beside it   -- ride (E again to get off; you step off to the left)
##   W / S         -- throttle / brake and reverse
##   A / D         -- steer
##   Shift         -- boost
##   Space or LMB  -- both lasers at once   V -- chase / close camera
##   Space         -- with a Grav Lifter fitted (issue #95): hop and hang; LMB fires
##
## `rideable = false` is the one on Skrugs's display pad: it just sits there.
## Bolts hit the hull (a StaticBody child; bolts call apply_damage on its parent):
## at 0 hull it bursts and is gone, and anyone riding is thrown clear. Nothing
## else hurts it.

const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const WeaponActor := preload("res://src/systems/combat/weapon_actor.gd")
const Weapon := preload("res://src/systems/combat/weapon.gd")

signal mounted
signal dismounted
signal destroyed(at: Vector3)

var demo                              ## town_demo.gd (player, rig, terrain)
var model: HoverModel
var cfg: Dictionary = {}
var rideable := true
var paint := ""                       ## issue #82: a look.paints name ("" = look.scene)
var riding := false
var hull: StaticBody3D
var visual: Node3D
var chase = ChaseCamera.new()
var gun: WeaponActor
var feedback: HitFeedback             ## hit markers and the thud for the lasers, as on foot
var shots := 0
var log_events: Array = []            ## every HoverModel event, for traces and tests

var _external: Dictionary = {}        ## a bot's command; empty = read the keys
var _hud: CanvasLayer
var _readout: Label
var _prompt: Label
var _fan: Node3D
var _glow_mat: StandardMaterial3D
var _t := 0.0
var jolt := BoardJolt.new()      ## issue #87: sink, lift and shudder as you climb on
var _lean := Vector2.ZERO        ## smoothed (pitch, roll) for the eye
var _jolt_xf := Transform3D.IDENTITY
static var _hulls: Dictionary = {}   ## issue #82: model -> its hull shape (see _model_hull)
var _engine: AudioStreamPlayer3D   ## issue #16: the speeder's drone while you ride
## Issue #95: the mechanic's looks parts (cfg.parts) and how big the body is.
var _size := Vector3(2.4, 1.2, 5.0)
var _flames: Array = []              ## the turbo boosters' flames (scaled by boost)
var _roof: Node3D                    ## the soft-top's hinge (folds back while you ride)
var _roof_fold := 0.0                ## 0 = up, 1 = folded
var _lift_glow := 0.0                ## the hover glow's flare while the Grav Lifter holds it up


func setup(town_demo, ground: WorldGround, config: Dictionary = {}, can_ride: bool = true, paint_job: String = "") -> void:
	demo = town_demo
	cfg = config if not config.is_empty() else HoverModel.load_config("speeder")
	rideable = can_ride
	paint = paint_job
	model = HoverModel.new(cfg, ground)
	name = "Speeder" if can_ride else "DisplaySpeeder"


func _ready() -> void:
	_build_visual()
	_build_parts()
	_build_hull()
	_engine = Sound.loop("speeder_engine", self)
	if rideable:
		gun = WeaponActor.new()
		var laser: Dictionary = cfg.get("laser", {})
		gun.set_weapon(laser)
		gun.bolt_parent = demo if demo is Node3D else get_parent()
		var color := Color(str(laser.get("color", "#7fe0d0")))
		gun.configure_bolt = func(b):
			b.shooter = hull
			b.stylize = true
			b.sweep = true
			b.color = color
			b.on_hit.connect(_on_laser_hit)
			b.on_splash.connect(_on_laser_hit)
		chase.fit_to(float(cfg.get("look", {}).get("length", 4.6)))
		chase.chase_back = 9.0
		chase.chase_up = 3.2
		chase.look_ahead = 30.0
		_build_hud()
	_sync()


## Set it down at `at` facing `yaw` (on whatever ground is there).
func place(at: Vector3, yaw: float) -> void:
	model.place(at, yaw)
	_sync()


# ------------------------------------------------------------------ riding

func player() -> CharacterBody3D:
	return demo._player if demo != null else null


func can_mount() -> bool:
	var p := player()
	if not rideable or riding or p == null or p.locked or p.piloting or not model.alive():
		return false
	# Along the ground and along up (issue #77: up leans on the ball).
	var u := model.up()
	var rel: Vector3 = p.global_position - (model.position - u)
	var along := rel.dot(u)
	return (rel - u * along).length() <= float(cfg.get("board_reach", 3.2)) and absf(along) < 2.5


func mount() -> bool:
	if not can_mount():
		return false
	var p := player()
	riding = true
	p.piloting = true
	p.vehicle = self
	p.locked = true
	p.velocity = Vector3.ZERO
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_player_collision(false)
	if demo.terrain != null:
		demo.terrain.follow(null)
	chase._primed = false
	_external = {}
	if _hud != null:
		_hud.visible = true
	jolt.start()
	_ensure_parts()             # issue #100: the looks parts are on every time you get in
	mounted.emit()
	return true


## Get off, beside it (left, then right, then behind).
func dismount() -> bool:
	if not riding:
		return false
	var p := player()
	riding = false
	model.set_command(0.0, 0.0)
	if _engine != null:
		_engine.stop()
	var spot := _exit_spot()
	p.piloting = false
	p.vehicle = null
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	_player_collision(true)
	p.global_position = spot
	var rig = demo._rig
	if rig != null:
		rig.clear_override()
		rig.rig.yaw = model.yaw
		p.rotation.y = rig.rig.yaw
		if "player_kit" in demo and demo.player_kit != null and demo.player_kit.avatar != null:
			demo.player_kit.avatar.facing_yaw = rig.rig.yaw
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
		p.controller.velocity = Vector3.ZERO
		p.controller.body_pos = spot
	if demo.terrain != null:
		demo.terrain.follow(p)
	if _hud != null:
		_hud.visible = false
	dismounted.emit()
	return true


## A bot's command for this frame and on: { throttle, steer, boost, fire }.
## Pass {} to give control back to the keys.
func set_external_command(c: Dictionary) -> void:
	_external = c


## Issue #55: ridden inside town, the garrison treats it as hostile and shoots
## the hull. Out in the desert nobody minds it.
func hostile_in_town() -> bool:
	return riding and model.alive() and demo != null and TownNav.in_town(demo.get("town"), model.position)


## Ridden and whole: an outpost's troopers fight it as they would you on foot.
func targetable() -> bool:
	return riding and model.alive()


## What the troopers' eyes and bolts hit while you ride.
func hull_body() -> CollisionObject3D:
	return hull


func threat_velocity() -> Vector3:
	return model.forward() * model.speed


## Bolts land here (the hull's parent). Riding or parked, the hull takes it.
func apply_damage(amount: float) -> void:
	var killed := model.apply_damage(amount)
	for e in model.events:
		log_events.append(e)
	if killed:
		_burst()


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if model == null or not model.alive():
		if _engine != null and _engine.playing:
			_engine.stop()
		return
	_t += dt
	_jolt_xf = jolt.step(dt)
	if riding:
		_ride(dt)
	elif rideable:
		model.set_command(0.0, 0.0)
		for e in model.step(dt):
			log_events.append(e)
		_sync()
		var free := can_mount() and not _hijack_claims()
		_show_prompt(free)
		if free and _just("interact"):
			mount()


func _ride(dt: float) -> void:
	var fire := false
	if _external.is_empty():
		if _just("interact") and not model.airborne and not _hijack_claims():
			dismount()
			return
		var throttle := _axis("move_back", "move_forward")
		var steer := _axis("move_left", "move_right")
		model.set_command(throttle, steer, _held("sprint_mod") or _held("flight_boost"))
		if model.has_lifter():
			# Issue #95: Space is the Grav Lifter now; the mouse fires.
			fire = _held("fire")
			if _just("jump"):
				model.lift()
		else:
			fire = _held("jump") or _held("fire") or _held("flight_fire")
	else:
		model.set_command(float(_external.get("throttle", 0.0)), float(_external.get("steer", 0.0)),
			bool(_external.get("boost", false)))
		fire = bool(_external.get("fire", false))
		if bool(_external.get("lift", false)):
			model.lift()
	for e in model.step(dt):
		log_events.append(e)
	_fire(dt, fire)
	_sync()
	if _engine != null:
		if not _engine.playing:
			_engine.play()
		_engine.pitch_scale = 1.1 + clampf(absf(model.speed) / 40.0, 0.0, 1.0) * 0.6
	var p := player()
	p.global_position = model.position
	if demo.terrain != null and model.height_over_ground() < 30.0:
		demo.terrain.prefetch(model.position)      # ground to step off onto, built in the background
	if demo._rig != null:
		demo._rig.set_override(chase.update(dt, model.transform().translated_local(Vector3(0, 0.6, 0))), 75.0)
	if demo.detail != null:
		demo.detail.update_for(model.ground.altitude(model.position) if model.ground != null else model.position.y)
	_update_hud()


func _fire(dt: float, trigger: bool) -> void:
	if gun == null:
		return
	# The weapon keeps the rate and the ammo; one trigger pull fires both barrels
	# together, left and right.
	if gun.weapon.start_firing(dt, trigger) == Weapon.Result.SHOT:
		var b := model.transform().basis
		# Issue #64: the barrels sit either side of the nose, so two parallel bolts
		# straddled anyone straight ahead. Both converge on what the nose points at.
		var aim := _aim_point(b)
		var m := _muzzle()
		for side in [-1.0, 1.0]:
			var origin := model.position + b * Vector3(side * m.x, m.y, m.z)
			gun._make_bolt(aim - origin, origin, float(gun.weapon.config.get("damage", 18.0)),
				float(gun.weapon.config.get("bolt_speed", 90.0)))
			gun.shots_fired += 1
		shots += 1
		Sound.play("speeder_laser", model.position)


## A laser bolt landed on `target`: the hit marker pops if it really took damage
## (people, droids, other speeders, ships), as for the guns on foot.
func _on_laser_hit(target: Object) -> void:
	if feedback != null:
		feedback.on_hit(target)


## Where the lasers meet: the first thing straight ahead of the nose (not the
## speeder or its rider), else a point at the guns' convergence range.
func _aim_point(b: Basis) -> Vector3:
	var from := model.position + b * Vector3(0, _muzzle().y, _muzzle().z)
	var far := from + model.forward() * float(gun.weapon.config.get("range", 140.0))
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(from, far)
		var skip: Array[RID] = [hull.get_rid()]
		if player() != null:
			skip.append(player().get_rid())
		q.exclude = skip
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and from.distance_to(hit.position) > 3.0:
			return hit.position
	return from + model.forward() * float(cfg.get("laser", {}).get("converge", 30.0))


func _sync() -> void:
	global_transform = model.transform()
	if visual != null:
		# Lean into turns and pitch with the climb, for the eye only.
		var lean := clampf(model.speed / 40.0, -1.0, 1.0) * (_axis("move_left", "move_right") if riding and _external.is_empty() else float(_external.get("steer", 0.0)))
		_lean.y = lerpf(_lean.y, -lean * 0.25, 0.15)
		_lean.x = lerpf(_lean.x, clampf(model.vy / 30.0, -0.35, 0.35), 0.2)
		visual.transform = Transform3D(Basis.from_euler(Vector3(_lean.x, 0.0, _lean.y)), Vector3(0, 0.04 * sin(_t * 3.0), 0)) * _jolt_xf
	if _fan != null:
		_fan.rotation.z += 0.3 + absf(model.speed) * 0.02
	_lift_glow = move_toward(_lift_glow, 1.0 if model.float_left > 0.0 else 0.0, 0.08)
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 1.5 + absf(model.speed) / 10.0 + 6.0 * _lift_glow
	_sync_parts()


# ------------------------------------------------------------------ hijacking (Hijack)

## E is the town's Hijack's this frame (a vehicle someone else rides is in reach).
func _hijack_claims() -> bool:
	var h = demo.get("hijack") if demo != null else null
	return h != null and is_instance_valid(h) and h.claims_e()


## Someone may take it from you now: you ride it, it is whole, on the ground.
func can_be_hijacked() -> bool:
	return riding and model.alive() and not model.airborne


## Player `by` threw you off (Hijack.on_take): you are beside it, and it is not
## here for you while they ride it (hidden, still, nothing to hit). Returns what
## their game needs to build it ({} when it can not be taken now).
func thrown_out(by: int) -> Dictionary:
	if not can_be_hijacked():
		return {}
	var st := { "cfg": cfg, "paint": paint, "xf": model.transform(), "yaw": model.yaw, "speed": model.speed }
	dismount()
	set_meta("hijacked_by", by)
	visible = false
	set_physics_process(false)
	if hull != null:
		set_meta("hull_layer", hull.collision_layer)
		hull.collision_layer = 0
	return st


## They let it go at `xf` (Hijack.on_back): it stands there again, yours; or,
## `wrecked`, it burst under them.
func hijack_returned(xf: Transform3D, wrecked: bool) -> void:
	if not has_meta("hijacked_by"):
		return
	remove_meta("hijacked_by")
	place(xf.origin, _yaw_from(xf))
	visible = true
	set_physics_process(true)
	if hull != null:
		hull.collision_layer = int(get_meta("hull_layer", 1))
	if wrecked:
		model.apply_damage(1.0e6)
		_burst()


func _yaw_from(xf: Transform3D) -> float:
	var f := -xf.basis.z
	var u := model.up()
	f -= u * f.dot(u)
	var local := PlanetSphere.tilt_to(u).inverse() * f
	return atan2(-local.x, -local.z) if Vector2(local.x, local.z).length() > 0.01 else model.yaw


# ------------------------------------------------------------------ helpers

func _exit_spot() -> Vector3:
	var b := model.transform().basis
	var g := model.ground
	var u := model.up()
	for off in [-b.x * 2.6, b.x * 2.6, b.z * 4.0]:
		var q: Vector3 = model.position + off
		var at: Vector3 = g.surface_below(q) + u * 0.05 if g != null else Vector3(q.x, 0.05, q.z)
		if g == null or g.hit(at + u, 0.6) == "":
			return at
	return model.position + u * 0.5


func _player_collision(on: bool) -> void:
	for ch in player().get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


func _burst() -> void:
	var at := model.position
	if riding:
		dismount()
	ExplosionFx.big(get_parent(), at + Vector3(0, 0.6, 0), 0.6)
	Sound.play("vehicle_boom", at)
	destroyed.emit(at)
	queue_free()


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _axis(neg: String, pos: String) -> float:
	if not InputMap.has_action(neg) or not InputMap.has_action(pos):
		return 0.0
	return Input.get_axis(neg, pos)


# ------------------------------------------------------------------ look

## An original hover sled (docs/ART_DIRECTION.md: big readable shapes, sand and
## madder red, no franchise silhouettes): a low open tub on two long outrigger
## skids, a ducted fan at the back, a teal glow under the skids.
func _build_visual() -> void:
	var look: Dictionary = cfg.get("look", {})
	# The town's materials: a new LookMaterials builds its own textures, a 60 ms
	# hitch at the moment you buy one.
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var hullm := mats.flat(Color(str(look.get("hull", "#c9a46a"))), 0.6)
	var trim := mats.flat(Color(str(look.get("trim", "#8e3a26"))), 0.7)
	var metal := mats.flat(Color(str(look.get("metal", "#4a4c52"))), 0.4, 0.6)
	var seat := mats.flat(Color(str(look.get("seat", "#3a2a20"))), 0.9)
	_glow_mat = StandardMaterial3D.new()
	var gc := Color(str(look.get("glow", "#7fe0d0")))
	_glow_mat.albedo_color = gc
	_glow_mat.emission_enabled = true
	_glow_mat.emission = gc
	_glow_mat.emission_energy_multiplier = 2.0
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual = Node3D.new()
	visual.name = "Look"
	add_child(visual)
	var scene := str(look.get("paints", {}).get(paint, look.get("scene", "")))
	if _build_model(scene, float(look.get("base_y", -0.65))):
		return
	# The tub: a low wedge-ended body, the rider sits in it.
	_part(_box(Vector3(1.5, 0.5, 3.0)), hullm, Vector3(0, -0.15, 0.1))
	_part(_box(Vector3(1.2, 0.35, 1.0)), hullm, Vector3(0, -0.05, -1.75), Vector3(-18, 0, 0))
	_part(_box(Vector3(1.56, 0.1, 3.06)), trim, Vector3(0, 0.12, 0.1))
	_part(_box(Vector3(0.7, 0.3, 0.8)), seat, Vector3(0, 0.15, 0.6))
	_part(_box(Vector3(0.9, 0.5, 0.12)), metal, Vector3(0, 0.3, -0.55), Vector3(-25, 0, 0))
	# Two outrigger skids on struts, with the hover glow under them.
	for side in [-1.0, 1.0]:
		_part(_cyl(0.16, 0.16, 4.4), trim, Vector3(side * 1.25, -0.45, -0.1), Vector3(90, 0, 0))
		_part(_cyl(0.05, 0.05, 0.6), metal, Vector3(side * 1.0, -0.3, -1.0), Vector3(0, 0, side * 50))
		_part(_cyl(0.05, 0.05, 0.6), metal, Vector3(side * 1.0, -0.3, 0.9), Vector3(0, 0, side * 50))
		_part(_box(Vector3(0.24, 0.04, 3.8)), _glow_mat, Vector3(side * 1.25, -0.63, -0.1))
		# Twin lasers along the skids' noses.
		_part(_cyl(0.05, 0.05, 0.9), metal, Vector3(side * 0.55, 0.15, -2.15), Vector3(90, 0, 0))
	# The rear ducted fan.
	var duct := _part(_cyl(0.6, 0.6, 0.35), metal, Vector3(0, 0.15, 1.85), Vector3(90, 0, 0))
	duct.name = "Duct"
	_fan = Node3D.new()
	_fan.position = Vector3(0, 0.15, 1.85)
	visual.add_child(_fan)
	for k in 3:
		var blade := MeshInstance3D.new()
		blade.mesh = _box(Vector3(0.12, 1.0, 0.04))
		blade.material_override = trim
		blade.rotation.z = k * PI / 3.0
		_fan.add_child(blade)


## Issue #43: the Hyper3D speeder (the look's "scene", prepped by
## tools/look/prep_vehicle.gd: facing -Z, metres, centred). Its underside sits at
## `base_y` (where the stand-in's skids are), with the hover glow under it. False
## when there is no model, so the stand-in is built instead.
func _build_model(path: String, base_y: float) -> bool:
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
	visual.add_child(m)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _local_xf(mi, m) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	m.position = Vector3(-box.get_center().x, base_y - box.position.y, -box.get_center().z)
	_size = box.size
	for side in [-1.0, 1.0]:
		_part(_box(Vector3(0.24, 0.04, box.size.z * 0.75)), _glow_mat, Vector3(side * box.size.x * 0.32, base_y - 0.02, 0))
	_build_blasters()
	return true


## Issue #82: the twin blasters under the nose, where the bolts come from
## (laser.muzzle). Bolted on here so every paint job has them.
func _build_blasters() -> void:
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var gunmetal := mats.flat(Color(str(cfg.get("look", {}).get("metal", "#4a4c52"))), 0.4, 0.6)
	var m := _muzzle()
	for side in [-1.0, 1.0]:
		var at := Vector3(side * m.x, m.y, m.z)
		_part(_box(Vector3(0.24, 0.2, 0.7)), gunmetal, at + Vector3(0, 0, 1.0)).name = "BlasterHousing"
		_part(_cyl(0.07, 0.07, 1.0), gunmetal, at + Vector3(0, 0, 0.5), Vector3(90, 0, 0)).name = "Blaster"
		_part(_cyl(0.09, 0.09, 0.06), _glow_mat, at + Vector3(0, 0, 0.03), Vector3(90, 0, 0))


## Where each laser's bolt starts (the right barrel's tip; the left is mirrored).
func _muzzle() -> Vector3:
	var v: Array = cfg.get("laser", {}).get("muzzle", [0.55, 0.25, -2.4])
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func _local_xf(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return top.transform * xf


# ------------------------------------------------------------------ parts (issue #95)

func has_part(id: String) -> bool:
	return (cfg.get("parts", []) as Array).has(id)


## Issue #100: the boosters and the soft-top went missing when you got back in.
## Rebuild the looks parts if any of them is gone (freed, or never built because the
## body was not ready), so whatever the mechanic fitted is always on.
func _ensure_parts() -> void:
	if visual == null:
		return
	var want_boosters := has_part("turbo_boosters")
	var want_roof := has_part("soft_top")
	var have_boosters := not _flames.is_empty() and _flames.all(func(f): return is_instance_valid(f) and (f as Node).is_inside_tree())
	var have_roof := _roof != null and is_instance_valid(_roof) and _roof.is_inside_tree()
	if (want_boosters and not have_boosters) or (want_roof and not have_roof):
		for n in visual.get_children():
			if str(n.name).begins_with("Booster") or n.name == "SoftTop":
				n.queue_free()
		_flames = []
		_roof = null
		_build_parts()


## The mechanic's looks parts, on whatever body this is (sized from _size).
func _build_parts() -> void:
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var metal := mats.flat(Color(str(cfg.get("look", {}).get("metal", "#4a4c52"))), 0.35, 0.7)
	var hx := _size.x * 0.5
	var back := _size.z * 0.5
	var base_y := float(cfg.get("look", {}).get("base_y", -0.65))
	if has_part("turbo_boosters"):
		var flame_mat := StandardMaterial3D.new()
		flame_mat.albedo_color = Color("#ffb060")
		flame_mat.emission_enabled = true
		flame_mat.emission = Color("#ff8a30")
		flame_mat.emission_energy_multiplier = 4.0
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.albedo_color.a = 0.85
		for side in [-1.0, 1.0]:
			# Issue #100: out past the tail, so the body never swallows them.
			var at := Vector3(side * (hx * 0.62), base_y + 0.55, back + 0.1)
			_part(_cyl(0.2, 0.24, 1.3), metal, at, Vector3(90, 0, 0)).name = "Booster"
			_part(_cyl(0.26, 0.26, 0.12), metal, at + Vector3(0, 0, 0.66), Vector3(90, 0, 0)).name = "BoosterRing"
			_part(_cyl(0.15, 0.15, 0.04), _glow_mat, at + Vector3(0, 0, 0.7), Vector3(90, 0, 0)).name = "BoosterGlow"
			var flame := _part(_cyl(0.16, 0.0, 1.0), flame_mat, at + Vector3(0, 0, 1.2), Vector3(-90, 0, 0))
			flame.name = "BoosterFlame"
			flame.visible = false
			_flames.append(flame)
	if has_part("soft_top"):
		var cloth := mats.flat(Color(str(cfg.get("look", {}).get("roof", "#8a7456"))), 0.95)
		_roof = Node3D.new()
		_roof.name = "SoftTop"
		_roof.position = Vector3(0, base_y + _size.y * 0.78, 0.9)   # the hinge, behind the seat
		visual.add_child(_roof)
		var w := minf(_size.x * 0.7, 1.6)
		for k in [[0.0, 0.0], [-0.55, 0.0], [-1.1, 0.0]]:
			var bar := MeshInstance3D.new()
			bar.mesh = _box(Vector3(w, 0.05, 0.05))
			bar.material_override = metal
			bar.position = Vector3(0, 0.55, float(k[0]))
			_roof.add_child(bar)
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = _box(Vector3(0.05, 0.6, 0.05))
			post.material_override = metal
			post.position = Vector3(side * w * 0.5, 0.27, 0.0)
			_roof.add_child(post)
		var top := MeshInstance3D.new()
		top.mesh = _box(Vector3(w + 0.06, 0.06, 1.25))
		top.material_override = cloth
		top.position = Vector3(0, 0.6, -0.58)
		_roof.add_child(top)


## Boost lights the flames; the roof folds back while someone rides.
func _sync_parts() -> void:
	var lit := model.boosting() and riding
	for f in _flames:
		(f as Node3D).visible = lit
		if lit:
			(f as Node3D).scale = Vector3(1, 0.8 + 0.4 * absf(sin(_t * 41.0)), 1)
	if _roof != null:
		_roof_fold = move_toward(_roof_fold, 1.0 if riding else 0.0, 0.03)
		var e := _roof_fold * _roof_fold * (3.0 - 2.0 * _roof_fold)
		# Issue #100: folded back behind the seat, still in sight (it used to fold
		# down into the body and vanish while you rode).
		_roof.rotation.x = deg_to_rad(-95.0 * e)
		_roof.scale = Vector3(1, 1, lerpf(1.0, 0.55, e))


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	visual.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	return c


## The hull: what bolts hit (and what you bump into on foot). Its parent (this
## node) takes the damage.
func _build_hull() -> void:
	hull = StaticBody3D.new()
	hull.name = "Hull"
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = _model_hull()
	if cs.shape == null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(3.0, 1.0, 4.6)
		cs.shape = shape
		cs.position = Vector3(0, -0.2, 0)
	hull.add_child(cs)
	add_child(hull)


## Issue #82: the hull is the model's own shape (its convex hull, blasters and
## all), not a box: bolts that miss the body miss the speeder. One shape per
## model, shared by every speeder that uses it. Null with no model.
func _model_hull() -> ConvexPolygonShape3D:
	var m := visual.get_node_or_null("Model") as Node3D if visual != null else null
	if m == null:
		return null
	var key := str(m.scene_file_path) + str(m.position)
	if _hulls.has(key):
		return _hulls[key]
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override == _glow_mat:
			continue                       # the hover glow is light, not metal
		var xf := _local_xf(mi, visual)
		for sf in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(sf)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 4000)
			for i in range(0, verts.size(), step):
				pts.append(xf * verts[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var cloud := ArrayMesh.new()
	cloud.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var shape := cloud.create_convex_shape(true, false)     # just the hull's corners
	_hulls[key] = shape
	return shape


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	_readout = Label.new()
	_readout.position = Vector2(18, 54)
	_readout.add_theme_font_size_override("font_size", RetroUI.size("speeder_readout", 24))   # issue #71
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_readout.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_readout)
	var help := Label.new()
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-420, -100)
	help.size = Vector2(840, 28)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.text = "[W/S] Throttle   [A/D] Steer   [Shift] Boost   [LMB] Lasers   [Space] Grav Lifter   [E] Get off" \
		if model.has_lifter() else "[W/S] Throttle   [A/D] Steer   [Shift] Boost   [Space / LMB] Lasers   [E] Get off"
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	help.add_theme_constant_override("outline_size", 4)
	_hud.add_child(help)
	feedback = HitFeedback.new()
	add_child(feedback)
	feedback.setup(_hud)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -170)
	_prompt.size = Vector2(600, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.text = "[E]  Ride speeder"
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	layer.add_child(_prompt)


func _show_prompt(on: bool) -> void:
	if _prompt != null:
		_prompt.visible = on


func _update_hud() -> void:
	if _readout == null:
		return
	_readout.text = "SPEEDER\nSPEED  %3d m/s   %3d km/h\nHULL   %3d / %d\nBOOST  %3d%%%s" % [
		int(absf(model.speed)), int(absf(model.speed) * 3.6), model.hp, model.max_hp,
		int(model.boost_left / maxf(model.p("boost_time", 3.5), 0.001) * 100.0),
		"\nAIRBORNE" if model.airborne else ""]
	if model.has_lifter():
		_readout.text += "\nLIFTER %s" % ("READY [SPACE]" if model.lift_ready() else "%.1fs" % model.lift_cooldown)
