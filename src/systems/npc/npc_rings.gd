extends Node
## Issue #541: the town's own people think less the further they are from every
## player, and sleep past the draw distance, as the outposts' guards already do.
## Three rings from content/core/npcs/wake_rings.json:
##   FULL   within near_m: senses, brain and walking every tick
##   SLOW   to far_m: walking every tick, senses and brain every think_every ticks
##          (NpcBody.think_stride; Garrison and Townsfolk read it for the brain)
##   ASLEEP past far_m: PROCESS_MODE_DISABLED, think_stride 0 (the directors skip
##          the brain); the body stands where it was and walks on when woken
## Checked every tick (a distance per body), so walking back in wakes everyone the
## tick they cross; a ring is left inward only hysteresis_m inside its edge. The
## altitude tiers still hide the whole "people" group from high up on top of this.

const PATH := "res://content/core/npcs/wake_rings.json"
enum Ring { FULL, SLOW, ASLEEP }

var demo                               ## town_demo.gd
var near_m := 60.0
var far_m := 320.0
var hysteresis_m := 20.0
var think_every := 4
var ring_of: Dictionary = {}           ## NpcBody -> Ring
var counts := { "full": 0, "slow": 0, "asleep": 0 }   ## last tick (traces, probes)


static func config() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


func setup(town_demo) -> void:
	demo = town_demo
	name = "NpcRings"
	var c := config()
	near_m = float(c.get("near_m", near_m))
	far_m = float(c.get("far_m", far_m))
	hysteresis_m = float(c.get("hysteresis_m", hysteresis_m))
	think_every = maxi(1, int(c.get("think_every", think_every)))


## The ring for someone `d` metres from the nearest player, coming from `was`.
func ring_for(d: float, was: int) -> int:
	var far_edge := far_m - (hysteresis_m if was == Ring.ASLEEP else 0.0)
	var near_edge := near_m - (hysteresis_m if was != Ring.FULL else 0.0)
	if d > far_edge:
		return Ring.ASLEEP
	if d > near_edge:
		return Ring.SLOW
	return Ring.FULL


func _physics_process(_dt: float) -> void:
	if demo == null or bool(demo.get("lan_shared")):
		return
	var viewers := _viewers()
	if viewers.is_empty():
		return
	counts = { "full": 0, "slow": 0, "asleep": 0 }
	for d in [demo.get("garrison"), demo.get("townsfolk"), demo.get("locals_garrison")]:
		if d == null or not is_instance_valid(d):
			continue
		var up: bool = d.alarm != null and d.alarm.active()
		var busy := _busy_guards(d)
		for g in d.members:
			if not is_instance_valid(g) or _own_sleep(g):
				continue
			var r := Ring.FULL
			if not (g.dead or up or g.hostile or g.perception.noticed or busy.has(g)):
				r = ring_for(_nearest(g.global_position, viewers), int(ring_of.get(g, Ring.FULL)))
			_put(g, r)
	_forget_freed()


func _put(g, r: int) -> void:
	ring_of[g] = r
	match r:
		Ring.ASLEEP:
			g.think_stride = 0
			g.process_mode = Node.PROCESS_MODE_DISABLED
			counts.asleep += 1
		Ring.SLOW:
			g.think_stride = think_every
			g.process_mode = Node.PROCESS_MODE_INHERIT
			counts.slow += 1
		_:
			g.think_stride = 1
			g.process_mode = Node.PROCESS_MODE_INHERIT
			counts.full += 1


## Where the players are: you, and on a LAN host every guest's body here.
func _viewers() -> Array:
	var out: Array = []
	var p = demo.get("_player")
	if p != null and is_instance_valid(p) and p is Node3D:
		out.append((p as Node3D).global_position)
	if NetSession.is_host() and NetSession.link != null:
		for b in NetSession.link.bodies.values():
			if is_instance_valid(b) and b is Node3D:
				out.append((b as Node3D).global_position)
	return out


static func _nearest(at: Vector3, viewers: Array) -> float:
	var best := INF
	for v in viewers:
		best = minf(best, at.distance_to(v))
	return best


## Someone another system already puts to sleep (an outpost's, a ranch's, the
## cruiser's) or keeps on its own (a bounty target, the general's squad, a heist's
## wave): left to it, as before.
static func _own_sleep(g) -> bool:
	for m in ["outpost", "ranch", "cruiser", "bounty", "general_squad", "heist_wave"]:
		if g.has_meta(m):
			return true
	return false


## The gate's and the zones' guards while their checkpoint is dealing with you
## (asking, searching, warning, found something, or fighting; not once cleared).
func _busy_guards(d) -> Dictionary:
	var out := {}
	if not d.has_method("_posts"):
		return out
	for post in d._posts():
		var cp = post.checkpoint
		if cp != null and cp.state != Checkpoint.State.IDLE and cp.state != Checkpoint.State.CLEARED:
			for g in post.guards:
				out[g] = true
	return out


func _forget_freed() -> void:
	if ring_of.size() < 256:
		return
	for g in ring_of.keys():
		if not is_instance_valid(g):
			ring_of.erase(g)
