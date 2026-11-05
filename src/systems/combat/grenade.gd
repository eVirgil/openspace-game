class_name Grenade
extends Node3D
## Issue #372: a thrown grenade. A thin node on GrenadeArc: each physics tick it
## takes one arc step, and where the step's ray touches something it either bursts
## (a person, a droid, a vehicle: anything Blast would hurt) or bounces (the ground,
## a wall), losing speed each bounce, until it rests. The fuse bursts it wherever it
## is. The burst is Blast.burst with the grenade's data.
##
## Headless tests drive tick() with their own `hit` and `up_at` (no physics needed).

const CFG_PATH := "res://content/core/weapons/grenade.json"

signal burst(at: Vector3, hurt: Array)

var cfg: Dictionary = {}           ## content/core/weapons/grenade.json
var velocity := Vector3.ZERO
var shooter: Node = null           ## the player: never bounces off or bursts on its thrower
var player: Node = null            ## the local player, hurt by its own grenade (friendly fire)
var host: Node = null              ## where the blast's effects go (null: the parent)
var up_at: Callable = Callable()   ## (p) -> Vector3; default the planet's up
var hit: Callable = Callable()     ## (a, b) -> Dictionary ray hit; default this world's physics
var is_target: Callable = Callable()   ## (collider) -> bool: touching it bursts; default Blast.target
var fuse_left := 3.0
var bounces := 0
var first_contact := Vector3.INF   ## where it first touched anything (the preview's landing)
var resting := false
var done := false
var _look: Node3D


func setup(c: Dictionary, at: Vector3, v: Vector3, thrower: Node = null) -> void:
	cfg = c
	position = at
	velocity = v
	shooter = thrower
	fuse_left = float(cfg.get("fuse_s", 3.0))


func _ready() -> void:
	name = "Grenade"
	top_level = true                  # its position is the world's (the rays are)
	if _look == null and DisplayServer.get_name() != "headless":
		_look = ItemKit.new().build(str(cfg.get("look", "grenade")))
		add_child(_look)


func _physics_process(dt: float) -> void:
	tick(dt)


## One tick: the fuse, then one arc step (or nothing, at rest). Returns true once it burst.
func tick(dt: float) -> bool:
	if done:
		return true
	fuse_left -= dt
	if fuse_left <= 0.0:
		_burst(position)
		return true
	if resting:
		return false
	var up := _up(position)
	var s := GrenadeArc.step(position, velocity, up, float(cfg.get("gravity", 20.0)), dt)
	var to: Vector3 = s[0]
	var h := _ray(position, to)
	if h.is_empty():
		position = to
		velocity = s[1]
		_spin(dt)
		return false
	if first_contact == Vector3.INF:
		first_contact = h.position
	if _bursts_on(h.get("collider")):
		_burst(h.position)
		return true
	var n: Vector3 = h.get("normal", up)
	velocity = GrenadeArc.bounce(s[1], n, float(cfg.get("bounce", 0.38)), float(cfg.get("slide", 0.62)))
	position = h.position + n.normalized() * float(cfg.get("radius_m", 0.09))
	bounces += 1
	if velocity.length() < float(cfg.get("rest_speed", 0.6)):
		velocity = Vector3.ZERO
		resting = true
	return false


func _bursts_on(c) -> bool:
	if c == null or (shooter != null and c == shooter):
		return false
	if is_target.is_valid():
		return bool(is_target.call(c))
	return Blast.target(c) != null


func _burst(at: Vector3) -> void:
	done = true
	position = at
	var hurt: Array = []
	var into: Node = host if host != null else get_parent()
	if is_inside_tree():
		hurt = Blast.burst(into, global_position, cfg, shooter, player)
	burst.emit(at, hurt)
	if is_inside_tree():
		queue_free()


func _up(p: Vector3) -> Vector3:
	if up_at.is_valid():
		return up_at.call(p)
	return PlanetSphere.current.up_at(p) if PlanetSphere.current != null else Vector3.UP


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if hit.is_valid():
		return hit.call(a, b)
	if not is_inside_tree():
		return {}
	return ray(get_world_3d().direct_space_state, a, b, shooter)


## The ray the grenade and its preview both use: any body but the thrower (and
## the cruiser bay's shield, which bolts pass too).
static func ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, thrower: Node) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	var skip: Array[RID] = []
	if thrower is CollisionObject3D:
		skip.append((thrower as CollisionObject3D).get_rid())
	q.exclude = skip
	var h := space.intersect_ray(q)
	while not h.is_empty() and (h.collider as Object).has_meta("bolts_pass"):
		skip.append(h.rid)
		q.exclude = skip
		h = space.intersect_ray(q)
	return h


func _spin(dt: float) -> void:
	if _look != null:
		_look.rotate_object_local(Vector3.RIGHT, dt * 9.0)
