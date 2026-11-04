extends GutTest
## The backpack (five slots, the pistol in the first, activated gear riding free),
## the droid merchant's upgrades (health, cargo racks, gun damage; a cargo droid
## starts with two hold slots), your droids taking hits and rebooting, and your
## gun droids walking ten steps toward what they see and coming back.


func before_each() -> void:
	WorldState.reset()


# ---- the backpack -------------------------------------------------------------

func test_pistol_holds_the_first_of_five_slots() -> void:
	var inv := Inventory.new()
	assert_eq(Inventory.backpack_slots(), 5)
	assert_eq(inv.slots_used(), 1, "the pistol")
	for id in ["holocrystals", "food", "quartz", "energy_blade"]:
		assert_true(inv.room_for(id))
		inv.add(id)
	assert_eq(inv.slots_used(), 5)
	assert_false(inv.room_for("unmarked_cells"), "full")
	assert_true(inv.room_for("food"), "a stack takes no new slot")


func test_activated_gear_rides_free() -> void:
	var inv := Inventory.new()
	var pack := { "slot": "back" }
	inv.add("jetpack")
	assert_eq(inv.slots_used(), 2, "a jetpack in the backpack takes a slot")
	inv.attach("jetpack", pack)
	assert_eq(inv.slots_used(), 1, "activated, it does not")
	for id in ["holocrystals", "food", "quartz", "energy_blade"]:
		inv.add(id)
	assert_eq(inv.slots_free(), 0)
	assert_true(inv.room_for("quantonium_armour", { "slot": "armour" }), "goes straight on")
	assert_false(inv.room_for("quantonium_armour"), "but not into the backpack")


func test_room_for_all_and_paying() -> void:
	var inv := Inventory.new()
	inv.add("food", 2)
	inv.add("holocrystals")
	inv.add("quartz")
	assert_true(inv.room_for_all({ "unmarked_cells": 1, "food": 3 }))
	assert_false(inv.room_for_all({ "unmarked_cells": 1, "space_whale_teeth": 1 }))
	inv.add("energy_blade")
	assert_true(inv.room_after_paying("rifle_blaster", "food", 2), "the last food frees its slot")
	assert_false(inv.room_after_paying("rifle_blaster", "food", 1))


# ---- the droid merchant's upgrades -------------------------------------------------

func test_cargo_droid_starts_with_two_slots() -> void:
	var r := WorldState.droids
	var inv := WorldState.inventory
	var d := r.add("cargo", "tan")
	assert_eq(DroidRoster.cargo_slots(d), 2)
	for id in ["holocrystals", "unmarked_cells", "quartz"]:
		inv.add(id, 2)
	assert_true(r.stash(int(d.uid), inv, "holocrystals", 2))
	assert_true(r.stash(int(d.uid), inv, "unmarked_cells", 2))
	assert_false(r.stash(int(d.uid), inv, "quartz", 2), "a third kind does not fit")
	assert_eq(inv.count("quartz"), 2, "and stays in the pockets")
	inv.add("holocrystals")
	assert_true(r.stash(int(d.uid), inv, "holocrystals"), "more of a kind it holds does")
	assert_eq(r.upgrade(int(d.uid), "cargo", 190).get("level"), 1)
	assert_eq(DroidRoster.cargo_slots(d), 8, "one buy: the racks at their top")
	assert_true(r.stash(int(d.uid), inv, "quartz", 2))


func test_upgrades_by_kind_price_and_cap() -> void:
	var r := WorldState.droids
	assert_eq(DroidRoster.upgrades_for("cargo"), ["health", "cargo"])
	assert_eq(DroidRoster.upgrades_for("assassin"), ["health", "damage"])
	assert_eq(DroidRoster.upgrades_for("floating"), ["health", "damage"])
	var a := r.add("assassin", "bone")
	assert_eq(r.upgrade(int(a.uid), "cargo", 999).get("error"), "unknown", "an assassin has no hold")
	assert_eq(r.upgrade(int(a.uid), "damage", 10).get("error"), "cant_afford")
	var base_hp := DroidRoster.health(a)
	assert_eq(base_hp, 120.0)
	assert_eq(DroidRoster.upgrade_max("health"), 1, "one level each")
	assert_eq(int(r.upgrade(int(a.uid), "health", 999).cost), 260)
	assert_eq(r.upgrade(int(a.uid), "health", 999).get("error"), "maxed")
	assert_almost_eq(DroidRoster.health(a), base_hp * 2.5, 0.01)
	r.upgrade(int(a.uid), "damage", 999)
	assert_almost_eq(DroidRoster.damage_mult(a), 2.05, 0.001)


func test_upgrades_survive_a_save() -> void:
	var r := WorldState.droids
	var c := r.add("cargo", "tan")
	r.upgrade(int(c.uid), "cargo", 999)
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	var back: Dictionary = WorldState.droids.owned[0]
	assert_eq(DroidRoster.level(back, "cargo"), 1)
	assert_eq(DroidRoster.cargo_slots(back), 8)


func test_old_saves_levels_count_as_the_top() -> void:
	WorldState.droids.from_save({ "owned": [{ "uid": 4, "kind": "cargo", "variant": "gold", "cargo": {}, "up": { "cargo": 2, "health": 3 } }] })
	var d: Dictionary = WorldState.droids.owned[0]
	assert_eq(DroidRoster.level(d, "cargo"), 1)
	assert_eq(DroidRoster.cargo_slots(d), 8, "not past the top")
	assert_eq(DroidRoster.upgrade_price(d, "health"), -1, "nothing left to buy")


func test_unload_stops_at_a_full_backpack() -> void:
	var r := WorldState.droids
	var inv := WorldState.inventory
	var c := r.add("cargo", "tan")
	inv.add("holocrystals")
	inv.add("unmarked_cells")
	r.stash(int(c.uid), inv, "holocrystals")
	r.stash(int(c.uid), inv, "unmarked_cells")
	for id in ["food", "quartz", "energy_blade"]:
		inv.add(id)
	assert_eq(inv.slots_free(), 1)
	assert_false(r.cargo_fits(int(c.uid), inv))
	assert_eq(r.unload(int(c.uid), inv), 1, "one kind fits")
	assert_eq(c.cargo.size(), 1, "the other waits in the hold")


# ---- your droids in a fight ---------------------------------------------------------

class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false


func _scene() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	root.add_child(ctl)
	return [ctl, p, root]


func test_hits_knock_your_droid_out_and_it_reboots() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	var d := WorldState.droids.add("floating", "rust")
	var u = ctl._spawn_companion(d, Vector3(2, 0, 0))
	assert_eq(u.max_hp, 40.0)
	ctl.on_unit_hit(u, 30.0, p)
	assert_eq(u.hp, 40.0, "your own shots never hurt it")
	var foe := Node3D.new()
	add_child_autofree(foe)
	ctl.on_unit_hit(u, 30.0, foe)
	assert_eq(u.hp, 10.0)
	ctl.on_unit_hit(u, 30.0, foe)
	assert_true(u.dead, "knocked out")
	ctl._tick_knocked_out(float(DroidRoster.config().get("knocked_out_s", 20.0)) + 0.1)
	var back = ctl.companions[int(d.uid)]
	assert_ne(back, u, "a fresh body")
	assert_false(back.dead)
	assert_eq(back.hp, back.max_hp)


func test_gun_droid_walks_ten_steps_then_comes_back() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var d := WorldState.droids.add("assassin", "bone")
	var u = ctl._spawn_companion(d, Vector3.ZERO)
	var foe := Node3D.new()
	s[2].add_child(foe)
	foe.global_position = Vector3(0, 0, -20)
	u.target = foe
	ctl._engage(u, [foe])
	assert_eq(u.engaged, foe)
	var goal: Vector3 = ctl._advance_goal(u)
	assert_almost_eq(goal.distance_to(Vector3.ZERO), 7.5, 0.01, "about ten steps")
	foe.global_position = Vector3(0, 0, -5)
	assert_almost_eq(ctl._advance_goal(u).distance_to(Vector3.ZERO), 2.0, 0.01, "never closer than the standoff")
	u.target = null
	ctl._engage(u, [])
	assert_null(u.engaged, "its enemy is gone")
	assert_eq(u.engage_from, Vector3.INF)
	assert_true(u.following, "back to you")
	var c = ctl._spawn_companion(WorldState.droids.add("cargo", "tan"), Vector3.ZERO)
	c.target = foe
	ctl._engage(c, [foe])
	assert_null(c.engaged, "a cargo droid never goes after anyone")


# ---- the shiny look ------------------------------------------------------------------

func test_base_look_until_any_upgrade_then_shiny() -> void:
	var r := WorldState.droids
	var picks := { "floating": ["rust", "chrome"], "cargo": ["tan", "gold"], "assassin": ["gunmetal", "chrome"] }
	for kind in picks:
		var d := r.add(kind, DroidRoster.pick_variant(kind, RandomNumberGenerator.new()))
		assert_eq(d.variant, picks[kind][0], "%s starts in its base look" % kind)
		r.upgrade(int(d.uid), "health", 999)
		assert_eq(d.variant, picks[kind][1], "%s: any upgrade makes it shiny" % kind)
		assert_false(DroidRoster.variant_cfg(kind, d.variant).get("shine", {}).is_empty())
		r.remove(int(d.uid))


func test_old_saves_take_the_base_look() -> void:
	WorldState.droids.from_save({ "owned": [{ "uid": 3, "kind": "cargo", "variant": "olive", "cargo": {} }] })
	assert_eq(WorldState.droids.owned[0].variant, "tan")


func test_first_upgrade_rebuilds_it_shiny() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var d := WorldState.droids.add("cargo", "tan")
	var u = ctl._spawn_companion(d, Vector3(3, 0, 0))
	WorldState.credits = 500
	assert_eq(ctl.upgrade(int(d.uid), "cargo"), "upgraded")
	var shiny = ctl.companions[int(d.uid)]
	assert_ne(shiny, u, "a new body")
	assert_eq(shiny.variant, "gold")
	assert_almost_eq(shiny.global_position.x, 3.0, 0.01, "where it stood")
	assert_eq(ctl.upgrade(int(d.uid), "health"), "upgraded")
	assert_eq(ctl.companions[int(d.uid)], shiny, "already shiny: no rebuild")


# ---- stash one, stash all -----------------------------------------------------------

func _hold_row(ctl: DroidController, item: String) -> Dictionary:
	for o in ctl.menu.options:
		if str(o.id) == "stash:" + item:
			return o
	return {}


func test_hold_stashes_one_or_the_whole_stack() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var inv := WorldState.inventory
	var c := WorldState.droids.add("cargo", "tan")
	inv.add("holocrystals", 3)
	inv.add("food")
	ctl.focus = { "kind": "cargo", "uid": int(c.uid) }
	assert_eq(ctl.interact(), "menu")
	var row := _hold_row(ctl, "holocrystals")
	assert_eq(str(row.get("alt", "")), "stash_all:holocrystals", "Shift+Enter stashes the stack")
	var ids := []
	for b in row.get("buttons", []):
		ids.append(str(b.id))
	assert_eq(ids, ["stash:holocrystals", "stash_all:holocrystals"], "Stash one and Stash all buttons")
	assert_false(_hold_row(ctl, "food").has("alt"), "a single item has no stash-all")
	assert_eq((_hold_row(ctl, "food").get("buttons", []) as Array).size(), 1, "just a Stash button")
	assert_true(ctl.menu.hint.text.contains("Shift+Enter"), "the key hint names Shift+Enter")

	ctl.menu.choose("stash:holocrystals")
	assert_eq(inv.count("holocrystals"), 2, "Enter stashes one")
	assert_eq(int(c.cargo.get("holocrystals", 0)), 1)
	assert_true(ctl.menu.is_open(), "the hold stays open for the next one")

	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	key.shift_pressed = true
	ctl.menu.selected = ctl.menu.options.find(_hold_row(ctl, "holocrystals"))
	ctl.menu._input(key)
	assert_eq(inv.count("holocrystals"), 0, "Shift+Enter stashes the rest")
	assert_eq(int(c.cargo.get("holocrystals", 0)), 3)
	assert_true(_hold_row(ctl, "holocrystals").is_empty(), "nothing left of it to stash")

	ctl.menu.choose("stash_all:food")
	assert_eq(int(c.cargo.get("food", 0)), 1, "stash all of one is one")
	ctl.menu.choose("")
	assert_false(ctl.menu.is_open())
