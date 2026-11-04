class_name ClubMusic
extends Node
## Issue #104: tells Sound where the player is from this town's cantina, every
## frame: the club's playlist, how near they are (0 at `hear` metres from the
## walls .. 1 against them) and whether they are inside. The scene changes and
## this node goes: no club.
##
## A new band plays every visit, so the music is back on when the town is built
## again after the last band was killed.
##
## Issue #392: on a station whose dome is the club (club_dome), the hallway and
## the landing pit count as inside too (also_inside), so the rave's mix is the
## only music anywhere on the station, even in a gunfight.
##
## Issue #269: a club can also follow a node (the party barge): heard by distance
## from it, inside within `follow_r` metres. With more than one club in a scene,
## the loudest one is what Sound plays.

var playlist := ""
var rect := Rect2()     ## the cantina's floor (x, z), in the scene's space
var target: Node3D      ## the player
var hear := 40.0
var follow: Node3D       ## issue #269: a moving club (the barge); rect unused
var follow_r := 0.0
var inside_fn := Callable()   ## optional: (pos) -> bool, overrides "within follow_r"
var also: Array = []          ## issue #392: more floors (Rect2s) that count as inside (the station's hall and pit)
static var _levels: Dictionary = {}   ## instance id -> [playlist, near, inside]


func setup(id: String, zone: Dictionary, who: Node3D) -> ClubMusic:
	name = "ClubMusic"
	playlist = id
	target = who
	var a: Array = zone.get("min", [0, 0])
	var b: Array = zone.get("max", [0, 0])
	rect = Rect2(float(a[0]), float(a[1]), float(b[0]) - float(a[0]), float(b[1]) - float(a[1]))
	hear = float(Sound.lib().cfg.get("club", {}).get("hear", 40.0))
	Sound.set_club_live(true)
	return self


## Issue #392: the moon rave's mix fills the whole station: these zones (the
## town's zone dicts) count as inside too, on foot (in a ship you have taken off).
func also_inside(zones: Array) -> ClubMusic:
	for z in zones:
		var a: Array = z.get("min", [0, 0])
		var b: Array = z.get("max", [0, 0])
		also.append(Rect2(float(a[0]), float(a[1]), float(b[0]) - float(a[0]), float(b[1]) - float(a[1])))
	return self


## Issue #269: the same club music, heard from a node that moves.
func setup_follow(id: String, node: Node3D, radius: float, who: Node3D) -> ClubMusic:
	name = "ClubMusic_" + node.name
	playlist = id
	target = who
	follow = node
	follow_r = radius
	hear = float(Sound.lib().cfg.get("club", {}).get("hear", 40.0)) * 1.5
	Sound.set_club_live(true)
	return self


func _process(_dt: float) -> void:
	var key := get_instance_id()
	if playlist == "" or not is_instance_valid(target) or (follow != null and not is_instance_valid(follow)):
		_levels.erase(key)
	else:
		var p := target.global_position
		var d: float
		var inside: bool
		if follow != null:
			d = maxf(0.0, p.distance_to(follow.global_position) - follow_r)
			inside = bool(inside_fn.call(p)) if inside_fn.is_valid() else d <= 0.0
		else:
			d = distance(rect, p.x, p.z)
			inside = d <= 0.0
			if not inside and target.get("piloting") != true:
				for r in also:
					if distance(r, p.x, p.z) <= 0.0:
						d = 0.0
						inside = true
						break
		_levels[key] = [playlist, near(d, hear), inside]
	_apply()


func _exit_tree() -> void:
	_levels.erase(get_instance_id())
	_apply()


## The loudest club in the scene is the one Sound plays.
static func _apply() -> void:
	var best: Array = []
	for k in _levels:
		var l: Array = _levels[k]
		if best.is_empty() or float(l[1]) > float(best[1]) or (bool(l[2]) and not bool(best[2])):
			best = l
	if best.is_empty():
		Sound.set_club("", 0.0, false)
	else:
		Sound.set_club(str(best[0]), float(best[1]), bool(best[2]))


## Metres from (x, z) to the nearest point of `r` (0 inside it).
static func distance(r: Rect2, x: float, z: float) -> float:
	var dx := maxf(maxf(r.position.x - x, 0.0), x - r.end.x)
	var dz := maxf(maxf(r.position.y - z, 0.0), z - r.end.y)
	return sqrt(dx * dx + dz * dz)


## 1 at the walls, falling to 0 at `hear` metres out.
static func near(d: float, hear_m: float) -> float:
	return clampf(1.0 - d / maxf(hear_m, 0.001), 0.0, 1.0)
