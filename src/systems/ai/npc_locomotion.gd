extends RefCounted
## Path following for a body on foot. Pure and headless-testable, like the flight
## model: it is handed a path (from TownNav) and the body's position each frame,
## and it says which way to walk, how fast (0..1), and whether the body has
## arrived or is stuck. The body node turns that into a CharacterController
## command, so an NPC walks with exactly the player's movement code.
##
## Every number comes from the soldier profile's "nav" block.

var waypoint_reach := 0.5    ## m: close enough to a corner to take the next one
var arrive_radius := 0.6     ## m: close enough to the final point
var slow_radius := 2.0       ## m: ease off the speed inside this of the end
var stuck_s := 2.0           ## s: window for the stuck check
var stuck_move := 0.35       ## m: must get this much closer along the path per window, or stuck
var corner_lead_s := 0.3     ## s: at speed, take a corner this far ahead (momentum)

var path: Array = []         ## Vector3 points, the first is where we started
var index := 0               ## the point we are walking to
var arrived := true
var stuck := false

var _stuck_clock := 0.0
var _best_left := INF        ## best remaining distance seen this window


func _init(nav: Dictionary = {}) -> void:
	waypoint_reach = float(nav.get("waypoint_reach", waypoint_reach))
	arrive_radius = float(nav.get("arrive_radius", arrive_radius))
	slow_radius = float(nav.get("slow_radius", slow_radius))
	stuck_s = float(nav.get("stuck_s", stuck_s))
	stuck_move = float(nav.get("stuck_move", stuck_move))
	corner_lead_s = float(nav.get("corner_lead_s", corner_lead_s))


func set_path(points) -> void:
	path = []
	for p in points:
		path.append(p)
	index = 1 if path.size() > 1 else 0
	arrived = path.is_empty()
	stuck = false
	_stuck_clock = 0.0
	_best_left = INF


func clear() -> void:
	set_path([])


func goal() -> Vector3:
	return path[path.size() - 1] if not path.is_empty() else Vector3.INF


func has_path() -> bool:
	return not path.is_empty() and not arrived


## Advance one frame. `ground_speed` is how fast the body is actually moving
## (m/s): a running body carries momentum, so it takes corners earlier.
## Returns { move: Vector3 (flat, unit or zero), speed: 0..1, arrived, stuck }.
## Issue #540: with `reuse_out` the same dictionary comes back every call, filled in
## (NpcBody reads it at once and keeps nothing); else a new one, as before.
var reuse_out := false
var _out := { "move": Vector3.ZERO, "speed": 0.0, "arrived": false, "stuck": false }


func _result(move: Vector3, speed: float, arrived_now: bool, stuck_now: bool) -> Dictionary:
	if not reuse_out:
		return { "move": move, "speed": speed, "arrived": arrived_now, "stuck": stuck_now }
	_out.move = move
	_out.speed = speed
	_out.arrived = arrived_now
	_out.stuck = stuck_now
	return _out


func update(dt: float, pos: Vector3, ground_speed: float = 0.0) -> Dictionary:
	if path.is_empty() or arrived:
		return _result(Vector3.ZERO, 0.0, arrived, false)

	# Take every corner we are already on (paths often start under our feet).
	var last := path.size() - 1
	var lead := maxf(waypoint_reach, ground_speed * corner_lead_s)
	while index < last and _flat(path[index] - pos).length() <= (lead if _flat_turn(index) else waypoint_reach):
		index += 1
	var to_goal := _flat(path[last] - pos).length()
	if index >= last and to_goal <= arrive_radius:
		arrived = true
		return _result(Vector3.ZERO, 0.0, true, false)

	# Stuck: no progress ALONG THE PATH over a window. This catches a body pinned
	# on a wall and also one circling a corner it keeps overshooting (it moves a
	# lot but gets no closer). A stuck body skips the corner it is fighting; the
	# node also asks for a fresh path.
	var left := remaining(pos)
	_stuck_clock += dt
	stuck = false
	if _best_left == INF:
		_best_left = left
	if _stuck_clock >= stuck_s:
		stuck = _best_left - left < stuck_move
		_stuck_clock = 0.0
		_best_left = left
		if stuck and index < last and _flat_turn(index):
			index += 1

	var to := _flat(path[index] - pos)
	var move := to.normalized() if to.length() > 0.001 else Vector3.ZERO
	var speed := 1.0
	if index >= last and slow_radius > 0.0:
		speed = clampf(to_goal / slow_radius, 0.35, 1.0)
	return _result(move, speed, false, stuck)


## True when the legs into and out of corner `i` stay level. Only then may a
## running body cut the corner (take it early, or skip it when stuck): where the
## path climbs (the foot of a ramp), cutting the corner walks it into the ramp's
## side, a ledge the capsule cannot step.
func _flat_turn(i: int) -> bool:
	var a: Vector3 = path[maxi(i - 1, 0)]
	var b: Vector3 = path[i]
	var c: Vector3 = path[mini(i + 1, path.size() - 1)]
	return absf(b.y - a.y) < 0.3 and absf(c.y - b.y) < 0.3


## Remaining walking distance along the path from `pos`.
func remaining(pos: Vector3) -> float:
	if path.is_empty() or arrived:
		return 0.0
	var d := _flat(path[index] - pos).length()
	for i in range(index, path.size() - 1):
		d += _flat(path[i + 1] - path[i]).length()
	return d


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# ------------------------------------------------------------------ frame helpers

## World move direction -> the controller's local command, for a body whose
## CharacterController yaw is `yaw` (character_body.gd passes -rotation.y).
## Inverse of the mapping in character_controller.gd step().
static func world_to_command(world_dir: Vector3, yaw: float) -> Vector2:
	var c := cos(yaw)
	var s := sin(yaw)
	return Vector2(world_dir.x * c + world_dir.z * s, -world_dir.x * s + world_dir.z * c)


## The rotation.y that faces a body (CharacterKit faces +Z) from `from` toward `to`.
static func facing_toward(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## Turn `cur` toward `want` (radians) by at most `max_step`, the short way round.
static func approach_angle(cur: float, want: float, max_step: float) -> float:
	var d := wrapf(want - cur, -PI, PI)
	if absf(d) <= max_step:
		return want
	return cur + signf(d) * max_step
