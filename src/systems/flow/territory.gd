class_name Territory
extends RefCounted
## Who holds each place (issue #187): the Remnant or the locals. Pure and static,
## like Story; its state lives in WorldState.control (saved with the world):
##   { <outpost id>: { owner: "locals", hold: seconds left }, supply: <outpost id> }
## An outpost with no entry is the Remnant's (for ever, until you clear it).
## Issue #425: once the cruiser has fallen (Story.cruiser_taken) the Remnant on
## the ground are cut off, and every outpost of theirs gets an entry too:
## { owner: "remnant", hold: seconds left }, staggered so they run short one at a
## time. When one runs out the locals move in on their own (give_up). A player
## the Remnant still deal with (remnant_friend) is offered a resupply quest for
## each one that runs short (resupply_remnant_<id>); walking up to it with that
## quest's waypoint on fills its clock back up (deliver_remnant).
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
## Other fronts (territory.json "fronts": the moon, the lava moon), each with its own outposts, its own
## barracks under a dome and its own drive-off flag, on the same rules as the
## port's: kill every trooper at a moon outpost and the locals move in (no hold
## clock there and no supply runs: they keep it until their guards there are all
## dead); hold all of them at once and the Remnant are driven off the moon, and the
## locals take its barracks. The moon's barracks also go to the locals when the
## fleet is beaten, the Remnant take them back when the locals' guards there are
## all dead, and once the fleet is beaten killing every trooper there frees them.
## Once the cruiser has fallen the moon's Remnant outposts run short and give up
## one at a time too (no resupply quests there). Every function that takes a
## `front` ("home" or a "fronts" key such as "moon") defaults to the port's; one that takes a place id
## works out its front from the id (front_of).
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
const HOME := "home"

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
	var out: Array = Story.OUTPOSTS + [BARRACKS]
	for f in fronts():
		out += outposts(f) + [barracks_of(f)]
	return out


# ------------------------------------------------------------------ fronts

## A front's block: { outposts, barracks, driven_off, retaken, dead, remnant_dead,
## clock (locals hold on a clock), lines, posts (the barracks') }.
static func front(f: String) -> Dictionary:
	var got = cfg().get("fronts", {}).get(f, {})
	var m: Dictionary = got if got is Dictionary else {}
	if f != HOME and not m.is_empty():
		return { "outposts": m.get("outposts", []), "barracks": str(m.get("barracks_id", f + "_barracks")),
			"driven_off": f + "_remnant_driven_off", "retaken": f + "_town_retaken",
			"dead": f + "_barracks_dead", "remnant_dead": f + "_remnant_dead", "clock": false,
			"lines": m.get("lines", {}), "posts": m.get(BARRACKS, {}).get("posts", {}), "planet": str(m.get("planet", "")),
			"label": str(m.get("barracks_label", "Barracks")) }
	return { "outposts": Story.OUTPOSTS, "barracks": BARRACKS, "driven_off": DRIVEN_OFF, "retaken": RETAKEN,
		"dead": "barracks_dead", "remnant_dead": "remnant_dead", "clock": true, "lines": cfg().get("lines", {}),
		"posts": cfg().get(BARRACKS, {}).get("posts", {}), "planet": "", "label": "Barracks" }


## The fronts past the port's (territory.json "fronts" keys: "moon", "lava_moon").
static func fronts() -> Array:
	var all: Dictionary = cfg().get("fronts", {})
	return all.keys().filter(func(k): return all[k] is Dictionary)


static func outposts(f: String = HOME) -> Array:
	return front(f).outposts


static func barracks_of(f: String = HOME) -> String:
	return str(front(f).barracks)


## The front place `id` (an outpost or a barracks) belongs to.
static func front_of(id: String) -> String:
	for f in fronts():
		var fc := front(f)
		if (fc.outposts as Array).has(id) or id == str(fc.barracks):
			return f
	return HOME


## The front of planet `planet_id` (the moon's planet is the moon's; any other the port's).
static func front_for_planet(planet_id: String) -> String:
	for f in fronts():
		if planet_id != "" and str(front(f).planet) == planet_id:
			return f
	return HOME


## The front of the planet you are on.
static func here() -> String:
	return front_for_planet(GameFlow.current_planet_id())


## The barracks of the planet you are on.
static func barracks_here() -> String:
	return barracks_of(here())


## A front's line (the moon's own, else the port's).
static func fline(f: String, key: String) -> String:
	var l = front(f).lines.get(key, null)
	return str(l) if l != null else line(key)


static func driven_off(f: String = HOME) -> bool:
	return WorldState.has_flag(str(front(f).driven_off))


## "remnant" or "locals".
static func owner(id: String) -> String:
	var fc := front(front_of(id))
	if id == str(fc.barracks):
		if WorldState.has_flag(fc.driven_off):
			return LOCALS
		return LOCALS if Story.remnant_gone() and not WorldState.has_flag(fc.retaken) else REMNANT
	if WorldState.has_flag(fc.driven_off):
		return LOCALS
	var c = WorldState.control.get(id, {})
	return str(c.get("owner", REMNANT)) if c is Dictionary else REMNANT


static func held(f: String = HOME) -> Array:
	return outposts(f).filter(func(id): return owner(str(id)) == LOCALS)


## Outposts the Remnant have lost.
static func lost(f: String = HOME) -> int:
	return held(f).size()


static func hold_left(id: String) -> float:
	var c = WorldState.control.get(id, {})
	return float(c.get("hold", 0.0)) if c is Dictionary else 0.0


## The locals there are running short (a supply run would help).
static func short(id: String) -> bool:
	return front_of(id) == HOME and owner(id) == LOCALS and not WorldState.has_flag(DRIVEN_OFF) and hold_left(id) <= n("supply_warn_s", 420.0)


## Issue #425: a number from territory.json "remnant" (the Remnant's clocks).
static func rn(key: String, fallback: float) -> float:
	return float(cfg().get(REMNANT, {}).get(key, fallback))


## The cruiser has fallen and the Remnant still hold some of the desert: their
## outposts run down.
static func remnant_cut_off(f: String = HOME) -> bool:
	return Story.cruiser_taken() and not driven_off(f)


## The Remnant's outposts on a clock (only once they are cut off).
static func remnant_clocked(f: String = HOME) -> Array:
	return outposts(f).filter(func(id): return owner(str(id)) == REMNANT and WorldState.control.get(id) is Dictionary)


## The Remnant at outpost `id` are running short.
static func remnant_short(id: String) -> bool:
	var f := front_of(id)
	return remnant_cut_off(f) and remnant_clocked(f).has(id) and hold_left(id) <= rn("warn_s", 2400.0)


## The ranch villages' outposts (their location's "after_cruiser"): the Remnant
## there answer to the cruiser, so killing them all hands nothing over until it
## has fallen (Story.cruiser_taken); they come back like any outpost's. The same
## rule as the barracks: the cruiser first, then its guards.
static func locked(id: String) -> bool:
	return not Story.cruiser_taken() and after_cruiser(id)


static var _after_cruiser := {}

static func after_cruiser(id: String) -> bool:
	if not _after_cruiser.has(id):
		var f := FileAccess.open("res://content/core/locations/%s.json" % id, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_after_cruiser[id] = d is Dictionary and bool(d.get("after_cruiser", false))
	return bool(_after_cruiser[id])


## The Remnant still give you work (the general's band: not hostile).
static func remnant_friend() -> bool:
	return int(WorldState.standing.get("imperial_remnant", 0)) >= int(rn("friend_from", -39.0))


# ------------------------------------------------------------------ changes

## Every trooper at the outpost is dead: the locals have it. `quiet` (issue #425):
## the Remnant there ran out of supplies and gave up (give_up), so nobody took
## it: no standing and no outposts_taken count.
static func take(id: String, quiet := false) -> void:
	var f := front_of(id)
	if not outposts(f).has(id) or owner(id) == LOCALS:
		return
	WorldState.control[id] = { "owner": LOCALS, "hold": n("hold_s", 900.0) }
	if f == HOME:
		Quests.fail(remnant_quest_id(id))     # it fell before a load got there
	if quiet:
		WorldState.log_event(fline(f, "remnant_gave_up") % Story.outpost_label(id))
	else:
		WorldState.bump("outposts_taken")
		WorldState.change_standing("locals", int(cfg().get("standing", {}).get("outpost_taken", 6)), "The locals took an outpost.")
		WorldState.log_event(fline(f, "taken") % Story.outpost_label(id))
	if lost(f) == outposts(f).size():
		_drive_off(f)
	_sync_flags()


## Every outpost of a front is the locals': the Remnant are driven off the planet.
static func _drive_off(f: String = HOME) -> void:
	var fc := front(f)
	WorldState.set_flag(str(fc.driven_off))
	WorldState.set_flag(str(fc.retaken), false)
	WorldState.control.erase(str(fc.remnant_dead))
	WorldState.log_event(fline(f, "driven_off"))
	if f != HOME:
		return
	_cancel_supply()
	for o in Story.OUTPOSTS:
		Quests.complete(quest_id(str(o)))     # nothing left to run short


## The Remnant have it again.
static func retake(id: String) -> void:
	var f := front_of(id)
	if owner(id) != LOCALS or driven_off(f):
		return
	WorldState.control.erase(id)
	if remnant_cut_off(f):                    # issue #425: cut off, they cannot hold it for ever
		WorldState.control[id] = { "owner": REMNANT, "hold": rn("hold_s", 6000.0) }
	if supply_out() == id:
		_cancel_supply()
	WorldState.bump("outposts_retaken")
	WorldState.set_flag("outpost_retaken")
	WorldState.log_event(fline(f, "retaken") % Story.outpost_label(id))
	if f == HOME:
		Quests.fail(quest_id(id))
	_sync_flags()


## The locals' guards at an outpost are all dead: the Remnant take it on the next
## tick (the moon's, with no clock, at once).
static func guards_lost(id: String) -> void:
	if owner(id) != LOCALS or not WorldState.control.get(id) is Dictionary:
		return
	if bool(front(front_of(id)).clock):
		WorldState.control[id].hold = 0.0
	else:
		retake(id)


## Seconds of play (WorldState.tick). The locals' hold on each outpost runs down.
static func tick(dt: float) -> void:
	for f in fronts():
		_tick_front(f, dt)
	if WorldState.has_flag(DRIVEN_OFF):
		return
	# Every outpost already held with the barracks back too (the town retaken, then
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
	if remnant_cut_off():
		_tick_remnant(dt)
	_sync_flags()


## A front past the port's: no locals' clock; held all at once (the barracks back too)
## drives the Remnant off it; once the cruiser has fallen their outposts run down.
static func _tick_front(f: String, dt: float) -> void:
	if outposts(f).is_empty() or driven_off(f):
		return
	if lost(f) == outposts(f).size() and not WorldState.has_flag(str(front(f).retaken)):
		_drive_off(f)
		return
	if remnant_cut_off(f):
		_start_remnant_clocks(f)
		for id in remnant_clocked(f):
			var c: Dictionary = WorldState.control[id]
			var was := float(c.hold)
			c.hold = was - dt
			if was > rn("warn_s", 2400.0) and float(c.hold) <= rn("warn_s", 2400.0):
				WorldState.log_event(fline(f, "remnant_warn") % Story.outpost_label(str(id)))
			if float(c.hold) <= 0.0:
				give_up(str(id))
				if driven_off(f):
					return


## Issue #425: the Remnant at outpost `id` have run out: the locals move in.
static func give_up(id: String) -> void:
	take(id, true)


## The Remnant's clocks run down once the cruiser has fallen. A friend of theirs
## is offered a resupply quest for each one running short (and loses it on
## turning hostile); one that runs out goes to the locals.
static func _tick_remnant(dt: float) -> void:
	_start_remnant_clocks()
	var warn := rn("warn_s", 2400.0)
	var friend := remnant_friend()
	for id in remnant_clocked():
		var c: Dictionary = WorldState.control[id]
		var was := float(c.hold)
		c.hold = was - dt
		if was > warn and float(c.hold) <= warn:
			WorldState.log_event(line("remnant_warn") % Story.outpost_label(str(id)))
		var q := remnant_quest_id(str(id))
		if friend and remnant_short(str(id)) and Quests.state(q) != "open":
			Quests.offer_again(q)
		elif not friend:
			Quests.fail(q)
		if float(c.hold) <= 0.0:
			give_up(str(id))
			if WorldState.has_flag(DRIVEN_OFF):
				return


## Every Remnant outpost with no clock yet gets one (the tick after the cruiser
## falls, or the first after loading a save from before this): the first in
## Story.OUTPOSTS a full hold, each one after it stagger_s less.
static func _start_remnant_clocks(f: String = HOME) -> void:
	var i := 0
	for id in outposts(f):
		if owner(str(id)) != REMNANT or WorldState.control.get(id) is Dictionary:
			continue
		WorldState.control[id] = { "owner": REMNANT, "hold": maxf(1.0, rn("hold_s", 6000.0) - i * rn("stagger_s", 540.0)) }
		i += 1


## Flags the rumors and the board read.
static func _sync_flags() -> void:
	WorldState.set_flag("locals_hold_outpost", lost() > 0)
	WorldState.set_flag("outpost_short", Story.OUTPOSTS.any(func(id): return short(str(id))))
	WorldState.set_flag("remnant_outpost_short", Story.OUTPOSTS.any(func(id): return remnant_short(str(id))))


# ------------------------------------------------------------------ the barracks change hands (issue #303)

## The barracks posts the locals put a guard on (territory.json "barracks", the
## moon's "moon" "barracks").
static func barracks_posts(f: String = HOME) -> Array:
	var posts: Dictionary = front(f).posts
	return posts.keys().filter(func(k): return str(posts[k]) != "")


## The soldier profile the locals put on barracks post `post` of front `f`, or "".
static func barracks_local(post: String, f: String = HOME) -> String:
	return str(front(f).posts.get(post, ""))


## Posts whose local guard is dead (they do not come back).
static func barracks_dead(f: String = HOME) -> Array:
	var d = WorldState.control.get(str(front(f).dead), [])
	return d if d is Array else []


## A local guard on a barracks post died. The last one hands the town to the Remnant.
static func barracks_guard_died(post: String, f: String = HOME) -> void:
	if owner(barracks_of(f)) != LOCALS or not barracks_posts(f).has(post):
		return
	var dead := barracks_dead(f)
	if not dead.has(post):
		dead.append(post)
	WorldState.control[str(front(f).dead)] = dead
	if barracks_posts(f).all(func(p): return dead.has(p)):
		retake_town(f)


## The Remnant hold the town's barracks again. Driven off, this is how they come
## back: the outposts the locals hold start running down again from a full hold.
static func retake_town(f: String = HOME) -> void:
	var fc := front(f)
	if owner(str(fc.barracks)) != LOCALS:
		return
	if WorldState.has_flag(fc.driven_off):
		WorldState.set_flag(str(fc.driven_off), false)
		for id in held(f):
			WorldState.control[id].hold = n("hold_s", 900.0)
	WorldState.set_flag(str(fc.retaken))
	WorldState.control.erase(str(fc.dead))
	WorldState.control.erase(str(fc.remnant_dead))
	WorldState.change_standing("locals", int(cfg().get("standing", {}).get("town_retaken", -20)), fline(f, "town_retaken"))
	if f == HOME:
		DarkPact.on_town_retaken()
	_sync_flags()
	WorldState.checkpoint("town_retaken" if f == HOME else f + "_town_retaken")


## Remnant trooper posts at the barracks whose trooper is dead. Once the fleet is
## beaten they do not come back: the last one hands the town to the locals.
static func remnant_dead(f: String = HOME) -> Array:
	var d = WorldState.control.get(str(front(f).remnant_dead), [])
	return d if d is Array else []


## A Remnant trooper on barracks post `post` died; `posts` are all the town's
## trooper posts. Before the fleet is beaten they respawn and nothing changes.
static func remnant_guard_died(post: String, posts: Array, f: String = HOME) -> void:
	if not Story.remnant_gone() or owner(barracks_of(f)) != REMNANT or not posts.has(post):
		return
	var dead := remnant_dead(f)
	if not dead.has(post):
		dead.append(post)
	WorldState.control[str(front(f).remnant_dead)] = dead
	if posts.all(func(p): return dead.has(p)):
		free_town(f)


## The locals hold the town's barracks again (every Remnant trooper there dead).
static func free_town(f: String = HOME) -> void:
	var fc := front(f)
	if not WorldState.has_flag(fc.retaken) or WorldState.has_flag(fc.driven_off):
		return
	WorldState.set_flag(str(fc.retaken), false)
	WorldState.control.erase(str(fc.remnant_dead))
	WorldState.control.erase(str(fc.dead))
	WorldState.change_standing("locals", int(cfg().get("standing", {}).get("town_freed", 10)), fline(f, "town_freed"))
	WorldState.checkpoint("town_freed" if f == HOME else f + "_town_freed")


## The Remnant hold the whole planet: the town's barracks, and not one outpost lost.
static func remnant_planet() -> bool:
	return owner(BARRACKS) == REMNANT and lost() == 0


# ------------------------------------------------------------------ supply runs (Oda's j_supply)

## You have taken Oda's supply run at least once. Until then the F11 map does not
## show which outposts are short; after it, it does, and any of them takes your
## supplies when you get there (can_deliver), with no job to take again.
static func supplier() -> bool:
	return WorldState.has_flag(SUPPLIER) or WorldState.count("supplies_delivered") > 0 or supply_out() != ""


## Do the maps (F11, the cruiser's hologram) mark outpost `id` as short? The
## locals' only once you are their supplier; the Remnant's (issue #425) only
## while they still deal with you.
static func short_shown(id: String) -> bool:
	return id != BARRACKS and ((supplier() and short(id)) or (remnant_friend() and remnant_short(id)))


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


## Issue #425: would walking up to outpost `id` hand the Remnant a load? Only
## while they are short there, still deal with you, and you are pointed at
## its resupply quest (the waypoint is the job: you are carrying the load).
static func can_deliver_remnant(id: String) -> bool:
	return remnant_short(id) and remnant_friend() and Quests.state(remnant_quest_id(id)) == "open" \
		and bool(WorldState.quests.get(remnant_quest_id(id), {}).get("waypoint", false))


## The player brought the Remnant a load at outpost `id`. Returns the pay (0 = not theirs).
static func deliver_remnant(id: String) -> int:
	if not can_deliver_remnant(id):
		return 0
	WorldState.control[id].hold = rn("hold_s", 6000.0)
	var pay := int(rn("pay", 120.0))
	var st: Dictionary = cfg().get(REMNANT, {}).get("standing", {})
	WorldState.credits += pay
	WorldState.bump("remnant_supplies_delivered")
	WorldState.change_standing("imperial_remnant", int(st.get("remnant", 3)), "Supplies reached the Remnant.")
	WorldState.change_standing("locals", int(st.get("locals", -2)), "Someone is keeping the Remnant supplied.")
	WorldState.log_event(line("remnant_supplied") % [Story.outpost_label(id), pay])
	QuestNews.push("supplies_delivered", "+%d cr" % pay)
	Quests.complete(remnant_quest_id(id))
	_sync_flags()
	return pay


## The resupply quest for outpost `id`.
static func quest_id(id: String) -> String:
	return "resupply_" + id


## Issue #425: the Remnant's resupply quest for outpost `id`.
static func remnant_quest_id(id: String) -> String:
	return "resupply_remnant_" + id


## One optional resupply quest per outpost for each side, in Quests' shape
## (territory.json "quest", and "remnant" "quest" for the Remnant's).
static func quests() -> Array:
	var q: Dictionary = cfg().get("quest", {})
	var rq: Dictionary = cfg().get(REMNANT, {}).get("quest", {})
	var out: Array = []
	for id in Story.OUTPOSTS:
		var label := Story.outpost_label(str(id))
		out.append({ "id": quest_id(str(id)), "title": str(q.get("title", "%s")) % label,
			"text": str(q.get("text_supplier" if supplier() else "text", "%s")) % label, "target": "outpost:" + str(id) })
	for id in Story.OUTPOSTS:
		var label := Story.outpost_label(str(id))
		out.append({ "id": remnant_quest_id(str(id)), "title": str(rq.get("title", "%s")) % label,
			"text": str(rq.get("text_oath" if DarkPact.joined() else "text", "%s")) % label, "target": "outpost:" + str(id) })
	return out


## Fraction of a full hold the holders have left at outpost `id` (0..1), or -1
## when there is no clock (the Remnant's before the cruiser falls, or the
## Remnant are gone).
static func hold_frac(id: String) -> float:
	var f := front_of(id)
	if driven_off(f) or not outposts(f).has(id):
		return -1.0
	if owner(id) == REMNANT:
		return clampf(hold_left(id) / rn("hold_s", 6000.0), 0.0, 1.0) if remnant_clocked(f).has(id) else -1.0
	if not bool(front(f).clock):
		return -1.0                           # the moon's locals keep it with no clock
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
		var fc := front(front_of(str(id)))
		var label := str(fc.label) if id == str(fc.barracks) else Story.outpost_label(str(id)).trim_prefix("the ")
		var who := owner(str(id))
		var tag := str(labels.get(who, who.to_upper()))
		if hold_frac(str(id)) >= 0.0:
			var left := maxf(0.0, hold_left(str(id)))
			var low := short(str(id)) or remnant_short(str(id))
			tag = "%s %d:%02d" % [str(labels.get("short" if who == LOCALS else "remnant_short", tag)) if low else tag, int(left) / 60, int(left) % 60]
		out.append("%-19s %s" % [label.capitalize().left(19), tag])
	return out
