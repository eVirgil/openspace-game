class_name DroidController
extends Node3D
## Companion droids in the town (issue #51). The node over the pure DroidRoster
## (WorldState.droids):
##   - your droids follow you on foot, vanish while you fly the ship and come
##     back beside you when you climb out,
##   - an assassin droid of yours shoots whoever the town is fighting you with,
##     and so does a floating droid of yours, with its smaller gun: the Remnant,
##     the port's locals once their alarm is up, a native pack on the attack
##     (anything you are in a fight with; enemies()). What they hit or kill counts
##     as yours (by_player),
##   - a cargo droid holds items the gate never searches ([E] near it),
##   - the droid merchant in the market buys and sells all three kinds,
##   - broken droids turn up in the desert now and then; [E] and ten seconds
##     beside one fixes it, and it follows you,
##   - the range remote follows you once you block its bolts five times in a row,
##   - the Remnant's own two droids patrol the main street, call the alarm and
##     fight when the garrison would,
##   - issue #64: each desert outpost keeps an assassin droid walking round it
##     (RemnantOutposts.droid_specs). Destroyed Remnant droids come back like the
##     troopers do (behind the barracks / at their outpost); after the fleet is
##     beaten the town's two are gone and the outposts' shoot on sight.
##   - issue #76: and a floating droid and a cargo droid (droids.json
##     remnant.outpost_units). When the outpost's alarm goes up the cargo droid
##     runs off into the desert and is left there broken: a wreck to fix and keep.
##   - issue #187: the locals' white assassin droids (droids.json "locals"), in the
##     same list: one at each outpost the locals hold, two on the main street once
##     they hold the barracks. They answer to the locals' alarm (Townsfolk), not the
##     garrison's, and leave you alone until you hurt a local or shoot one.
##   - issue #148: what is left of the Remnant aboard the crashed starcruiser
##     patrols its bridge and hold and shoots on sight, answering to no garrison,
##     and an old cargo droid in its deep hold carries a red energy saber.
##   - the droid merchant also upgrades your droids (DroidRoster.upgrade): more
##     health, a bigger cargo hold (a cargo droid starts with two slots), a
##     harder-hitting gun. Your droids take hits from whoever you are fighting; one
##     at 0 hp is knocked out a while, then reboots,
##   - in a fight your assassin and floating droids walk up to ten steps toward
##     what they see (their kind's "engage"), and come back to you once it is dead.
##   - issue #402: in a LAN guest's town on the host's planet (TownDemo.lan_shared)
##     the Remnant's droids, the locals' and the haulers are the host's: none are
##     built or think here (net_copy); NetWorld makes copies (net_unit) and moves
##     them, and a hit on one goes to the host's game (net_hit). Every other
##     player's droids walk here too, as pictures (net_picture).
## Up to max_owned droids: a fourth asks which one to sell to make room.
## Words, prices and tuning: content/core/droids/droids.json. Looks: DroidKit.
##
## The headless test calls interact() and the menu's choose() directly: the same
## code path as the keys.

const BoltScene := preload("res://scenes/entities/bolt.tscn")
const DROID_LAYER := 2              ## bolts' sweep rays find them; bodies walk through them
const TRAIL_STEP_S := 0.25          ## how often your trail drops a point
const REJOIN_LAG_S := 5.0           ## a lost droid turns up where you were this long ago...
const REJOIN_MAX := 25.0            ## ...or nearer, if that is further back than this (m)
const BLOCK_PROBE_H := 0.5          ## an engaged droid looks for walls this high off the ground (m)...
const BLOCK_PROBE_R := 0.4          ## ...this far past its next step (about half a body)

signal unit_down(u: DroidUnit, sweep: Vector3)   ## one of the Remnant's (or the locals') died; sweep INF: it ran off

var demo                            ## the town scene (town, terrain, garrison, npcs, training_range)
var player: CharacterBody3D
var gear: GearController            ## for its HUD (prompt, toast) and its focus (E is shared)
var ground_at := Callable()         ## (x, z) -> sand height (flat worlds, and the wrecks' placing)
## Issue #93: the world's ground (the ship's). On the home planet's ball the droids stand on
## its height_above / surface_below along the ground's up, never the flat (x, z) line.
var ground: WorldGround
var cfg: Dictionary = {}
var labels: Dictionary = {}
var menu: DroidMenu
var companions: Dictionary = {}     ## uid -> DroidUnit (yours, following)
const LENT_UID := -310               ## issue #310: a borrowed droid's uid (never a roster uid)
var lent: Dictionary = {}            ## issue #310: the droid a heist lends you: { kind, variant } ({} = none)
var lent_down := false               ## ... it was knocked out: it is gone for this heist
var wreck_nodes: Dictionary = {}    ## uid -> DroidUnit (broken, in the desert)
var remnant: Array = []             ## DroidUnit (the Remnant's patrol, and issue #187 the locals')
var vendor_pos := Vector3.INF
var vendor_face := Vector3.ZERO     ## issue #80: the way the droid merchant faces (the aisle); behind = the other way
var vendor_sites: Array = []        ## town stall plus independent planet relays
var focus: Dictionary = {}          ## what E would act on: { kind: "vendor"|"wreck"|"cargo"|"lasers", uid }
var site_i := -1                    ## issue #392: the stall whose menu is open (vendor_sites index)
var fixing: Dictionary = {}         ## { uid, left }
var rng := RandomNumberGenerator.new()
var shots_fired := 0
var stranded := 0                   ## issue #76: outpost cargo droids that ran off and broke down
var _wreck_clock := 0.0
var _heading := Vector3.FORWARD
var _follow_t := 0.0
var _trail: Array = []              ## [[_follow_t, player position], ...], newest last: where a lost droid rejoins
var _mats: LookMaterials
var _was_locked := false
var net_copy := false               ## issue #402: the host's game runs this town's droids (see the top)
var net_hit := Callable()           ## (u, amount, shooter, sweep): a hit on a copy, for the host's game


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "Droids"
	cfg = DroidRoster.config()
	labels = cfg.get("labels", {})
	_mats = LookMaterials.new()
	rng.randomize()
	menu = DroidMenu.new()
	add_child(menu)
	if gear != null and gear.ground_at.is_valid():
		ground_at = gear.ground_at
	if ground == null and demo != null and "pilot" in demo and demo.pilot != null:
		ground = demo.pilot.ground
	if demo != null and "town" in demo and demo.town != null:
		var v: Dictionary = cfg.get("vendor", {})
		if not demo.town.get_marker(str(v.get("marker", ""))).is_empty():
			var off: Array = v.get("offset", [0, 0, 0])
			var town_pos: Vector3 = demo.town.marker_pos(str(v.marker)) + Vector3(float(off[0]), float(off[1]), float(off[2]))
			var vm: Dictionary = demo.town.get_marker(str(v.marker))
			var face := Vector3.ZERO
			if vm.has("face"):
				face = Vector3(float(vm.face[0]) - town_pos.x, float(vm.face[1]) - town_pos.y,
					float(vm.face[2]) - town_pos.z)
				var up := _up(town_pos)
				face = (face - up * face.dot(up)).normalized()
			vendor_sites.append({ "id": "port_market", "pos": town_pos, "face": face,
				"label": str(v.get("label", "Droid Merchant")) })
			vendor_pos = town_pos
			vendor_face = face
	# Issue #392: the moon rave's droid merchant (its own stock, and the laser rig).
	var cv: Dictionary = cfg.get("club_vendor", {})
	if demo != null and "town" in demo and demo.town != null and not cv.is_empty() \
			and not demo.town.get_marker(str(cv.get("marker", ""))).is_empty():
		var at: Vector3 = demo.town.marker_pos(str(cv.marker))
		var cm: Dictionary = demo.town.get_marker(str(cv.marker))
		var cface := Vector3.ZERO
		if cm.has("face"):
			cface = Vector3(float(cm.face[0]) - at.x, 0.0, float(cm.face[2]) - at.z).normalized()
		var g := gear
		vendor_sites.append({ "id": str(cv.get("id", "droid_merchant_club")), "pos": at, "face": cface,
			"label": str(cv.get("label", "Droid Merchant")), "stock": cv.get("stock", []), "sells": str(cv.get("sells", "")),
			"open": func() -> bool: return g == null or g.is_open(cv) })
	if demo != null and "droid_merchant_outposts" in demo and demo.droid_merchant_outposts != null:
		for site in demo.droid_merchant_outposts.sites:
			vendor_sites.append(site)
	if demo != null and "ranches" in demo and demo.ranches != null:
		for site in demo.ranches.droid_sites:        # a ranch village's droid stand
			vendor_sites.append(site)
	net_copy = demo != null and "lan_shared" in demo and bool(demo.lan_shared)
	if _on_ball() and not roster().wrecks_seeded:
		var starting_count := int(cfg.get("wrecks", {}).get("ball_starting_count", 8))
		while roster().wrecks.size() < starting_count:
			if _roll_wreck(true).is_empty():
				break
		roster().wrecks_seeded = true
	for w in roster().wrecks:
		_build_wreck(w)
	if not net_copy:
		_build_remnant()
		_build_hauler()
	if demo != null and "training_range" in demo and demo.training_range != null:
		demo.training_range.remote_tamed.connect(_on_remote_tamed)


func roster() -> DroidRoster:
	return WorldState.droids


func _l(key: String) -> String:
	return str(labels.get(key, key))


# ------------------------------------------------------------------ frame

## Issue #538: physics rays this controller has cast (clear shots and ground
## points), for probes counting them.
var rays := 0
## Issue #538: who you are fighting, rebuilt every ENEMIES_EVERY_S and shared by
## every companion that tick (enemies() walks every NPC, local and pack member).
const ENEMIES_EVERY_S := 0.25
## How often a companion looks again for the nearest enemy it can hit (a target
## keeps its clear shot until then), and how many of the nearest it ray-checks.
const AIM_EVERY_S := 0.2
const AIM_RAYS := 3
var _enemies: Array = []
var _enemies_left := 0.0
var _aim_left := {}                  ## companion uid -> seconds to its next look
var _player_off_index := false       ## the player stands on something the height index does not know (a deck, a hull)


## Issue #538: true once every `every` seconds, by a countdown the caller keeps
## in `timers[key]` (the pattern for the other per-tick systems to copy).
static func _tick_every(timers: Dictionary, key, every: float, dt: float) -> bool:
	var left := float(timers.get(key, 0.0)) - dt
	if left > 0.0:
		timers[key] = left
		return false
	timers[key] = left + every if left > -every else every
	return true


func _physics_process(dt: float) -> void:
	if player == null:
		return
	_player_off_index = _off_index(player.global_position)
	if player.piloting:
		_despawn_companions()          # they wait while you fly
		_trail.clear()
		fixing = {}
		focus = {}
	else:
		_sync_companions()
		_tick_knocked_out(dt)
		_follow(dt)
		_companion_guns(dt)
		_tick_fix(dt)
		_tick_focus()
	if not net_copy:
		_remnant_step(dt)
	_hauler_step(dt)
	_tick_wrecks(dt)
	_chirps(dt)


## Ten seconds beside a wreck fixes it; walking off cancels.
func _tick_fix(dt: float) -> void:
	if fixing.is_empty():
		return
	var n: DroidUnit = wreck_nodes.get(int(fixing.uid))
	if n == null or _flat_dist(n.global_position, player.global_position) > float(cfg.get("fix_reach", 2.6)) + 1.0:
		if n != null and gear != null and gear.hud != null:
			gear.hud.toast(_l("fix_cancelled") % DroidRoster.label(n.kind).to_lower())
		fixing = {}
		return
	fixing.left = float(fixing.left) - dt
	if float(fixing.left) <= 0.0:
		_finish_fix(int(fixing.uid))


func _tick_focus() -> void:
	if menu.is_open():
		return
	if _was_locked:
		player.locked = false
		_was_locked = false
	focus = {} if (gear != null and not gear.focus.is_empty()) else _find_focus()
	var text := prompt_text()
	if text != "" and gear != null and gear.hud != null:
		gear.hud.set_prompt(text)
	if not player.locked and focus.size() > 0 and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		interact()


func _find_focus() -> Dictionary:
	var p := player.global_position
	var closest := -1
	var distance := float(cfg.get("vendor", {}).get("reach", 3.5))
	for i in vendor_sites.size():
		if not _vendor_site_open(i):
			continue
		var pos: Vector3 = vendor_sites[i].pos
		var up := _up(pos)
		var d := _flat_dist(p, pos)
		if d <= distance and absf((p - pos).dot(up)) <= 2.0:
			closest = i
			distance = d
	if closest >= 0:
		return { "kind": "vendor", "site": closest }
	for uid in wreck_nodes:
		if _flat_dist(p, wreck_nodes[uid].global_position) <= float(cfg.get("wrecks", {}).get("reach", 3.0)):
			return { "kind": "wreck", "uid": uid }
	for uid in companions:
		var d := roster().find(uid)
		if bool(DroidRoster.kind_cfg(str(d.get("kind", ""))).get("carries", false)) \
				and _flat_dist(p, companions[uid].global_position) <= 2.4:
			return { "kind": "cargo", "uid": uid }
	for uid in companions:              # issue #392: a droid of yours with the laser rig
		var d := roster().find(uid)
		if DroidRoster.has_lasers(d) and not companions[uid].dead \
				and _flat_dist(p, companions[uid].global_position) <= 2.4:
			return { "kind": "lasers", "uid": uid }
	return {}


func _vendor_open() -> bool:
	if gear == null:
		return true
	return gear.is_open(cfg.get("vendor", {}))


func _vendor_site_open(site: int) -> bool:
	if site >= 0 and site < vendor_sites.size() \
			and str(vendor_sites[site].get("id", "")).begins_with("droid_post_"):
		return true
	if site >= 0 and site < vendor_sites.size() and vendor_sites[site].get("open") is Callable:
		return bool((vendor_sites[site].open as Callable).call())   # a ranch's stand: its keeper's
	return _vendor_open()


func prompt_text() -> String:
	if not fixing.is_empty():
		var n: DroidUnit = wreck_nodes.get(int(fixing.uid))
		var total := float(cfg.get("fix_seconds", 10.0))
		if n != null:
			return _l("fixing") % [DroidRoster.label(n.kind).to_lower(), int(100.0 * (1.0 - float(fixing.left) / total))]
	match str(focus.get("kind", "")):
		"vendor":
			return _l("trade") % _vendor_label(int(focus.get("site", -1))).to_lower()
		"wreck":
			var w := roster().find_wreck(int(focus.uid))
			return _l("fix") % [DroidRoster.label(str(w.get("kind", ""))).to_lower(), int(cfg.get("fix_seconds", 10.0))]
		"cargo":
			return _l("hold")
		"lasers":
			var d := roster().find(int(focus.uid))
			return _l("lasers_off" if DroidRoster.lasers_on(d) else "lasers_on") % droid_name(d).to_lower()
	return ""


# ------------------------------------------------------------------ actions

## Act on whatever is in reach. Returns "menu", "fixing", or "".
func interact() -> String:
	if focus.is_empty():
		focus = _find_focus()
	match str(focus.get("kind", "")):
		"vendor":
			_select_vendor(int(focus.get("site", -1)))
			_open_trade(int(focus.get("site", -1)))
			return "menu"
		"wreck":
			var uid := int(focus.uid)
			if roster().is_full():
				_ask_make_room(func(): start_fix(uid))
				return "menu"
			return "fixing" if start_fix(uid) else ""
		"cargo":
			var opts := hold_options(int(focus.uid))
			if opts.is_empty():
				_toast(_l("empty_hold"))
				return ""
			_open_hold(int(focus.uid), opts)
			return "menu"
		"lasers":
			return "lasers_on" if toggle_lasers(int(focus.uid)) else "lasers_off"
	return ""


func _vendor_label(site: int) -> String:
	if site >= 0 and site < vendor_sites.size():
		return str(vendor_sites[site].get("label", "Droid Merchant"))
	return str(cfg.get("vendor", {}).get("label", "Droid Merchant"))


func _select_vendor(site: int) -> void:
	if site < 0 or site >= vendor_sites.size():
		return
	site_i = site
	vendor_pos = vendor_sites[site].pos
	vendor_face = vendor_sites[site].face


func _open_menu(title: String, opts: Array, pick: Callable, keep_cursor := false) -> void:
	menu.open(title, opts, pick, "", keep_cursor)
	if not player.locked:
		player.locked = true
		_was_locked = true


## Issue #392: the stall whose menu is open ({} = the market's, as before).
func _site() -> Dictionary:
	return vendor_sites[site_i] if site_i >= 0 and site_i < vendor_sites.size() else {}


func trade_options() -> Array:
	var out := []
	for kind in _site().get("stock", cfg.get("vendor", {}).get("stock", [])):
		out.append({ "id": "buy:" + str(kind), "text": _l("buy") % [DroidRoster.label(str(kind)), price_here(str(kind))] })
	if not roster().owned.is_empty():
		out.append({ "id": "upgrades", "text": _l("upgrades") })
	for d in roster().owned:
		out.append({ "id": "sell:%d" % int(d.uid), "text": _l("sell") % [DroidRoster.label(str(d.kind)), DroidRoster.resale(str(d.kind))] })
	# Issue #212: at a desert post, Oda's friend takes the droids she asked for.
	# They close her job, so they go first, marked "job" (green, the cursor on them).
	var want := Story.droid_wanted_kind()
	if want != "" and _at_post():
		var job_rows := []
		for d in roster().owned:
			if str(d.kind) == want:
				job_rows.append({ "id": "deliver:%d" % int(d.uid), "job": true,
					"text": _l("deliver") % [DroidRoster.label(want), Story.droids_wanted()] })
		out = job_rows + out
	return out


## The menu is open at one of the desert droid posts (not the market stall).
func _at_post() -> bool:
	for s in vendor_sites:
		if str(s.get("id", "")).begins_with("droid_post_") and s.pos == vendor_pos:
			return true
	return false


## keep_cursor: open again after a buy or a sale, the cursor where it was.
func _open_trade(site: int, keep_cursor := false) -> void:
	var title := _l("menu_trade") % [_vendor_label(site), WorldState.credits, roster().owned.size(), DroidRoster.max_owned()]
	if keep_cursor:
		menu.open(title, trade_options(), _on_trade.bind(site), "", true)
	else:
		_open_menu(title, trade_options(), _on_trade.bind(site))


## A buy or a sale leaves the stall open (Esc walks away).
func _on_trade(id: String, site: int) -> void:
	if id.begins_with("buy:"):
		buy(id.substr(4))
	elif id.begins_with("sell:"):
		sell(int(id.substr(5)))
	elif id.begins_with("deliver:"):
		deliver(int(id.substr(8)))
	elif id == "upgrades":
		open_upgrades()
		return                                # its own menu, not the stall's again
	if id != "":
		_open_trade(site, true)


# ------------------------------------------------------------------ upgrades

## "Cargo droid", or "Cargo droid 2" when you run more than one of a kind.
func droid_name(d: Dictionary) -> String:
	var same: Array = roster().owned.filter(func(o): return str(o.kind) == str(d.kind))
	var label := DroidRoster.label(str(d.kind))
	return label if same.size() < 2 else "%s %d" % [label, same.find(d) + 1]


## Every upgrade the merchant can still fit, droid by droid.
func upgrade_options() -> Array:
	var out := []
	for d in roster().owned:
		for key in DroidRoster.upgrades_for(str(d.kind), str(_site().get("sells", ""))):
			var price := DroidRoster.upgrade_price(d, str(key))
			if price < 0:
				continue
			out.append({ "id": "up:%d:%s" % [int(d.uid), key], "text": _l("upgrade") % [droid_name(d),
				DroidRoster.upgrade_label(str(key)), price] })
	return out


func open_upgrades() -> void:
	var opts := upgrade_options()
	if opts.is_empty():
		_toast(_l("nothing_to_upgrade"))
		return
	_open_menu(_l("menu_upgrades") % WorldState.credits, opts, func(id: String):
		if id.begins_with("up:"):
			var parts := id.split(":")
			if upgrade(int(parts[1]), parts[2]) == "upgraded":
				open_upgrades())         # buy another without walking off and back


## Fit the next level of `key` to droid `uid`. Returns "upgraded", "cant_afford",
## "maxed" or "". A droid out in the world takes its new health at once.
func upgrade(uid: int, key: String) -> String:
	var d := roster().find(uid)
	var r := roster().upgrade(uid, key, WorldState.credits)
	match str(r.get("error", "")):
		"cant_afford":
			_toast(_l("upgrade_cant_afford") % [DroidRoster.upgrade_label(key), DroidRoster.upgrade_price(d, key), WorldState.credits])
			return "cant_afford"
		"maxed":
			return "maxed"
		"unknown":
			return ""
	WorldState.credits -= int(r.cost)
	var u: DroidUnit = companions.get(uid)
	if u != null and not u.dead and u.variant != str(d.variant):
		# Its first upgrade: it comes back from the merchant's bench in the shiny look.
		var at := u.global_position
		var yaw := u.yaw
		_free_companion(uid)
		u = _spawn_companion(d, at)
		u.yaw = yaw
		_orient(u)
	elif u != null and not u.dead:
		var was := u.max_hp
		u.max_hp = DroidRoster.health(d)
		u.hp += u.max_hp - was
	_toast(_l("upgraded") % [droid_name(d), DroidRoster.upgrade_label(key)])
	_beep(u)
	return "upgraded"


## Issue #212: hand a droid over for Oda's friend (no pay: it is a favour to
## her). Its cargo comes back to your pockets. Returns true when it went.
func deliver(uid: int) -> bool:
	var d := roster().find(uid)
	if d.is_empty() or str(d.kind) != Story.droid_wanted_kind():
		return false
	if not roster().cargo_fits(uid, WorldState.inventory):
		_toast(_l("hold_wont_fit"))
		return false
	roster().unload(uid, WorldState.inventory)
	roster().remove(uid)
	_free_companion(uid)
	Story.on_droid_delivered()
	_toast(_l("delivered") % [DroidRoster.label(str(d.kind)), Story.droids_wanted()])
	return true


## Issue #303: a droid's price at the stall that is open: the desert posts deal
## cheaply with friends of the Remnant, the port's market with friends of the locals.
func price_here(kind: String) -> int:
	return DarkPact.droid_price(kind, _at_post())


## Buy a droid from the merchant. Returns "bought", "full", "cant_afford" or "".
func buy(kind: String) -> String:
	var r := roster().buy(kind, DroidRoster.pick_variant(kind, rng), WorldState.credits, price_here(kind))
	match str(r.get("error", "")):
		"full":
			_toast(_l("full") % DroidRoster.max_owned())
			return "full"
		"cant_afford":
			_toast(_l("cant_afford") % [DroidRoster.label(kind), price_here(kind), WorldState.credits])
			return "cant_afford"
		"unknown":
			return ""
	WorldState.credits -= int(r.cost)
	WorldState.log_event(_l("event_bought") % DroidRoster.label(kind).to_lower())
	var at := vendor_pos if vendor_pos != Vector3.INF else player.global_position
	if vendor_pos != Vector3.INF and vendor_face != Vector3.ZERO:
		# Issue #80: it comes out from the back of the stall and walks round to you.
		var v: Dictionary = cfg.get("vendor", {})
		var back := -vendor_face * float(v.get("spawn_behind", 2.6))
		var up := _up(vendor_pos)
		var side := vendor_face.cross(up).normalized() * float(v.get("walk_round", 3.4))
		if side.dot(player.global_position - vendor_pos) < 0.0:
			side = -side                       # round the side nearer the player
		at = vendor_pos + back
		var u := _spawn_companion(r.droid, at)
		u.via = [at + side, vendor_pos + side + vendor_face * 2.0]
		u.following = true
	else:
		_spawn_companion(r.droid, at)
	_toast(_l("bought") % [DroidRoster.label(kind), int(r.cost)])
	return "bought"


## Sell one of your droids at the merchant's price. It leaves (de-spawns); what
## a cargo droid carried goes back in your pockets first. Returns the price or -1.
func sell(uid: int) -> int:
	var d := roster().find(uid)
	if d.is_empty():
		return -1
	if not roster().cargo_fits(uid, WorldState.inventory):
		_toast(_l("hold_wont_fit"))      # never sell what you are carrying out from under you
		return -1
	var moved := roster().unload(uid, WorldState.inventory)
	var price := roster().sell(uid)
	WorldState.credits += price
	_free_companion(uid)
	var msg := _l("sold") % [DroidRoster.label(str(d.kind)), price]
	if moved > 0:
		msg += "  " + _l("unloaded_on_sale") % moved
	_toast(msg)
	return price


## At the cap: pick one droid to sell (merchant price) and then `then` runs.
## Walking away runs `declined` instead.
func _ask_make_room(then: Callable, declined := Callable()) -> void:
	var opts := []
	for d in roster().owned:
		opts.append({ "id": str(d.uid), "text": _l("sell") % [DroidRoster.label(str(d.kind)), DroidRoster.resale(str(d.kind))] })
	_open_menu(_l("make_room") % DroidRoster.max_owned(), opts, _on_make_room.bind(then, declined))


func _on_make_room(id: String, then: Callable, declined: Callable) -> void:
	if id != "" and sell(int(id)) >= 0:
		then.call()
	elif declined.is_valid():
		declined.call()


## A cargo droid's hold menu. keep_cursor: reopened after a stash, so you can stash
## one more without starting over.
func _open_hold(uid: int, opts: Array, keep_cursor := false) -> void:
	var d := roster().find(uid)
	_open_menu(_l("menu_hold") % [d.get("cargo", {}).size(), DroidRoster.cargo_slots(d)], opts, _on_hold.bind(uid), keep_cursor)


## Stash what the hold has a slot for (or already holds some of), and unload.
## Enter (or "Stash one") stashes one of a stack; Shift+Enter (or "Stash all") the
## whole stack.
func hold_options(uid: int) -> Array:
	var out := []
	var inv := WorldState.inventory
	var d := roster().find(uid)
	for id in inv.item_ids():
		if not DroidRoster.hold_has_room(d, str(id)):
			continue
		var it: Dictionary = WorldState._item(str(id))
		var row := { "id": "stash:" + str(id), "text": _l("stash") % [str(it.get("label", id)), inv.count(str(id))] }
		if inv.count(str(id)) > 1:
			row["alt"] = "stash_all:" + str(id)
			row["alt_hint"] = _l("stash_all_hint")
			row["buttons"] = [{ "id": "stash:" + str(id), "text": _l("stash_one_button") },
				{ "id": "stash_all:" + str(id), "text": _l("stash_all_button") }]
		else:
			row["buttons"] = [{ "id": "stash:" + str(id), "text": _l("stash_button") }]
		out.append(row)
	var held: Array = []
	for id in d.get("cargo", {}):
		held.append("%s x%d" % [str(WorldState._item(str(id)).get("label", id)), int(d.cargo[id])])
	if not held.is_empty():
		out.append({ "id": "unload", "text": _l("unload") % ", ".join(held) })
	return out


func _on_hold(id: String, uid: int) -> void:
	if id == "unload":
		var moved := roster().unload(uid, WorldState.inventory)
		var left := 0
		for n in roster().find(uid).get("cargo", {}).values():
			left += int(n)
		_toast(_l("unloaded") % moved if left == 0 else _l("unload_partial") % left)
	elif id.begins_with("stash:") or id.begins_with("stash_all:"):
		var all := id.begins_with("stash_all:")
		var item := id.substr(id.find(":") + 1)
		var d := roster().find(uid)
		var n := WorldState.inventory.count(item) if all else 1
		var label := str(WorldState._item(item).get("label", item))
		if n > 0 and roster().stash(uid, WorldState.inventory, item, n):
			_toast(_l("stashed_many") % [n, label] if n > 1 else _l("stashed") % label)
			if gear != null:
				gear.sync_gear()        # a stashed jetpack comes off your back
			var opts := hold_options(uid)
			if not opts.is_empty():
				_open_hold(uid, opts, true)     # stay open: stash the next one
		elif not DroidRoster.hold_has_room(d, item):
			_toast(_l("hold_full") % [d.get("cargo", {}).size(), DroidRoster.cargo_slots(d)])
	_beep(companions.get(uid))


# ------------------------------------------------------------------ wrecks

func start_fix(uid: int) -> bool:
	if not wreck_nodes.has(uid) or roster().is_full():
		return false
	fixing = { "uid": uid, "left": float(cfg.get("fix_seconds", 10.0)) }
	Sound.play("droid_fix", wreck_nodes[uid].global_position)
	return true


func _finish_fix(uid: int) -> void:
	fixing = {}
	var n: DroidUnit = wreck_nodes.get(uid)
	var d := roster().fix_wreck(uid)
	if d.is_empty() or n == null:
		return
	var at := n.global_position
	wreck_nodes.erase(uid)
	n.queue_free()
	var u := _spawn_companion(d, at)
	Sound.play("droid_wake", at)
	_beep(u)
	WorldState.log_event(_l("event_found") % DroidRoster.label(str(d.kind)).to_lower())
	_toast(_l("fixed") % DroidRoster.label(str(d.kind)).to_lower())


## Now and then one more broken droid turns up out in the desert.
func _tick_wrecks(dt: float) -> void:
	_wreck_clock += dt
	if _wreck_clock < float(cfg.get("wrecks", {}).get("check_seconds", 300.0)):
		return
	_wreck_clock = 0.0
	spawn_wreck(false)


## Roll for a wreck now (force: skip the chance). Returns its uid or -1.
func spawn_wreck(force := true) -> int:
	var w := _roll_wreck(force)
	if w.is_empty():
		return -1
	_build_wreck(w)
	return int(w.uid)


func _roll_wreck(force: bool) -> Dictionary:
	if _on_ball():
		var sp := ground.sphere()
		return roster().roll_wreck(rng, Vector3.ZERO, ground_at, force,
			Callable(self, "_wreck_surface_at"), sp.center, sp.radius, Callable(self, "_wreck_spot_clear"))
	return roster().roll_wreck(rng, Vector3.ZERO, ground_at, force)


## The map sampler asks for (x, z); the ball's surface and its landmarks are in
## WorldGround, not the flat terrain-height callback used by the older worlds.
func _wreck_surface_at(x: float, z: float) -> Vector3:
	var sp := ground.sphere()
	var base := sp.surface_at(x, z)
	return ground.surface_below(base + sp.up_at(base) * 200.0)


## Do not leave a wreck on a town/outpost building, a mesa or a boulder.
func _wreck_spot_clear(p: Vector3) -> bool:
	for b in ground.boxes:
		var local: Vector3 = WorldGround.box_xf(b).affine_inverse() * p
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if local.x >= mn.x - 24.0 and local.x <= mx.x + 24.0 \
				and local.z >= mn.z - 24.0 and local.z <= mx.z + 24.0:
			return false
	for c in ground.columns:
		var up: Vector3 = c.get("up", Vector3.UP)
		var rel: Vector3 = p - (c.center as Vector3)
		if (rel - up * rel.dot(up)).length() <= float(c.radius) + 24.0:
			return false
	for b in ground.boulders:
		var up: Vector3 = b.up
		var rel: Vector3 = p - (b.center as Vector3)
		if (rel - up * rel.dot(up)).length() <= float(b.radius) * WorldGround.RAMP_SPREAD + 24.0:
			return false
	return true


func _build_wreck(w: Dictionary) -> void:
	var u := _make_unit(str(w.kind), str(w.variant))
	u.broken = true
	u.uid = int(w.uid)
	add_child(u)
	var at := Vector3(float(w.pos[0]), float(w.pos[1]), float(w.pos[2]))
	u.global_position = ground.surface_below(at + _up(at) * 200.0) if _on_ball() else _ground_point(at)
	w.pos = [u.global_position.x, u.global_position.y, u.global_position.z]
	u.yaw = rng.randf() * TAU
	_orient(u)
	_lay_down(u)
	wreck_nodes[int(w.uid)] = u


## Broken or dead: eyes dark, and down on the sand (the assassin flat on its back).
func _lay_down(u: DroidUnit) -> void:
	DroidKit.set_awake(u.look, false)
	var model := u.look.get_node("Model") as Node3D
	match u.kind:
		"assassin":
			# A rigged assassin plays its fall and stays down; the old look tips over.
			if DroidKit.play_anim(u.look, "die"):
				if u.broken:
					DroidKit.finish_anim(u.look)
				u.shape.rotation.x = PI * 0.5
				u.shape.position = Vector3(0, 0.15, 1.1)
				if u.hum != null:
					u.hum.stop()
				return
			model.rotation.x = PI * 0.5
			model.position.y = 0.12
			u.shape.rotation.x = PI * 0.5
			u.shape.position = Vector3(0, 0.15, 1.1)
		"floating":
			# Issue #80: it drops out of the air (it used to appear on the ground).
			u.falling = true
			var from := u.look.position.y
			var t := sqrt(maxf(0.1, from - 0.25) * 2.0 / 9.8)
			var tw := u.create_tween().set_parallel(true)
			tw.tween_property(u.look, "position:y", 0.25, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(u.shape, "position:y", 0.25, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(model, "rotation:z", 0.5, t)
			tw.chain().tween_callback(func(): Sound.play("droid_beep", u.global_position + Vector3(0, 0.3, 0)))
		"cargo":
			model.rotation.z = 0.35
	if u.hum != null:
		u.hum.stop()


## Cut down by the energy sword: like a guard (NpcBody._go_limp), the droid goes
## flying along the blade's sweep and lifted (ragdoll.json blade_fling, blade_fling_up),
## tumbling end over end, and lands where physics puts it. Its look rides a rigid
## body the shape of its outline (Ragdoll.drop), kept under the unit so a respawn
## clears both.
func _bat(u: DroidUnit, sweep: Vector3) -> void:
	DroidKit.set_awake(u.look, false)
	if u.hum != null:
		u.hum.stop()
	u.falling = true
	if u.kind == "assassin":
		DroidKit.play_anim(u.look, "die")
	var rc := Ragdoll.load_config()
	var up := _up(u.global_position)
	var side := _flat(sweep, up).normalized()
	var fling := side * float(rc.get("blade_fling", 8.0)) + up * float(rc.get("blade_fling_up", 5.5))
	var rb := Ragdoll.drop(u.look, u, fling / maxf(1.0, u.size_scale), rc)
	if rb == null:
		_lay_down(u)
		return
	rb.name = "Batted"
	rb.mass = float(rc.get("droid_mass", 40.0)) * u.size_scale
	rb.gravity_scale = float(rc.get("gravity", 20.0)) / 9.8
	rb.angular_velocity += up.cross(side) * float(rc.get("droid_tumble", 7.0))
	rb.physics_material_override = PhysicsMaterial.new()
	rb.physics_material_override.friction = float(rc.get("friction", 0.6))
	rb.physics_material_override.bounce = float(rc.get("bounce", 0.15))


# ------------------------------------------------------------------ taming

## The range remote wants to follow you (TrainingRange.remote_tamed).
func _on_remote_tamed() -> void:
	if roster().is_full():
		_ask_make_room(_take_remote, _decline_remote)
		return
	_take_remote()


func _decline_remote() -> void:
	roster().streak = 0
	_toast(_l("tame_declined"))


func _take_remote() -> void:
	var xf: Transform3D = demo.training_range.release_remote_transform() if demo != null and demo.training_range != null else Transform3D(Basis.IDENTITY, Vector3.INF)
	var at := xf.origin
	var d := roster().add("floating", "range")
	if d.is_empty():
		return
	# Issue #80: the same droid, where it was: no swap to another look, no jump.
	var u := _spawn_companion(d, at if at != Vector3.INF else player.global_position, at.y if at != Vector3.INF else INF)
	if at != Vector3.INF:
		u.yaw = xf.basis.get_euler().y
		_orient(u)
	_beep(u)
	_toast(_l("tamed"))


# ------------------------------------------------------------------ companions

## Bring every owned droid that has no body yet, beside the player. Issue #310:
## and the one a heist lends you (not in your roster).
func _sync_companions() -> void:
	for d in roster().owned:
		if not companions.has(int(d.uid)):
			_spawn_companion(d, player.global_position - _heading * 2.0)
	if not lent.is_empty() and not lent_down and not companions.has(LENT_UID):
		_spawn_companion(_lent_entry(), player.global_position - _heading * 3.0)
	for uid in companions.keys():
		if uid == LENT_UID:
			if lent.is_empty() or lent_down and not companions[uid].dead:
				_free_companion(uid)
			continue
		if roster().find(uid).is_empty():
			_free_companion(uid)


## Issue #310: lend the player a droid for a heist ({ kind, variant }). It follows
## and fights like one of theirs (the same follow and guns), but is not in the
## roster: no slot, no cargo, no sale. Knocked out it stays down for the heist.
func lend(kind: String, variant: String) -> void:
	if not lent.is_empty() and str(lent.kind) == kind and str(lent.variant) == variant:
		return
	give_back()
	lent = { "kind": kind, "variant": variant }
	lent_down = false


## Issue #310: the heist is over: the borrowed droid goes home.
func give_back() -> void:
	lent = {}
	lent_down = false
	if companions.has(LENT_UID):
		_free_companion(LENT_UID)


func lent_unit() -> DroidUnit:
	return companions.get(LENT_UID)


func _lent_entry() -> Dictionary:
	return { "uid": LENT_UID, "kind": str(lent.kind), "variant": str(lent.variant) }


func _spawn_companion(d: Dictionary, at: Vector3, from_y := INF) -> DroidUnit:
	var u := _make_unit(str(d.kind), str(d.variant))
	u.uid = int(d.uid)
	add_child(u)
	_put(u, at)
	if u.kind == "floating":
		u.look_lift += u.quirk().z * 0.5 - 0.15      # issue #64: not all at one height
		# Issue #80: start at the height it was at (a tamed remote) and ease to its own.
		u.lift_now = (from_y - u.global_position.y) if from_y != INF else u.look_lift
		u.look.position.y = u.lift_now
		u.shape.position.y = u.lift_now
	DroidKit.set_awake(u.look, true)
	if DroidRoster.has_lasers(d):
		_fit_rig(u, DroidRoster.lasers_on(d))
	u.max_hp = DroidRoster.health(d)
	u.hp = u.max_hp
	if int(d.uid) == LENT_UID:
		u.set_meta("lent", true)
	companions[int(d.uid)] = u
	return u


func _free_companion(uid: int) -> void:
	var u: DroidUnit = companions.get(uid)
	companions.erase(uid)
	if u != null and is_instance_valid(u):
		u.queue_free()


func _despawn_companions() -> void:
	for uid in companions.keys():
		_free_companion(uid)


## Each droid holds its ground until the player gets `leash` metres away (its
## kind's "follow"), then walks to its slot beside / behind the player and stops
## there (within `settle` m). It catches up faster when far behind, and if it was
## left a long way back (a jetpack hop, a speeder ride) it turns up on your trail
## some seconds back (_rejoin_point), not at your side, and runs the rest.
func _follow(dt: float) -> void:
	var pup := _up(player.global_position)
	var v := _flat(player.velocity, pup)
	if v.length() > 0.6:
		_heading = v.normalized()
	else:
		# Standing still: keep the last heading, laid back onto the ground's plane here.
		var h := _flat(_heading, pup)
		_heading = h.normalized() if h.length() > 0.01 else _flat(-player.global_basis.z, pup).normalized()
	var right := _heading.cross(pup).normalized()
	_follow_t += dt
	if _trail.is_empty() or _follow_t - float(_trail[-1][0]) >= TRAIL_STEP_S:
		_trail.append([_follow_t, player.global_position])
		while _follow_t - float(_trail[0][0]) > REJOIN_LAG_S + TRAIL_STEP_S:
			_trail.pop_front()
	var of_kind := {}                  # kind -> how many placed so far
	for uid in companions:
		var u: DroidUnit = companions[uid]
		if u.dead:
			continue                          # knocked out: it lies there until it reboots
		var f: Dictionary = DroidRoster.kind_cfg(u.kind).get("follow", {})
		# Issue #64: two of a kind no longer share a slot and march in step. Each
		# takes the next place in a fan behind its kind's slot (alternating sides,
		# further back), drifts a little around it, and has its own pace and
		# reaction time (from its uid), so a group reads as droids, not puppets.
		var k := int(of_kind.get(u.kind, 0))
		of_kind[u.kind] = k + 1
		var me := u.quirk()
		var fan := 0.0 if k == 0 else (1.0 if k % 2 == 1 else -1.0) * ceilf(k / 2.0) * 1.4
		var drift := Vector2(sin(_follow_t * 0.37 + me.x * TAU), cos(_follow_t * 0.29 + me.y * TAU)) * 0.45
		var slot := player.global_position + right * (float(f.get("side", 1.0)) + fan + drift.x) \
			- _heading * (float(f.get("back", 1.5)) + 1.1 * k + drift.y)
		if not u.via.is_empty():
			var wp: Vector3 = u.via[0]
			if _flat_dist(u.global_position, wp) < 0.5:
				u.via.pop_front()
			else:
				slot = wp                         # issue #80: round the stall first
		var to := _flat(slot - u.global_position, _up(u.global_position))
		var dist := to.length()
		var leash := float(f.get("leash", 5.0)) + me.z * 2.0 + 0.8 * k
		if not u.following and _flat_dist(u.global_position, player.global_position) > leash:
			u.wait_left -= dt
			if u.wait_left <= 0.0:
				u.following = true
		else:
			u.wait_left = 0.15 + me.x * 0.6        # a beat before it notices you left
		if u.following and dist <= float(f.get("settle", 0.35)) and u.via.is_empty():
			u.following = false
		var pos: Vector3 = u.global_position
		var speed := 0.0
		if dist > 40.0 and u.via.is_empty():
			var back := _rejoin_point()
			# Keep its place in the group (slot's offset from you) so they do not land in a heap.
			pos = slot if back == Vector3.INF else back + (slot - player.global_position)
			_disengage(u)                     # you walked off: it jumps to you, fight or not
		elif u.engaged != null and is_instance_valid(u.engaged):
			var to_goal := _flat(_advance_goal(u) - pos, _up(pos))
			if to_goal.length() > 0.15:
				var step := to_goal.normalized() * minf(float(f.get("speed", 7.0)) * 0.7 * dt, to_goal.length())
				if not _blocked(u, pos, step):
					speed = float(f.get("speed", 7.0)) * 0.7
					pos += step
			_face(u, u.engaged.global_position - pos)
		elif u.following:
			speed = float(f.get("speed", 7.0)) * (0.85 + me.y * 0.3) * (2.0 if dist > 8.0 else clampf(dist / 1.5, 0.3, 1.0))
			pos += to / dist * minf(speed * dt, dist)
			_face(u, to)
		elif u.target == null:
			_face(u, player.global_position - u.global_position)
		pos += _separation(u, pos) * dt
		_put(u, pos)
		u.walk(dt, u.following or speed > 0.0, speed, u.target != null)


## Where an engaged droid is going: from where it stood when the fight found it,
## toward its enemy, at most its kind's engage.advance (about ten steps) and never
## closer than engage.standoff.
func _advance_goal(u: DroidUnit) -> Vector3:
	var e: Dictionary = DroidRoster.kind_cfg(u.kind).get("engage", {})
	var up := _up(u.engage_from)
	var to := _flat(u.engaged.global_position - u.engage_from, up)
	var reach := minf(float(e.get("advance", 7.5)), maxf(0.0, to.length() - float(e.get("standoff", 3.0))))
	return u.engage_from + (to.normalized() * reach if to.length() > 0.01 else Vector3.ZERO)


## Whether a step from `at` runs u into something (a wall, a crate, a hull): a ray
## at knee height a body's width past the step. An engaged droid that would hit one
## stops where it is and fights from there; once the fight is over it trails back
## to you as usual. Sloped ground (a dune, a ramp) does not count.
func _blocked(u: DroidUnit, at: Vector3, step: Vector3) -> bool:
	if not is_inside_tree() or step.length() < 0.001:
		return false
	var up := _up(at)
	var from := at + up * BLOCK_PROBE_H
	var q := PhysicsRayQueryParameters3D.create(from, from + step + step.normalized() * BLOCK_PROBE_R, 1)
	q.exclude = [u.get_rid(), player.get_rid()] if player != null else [u.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and (hit.normal as Vector3).dot(up) < 0.7


## Go after what it sees (a kind with "engage"), keep after it while it lives, and
## head back to you once it is dead or out of the fight with nobody else in sight.
func _engage(u: DroidUnit, cands: Array) -> void:
	if DroidRoster.kind_cfg(u.kind).get("engage", {}).is_empty():
		return
	var e = u.engaged                         # untyped: it may have been freed
	if not is_instance_valid(e) or ("dead" in e and e.dead) or not cands.has(e):
		e = null
	if e == null and u.target != null:
		e = u.target
		if u.engage_from == Vector3.INF:
			u.engage_from = u.global_position     # ten steps from here, however many it fights
	if e == null:
		_disengage(u)
	else:
		u.engaged = e


func _disengage(u: DroidUnit) -> void:
	if u.engage_from == Vector3.INF:
		return
	u.engaged = null
	u.engage_from = Vector3.INF
	u.following = true                        # back to its place by you


## A knocked-out droid of yours lies there knocked_out_s, then reboots where it
## fell at full health (a new body: the fall and the dark eyes are undone).
func _tick_knocked_out(dt: float) -> void:
	for uid in companions.keys():
		var u: DroidUnit = companions[uid]
		if not u.dead:
			continue
		u.down_left -= dt
		if u.down_left > 0.0:
			continue
		var d := roster().find(uid)
		var at := u.global_position
		_free_companion(uid)
		if d.is_empty():
			continue
		var n := _spawn_companion(d, at)
		Sound.play("droid_wake", at)
		_beep(n)
		_toast(_l("rebooted") % DroidRoster.label(str(d.kind)).to_lower())


## One of your droids took a hit from someone you are fighting.
## Issue #372: a grenade burst on a droid. The Remnant's, the locals' and wrecks
## take `wreck` (they go up); yours take `amount` even from your own grenade.
func on_unit_blast(u: DroidUnit, amount: float, shooter: Node, wreck: float) -> void:
	if u.dead:
		return
	if u.faction == "" and not u.broken and companions.get(u.uid) == u and not u.has_meta("net_id"):
		_beep(u)
		_hurt_companion(u, amount)
		return
	on_unit_hit(u, maxf(amount, wreck), shooter)


func _hurt_companion(u: DroidUnit, amount: float) -> void:
	u.hp -= amount
	if u.hp > 0.0:
		return
	u.dead = true
	u.target = null
	u.engaged = null
	u.engage_from = Vector3.INF
	u.down_left = float(cfg.get("knocked_out_s", 20.0))
	if u.uid == LENT_UID:
		lent_down = true                      # issue #310: down for the rest of the heist
	u.collision_layer = 0
	if u.rig != null:
		u.rig.visible = false               # issue #392: dark until it reboots
	ExplosionFx.small(u.get_parent(), u.center())
	Sound.play("droid_pop", u.center())
	_lay_down(u)
	if u.uid == LENT_UID:
		_toast(Heist.line("droid_down"))
		return
	_toast(_l("knocked_out") % [DroidRoster.label(u.kind).to_lower(), int(u.down_left)])


## Issue #392: the laser rig on droid `u` (a floating droid of yours): a neon ring
## round its belly and the stage droid's fan of lasers under it, sweeping ahead
## of it (ClubProps.laser_fan, on its own clock, so the beat goes on whatever the
## club is doing). `on`: the beams lit; the ring stays.
func _fit_rig(u: DroidUnit, on: bool) -> void:
	var lc := DroidRoster.upgrade_cfg("lasers")
	var rig := ClubProps.new("rave", float(lc.get("bpm", 126.0)))
	rig.name = "LaserRig"
	rig.live_fn = func() -> bool: return true
	u.look.add_child(rig)
	var rc: Dictionary = lc.get("ring", {})
	var ring := TorusMesh.new()
	ring.inner_radius = float(rc.get("inner", 0.42))
	ring.outer_radius = float(rc.get("outer", 0.47))
	var glow := ClubTextures.glow(Color(str(rc.get("color", "#ff2bd6"))), 6.0)
	var mi := rig._put(rig, ring, Vector3(0, float(rc.get("y", 0.22)), 0), glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.pulses.append([glow, 3.0, 8.0, 1.0, 0.0])
	var lasers := Node3D.new()
	lasers.name = "Lasers"
	lasers.position = Vector3(0, -0.1, 0)        # the emitter under its belly
	rig.add_child(lasers)
	rig.laser_fan(lasers, Basis(Vector3.UP, PI), lc.get("fan", {}))     # ahead of it: the model faces -Z
	lasers.visible = on
	u.rig = rig
	u.lasers = lasers


## Turn droid `uid`'s lasers on or off (E beside it). Returns the new state.
func toggle_lasers(uid: int) -> bool:
	var d := roster().find(uid)
	var on := roster().set_lasers(uid, not DroidRoster.lasers_on(d))
	var u: DroidUnit = companions.get(uid)
	if u != null and u.lasers != null:
		u.lasers.visible = on
	_toast(_l("lasers_now_on" if on else "lasers_now_off"))
	_beep(u)
	return on


## Where a droid left far behind rejoins: the oldest point of your trail at most
## REJOIN_LAG_S old and within REJOIN_MAX m of you (so it does not land past the
## jump distance and jump again next frame). INF when even the newest point is
## too far (you were moved), and the droid takes its slot beside you as before.
func _rejoin_point() -> Vector3:
	var at := Vector3.INF
	for i in range(_trail.size() - 1, -1, -1):
		var e: Array = _trail[i]
		if _follow_t - float(e[0]) > REJOIN_LAG_S or _flat_dist(e[1], player.global_position) > REJOIN_MAX:
			break
		at = e[1]
	return at


## A push away from any other droid of yours closer than a body's width.
func _separation(u: DroidUnit, at: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for other in companions.values():
		if other == u:
			continue
		var up := _up(at)
		var d := _flat(at - other.global_position, up)
		var l := d.length()
		if l < 1.3:
			push += (d / l if l > 0.01 else PlanetSphere.tilt_to(up) * Vector3(u.quirk().x - 0.5, 0, 0.5 - u.quirk().y).normalized()) * (1.3 - l) * 4.0
	return push


## Your assassin droid (deadly aim) and floating droid (a smaller gun): each kind's
## "gun" block, at whoever you are fighting. A kind with no gun (cargo) never shoots.
func _companion_guns(dt: float) -> void:
	_enemies_left -= dt
	if _enemies_left <= 0.0:
		_enemies_left = ENEMIES_EVERY_S
		_enemies = enemies()
	var cands := _enemies
	for uid in companions:
		var u: DroidUnit = companions[uid]
		var gun: Dictionary = DroidRoster.kind_cfg(u.kind).get("gun", {})
		if gun.is_empty() or u.dead:
			continue
		u.gun_cd -= dt
		var reach := float(gun.get("range", 30.0))
		# Issue #538: look again a few times a second, or at once when the target is gone.
		if _tick_every(_aim_left, uid, AIM_EVERY_S, dt) or not _still_target(u, reach, cands):
			u.target = _enemy_near(u, reach, cands)
		_engage(u, cands)
		if u.target == null:
			continue
		var aim := _chest(u.target)
		_face(u, aim - u.global_position)
		if u.gun_cd <= 0.0:
			u.gun_cd = float(gun.get("interval", 1.0)) * (0.9 + u.quirk().x * 0.2)
			var mult := DroidRoster.damage_mult(roster().find(uid))
			if mult != 1.0:
				gun = gun.duplicate()
				gun["damage"] = float(gun.get("damage", 10.0)) * mult     # the merchant's capacitor
			fire(u, aim, gun)


## Everyone in a fight with you right now, for your droids to shoot: the Remnant's
## soldiers while their garrison's alarm is up (issue #64: the town's, or their
## outpost's), its droids once you shot one, it shot at you or its alarm is up
## (never a cargo droid running off: that one is yours to fix; and never one that
## has not started on you yet, so your droids do not start a fight), the port's locals while their alarm is up, and every
## member of a native pack on the attack. Nobody you are not fighting.
func enemies() -> Array:
	var out: Array = []
	for r in remnant:
		if not r.dead and not r.spec.has("flee") and (r.provoked or _alarm_up(r)):
			out.append(r)
	if demo == null:
		return out
	for n in demo.npcs:
		if not is_instance_valid(n) or n.dead:
			continue
		var g = demo.garrison_for(n) if demo.has_method("garrison_for") else _garrison()
		if n.hostile or (g != null and g.alarm.active()):
			out.append(n)
	var locals = demo.get("locals")
	for n in (locals if locals != null else []):
		if not is_instance_valid(n) or n.dead:
			continue
		# Issue #187: an outpost's locals have their own alarm.
		var folk = demo.townsfolk_for(str(n.get_meta("outpost", ""))) if demo.has_method("townsfolk_for") else demo.get("townsfolk")
		var up: bool = folk != null and is_instance_valid(folk) and folk.alarm != null and folk.alarm.active()
		if up or n.hostile:
			out.append(n)
	var nat = demo.get("natives")
	if nat != null and is_instance_valid(nat):
		for p in nat.packs:
			if p is Dictionary and p.has("members") and str(p.get("state", "")) == "attack":
				for m in nat.alive(p):
					out.append(m.npc)
	return out


## A shot from `shooter` is the player's: theirs, or from one of their droids
## (the natives and the locals hold your droid's kills against you).
static func by_player(shooter, player: Node) -> bool:
	if shooter == null or not is_instance_valid(shooter):
		return false
	return shooter == player or (shooter is DroidUnit and (shooter as DroidUnit).faction == "" and (shooter as DroidUnit).uid >= 0)


## The nearest of `cands` (enemies()) within `reach` with nothing in the way.
## Issue #538: only the AIM_RAYS nearest are ray-checked, nearest first (it was
## every candidate in reach, unsorted, every tick).
func _enemy_near(u: DroidUnit, reach: float, cands: Array) -> Node3D:
	var near: Array = []
	for c in cands:
		if not _alive(c):
			continue
		var d: float = u.global_position.distance_to(c.global_position)
		if d < reach:
			near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(near.size(), AIM_RAYS):
		if _clear_shot(u, near[i][1]):
			return near[i][1]
	return null


## u's target is still worth shooting at: alive, still in the fight, in reach.
func _still_target(u: DroidUnit, reach: float, cands: Array) -> bool:
	var t = u.target
	return t != null and _alive(t) and cands.has(t) and u.global_position.distance_to(t.global_position) < reach


static func _alive(c) -> bool:
	return is_instance_valid(c) and not ("dead" in c and c.dead)


# ------------------------------------------------------------------ the pit's hauler (issue #64)

var hauler: DroidUnit                 ## the old cargo droid that roams the pit
var _hauler_pause := 0.0
var wreck_hauler: DroidUnit           ## issue #148: the one in the wreck's deep hold
var _wreck_hauler_pause := 0.0


func _build_hauler() -> void:
	var hc: Dictionary = cfg.get("pit_hauler", {})
	var route: Array = hc.get("route", [])
	if route.is_empty():
		return
	hauler = _make_unit("cargo", str(hc.get("variant", "tan")))
	hauler.patrol = route.map(func(p): return _v3(p))
	hauler.spec = { "hauler": true }
	add_child(hauler)
	_put(hauler, hauler.patrol[0])
	hauler.patrol_i = 1 % hauler.patrol.size()      # already at the first stop: off to the next
	DroidKit.set_awake(hauler.look, true)


## It walks its round of the pit, stopping a while at each point, and the
## pickup it carries rides on its back (GearController still owns the pickup).
func _hauler_step(dt: float) -> void:
	if net_copy:
		# The copies walk where the host's do; the loads still ride on their backs.
		if hauler != null and is_instance_valid(hauler):
			_carry(hauler, cfg.get("pit_hauler", {}))
		if wreck_hauler != null and is_instance_valid(wreck_hauler):
			_carry(wreck_hauler, cfg.get("wreck", {}).get("hauler", {}))
		return
	if hauler != null:
		_hauler_pause = _haul(hauler, cfg.get("pit_hauler", {}), _hauler_pause, dt)
	if wreck_hauler != null:
		_wreck_hauler_pause = _haul(wreck_hauler, cfg.get("wreck", {}).get("hauler", {}), _wreck_hauler_pause, dt)


## One step of a hauler `u` (config `hc`) on its round. Returns its pause left.
func _haul(u: DroidUnit, hc: Dictionary, pause: float, dt: float) -> float:
	var moving := false
	if pause > 0.0:
		pause -= dt
	else:
		var goal: Vector3 = u.patrol[u.patrol_i]
		var to := _flat(goal - u.global_position, _up(u.global_position))
		if to.length() < 0.4:
			u.patrol_i = (u.patrol_i + 1) % u.patrol.size()
			pause = float(hc.get("pause_s", 4.0))
		else:
			var spd := float(hc.get("walk_speed", 1.3))
			var pos: Vector3 = u.global_position + to.normalized() * minf(spd * dt, to.length())
			_put(u, pos)
			_face(u, to)
			moving = true
	u.walk(dt, moving, float(hc.get("walk_speed", 1.3)) if moving else 0.0)
	_carry(u, hc)
	return pause


## The pickup a hauler `u` carries (its config's "carries") rides on its back.
func _carry(u: DroidUnit, hc: Dictionary) -> void:
	var load = gear.pickup_node(str(hc.get("carries", ""))) if gear != null else null
	# Only while the pickup is its load: a story save puts the pit jetpack on the
	# cantina tower instead (pickups/port_town.json, "modes"), and the hauler roams empty.
	if load != null and is_instance_valid(load) \
			and (str(load.pickup.get("inside", "")) != "" or bool(load.pickup.get("carried", false))):
		var at := u.global_position + _up(u.global_position) * float(hc.get("load_lift", 1.05))
		load.base = at
		load.global_position = at
		load.visible = true


# ------------------------------------------------------------------ the Remnant's droids

func _build_remnant() -> void:
	if Story.town_garrison():
		_build_town_units(cfg.get("remnant", {}))
	else:
		_build_town_units(_side_cfg(Territory.LOCALS))
	_build_wreck_site()
	var outposts = demo.outposts if demo != null and "outposts" in demo else null
	if outposts == null:
		return
	for o in outposts.droid_specs():
		build_outpost_units(str(o.outpost))


## The main street's patrol droids for one side's block (droids.json "remnant" or
## "locals"), on the Remnant's street route.
func _build_town_units(side: Dictionary) -> void:
	var station = demo.platform if demo != null and "platform" in demo else null
	if station is AsteroidWorld and not station.st.is_empty():
		_build_station_pacers(side, station)
		return
	var pts: Array = cfg.get("remnant", {}).get("patrol", [])
	# Issue #237: a town layout can draw its own street patrol (route "street_patrol").
	if demo != null and "town" in demo and demo.town != null and not demo.town.get_route("street_patrol").is_empty():
		pts = demo.town.get_route("street_patrol").points.map(func(p): return [p[0], 0, p[1]])
	if pts.is_empty():
		return
	var route: Array = pts.map(func(p): return _v3(p))
	for spec in side.get("units", []):
		var sp: Dictionary = _side_spec(side, spec)
		sp["patrol"] = route
		_spawn_remnant(sp, int(spec.get("start", 0)) % route.size())


## The moon station: no street patrol under the dome (the home port's route crossed
## its walls and walked the hallway's roof). The side's droids pace short beats on
## the rock outside the ring wall instead (droids.json "station"), one per post.
func _build_station_pacers(side: Dictionary, station: AsteroidWorld) -> void:
	var sc: Dictionary = cfg.get("station", {})
	var units: Array = side.get("units", [])
	if units.is_empty():
		return
	var r: float = station.rw + float(sc.get("out", 8.0))
	var half := float(sc.get("half", 6.0))
	var i := 0
	for deg in sc.get("posts_deg", []):
		var a := deg_to_rad(float(deg))
		var at: Vector3 = station.rc + Vector3(cos(a), 0.0, sin(a)) * r
		var along := Vector3(-sin(a), 0.0, cos(a)) * half
		var beat: Array = [at - along, at + along]
		if _on_ball():
			beat = beat.map(func(p): return ground.surface_below(p + _up(p) * 200.0))
		var sp := _side_spec(side, units[i % units.size()])
		sp["patrol"] = beat
		_spawn_remnant(sp, i % 2)
		i += 1


## Issue #187: a side's block: "remnant" (the Remnant's) or "locals".
func _side_cfg(owner: String) -> Dictionary:
	return cfg.get("locals", {}) if owner == Territory.LOCALS else cfg.get("remnant", {})


func _side_spec(side: Dictionary, spec: Dictionary) -> Dictionary:
	var sp: Dictionary = spec.duplicate()
	sp["faction"] = str(side.get("faction", "imperial_remnant"))
	if side.has("gun") and not sp.has("gun"):
		sp["gun"] = side.gun
	return sp


## Issue #187: the droids of outpost `id` for whoever holds it now (the Remnant's
## three, or the locals' white assassin droid).
func build_outpost_units(id: String) -> void:
	if net_copy:
		return
	var outposts = demo.outposts if demo != null and "outposts" in demo else null
	if outposts == null:
		return
	var side := _side_cfg(Territory.owner(id))
	var units: Array = side.get("outpost_units", [side.get("outpost_unit", {})])
	for o in outposts.droid_specs():
		if str(o.outpost) != id:
			continue
		for oc in units:
			var route: Array = o.routes.get(str(oc.get("route", "patrol")), [])
			if route.is_empty():
				continue
			var sp := _side_spec(side, oc)
			sp["patrol"] = route
			sp["outpost"] = o.outpost
			_spawn_remnant(sp, 0)


## And gone: everyone's droids at outpost `id` (it changed hands).
func clear_outpost_units(id: String) -> void:
	if net_copy:
		return
	for u in remnant.duplicate():
		if str(u.spec.get("outpost", "")) == id:
			remnant.erase(u)
			u.queue_free()


## Issue #148: the wreck's Remnant droids and its hauler, on routes from the data
## (droids.json "wreck") turned into world points. Nothing when this ground has
## no wreck (another planet, a test without one).
## Wreck field: the same crew aboard every wreck in "sites" this ground has, less
## the routes over a deck that one lost; the hauler only on the original.
func _build_wreck_site() -> void:
	var wc: Dictionary = cfg.get("wreck", {})
	for site in wreck_sites():
		var id := str(site.landmark)
		if not StarcruiserWreck.has_wreck(ground, id):
			continue
		var skip: Array = site.get("skip_routes", [])
		for spec in wc.get("units", []):
			if str(spec.get("route", "")) in skip:
				continue
			var route := wreck_route(str(spec.get("route", "")), id)
			if route.is_empty():
				continue
			var sp: Dictionary = spec.duplicate()
			sp["patrol"] = route
			sp["site"] = id
			sp["wreck"] = true
			sp["hostile"] = true
			_spawn_remnant(sp, int(spec.get("start", 0)) % route.size())
		if bool(site.get("hauler", false)):
			_build_wreck_hauler(id)


func _build_wreck_hauler(id: String) -> void:
	var hc: Dictionary = cfg.get("wreck", {}).get("hauler", {})
	var stops := wreck_route(str(hc.get("route", "")), id)
	if stops.is_empty():
		return
	wreck_hauler = _make_unit("cargo", str(hc.get("variant", "olive")))
	wreck_hauler.patrol = stops
	wreck_hauler.spec = { "hauler": true, "site": id }
	add_child(wreck_hauler)
	_put(wreck_hauler, stops[0])
	wreck_hauler.patrol_i = 1 % stops.size()
	DroidKit.set_awake(wreck_hauler.look, true)


## Wreck field: the wrecks the Remnant holds ("wreck"/"sites": { landmark,
## skip_routes?, hauler? }); just the original when the data lists none.
func wreck_sites() -> Array:
	var wc: Dictionary = cfg.get("wreck", {})
	return wc.get("sites", [{ "landmark": str(wc.get("landmark", "starcruiser_wreck")), "hauler": true }])


## A named route of the wreck's ("wreck"/"routes" in droids.json), in the world,
## aboard wreck `id` (the original by default).
func wreck_route(name: String, id: String = "") -> Array:
	var wc: Dictionary = cfg.get("wreck", {})
	var r: Dictionary = wc.get("routes", {}).get(name, {})
	if id == "":
		id = str(wc.get("landmark", "starcruiser_wreck"))
	return r.get("points", []).map(func(p): return StarcruiserWreck.site_point(ground, _v3(p), str(r.get("frame", "level")), id))


## One of the Remnant's droids from its spec ({ kind, variant, hp, gun, patrol:
## [Vector3], outpost }), standing at patrol point `start`.
func _spawn_remnant(spec: Dictionary, start: int, at := Vector3.INF) -> DroidUnit:
	var rc: Dictionary = cfg.get("remnant", {})
	var u := _make_unit(str(spec.get("kind", "assassin")), str(spec.get("variant", "remnant")))
	u.faction = str(spec.get("faction", rc.get("faction", "imperial_remnant")))
	u.max_hp = float(spec.get("hp", 40))
	u.hp = u.max_hp
	u.gun = spec.get("gun", DroidRoster.kind_cfg(u.kind).get("gun", {}))
	u.spec = spec
	u.patrol = spec.get("patrol", [])
	u.patrol_i = start % maxi(1, u.patrol.size())
	add_child(u)
	var p: Vector3 = at if at != Vector3.INF else (u.patrol[u.patrol_i] if not u.patrol.is_empty() else Vector3.ZERO)
	_put(u, p)
	DroidKit.set_awake(u.look, true)
	remnant.append(u)
	return u


## Issue #193: a Remnant droid at a site of its own (the cruiser), from its spec:
## { kind, variant, hp, gun?, patrol: [Vector3], site, hostile, respawn, garrison? }.
func spawn_site_unit(spec: Dictionary) -> DroidUnit:
	if net_copy:
		return null
	var route: Array = spec.get("patrol", [])
	if route.is_empty():
		return null
	return _spawn_remnant(spec, int(spec.get("start", 0)) % route.size())


## And gone again (the cruiser's crew took the pods).
func remove_site_unit(u: DroidUnit) -> void:
	remnant.erase(u)
	if is_instance_valid(u):
		u.queue_free()


## Issue #64: the fleet is beaten; the town's droids leave with the garrison.
## Issue #187: and the locals' two take the street.
func withdraw_town_remnant() -> void:
	if net_copy:
		return
	for u in remnant.duplicate():
		if not u.spec.has("outpost") and not u.spec.has("site"):
			remnant.erase(u)
			u.queue_free()
	_build_town_units(_side_cfg(Territory.LOCALS))


## Issue #303: the Remnant take the town back: the locals' street droids go, theirs return.
func return_town_remnant() -> void:
	if net_copy:
		return
	for u in remnant.duplicate():
		if not u.spec.has("outpost") and not u.spec.has("site") and u.faction == "locals":
			remnant.erase(u)
			u.queue_free()
	_build_town_units(cfg.get("remnant", {}))


## Issue #187: the side that holds this droid's place still does (else it does not come back).
func _still_posted(u: DroidUnit) -> bool:
	var side := Territory.LOCALS if u.faction == "locals" else Territory.REMNANT
	if u.spec.has("site"):
		return true
	if u.spec.has("outpost"):
		return Territory.owner(str(u.spec.outpost)) == side
	return Territory.owner(Territory.barracks_here()) == side


## A destroyed Remnant droid comes back: in town behind the barracks a minute
## later while the garrison holds the town, at its outpost after a few minutes.
func _tick_remnant_respawns(dt: float) -> void:
	# Issue #538: backwards over the list, not a copy of it every tick (a respawn
	# erases its droid and appends the new one, past where this has been).
	for i in range(remnant.size() - 1, -1, -1):
		var u: DroidUnit = remnant[i]
		if not u.dead or u.respawn_left < 0.0:
			continue
		u.respawn_left -= dt
		if u.respawn_left > 0.0 and not _left_behind(u):
			continue
		var at := Vector3.INF
		if not _still_posted(u):
			u.respawn_left = -1.0
			continue
		if not u.spec.has("outpost") and not u.spec.has("site") and u.faction != "locals":
			var mk := str(Story.remnant_cfg().get("town_respawn_marker", "remnant_respawn"))
			if demo != null and not demo.town.get_marker(mk).is_empty():
				at = demo.town.marker_pos(mk)
		remnant.erase(u)
		u.queue_free()
		_spawn_remnant(u.spec, u.patrol_i, at)


## Wreck field: a wreck's droid is back once you are respawn_away_m (500 ft) from
## where it fell, without waiting out its timer.
func _left_behind(u: DroidUnit) -> bool:
	if not bool(u.spec.get("wreck", false)) or player == null:
		return false
	var away := float(cfg.get("wreck", {}).get("respawn_away_m", INF))
	return player.global_position.distance_to(u.global_position) >= away


func _garrison(u: DroidUnit = null):
	if u != null and u.faction == "locals":
		return null                    # issue #187: the locals' droids answer to their own alarm (_folk)
	if u != null and u.spec.get("garrison") is Garrison and is_instance_valid(u.spec.garrison):
		return u.spec.garrison         # issue #193: the cruiser's droids answer to its crew's alarm
	if u != null and u.spec.has("site"):
		return null                    # issue #148: out at the wreck nobody calls the town
	if demo == null or not "garrison" in demo:
		return null
	# Issue #64: an outpost's droid answers to that outpost's garrison.
	if u != null and u.spec.has("outpost") and demo.outposts != null:
		var g = demo.outposts.garrisons.get(str(u.spec.outpost), null)
		if g != null:
			return g
	return demo.garrison


## They turn on you exactly when the garrison would: the alarm is up, your Remnant
## standing is in the hostile band, or you shot at them.
func remnant_hostile(u: DroidUnit) -> bool:
	if u.faction == "locals":
		return u.provoked or _alarm_up(u)
	if u.provoked or bool(u.spec.get("hostile", false)) or Story.remnant_hostile():
		return true
	var g = _garrison(u)
	if g == null:
		return false
	return g.alarm.active() or g.checkpoint.base_band(int(WorldState.standing.get("imperial_remnant", 0))) == "hostile"


func _remnant_step(dt: float) -> void:
	var rc: Dictionary = cfg.get("remnant", {})
	_tick_remnant_respawns(dt)
	for u in remnant:
		if u.dead:
			continue
		var pts: Array = u.patrol
		u.gun_cd -= dt
		if _idle_far(u):
			continue
		var sees := false
		if u.spec.has("flee"):
			# Issue #76: no gun; it bolts when its outpost is in a fight.
			if u.has_meta("flee_to") or u.provoked or _alarm_up(u):
				_flee(u, dt)
				continue
		elif remnant_hostile(u):
			# In a speeder or ship: only where its garrison fights it (an outpost's, or in town).
			var hull := _vehicle_hull(u)
			if not player.piloting or hull != null:
				var d: float = u.global_position.distance_to(player.global_position)
				sees = d <= float(rc.get("sight", 22.0)) \
					and (_clear_shot(u, hull, player.global_position) if hull != null else _clear_shot(u, player))
		if sees:
			u.provoked = true              # in a fight with you now: your droids answer it
			var aim := player.global_position if player.piloting else _chest(player)   # the hull, not a seat above it
			_face(u, aim - u.global_position)
			u.walk(dt, false, 0.0, true)
			var g = _garrison(u)
			if g != null and not g.alarm.active():
				g._raise("droid")
			if u.gun_cd <= 0.0:
				u.gun_cd = float(u.gun.get("interval", 1.0))
				fire(u, aim, u.gun)
			continue
		if pts.is_empty():
			continue
		var goal: Vector3 = pts[u.patrol_i]
		var to := _flat(goal - u.global_position, _up(u.global_position))
		if to.length() < 0.6:
			u.patrol_i = (u.patrol_i + 1) % pts.size()
			continue
		var pace := float(u.spec.get("walk_speed", rc.get("walk_speed", 2.2)))
		var pos: Vector3 = u.global_position + to.normalized() * minf(pace * dt, to.length())
		_put(u, pos)
		_face(u, to)
		u.walk(dt, true, pace)


## Wreck field: a wreck's droid far beyond anyone's sight stands where it is.
func _idle_far(u: DroidUnit) -> bool:
	if not bool(u.spec.get("wreck", false)) or player == null:
		return false
	var far := float(cfg.get("wreck", {}).get("idle_beyond_m", INF))
	return player.global_position.distance_squared_to(u.global_position) > far * far


## The player died and woke in the pit: the Remnant's droids (and the locals')
## forget who shot at them. Their garrison has stood down too, so they walk their
## round again instead of waiting at the pit.
func forgive_player() -> void:
	for u in remnant:
		u.provoked = false


## The hull of the speeder or ship the player is in, while u's garrison fights it
## (Garrison.target_vehicle); null on foot or when nobody minds it.
func _vehicle_hull(u: DroidUnit) -> Node3D:
	var g = _garrison(u) if player.piloting else null
	var v = g.target_vehicle() if g != null else null
	return v.hull_body() if v != null else null


func _alarm_up(u: DroidUnit) -> bool:
	var g = _folk(u) if u.faction == "locals" else _garrison(u)
	return g != null and g.alarm != null and g.alarm.active()


## Issue #187: the locals a locals' droid stands with (its outpost's, else the town's).
func _folk(u: DroidUnit):
	if demo == null or not demo.has_method("townsfolk_for"):
		return null
	return demo.townsfolk_for(str(u.spec.get("outpost", "")))


## Issue #76: run `flee.distance` metres away from the player (and on from the
## outpost), then give out there: see _strand.
func _flee(u: DroidUnit, dt: float) -> void:
	var fc: Dictionary = u.spec.get("flee", {})
	var up := _up(u.global_position)
	if not u.has_meta("flee_to"):
		var away := _flat(u.global_position - player.global_position, up)
		if away.length() < 0.5:
			away = _flat(u.global_position - (u.patrol[0] as Vector3), up)
		if away.length() < 0.05:
			away = _flat(Vector3(1, 0, 0), up)
		away = away.normalized().rotated(up, rng.randf_range(-0.6, 0.6))
		u.set_meta("flee_to", u.global_position + away * float(fc.get("distance", 150.0)))
		u.set_meta("flee_left", float(fc.get("max_s", 45.0)))
		_beep(u)
	var left: float = float(u.get_meta("flee_left")) - dt
	u.set_meta("flee_left", left)
	var to := _flat((u.get_meta("flee_to") as Vector3) - u.global_position, up)
	if to.length() < 1.0 or left <= 0.0:
		_strand(u)
		return
	var speed := float(fc.get("speed", 5.0))
	_put(u, u.global_position + to.normalized() * minf(speed * dt, to.length()))
	_face(u, to)
	u.walk(dt, true, speed)


## The runaway gives out where it stopped: a wreck there (saved; [E] fixes it and
## it is yours), and the outpost gets a new one when its troopers come back.
func _strand(u: DroidUnit) -> void:
	var w := roster().add_wreck(u.kind, u.variant, u.global_position)
	_build_wreck(w)
	stranded += 1
	u.remove_meta("flee_to")
	u.dead = true
	u.visible = false
	u.collision_layer = 0
	u.respawn_left = float(Story.remnant_cfg().get("outpost_respawn_s", 180.0))
	unit_down.emit(u, Vector3.INF)


## A bolt hit a droid. Wrecks shrug it off, and so do yours unless someone else
## fired it (yours, your droids' and your sword's never hurt them); the Remnant's
## take damage from anyone outside the Remnant, turn on you, and call it in.
## `sweep` is the way the player's energy sword was moving (zero for a bolt): a
## killing cut bats it.
func on_unit_hit(u: DroidUnit, amount: float, shooter: Node, sweep := Vector3.ZERO) -> void:
	_beep(u)
	if u.dead:
		return
	if u.has_meta("net_id"):
		if net_hit.is_valid():
			net_hit.call(u, amount, shooter, sweep)    # the host's game says what it did
		return
	if u.faction == "":
		if not u.broken and companions.get(u.uid) == u and shooter != null and is_instance_valid(shooter) \
				and not by_player(shooter, player):
			_hurt_companion(u, amount)
		return
	if shooter is DroidUnit and (shooter as DroidUnit).faction == u.faction:
		return
	if shooter != null and "faction" in shooter and str(shooter.faction) == u.faction:
		return
	u.provoked = true
	u.hp -= amount
	var g = _garrison(u)
	if g != null and not g.alarm.active():
		g._raise("droid_shot")
	var folk = _folk(u) if u.faction == "locals" else null
	if folk != null and by_player(shooter, player):
		folk._attacked = true          # issue #187: shooting the locals' droid is shooting the locals
	if u.hp <= 0.0:
		_fall(u, sweep)
		unit_down.emit(u, sweep)
		var rsc := Story.remnant_cfg()
		u.respawn_left = float(rsc.get("outpost_respawn_s" if u.spec.has("outpost") else "town_respawn_s", 60.0))
		if u.spec.has("site"):
			u.respawn_left = float(cfg.get("wreck", {}).get("respawn_s", 180.0))
		if not bool(u.spec.get("respawn", true)):
			u.respawn_left = -1.0          # issue #193: the cruiser's crew never come back
		if u.faction == "locals":
			WorldState.change_standing(u.faction, int(cfg.get("remnant", {}).get("kill_standing", -6)), "A locals' droid was destroyed.")
		else:
			WorldState.change_standing(u.faction, int(cfg.get("remnant", {}).get("kill_standing", -6)), "A Remnant patrol droid was destroyed.")
			WorldState.log_event(_l("event_remnant_droid"))


## It blows: the pop, and down it goes (batted along a blade's `sweep`).
func _fall(u: DroidUnit, sweep: Vector3) -> void:
	u.dead = true
	ExplosionFx.small(u.get_parent(), u.center())
	Sound.play("droid_pop", u.center())
	u.collision_layer = 0
	if sweep != Vector3.ZERO:
		_bat(u, sweep)
	else:
		_lay_down(u)


# ------------------------------------------------------------------ LAN copies (issue #402)

## A copy of one of the host's droids from its description (NetWorld.droid_meta):
## { kind, variant, faction, hp, max_hp, gun, outpost, site, hauler, pos, yaw }.
## It thinks nothing; NetWorld moves it, and a hit on it goes to net_hit.
func net_unit(m: Dictionary) -> DroidUnit:
	var u := _make_unit(str(m.kind), str(m.variant))
	u.faction = str(m.get("faction", ""))
	u.max_hp = float(m.get("max_hp", 40.0))
	u.hp = float(m.get("hp", u.max_hp))
	u.gun = m.get("gun", {})
	for k in ["outpost", "site"]:
		if str(m.get(k, "")) != "":
			u.spec[k] = str(m[k])
	add_child(u)
	u.global_position = m.pos
	u.yaw = float(m.get("yaw", 0.0))
	_orient(u)
	DroidKit.set_awake(u.look, true)
	match str(m.get("hauler", "")):
		"pit":
			hauler = u
		"wreck":
			wreck_hauler = u
		_:
			remnant.append(u)              # your droids fight it, it chirps
	return u


## Another player's droid, shown here: it looks and walks like theirs and does
## nothing else (a bolt that lands on it is stopped and does no harm).
func net_picture(kind: String, variant: String) -> DroidUnit:
	var u := _make_unit(kind, variant)
	u.set_meta("net_picture", true)
	add_child(u)
	DroidKit.set_awake(u.look, true)
	return u


## The host's one died (sweep INF: it ran off and broke down out there).
func net_down(u: DroidUnit, sweep: Vector3) -> void:
	if u.dead:
		return
	if sweep == Vector3.INF:
		u.dead = true
		u.visible = false
		u.collision_layer = 0
		return
	_fall(u, sweep)


## A droid's harmless bolt at `aim`: a picture of a shot fired in another game.
func net_fire(u: DroidUnit, aim: Vector3, gun: Dictionary) -> void:
	var b = fire(u, aim, gun)
	b.damage = 0.0
	b.splash_damage = 0.0
	b.sweep = false
	b.monitoring = false               # what it hit is the other game's to say
	b.collision_mask = 0
	b.remove_from_group("bolts")


# ------------------------------------------------------------------ guns

## A bolt from a droid's gun (its kind's "gun" block) at a point.
func fire(u: DroidUnit, aim: Vector3, gun: Dictionary) -> Node:
	var origin := u.muzzle()
	var dir := (aim - origin).normalized()
	var spread := deg_to_rad(float(gun.get("spread_deg", 0.5)))
	dir = dir.rotated(Vector3.UP, rng.randf_range(-spread, spread))
	var axis := dir.cross(Vector3.UP)
	if axis.length() > 0.01:
		dir = dir.rotated(axis.normalized(), rng.randf_range(-spread, spread))
	u.shots += 1
	u.last_aim = aim
	var b = BoltScene.instantiate()
	b.direction = dir
	b.speed = float(gun.get("bolt_speed", 30.0))
	b.damage = float(gun.get("damage", 10.0))
	b.range_m = float(gun.get("range", 30.0)) + 15.0
	b.shooter = u
	if u.faction == "" and player != null:
		b.friends = [player]           # issue #64: your droid shoots past you, never into you
	b.stylize = true
	b.sweep = true
	b.color = Color(str(gun.get("color", "#ff5a3a")))
	var parent: Node = demo if demo is Node else self
	parent.add_child(b)
	b.global_position = origin
	shots_fired += 1
	Sound.play("droid_shot", origin)
	return b


## Nothing solid between the droid's muzzle and the target's chest, or `at` (the player
## and other droids in the way count as solid, so it never shoots through you).
func _clear_shot(u: DroidUnit, target: Node3D, at := Vector3.INF) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(u.muzzle(), at if at != Vector3.INF else _chest(target))
	rays += 1
	q.exclude = [u.get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var c: Object = hit.collider
	return c == target or (c is Node and (target.is_ancestor_of(c) or (c as Node).is_ancestor_of(target)))


func _chest(t: Node3D) -> Vector3:
	if t is DroidUnit:
		return (t as DroidUnit).center()
	if t.has_method("eye_position"):
		return t.eye_position() - Vector3(0, 0.3, 0)
	return t.global_position + Vector3(0, 1.2, 0)


# ------------------------------------------------------------------ helpers

func _make_unit(kind: String, variant: String) -> DroidUnit:
	var u := DroidUnit.new()
	u.ctl = self
	u.kind = kind
	u.variant = variant
	u.collision_layer = DROID_LAYER
	u.collision_mask = 0
	u.shape = CollisionShape3D.new()
	var kc := DroidRoster.kind_cfg(kind)
	match kind:
		"floating":
			var s := SphereShape3D.new()
			s.radius = float(kc.get("hit_radius", 0.55))        # issue #80: was 0.3, easy to miss
			u.shape.shape = s
			u.look_lift = float(kc.get("hover", 1.7))
			u.shape.position = Vector3(0, u.look_lift, 0)
		"cargo":
			u.size_scale = float(kc.get("scale", 1.0))
			var b := BoxShape3D.new()
			b.size = Vector3(0.66, 0.7, 0.76) * u.size_scale
			u.shape.shape = b
			u.shape.position = Vector3(0, 0.38 * u.size_scale, 0)
		_:
			var b := BoxShape3D.new()
			b.size = Vector3(0.55, float(kc.get("height", 2.3)) - 0.1, 0.4)
			u.shape.shape = b
			u.shape.position = Vector3(0, b.size.y * 0.5, 0)
	u.add_child(u.shape)
	u.look = DroidKit.build(kind, DroidRoster.variant_cfg(kind, variant), _mats, cfg.get("kinds", {}).get(kind, {}).get("look", {}))
	u.look.position.y = u.look_lift
	u.look.scale = Vector3.ONE * u.size_scale
	u.add_child(u.look)
	if kind == "floating":
		u.hum = Sound.loop("droid_hum", u)
		if u.hum != null:
			u.hum.autoplay = true
	return u


## Issue #93: "up" at p -- the ground's on the home planet's ball, straight up elsewhere.
func _up(p: Vector3) -> Vector3:
	if ground != null:
		return ground.up_at(p)
	return PlanetSphere.current.up_at(p) if PlanetSphere.current != null else Vector3.UP


## v with its part along `up` taken out: a move or a heading on the ground's tangent plane.
static func _flat(v: Vector3, up := Vector3.UP) -> Vector3:
	return v - up * v.dot(up)


## Whether the ground here is the home planet's ball (so flat (x, z) queries are wrong).
func _on_ball() -> bool:
	return ground != null and ground.sphere() != null


## The ground point under p, along the ground's up, seen from just over the player's
## feet. Issue #538: on the ball, WorldGround's height index answers (the town's
## floors and roofs, the outposts, the desert: about 7 us, where this was a 60 m ray
## per droid per tick). The ray is still cast where the index does not know the
## floor: `ray` (a droid aboard a wreck, your droids while you stand on a deck or a
## hull), inside a gravity zone (the cruiser, a station), and on flat worlds. Then
## WorldGround.surface_below, else the flat sand height.
func _ground_point(p: Vector3, max_lift := INF, ray := false) -> Vector3:
	var up := _up(p)
	var lift := 1.0
	if player != null:
		lift = minf(maxf((player.global_position - p).dot(up) + 2.5, 1.0), max_lift)
	var top := p + up * lift
	if not ray and not _off_index(top, false):
		return ground.surface_below(top)
	if is_inside_tree():
		rays += 1
		var q := PhysicsRayQueryParameters3D.create(top, top - up * 60.0, 1)
		if player != null:
			q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return hit.position
	if _on_ball():
		return ground.surface_below(top)
	if ground_at.is_valid():
		return Vector3(p.x, float(ground_at.call(p.x, p.z)), p.z)
	if player != null:
		return p + up * (player.global_position - p).dot(up)
	return p


## Issue #538: whether the height index can stand in for a ray at p: only on the
## ball, and not inside a gravity zone. With `standing`, also whether someone at p
## stands on something the index does not know (a barge's deck, a ship's hull):
## the index puts the ground well below their feet.
func _off_index(p: Vector3, standing := true) -> bool:
	if not _on_ball():
		return true
	for z in ground.sphere().gravity_zones:
		if p.distance_squared_to(z.center) < z.reach and (z.box as AABB).has_point((z.inv as Transform3D) * p):
			return true
	return standing and player != null and player.is_on_floor() and ground.height_above(p) > 0.6


## The sand height under p on a flat world (kept for callers that want a number).
func _ground_y(p: Vector3) -> float:
	return _ground_point(p).y


## Stand u on the ground under p, upright to it.
## Issue #148: a droid aboard the wreck looks for its floor just over its feet,
## never from the player's height (that would find a deck or the hull above it).
func _put(u: DroidUnit, p: Vector3) -> void:
	var site := u.spec.has("site")
	var ray: bool = site or (_player_off_index and u.uid >= 0 and companions.get(u.uid) == u)
	u.global_position = _ground_point(p, 1.5 if site else INF, ray)
	_orient(u)


## u's basis: its heading (yaw) about the ground's up here. On the ball the up turns with
## where it stands, so a droid on the far side stands the right way up, as the player does.
func _orient(u: DroidUnit) -> void:
	var yaw := Basis(Vector3.UP, u.yaw)
	if _on_ball():
		u.global_basis = PlanetSphere.tilt_to(_up(u.global_position)) * yaw
	else:
		u.rotation = Vector3(0.0, u.yaw, 0.0)


func _face(u: DroidUnit, dir: Vector3) -> void:
	var up := _up(u.global_position)
	var flat := _flat(dir, up)
	if flat.length() > 0.05:
		# The heading in the ground's own frame (where "up" is world up again).
		var local := PlanetSphere.tilt_to(up).inverse() * flat
		u.yaw = atan2(-local.x, -local.z)
		_orient(u)
	if u.kind == "floating":
		var m := u.look.get_node("Model") as Node3D
		m.rotation.x = clampf(atan2(dir.dot(up), flat.length()), -0.8, 0.8)


## Idle chatter: each droid near the player beeps in its own voice now and then.
func _chirps(dt: float) -> void:
	for u in companions.values():    # issue #538: no companions + remnant array every tick
		_chirp(u, dt)
	for u in remnant:
		_chirp(u, dt)


func _chirp(u, dt: float) -> void:
	if not is_instance_valid(u) or u.dead:
		return
	u.chirp_cd -= dt
	if u.chirp_cd <= 0.0:
		var ch: Array = DroidRoster.kind_cfg(u.kind).get("chirp_s", [9.0, 20.0])   # issue #80: slow, per-kind rates, per-droid spread
		var t := rng.randf_range(float(ch[0]), float(ch[1]))   # per-droid spread so no two beep in step
		u.chirp_cd = t * (0.8 + u.quirk().x * 0.4)
		if u.global_position.distance_to(player.global_position) <= 25.0:
			_beep(u)


func _beep(u) -> void:
	if u != null and is_instance_valid(u):
		Sound.play(str(DroidRoster.kind_cfg(u.kind).get("sound", "droid_beep")), u.center())


func _toast(text: String) -> void:
	if gear != null and gear.hud != null:
		gear.hud.toast(text, 4.0)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	var up := PlanetSphere.current.up_at(a) if PlanetSphere.current != null else Vector3.UP
	return _flat(a - b, up).length()


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## One droid in the world: a shootable body with its look. Origin on the ground.
class DroidUnit extends StaticBody3D:
	var ctl
	var uid := -1
	var kind := ""
	var variant := ""
	var faction := ""               ## "" = yours or a wreck; else the Remnant's
	var look: Node3D
	var shape: CollisionShape3D
	var look_lift := 0.0            ## a floating droid hovers this high
	var hum: Node
	var broken := false
	var dead := false
	var provoked := false
	var hp := 1.0
	var max_hp := 1.0
	var gun: Dictionary = {}
	var gun_cd := 0.0
	var chirp_cd := 4.0
	var patrol_i := 0
	var patrol: Array = []          ## Vector3 points it walks (the Remnant's)
	var spec: Dictionary = {}       ## how to build it again (the Remnant's)
	var respawn_left := -1.0        ## seconds until a dead one comes back (< 0 = never)
	var wait_left := 0.0            ## a beat before it starts after you (issue #64)
	var size_scale := 1.0           ## its kind's "scale" (the cargo droid is bigger, issue #64)
	var via: Array = []             ## issue #80: points to pass first (round the merchant's stall)
	var lift_now := 0.0             ## issue #80: its hover height now, easing to look_lift
	var falling := false            ## issue #80: dropping after it died (the bob stops)
	var yaw := 0.0                  ## issue #93: its heading about the ground's up (see _orient)
	var engaged: Node3D             ## the enemy one of yours is going after (see _engage)
	var engage_from := Vector3.INF  ## where it stood when that fight found it
	var down_left := 0.0            ## a knocked-out droid of yours: seconds until it reboots
	var rig: ClubProps              ## issue #392: the laser rig (ring and beams), null without one
	var lasers: Node3D              ## ...its beams
	var shots := 0                  ## issue #402: bolts it has fired (NetWorld sends each one)...
	var last_aim := Vector3.INF     ## ...and where the last went

	## This droid's own small differences, 0..1 each, steady for its uid.
	func quirk() -> Vector3:
		var h := absi(hash(uid * 7919 + 13))
		return Vector3(float(h % 1000) / 1000.0, float((h / 1000) % 1000) / 1000.0, float((h / 1000000) % 1000) / 1000.0)
	var target: Node3D
	var following := false          ## closing the gap to its slot (else it holds still)
	var _t := 0.0

	func center() -> Vector3:
		match kind:
			"floating":
				return look.global_position
			"cargo":
				return global_position + Vector3(0, 0.45 * size_scale, 0)
		return global_position + Vector3(0, 1.5, 0)

	func muzzle() -> Vector3:
		var m := look.find_child("Muzzle", true, false) as Node3D
		if m != null:
			return m.global_position
		return center() + (-global_basis.z) * 0.35

	## Bob (floating), roll the wheels (cargo), walk or run (assassin: its rigged
	## clips, timed to `speed` in m/s; without a rig, a sway).
	## `fighting`: standing still in a fight, it holds its ready stance (the idle's
	## shuffle is for waking up and for standing about, issue #64).
	func walk(dt: float, moving: bool, speed := 0.0, fighting := false) -> void:
		_t += dt
		var model := look.get_node("Model") as Node3D
		match kind:
			"floating":
				if falling or dead or broken:
					return
				lift_now = move_toward(lift_now, look_lift, dt * 0.8)
				look.position.y = lift_now + sin(_t * 2.1) * 0.12
				shape.position.y = look.position.y          # issue #80: the hit box bobs with it
			"cargo":
				model.rotation.z = sin(_t * 18.0) * 0.02 if moving else 0.0
			"assassin":
				var a: Dictionary = DroidRoster.kind_cfg(kind).get("look", {})
				var played := false
				if not moving and fighting:
					played = DroidKit.hold_pose(look, "aim", float(a.get("aim_at", 0.0)))
				elif not moving:
					played = DroidKit.play_anim(look, "idle")
				elif speed >= float(a.get("run_from", 3.5)):
					played = DroidKit.play_anim(look, "run", clampf(speed / float(a.get("run_speed", 5.0)), 0.6, 1.8))
				else:
					played = DroidKit.play_anim(look, "walk", clampf(maxf(speed, 1.0) / float(a.get("walk_speed", 1.6)), 0.6, 1.8))
				if not played:
					model.rotation.x = sin(_t * 7.0) * 0.03 if moving else 0.0

	func apply_damage_from(amount: float, shooter: Node) -> void:
		if ctl != null:
			ctl.on_unit_hit(self, amount, shooter)

	func apply_damage(amount: float) -> void:
		apply_damage_from(amount, null)

	## Issue #372: a blast (Blast.hit). Anyone's droid goes up (`wreck`); yours is
	## knocked out like any hit that takes it to nothing (`amount`).
	func apply_blast(amount: float, _from: Vector3, shooter: Node, wreck := 0.0, _reach := 0.0) -> void:
		if ctl != null:
			ctl.on_unit_blast(self, amount, shooter, wreck)

	## The player's energy sword calls this instead: a killing cut bats it along `sweep`.
	func apply_blade_hit(amount: float, sweep: Vector3) -> void:
		if ctl != null:
			ctl.on_unit_hit(self, amount, null, sweep)
