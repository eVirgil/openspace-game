class_name GameFlow
extends RefCounted
## Scene flow between the port (on foot) and flight.
##
## M14: two ways up. A pad's quick launch (mode "pad") as before, or flying the
## ship out of the atmosphere (mode "ascent", see ShipPilot). Two ways down: after
## a fight, or by diving at the planet, the player re-enters still flying, in the
## sky above the port (arrival mode "reentry"); a lost ship limps home to the pad
## on foot (arrival mode "pad").
##
## Issue #46: the town's own ship no longer leaves the scene. Flying out of the
## atmosphere keeps you in the port's sky, over the same ground, and (when
## space_dogfight() is on) starts the pad's encounter right there (SpaceFight).
## The pad launch below is still the hand-off for a quick-launch pad and the
## stand-alone dogfight scene.
##
## The port and the dogfight are separate scenes. This class is the hand-off
## between them: a launch pad in the port calls launch(), the dogfight scene asks
## which encounter to fly, and when the fight ends it calls finish_flight(), which
## loads the port again. The port then calls take_arrival() to spawn the player
## at the pad they left from and show the outcome.
##
## State lives in static vars so it survives change_scene_to_file(). There is no
## autoload on purpose: nothing runs unless a pad starts a flight, so opening the
## dogfight scene on its own (F6, tests, review renders) behaves exactly as before.
##
## Tests swap `change_scene` for a recorder so they never tear down the GUT tree.

const PADS_PATH := "res://content/core/flow/launch_pads.json"

static var in_flight := false
static var pad_id := ""
static var encounter_id := ""
static var return_scene := ""
static var arrival: Dictionary = {}       ## { pad, encounter, outcome, payout, mode } until taken
static var mode := ""                     ## M14: how this flight started: "pad" or "ascent"
static var change_scene: Callable = Callable()
## Issue #46: null = the data's "space_dogfight"; a bool once a menu (F11) sets it.
static var dogfight_override: Variant = null
## Issue #45: the planet the town scene builds ("" = the home planet), and the ship
## the player flew in on from another planet ("" = none: the pad's own ship).
static var planet_id := ""
static var flown_ship := ""
static var flown_key := ""                ## issue #368: which of your ships that is (Fleet key; "" = none of yours)
## Issue #113: the game opened from a save resumes where it was: the planet, then
## the spot (resume_pos, taken once by the town's spawn). Once per run.
static var resumed := false
static var resume_pos := Vector3.INF

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PADS_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			push_warning("GameFlow: could not read ", PADS_PATH)
	return _data


static func pad(id: String) -> Dictionary:
	var p: Dictionary = data().get("pads", {}).get(id, {})
	if p.is_empty():
		return {}
	var out := p.duplicate(true)
	out["id"] = id
	return out


## Every pad that belongs to a scene, by scene path.
static func pads_for_scene(scene_path: String) -> Array:
	var out: Array = []
	for id in data().get("pads", {}).keys():
		var p := pad(id)
		if str(p.get("scene", "")) == scene_path:
			out.append(p)
	return out


static func label(key: String) -> String:
	return str(data().get("labels", {}).get(key, ""))


static func setting(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


static func vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## Issue #46: does flying out of the atmosphere start the pad's space fight? On by
## default ("space_dogfight" in the pads data); a menu can switch it at runtime.
static func space_dogfight() -> bool:
	if dogfight_override != null:
		return bool(dogfight_override)
	return bool(data().get("space_dogfight", true))


static func set_space_dogfight(on: bool) -> void:
	dogfight_override = on


## Start a flight from a pad. Loads the flight scene.
static func launch(tree: SceneTree, from_pad: Dictionary, how: String = "pad") -> void:
	in_flight = true
	mode = how
	pad_id = str(from_pad.get("id", ""))
	encounter_id = str(from_pad.get("encounter", ""))
	return_scene = str(from_pad.get("scene", data().get("default_port_scene", "")))
	arrival = {}
	_go(tree, str(data().get("flight_scene", "res://scenes/flight/dogfight_demo.tscn")))


## M14: the ship flew out of the atmosphere from a pad's town. Same hand-off as a
## launch, so the space scene flies the pad's encounter.
static func ascend(tree: SceneTree, from_pad: Dictionary) -> void:
	launch(tree, from_pad, "ascent")


## End the flight and load the port it started from. Safe to call when no flight
## is active (does nothing), so a stand-alone dogfight never jumps scenes.
## `how`: "pad" lands you on foot beside the pad; "reentry" (M14) puts you back in
## the port's sky, still flying.
static func finish_flight(tree: SceneTree, outcome: String, payout: int = 0, how: String = "pad") -> bool:
	if not in_flight:
		return false
	in_flight = false
	arrival = { "pad": pad_id, "encounter": encounter_id, "outcome": outcome, "payout": payout, "mode": how }
	var target := return_scene if return_scene != "" else str(data().get("default_port_scene", ""))
	_go(tree, target)
	return true


## The port calls this once on load. Returns the arrival (and clears it) when the
## player is coming back from a flight, else {}.
static func take_arrival() -> Dictionary:
	var a := arrival
	arrival = {}
	return a


static func arrival_text(a: Dictionary) -> String:
	if a.is_empty():
		return ""
	if str(a.get("mode", "")) in ["travel", "handoff"]:
		var t := label("arrive_planet")
		return t % str(a.get("name", "")) if t.contains("%s") else t
	if str(a.get("mode", "")) == "reentry" and str(a.get("outcome", "")) != "complete":
		return label("arrive_reentry")
	if str(a.get("outcome", "")) == "complete":
		var t := label("arrive_complete")
		return t % int(a.get("payout", 0)) if t.contains("%d") else t
	return label("arrive_failed")


static func reset() -> void:
	in_flight = false
	pad_id = ""
	encounter_id = ""
	return_scene = ""
	arrival = {}
	mode = ""
	change_scene = Callable()
	dogfight_override = null
	planet_id = ""
	flown_ship = ""
	flown_key = ""


# ------------------------------------------------------------------ resume (issue #113)

## Once per run, before the first town is built: the save's planet becomes the
## one to build, and its spot the one to stand on. A planet that no longer exists
## (or a save with no "where") leaves the home planet's spawn, as before.
static func resume_from_save(path: String) -> bool:
	if resumed:
		return false
	resumed = true
	var w: Dictionary = load("res://src/systems/save/save_system.gd").where_in(path)
	var id := str(w.get("planet", ""))
	if id == "" or not PlanetGen.is_planet(id) or PlanetGen.build(id).is_empty():
		return false           # issue #573: open space is never where a save puts you
	planet_id = "" if id == PlanetGen.home_id() else id
	var p = w.get("pos", null)
	resume_pos = Vector3(float(p[0]), float(p[1]), float(p[2])) if p is Array and (p as Array).size() == 3 else Vector3.INF
	return true


## The spot to stand on after a resume (INF = none), taken once.
static func take_resume_pos() -> Vector3:
	var p := resume_pos
	resume_pos = Vector3.INF
	return p


# ------------------------------------------------------------------ planets (issue #45)

## The planet the town scene is (or is about to be) built for.
static func current_planet_id() -> String:
	return planet_id if planet_id != "" else PlanetGen.home_id()


static func planet() -> Dictionary:
	return PlanetGen.build(current_planet_id())


## Fly from this planet to `to`: the town scene reloads as that planet, and the
## ship you flew (`ship_id`) arrives in its sky, still flying, above its bay. The
## same scene file every time: a planet is data, not a scene.
## `extra` (issue #99): { handoff: { position, basis, speed, throttle } in the
## new planet's own coordinates, hour, preset }: no fade, the ship carries on
## exactly where it was, under the same sun.
static func travel(tree: SceneTree, to: String, ship_id: String = "", name: String = "", extra: Dictionary = {}) -> void:
	var from := current_planet_id()
	planet_id = to
	flown_ship = ship_id
	in_flight = false
	arrival = { "mode": "handoff" if extra.has("handoff") else "travel", "from": from, "to": to, "ship": ship_id, "name": name,
		"pad": str(data().get("pads", {}).keys()[0]) if not data().get("pads", {}).is_empty() else "" }
	arrival.merge(extra)
	var path := str(data().get("default_port_scene", "res://scenes/town_demo.tscn"))
	if extra.has("handoff") and not change_scene.is_valid() and tree != null:
		_swap_scene.call_deferred(tree, path)
		return
	_go(tree, path)


static func _go(tree: SceneTree, path: String) -> void:
	if change_scene.is_valid():
		change_scene.call(path)
	elif tree != null:
		tree.change_scene_to_file.call_deferred(path)


## A no-fade handoff's scene change: the old scene leaves the tree, the new one
## takes its place in the same frame, and the old one is freed over the frames
## after (SceneReaper) instead of all at once before the new one is built.
static func _swap_scene(tree: SceneTree, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		tree.change_scene_to_file(path)
		return
	var old := tree.current_scene
	if old != null:
		tree.root.remove_child(old)
	var fresh := packed.instantiate()
	tree.root.add_child(fresh)
	tree.current_scene = fresh
	SceneReaper.reap(old)
