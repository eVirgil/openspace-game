class_name Heist
extends RefCounted
## Heists (issue #306): rob an outpost's control room. Pure and static, like
## Territory; its state lives in WorldState.heist (saved with the world):
##   { run, outpost, hacked }    ({} = no heist on)
##
## Issue #309: the console in each outpost's control room (OutpostRoom). Held
## for hack_seconds() while a heist names that outpost (armed), it releases the
## stash: stash_entry() is then a pickup lying at the console (RemnantOutposts
## puts it there, and back after a load) until you take it.
##
## Numbers and lines: content/core/story/heist.json.

const PATH := "res://content/core/story/heist.json"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


static func line(key: String) -> String:
	return str(cfg().get("lines", {}).get(key, ""))


static func hack_cfg() -> Dictionary:
	return cfg().get("hack", {})


static func hack_seconds() -> float:
	return float(hack_cfg().get("seconds", 5.0))


static func reach() -> float:
	return float(hack_cfg().get("reach", 1.4))


static func stash_item() -> String:
	return str(hack_cfg().get("stash", {}).get("item", "refined_quantonium"))


static func stash_count() -> int:
	return int(hack_cfg().get("stash", {}).get("count", 15))


## The outpost the heist on is after ("" = none).
static func target() -> String:
	return str(WorldState.heist.get("outpost", ""))


static func hacked() -> bool:
	return bool(WorldState.heist.get("hacked", false))


## Does outpost `id`'s console have something to release right now?
static func armed(id: String) -> bool:
	return id != "" and target() == id and not hacked()


static func stash_id() -> String:
	return "heist_%d" % int(WorldState.heist.get("run", 0))


## The stash lying at the hacked console, as a pickup entry, or {} (no heist,
## not hacked yet, or already picked up).
static func stash_entry() -> Dictionary:
	if target() == "" or not hacked() or WorldState.inventory.is_taken(stash_id()):
		return {}
	return { "id": stash_id(), "item": stash_item(), "count": stash_count(), "reach": 1.8, "job": true }


## The console at outpost `id` was held long enough: the stash is out. False
## (and nothing changes) when it was not armed.
static func on_hacked(id: String, label: String = "") -> bool:
	if not armed(id):
		return false
	WorldState.heist["hacked"] = true
	WorldState.bump("consoles_hacked")
	WorldState.log_event(line("log_hacked") % (label if label != "" else id))
	return true
