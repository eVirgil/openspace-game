class_name GearController
extends Node
## Gear in a scene (M13). The thin node over the pure Inventory and Jetpack:
##   - places the location's pickups (content/core/pickups/<location>.json) and
##     knows where its vendors stand (content/core/vendors/*.json),
##   - puts Oda's smuggling drop out once the player takes her job
##     (WorldState.smuggle_drop()), and swaps it when she lines up the next one,
##   - shows a prompt when the player is in reach and acts on `interact` (E):
##     pick up, sell, buy,
##   - attaches and detaches gear on `gear_toggle` (G): the jetpack and the armour. With
##     one of them it just toggles; with both it opens a small menu (put on / take off
##     each). Picking up or buying new equipment, or a weapon, toasts the key to press.
##   - gives the player node a Jetpack while one is on its back, puts the pack's
##     look on the body's chest joint, and lights its flames while thrusting,
##   - issue #148: an item with a "blade_color" (the red saber from the wreck, or
##     the dark master's) turns the player's energy sword that colour while it is
##     activated (slot "blade", toggled in the inventory on I); off, the sword is
##     the energy blade's own again, and
##   - catches a player who flew out over the walls (the town has no ground there)
##     and puts them back where they last stood.
##
##   - issues #208, #209: the fence's offers (GearUpgrades) from a menu on [E]:
##     gun and jetpack upgrades, and quantonium armour once the first bounty is
##     paid. Worn armour (slot "armour", toggled in the inventory on I) multiplies
##     the player's health; in a story save it is the desert guard's whole look,
##   - issue #210: a pickup can be "story_only", can sit "inside" a droid (no glow,
##     "[E] Open the cargo droid"), and reports its "event" to the story when taken.
##     Issue #321: or inside a console (its "prompt": "[E] Search the console").
##   - the backpack (Inventory.room_for): picking up, buying and taking gear off
##     all need a free slot; the pistol always holds the first of five.
##   - wreck field: a supply crate on each crashed starcruiser's bridge platform
##     (pickups "site_crates"), placed once the world's ground is here; [E] opens
##     it for one prize rolled from "crate_prizes" (credits or a stack of goods).
##
## The headless trace calls interact() and toggle_gear() directly: the same code
## path the keys use. All words come from content/core/flow/gear.json.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const Jetpack := preload("res://src/systems/player/jetpack.gd")
const PickupNode := preload("res://src/systems/items/pickup_node.gd")
const LABELS_PATH := "res://content/core/flow/gear.json"
const SLOT_BACK := "back"
const SLOT_ARMOUR := "armour"
const SLOT_BLADE := "blade"
const G_SLOTS := [SLOT_BACK, SLOT_ARMOUR]   ## the slots [G] puts on and takes off
const FALL_MARGIN := 20.0       ## metres below the lowest floor before a rescue
const MOVE_HINT_SECS := 5.0
const MOVE_HINT_SETTLE := 0.5   ## free on foot this long first (a talk that opens as you step out wins)

## The move keys go up once a run, the first time you are on your feet and free.
static var move_hint_shown := false
var _free_for := 0.0

var content
var town                        ## TownLayout (marker_pos, boxes)
var player: CharacterBody3D
var rig_node: Node              ## camera rig node (first-person check), optional
var location_id := "port_town"
var items: ItemKit
var hud: GearHud
var labels: Dictionary = {}
var pickups: Array = []         ## PickupNode
var drop                        ## PickupNode: Oda's smuggling drop, while one is lying out there
var vendors: Array = []         ## { cfg, pos }
var worn: Node3D                ## the attached item's look on the body
var worn_id := ""
var focus: Dictionary = {}      ## what E would act on: { kind: "pickup"|"vendor", ... }
var recoveries := 0
var lowest_floor := 0.0
## Ground height under (x, z), when the scene has terrain (the town's desert).
## Unset: the town's lowest floor stands in for the ground everywhere.
var ground_at := Callable()
## Issue #93: the world's ground (the ship's), set once the ship is built. Out on the home
## planet's ball the fall guard asks it how high you are over the ground along its up,
## because the flat (x, z) line above is wrong past the equator.
var ground: WorldGround
## Whether the stall at a vendor marker trades right now: (marker: String) -> bool.
## Unset: always open. The town's locals close a stall while they fight, or for good
## once its keeper is dead (Townsfolk.vendor_open).
var vendor_open := Callable()
## What a closed stall says: (marker: String) -> String ("" = the "closed" label).
var closed_line := Callable()
## Issue #188: stalls whose keeper talks (the fence): vendor id -> () that opens
## the chat. "Talk" leads that stall's [E] menu.
var vendor_talk: Dictionary = {}

var _packs: Dictionary = {}     ## item id -> Jetpack (fuel survives a detach)
var menu: DroidMenu             ## a stall's trade menu: sell, buy, the fence's offers (issue #208)
var last_trade := ""            ## what the last pick in it did: "sold", "bought", "cant_afford", ...
var _trade_said := ""           ## the trade menu's body: the pitch, then what the last trade did
var on_refit := Callable()      ## issue #208: () after an upgrade (the town refits the player's guns)
var _armour_look := false       ## issue #209: the desert guard's look is on (story saves)
var _dressed := ""              ## the outfit_note of armour just put on in free roam, said after the put-on line
var _last_safe := Vector3.ZERO
var _crates_built := false      ## wreck field: the site crates are out (they need `ground`)
var rng := RandomNumberGenerator.new()   ## the crates' prizes


func setup(p_content, p_town, p_player: CharacterBody3D, p_rig: Node = null, p_location: String = "port_town") -> void:
	content = p_content
	town = p_town
	player = p_player
	rig_node = p_rig
	location_id = p_location


func inv() -> Inventory:
	return WorldState.inventory


func _ready() -> void:
	name = "Gear"
	if content == null:
		content = CoreContent.new()
		content.load_from()
	var raw = ItemKit._read_json(LABELS_PATH)
	labels = raw.get("labels", {}) if raw is Dictionary else {}
	items = ItemKit.new()
	hud = GearHud.new()
	add_child(hud)
	menu = DroidMenu.new()
	add_child(menu)
	lowest_floor = _lowest_floor()
	if player != null:
		_last_safe = player.global_position
	rng.randomize()
	_build_pickups()
	_build_site_crates()
	_build_vendors()
	sync_gear()


func _l(key: String) -> String:
	return str(labels.get(key, key))


func floor_below(p: Vector3) -> float:
	if ground_at.is_valid():
		return minf(float(ground_at.call(p.x, p.z)), lowest_floor if _over_town(p) else INF)
	return lowest_floor


## Fallen out of the world: under the ground by FALL_MARGIN. Away from the town on the
## ball that is measured along the ground's up; everywhere else, on world y as before.
func fell_out_of_world(p: Vector3) -> bool:
	if ground != null and ground.sphere() != null and not _town_here(p):
		return ground.height_above(p) < -FALL_MARGIN
	return p.y < floor_below(p) - FALL_MARGIN


## Over the town's footprint and on its side of the ball (not the same x, z through the
## planet on the far side).
func _town_here(p: Vector3) -> bool:
	return _over_town(p) and (ground == null or ground.sphere() == null or ground.up_at(p).y > 0.5)


func _over_town(p: Vector3) -> bool:
	if town == null:
		return false
	var b: Dictionary = town.data.get("bounds", {})
	return not b.is_empty() and p.x >= float(b.min[0]) and p.x <= float(b.max[0]) \
		and p.z >= float(b.min[1]) and p.z <= float(b.max[1])


func _lowest_floor() -> float:
	var y := 0.0
	if town != null:
		for b in town.boxes():
			y = minf(y, float(b.min[1]))
	return y


# ------------------------------------------------------------------ world

func _build_pickups() -> void:
	var layout := ""
	if town != null and "data" in town:
		layout = str(town.data.get("layout", ""))
	for entry in content.get_pickups(location_id, layout, WorldState.mode):
		if inv().is_taken(str(entry.get("id", ""))):
			continue
		if bool(entry.get("story_only", false)) and not WorldState.story_mode():
			continue
		var item: Dictionary = content.get_item(str(entry.get("item", "")))
		if item.is_empty():
			push_warning("GearController: pickup %s names an unknown item" % str(entry.get("id", "")))
			continue
		var node = PickupNode.new()
		node.setup(items, entry, item, _place(entry))
		# Issue #148: one a droid carries stays hidden (and out of reach) until
		# its carrier puts it on its back (DroidController._haul).
		node.visible = not bool(entry.get("carried", false)) and str(entry.get("inside", "")) == ""
		add_child(node)
		pickups.append(node)


## Wreck field: a supply crate on each wreck this ground holds, at its point in
## the wreck's level frame, turned to the ground's up there. Once, when the ground
## is here (it can come after the gear: _physics_process tries again).
func _build_site_crates() -> void:
	if _crates_built or ground == null:
		return
	_crates_built = true
	for entry in content.get_site_crates(location_id):
		var site := str(entry.get("site", ""))
		if inv().is_taken(str(entry.get("id", ""))) or not StarcruiserWreck.has_wreck(ground, site):
			continue
		var pt: Array = entry.get("site_point", [0, 0, 0])
		var at := StarcruiserWreck.site_point(ground, Vector3(float(pt[0]), float(pt[1]), float(pt[2])), "level", site)
		var e: Dictionary = entry.duplicate()
		e["crate"] = true
		e["still"] = true
		e["marked"] = true
		e["reach"] = float(entry.get("reach", 2.4))
		var node = PickupNode.new()
		node.setup(items, e, { "look": "prize_crate" }, at)
		node.transform = Transform3D(PlanetSphere.tilt_to(ground.up_at(at)), at)
		add_child(node)
		pickups.append(node)


## A supply crate's prize: { credits } or { item, count }, rolled by weight.
func roll_crate_prize() -> Dictionary:
	var table: Array = content.get_crate_prizes(location_id)
	var total := 0.0
	for e in table:
		total += float(e.get("weight", 1.0))
	var r := rng.randf() * total
	for e in table:
		r -= float(e.get("weight", 1.0))
		if r <= 0.0:
			return e
	return table.back() if not table.is_empty() else {}


## Issue #64: one loot box at a time. Contraband lying in the world (the desert
## cache) only shows in free play, and only while no drop of Oda's is out and
## the player carries none: it never gets in the way of the story's runs.
## A job's own goods ("job": the heist's stash, issue #309) always show.
func _sync_loose_contraband() -> void:
	var allowed := Story.chapter() == "free" and WorldState.smuggle_drop().is_empty() and not WorldState.carrying_contraband()
	for n in pickups:
		if is_instance_valid(n) and not bool(n.pickup.get("job", false)) \
				and bool(content.get_item(str(n.pickup.get("item", ""))).get("contraband", false)):
			n.visible = allowed


## Make the world match Oda's drop: place it when she puts one out, clear it
## once it is taken. Cheap; called every frame.
func sync_drop() -> void:
	_sync_loose_contraband()
	var want := WorldState.smuggle_drop()
	if str(want.get("location", "")) not in ["", location_id]:
		want = {}               # issue #75: taken on another planet; the drop is in its own town
	var have := str(drop.pickup.get("id", "")) if drop != null and is_instance_valid(drop) else ""
	if str(want.get("id", "")) == have:
		return
	if have != "":
		drop.queue_free()
	drop = null
	if want.is_empty():
		return
	var item: Dictionary = content.get_item(str(want.item))
	if item.is_empty():
		push_warning("GearController: smuggling drop names an unknown item")
		return
	drop = PickupNode.new()
	drop.setup(items, want, item, _place(want))
	add_child(drop)


func _build_vendors() -> void:
	for v in content.vendors_in(location_id):
		vendors.append({ "cfg": v, "pos": _place(v) })


## A data entry's world position: its town marker plus its offset.
func _place(entry: Dictionary) -> Vector3:
	var off: Array = entry.get("offset", [0, 0, 0])
	var at := Vector3.ZERO
	if town != null and not town.get_marker(str(entry.get("marker", ""))).is_empty():
		at = town.marker_pos(str(entry.get("marker", "")))
	at += Vector3(float(off[0]), float(off[1]), float(off[2]))
	# Out in the desert the sand is not flat: sit on it, never under it. A drop
	# on open rock (surface) sits exactly on the ground, even below the marker's
	# height.
	if bool(entry.get("ground", false)) and ground_at.is_valid():
		var floor_y := float(ground_at.call(at.x, at.z))
		at.y = floor_y if bool(entry.get("surface", false)) else maxf(at.y, floor_y)
	return at


## Something dropped where it fell (the dark master's blade, issue #303): a pickup
## entry ({ id, item, reach }) lying at `at` (world). Taken once, like the rest;
## not saved while it lies there. Returns the node, or null (taken, unknown item).
func drop_item(entry: Dictionary, at: Vector3) -> Node3D:
	var item: Dictionary = content.get_item(str(entry.get("item", ""))) if content != null else {}
	if item.is_empty() or inv().is_taken(str(entry.get("id", ""))) or pickup_node(str(entry.get("id", ""))) != null:
		return null
	var node = PickupNode.new()
	node.setup(items, entry, item, at)
	add_child(node)
	pickups.append(node)
	return node


func pickup_node(pickup_id: String) -> Node3D:
	for n in pickups:
		if is_instance_valid(n) and str(n.pickup.get("id", "")) == pickup_id:
			return n
	return null


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if player.piloting:
		focus = {}
		if hud != null:
			hud.set_prompt("")
		return
	sync_drop()
	_build_site_crates()
	focus = _find_focus()
	if hud != null:
		hud.set_prompt("" if menu.is_open() else prompt_text())
	if not player.locked:
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			interact()
		if InputMap.has_action("gear_toggle") and Input.is_action_just_pressed("gear_toggle"):
			toggle_gear()
	sync_gear()                 # cheap; catches a body attached later or a save loaded
	_update_worn_view()
	if DisplayServer.get_name() != "headless":
		_tick_move_hint(dt)     # tests and traces read the toasts they make
	var jet = player.jetpack
	if worn != null:
		ItemKit.set_flames(worn, jet != null and jet.thrusting, 1.0)
	_guard_fall()


func _tick_move_hint(dt: float) -> void:
	if move_hint_shown or hud == null:
		return
	_free_for = 0.0 if player.locked or menu.is_open() else _free_for + dt
	if _free_for >= MOVE_HINT_SETTLE:
		move_hint_shown = true
		hud.toast_after(_l("move_hint"), MOVE_HINT_SECS)     # after a toast already up (the general's hint)


func _find_focus() -> Dictionary:
	var p := player.global_position
	for n in pickups:
		if is_instance_valid(n) and (n.visible or str(n.pickup.get("inside", "")) != "") and n.in_reach(p):
			return { "kind": "pickup", "node": n }
	if drop != null and is_instance_valid(drop) and drop.in_reach(p):
		return { "kind": "pickup", "node": drop }
	for v in vendors:
		var vp: Vector3 = v.pos
		if Vector2(p.x - vp.x, p.z - vp.z).length() <= float(v.cfg.get("reach", 3.0)) and absf(p.y - vp.y) <= 2.0:
			return { "kind": "vendor", "cfg": v.cfg }
	return {}


## An item as a prompt shows it: its label and its make and model, "Jetpack
## (Redfern BX-14 Wingbeat)" (issue #15; just the label when it has no naming).
## M15: what you are carrying, the settings panel's Inventory page (on I), wired
## to this gear's item data and wear toggle.
func inventory_page() -> InventoryPanel:
	var page := InventoryPanel.new()
	page.content = content
	page.name_of = _shown
	page.toggle_item = func(id: String) -> String:
		var r := toggle_item(id)
		_say_dressed()
		return r
	return page


func _shown(item: Dictionary, id: String) -> String:
	var label := str(item.get("label", id))
	var model := NameHooks.equipment(item, id)
	return ("%s (%s)" % [label, model]) if model != "" else label


## What the prompt says right now ("" when nothing is in reach).
func prompt_text() -> String:
	if focus.is_empty():
		return ""
	if focus.kind == "pickup":
		if str(focus.node.pickup.get("inside", "")) != "":
			return _l(str(focus.node.pickup.get("prompt", "open_droid")))   # issue #321: a console's "search_console"
		if bool(focus.node.pickup.get("crate", false)):
			return _l("open_crate")
		var item: Dictionary = content.get_item(str(focus.node.pickup.get("item", "")))
		return _l("pick_up") % _shown(item, str(focus.node.pickup.get("item", "")))
	var v: Dictionary = focus.cfg
	if not is_open(v):
		var said: String = closed_line.call(str(v.get("marker", ""))) if closed_line.is_valid() else ""
		return said if said != "" else _l("closed") % str(v.get("label", "vendor")).to_lower()
	if bool(v.get("bounties", false)) and Heist.collectable("fence"):
		return Heist.line("collect") % int(Heist.pay("fence", Heist.carrying()).net)     # issue #310
	if bool(v.get("bounties", false)) and WorldState.bounty_collectable():
		return str(Story.bounty_cfg().get("collect", "%s %d")) % [str(WorldState.bounty.name), int(WorldState.bounty.pay)]
	var opts := trade_options(v)
	if (opts.size() == 1 and str(opts[0].id) == "talk") or talks_first(v):
		return _l("talk_to") % str(v.get("label", "vendor")).to_lower()
	if not opts.is_empty():
		return _l("trade") % str(v.get("label", "vendor")).to_lower()
	if v.has("pitch"):
		return str(v.pitch) % str(v.get("label", "vendor")).to_lower()
	return _l("nothing_to_trade") % str(v.get("label", "vendor")).to_lower()


## Every owned item this vendor buys (the attached one first).
func _sellable(v: Dictionary) -> Array:
	var ids := inv().item_ids()
	var back := inv().in_slot(SLOT_BACK)
	if back != "":
		ids.erase(back)
		ids.push_front(back)
	return ids.filter(func(id): return Inventory.sell_price(content.get_item(str(id)), v) >= 0)


## A stall's menu: talk (a keeper with a brain), what it buys from you, what it
## sells, and the fence's offers. [{ id, text, job? }]; empty = nothing to trade.
## While a smuggling run for this stall waits on the sale, the goods that close it
## come first, marked "job" (the menu shows them green, the cursor on them), the
## drop's own goods at the very top.
func trade_options(v: Dictionary) -> Array:
	var out: Array = []
	if v.has("offers") and vendor_talk.has(str(v.get("id", ""))):
		out.append({ "id": "talk", "text": _l("talk") })     # issue #188: the fence is an AI character
	var run := bool(v.get("buys", []).has("contraband")) and WorldState.fence_run_open(str(v.get("location", "")))
	var job_rows: Array = []
	for id in _sellable(v):
		var it: Dictionary = content.get_item(str(id))
		var shown := _shown(it, str(id)) + (_l("worn") if inv().in_slot(str(it.get("slot", ""))) == str(id) else "")
		var n := inv().count(str(id))
		var price := Inventory.sell_price(it, v)
		var row := { "id": "sell:" + str(id),
			"text": _l("sell_row_many") % [shown, n, price] if n > 1 else _l("sell_row") % [shown, price] }
		if run and bool(it.get("contraband", false)):
			row["job"] = true
			if str(id) == str(WorldState.smuggle.get("item", "")):
				job_rows.push_front(row)
			else:
				job_rows.append(row)
		else:
			out.append(row)
	out = job_rows + out
	var stock := inv().vendor_stock(v)
	var seen := {}
	for id in stock:
		if seen.has(id):
			continue
		seen[id] = true
		var it: Dictionary = content.get_item(str(id))
		var cost := Inventory.buy_price(it, v)
		var text := _l("buy_row") % [_shown(it, str(id)), cost]
		if cost > WorldState.credits:
			text = _l("buy_row_poor") % [_shown(it, str(id)), cost, WorldState.credits]
		out.append({ "id": "buy:" + str(id), "text": text })
	if bool(v.get("bounties", false)) and Heist.on() and Heist.pays_to() == "fence" and not Heist.holding():
		out.append({ "id": "heist_off", "text": Heist.line("call_off") })     # issue #310
	if v.has("offers"):
		for o in GearUpgrades.open_offers():
			out.append({ "id": "offer:" + str(o.id), "text": _l("offer") % [str(o.label), int(o.price), str(o.get("about", ""))] })
		for o in GearUpgrades.locked_offers():
			out.append({ "id": "locked:" + str(o.id), "text": _l("offer_locked") % [str(o.label), int(o.price), str(o.locked)] })
	return out


# ------------------------------------------------------------------ actions

## Act on whatever is in reach. Returns what happened: "picked_up", "menu" (a
## stall's trade menu opened), "bounty" (paid one out), or "" for nothing.
func interact() -> String:
	if focus.is_empty() and player != null:
		focus = _find_focus()
	if focus.is_empty():
		return ""
	if focus.kind == "pickup":
		return _take(focus.node)
	return _trade(focus.cfg)


func _take(node) -> String:
	var entry: Dictionary = node.pickup
	if bool(entry.get("crate", false)):
		return _open_crate(node)
	var id := str(entry.get("item", ""))
	var item: Dictionary = content.get_item(id)
	if not inv().is_taken(str(entry.get("id", ""))) and not inv().room_for(id, item):
		_full()
		return "full"
	if not inv().pick_up(entry):
		return ""
	if str(entry.get("taken_flag", "")) != "":
		WorldState.set_flag(str(entry.taken_flag))
	Story.event(str(entry.get("event", "")))     # issue #210: an optional quest done
	pickups.erase(node)
	if node == drop:
		drop = null
		QuestNews.push("cargo_found", WorldState.smuggle_goods_text())
	node.queue_free()
	focus = {}
	var msg := _l("picked_up") % str(item.get("label", id))
	# Wear it straight away if its slot is free (not one you activate yourself: "auto_on" false).
	if bool(item.get("auto_on", true)) and inv().in_slot(str(item.get("slot", ""))) == "" and inv().attach(id, item):
		msg = _l("attached") % str(item.get("label", id))
	sync_gear()
	if hud != null:
		hud.toast(msg, 4.0)
	_tips_for(id)
	return "picked_up"


## Wreck field: open a supply crate. Its prize is rolled the first time you try
## (so a full backpack does not re-roll it); goods need a free slot.
func _open_crate(node) -> String:
	var entry: Dictionary = node.pickup
	if not entry.has("prize"):
		entry["prize"] = roll_crate_prize()
	var prize: Dictionary = entry.prize
	var id := str(prize.get("item", ""))
	var item: Dictionary = content.get_item(id) if id != "" else {}
	if id != "" and not inv().room_for(id, item):
		_full()
		return "full"
	inv().taken[str(entry.get("id", ""))] = true
	var what := ""
	if id != "":
		inv().add(id, int(prize.get("count", 1)))
		what = _l("crate_items") % [int(prize.get("count", 1)), str(item.get("label", id))]
	else:
		WorldState.credits += int(prize.get("credits", 0))
		what = _l("crate_credits") % int(prize.get("credits", 0))
	WorldState.log_event(_l("event_crate") % what)
	pickups.erase(node)
	node.queue_free()
	focus = {}
	sync_gear()
	if hud != null:
		hud.toast(_l("crate_opened") % what, 4.0)
	return "opened"


## False while the stall's keeper will not deal (see vendor_open).
func is_open(v: Dictionary) -> bool:
	return not vendor_open.is_valid() or bool(vendor_open.call(str(v.get("marker", ""))))


func _trade(v: Dictionary) -> String:
	if not is_open(v):
		return ""
	if bool(v.get("bounties", false)) and Heist.collectable("fence"):
		# Issue #310: he takes the locals' heist's flasks, less the crew's cut.
		var crew := Heist.crew_name()
		var p := Heist.collect("fence")
		if hud != null:
			hud.toast(Heist.line("paid") % [int(p.net), crew, int(p.cut)], 5.0)
		return "heist"
	if bool(v.get("bounties", false)) and WorldState.bounty_collectable():
		# Issue #64: the fence pays Oda's bounties.
		var who := str(WorldState.bounty.name)
		var pay := WorldState.collect_bounty()
		if hud != null:
			hud.toast(str(Story.bounty_cfg().get("collected", "%d %s")) % [pay, who], 4.0)
		return "bounty"
	if talks_first(v):
		vendor_talk[str(v.get("id", ""))].call()
		return "talk"
	if trade_options(v).is_empty():
		return ""
	open_trade(v)
	return "menu"


## Issue #305: a keeper with a brain (the fence) talks first; his stall's menu is
## a keyword in the chat. Not while a run for his stall waits on the sale: then
## the goods go straight on his menu, as before.
func talks_first(v: Dictionary) -> bool:
	var talk: Callable = vendor_talk.get(str(v.get("id", "")), Callable())
	return talk.is_valid() and not WorldState.fence_run_open(str(v.get("location", ""))) \
		and not (bool(v.get("bounties", false)) and Heist.collectable("fence"))


## Issue #305: the fence's offers on sale now, as his offer_item's wares.
func offer_wares() -> Array:
	var out: Array = []
	for o in GearUpgrades.open_offers():
		out.append({ "id": str(o.id), "name": str(o.label), "price": int(o.price), "text": str(o.get("about", "")) })
	return out


## Issue #188, #305: stall `v`'s keeper talks (the fence): [E] starts the chat,
## "Trade" over the chat box opens his stall's menu (whose "Talk" comes back), and
## his offer_item puts one of his offers' price cards in the chat box.
func add_talk(v: Dictionary, spot: TalkSpot, host) -> void:
	var id := str(v.get("id", ""))
	vendor_talk[id] = func(): host.start_talk(spot)
	spot.shortcuts = func(): return [{ "id": "go_trade", "label": _l("key_trade") }]
	spot.on_shortcut = func(_k: String) -> void:
		host.end_talk()
		open_trade(v)
	spot.brain.wares = offer_wares
	var offered := {}
	spot.brain.item_offered.connect(func(item: Dictionary) -> void:
		if host.active != spot:
			return
		offered.clear()
		offered.merge(item)
		offered["text"] = str(GearUpgrades.offer(str(item.id)).get("about", ""))
		host.panel.show_sale(offered, WorldState.credits))
	host.panel.sale_answered.connect(func(item_id: String, accepted: bool) -> void:
		if not accepted or host.active != spot or item_id != str(offered.get("id", "")):
			return
		offered.clear()
		buy_offer(item_id)
		host.panel.set_line(_trade_said)
		host.panel.set_money(WorldState.credits, spot.brain.rel.tab))


## Sell one `id` to vendor `v`. Returns "sold" or "" (it does not buy that, or
## you have none).
func sell_item(id: String, v: Dictionary) -> String:
	var it: Dictionary = content.get_item(id)
	var price := inv().sell(id, it, v)
	if price < 0:
		return ""
	WorldState.credits += price
	WorldState.log_event(_l("event_sold") % str(it.get("label", id)).to_lower())
	if not inv().has(id):
		_packs.erase(id)
	sync_gear()
	if bool(it.get("contraband", false)):
		WorldState.on_contraband_sold()     # issue #64: a smuggling run done?
	_trade_said = _l("sold") % [str(it.get("label", id)), price]
	if hud != null:
		hud.toast(_trade_said)
	return "sold"


## Buy one `id` from vendor `v`; it goes on if its slot is free. Returns "bought",
## "cant_afford", "full" (no backpack slot) or "" (not in stock).
func buy_item(id: String, v: Dictionary) -> String:
	if not inv().vendor_stock(v).has(id):
		return ""
	var it: Dictionary = content.get_item(id)
	if not inv().room_for(id, it):
		_trade_said = Inventory.full_line()
		_full()
		return "full"
	var cost := inv().buy(id, it, v, WorldState.credits)
	if cost < 0:
		_trade_said = _l("cant_afford") % [str(it.get("label", id)), Inventory.buy_price(it, v), WorldState.credits]
		return "cant_afford"
	WorldState.credits -= cost
	WorldState.log_event(_l("event_bought") % str(it.get("label", id)).to_lower())
	if bool(it.get("auto_on", true)) and inv().in_slot(str(it.get("slot", ""))) == "":
		inv().attach(id, it)
	sync_gear()
	_trade_said = _l("bought") % [str(it.get("label", id)), cost]
	if hud != null:
		hud.toast(_trade_said)
	_tips_for(id)
	return "bought"


# ------------------------------------------------------------------ the trade menu (issues #208, #209)

## A stall's menu. Each sale or buy leaves it open with the new prices and the
## cursor where it was (keep_cursor); Esc walks away, Talk hands over to the chat.
func open_trade(v: Dictionary, keep_cursor := false) -> void:
	var opts := trade_options(v)
	if opts.is_empty():
		return
	if not keep_cursor:
		_trade_said = str(v.get("pitch", "")) % str(v.get("label", "vendor")).to_lower() if v.has("pitch") else ""
	var lock: bool = player != null and not bool(player.get("locked"))
	if lock:
		player.locked = true
	var pick := func(id: String) -> void:
		if lock:
			player.locked = false
		_on_trade(id, v)
	menu.open(_l("offers_title") % [str(v.get("label", "Vendor")), WorldState.credits], opts, pick, _trade_said, keep_cursor)


func _on_trade(id: String, v: Dictionary) -> void:
	if id == "":
		return
	if id == "talk":
		var talk: Callable = vendor_talk.get(str(v.get("id", "")), Callable())
		if talk.is_valid():
			talk.call()
		return
	if id.begins_with("sell:"):
		last_trade = sell_item(id.substr(5), v)
	elif id.begins_with("buy:"):
		last_trade = buy_item(id.substr(4), v)
	elif id.begins_with("offer:"):
		last_trade = buy_offer(id.substr(6))
	elif id == "heist_off":
		Heist.give_up()
		_trade_said = Heist.line("given_up")
		if hud != null:
			hud.toast(_trade_said, 4.0)
		last_trade = "heist_off"
	elif id.begins_with("locked:"):
		var o := GearUpgrades.offer(id.substr(7))
		_trade_said = _l("offer_locked_toast") % [str(o.label), str(o.locked)]
		last_trade = "locked"
	open_trade(v, true)


## Buy one of the fence's offers. Returns GearUpgrades.buy's answer.
func buy_offer(id: String) -> String:
	var o := GearUpgrades.offer(id)
	var r := GearUpgrades.buy(id)
	if r == "bought":
		refit()
		_trade_said = _l("offer_bought") % str(o.label)
	elif r == "cant_afford":
		_trade_said = _l("offer_cant_afford") % [str(o.label), int(o.price), WorldState.credits]
	elif r == "full":
		_trade_said = Inventory.full_line()
	if r in ["bought", "cant_afford", "full"] and hud != null:
		hud.toast(_trade_said, 4.0)
	if r == "bought" and o.has("item"):
		_tips_for(str(o.item))
	return r


## The backpack has no slot for it.
func _full() -> void:
	if hud != null:
		hud.toast(Inventory.full_line(), 4.0)


## Taking `id` off puts it in the backpack: false (and says so) with no slot free.
func _room_to_take_off(id: String) -> bool:
	if inv().slots_free() > 0:
		return true
	if hud != null:
		hud.toast(_l("no_room_to_take_off") % str(content.get_item(id).get("label", id)).to_lower(), 4.0)
	return false


## An upgrade went on: the jetpack takes its new tank, the guns their new numbers.
func refit() -> void:
	_packs.clear()
	sync_gear()
	if on_refit.is_valid():
		on_refit.call()


## Issue #209: put on or take off a worn item (the inventory's button): the
## jetpack on the back, the armour. Returns "attached", "detached", "full" (no
## backpack slot to take it off into) or "".
func toggle_item(id: String) -> String:
	var item: Dictionary = content.get_item(id)
	if inv().is_attached(id):
		if not _room_to_take_off(id):
			return "full"
		inv().detach(id)
		sync_gear()
		return "detached"
	if inv().has(id) and str(item.get("slot", "")) != "":
		var on := inv().in_slot(str(item.slot))
		if on != "":
			inv().detach(on)
		if inv().attach(id, item):
			sync_gear()
			_dressed = _dress_in(item)
			return "attached"
	return ""


## Free roam: putting on armour with an "outfit" dresses the player in it (saved,
## like a pick in the character builder) and says so ("outfit_note"); the
## builder (F11, Character) changes it back. A story save's armour is its look
## only while worn (_sync_armour). Returns the note to say ("" = none).
func _dress_in(item: Dictionary) -> String:
	if WorldState.story_mode() or not item.has("outfit"):
		return ""
	PlayerOutfit.save_outfit(item.outfit)
	var avatar := player.get_node_or_null("Avatar") if player != null else null
	if avatar != null and avatar.has_method("set_outfit"):
		avatar.set_outfit(PlayerOutfit.load_outfit())
	return str(item.get("outfit_note", ""))


## The outfit note, queued behind whatever the put-on said.
func _say_dressed() -> void:
	if hud != null and _dressed != "":
		hud.toast_after(_dressed)
	_dressed = ""


## What [G] works on: the owned jetpack and armour, worn or in the pack.
func g_items() -> Array:
	var out: Array = []
	for slot in G_SLOTS:
		for id in inv().item_ids():
			if str(content.get_item(str(id)).get("slot", "")) == slot:
				out.append(str(id))
	return out


## [G]: with one piece of gear it goes on or comes off; with several (the jetpack
## and the armour) a menu asks which. Returns "attached", "detached", "full" (no
## backpack slot to take it off into), "menu" (asking) or "" (nothing to put on).
func toggle_gear() -> String:
	var ids := g_items()
	if ids.is_empty():
		if hud != null:
			hud.toast(_l("nothing_to_attach"))
		return ""
	if ids.size() > 1:
		_open_gear_menu(ids)
		return "menu"
	return _toggle_worn(str(ids[0]))


## Put `id` on or take it off, and say so.
func _toggle_worn(id: String) -> String:
	var r := toggle_item(id)
	if r in ["attached", "detached"] and hud != null:
		var item: Dictionary = content.get_item(id)
		var key := r if str(item.get("slot", "")) == SLOT_BACK else "%s_%s" % [r, str(item.get("slot", ""))]
		hud.toast(_l(key) % str(item.get("label", id)))
	_say_dressed()
	return r


func _open_gear_menu(ids: Array) -> void:
	var opts: Array = []
	for id in ids:
		var label := str(content.get_item(str(id)).get("label", id))
		opts.append({ "id": str(id), "text": _l("take_off_row" if inv().is_attached(str(id)) else "put_on_row") % label })
	var lock: bool = player != null and not bool(player.get("locked"))
	if lock:
		player.locked = true
	var pick := func(id: String) -> void:
		if lock:
			player.locked = false
		if id != "":
			_toggle_worn(id)
	menu.open(_l("gear_title"), opts, pick)


## After something new comes into the pack: the key that puts new equipment on, and
## how to change weapons. Queued behind the pickup's own toast.
func _tips_for(id: String) -> void:
	if hud == null:
		return
	var item: Dictionary = content.get_item(id)
	if G_SLOTS.has(str(item.get("slot", ""))) and not inv().is_attached(id):
		hud.toast_after(_l("new_equipment") % str(item.get("label", id)))
	if str(item.get("kind", "")) == "weapon":
		hud.toast_after(_l("weapon_tip"))


# ------------------------------------------------------------------ gear -> player

## Make the player match the inventory: a Jetpack on the node while a jetpack is
## on the back, and the worn look on the chest. Safe to call any time.
func sync_gear() -> void:
	if player == null:
		return
	var back := inv().in_slot(SLOT_BACK)
	var item: Dictionary = content.get_item(back) if back != "" else {}
	if item.has("jetpack"):
		if not _packs.has(back):
			_packs[back] = Jetpack.new(GearUpgrades.apply(item, back).jetpack)    # issue #208: the fence's tank
		player.jetpack = _packs[back]
	else:
		player.jetpack = null
	_mount_worn(back, item)
	_sync_armour()
	var avatar := player.get_node_or_null("Avatar")
	var color := blade_color()
	var hilt := blade_hilt()
	if avatar != null and avatar.has_method("set_blade_color") and (avatar.blade_color != color or avatar.blade_hilt != hilt):
		avatar.set_blade_color(color, hilt)


## Issue #209: worn armour multiplies the player's health (the hurt share kept);
## in a story save its "outfit" is the player's whole look while it is on.
func _sync_armour() -> void:
	var id := inv().in_slot(SLOT_ARMOUR)
	var item: Dictionary = content.get_item(id) if id != "" else {}
	if not "max_health" in player:
		return
	if not player.has_meta("base_health"):
		player.set_meta("base_health", int(player.max_health))
	var want := int(round(int(player.get_meta("base_health")) * float(item.get("health_mult", 1.0))))
	if int(player.max_health) != want:
		var h = player.health
		var frac := float(h.hp) / maxf(1.0, float(h.max_hp))
		player.max_health = want
		h.max_hp = want
		h.hp = maxi(1, int(round(frac * want)))
	var avatar := player.get_node_or_null("Avatar")
	var look := WorldState.story_mode() and item.has("outfit")
	if avatar == null or not avatar.has_method("set_outfit") or look == _armour_look:
		return
	_armour_look = look
	avatar.set_outfit(item.outfit if look else PlayerOutfit.load_outfit())


## Issue #148: the energy sword's colour from the activated blade (the item in the
## "blade" slot, its "blade_color"), or alpha 0 for the default.
func blade_color() -> Color:
	var item: Dictionary = content.get_item(inv().in_slot(SLOT_BLADE)) if inv().in_slot(SLOT_BLADE) != "" else {}
	return Color(str(item.blade_color)) if item.has("blade_color") else Color(0, 0, 0, 0)


## The sword's hilt model from the same item ("hilt"), or "" for the default.
func blade_hilt() -> String:
	var item: Dictionary = content.get_item(inv().in_slot(SLOT_BLADE)) if inv().in_slot(SLOT_BLADE) != "" else {}
	return str(item.get("hilt", "")) if item.has("blade_color") else ""


func _mount_worn(id: String, item: Dictionary) -> void:
	var avatar := player.get_node_or_null("Avatar")
	var want := id if avatar != null else ""
	if want == worn_id and (worn == null) == (want == ""):
		return
	if worn != null:
		worn.queue_free()
		worn = null
	worn_id = want
	if want == "":
		return
	var look_id := str(item.get("look", id))
	worn = items.build(look_id)
	worn.name = "Worn_" + id
	var chest: Node3D = avatar.joints.get("chest") if "joints" in avatar else null
	if chest == null:
		chest = avatar
	chest.add_child(worn)
	worn.transform = items.on_back_transform(look_id)
	_update_worn_view()


## First person: the worn pack casts a shadow but is not drawn (like the body).
## Checked per mesh every tick rather than on a cached view flag: the flag could
## fall out of step with the meshes and leave the pack's shoulder straps drawn
## right beside the first-person camera.
func _update_worn_view() -> void:
	if worn == null:
		return
	var fp := false
	if rig_node != null and "rig" in rig_node and rig_node.rig != null:
		fp = rig_node.rig.is_first_person()
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if fp else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in PlayerAvatar._meshes_under(worn):
		if not str(m.get_parent().get_parent().name).begins_with("Flames") and m.get_parent().name != "Flames" \
				and (m as GeometryInstance3D).cast_shadow != mode:
			(m as GeometryInstance3D).cast_shadow = mode


# ------------------------------------------------------------------ safety

## A safety net for falling through the world. With terrain, "the world" is the
## ground under the player (out in the desert that can be well below the town);
## without it, the town has ground only inside its walls, so the lowest floor
## stands in. Drop FALL_MARGIN below that and you are put back where you stood.
func _guard_fall() -> void:
	if player.is_on_floor():
		_last_safe = player.global_position
		return
	if fell_out_of_world(player.global_position):
		var up := PlanetSphere.current.up_at(_last_safe) if PlanetSphere.current != null else Vector3.UP
		player.global_position = _last_safe + up * 0.1
		if player.has_method("align_to_ground"):
			player.call("align_to_ground", true)
		else:
			player.velocity = Vector3.ZERO
			player.controller.velocity = Vector3.ZERO
			player.controller.body_pos = player.global_position
		recoveries += 1
		if hud != null:
			hud.toast(_l("recovered"), 4.0)
