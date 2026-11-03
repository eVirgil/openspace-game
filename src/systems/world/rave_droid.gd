class_name RaveDroid
extends Node3D
## The moon rave's laser droid: a floating droid in rave colours that hovers over
## the stage, drifting about on a slow loop, with the club's fan of lasers hanging
## under it (ClubDressing builds the beams into `lasers`). Shoot it (or cut it) and
## it pops, the lasers go out and it drops to the floor, dark.
##
## The root never turns, so the beams keep the way ClubDressing aimed them; only
## the look banks and turns as it drifts.
##
## Issue #402: in a LAN guest's town on the host's planet it is the host's
## (net_copy): it drifts in step with the host's (NetWorld sets `t`), your hit goes
## to the host's game (net_hit) and it falls when the host's does (shoot_down).

const SCALE := 1.5
const BODY := { "body": "#141418", "trim": "#ff2bd6", "eye": "#ff2bd6" }

var home := Vector3.ZERO      ## the middle of its loop
var fwd := Vector3.FORWARD    ## toward the dance floor
var side := Vector3.RIGHT     ## across the stage
var reach := Vector2(2.2, 1.2)  ## how far it drifts across (x) and toward the floor (y)
var floor_at: Callable        ## (p: Vector3) -> the floor's height under p
var lasers: Node3D
var look: Node3D
var hull: StaticBody3D
var alive := true
var t := 0.0
var _fall := 0.0              ## speed it is falling at, once shot
var _ring: TorusMesh
var _ring_mat: StandardMaterial3D
var _lamp: OmniLight3D
var net_copy := false         ## issue #402: a LAN guest's copy of the host's
var net_hit: Callable         ## (amount, shooter) -> your hit on the copy, for the host's game

signal shot_down


func _init() -> void:
	name = "RaveDroid"
	add_to_group("rave_droids")
	lasers = Node3D.new()
	lasers.name = "Lasers"
	lasers.position = Vector3(0, -0.4 * SCALE, 0)     # the emitter hangs under its belly
	add_child(lasers)


func _ready() -> void:
	var cfg := DroidRoster.kind_cfg("floating")
	look = DroidKit.build("floating", BODY, LookMaterials.new(), cfg.get("look", {}))
	look.name = "Look"
	look.scale = Vector3.ONE * SCALE
	look.position = Vector3(0, -0.3 * SCALE, 0)
	add_child(look)
	DroidKit.set_awake(look, true)
	# A neon ring round its belly and a light under it, so it shows against the dark dome.
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.42
	_ring.outer_radius = 0.47
	_ring_mat = ClubTextures.glow(Color(BODY.trim), 6.0)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	look.add_child(ring)
	ring.position = Vector3(0, 0.22, 0)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(BODY.trim)
	_lamp.light_energy = 2.5
	_lamp.omni_range = 3.0
	_lamp.position = Vector3(0, -0.9, 0)
	add_child(_lamp)
	hull = Hull.new()
	hull.name = "Hull"
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = float(cfg.get("hit_radius", 0.55)) * SCALE
	col.shape = sh
	hull.add_child(col)
	add_child(hull)
	position = home


func _process(dt: float) -> void:
	if not alive:
		_drop(dt)
		return
	t += dt
	var was := position
	position = home + side * (sin(t * 0.23) * reach.x) + fwd * (sin(t * 0.17 + 1.3) * reach.y) \
		+ Vector3(0, sin(t * 0.9) * 0.25, 0)
	# Bank into the drift and turn slowly to look over the crowd.
	var v := (position - was) / maxf(dt, 0.0001)
	look.rotation.z = lerpf(look.rotation.z, clampf(-v.dot(side) * 0.35, -0.35, 0.35), minf(dt * 3.0, 1.0))
	look.rotation.y = atan2(-fwd.x, -fwd.z) + sin(t * 0.31) * 0.6


func apply_damage(amount: float) -> void:
	hit(amount, null)


## A bolt or a blade from `shooter` (null: unknown).
func hit(amount: float, shooter: Node) -> void:
	if not alive:
		return
	if net_copy:
		if net_hit.is_valid():
			net_hit.call(amount, shooter)
		return
	shoot_down()


## It pops, the lasers go out, and it drops.
func shoot_down() -> void:
	if not alive:
		return
	alive = false
	lasers.visible = false     # hidden, not freed: ClubProps still holds the beams
	hull.queue_free()
	DroidKit.set_awake(look, false)
	_ring_mat.emission_energy_multiplier = 0.0
	_lamp.visible = false
	if is_inside_tree():
		ExplosionFx.small(get_parent(), global_position)
		Sound.play("droid_pop", global_position)
	WorldState.log_event("Someone shot down the laser droid over the rave stage.")
	shot_down.emit()


## Falls to the floor once shot and lies there on its side.
func _drop(dt: float) -> void:
	var ground := float(floor_at.call(position)) if floor_at.is_valid() else 0.0
	if position.y <= ground + 0.35 * SCALE:
		return
	_fall += 9.8 * dt
	position.y = maxf(ground + 0.35 * SCALE, position.y - _fall * dt)
	look.rotation.z = move_toward(look.rotation.z, PI * 0.5, dt * 4.0)


## The droid's shootable body: hits go to the droid.
class Hull extends StaticBody3D:
	func apply_damage(amount: float) -> void:
		(get_parent() as RaveDroid).hit(amount, null)

	func apply_damage_from(amount: float, shooter: Node) -> void:
		(get_parent() as RaveDroid).hit(amount, shooter)

	## Only the player's energy sword calls this.
	func apply_blade_hit(amount: float, _dir: Vector3) -> void:
		var scene := get_tree().current_scene
		(get_parent() as RaveDroid).hit(amount, scene.get("_player") if scene != null else null)
