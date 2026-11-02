class_name QuestNews
extends RefCounted
## The big quest banner's queue: a few words in the middle of the screen when a
## quest or job starts, moves on or ends ("New Job", "Cargo Found", "Target
## Killed"), with a sound. Pure and static, like Quests: a system pushes a key
## from content/core/story/main.json "quest_news" and a subtitle (what, or the
## pay); QuestBanner (on the ObjectiveHud) shows them one at a time.
##
## Not saved, and WorldState.reset() clears it: a load is not news.

const MAX := 4                         ## past this many waiting, the oldest drops off

static var queue: Array = []           ## [{ key, head, sub, hint, sound }], oldest first


static func cfg(key: String) -> Dictionary:
	return Story.data().get("quest_news", {}).get(key, {})


## Queue `key`'s banner with `sub` under it. The same banner twice in a row is one.
static func push(key: String, sub: String = "") -> void:
	var c := cfg(key)
	if c.is_empty():
		return
	if not queue.is_empty() and queue[-1].key == key and queue[-1].sub == sub:
		return
	queue.append({ "key": key, "head": str(c.get("head", key)), "sub": sub,
		"hint": str(c.get("hint", "")), "sound": str(c.get("sound", "")) })
	while queue.size() > MAX:
		queue.pop_front()


## Take back a banner still waiting (not shown yet): the one with this key and
## subtitle, if it is queued.
static func retract(key: String, sub: String) -> void:
	for i in range(queue.size() - 1, -1, -1):
		if queue[i].key == key and queue[i].sub == sub:
			queue.remove_at(i)


## The next banner to show, or {}.
static func take() -> Dictionary:
	return queue.pop_front() if not queue.is_empty() else {}


static func clear() -> void:
	queue.clear()
