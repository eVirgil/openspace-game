class_name WorldState
extends RefCounted
## What is true in the world right now (M12): faction standing, town flags,
## counters, the job board, credits and a short log of recent events.
##
## Static, like GameFlow, so it survives scene changes (town -> flight -> town)
## without an autoload. Systems write to it when something actually happens
## (a fight won, shots fired in the street, a job accepted); the cantina owner only
## ever reads it. That is what keeps her rumors true: a rumor is shown to her
## only when its conditions hold here (see rumors()).
##
## Saved and restored through SaveSystem (to_save / from_save).

const RUMOR_DIR := "res://content/core/rumors"
const BOARD_PATH := "res://content/core/board/bar_board.json"
const PICKUP_DIR := "res://content/core/pickups"
const ITEM_DIR := "res://content/core/items"
const VENDOR_DIR := "res://content/core/vendors"
const FACTIONS := ["imperial_remnant", "locals", "smuggler"]
const DEFAULT_STANDING := { "imperial_remnant": -10, "locals": 5, "smuggler": 20 }
const STORY := "story"
const FREEPLAY := "freeplay"
const STORY_WEAPON := "pistol_blaster"     ## issue #200: the one hand weapon a story save starts with
const GENERAL_CARD := "res://content/core/npcs/general_card.json"
const SHIP_REBUILT := "ship_rebuilt"        ## issue #206: T-89 rebuilt the wreck on the pit pad (a story save's own ship)
const COMRADE := "t89_comrade"              ## issue #206: the player told T-89 they can't stand the Remnant
const FREE_OPENING := "free_opening"        ## a new free roam game: the landing still to play (opening_due)
const FREE_SHIP := "free_ship"              ## a free roam game's own interceptor is yours (Fleet.FREE)
const FREE_SHIP_GONE := "free_ship_gone"    ## ... and was sold or lost for good

static var standing: Dictionary = DEFAULT_STANDING.duplicate()
static var flags: Dictionary = {}          ## name -> true
static var counters: Dictionary = {}       ## name -> int
static var events: Array = []              ## [{ t, text, where? }] newest last, capped (issue #188: where = the place it happened)
static var credits := 60
static var time_of_day := "golden"
static var day_pick := "auto"              ## issue #381: the F11 picker: "auto" or a preset (DayClock)
static var day_step := 0                   ## issue #381: where the day is in time_of_day.json "day_order"
static var day_moved_at := 0.0             ## `clock` when the day last moved on by itself (DayClock.min_seconds)
static var jobs_taken: Dictionary = {}     ## job id -> "active" | "done"
static var clock := 0.0                    ## seconds of play, for cooldowns
static var inventory := Inventory.new()    ## M13: the player's gear (owned, attached, taken, vendor stock)
static var names := NameBook.new()         ## issue #15: every name given out, so each one is unique
static var smuggle: Dictionary = {}        ## the drop put out: { run, job, to, item, count, area, hint, marker, offset, near, ground, surface, marked, location, out }
static var smuggle_offers: Dictionary = {} ## issue #251: smuggling job id -> the drop it offers, not out yet (not saved: rolled again after a load)
static var droids := DroidRoster.new()     ## issue #51: the player's companion droids, their cargo, desert wrecks
static var hangar := ""                    ## issue #58: the ship id you bought from T-89 (on the spare pad), "" = none
static var story: Dictionary = {}          ## issue #64: { chapter, told } (Story); {} = the first chapter
static var ships_destroyed: Array = []     ## issue #64: town boxes whose parked ship was shot to pieces (never back)
static var native_packs: Dictionary = {}       ## issue #96: pack id -> { rep, friendly, locked, trades, kills }
static var native_camps: Dictionary = {}       ## issue #96: camp id -> { wrecked_h, looted: { box id -> game hour } }
static var game_hours := 0.0               ## issue #96: in-game hours played (camps come back, boxes refill, rest)
static var speeder_fits: Array = []        ## issue #95: one SpeederUpgrades fit per owned speeder, by parking slot
static var bounty: Dictionary = {}         ## issue #64: { run, key, name, crime, outpost, pay, state: "rolled"|"out"|"dead" }
static var mode := FREEPLAY                ## issue #200: STORY or FREEPLAY, picked on New Game, kept in the save
static var ship_fits: Dictionary = {}      ## issue #207: ship id -> [upgrade id] T-89 fitted (ShipUpgrades)
static var gear_fits: Array = []           ## issues #208, #209: fence offers bought (GearUpgrades)
static var wreck_ship := ""                ## issue #207: the ship id of the wreck T-89 rebuilt ("" = none)
static var kept_ships: Array = []          ## issue #368: stolen ships Skrugs cleaned up for you: [{ key, ship }] (Fleet)
static var ship_spots: Dictionary = {}     ## issue #368: owned ship key -> { planet, pos, rot } where it was last left (Fleet)
static var primary_ship := ""              ## issue #368: the owned ship key that wakes with you ("" = the first; Fleet.primary)
static var quests: Dictionary = {}         ## issue #201: optional quest id -> { state: "open"|"done", waypoint } (Quests)
static var heist: Dictionary = {}          ## issue #306: the heist on: { run, state, job, side, outpost, hacked, crew, ... } (Heist)
static var control: Dictionary = {}        ## issue #187: who holds each outpost, and the supply run out (Territory)
static var map_waypoint: Dictionary = {}   ## the F11 map's waypoint: { id, label, target, planet, arrive } (GlobeMap)
static var objective_pin := ""             ## the job the player made the waypoint in the Ledger ("" = most urgent; Objective.pin)
static var loads := 0                      ## how many times the world was reset or loaded (a LAN guest then waits for the host's jobs, NetJobs)

## Issue #303: called (with a reason) whenever the game must be saved right now: the
## general's death, the dark master's answer, the town changing hands. The town's
## ConversationHost (which owns the save) adds its save here.
static var checkpoint_hooks: Array[Callable] = []

static var _rumors: Array = []
static var _board: Array = []
static var _cooldowns: Dictionary = {}
static var _items: Dictionary = {}         ## item id -> its content/core/items entry (cache)

const MAX_EVENTS := 12
const DROP_NEAR := 15.0                    ## issue #251: the pointer lands at most this far from a drop (m)


static func reset() -> void:
	loads += 1
	standing = DEFAULT_STANDING.duplicate()
	flags = {}
	counters = {}
	events = []
	credits = 60
	time_of_day = "golden"
	day_pick = "auto"
	day_step = 0
	day_moved_at = 0.0
	jobs_taken = {}
	clock = 0.0
	_cooldowns = {}
	inventory = Inventory.new()
	names = NameBook.new()
	smuggle = {}
	smuggle_offers = {}
	droids = DroidRoster.new()
	hangar = ""
	story = {}
	bounty = {}
	ships_destroyed = []
	speeder_fits = []
	native_packs = {}
	native_camps = {}
	game_hours = 0.0
	mode = FREEPLAY
	quests = {}
	control = {}
	heist = {}
	map_waypoint = {}
	objective_pin = ""
	QuestNews.clear()
	StandingNews.clear()
	ship_fits = {}
	wreck_ship = ""
	kept_ships = []
	ship_spots = {}
	primary_ship = ""
	gear_fits = []


## Issue #200: a new save in STORY or FREEPLAY mode. Story starts at the first
## chapter with every faction neutral and the pistol only (weapon_allowed).
## Freeplay goes straight to the free chapter (drops and bounties on repeat), the
## port's ships flying, the world otherwise as today. It also opens with the
## landing (no general in the pit), with the rifle and the blade already in your
## backpack (the story's "free_roam_kit").
static func new_game(m: String) -> void:
	reset()
	mode = STORY if m == STORY else FREEPLAY
	if mode == STORY:
		for f in FACTIONS:
			standing[f] = 0
		story = Story.fresh()
	else:
		story = { "chapter": "free", "told": true }
		set_flag("ships_unlocked")
		set_flag(FREE_OPENING)
		set_flag(FREE_SHIP)
		for id in Story.data().get("free_roam_kit", []):
			inventory.add(str(id))


static func story_mode() -> bool:
	return mode == STORY


## Issue #202: does the town open with the landing (ShipPilot.opening_landing)? A
## story save at its first chapter, or a new free roam game until you get out.
static func opening_due() -> bool:
	return Story.chapter() == "land" if story_mode() else has_flag(FREE_OPENING)


## Issue #206: the player owns a ship: the wreck T-89 rebuilt, or one bought from him.
## Issue #368: or a stolen one Skrugs cleaned up.
static func owns_ship() -> bool:
	return has_flag(SHIP_REBUILT) or hangar != "" or not kept_ships.is_empty()


## Issue #200: may the player draw hand weapon `id`? Freeplay: all of them. Story:
## the pistol, and any other once you own it (issue #210: the rifle on the barracks
## roof, the blade on the cantina tower) or something sets its "weapon_<id>" flag.
## A weapon whose item is "must_own" (the fence's sniper rifle) needs owning in both.
static func weapon_allowed(id: String) -> bool:
	if bool(_item(id).get("must_own", false)):
		return inventory.has(id) or has_flag("weapon_" + id)
	return not story_mode() or id == STORY_WEAPON or inventory.has(id) or has_flag("weapon_" + id) \
		or (id == "energy_blade" and inventory.in_slot("blade") != "")     # an activated red saber is a blade too


## Issue #203: searched on the spot (the general's guards): the gate's rules, so
## whatever contraband is in your pockets is taken (a droid's hold is not
## searched). Returns the item ids taken.
static func search_player() -> Array:
	var taken: Array = []
	for id in inventory.item_ids():
		if bool(_item(str(id)).get("contraband", false)):
			while inventory.has(str(id)):
				inventory.remove(str(id))
			taken.append(str(id))
	bump("searches")
	log_event("Searched by the Remnant%s." % (": they took %s" % ", ".join(PackedStringArray(taken)) if not taken.is_empty() else ""))
	return taken


# ------------------------------------------------------------------ writes

static func set_flag(name: String, on: bool = true) -> void:
	if on:
		flags[name] = true
	else:
		flags.erase(name)


static func has_flag(name: String) -> bool:
	return flags.has(name)


static func bump(counter: String, by: int = 1) -> int:
	counters[counter] = int(counters.get(counter, 0)) + by
	return counters[counter]


static func count(counter: String) -> int:
	return int(counters.get(counter, 0))


static func change_standing(faction: String, delta: int, why: String = "", where: String = "") -> void:
	var before := int(standing.get(faction, 0))
	standing[faction] = clampi(before + delta, -100, 100)
	StandingNews.push(faction, before, int(standing[faction]))
	if why != "":
		log_event(why, where)


## Issue #188: `where` is the place in town it happened ("gate", "market", "pit",
## "back_gate", "barracks", "cantina", "orbit"): who is there hears it at once,
## everyone else when the gossip gets to them (NpcBrain.heard). "" = nowhere in
## particular: gossip only.
static func log_event(text: String, where: String = "") -> void:
	var e := { "t": clock, "text": text }
	if where != "":
		e["where"] = where
	events.append(e)
	while events.size() > MAX_EVENTS:
		events.pop_front()


## True at most once per `seconds` per key (so spamming an action cannot farm
## or tank standing).
static func cooldown_ok(key: String, seconds: float) -> bool:
	if clock - float(_cooldowns.get(key, -INF)) < seconds:
		return false
	_cooldowns[key] = clock
	return true


static func tick(dt: float) -> void:
	clock += dt
	Territory.tick(dt)          # issue #187: the locals' hold on each outpost runs down


# ------------------------------------------------------------------ things that happen

## The player fired a blaster. `in_range` = on the sanctioned range in the pit.
static func on_player_fired(in_range: bool) -> void:
	if in_range:
		bump("range_shots")
		return
	bump("street_shots")
	set_flag("shots_in_street")
	if cooldown_ok("street_shots", 45.0):
		change_standing("imperial_remnant", -3, "Somebody fired a blaster in the street.")
		change_standing("locals", -1)


## M15: the gate checkpoint. Every outcome lands here so the cantina owner (and any
## later system) reads it from one place.
static func on_gate_bribe(price: int) -> void:
	credits = maxi(0, credits - price)
	bump("gate_bribes")
	set_flag("bribed_gate")
	log_event("Paid off the front gate (%d cr)." % price, "gate")


## A Remnant guard died. `all_down`: that was the last one at the gate. `where`:
## the place it happened ("gate" for the town's own garrison; issue #188).
static func on_guard_killed(delta: int, all_down: bool, where: String = "") -> void:
	bump("guards_killed")
	change_standing("imperial_remnant", delta, "A Remnant gate guard was killed.", where)
	change_standing("locals", 1)
	if all_down:
		set_flag("gate_guards_down")
		set_flag("gate_checkpoint_up", false)
		log_event("The front gate checkpoint is down. Nobody is on it.", "gate")


## Issue #76: the player killed a Remnant soldier worth `amount` (its profile's
## kill_reward). Droids pay nothing.
static func on_guard_reward(amount: int) -> void:
	if amount <= 0:
		return
	credits += amount
	bump("guard_rewards", amount)


## Knocked out at the gate and dragged to the pit: they help themselves to a
## share of your credits. Returns what was taken.
static func on_player_downed(share: float = 0.2, minimum: int = 5) -> int:
	var take := mini(credits, maxi(minimum, int(credits * share)))
	credits -= take
	bump("times_downed")
	log_event("Woke up in the pit, %d cr lighter." % take, "pit")
	return take


static func on_flight_returned(arrival: Dictionary) -> void:
	if arrival.is_empty():
		return
	if str(arrival.get("outcome", "")) == "complete":
		bump("patrols_beaten")
		set_flag("remnant_patrol_beaten")
		set_flag("ship_limped_home", false)
		change_standing("imperial_remnant", -15, "A Remnant patrol in orbit was shot to pieces.", "orbit")
		change_standing("locals", 4)
		change_standing("smuggler", 5)
		# The fleet's fighters are only in the way: the story waits on the cruiser's general.
		credits += int(arrival.get("payout", 0))
		_complete_jobs("flight_complete")
	else:
		set_flag("ship_limped_home")
		log_event("A ship came back into the pit trailing smoke.", "pit")


## Issue #64: the player is on the practice range (Oda's honour system: going
## there is the practice).
static func on_range_visited() -> void:
	Story.event("range_visited")


## Issue #64: every target on the range down at once (any time; the record is
## the bet's business).
static func on_range_cleared() -> void:
	bump("range_clears")


## Issue #64: something contraband went to the fence. The run is over once the
## drop was picked up and nothing contraband is left on you or your droids.
## Only a run Oda gave you in this chapter counts: goods found or carried in from
## before the story asked for them do not move it on.
static func on_contraband_sold() -> void:
	if smuggle_drop().is_empty() and not carrying_contraband():
		bump("smuggle_sold")
		if smuggle_to() == "fence":
			_cargo_delivered()
		if bool(story.get("took_run", false)):
			Story.event("smuggle_sold")


static func on_range_record(seconds: float) -> void:
	set_flag("range_record")
	log_event("Someone cleared the practice range in %.1f seconds." % seconds)
	_complete_jobs("range_record")


static func on_deflection() -> void:
	bump("deflections")
	if count("deflections") >= 5:
		set_flag("blade_trained")


# ------------------------------------------------------------------ jobs

static func board() -> Array:
	if _board.is_empty():
		var d = _read_json(BOARD_PATH)
		if d is Dictionary:
			_board = d.get("jobs", [])
	return _board


## A job as the cantina owner shows it. A smuggling job comes back with its text
## and pay filled in from the drop she has lined up.
static func job(id: String) -> Dictionary:
	for j in board():
		if str(j.get("id", "")) == id:
			match str(j.get("kind", "")):
				"smuggle":
					return _smuggle_job(j)
				"bounty":
					return _bounty_job(j)
				"supply":
					return _supply_job(j)
				"heist":
					return Heist.job_view(j)       # issue #310: the outpost, the crew, the pay
			return j
	return {}


## Jobs the cantina owner can offer at this trust tier, not yet taken.
##
## A smuggling job belongs to its town: the port's drop is offered at the port,
## the station's on the station. Contracts stay global: off the home planet they
## are always on the board, without waiting on the port's story.
static func open_jobs(tier: String) -> Array:
	var out: Array = []
	var away := always_jobs_here()
	var here := current_town_id()
	for j in board():
		if jobs_taken.has(str(j.id)):
			continue
		var kind := str(j.get("kind", ""))
		if kind == "smuggle" and (not smuggle_ready() or str(j.get("location", "")) != here):
			continue
		if kind == "bounty" and not (bounty_ready() and (away or Story.bounties_open())):
			continue
		if kind == "supply" and (away or Territory.supply_target() == "" or Territory.supplier()):
			continue
		if kind == "heist" and not Heist.can_offer(j):
			continue                       # issue #310: one at a time, somewhere to hit
		var req: Dictionary = j.get("requires", {})
		if away and kind in ["smuggle", "bounty"]:
			req = req.duplicate()
			req.erase("story")
		if _conditions_hold(req, tier):
			out.append(job(str(j.id)))
	return out


## True off the home planet: there the contract is always on the board (issue
## #75). Smuggling is local to each town now.
static func always_jobs_here() -> bool:
	return GameFlow.current_planet_id() != PlanetGen.home_id()


## The town this scene is built for (the port's authored town, or a generated
## one such as grit_station_town).
static func current_town_id() -> String:
	return str(GameFlow.planet().get("town_id", "port_town"))


## Takes job `id`, with a banner (QuestNews): "New Job", or "New Target" for a bounty.
static func accept_job(id: String) -> bool:
	var j := job(id)
	var ok := false
	match str(j.get("kind", "")):
		"smuggle":
			ok = _start_smuggle(j)
		"bounty":
			ok = _start_bounty(j)
		"supply":
			ok = Territory.start_supply()
		"heist":
			ok = Heist.start(j)            # issue #310
		_:
			ok = not j.is_empty() and not jobs_taken.has(id)
			if ok:
				jobs_taken[id] = "active"
				log_event("Took the job: " + str(j.get("title", id)))
	if ok and str(j.get("kind", "")) == "bounty":
		QuestNews.push("target_new", str(bounty.name))
	elif ok:
		QuestNews.push("job_taken", str(j.get("title", id)))
	return ok


static func _complete_jobs(trigger: String) -> void:
	for id in jobs_taken.keys():
		var j := job(id)
		if jobs_taken[id] == "active" and str(j.get("completes_on", "")) == trigger:
			jobs_taken[id] = "done"
			credits += int(j.get("pays", 0))
			set_flag("job_done_" + id)
			log_event("Finished the job: " + str(j.get("title", id)))
			QuestNews.push("job_done", str(j.get("title", id)))


## Issue #187: Oda's supply run, its text naming the outpost short of supplies
## (or the one the supplies are going to, once taken).
static func _supply_job(j: Dictionary) -> Dictionary:
	var out := j.duplicate()
	var to := Territory.supply_out()
	if to == "":
		to = Territory.supply_target()
	out.text = str(j.get("text", "%s %d")) % [Story.outpost_label(to) if to != "" else "an outpost", int(Territory.cfg().get("supply_pay", 120))]
	out.pays = int(Territory.cfg().get("supply_pay", 120))
	return out


# ------------------------------------------------------------------ smuggling

## The repeating smuggling jobs (kind "smuggle"). Each one lines up a drop of
## contraband in one of its town's hiding places (pickups/<location>.json
## "drops", only its own "areas" when it names some); taking the job puts it
## there. One drop is out at a time: the next one is offered once that drop is
## picked up and the player carries no contraband (sold to the fence, handed to
## the general, or lost at the gate), so the loop runs for as long as anyone plays.
##
## Issue #251: at the port, Oda and the fence send you out of town (the desert
## past either gate) and the fence buys the goods; the general sends you after
## stashes inside the town (the alleys, the roofs) and the goods go to him
## ("deliver_to": "general").

## The drop lying in the world, as a pickup entry, or {} when there is none.
static func smuggle_drop() -> Dictionary:
	if not bool(smuggle.get("out", false)):
		return {}
	var id := "smuggle_%d" % int(smuggle.run)
	if inventory.is_taken(id) or bool(smuggle.get("taken", false)):
		return {}                # "taken": in a LAN game, another player picked it up (NetJobs)
	return {
		"id": id, "item": smuggle.item, "count": int(smuggle.count), "marker": smuggle.marker,
		"offset": smuggle.offset, "ground": bool(smuggle.get("ground", false)), "hidden": true, "reach": 2.0,
		"surface": bool(smuggle.get("surface", false)),
		"marked": bool(smuggle.get("marked", false)),
		"location": str(smuggle.get("location", "")),
	}


## Can a new drop be lined up? Not while one is lying out there, and not while
## the player still has contraband to get rid of.
static func smuggle_ready() -> bool:
	return smuggle_drop().is_empty() and not carrying_contraband()


## Who takes the goods of the last drop put out: "fence" or "general" (issue #251).
static func smuggle_to() -> String:
	return str(smuggle.get("to", "fence"))


## Pockets or a cargo droid (issue #51): the gate never finds what a droid
## carries, but Oda still waits until it is sold.
static func carrying_contraband() -> bool:
	for id in inventory.item_ids() + droids.all_cargo().keys():
		if bool(_item(str(id)).get("contraband", false)):
			return true
	return false


## A run for the fence in `location` waits only on a sale: its drop is picked up
## and contraband is in your pockets. Selling it there is what closes the job, so
## his menu puts those rows first (GearController.trade_options).
static func fence_run_open(location: String) -> bool:
	return bool(smuggle.get("out", false)) and smuggle_to() == "fence" and smuggle_drop().is_empty() \
			and str(smuggle.get("location", "")) == location and carrying_contraband()


static func _smuggle_job(j: Dictionary) -> Dictionary:
	var s := _smuggle_for(j)
	if s.is_empty():
		return {}
	var out := j.duplicate()
	out["text"] = str(j.get("text", "%s %s")) % [smuggle_goods_text(j, s), str(s.hint)]
	out["pays"] = roundi(float(j.get("pay_mult", 1.0)) * int(s.count) * maxi(0, Inventory.sell_price(_item(str(s.item)), _fence(str(s.get("location", ""))))))
	return out


## The drop job `j` is about: its own drop while that one is still on (out, or
## its goods still on you), else the one it offers next (rolled once, then kept
## until it is taken, so the text the player read is the drop they get).
static func _smuggle_for(j: Dictionary) -> Dictionary:
	if bool(smuggle.get("out", false)) and not smuggle_ready() and _drop_job_id() == str(j.get("id", "")):
		return smuggle
	var id := str(j.get("id", ""))
	if not smuggle_offers.has(id):
		smuggle_offers[id] = _roll_smuggle(j)
	return smuggle_offers[id]


## The board job the drop put out came from (a drop saved before issue #251
## names none: its town's run for the fence).
static func _drop_job_id() -> String:
	if smuggle.has("job"):
		return str(smuggle.job)
	for b in board():
		if str(b.get("kind", "")) == "smuggle" and str(b.get("location", "")) == str(smuggle.get("location", "")) \
				and str(b.get("deliver_to", "fence")) == "fence":
			return str(b.id)
	return ""


## The vendor in `location` that buys contraband (the fence the drop goes to), or {}.
static func _fence(location: String) -> Dictionary:
	for f in DirAccess.get_files_at(VENDOR_DIR):
		if not f.ends_with(".json"):
			continue
		var v = _read_json(VENDOR_DIR + "/" + f)
		if v is Dictionary and str(v.get("location", "")) == location and (v.get("buys", []) as Array).has("contraband"):
			return v
	return {}


## What a drop is, in its job's words ("2 cases of holocrystals"). `s` = the
## drop ({} = the one put out), `j` = its smuggling job ({} = the one it came
## from). Reads only.
static func smuggle_goods_text(j: Dictionary = {}, s: Dictionary = {}) -> String:
	if s.is_empty():
		s = smuggle
	if s.is_empty():
		return ""
	if j.is_empty():
		var from := str(s.job) if s.has("job") else _drop_job_id()
		for b in board():
			if str(b.get("id", "")) == from:
				j = b
	var n := int(s.count)
	var goods := {}
	for g in j.get("goods", []):
		if str(g.get("item", "")) == str(s.item):
			goods = g
	var what := str(goods.get("say_one", goods.get("say", "%d"))) if n == 1 else str(goods.get("say", "%d"))
	if what.contains("%d"):
		what = what % n
	return what


## Pick job `j`'s next drop: goods from the job, a hiding place from its areas of
## the location's drops (never the area of the last drop put out), and where the
## pointer goes ("near": within DROP_NEAR of it, so there is still a search).
## {} when it has nothing to offer.
static func _roll_smuggle(j: Dictionary) -> Dictionary:
	var goods: Array = j.get("goods", [])
	var d = _read_json(PICKUP_DIR + "/" + str(j.get("location", "")) + ".json")
	var areas: Array = d.get("drops", {}).get("areas", []) if d is Dictionary else []
	var mine: Array = j.get("areas", [])
	# Issue #237: in a town built to a saved layout, an area's "layouts" block (its
	# spots in that layout) is laid over it.
	if str(j.get("location", "")) == current_town_id():
		var layout := str(GameFlow.planet().get("town", {}).get("layout", ""))
		areas = areas.map(func(a):
			var over: Dictionary = a.get("layouts", {}).get(layout, {})
			if over.is_empty():
				return a
			var m: Dictionary = a.duplicate(true)
			m.merge(over, true)
			return m)
	var last := str(smuggle.get("area", ""))
	var choices := areas.filter(func(a): return str(a.get("id", "")) != last and not (a.get("spots", []) as Array).is_empty() \
			and (mine.is_empty() or mine.has(str(a.get("id", "")))))
	if goods.is_empty() or choices.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var g: Dictionary = goods[rng.randi() % goods.size()]
	var a: Dictionary = choices[rng.randi() % choices.size()]
	var spots: Array = a.spots
	var span: Array = g.get("count", [1, 1])
	var turn := rng.randf() * TAU
	var r := rng.randf_range(DROP_NEAR * 0.3, DROP_NEAR)
	return {
		"job": str(j.get("id", "")), "to": str(j.get("deliver_to", "fence")), "item": str(g.item),
		"count": rng.randi_range(int(span[0]), int(span[1])),
		"area": str(a.id), "hint": str(a.get("hint", "")), "marker": str(a.get("marker", "")),
		"offset": spots[rng.randi() % spots.size()], "near": [cos(turn) * r, sin(turn) * r],
		"ground": bool(a.get("ground", false)),
		"surface": bool(a.get("surface", false)), "out": false,
		"marked": bool(a.get("marked", false)),
		"location": str(j.get("location", "")),    # the town this drop belongs to
	}


static func _start_smuggle(j: Dictionary) -> bool:
	var s: Dictionary = smuggle_offers.get(str(j.get("id", "")), {})
	if j.is_empty() or s.is_empty() or not smuggle_ready():
		return false
	var run := smuggle_run() + 1
	smuggle = s.duplicate(true)
	smuggle["run"] = run
	smuggle.out = true
	smuggle_offers.erase(str(j.id))
	# Issue #64: only the port's chapter run counts. A station job never moves
	# the port's story on, even if that story is waiting for a smuggling sale,
	# and neither does the general's (issue #251: his goods never reach the fence).
	story["took_run"] = str(j.get("location", "")) == "port_town" and smuggle_to() == "fence"
	bump("smuggle_runs")
	log_event(("The general sent you after contraband: " if smuggle_to() == "general" else "Oda set up a drop: ") + str(j.get("text", "")))
	return true


## How many drops have been put out (each one's pickup id is smuggle_<run>).
static func smuggle_run() -> int:
	return int(smuggle.get("run", 0))


## Issue #251: the general's run. What he pays for the contraband in your
## pockets (his job's pay_mult times what the fence would have: he outbids the
## fence), or 0 when the run on is not his or its drop is still lying out there.
static func repossession_pay() -> int:
	if smuggle_to() != "general" or not bool(smuggle.get("out", false)) or not smuggle_drop().is_empty():
		return 0
	var fence := _fence(str(smuggle.get("location", "")))
	var pay := 0
	for id in inventory.item_ids():
		var it := _item(str(id))
		if bool(it.get("contraband", false)):
			pay += inventory.count(str(id)) * maxi(0, Inventory.sell_price(it, fence))
	var mult := 1.0
	for j in board():
		if str(j.get("id", "")) == str(smuggle.get("job", "")):
			mult = float(j.get("pay_mult", 1.0))
	return roundi(mult * pay)


## Hand the general the contraband in your pockets: he pays repossession_pay(),
## Remnant standing goes up by `standing_gain`, and once nothing contraband is
## left on you the next drop can be lined up. Returns the pay, or 0.
static func hand_over_contraband(standing_gain: int) -> int:
	var pay := repossession_pay()
	if pay <= 0:
		return 0
	for id in inventory.item_ids():
		if bool(_item(str(id)).get("contraband", false)):
			while inventory.has(str(id)):
				inventory.remove(str(id))
	credits += pay
	change_standing("imperial_remnant", standing_gain, "Someone handed the Remnant general a smuggler's stash.")
	bump("repossessions")
	log_event("Handed the general the contraband for %d cr." % pay)
	if not carrying_contraband():
		_cargo_delivered()
	return pay


## The drop put out reached whoever takes it: its banner, once per drop (the
## next drop is a fresh `smuggle`). Loose contraband sold later is not news.
static func _cargo_delivered() -> void:
	if not bool(smuggle.get("out", false)) or bool(smuggle.get("delivered", false)):
		return
	smuggle["delivered"] = true
	QuestNews.push("cargo_delivered", smuggle_goods_text())


static func _item(id: String) -> Dictionary:
	if not _items.has(id):
		var d = _read_json(ITEM_DIR + "/" + id + ".json")
		_items[id] = d if d is Dictionary else {}
	return _items[id]


# ------------------------------------------------------------------ bounties (issue #64)

## Oda's other repeating job (kind "bounty"): a named Remnant officer at one of
## the desert outposts (Story.OUTPOSTS). Taking it puts them there
## (RemnantOutposts spawns whoever bounty_target() names); killing them makes the
## bounty collectable at the fence. One at a time.

## No contract out and none waiting to be paid.
static func bounty_ready() -> bool:
	return not ["out", "dead"].has(str(bounty.get("state", "")))


## The officer to put at an outpost, or {} when there is none to hunt.
static func bounty_target() -> Dictionary:
	return bounty if str(bounty.get("state", "")) == "out" else {}


## The fence has a bounty to pay out.
static func bounty_collectable() -> bool:
	return str(bounty.get("state", "")) == "dead"


static func on_bounty_killed() -> void:
	if str(bounty.get("state", "")) != "out":
		return
	bounty.state = "dead"
	bump("bounties_killed")
	if bool(bounty.get("general", false)):
		set_flag("general_dead")          # issue #213: the general is gone for good
	change_standing("imperial_remnant", -5)
	change_standing("locals", 3)
	log_event(str(Story.bounty_cfg().get("event_killed", "%s was found dead.")) % str(bounty.name))
	QuestNews.push("target_killed", str(bounty.name))


## The Remnant general was shot dead in the barracks yard (not as Oda's bounty):
## he is gone for good. A contract on him not yet taken goes to an officer at an
## outpost instead (rolled again when Oda next offers it), and his droid job closes.
static func on_general_killed() -> void:
	if has_flag("general_dead"):
		return
	set_flag("general_dead")
	if bool(bounty.get("general", false)) and str(bounty.get("state", "")) == "rolled":
		bounty = { "run": int(bounty.run), "outpost": str(bounty.outpost), "state": "" }
	jobs_taken.erase(GeneralPost.job_id())
	log_event(str(Story.bounty_cfg().get("event_general", "%s was shot dead at the barracks.")) % str(NpcBrain._read(GENERAL_CARD).get("name", "The general")), "barracks")


## Issue #193: the general aboard the Remnant cruiser is dead. The cruiser is taken
## (nobody aboard from now on), the locals' purse is paid, and the port loves you
## for it. `reward`: { credits, locals, remnant, smuggler } (remnant_cruiser.json).
## Returns the credits paid (0 when it was taken already).
## Issue #327: `flag` is the cruiser's own (its config's "flag"). Only the home one's,
## cruiser_taken, is the story's; any other only sets its flag and pays its reward.
static func on_cruiser_taken(general: String, reward: Dictionary, line: String = "", flag: String = "cruiser_taken") -> int:
	if flag != "cruiser_taken":
		return _on_other_cruiser_taken(flag, general, reward, line)
	if has_flag("cruiser_taken"):
		return 0
	set_flag("cruiser_taken")
	bump("generals_killed")
	var pay := int(reward.get("credits", 0))
	credits += pay
	change_standing("imperial_remnant", int(reward.get("remnant", -40)), "The Remnant general aboard the star cruiser was killed.")
	change_standing("locals", int(reward.get("locals", 60)))
	change_standing("smuggler", int(reward.get("smuggler", 0)))
	set_flag("locals_hero")
	log_event(line % general if line.contains("%s") else ("%s was killed aboard the Remnant cruiser." % general))
	QuestNews.push("target_killed", general)
	Story.event("cruiser_taken")
	if not Story.remnant_gone():
		# Issue #303: free roam too (no story chapter waits for it): the fleet is broken.
		set_flag("remnant_fleet_beaten")
		log_event("The Remnant fleet in orbit was broken. The garrison is pulling out of town.", "orbit")
	checkpoint("cruiser_taken")
	return pay


## Issue #327: a cruiser other than the home one is taken: its flag (saved with the
## world) and its reward, nothing else: no story, no locals' love, no fleet beaten.
static func _on_other_cruiser_taken(flag: String, general: String, reward: Dictionary, line: String) -> int:
	if has_flag(flag):
		return 0
	set_flag(flag)
	var pay := int(reward.get("credits", 0))
	credits += pay
	for pair in [["imperial_remnant", "remnant"], ["locals", "locals"], ["smuggler", "smuggler"]]:
		if int(reward.get(pair[1], 0)) != 0:
			change_standing(str(pair[0]), int(reward.get(pair[1], 0)))
	log_event(line % general if line.contains("%s") else ("%s was killed aboard a Remnant cruiser." % general), "orbit")
	QuestNews.push("target_killed", general)
	checkpoint(flag)
	return pay


## Issue #303: save the game now (checkpoint_hooks). Returns how many saves ran.
static func checkpoint(why: String) -> int:
	var ran := 0
	for h in checkpoint_hooks.duplicate():
		if h.is_valid():
			h.call(why)
			ran += 1
		else:
			checkpoint_hooks.erase(h)
	return ran


## Issue #213: Oda's first bounty in a story save goes on the general himself
## when your Remnant standing is -15 or lower (unfriendly or worse) and he lives.
static func general_target() -> bool:
	return story_mode() and Story.chapter() == "bounty" and not has_flag("general_dead") \
		and int(standing.get("imperial_remnant", 0)) <= int(Story.bounty_cfg().get("general_standing", -15))


## Paid at the fence. Returns the credits, or 0 when nothing is owed.
static func collect_bounty() -> int:
	if not bounty_collectable():
		return 0
	var pay := int(bounty.pay)
	credits += pay
	bump("bounties_paid")
	bounty = { "run": int(bounty.run), "outpost": str(bounty.outpost), "state": "" }
	QuestNews.push("bounty_paid", "+%d cr" % pay)
	Story.event("bounty_paid")
	return pay


static func _bounty_job(j: Dictionary) -> Dictionary:
	if str(bounty.get("state", "")) == "":
		_roll_bounty()
	var out := j.duplicate()
	var cfg := Story.bounty_cfg()
	out["text"] = str(cfg.get("offer", "%s %s %s %d")) % [str(bounty.name), Story.outpost_label(str(bounty.outpost)),
		str(bounty.crime), int(bounty.pay)]
	out["pays"] = int(bounty.pay)
	return out


## The next contract: a fresh name, a crime, one of the outposts (the first
## one is the nearest), and the pay (the story's first bounty pays less).
static func _roll_bounty() -> void:
	var cfg := Story.bounty_cfg()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var run := int(bounty.get("run", 0)) + 1
	var key := "npc:bounty/%d" % run
	var crimes: Array = cfg.get("crimes", ["They did something unforgivable."])
	var span: Array = cfg.get("pay", [1800, 3200])
	var first := count("bounties_paid") == 0
	var last := str(bounty.get("outpost", ""))
	var choices := Story.OUTPOSTS.filter(func(o): return o != last)
	if first and general_target():
		# Issue #213: the man who's been giving you jobs is your first assassination.
		bounty = {
			"run": run, "key": "npc:general", "name": str(NpcBrain._read(GENERAL_CARD).get("name", "the general")),
			"crime": str(cfg.get("general_crime", "He runs this port for the Remnant.")),
			"outpost": Story.OUTPOSTS[0], "pay": int(cfg.get("first_pay", 1200)), "state": "rolled", "general": true,
		}
		return
	var who := NameHooks.person(Story.target_naming(), key)
	bounty = {
		"run": run, "key": key, "name": who if who != "" else "the officer",
		"crime": str(crimes[rng.randi() % crimes.size()]),
		"outpost": Story.OUTPOSTS[0] if first else str(choices[rng.randi() % choices.size()]),
		"pay": int(cfg.get("first_pay", 1200)) if first else rng.randi_range(int(span[0]), int(span[1])),
		"state": "rolled",
	}


static func _start_bounty(j: Dictionary) -> bool:
	if j.is_empty() or str(bounty.get("state", "")) != "rolled":
		return false
	bounty.state = "out"
	bump("bounties_taken")
	log_event("Took a contract on " + str(bounty.name) + ".")
	return true


# ------------------------------------------------------------------ rumors

static func all_rumors() -> Array:
	if _rumors.is_empty():
		var da := DirAccess.open(RUMOR_DIR)
		if da != null:
			for f in da.get_files():
				if f.ends_with(".json"):
					var d = _read_json(RUMOR_DIR + "/" + f)
					if d is Dictionary and d.has("rumors"):
						_rumors.append_array(d.rumors)
	return _rumors


## Rumors whose conditions hold right now, for a trust tier. Unknown ones first,
## then by weight, at most `limit`.
static func rumors(tier: String, known: Array = [], limit: int = 4) -> Array:
	var ok: Array = []
	for r in all_rumors():
		if _conditions_hold(r.get("requires", {}), tier):
			ok.append(r)
	ok.sort_custom(func(a, b):
		var ka := known.has(a.id)
		var kb := known.has(b.id)
		if ka != kb:
			return not ka
		return float(a.get("weight", 1)) > float(b.get("weight", 1)))
	return ok.slice(0, limit)


const TIERS := ["stranger", "regular", "trusted", "confidant"]


## requires: { flags: [..], not_flags: [..], tier: "regular", story: "<chapter reached>",
##   standing: { faction: [min, max] }, counters: { name: min }, time: [..],
##   mode: "story" or "freeplay" (only in that kind of save) }
static func _conditions_hold(req: Dictionary, tier: String) -> bool:
	if req.has("mode") and str(req.mode) != mode:
		return false
	if req.has("story") and not Story.reached(str(req.story)):
		return false
	for f in req.get("flags", []):
		if not flags.has(str(f)):
			return false
	for f in req.get("not_flags", []):
		if flags.has(str(f)):
			return false
	if req.has("tier") and TIERS.find(tier) < TIERS.find(str(req.tier)):
		return false
	var st: Dictionary = req.get("standing", {})
	for fac in st:
		var v := int(standing.get(fac, 0))
		var rng: Array = st[fac]
		if v < int(rng[0]) or v > int(rng[1]):
			return false
	var cs: Dictionary = req.get("counters", {})
	for c in cs:
		if count(str(c)) < int(cs[c]):
			return false
	var times: Array = req.get("time", [])
	if not times.is_empty() and not times.has(time_of_day):
		return false
	return true


## "hostile" is where the Remnant's troopers shoot on sight: below the gate's
## "search" band (gate_guard.json), as the status HUD's standing_word says.
static func standing_label(v: int) -> String:
	if v <= -40:
		return "hostile"
	if v <= -15:
		return "unfriendly"
	if v < 15:
		return "neutral"
	if v < 50:
		return "friendly"
	return "allied"


# ------------------------------------------------------------------ save

static func to_save() -> Dictionary:
	return {
		"standing": standing.duplicate(), "flags": flags.duplicate(), "counters": counters.duplicate(),
		"events": events.duplicate(true), "credits": credits, "time_of_day": time_of_day,
		"day_pick": day_pick, "day_step": day_step, "day_moved_at": day_moved_at,
		"jobs_taken": jobs_taken.duplicate(), "clock": clock,
		"inventory": inventory.to_save(),
		"names": names.to_save(),
		"smuggle": smuggle.duplicate(true),
		"droids": droids.to_save(),
		"hangar": hangar,
		"story": story.duplicate(),
		"bounty": bounty.duplicate(),
		"ships_destroyed": ships_destroyed.duplicate(),
		"speeder_fits": speeder_fits.duplicate(true),
		"native_packs": native_packs.duplicate(true),
		"native_camps": native_camps.duplicate(true),
		"game_hours": game_hours,
		"mode": mode,
		"quests": quests.duplicate(true),
		"ship_fits": ship_fits.duplicate(true),
		"wreck_ship": wreck_ship,
		"kept_ships": kept_ships.duplicate(true),
		"ship_spots": ship_spots.duplicate(true),
		"primary_ship": primary_ship,
		"gear_fits": gear_fits.duplicate(),
		"control": control.duplicate(true),
		"heist": heist.duplicate(true),
		"map_waypoint": map_waypoint.duplicate(),
		"objective_pin": objective_pin,
	}


static func from_save(d: Dictionary) -> void:
	reset()
	standing = d.get("standing", DEFAULT_STANDING).duplicate()
	flags = d.get("flags", {}).duplicate()
	counters = d.get("counters", {}).duplicate()
	events = d.get("events", []).duplicate(true)
	credits = int(d.get("credits", 60))
	time_of_day = str(d.get("time_of_day", "golden"))
	day_pick = str(d.get("day_pick", "auto"))          # issue #381: older saves are on Auto
	day_step = int(d.get("day_step", 0))
	day_moved_at = float(d.get("day_moved_at", 0.0))
	jobs_taken = d.get("jobs_taken", {}).duplicate()
	clock = float(d.get("clock", 0.0))
	inventory = Inventory.new()
	inventory.from_save(d.get("inventory", {}))
	if inventory.is_taken("pit_jetpack"):
		set_flag("pit_jetpack_taken")      # issue #64: saves from before the flag
	names = NameBook.new()
	names.from_save(d.get("names", {}))
	smuggle = d.get("smuggle", {}).duplicate(true)
	droids = DroidRoster.new()
	droids.from_save(d.get("droids", {}))
	hangar = str(d.get("hangar", ""))
	story = d.get("story", {}).duplicate()
	if story.has("chapter"):
		story.chapter = Story.renamed(str(story.chapter))     # issue #215: chapters renamed since
	if not d.has("story"):
		smuggle = {}           # issue #64: a save from before the story; its old drop goes with it
	bounty = d.get("bounty", {}).duplicate()
	ships_destroyed = d.get("ships_destroyed", []).duplicate()
	speeder_fits = d.get("speeder_fits", []).duplicate(true)
	native_packs = d.get("native_packs", {}).duplicate(true)
	native_camps = d.get("native_camps", {}).duplicate(true)
	game_hours = float(d.get("game_hours", 0.0))
	mode = STORY if str(d.get("mode", FREEPLAY)) == STORY else FREEPLAY    # issue #200: older saves are freeplay
	quests = d.get("quests", {}).duplicate(true)
	ship_fits = d.get("ship_fits", {}).duplicate(true)
	wreck_ship = str(d.get("wreck_ship", ""))
	kept_ships = d.get("kept_ships", []).duplicate(true)
	ship_spots = d.get("ship_spots", {}).duplicate(true)
	primary_ship = str(d.get("primary_ship", ""))
	gear_fits = d.get("gear_fits", []).duplicate()
	control = d.get("control", {}).duplicate(true)
	heist = d.get("heist", {}).duplicate(true)
	map_waypoint = d.get("map_waypoint", {}).duplicate()
	objective_pin = str(d.get("objective_pin", ""))
	if mode == FREEPLAY and str(story.get("chapter", "")) == "free" and not has_flag(FREE_SHIP_GONE):
		set_flag(FREE_SHIP)    # a free roam save from before its interceptor was yours (Fleet.FREE)
	if story.has("chapter"):
		Story.catch_up()       # the general dead in a save from when the fleet chapter waited on a dogfight


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


# ------------------------------------------------------------------ native packs (issue #96)

## What pack `id` thinks of the player, made the first time it is asked from the
## pack's own data (its starting attitude). Reputation is per pack, never shared,
## and has nothing to do with the player's standing with the Remnant.
static func native_pack(id: String, attitude: String = "friendly") -> Dictionary:
	if not native_packs.has(id):
		native_packs[id] = { "rep": 0, "friendly": attitude == "friendly", "locked": false, "trades": 0, "kills": 0 }
	return native_packs[id]


## A pack's camp: when it was wrecked (game hours, -1 = standing) and when each of
## its tents' boxes was emptied. Made the first time it is asked.
static func native_camp(id: String) -> Dictionary:
	if not native_camps.has(id):
		native_camps[id] = { "wrecked_h": -1.0, "looted": {} }
	return native_camps[id]
