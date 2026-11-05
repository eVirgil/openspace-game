class_name Ragdoll
extends RefCounted
## Death and knock-out physics (issue #25): a point-mass ragdoll that drives a
## CharacterKit joint hierarchy, so guards, locals and the player fall the same way
## and a rigged skin (SkinnedBody.sync) follows for free.
##
## The design:
##   - One particle per joint, plus five tips (head top, hands, toes), placed where
##     the pose was at the moment of the hit. Verlet integration, the game's gravity.
##   - Distance constraints keep every bone its length. The shoulders and the hips
##     are two rigid blocks joined by a spine and four soft braces, so the back bends
##     a little but never folds.
##   - Joint limits: knees fold forward and elbows back (a hinge test against the
##     torso's facing), and minimum reaches stop a limb, the neck or the hips
##     folding flat (the torso never jackknifes onto the thighs).
##   - The killing blow pushes the upper body away from the shooter; the knees get a
##     small forward push so the legs buckle instead of the body falling like a plank.
##   - Every particle casts a short ray against the world (layer 1): it lands, slides
##     with friction, bounces a little, and cannot go through walls.
##   - It sleeps once everything is slow, or after max_seconds, and costs nothing.
##
## Joints are written as rotations only (except the pelvis, which also moves), so the
## primitive body and a skinned one look the same. stop() puts every joint back.
## Numbers live in content/look/ragdoll.json.

const CFG_PATH := "res://content/look/ragdoll.json"

## [name, joint or "", mass, radius]. A "" joint is a tip, placed by TIPS.
const POINTS := [
	["pelvis", "pelvis", 3.0, 0.12], ["chest", "chest", 3.0, 0.13], ["neck", "neck", 1.0, 0.08],
	["head", "head", 1.2, 0.11], ["head_top", "", 0.5, 0.1],
	["l_shoulder", "l_shoulder", 1.5, 0.08], ["r_shoulder", "r_shoulder", 1.5, 0.08],
	["l_elbow", "l_elbow", 0.8, 0.06], ["r_elbow", "r_elbow", 0.8, 0.06],
	["l_wrist", "l_wrist", 0.5, 0.05], ["r_wrist", "r_wrist", 0.5, 0.05],
	["l_hand", "", 0.3, 0.05], ["r_hand", "", 0.3, 0.05],
	["l_hip", "l_hip", 1.5, 0.1], ["r_hip", "r_hip", 1.5, 0.1],
	["l_knee", "l_knee", 1.0, 0.07], ["r_knee", "r_knee", 1.0, 0.07],
	["l_ankle", "l_ankle", 0.7, 0.06], ["r_ankle", "r_ankle", 0.7, 0.06],
	["l_toe", "", 0.3, 0.04], ["r_toe", "", 0.3, 0.04],
]
## Tip -> [joint it hangs off, offset in that joint's space].
const TIPS := {
	"head_top": ["head", Vector3(0, 0.22, 0)],
	"l_hand": ["l_wrist", Vector3(0, -0.12, 0)], "r_hand": ["r_wrist", Vector3(0, -0.12, 0)],
	"l_toe": ["l_ankle", Vector3(0, -0.02, 0.2)], "r_toe": ["r_ankle", Vector3(0, -0.02, 0.2)],
}
## Bones and braces: [a, b, stiffness]. Stiffness 1 is rigid.
const LINKS := [
	# Upper block: shoulders, chest and neck.
	["chest", "l_shoulder", 1.0], ["chest", "r_shoulder", 1.0], ["l_shoulder", "r_shoulder", 1.0],
	["neck", "chest", 1.0], ["neck", "l_shoulder", 1.0], ["neck", "r_shoulder", 1.0],
	# Lower block: pelvis and hips.
	["pelvis", "l_hip", 1.0], ["pelvis", "r_hip", 1.0], ["l_hip", "r_hip", 1.0],
	# Spine and its braces.
	["pelvis", "chest", 1.0],
	["l_hip", "l_shoulder", 0.25], ["r_hip", "r_shoulder", 0.25],
	["l_hip", "r_shoulder", 0.15], ["r_hip", "l_shoulder", 0.15],
	# Head.
	["neck", "head", 1.0], ["head", "head_top", 1.0], ["neck", "head_top", 1.0],
	# Arms.
	["l_shoulder", "l_elbow", 1.0], ["l_elbow", "l_wrist", 1.0], ["l_wrist", "l_hand", 1.0],
	["r_shoulder", "r_elbow", 1.0], ["r_elbow", "r_wrist", 1.0], ["r_wrist", "r_hand", 1.0],
	["l_elbow", "l_hand", 0.6], ["r_elbow", "r_hand", 0.6],
	# Legs. Toe to knee holds the ankle near square.
	["l_hip", "l_knee", 1.0], ["l_knee", "l_ankle", 1.0], ["l_ankle", "l_toe", 1.0],
	["r_hip", "r_knee", 1.0], ["r_knee", "r_ankle", 1.0], ["r_ankle", "r_toe", 1.0],
	["l_knee", "l_toe", 0.8], ["r_knee", "r_toe", 0.8],
]
## [a, b, fraction of the rest distance they may not get closer than].
const MIN_REACH := [
	["l_shoulder", "l_wrist", 0.45], ["r_shoulder", "r_wrist", 0.45],
	["l_hip", "l_ankle", 0.5], ["r_hip", "r_ankle", 0.5],
	["head_top", "chest", 0.8], ["head", "pelvis", 0.85],
	# Hips: the torso may fold over the thighs about as far as sitting, no further.
	["l_knee", "chest", 0.6], ["r_knee", "chest", 0.6], ["l_knee", "neck", 0.6], ["r_knee", "neck", 0.6],
]
## Joint -> [particle it sits on, particle its bone points at]. Order is parent first.
const SEGMENTS := [
	["pelvis", "pelvis", "chest"], ["chest", "chest", "neck"], ["neck", "neck", "head"],
	["head", "head", "head_top"],
	["l_shoulder", "l_shoulder", "l_elbow"], ["l_elbow", "l_elbow", "l_wrist"], ["l_wrist", "l_wrist", "l_hand"],
	["r_shoulder", "r_shoulder", "r_elbow"], ["r_elbow", "r_elbow", "r_wrist"], ["r_wrist", "r_wrist", "r_hand"],
	["l_hip", "l_hip", "l_knee"], ["l_knee", "l_knee", "l_ankle"], ["l_ankle", "l_ankle", "l_toe"],
	["r_hip", "r_hip", "r_knee"], ["r_knee", "r_knee", "r_ankle"], ["r_ankle", "r_ankle", "r_toe"],
]
## How much of the kick each particle takes (the rest take `kick_rest`).
const KICK_SHARE := {
	"head": 1.0, "head_top": 1.0, "neck": 1.0, "chest": 1.0, "l_shoulder": 0.85, "r_shoulder": 0.85,
	"l_elbow": 0.6, "r_elbow": 0.6, "l_wrist": 0.5, "r_wrist": 0.5, "l_hand": 0.5, "r_hand": 0.5,
	"pelvis": 0.35, "l_hip": 0.3, "r_hip": 0.3,
}

var cfg: Dictionary = {}
var joints: Dictionary = {}
var asleep := true
var running := false
var elapsed := 0.0
var rays_cast := 0

var _idx := {}                 ## name -> index
var _pos: PackedVector3Array
var _prev: PackedVector3Array
var _inv_mass: PackedFloat32Array
var _radius: PackedFloat32Array
var _links: Array = []         ## [ia, ib, rest, stiffness]
var _mins: Array = []          ## [ia, ib, min]
var _rest_local: Dictionary = {}    ## joint -> Transform3D to restore
var _start_basis: Dictionary = {}   ## joint -> global Basis at the start
var _start_dir: Dictionary = {}     ## joint -> bone direction at the start
var _torso0: Basis
var _hips0: Basis
var _still := 0.0
var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []


func _init(body_joints: Dictionary, config: Dictionary = {}) -> void:
	joints = body_joints
	cfg = config if not config.is_empty() else load_config()


static func load_config() -> Dictionary:
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## The killing blow's push: away from `from` (flat), lifted by kick_up, harder for
## bigger hits. `from` INF = no push.
static func kick_for(at: Vector3, from: Vector3, damage: float, config: Dictionary) -> Vector3:
	if from == Vector3.INF:
		return Vector3.ZERO
	var away := Vector3(at.x - from.x, 0.0, at.z - from.z)
	if away.length() < 0.01:
		return Vector3.ZERO
	var speed := clampf(damage * float(config.get("kick_per_damage", 0.12)),
		float(config.get("kick_min", 1.5)), float(config.get("kick_max", 4.5)))
	return (away.normalized() + Vector3(0, float(config.get("kick_up", 0.35)), 0)).normalized() * speed


## Issue #372: a blast's kill throws the whole body away from where it burst
## (along the ground, lifted along `up`), blast_fling m/s at the edge of `reach`
## up to blast_fling_close m/s right on top of it.
static func blast_fling(at: Vector3, from: Vector3, reach: float, up: Vector3, config: Dictionary) -> Vector3:
	if from == Vector3.INF:
		return Vector3.ZERO
	var u := up.normalized() if up.length() > 0.01 else Vector3.UP
	var off := at - from
	var away := off - u * off.dot(u)
	away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
	var close := 1.0 - clampf(off.length() / maxf(0.1, reach), 0.0, 1.0)
	var speed := lerpf(float(config.get("blast_fling", 7.0)), float(config.get("blast_fling_close", 13.0)), close)
	return away * speed + u * speed * float(config.get("blast_fling_up", 0.7))


func _num(key: String, def: float) -> float:
	return float(cfg.get(key, def))


## Let go. `velocity` is how the body was moving (m/s); `kick` is the push of the
## killing blow (m/s, world space; zero for none). `space` is the world to land in
## (null = fall forever, for tests without a world); `exclude` is the body's own
## collision, so it does not land on itself.
func start(velocity: Vector3, kick: Vector3, space: PhysicsDirectSpaceState3D = null, exclude: Array[RID] = []) -> void:
	_space = space
	_exclude = exclude
	var n := POINTS.size()
	_pos.resize(n)
	_prev.resize(n)
	_inv_mass.resize(n)
	_radius.resize(n)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var fwd := _forward()
	for i in n:
		var p: Array = POINTS[i]
		_idx[p[0]] = i
		var at: Vector3
		if p[1] != "":
			at = (joints[p[1]] as Node3D).global_position
		else:
			var tip: Array = TIPS[p[0]]
			at = (joints[tip[0]] as Node3D).global_transform * (tip[1] as Vector3)
		_pos[i] = at
		_inv_mass[i] = 1.0 / float(p[2])
		_radius[i] = float(p[3])
		var v := velocity + kick * float(KICK_SHARE.get(p[0], _num("kick_rest", 0.15)))
		if p[0] == "l_knee" or p[0] == "r_knee":
			v += fwd * _num("knee_buckle", 1.4)
		_prev[i] = at - v * dt
	_links.clear()
	for l in LINKS:
		_links.append([_idx[l[0]], _idx[l[1]], _pos[_idx[l[0]]].distance_to(_pos[_idx[l[1]]]), float(l[2])])
	_mins.clear()
	for m in MIN_REACH:
		_mins.append([_idx[m[0]], _idx[m[1]], _pos[_idx[m[0]]].distance_to(_pos[_idx[m[1]]]) * float(m[2])])
	_rest_local.clear()
	_start_basis.clear()
	_start_dir.clear()
	for jn in joints:
		_rest_local[jn] = (joints[jn] as Node3D).transform
	for s in SEGMENTS:
		_start_basis[s[0]] = (joints[s[0]] as Node3D).global_basis.orthonormalized()
		_start_dir[s[0]] = _dir(s[1], s[2])
	_torso0 = _frame("chest", "neck", "l_shoulder", "r_shoulder")
	_hips0 = _frame("pelvis", "chest", "l_hip", "r_hip")
	elapsed = 0.0
	_still = 0.0
	asleep = false
	running = true


## Put every joint back where the animator left it (getting up).
func stop() -> void:
	if not running:
		return
	for jn in _rest_local:
		if is_instance_valid(joints[jn]):
			(joints[jn] as Node3D).transform = _rest_local[jn]
	running = false
	asleep = true


## One physics step. Returns true while it is still moving.
func step(dt: float) -> bool:
	if asleep or not running:
		return false
	elapsed += dt
	var g := Vector3(0, -_num("gravity", 20.0), 0)
	var damp := 1.0 - _num("air_drag", 0.02)
	var fastest := 0.0
	for i in _pos.size():
		var v := (_pos[i] - _prev[i]) * damp
		_prev[i] = _pos[i]
		_pos[i] += v + g * dt * dt
		fastest = maxf(fastest, v.length() / dt)
	var iters := int(_num("iterations", 8))
	for k in iters:
		_solve_links()
		_solve_limits()
	_collide()
	_write()
	if fastest < _num("sleep_speed", 0.15):
		_still += dt
	else:
		_still = 0.0
	if _still >= _num("sleep_after", 0.5) or elapsed >= _num("max_seconds", 6.0):
		asleep = true
	return not asleep


## The floor it lies on moved by `by` this tick (a body on the party barge's
## deck): every particle goes with it, so it falls and settles on the deck, not
## in the air the deck has left. A no-op once asleep (the joints then ride along
## in their parent's frame).
func carry(by: Transform3D) -> void:
	if asleep or not running or by.is_equal_approx(Transform3D.IDENTITY):
		return
	for i in _pos.size():
		_pos[i] = by * _pos[i]
		_prev[i] = by * _prev[i]


func point(pname: String) -> Vector3:
	return _pos[_idx[pname]]


## Let go of a held thing: it becomes a rigid body in `world` with a box hull from
## its meshes, thrown with `velocity` and a little spin, and frozen once it rests
## (or after weapon_rest_seconds). Returns the body (null if there is nothing to drop).
static func drop(item: Node3D, world: Node3D, velocity: Vector3, config: Dictionary) -> RigidBody3D:
	if item == null or world == null or not is_instance_valid(item):
		return null
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null:
			continue
		var b: AABB = (item.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return null
	var at := item.global_transform
	var rb := RigidBody3D.new()
	rb.name = "Dropped_" + item.name
	rb.mass = 3.0
	rb.collision_layer = 0
	rb.collision_mask = int(config.get("collision_mask", 1))
	rb.continuous_cd = true
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (box.size * at.basis.get_scale()).max(Vector3.ONE * 0.04)
	shape.shape = bs
	shape.position = box.get_center() * at.basis.get_scale()
	rb.add_child(shape)
	world.add_child(rb)
	rb.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	item.get_parent().remove_child(item)
	rb.add_child(item)
	item.transform = Transform3D(Basis.from_scale(at.basis.get_scale()), Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spin := float(config.get("weapon_spin", 6.0))
	rb.linear_velocity = velocity + Vector3(0, float(config.get("weapon_toss", 1.5)), 0)
	rb.angular_velocity = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spin
	rb.can_sleep = true
	var t := world.get_tree().create_timer(float(config.get("weapon_rest_seconds", 20.0)), false, true)
	t.timeout.connect(func():
		if is_instance_valid(rb):
			rb.freeze = true)
	return rb


# ------------------------------------------------------------------ solver

func _solve_links() -> void:
	for l in _links:
		var a: int = l[0]
		var b: int = l[1]
		var d := _pos[b] - _pos[a]
		var dist := d.length()
		if dist < 0.0001:
			continue
		var wsum := _inv_mass[a] + _inv_mass[b]
		var corr := d * ((dist - float(l[2])) / dist) * float(l[3]) / wsum
		_pos[a] += corr * _inv_mass[a]
		_pos[b] -= corr * _inv_mass[b]
	for m in _mins:
		var a: int = m[0]
		var b: int = m[1]
		var d := _pos[b] - _pos[a]
		var dist := d.length()
		if dist >= float(m[2]) or dist < 0.0001:
			continue
		var wsum := _inv_mass[a] + _inv_mass[b]
		var corr := d * ((dist - float(m[2])) / dist) / wsum
		_pos[a] += corr * _inv_mass[a]
		_pos[b] -= corr * _inv_mass[b]


## Hinges: a knee stays in front of the hip-ankle line and an elbow behind the
## shoulder-wrist line, so legs and arms only fold the way they really do.
func _solve_limits() -> void:
	var hips := _frame("pelvis", "chest", "l_hip", "r_hip")
	var torso := _frame("chest", "neck", "l_shoulder", "r_shoulder")
	for s in ["l", "r"]:
		_hinge(s + "_hip", s + "_knee", s + "_ankle", hips.z, 1.0)
		_hinge(s + "_shoulder", s + "_elbow", s + "_wrist", torso.z, -1.0)


## Keep `mid` on the `sign` side of the a-c line along `fwd`.
func _hinge(a: String, mid: String, c: String, fwd: Vector3, sign: float) -> void:
	var ia: int = _idx[a]
	var im: int = _idx[mid]
	var ic: int = _idx[c]
	var line := (_pos[ia] + _pos[ic]) * 0.5
	var off := (_pos[im] - line).dot(fwd) * sign
	if off < 0.0:
		_pos[im] -= fwd * off * sign


func _collide() -> void:
	if _space == null:
		return
	var friction := _num("friction", 0.6)
	var bounce := _num("bounce", 0.15)
	var mask := int(_num("collision_mask", 1))
	for i in _pos.size():
		var r := _radius[i]
		var from := _prev[i] + Vector3(0, r, 0)
		var to := _pos[i] - Vector3(0, r, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to, mask, _exclude)
		var hit := _space.intersect_ray(q)
		rays_cast += 1
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		var v := _pos[i] - _prev[i]
		_pos[i] = (hit.position as Vector3) + n * r
		var vn := n * v.dot(n)
		var vt := v - vn
		var out := vt * (1.0 - friction) - vn * bounce
		_prev[i] = _pos[i] - out


# ------------------------------------------------------------------ joints

func _dir(a: String, b: String) -> Vector3:
	return (_pos[_idx[b]] - _pos[_idx[a]]).normalized()


## An orthonormal frame: y along base->top, x toward the left point.
func _frame(base: String, top: String, left: String, right: String) -> Basis:
	var y := _dir(base, top)
	var side := _pos[_idx[left]] - _pos[_idx[right]]
	var x := (side - y * side.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


## Pelvis and chest turn with their blocks; every other joint turns by the shortest
## arc from its bone's starting direction, on top of its parent block's turn.
func _write() -> void:
	var hips_turn := _frame("pelvis", "chest", "l_hip", "r_hip") * _hips0.inverse()
	var torso_turn := _frame("chest", "neck", "l_shoulder", "r_shoulder") * _torso0.inverse()
	for s in SEGMENTS:
		var jn: String = s[0]
		var j := joints[jn] as Node3D
		var block := hips_turn if (jn == "pelvis" or jn.ends_with("hip") or jn.ends_with("knee") or jn.ends_with("ankle")) else torso_turn
		var b: Basis
		if jn == "pelvis" or jn == "chest":
			b = block * _start_basis[jn]
		else:
			var was: Vector3 = block * (_start_dir[jn] as Vector3)
			b = _arc(was, _dir(s[1], s[2])) * block * _start_basis[jn]
		b = b.scaled(j.global_basis.get_scale())
		if jn == "pelvis":
			j.global_transform = Transform3D(b, _pos[_idx["pelvis"]])
		else:
			j.global_basis = b


static func _arc(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	var s := axis.length()
	var c := from.dot(to)
	if s < 0.00001:
		return Basis()
	return Basis(axis / s, atan2(s, c))


func _forward() -> Vector3:
	var hips := (joints.l_hip as Node3D).global_position - (joints.r_hip as Node3D).global_position
	var up := (joints.chest as Node3D).global_position - (joints.pelvis as Node3D).global_position
	return hips.cross(up).normalized() if hips.length() > 0.001 else Vector3.FORWARD
