class_name Objective
extends RefCounted
## What to do next, and where (the HUD's objective pointer), and every job you
## have on (the job log on I). Pure and static, like Story: it only reads
## WorldState and the content, and never rolls a job or moves the story on.
##
## Most urgent first: a bounty to collect, a bounty to hunt, contraband to sell,
## a drop to find, supplies for the locals (issue #187), then what the story's
## chapter wants (home planet only).
##
## A target is a word the town scene turns into a place (ObjectiveHud.where):
## npc:<marker>, marker:<marker>, drop:<marker>, range, remote, pad, outpost:<location
## id>, cruiser, droid_post, and the F11 map's map:<x>,<z> and planet:<id>.
## Issue #251: the drop's target is a spot near it (within WorldState.DROP_NEAR,
## its area's marker until the drop is placed), not the exact spot: the last few
## metres are still a search. The general's run takes its goods to him, not the fence.
##
## Every line: content/core/story/main.json "objectives".

const VENDOR_DIR := "res://content/core/vendors"

static var _vendors: Array = []


static func cfg() -> Dictionary:
	return Story.data().get("objectives", {})


static func line(key: String) -> String:
	return str(cfg().get(key, ""))


static func home() -> bool:
	return GameFlow.current_planet_id() == PlanetGen.home_id()


## Most urgent first, for when the player has not picked one in the Ledger.
const AUTO := ["bounty", "smuggle", "supply", "story"]


## { text, target, key } for the pointer, or {} when there is nothing to point at.
## Issue #201: an optional quest whose waypoint the player switched on comes first,
## and before it a waypoint set on the F11 map (GlobeMap; only one is ever on).
## Then the job the player made the waypoint in the Ledger (pin), then the most
## urgent (AUTO). `key` names the job log entry it is ("map" for the F11 map's).
static func current() -> Dictionary:
	var mark := GlobeMap.waypoint()
	if not mark.is_empty():
		mark["key"] = "map"
		return mark
	var quest := Quests.waypoint()
	if not quest.is_empty():
		return quest
	if WorldState.objective_pin != "":
		var mine := of(WorldState.objective_pin)
		if not mine.is_empty():
			return mine
		WorldState.objective_pin = ""     # done or gone: back to the most urgent
	for k in AUTO:
		var o := of(k)
		if not o.is_empty():
			return o
	return {}


## One job's { text, target, key }, or {} when it is not on (here): "bounty",
## "smuggle", "supply", "story" or "job:<board id>" (a board job with a "target").
static func of(key: String) -> Dictionary:
	var o := {}
	match key:
		"bounty":
			o = _bounty()
		"smuggle":
			o = _smuggle()
		"supply":
			var to := Territory.supply_out()
			if to != "" and home():
				o = { "text": Territory.line("objective") % Story.outpost_label(to), "target": "outpost:" + to }
		"story":
			o = chapter_objective() if home() else {}
		_:
			if key.begins_with("job:"):
				o = _job(key.substr(4))
	if not o.is_empty():
		o["key"] = key
	return o


## Whether the Ledger can make `key` the waypoint: it is on, and somewhere here.
static func can_pin(key: String) -> bool:
	return str(of(key).get("target", "")) != ""


## Make job `key` the waypoint (the F11 map's and any quest's go: one pointer at a
## time), or, when it already is, hand the pointer back to the most urgent.
static func pin(key: String) -> bool:
	if WorldState.objective_pin == key and GlobeMap.waypoint().is_empty() and Quests.waypoint().is_empty():
		WorldState.objective_pin = ""
		return false
	if not can_pin(key):
		return false
	WorldState.objective_pin = key
	GlobeMap.clear_waypoint()
	for k in WorldState.quests:
		WorldState.quests[k].waypoint = false
	return true


## The key of the entry the pointer is on now ("" = nothing).
static func current_key() -> String:
	return str(current().get("key", ""))


static func _bounty() -> Dictionary:
	var b := WorldState.bounty
	if WorldState.bounty_collectable() and home():
		var fence := fence_marker(true)
		return { "text": line("collect") % str(b.name), "target": "marker:" + fence if fence != "" else "" }
	if not WorldState.bounty_target().is_empty():
		var where := Story.outpost_label(str(b.outpost))
		if not home():
			return { "text": line("hunt_away") % [str(b.name), where], "target": "" }
		return { "text": line("hunt") % [str(b.name), where], "target": "outpost:" + str(b.outpost) }
	return {}


static func _smuggle() -> Dictionary:
	if WorldState.carrying_contraband():
		if for_general():
			return { "text": line("general_bring"), "target": "npc:general" }
		var fence := fence_marker()
		return { "text": line("sell"), "target": "marker:" + fence if fence != "" else "" }
	var drop := WorldState.smuggle_drop()
	if not drop.is_empty() and str(drop.location) == WorldState.current_town_id():
		var hint := str(WorldState.smuggle.get("hint", ""))
		return { "text": run_line("drop") % hint, "target": "drop:" + str(drop.marker) }
	return {}


## A board job taken and not done that names a place ("target"; home planet only).
static func _job(id: String) -> Dictionary:
	if str(WorldState.jobs_taken.get(id, "")) != "active" or not home():
		return {}
	var j := WorldState.job(id)
	var target := str(j.get("target", ""))
	if target == "":
		return {}
	return { "text": str(j.get("objective", j.get("title", id))), "target": target }


## What the story's chapter wants: its own objective once its teller has told
## it, before that "go and talk to them" (the first chapter points at Oda
## from the start: T-89 only says where she is).
## Issue #303: on the dark master's oath, clearing the barracks comes before Oda.
static func chapter_objective() -> Dictionary:
	var c := Story.chapter_cfg()
	if c.is_empty():
		return {}
	var mine: Dictionary = cfg().get("chapters", {}).get(str(c.id), {})
	if str(c.id) == "debrief" and DarkPact.joined() and DarkPact.oath_open():
		mine = cfg().get("chapters", {}).get(DarkPact.QUEST, mine)
		return { "text": DarkPact.fill(str(mine.get("text", ""))), "target": str(mine.get("target", "")) }
	var told := bool(WorldState.story.get("told", false)) or str(c.get("teller", "")) != "cantina_owner"
	var step := Story.current_step(c) if told else {}
	if not step.is_empty():
		return { "text": Story.fill_step(str(step.get("text", ""))), "target": str(step.get("target", "")) }
	var o: Dictionary = mine if told and not mine.is_empty() else cfg().get("teller", {})
	return { "text": str(o.get("text", "")), "target": str(o.get("target", "")) } if str(o.get("text", "")) != "" else {}


## Issue #251: the run on is the general's and he is there to take its goods
## (dead or away, the fence still buys them).
static func for_general() -> bool:
	return WorldState.smuggle_to() == "general" and home() and GeneralPost.station() != ""


## A smuggling-run line, in the general's words ("general_<key>") while his run is on.
static func run_line(key: String) -> String:
	return line("general_" + key) if WorldState.smuggle_to() == "general" and cfg().has("general_" + key) else line(key)


## The marker of the stall that buys contraband in this town (or, with
## `bounties`, the one that pays bounties), or "".
static func fence_marker(bounties: bool = false) -> String:
	var here := WorldState.current_town_id()
	for v in vendors():
		if str(v.get("location", "")) != here or not "contraband" in v.get("buys", []):
			continue
		if bounties and not bool(v.get("bounties", false)):
			continue
		return str(v.get("marker", ""))
	return ""


static func vendors() -> Array:
	if _vendors.is_empty():
		var da := DirAccess.open(VENDOR_DIR)
		if da != null:
			for f in da.get_files():
				if f.ends_with(".json"):
					var fa := FileAccess.open(VENDOR_DIR + "/" + f, FileAccess.READ)
					var d = JSON.parse_string(fa.get_as_text()) if fa != null else null
					if d is Dictionary:
						_vendors.append(d)
	return _vendors


# ------------------------------------------------------------------ the job log

## The job log, one entry per thing on: [{ title, text, key }], the story first.
## `key` is what of() and pin() take ("" = nothing to point at). Always at least
## one entry (log_none when nothing is on). Your ships and gear upgrades are not
## jobs: the Ledger lists them with what you carry.
static func log_entries() -> Array:
	var out: Array = []
	if home():
		var c := Story.chapter_cfg()
		var say := str(c.get("remind", ""))
		if str(c.get("id", "")) == "debrief" and DarkPact.joined() and DarkPact.oath_open():
			say = str(chapter_objective().get("text", ""))
		if say == "":
			say = str(chapter_objective().get("text", ""))
		var title := line("log_story")
		if str(c.get("title", "")) != "":
			title += ": " + str(c.title).to_upper()
		if not Story.steps(c).is_empty() and bool(WorldState.story.get("told", false)):
			say = step_list(c)
		if say != "":
			out.append({ "title": title, "text": say, "key": "story" })
	var drop := WorldState.smuggle_drop()
	if WorldState.carrying_contraband():
		out.append({ "title": run_line("log_smuggle"), "text": line("general_log_carry") if for_general() else line("log_carry"), "key": "smuggle" })
	elif not drop.is_empty():
		out.append({ "title": run_line("log_smuggle"), "key": "smuggle",
			"text": run_line("log_drop") % [WorldState.smuggle_goods_text(), str(WorldState.smuggle.get("hint", ""))] })
	var b := WorldState.bounty
	if not WorldState.bounty_target().is_empty():
		out.append({ "title": line("log_bounty"), "key": "bounty",
			"text": line("log_hunt") % [str(b.name), Story.outpost_label(str(b.outpost)), int(b.pay), str(b.crime)] })
	elif WorldState.bounty_collectable():
		out.append({ "title": line("log_bounty"), "text": line("log_collect") % [str(b.name), int(b.pay)], "key": "bounty" })
	for id in WorldState.jobs_taken:
		if WorldState.jobs_taken[id] == "active":
			var j := WorldState.job(str(id))
			var kind := str(j.get("kind", ""))
			out.append({ "title": str(j.get("title", id)).to_upper(), "text": str(j.get("text", "")),
				"key": kind if kind in ["smuggle", "bounty", "supply"] else "job:" + str(id) })
	if out.is_empty():
		out.append({ "title": "", "text": line("log_none"), "key": "" })
	return out


## A chapter's steps, one a line, the done ones ticked.
static func step_list(c: Dictionary) -> String:
	var rows: Array = []
	for s in Story.steps(c):
		rows.append(line("step_done" if Story.step_done(c, s) else "step_open") + Story.fill_step(str(s.get("text", ""))))
	return "\n".join(rows)


## "Runs sold: 3    Bounties paid: 1"
static func tally() -> String:
	return line("log_tally") % [WorldState.count("smuggle_sold"), WorldState.count("bounties_paid")]
