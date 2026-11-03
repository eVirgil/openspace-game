class_name Territory
extends RefCounted
## Who holds each place (issue #187): the Remnant or the locals. Pure and static,
## like Story; its state lives in WorldState.control (saved with the world):
##   { <outpost id>: { owner: "locals", hold: seconds left }, supply: <outpost id> }
## An outpost with no entry is the Remnant's.
##
##   an outpost    the Remnant's until every trooper there is dead (take), then the
##                 locals' for hold_s of play. A supply run from Oda (j_supply)
##                 fills that up again (taken once, you are their supplier: the
##                 map shows who is short and any of them takes supplies, with
##                 no job to take again); when it runs out, or the locals' guards
##                 there are all dead, the Remnant take it back (retake).
##   the barracks  the Remnant's until the story is done (the fleet beaten) or the
##                 Remnant are driven off (every outpost held at once); then
##                 the locals'. Story.town_garrison() reads it. Issue #303: when
##                 every local guard on its posts is dead, the Remnant take it
##                 back (town_retaken), hostile or (on the dark master's oath) not.
##                 Driving them off every outpost again gives it back to the locals.
##                 Once the fleet is beaten, a dead Remnant trooper at the
##                 barracks stays dead (control.remnant_dead); the last one hands
##                 the town to the locals (free_town). Driven off, the Remnant come
##                 back only this way: kill every local guard at the barracks.
##                 The town scene swaps the people over once you are out of sight.
##
## What it changes: who stands at each place (RemnantOutposts, the town scene and
## DroidController ask owner()), the gate checkpoint (gate_strict, bribe_mult),
## the fence's prices (fence_mult), Oda's supply job and a resupply quest per
## outpost (quests), rumors (the flags below), the objective pointer, the F1
## screen (summary) and the F11 map (GlobeMap).
##
## Numbers and lines: content/core/story/territory.json.

const PATH := "res://content/core/story/territory.json"
const BARRACKS := "barracks"
const REMNANT := "remnant"
const LOCALS := "locals"
const DRIVEN_OFF := "remnant_driven_off"
const RETAKEN := "town_retaken"
const SUPPLY_JOB := "j_supply"
const SUPPLIER := "supply_job_taken"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


static func n(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func line(key: String) -> String:
	return str(cfg().get("lines", {}).get(key, ""))


static func places() -> Array:
	return Story.OUTPOSTS + [BARRACKS]


## "remnant" or "locals".
static func owner(id: String) -> String:
	if id == BARRACKS:
		if WorldState.has_flag(DRIVEN_OFF):
			return LOCALS
		return LOCALS if Story.remnant_gone() and not WorldState.has_flag(RETAKEN) else REMNANT
	if WorldState.has_flag(DRIVEN_OFF):
		return LOCALS
	var c = WorldState.control.get(id, {})
	return str(c.get("owner", REMNANT)) if c is Dictionary else REMNANT


static func held() -> Array:
	return Story.OUTPOSTS.filter(func(id): return owner(str(id)) == LOCALS)


## Outposts the Remnant have lost.
static func lost() -> int:
	return held().size()


static func hold_left(id: String) -> float:
	var c = WorldState.control.get(id, {})
	return float(c.get("hold", 0.0)) if c is Dictionary else 0.0


## The locals there are running short (a supply run would help).
static func short(id: String) -> bool:
	return owner(id) == LOCALS and not WorldState.has_flag(DRIVEN_OFF) and hold_left(id) <= n("supply_warn_s", 420.0)


# ------------------------------------------------------------------ changes

## Every trooper at the outpost is dead: the locals have it.
static func take(id: String) -> void:
	if not Story.OUTPOSTS.has(id) or owner(id) == LOCALS:
		return
	WorldState.control[id] = { "owner": LOCALS, "hold": n("hold_s", 900.0) }
	WorldState.bump("outposts_taken")
	WorldState.change_standing("locals", int(cfg().get("standing", {}).get("outpost_taken", 6)), "The locals took an outpost.")
	WorldState.log_event(line("taken") % Story.outpost_label(id))
	if lost() == Story.OUTPOSTS.size():
		_drive_off()
	_sync_flags()


## Every outpost is the locals': the Remnant are driven off the planet.
static func _drive_off() -> void:
	WorldState.set_flag(DRIVEN_OFF)
	WorldState.set_flag(RETAKEN, false)
	WorldState.control.erase("remnant_dead")
	_cancel_supply()
	WorldState.log_event(line("driven_off"))
	for o in Story.OUTPOSTS:
		Quests.complete(quest_id(str(o)))     # nothing left to run short


## The Remnant have it again.
static func retake(id: String) -> void:
	if owner(id) != LOCALS or WorldState.has_flag(DRIVEN_OFF):
		return
	WorldState.control.erase(id)
	if supply_out() == id:
		_cancel_supply()
	WorldState.bump("outposts_retaken")
	WorldState.set_flag("outpost_retaken")
	WorldState.log_event(line("retaken") % Story.outpost_label(id))
	Quests.fail(quest_id(id))
	_sync_flags()


## The locals' guards at an outpost are all dead: the Remnant take it on the next tick.
static func guards_lost(id: String) -> void:
	if owner(id) == LOCALS and WorldState.control.get(id) is Dictionary:
		WorldState.control[id].hold = 0.0


## Seconds of play (WorldState.tick). The locals' hold on each outpost runs down.
static func tick(dt: float) -> void:
	if WorldState.has_flag(DRIVEN_OFF):
		return
	# All seven already held with the barracks back too (the town retaken, then
	# freed): no outpost is left to take, so the drive-off happens here.
	if lost() == Story.OUTPOSTS.size() and not WorldState.has_flag(RETAKEN):
		_drive_off()
		_sync_flags()
		return
	var warn := n("supply_warn_s", 420.0)
	for id in held():
		var c: Dictionary = WorldState.control[id]
		var was := float(c.hold)
		c.hold = was - dt
		if was > warn and float(c.hold) <= warn:
			WorldState.log_event(line("warn") % Story.outpost_label(str(id)))
			Quests.offer_again(quest_id(str(id)))
		if float(c.hold) <= 0.0:
			retake(str(id))
	_sync_flags()


## Flags the rumors and the board read.
static func _sync_flags() -> void:
	WorldState.set_flag("locals_hold_outpost", lost() > 0)
	WorldState.set_flag("outpost_short", Story.OUTPOSTS.any(func(id): return short(str(id))))


# ------------------------------------------------------------------ the barracks change hands (issue #303)

## The barracks posts the locals put a guard on (territory.json "barracks").
static func barracks_posts() -> Array:
	var posts: Dictionary = cfg().get(BARRACKS, {}).get("posts", {})
	return posts.keys().filter(func(k): return str(posts[k]) != "")


## Posts whose local guard is dead (they do not come back).
static func barracks_dead() -> Array:
	var d = WorldState.control.get("barracks_dead", [])
	return d if d is Array else []


## A local guard on a barracks post died. The last one hands the town to the Remnant.
static func barracks_guard_died(post: String) -> void:
	if owner(BARRACKS) != LOCALS or not barracks_posts().has(post):
		return
	var dead := barracks_dead()
	if not dead.has(post):
		dead.append(post)
	WorldState.control["barracks_dead"] = dead
	if barracks_posts().all(func(p): return dead.has(p)):
		retake_town()


## The Remnant hold the town's barracks again. Driven off, this is how they come
## back: the outposts the locals hold start running down again from a full hold.
static func retake_town() -> void:
	if owner(BARRACKS) != LOCALS:
		return
	if WorldState.has_flag(DRIVEN_OFF):
		WorldState.set_flag(DRIVEN_OFF, false)
		for id in held():
			WorldState.control[id].hold = n("hold_s", 900.0)
	WorldState.set_flag(RETAKEN)
	WorldState.control.erase("barracks_dead")
	WorldState.control.erase("remnant_dead")
	WorldState.change_standing("locals", int(cfg().get("standing", {}).get("town_retaken", -20)), line("town_retaken"))
	DarkPact.on_town_retaken()
	_sync_flags()
	WorldState.checkpoint("town_retaken")


## Remnant trooper posts at the barracks whose trooper is dead. Once the fleet is
## beaten they do not come back: the last one hands the town to the locals.
static func remnant_dead() -> Array:
	var d = WorldState.control.get("remnant_dead", [])
	return d if d is Array else []


## A Remnant trooper on barracks post `post` died; `posts` are all the town's
## trooper posts. Before the fleet is beaten they respawn and nothing changes.
static func remnant_guard_died(post: String, posts: Array) -> void:
	if not Story.remnant_gone() or owner(BARRACKS) != REMNANT or not posts.has(post):
		return
	var dead := remnant_dead()
	if not dead.has(post):
		dead.append(post)
	WorldState.control["remnant_dead"] = dead
	if posts.all(func(p): return dead.has(p)):
		free_town()


## The locals hold the town's barracks again (every Remnant trooper there dead).
static func free_town() -> void:
	if not WorldState.has_flag(RETAKEN) or WorldState.has_flag(DRIVEN_OFF):
		return
	WorldState.set_flag(RETAKEN, false)
	WorldState.control.erase("remnant_dead")
	WorldState.control.erase("barracks_dead")
	WorldState.change_standing("locals", int(cfg().get("standing", {}).get("town_freed", 10)), line("town_freed"))
	WorldState.checkpoint("town_freed")


## The Remnant hold the whole planet: the town's barracks, and not one outpost lost.
static func remnant_planet() -> bool:
	return owner(BARRACKS) == REMNANT and lost() == 0


# ------------------------------------------------------------------ supply runs (Oda's j_supply)

## You have taken Oda's supply run at least once. Until then the F11 map does not
## show which outposts are short; after it, it does, and any of them takes your
## supplies when you get there (can_deliver), with no job to take again.
static func supplier() -> bool:
	return WorldState.has_flag(SUPPLIER) or WorldState.count("supplies_delivered") > 0 or supply_out() != ""


## Do the maps (F11, the cruiser's hologram) mark outpost `id` as short? Only
## once you are the supplier.
static func short_shown(id: String) -> bool:
	return id != BARRACKS and supplier() and short(id)


## Would walking up to outpost `id` hand over supplies? Where the job sends you,
## or, once you are the locals' supplier, any outpost of theirs running short.
static func can_deliver(id: String) -> bool:
	return owner(id) == LOCALS and (supply_out() == id or (supplier() and short(id)))


## The outpost a supply run would go to: the one whose resupply quest you are
## pointed at, else the one shortest on time, or "".
static func supply_target() -> String:
	var best := ""
	for id in Story.OUTPOSTS:
		if short(str(id)) and bool(WorldState.quests.get(quest_id(str(id)), {}).get("waypoint", false)):
			return str(id)
	for id in Story.OUTPOSTS:
		if short(str(id)) and (best == "" or hold_left(str(id)) < hold_left(best)):
			best = str(id)
	return best


## Where the supplies you carry are going, or "".
static func supply_out() -> String:
	return str(WorldState.control.get("supply", ""))


static func start_supply() -> bool:
	var to := supply_target()
	if to == "" or supply_out() != "":
		return false
	WorldState.control["supply"] = to
	WorldState.jobs_taken[SUPPLY_JOB] = "active"
	WorldState.set_flag(SUPPLIER)
	WorldState.log_event("Took the job: supplies for %s." % Story.outpost_label(to))
	return true


## The player brought the supplies to outpost `id`. Returns the pay (0 = not theirs).
static func deliver(id: String) -> int:
	if not can_deliver(id):
		return 0
	WorldState.control[id].hold = n("hold_s", 900.0)
	if supply_out() == id:
		_cancel_supply()
	var pay := int(cfg().get("supply_pay", 120))
	WorldState.credits += pay
	WorldState.bump("supplies_delivered")
	WorldState.change_standing("locals", int(cfg().get("standing", {}).get("supplied", 3)), "Supplies reached the locals.")
	WorldState.log_event(line("supplied") % [Story.outpost_label(id), pay])
	QuestNews.push("supplies_delivered", "+%d cr" % pay)
	Quests.complete(quest_id(id))
	_sync_flags()
	return pay


## The resupply quest for outpost `id`.
static func quest_id(id: String) -> String:
	return "resupply_" + id


## One optional resupply quest per outpost, in Quests' shape (territory.json "quest").
static func quests() -> Array:
	var q: Dictionary = cfg().get("quest", {})
	var out: Array = []
	for id in Story.OUTPOSTS:
		var label := Story.outpost_label(str(id))
		out.append({ "id": quest_id(str(id)), "title": str(q.get("title", "%s")) % label,
			"text": str(q.get("text_supplier" if supplier() else "text", "%s")) % label, "target": "outpost:" + str(id) })
	return out


## Fraction of a full hold the locals have left at outpost `id` (0..1), or -1
## when there is no clock (not theirs, or the Remnant are gone).
static func hold_frac(id: String) -> float:
	if owner(id) != LOCALS or WorldState.has_flag(DRIVEN_OFF) or not Story.OUTPOSTS.has(id):
		return -1.0
	return clampf(hold_left(id) / n("hold_s", 900.0), 0.0, 1.0)


## The job is open again (done, or its outpost is gone).
static func _cancel_supply() -> void:
	WorldState.control.erase("supply")
	WorldState.jobs_taken.erase(SUPPLY_JOB)


# ------------------------------------------------------------------ what it changes

## The soldier profile the locals put on a post ("outposts" or "barracks"), or "".
static func locals_post(where: String, post: String) -> String:
	return str(cfg().get(where, {}).get("posts", {}).get(post, ""))


## Bands stricter at the Remnant's gate (0 or 1).
static func gate_strict() -> int:
	return 1 if lost() >= int(cfg().get("gate", {}).get("strict_from", 2)) else 0


static func bribe_mult() -> float:
	return 1.0 + lost() * float(cfg().get("gate", {}).get("bribe_per_lost", 0.5))


## The fence pays more for contraband with every outpost the locals hold.
static func fence_mult() -> float:
	return 1.0 + lost() * n("fence_per_held", 0.15)


## For the F1 screen: one line per place, "Dry wash outpost   LOCALS 12:30".
static func summary() -> Array:
	var labels: Dictionary = cfg().get("labels", {})
	var out: Array = []
	for id in places():
		var label := "Barracks" if id == BARRACKS else Story.outpost_label(str(id)).trim_prefix("the ")
		var who := owner(str(id))
		var tag := str(labels.get(who, who.to_upper()))
		if id != BARRACKS and who == LOCALS and not WorldState.has_flag(DRIVEN_OFF):
			var left := maxf(0.0, hold_left(str(id)))
			tag = "%s %d:%02d" % [str(labels.get("short", tag)) if short(str(id)) else tag, int(left) / 60, int(left) % 60]
		out.append("%-19s %s" % [label.capitalize().left(19), tag])
	return out
