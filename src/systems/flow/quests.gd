class_name Quests
extends RefCounted
## Optional quests (issue #201). Pure and static, like Story; their state lives in
## WorldState.quests (saved with the world): id -> { state: "open"|"done"|"failed", waypoint }.
## Issue #303: a quest can fail (fail(): the dark master's oath, broken); "{town}"
## in its text is the town's name.
##
## Each quest is data in content/core/story/main.json "quests": { id, title, text,
## target, unlocked_by, done_on }, plus one resupply quest per outpost that
## Territory offers, finishes and offers again (Territory.quests, offer_again). Every Story.event() reaches event() here, so a
## quest unlocks (and finishes) on any event name a system reports. A quest done
## before it was ever offered is just done, with no news.
##
## Nothing points at a quest until the player switches its waypoint on in the job
## log (one at a time). A quest offered, done or failed is news for the HUD's
## banner (QuestNews).


static func all() -> Array:
	return Story.data().get("quests", []) + Territory.quests()


static func cfg(id: String) -> Dictionary:
	for q in all():
		if str(q.id) == id:
			return q
	return {}


## "" (not offered), "open", "done" or "failed".
static func state(id: String) -> String:
	return str(WorldState.quests.get(id, {}).get("state", ""))


static func event(name: String) -> void:
	if name == "":
		return
	for q in all():
		if str(q.get("unlocked_by", "")) == name:
			unlock(str(q.id))
		if str(q.get("done_on", "")) == name:
			complete(str(q.id))


## Offer a quest. Returns true if it is new.
static func unlock(id: String) -> bool:
	var q := cfg(id)
	if q.is_empty() or WorldState.quests.has(id):
		return false
	WorldState.quests[id] = { "state": "open", "waypoint": false }
	QuestNews.push("quest_new", str(q.get("title", id)))
	WorldState.log_event("New quest: %s." % str(q.get("title", id)))
	return true


## Offer a quest again that was done or failed (a repeatable one). Returns true if it is new.
static func offer_again(id: String) -> bool:
	if state(id) in ["done", "failed"]:
		WorldState.quests.erase(id)
	return unlock(id)


static func complete(id: String) -> bool:
	if cfg(id).is_empty() or state(id) in ["done", "failed"]:
		return false
	if state(id) == "open":            # done before it was offered: no news
		QuestNews.push("quest_done", str(cfg(id).get("title", id)))
	WorldState.quests[id] = { "state": "done", "waypoint": false }
	return true


## An open quest that can no longer be done.
static func fail(id: String) -> bool:
	if state(id) != "open":
		return false
	WorldState.quests[id] = { "state": "failed", "waypoint": false }
	QuestNews.push("quest_failed", str(cfg(id).get("title", id)))
	WorldState.log_event("Quest failed: %s." % str(cfg(id).get("title", id)))
	return true


## An open quest with somewhere to point at.
static func can_point(id: String) -> bool:
	return state(id) == "open" and str(cfg(id).get("target", "")) != ""


## Switch a quest's waypoint on (every other one goes off) or off. Returns it.
static func toggle_waypoint(id: String) -> bool:
	if not can_point(id):
		return false
	var on := not bool(WorldState.quests[id].get("waypoint", false))
	for k in WorldState.quests:
		WorldState.quests[k].waypoint = false
	WorldState.quests[id].waypoint = on
	if on:
		GlobeMap.clear_waypoint()      # one pointer at a time: the F11 map's goes
		WorldState.objective_pin = ""  # and the Ledger's pick
	return on


## { text, target, key } for the pointer while a quest's waypoint is on, else {}.
static func waypoint() -> Dictionary:
	for id in WorldState.quests:
		if bool(WorldState.quests[id].get("waypoint", false)) and can_point(str(id)):
			var q := cfg(str(id))
			return { "text": DarkPact.fill(str(q.get("text", ""))), "target": str(q.target), "key": "quest:" + str(id) }
	return {}


## Every quest offered, in the data's order: [{ id, title, text, done, waypoint, can_point }].
static func entries() -> Array:
	var out: Array = []
	for q in all():
		var id := str(q.id)
		if state(id) == "":
			continue
		out.append({ "id": id, "title": str(q.get("title", id)), "text": DarkPact.fill(str(q.get("text", ""))),
			"done": state(id) == "done", "failed": state(id) == "failed", "waypoint": bool(WorldState.quests[id].get("waypoint", false)),
			"can_point": can_point(id) })
	return out
