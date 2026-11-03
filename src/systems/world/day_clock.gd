class_name DayClock
extends RefCounted
## The time of day moves on with the game (issue #381). Pure and static, like
## Territory: it picks the preset; the town scene (town_demo) puts it on the sky.
## Every change happens where you cannot see the sky, as a plain preset swap.
##
##   Auto (freeplay, and a story save once the cruiser is won): each trigger
##     (going indoors, a faded trip to another planet, waking in the pit) steps
##     the day on along time_of_day.json "day_order", never landing on the time
##     you are in, and only once "day_min_seconds" of play (WorldState.clock)
##     have gone by since the last step. The seamless hop to the moon is no trigger.
##   A story save before the cruiser is won: the time is the chapter's ("time"
##     on each chapter in content/core/story/main.json; "time_after_job" once
##     you have taken that job). The L key and F11's time controls are locked.
##   The picker on Golden / Noon / Dusk: the time stays there; triggers do nothing.
##
## State (saved with the world): WorldState.time_of_day, day_pick ("auto" or a
## preset), day_step (where in day_order the day is: golden comes twice) and
## day_moved_at (WorldState.clock at the last step).

const PATH := "res://content/look/time_of_day.json"
const AUTO := "auto"
const PICKS := [AUTO, "golden", "noon", "dusk"]

static var _order: Array = []
static var _min_seconds := -1.0


static func _data() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


## The day's presets in order, round and round.
static func order() -> Array:
	if _order.is_empty():
		var o = _data().get("day_order", [])
		_order = o if o is Array and not o.is_empty() else ["golden", "noon", "golden", "dusk"]
	return _order


## Seconds of play the day holds on Auto before a trigger can move it on.
static func min_seconds() -> float:
	if _min_seconds < 0.0:
		_min_seconds = maxf(0.0, float(_data().get("day_min_seconds", 300.0)))
	return _min_seconds


## A story save before the cruiser is won: the chapters set the time.
static func locked() -> bool:
	return WorldState.story_mode() and not Story.cruiser_taken()


## The time the story's chapter asks for, or "" when it sets none.
static func story_time() -> String:
	var c := Story.chapter_cfg()
	var after: Dictionary = c.get("time_after_job", {})
	for job in after:
		if _taken(str(job)):
			return str(after[job])
	return str(c.get("time", ""))


## Job `id` taken in this save. A bounty contract is not kept in jobs_taken:
## it counts once one has been taken (bounties_taken).
static func _taken(id: String) -> bool:
	if WorldState.jobs_taken.has(id):
		return true
	return str(WorldState.job(id).get("kind", "")) == "bounty" and WorldState.count("bounties_taken") > 0


## The preset the light should change to after `trigger` ("indoors", "travel",
## "respawn"), or "" to leave it. Moves the day on (WorldState.time_of_day,
## day_step); the scene applies what it returns.
static func trigger(_trigger: String) -> String:
	if locked():
		return _to(story_time())
	if WorldState.day_pick != AUTO:
		return _to(WorldState.day_pick)
	if WorldState.clock - WorldState.day_moved_at < min_seconds():
		return ""                               # too soon after the last step: the day holds
	var o := order()
	var s := WorldState.day_step
	if s < 0 or s >= o.size() or str(o[s]) != WorldState.time_of_day:
		s = o.find(WorldState.time_of_day)      # moved by hand or by the story: pick up from there
	for k in o.size():
		s = (s + 1) % o.size()
		if str(o[s]) != WorldState.time_of_day:
			break
	WorldState.day_step = s
	WorldState.day_moved_at = WorldState.clock
	return _to(str(o[s]))


## The time a town opens on: the chapter's in a locked story save, the next one
## after a faded trip (`arrival_mode` "travel"), else the time the world is in.
static func on_arrival(arrival_mode: String) -> String:
	if arrival_mode == "travel":
		trigger("travel")
	elif locked():
		_to(story_time())
	return WorldState.time_of_day


## The story's time, if it has moved on from the light (the chapter or the
## bounty job changed while you were indoors), else "".
static func story_due() -> String:
	return _to(story_time()) if locked() else ""


## The picker: "auto" or a preset. Returns the preset to put on now ("" = none).
static func pick(p: String) -> String:
	if locked() or not PICKS.has(p):
		return ""
	WorldState.day_pick = p
	return _to(p) if p != AUTO else ""


## The time was set by hand (the L key, the hour slider, a preset button): the
## picker holds there. False while the story has the time locked.
static func set_by_hand(preset: String) -> bool:
	if locked():
		return false
	if PICKS.has(preset) and preset != AUTO:
		WorldState.day_pick = preset
	return true


## `preset`, written to the world, if it differs from the time it is; else "".
static func _to(preset: String) -> String:
	if preset == "" or preset == WorldState.time_of_day:
		return ""
	WorldState.time_of_day = preset
	var i := order().find(preset)
	if i >= 0 and str(order()[WorldState.day_step % order().size()]) != preset:
		WorldState.day_step = i
	return preset
