class_name CantinaOwnerNPC
extends Node3D
## The cantina owner's body (M12): a CharacterKit character behind the counter with a
## procedural idle. She wipes a glass; while "thinking" she slows and looks up;
## while talking her free hand gestures and her head nods with the words; she
## pours when a drink is ordered; and she tracks the player with her head.
## Issue #47: a drink the player pays for, she fetches a bottle from the cabinet
## behind her and sets it on the counter, a new colour each time (serve()); order
## several and she brings them one after another.
## The words come from NpcBrain; this node only acts them out.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")

enum Act { IDLE, THINKING, TALKING, POURING }

const SERVE_TIME := 1.4              ## fetch, carry, set down
const FETCH_AT := Vector3(-0.3, 0.95, -0.35)   ## behind her right hip (her local frame)

var kit: CharacterKit
var body: Node3D
var joints: Dictionary
var anim := BodyAnimator.new()
var act := Act.IDLE
var look_at_target: Node3D
var glass: Node3D
var dressing: CantinaDressing    ## the back bar and counter (null in the greybox)
var bottles_served := 0          ## paid drinks she has set on the counter
var serve_colors: Array = []     ## the colour of each one, in order
var _serve_queue := 0            ## paid drinks still to bring
var _serve_t := -1.0             ## >= 0 while carrying one
var _bottle: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _act_left := 0.0
var _talk_energy := 0.0


func _init(materials: LookMaterials = null, archetype: String = "cantina_owner") -> void:
	name = "CantinaOwner"
	kit = CharacterKit.new(materials if materials != null else LookMaterials.new(), -1000.0)
	body = kit.build(archetype, "idle")      # issue #45: another planet's owner, another look
	add_child(body)
	joints = body.get_meta("joints")
	glass = kit.make_bar_glass()
	(joints.chest as Node3D).add_child(glass)


func set_act(a: int, seconds: float = 0.0) -> void:
	act = a
	_act_left = seconds


## TalkSpot's hook (issue #42): the same acts by name.
func act_named(n: String, seconds: float = 0.0) -> void:
	match n:
		"thinking":
			set_act(Act.THINKING, seconds)
		"talking":
			set_act(Act.TALKING, seconds)
		"pouring":
			set_act(Act.POURING, seconds)
		_:
			set_act(Act.IDLE, seconds)


## A drink was ordered (NpcBrain.drink_poured). Paid: she brings a bottle to the
## counter. On the tab: she just pours, as before.
func serve(d: Dictionary) -> void:
	if not bool(d.get("paid", false)):
		return
	_serve_queue += 1
	if _serve_t < 0.0:
		_next_bottle()


func serving() -> bool:
	return _serve_t >= 0.0 or _serve_queue > 0


func _next_bottle() -> void:
	if _serve_queue <= 0:
		return
	_serve_queue -= 1
	if dressing == null:
		# The greybox has no counter to dress: count it all the same.
		serve_colors.append(Color.WHITE)
		bottles_served += 1
		_next_bottle()
		return
	dressing.serve_at(global_position)
	var color := dressing.take_color()
	serve_colors.append(color)
	_bottle = dressing.make_bottle(color)
	dressing.add_child(_bottle)
	_from = global_transform * FETCH_AT
	_to = dressing.slot(dressing.served_count)
	_bottle.global_position = _from
	_serve_t = 0.0
	set_act(Act.POURING, SERVE_TIME)


func _tick_serve(dt: float) -> void:
	if _serve_t < 0.0:
		return
	_serve_t += dt
	var k := clampf(_serve_t / SERVE_TIME, 0.0, 1.0)
	if is_instance_valid(_bottle):
		# A beat to grab it, then up and over onto the counter.
		var u := smoothstep(0.3, 1.0, k)
		_bottle.global_position = _from.lerp(_to, u) + Vector3(0, sin(PI * u) * 0.35, 0)
	if k >= 1.0:
		_serve_t = -1.0
		if is_instance_valid(_bottle):
			dressing.set_down(_bottle)
		_bottle = null
		bottles_served += 1
		_next_bottle()


## Pulse while words stream in (drives the nods and gestures).
func speak_pulse() -> void:
	_talk_energy = 1.0
	if act != Act.POURING:
		act = Act.TALKING
		_act_left = 1.2


func _process(dt: float) -> void:
	_t += dt
	if _act_left > 0.0:
		_act_left -= dt
		if _act_left <= 0.0 and act != Act.THINKING:
			act = Act.IDLE
	_talk_energy = maxf(0.0, _talk_energy - dt * 2.5)
	_tick_serve(dt)
	var out := anim.step(dt, { "speed": 0.0, "grounded": true, "upper": BodyAnimator.UPPER_HOLSTER })
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	_upper(dt)
	# The rigged model (characters.json "model") follows the joints after the IK.
	if body.has_meta("skin"):
		(body.get_meta("skin") as SkinnedBody).sync(body)


func _upper(_dt: float) -> void:
	var chest := joints.chest as Node3D
	var head := joints.head as Node3D
	var neck := joints.neck as Node3D
	var wipe_speed := 3.2
	var glass_at := Vector3(0.06, -0.16, 0.34)
	match act:
		Act.THINKING:
			wipe_speed = 1.2
			head.rotation_degrees.x = -8.0
			head.rotation_degrees.z = 6.0 * sin(_t * 0.7)
		Act.TALKING:
			wipe_speed = 1.6
			head.rotation_degrees.x = -3.0 + 5.0 * _talk_energy * sin(_t * 9.0)
		Act.POURING:
			glass_at = Vector3(0.0, -0.3, 0.42)
	# Look at the player when they are near (neck and head share the turn).
	if look_at_target != null and is_instance_valid(look_at_target):
		var to := look_at_target.global_position + Vector3(0, 1.5, 0) - head.global_position
		var local := global_basis.inverse() * to
		var yaw := clampf(rad_to_deg(atan2(local.x, local.z)), -55.0, 55.0)
		if local.length() < 7.0:
			neck.rotation_degrees.y = yaw * 0.4
			head.rotation_degrees.y = yaw * 0.6
	# Left hand holds the glass; the right hand wipes it, or gestures while talking.
	glass.position = glass_at
	glass.rotation = Vector3.ZERO
	kit.reach(body, "l", glass_at + Vector3(0.03, 0.03, -0.01), Vector3(0.6, -0.7, -0.4))
	if _serve_t >= 0.0 and is_instance_valid(_bottle):
		# Her right hand carries the bottle (the IK reaches as far as the arm goes).
		var at := chest.global_transform.affine_inverse() * (_bottle.global_position + Vector3(0, 0.12, 0))
		kit.reach(body, "r", at, Vector3(-0.5, -0.7, -0.5))
	elif act == Act.TALKING and _talk_energy > 0.2:
		var g := Vector3(-0.28, -0.05 + 0.08 * sin(_t * 3.0), 0.32 + 0.05 * sin(_t * 2.3))
		kit.reach(body, "r", g, Vector3(-0.6, -0.5, -0.4))
	elif act == Act.POURING:
		kit.reach(body, "r", glass_at + Vector3(-0.05, 0.22, 0.0), Vector3(-0.5, -0.7, -0.5))
	else:
		var a := _t * wipe_speed
		kit.reach(body, "r", glass_at + Vector3(-0.07 + 0.03 * cos(a), 0.06 + 0.035 * sin(a), 0.0), Vector3(-0.5, -0.7, -0.5))
	chest.rotation_degrees.x += 1.2 * sin(_t * 1.5)
