extends CharacterBody3D
## Player character node (M1).
##
## Two ways to drive it:
##   - Human: a real key/gamepad. When no command was pushed this frame, the node
##     reads input actions and steps the controller from them.
##   - Bot / demo: call set_command(...) to push a movement command for this frame.
##     That makes the command authoritative -- the input reader is skipped so the
##     bot is never clobbered by "no input". M5's bot uses exactly this path, so
##     human and bot share one movement implementation.

const CharacterController := preload("res://src/systems/player/character_controller.gd")
const GaitInput := preload("res://src/systems/player/gait_input.gd")
const FallDamage := preload("res://src/systems/combat/fall_damage.gd")

signal pose_changed(pose: int)
signal hurt(amount: float)          ## something hit the player (bolts, blades)
signal jumped
signal landed
signal fell(speed: float, damage: int)  ## issue #274: a landing hard enough to hurt
signal jet_started              ## M13: the jetpack lit
signal jet_stopped              ## M13: the jetpack cut out (released or empty)

## M11: while true (talking at the bar, a cutscene) the player stands still and
## ignores movement input. Gravity and collision still run.
var locked := false
var move_blocked := false     ## the weapon wheel is open: WASD points at slots, nobody walks
## M14: true while the player is in a ship's seat. ShipPilot sets it (and disables
## this node); prompts on foot (the bar, gear) check it so E means "roll" up there.
var piloting := false
## Issue #55: while piloting, the SpeederNode or ShipPilot you are in (null on
## foot). The garrison asks it whether it is a threat in town and where its hull is.
var vehicle: Node = null
var hits_taken := 0

## M15: health. Regenerates after regen_delay_s without a hit; `downed` at zero.
const HealthT := preload("res://src/systems/combat/health.gd")
signal downed
@export var max_health := 100
var regen_delay_s := 4.0
var regen_per_s := 14.0
var health = HealthT.new(100)
var is_downed := false
var invulnerable_left := 0.0
## Issue #25: where the last hit came from (INF = unknown) and how hard, so a
## ragdoll falls away from it.
var last_hit_from := Vector3.INF
var last_shooter: Node                  ## who fired the last bolt that knew its shooter (the garrison reads it when you go down)
var last_hit_amount := 0.0
var _since_hit := 999.0
var _regen_carry := 0.0
var _was_on_floor := true
## Issue #274: the falls.json tuning, set on the player only (empty = no fall damage:
## guards share this body). `fall_speed` is how fast it was falling (m/s, along up)
## the frame before it last touched down, for traces and tests.
var fall_damage: Dictionary = {}:
	set(v):
		fall_damage = v
		controller.max_fall = FallDamage.terminal_speed(v)
var fall_speed := 0.0
var _falling_at := 0.0
var _launched := false               ## launch(): the next tick is in the air

## Contained render smoothing. The game renders faster than the 60 Hz physics tick
## (120 Hz displays) and engine physics interpolation is off, so characters would
## step at 60 Hz. This node keeps the last two physics origins; render_origin() is
## the point between them at this frame's physics fraction. The camera rig, the
## player's avatar and NPC visuals read it. INF = no history yet.
const TELEPORT_M := 2.0              ## one tick moving farther than this is a teleport, not motion
const EXTERNAL_MOVE_M := 0.05        ## moved this far outside our own tick: someone set global_position
var _prev_origin := Vector3.INF
var _curr_origin := Vector3.INF
var _tick_frame := -100              ## Engine physics frame of the last recorded tick

@export var move_actions := PackedStringArray(["move_forward", "move_back", "move_left", "move_right"])
@export var jump_action := "jump"
@export var sprint_action := "sprint_mod"
@export var crouch_action := "crouch_act"

var controller := CharacterController.new()
## Issue #133: tap to walk a few steps, hold to run, Shift to sprint (keyboard only).
var gait := GaitInput.new()
var use_external_command := false
## Issue #77: on the home planet "up" turns with the ground. `tilt` takes world up
## to this body's up (identity on the town's plateau and on flat worlds). The pure
## controller keeps working in that tilted frame; this node turns its velocity
## into the world and back, and stands the capsule (and the avatar) along it.
var tilt := Basis.IDENTITY

## M13: the attached jetpack (src/systems/player/jetpack.gd), or null. Gear
## (GearController) sets it; this node only feeds it jump-held + grounded and
## hands its thrust to the controller.
var jetpack = null

## Capsule dimensions. The body origin is at the feet (the camera's fpv_offset of
## 1.6 assumes that), so the capsule is lifted by half its height.
@export var capsule_radius := 0.4
@export var capsule_height := 1.8


func _ready() -> void:
	# Without a shape, move_and_slide() collides with nothing and the player walks
	# through walls. Build one unless the scene already supplies it.
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D:
			has_shape = true
			break
	if not has_shape:
		var shape := CapsuleShape3D.new()
		shape.radius = capsule_radius
		shape.height = capsule_height
		var col := CollisionShape3D.new()
		col.name = "Capsule"
		col.shape = shape
		col.position = Vector3(0.0, capsule_height * 0.5, 0.0)
		add_child(col)
	health = HealthT.new(max_health)
	# Start the pure controller where the node actually is (it used to start at the
	# origin and teleport the player there on frame 1).
	controller.body_pos = global_position
	controller.can_slide = can_slide


func set_command(dir: Vector2, sprint: bool, crouch: bool, jump: bool, jump_held: bool = false, dash: bool = false) -> void:
	controller.set_command(dir, sprint, crouch, jump, jump_held, dash)
	use_external_command = true


func clear_external_command() -> void:
	use_external_command = false


func _physics_process(delta: float) -> void:
	_tick_health(delta)
	var yaw: float = -rotation.y
	if locked or move_blocked:
		controller.set_command(Vector2.ZERO, false, false, false)
		gait.reset()
	elif not use_external_command:
		var dir_in := Vector2(
			-Input.get_axis(move_actions[2], move_actions[3]),
			-Input.get_axis(move_actions[0], move_actions[1])
		)
		var g: Dictionary = gait.update(delta, dir_in, Input.is_action_pressed(sprint_action))
		controller.set_command(
			g.dir,
			g.run,
			Input.is_action_pressed(crouch_action),  # held, not one frame
			Input.is_action_just_pressed(jump_action),
			Input.is_action_pressed(jump_action),    # M13: held, for the jetpack
			g.dash
		)

	# M15: crouching shrinks the capsule, so cover really covers you (and the
	# guards, who use this same body). You stay down while there is no room to
	# stand (under a low overhang), whatever the key says.
	# A slide keeps the short capsule too, and ends standing even with crouch held.
	if not controller.crouching() and crouched_shape and not can_stand():
		controller.force_crouch()
	_set_crouch_shape(controller.crouching())

	# Physics is the authority on position and ground contact. The pure controller
	# only decides velocity and pose. Previously the node overwrote global_position
	# with the controller's own integration every frame, which threw away whatever
	# move_and_slide() resolved, so walls and floors never actually stopped anything.
	# Last frame's velocity was made in last frame's tilt: read it there, so it turns
	# with the ground (walking round the ball keeps it level, not climbing off it).
	var made_in := tilt
	_update_tilt()
	var to_local := tilt.inverse()
	var grounded := is_on_floor() and not _launched   # the floor it stood on before a launch is stale
	_launched = false
	controller.body_pos = global_position
	controller.on_ground = grounded
	controller.velocity = made_in.inverse() * velocity
	if grounded and controller.velocity.y < 0.0:
		controller.velocity.y = 0.0
	_step_jetpack(delta, grounded)
	# A ground height far below the world disables the controller's flat-floor
	# clamp, so landing is decided by collision instead of a hardcoded y = 0.
	controller.step(delta, yaw, -INF)
	_falling_at = maxf(0.0, -controller.velocity.y)   # along up: the planet's, on the ball

	velocity = tilt * controller.velocity
	if tilt != Basis.IDENTITY and controller.on_ground and controller.velocity.y < 0.01:
		# The turn leaves a rounding sliver along up (1e-7), and move_and_slide()
		# never snaps to the floor while moving "up": strip it and lean a hair down,
		# as a flat world's exact zero does.
		velocity -= tilt.y * (velocity.dot(tilt.y) + 0.001)
	move_and_slide()

	# Feed the resolved result back so the next step starts from reality.
	controller.body_pos = global_position
	controller.velocity = to_local * velocity
	controller.on_ground = is_on_floor()
	if controller.on_ground and controller.pose == CharacterController.Pose.JUMP:
		controller.pose = CharacterController.Pose.CROUCH if controller.crouching() else CharacterController.Pose.STAND
	pose_changed.emit(controller.pose)
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		fall_speed = _falling_at
		_take_fall(fall_speed)
		landed.emit()
	elif not on_floor and _was_on_floor and controller.velocity.y > 0.5:
		jumped.emit()
	_was_on_floor = on_floor
	record_origin(global_position, Engine.get_physics_frames())


# ------------------------------------------------------------------ render smoothing

## Render smoothing only exists with a renderer. Headless (GUT, traces, bots) keeps
## every position exactly as physics left it. The one place that decides.
static func smoothing_active() -> bool:
	return DisplayServer.get_name() != "headless"


## The point `f` of the way from the previous physics origin to the current one.
static func lerp_origin(prev: Vector3, curr: Vector3, f: float) -> Vector3:
	return prev.lerp(curr, clampf(f, 0.0, 1.0))


## True when one tick moved farther than `limit`: a teleport, never to be smeared.
static func is_teleport(prev: Vector3, curr: Vector3, limit: float = TELEPORT_M) -> bool:
	return prev.distance_squared_to(curr) > limit * limit


## Where a child must sit (in the parent's local space) so its world origin lands on
## `render_pos` while the parent itself stays at `parent_pos`.
static func local_offset(parent_basis: Basis, render_pos: Vector3, parent_pos: Vector3) -> Vector3:
	return parent_basis.inverse() * (render_pos - parent_pos)


## Note this tick's resting origin (end of _physics_process). History restarts at
## `pos` on the first tick, after a gap in ticks (process-disabled, e.g. piloting a
## ship), and after a teleport.
func record_origin(pos: Vector3, frame: int) -> void:
	if _curr_origin == Vector3.INF or frame - _tick_frame > 1 or is_teleport(_curr_origin, pos):
		_prev_origin = pos
	else:
		_prev_origin = _curr_origin
	_curr_origin = pos
	_tick_frame = frame


## Forget the history: the next render_origin() is exactly where the body is now.
func reset_render_origin() -> void:
	_prev_origin = global_position
	_curr_origin = global_position
	_tick_frame = Engine.get_physics_frames()


## The interpolation fraction `f` (0 = previous tick, 1 = this tick). Pure given the
## recorded state: tests call it directly; render_origin() feeds it the live fraction.
func render_origin_at(f: float) -> Vector3:
	return lerp_origin(_prev_origin, _curr_origin, f)


## Where to draw this body this frame (world space). Equals global_position headless,
## with no history, when ticks stopped (disabled), or when something outside our tick
## moved the body.
func render_origin() -> Vector3:
	var here := global_position
	if _curr_origin == Vector3.INF or not smoothing_active():
		return here
	if Engine.get_physics_frames() - _tick_frame > 1 \
			or here.distance_squared_to(_curr_origin) > EXTERNAL_MOVE_M * EXTERNAL_MOVE_M:
		return here
	return render_origin_at(Engine.get_physics_interpolation_fraction())


## Thrown into the air (issue #275: ejecting from a ship): moving at `v` (world),
## with a shove `push` across the ground that fades by `push_fade` m/s every
## second in the air and ends on landing (CharacterController.push).
func launch(v: Vector3, push: Vector3, push_fade: float) -> void:
	var to_local := tilt.inverse()
	velocity = v
	controller.velocity = to_local * v
	var local := to_local * push
	local.y = 0.0
	controller.push = local
	controller.push_fade = push_fade
	controller.push_holds = false
	controller.on_ground = false
	_was_on_floor = false
	_launched = true


## Knocked back across the ground at `v` m/s (world), fading by `fade` m/s every
## second, on the ground as well as in the air (two blades meeting).
func knock(v: Vector3, fade: float) -> void:
	var local := tilt.inverse() * v
	local.y = 0.0
	velocity += tilt * (local - controller.push)     # the shove rides on the walk, not against it
	controller.push = local
	controller.push_fade = fade
	controller.push_holds = true


## Read "up" from the planet (if any) and stand the capsule along it.
func _update_tilt(force: bool = false) -> void:
	var t := Basis.IDENTITY
	if PlanetSphere.current != null:
		t = PlanetSphere.current.tilt_at(global_position)
	if not force and t == Basis.IDENTITY and tilt == Basis.IDENTITY:
		return                   # flat here: nothing to turn (the body's yaw spins the capsule otherwise)
	tilt = t
	up_direction = t.y
	var col := _capsule()
	if col != null:
		_place_capsule(col, (col.shape as CapsuleShape3D).height)


## Rebuild the ground frame immediately after a hard position change. Physics has
## not moved the body yet, so relying on its next tick leaves the capsule, avatar,
## and controller temporarily using the old planet's up direction.
func align_to_ground(clear_motion: bool = true) -> void:
	if clear_motion:
		velocity = Vector3.ZERO
	_update_tilt(true)
	controller.body_pos = global_position
	controller.velocity = tilt.inverse() * velocity
	controller.on_ground = false
	_was_on_floor = false
	reset_render_origin()
	var avatar := get_node_or_null("Avatar")
	if avatar != null and avatar.has_method("align_to_ground"):
		avatar.call("align_to_ground", tilt)
		if avatar.has_method("reset_render_smoothing"):
			avatar.call("reset_render_smoothing")


## The capsule's local transform: standing along `tilt`, its foot at the origin.
func _place_capsule(col: CollisionShape3D, h: float) -> void:
	var local := global_basis.orthonormalized().inverse() * tilt if is_inside_tree() else tilt
	col.basis = local
	col.position = local * Vector3(0.0, h * 0.5, 0.0)


## True while the player is mid slide (camera, animation and audio read this).
var sliding: bool:
	get: return controller.is_sliding()
var slide_progress: float:
	get: return controller.slide_progress()
## Turn the sprint slide on (the player does; guards share this body and never do).
@export var can_slide := false:
	set(v):
		can_slide = v
		controller.can_slide = v

## True while the capsule is the short crouched one.
var crouched_shape := false
var _shape_node: CollisionShape3D


func _capsule() -> CollisionShape3D:
	if _shape_node == null or not is_instance_valid(_shape_node):
		for c in get_children():
			if c is CollisionShape3D and c.shape is CapsuleShape3D:
				_shape_node = c
				break
	return _shape_node


## Crouched: a capsule as tall as the crouch pose; standing: the full one.
func _set_crouch_shape(on: bool) -> void:
	var col := _capsule()
	if col == null or on == crouched_shape:
		return
	crouched_shape = on
	var h := controller.crouch_height + 0.05 if on else capsule_height
	var cap := (col.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	cap.height = maxf(h, capsule_radius * 2.0)
	col.shape = cap
	_place_capsule(col, cap.height)


## Room to stand up here: a full-height capsule would not hit anything.
func can_stand() -> bool:
	if not is_inside_tree():
		return true
	var cap := CapsuleShape3D.new()
	cap.radius = capsule_radius * 0.95
	cap.height = capsule_height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(tilt, global_position + tilt * Vector3(0, capsule_height * 0.5 + 0.06, 0))
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Collision height right now (crouched or standing).
func current_height() -> float:
	var col := _capsule()
	return (col.shape as CapsuleShape3D).height if col != null else capsule_height


## M13: run the jetpack (if one is attached) and hand its thrust to the controller.
func _step_jetpack(delta: float, grounded: bool) -> void:
	if jetpack == null:
		controller.lift = 0.0
		controller.max_rise = 0.0
		return
	var was: bool = jetpack.thrusting
	var held: bool = bool(controller.command.jump_held) and not locked
	controller.lift = jetpack.step(delta, held, grounded)
	controller.max_rise = jetpack.max_rise()
	if jetpack.thrusting and not was:
		# The kick as it lights: a shove the way the body faces.
		var yaw := -rotation.y
		controller.push = Vector3(-sin(yaw), 0.0, cos(yaw)) * jetpack.push()
		controller.push_fade = jetpack.push_fade()
		controller.push_holds = false
		jet_started.emit()
	elif was and not jetpack.thrusting:
		jet_stopped.emit()


## Bolts and blades call this (see bolt.gd). Hits are reported so the camera and
## HUD can react, and (M15) they cost health. Health comes back on its own after
## a few seconds without being hit. At zero the body is "downed": it says so and
## does nothing else. Whoever owns the scene decides what that means (the gate
## checkpoint knocks you out and drags you to the pit); with nobody listening, a
## trace just keeps walking.
func apply_damage(amount: float) -> void:
	hits_taken += 1
	last_hit_amount = amount
	hurt.emit(amount)
	if invulnerable_left > 0.0 or amount <= 0.0 or is_downed:
		return
	_since_hit = 0.0
	health.apply_damage(amount)
	if health.hp <= 0:
		is_downed = true
		downed.emit()


## Issue #274: touching down at `speed` m/s straight down hurts like a hit (god
## mode, the hit flash and being downed all work as for bolts). The player only.
func _take_fall(speed: float) -> void:
	if fall_damage.is_empty():
		return
	var dmg := FallDamage.damage(speed, fall_damage)
	if dmg <= 0:
		return
	last_hit_from = Vector3.INF
	apply_damage(dmg)
	fell.emit(speed, dmg)


## Bolts call this when they know who fired them (issue #25: so the fall is away
## from the shooter). NpcBody overrides it to skip friendly fire.
func apply_damage_from(amount: float, shooter: Node) -> void:
	if shooter is Node3D and is_instance_valid(shooter):
		last_hit_from = (shooter as Node3D).global_position
		last_shooter = shooter
	apply_damage(amount)


## Back on your feet (after being downed): full health, a short grace period.
func revive(grace_s: float = 3.0) -> void:
	health = HealthT.new(max_health)
	is_downed = false
	invulnerable_left = grace_s
	_since_hit = 999.0


func _tick_health(dt: float) -> void:
	invulnerable_left = maxf(0.0, invulnerable_left - dt)
	if is_downed:
		return
	_since_hit += dt
	if _since_hit >= regen_delay_s and health.hp < health.max_hp:
		_regen_carry += regen_per_s * dt
		var whole := int(_regen_carry)
		if whole > 0:
			health.heal(whole)
			_regen_carry -= whole