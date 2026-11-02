class_name StandingNews
extends RefCounted
## Faction standing changes waiting to be shown (StandingToast): WorldState
## .change_standing pushes one for every real change, from where the standing
## was to where it is now. Two changes to the same faction that are both still
## waiting are one (first "from", last "to"). Pure and static, like QuestNews.
##
## Not saved, and WorldState.reset() clears it: a load is not news. Only
## faction standing comes through here; what one character thinks of you (Oda's
## trust) never does.

const MAX := 8                         ## past this many waiting, the oldest drops off

static var queue: Array = []           ## [{ faction, from, to }], oldest first


## Queue the move of `faction`'s standing from `from_v` to `to_v`. No move (a
## standing already at its limit) is not news.
static func push(faction: String, from_v: int, to_v: int) -> void:
	if from_v == to_v:
		return
	for e in queue:
		if e.faction == faction:
			e.to = to_v
			return
	queue.append({ "faction": faction, "from": from_v, "to": to_v })
	while queue.size() > MAX:
		queue.pop_front()


## Everything waiting, oldest first; the queue is empty after.
static func take_all() -> Array:
	var all := queue.duplicate()
	queue.clear()
	return all


static func clear() -> void:
	queue.clear()


## "Remnant" for "imperial_remnant" (content/core/story/main.json "standing_names").
static func faction_name(faction: String) -> String:
	return str(Story.data().get("standing_names", {}).get(faction, faction.replace("_", " ").capitalize()))
