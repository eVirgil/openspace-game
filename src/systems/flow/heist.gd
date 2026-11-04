class_name Heist
extends RefCounted
## Heists (issue #306): rob an outpost's control room. Pure and static, like
## Territory; its state lives in WorldState.heist (saved with the world):
##   { run, state: "out" | "", job, side, outpost, hacked, crew, crew_down, droid_down }
##   ({} or state "" = no heist on; run counts every heist taken)
##
## Issue #309: the console in each outpost's control room (OutpostRoom). Held
## for hack_seconds() while the heist on names that outpost (armed), it releases
## the stash: stash_entry() is then a pickup lying at the console (RemnantOutposts
## puts it there, and back after a load) until you take it.
##
## Issue #310: heists are board jobs (kind "heist"). The locals' (j_heist: Oda,
## the fence, Skrugs, T-89) hits an outpost the Remnant hold and the fence pays;
## the Remnant's (j_general_heist, free roam only: the general) hits one the
## locals hold and the general pays, pay_mult times the fence's price. One heist
## at a time, either side's, a new one once the last is over, for ever. Each
## offer names its outpost (rolled when first shown, kept until taken or no
## longer the other side's). The crew's cut comes off the top. A heist ends when
## it is paid, when you are downed, when you call it off, or when the flasks are
## gone (sold elsewhere, or taken at the gate). Who holds the outpost afterwards
## is not the heist's business: Territory's rules stand (RemnantOutposts).
##
## The crew (a crew member and a borrowed assassin droid) are HeistCrew's.
## Numbers and lines: content/core/story/heist.json.

const PATH := "res://content/core/story/heist.json"
const LOCALS_JOB := "j_heist"
const REMNANT_JOB := "j_general_heist"
const STORY_FIRST := "remnant_outpost_mid"   ## issue #413: the story's first heist (the first bounty is the nearest)

static var _cfg: Dictionary = {}
static var _offers: Dictionary = {}      ## job id -> the outpost its offer names (not saved: rolled again after a load)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


static func line(key: String) -> String:
	return str(cfg().get("lines", {}).get(key, ""))


static func crew_cfg() -> Dictionary:
	return cfg().get("crew", {})


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


static func cut() -> float:
	return float(cfg().get("cut", 0.2))


# ------------------------------------------------------------------ the heist on

static func on() -> bool:
	return str(WorldState.heist.get("state", "")) == "out"


## The outpost the heist on is after ("" = none).
static func target() -> String:
	return str(WorldState.heist.get("outpost", "")) if on() else ""


## "locals" or "remnant": whose heist is on ("" = none).
static func side() -> String:
	return str(WorldState.heist.get("side", "")) if on() else ""


## Who takes the flasks: "fence" (the locals' heist) or "general".
static func pays_to() -> String:
	return "general" if side() == "remnant" else "fence"


static func hacked() -> bool:
	return on() and bool(WorldState.heist.get("hacked", false))


## Does outpost `id`'s console have something to release right now?
static func armed(id: String) -> bool:
	return id != "" and target() == id and not hacked()


static func stash_id() -> String:
	return "heist_%d" % int(WorldState.heist.get("run", 0))


static func stash_taken() -> bool:
	return hacked() and WorldState.inventory.is_taken(stash_id())


## The stash lying at the hacked console, as a pickup entry, or {} (no heist,
## not hacked yet, or already picked up).
static func stash_entry() -> Dictionary:
	if not hacked() or WorldState.inventory.is_taken(stash_id()):
		return {}
	return { "id": stash_id(), "item": stash_item(), "count": stash_count(), "reach": 1.8, "job": true }


## Flasks of the stash you carry now (at most the stash's count), once taken.
static func carrying() -> int:
	return mini(stash_count(), WorldState.inventory.count(stash_item())) if stash_taken() else 0


## You have the flasks and the heist waits on its pay.
static func holding() -> bool:
	return carrying() > 0


## `to` ("fence" or "general") can pay for the flasks now.
static func collectable(to: String) -> bool:
	return holding() and pays_to() == to


## The console at outpost `id` was held long enough: the stash is out. False
## (and nothing changes) when it was not armed. The side robbed thinks a little
## less of you (hack_standing).
static func on_hacked(id: String, label: String = "") -> bool:
	if not armed(id):
		return false
	WorldState.heist["hacked"] = true
	WorldState.bump("consoles_hacked")
	var robbed := "imperial_remnant" if side() == "locals" else "locals"
	if side() != "":
		WorldState.change_standing(robbed, int(cfg().get("hack_standing", -3)))
	WorldState.log_event(line("log_hacked") % (label if label != "" else Story.outpost_label(id)))
	return true


# ------------------------------------------------------------------ the jobs (issue #310)

static func is_job(j: Dictionary) -> bool:
	return str(j.get("kind", "")) == "heist"


static func job_side(j: Dictionary) -> String:
	return str(j.get("side", "locals"))


## The outposts job `j` could hit now: the other side's. The locals' heist
## leaves out the outpost a bounty is out on while it has another to pick.
static func targets(j: Dictionary) -> Array:
	var want := Territory.REMNANT if job_side(j) == "locals" else Territory.LOCALS
	var out: Array = Story.OUTPOSTS.filter(func(o): return Territory.owner(str(o)) == want)
	var hunted := str(WorldState.bounty_target().get("outpost", ""))
	if out.size() > 1 and out.has(hunted):
		out.erase(hunted)
	return out


## Can job `j` be on the board now (its "requires" aside, WorldState checks
## those): no heist on, the home planet, somewhere to hit and, for the general's,
## a free roam save with the general alive.
static func can_offer(j: Dictionary) -> bool:
	if on() or GameFlow.current_planet_id() != PlanetGen.home_id():
		return false
	if job_side(j) == "remnant" and (WorldState.story_mode() or WorldState.has_flag("general_dead")):
		return false
	return not targets(j).is_empty()


## The outpost job `j`'s offer names: the heist's own once it is on, else the
## one rolled for it (kept while it is still the other side's).
static func offer_outpost(j: Dictionary) -> String:
	var id := str(j.get("id", ""))
	if on() and str(WorldState.heist.get("job", "")) == id:
		return target()
	var t := targets(j)
	if t.is_empty():
		return ""
	if story_first(j) and t.has(STORY_FIRST):
		return STORY_FIRST
	if not t.has(str(_offers.get(id, ""))):
		_offers[id] = str(t[randi() % t.size()]) if t.size() > 1 else str(t[0])
	return str(_offers[id])


## Issue #413: job `j` is the story's first heist (the heist chapter, none paid yet).
static func story_first(j: Dictionary) -> bool:
	return job_side(j) == "locals" and WorldState.story_mode() and Story.chapter() == "heist" \
		and WorldState.count("heists_paid") == 0


## What the stash pays `to` ("fence" or "general"), before and after the crew's
## cut: { gross, cut, net } for `n` flasks (the whole stash by default).
static func pay(to: String, n: int = -1) -> Dictionary:
	if n < 0:
		n = stash_count()
	var each := maxi(0, Inventory.sell_price(WorldState._item(stash_item()), WorldState._fence("port_town")))
	var mult := 1.0
	if to == "general":
		for b in WorldState.board():
			if str(b.get("id", "")) == REMNANT_JOB:
				mult = float(b.get("pay_mult", 1.5))
	var gross := roundi(mult * n * each)
	var share := roundi(gross * cut())
	return { "gross": gross, "cut": share, "net": gross - share }


## Job `j` as its giver shows it: its text with the outpost, the crew and the pay.
static func job_view(j: Dictionary) -> Dictionary:
	var out := j.duplicate()
	var where := offer_outpost(j)
	var to := "general" if job_side(j) == "remnant" else "fence"
	var net := int(pay(to).net)
	var crew := str(WorldState.heist.get("crew", "")) if on() and str(WorldState.heist.get("job", "")) == str(j.get("id", "")) else ""
	out["text"] = str(j.get("text", "%s %s %d")) % [Story.outpost_label(where) if where != "" else "an outpost",
		crew if crew != "" else ("one of ours" if job_side(j) == "remnant" else "one of my people"), net]
	out["pays"] = net
	out["target"] = "outpost:" + where if where != "" else ""
	return out


## Take job `j`: the heist is on. The crew meet you (HeistCrew).
static func start(j: Dictionary) -> bool:
	if j.is_empty() or not is_job(j) or not can_offer(j):
		return false
	var where := offer_outpost(j)
	if where == "":
		return false
	WorldState.heist = {
		"run": int(WorldState.heist.get("run", 0)) + 1, "state": "out", "job": str(j.get("id", "")),
		"side": job_side(j), "outpost": where, "hacked": false, "crew": "", "crew_down": false, "droid_down": false,
	}
	_offers.erase(str(j.get("id", "")))
	WorldState.bump("heists_taken")
	WorldState.log_event(line("log_taken") % Story.outpost_label(where))
	Story.event("heist_taken")
	return true


## `to` takes the flasks you carry (at most the stash): it pays what pay() says
## for them, less the crew's cut, and the heist is over. Returns
## { net, cut, gross } (net 0 when there was nothing to pay for).
static func collect(to: String) -> Dictionary:
	if not collectable(to):
		return { "net": 0, "cut": 0, "gross": 0 }
	var n := carrying()
	for i in n:
		WorldState.inventory.remove(stash_item())
	var p := pay(to, n)
	WorldState.credits += int(p.net)
	var friend := "imperial_remnant" if to == "general" else "locals"
	WorldState.change_standing(friend, int(cfg().get("paid_standing", 3)))
	WorldState.bump("heists_paid")
	WorldState.log_event(line("log_paid") % [Story.outpost_label(target()), int(p.net)])
	QuestNews.push("job_done", str(WorldState.job(str(WorldState.heist.get("job", ""))).get("title", "Heist")))
	end("paid")
	Story.event("heist_paid")
	return p


## The heist is over (`why`: "paid", "downed", "given_up", "lost"). The crew
## walk off (HeistCrew sees it); the next one can be offered.
static func end(why: String) -> void:
	if not on():
		return
	var run := int(WorldState.heist.get("run", 0))
	WorldState.heist = { "run": run, "state": "", "ended": why }
	_offers.clear()


## You were downed: the heist is off.
static func on_downed() -> bool:
	if not on():
		return false
	end("downed")
	return true


## Call it off (the giver's menu).
static func give_up() -> bool:
	if not on():
		return false
	end("given_up")
	return true


## The flasks are gone (sold elsewhere, taken at the gate): the heist is off. True
## when that ended it just now.
static func check_lost() -> bool:
	if stash_taken() and carrying() == 0:
		end("lost")
		return true
	return false


## The heist's entry in the job log, or {}.
static func log_entry() -> Dictionary:
	if not on():
		return {}
	var where := Story.outpost_label(target())
	var to := "the general" if pays_to() == "general" else "the fence"
	var text := line("log_carry") % to if holding() else \
		line("log_rob") % [where, crew_name(), int(pay(pays_to()).net)]
	return { "title": line("log_title"), "text": text, "key": "heist" }


## The pointer's { text, target } while a heist is on, or {}.
static func objective() -> Dictionary:
	if not on() or GameFlow.current_planet_id() != PlanetGen.home_id():
		return {}
	var where := Story.outpost_label(target())
	if holding():
		if pays_to() == "general" and GeneralPost.station() != "":
			return { "text": line("objective_general"), "target": "npc:general" }
		var fence := Objective.fence_marker(true)
		return { "text": line("objective_fence"), "target": "marker:" + fence if fence != "" else "" }
	if hacked():
		return { "text": line("objective_take") % where, "target": "outpost:" + target() }
	return { "text": line("objective_rob") % where, "target": "outpost:" + target() }


static func crew_name() -> String:
	var n := str(WorldState.heist.get("crew", ""))
	return n if n != "" else "your crew"
