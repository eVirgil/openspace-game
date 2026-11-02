extends GutTest
## Issue #58: T-89, the ship salesman in the pit. He stocks every ship that flies
## in the atmosphere (not the Remnant's space-only fighters), says hello once a run
## and offers the tutorial (it explains the weapons the player already carries),
## nothing hurts him, and a ship bought from him lands on the empty pad, can be
## boarded like any parked ship, is kept in the save, and sells back at resale.
## A player he has met before only gets a returning line. With the town's
## conversation host he is an AI character who reads every ship's numbers and
## recommends one. He is solid.

const TownDemo := preload("res://scenes/town_demo.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64: the story unlocks the ships
	ShipSalesman.greeted = false


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


# ---- data -------------------------------------------------------------------

func test_stock_is_every_ship_that_flies_in_the_atmosphere() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	assert_not_null(s, "T-89 is in the town")
	var stock := s.stock()
	for id in ["interceptor", "courier", "gunship", "freighter"]:
		assert_true(stock.has(id), "%s is for sale" % id)
	assert_false(stock.has("remnant_fighter"), "space-only fighters are not")
	assert_eq(s.price(stock[0]), stock.map(s.price).min(), "cheapest first")
	assert_lt(s.resale("courier"), s.price("courier"), "he buys back for less")
	assert_eq(s.npc_name(), "T-89")


func test_tutorial_explains_the_weapons_the_player_already_has() -> void:
	var t = _town()
	var pages: Array = t.salesman.tutorial_pages()
	assert_gt(pages.size(), 3)
	var all := " ".join(pages)
	for word in ["pistol", "blade", "rifle", "holster", "board"]:
		assert_true(all.to_lower().contains(word), "the tutorial mentions %s" % word)


# ---- hello and tutorial ------------------------------------------------------

func test_greets_once_and_runs_the_tutorial() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	await wait_physics_frames(3)
	assert_false(s.menu.is_open(), "a headless run never greets on its own")
	s.greet()
	assert_true(ShipSalesman.greeted, "once per run")
	assert_true(WorldState.has_flag(ShipSalesman.MET_FLAG), "the save remembers he has met you")
	assert_true(s.menu.is_open())
	assert_true(s.said.begins_with(str(s.cfg.greeting)), "hello first")
	assert_eq(s.menu.options.size(), 2, "then the tutorial offer: yes or no")
	assert_true(t._player.locked, "the player stands still while he talks")
	s.menu.choose("yes")
	var pages: int = s.tutorial_pages().size()
	for i in pages - 1:
		assert_eq(s.page, i)
		assert_true(s.card.is_open(), "the page is on the small card, not a menu")
		assert_false(s.menu.is_open())
		assert_eq(s.card.body_label.text, str(s.tutorial_pages()[i]))
		s.advance_tutorial()
	assert_eq(s.page, pages - 1, "last page")
	s.advance_tutorial()
	assert_eq(s.page, -1)
	assert_false(s.card.is_open())
	await wait_physics_frames(2)
	assert_false(t._player.locked, "free to walk again")


func test_you_can_walk_the_pit_while_the_tutorial_runs() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	s.greet()
	s.menu.choose("yes")
	await wait_physics_frames(3)
	assert_eq(s.page, 0, "still on the first page")
	assert_false(t._player.locked, "nothing holds the player")
	t._player.global_position = s.pos + Vector3(8, 0.05, 6)     # across the pit
	await wait_physics_frames(3)
	assert_eq(s.page, 0, "still in the pit: the tutorial goes on")
	assert_true(s.card.is_open())


func test_leaving_the_pit_ends_the_tutorial() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	assert_true(s.pit_rect.has_area(), "the pit is the sunken floor under him")
	s.start_tutorial()
	await wait_physics_frames(2)
	assert_eq(s.page, 0)
	t._player.global_position = Vector3(s.pit_rect.end.x + 3.0, 0.0, s.pit_rect.get_center().y)     # up the ramp, on the street
	await wait_physics_frames(2)
	assert_eq(s.page, -1, "the tutorial is over")
	assert_false(s.card.is_open())
	assert_eq(s.said, str(s.lines.tutorial_left))
	assert_false(t._player.locked)


func test_his_menu_takes_over_from_the_tutorial() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	s.start_tutorial()
	s.talk()
	assert_eq(s.page, -1, "one thing at a time")
	assert_false(s.card.is_open())
	assert_true(s.menu.is_open())


func test_a_player_he_has_met_gets_a_returning_line() -> void:
	WorldState.set_flag(ShipSalesman.MET_FLAG)      # as loaded from an earlier game's save
	var t = _town()
	var s: ShipSalesman = t.salesman
	s.greet()
	assert_true(ShipSalesman.greeted)
	assert_false(s.menu.is_open(), "no hello, no tutorial offer")
	assert_false(t._player.locked, "nothing in the player's way")
	assert_has(s.cfg.returning, s.said, "one of his returning lines")
	assert_true(" ".join(s.cfg.returning).contains("multiple ships for sale"))


func test_skip_the_tutorial() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	s.greet()
	s.menu.choose("no")
	assert_eq(s.page, -1)
	assert_eq(s.said, str(s.lines.skipped))
	s.talk()
	assert_true(s.menu.options.any(func(o): return o.id == "tutorial"), "he offers it again any time")
	s.menu.choose("tutorial")
	assert_eq(s.page, 0)
	s.skip_tutorial()
	assert_eq(s.page, -1)
	assert_false(s.card.is_open())
	assert_eq(s.said, str(s.lines.skipped))


func test_nothing_hurts_him() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var n: Node = s.body
	assert_not_null(n)
	while n != null:
		assert_false(n.has_method("apply_damage") or n.has_method("apply_damage_from"),
			"%s takes no damage" % n.name)
		n = n.get_parent()
	assert_null(s.body.find_child("Muzzle", true, false), "and he carries no gun")
	var to_spawn := Vector2(t.town.spawn_pos().x - s.pos.x, t.town.spawn_pos().z - s.pos.z).length()
	assert_lt(to_spawn, 12.0, "he stands near where you start")


func test_out_of_board_reach_of_every_ship() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	t._player.global_position = s.pos + Vector3(0, 0.05, 0)
	assert_eq(t.pilot.nearest_berth(), -1, "E beside him talks to him, never boards a ship")


# ---- buying a ship -------------------------------------------------------------

func test_buy_fills_the_empty_pad_and_flies() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var pilot: ShipPilot = t.pilot
	var before := pilot.berths.size()
	WorldState.credits = 100
	assert_eq(s.buy("courier"), "cant_afford")
	assert_eq(WorldState.hangar, "")
	WorldState.credits = 5000
	assert_eq(s.buy("remnant_fighter"), "", "not for sale")
	assert_eq(s.buy("courier"), "bought")
	assert_eq(WorldState.credits, 5000 - s.price("courier"))
	assert_eq(WorldState.hangar, "courier")
	assert_eq(pilot.berths.size(), before + 1, "a new berth")
	var pad: Dictionary = t.town.get_box("spare_pad")
	var v: Node3D = s.bought_ship
	assert_almost_eq(v.global_position.x, (float(pad.min[0]) + float(pad.max[0])) * 0.5, 0.5, "on the spare pad")
	assert_almost_eq(v.global_position.z, (float(pad.min[2]) + float(pad.max[2])) * 0.5, 0.5)
	assert_eq(s.buy("gunship"), "taken", "one ship on the pad at a time")
	# Board it.
	var c: float = pilot.berths[before].clearance
	t._player.global_position = Vector3(v.global_position.x + 3.0, v.global_position.y - c, v.global_position.z)
	assert_eq(pilot.nearest_berth(), before)
	assert_true(pilot.board())
	assert_eq(pilot.ship_id, "courier")
	assert_eq(s.sell(), -1, "not while you sit in it")
	assert_true(pilot.exit_ship())
	var credits := WorldState.credits
	assert_eq(s.sell(), s.resale("courier"))
	assert_eq(WorldState.credits, credits + s.resale("courier"))
	assert_eq(WorldState.hangar, "")
	assert_eq(pilot.berths.size(), before, "its berth is gone")
	assert_eq(pilot.berth, 0, "back to the pit's own ship")
	assert_eq(s.buy("gunship"), "bought", "the pad is free again")


func test_shop_menu_lists_ships_then_sell_back() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	WorldState.credits = 5000
	s.talk()
	assert_eq(_ids(s), ["group:ships", "tutorial"], "the ship shop and the tutorial: nothing to upgrade yet")
	s.menu.choose("group:ships")
	assert_eq(s.menu.options.size(), s.stock().size() + 1, "every ship, and Back")
	s.menu.choose("buy:interceptor")
	assert_eq(WorldState.hangar, "interceptor")
	assert_true(s.menu.is_open(), "still in the ship shop after a buy")
	assert_true(_ids(s).has("sell"))
	s.menu.choose("sell")
	assert_eq(WorldState.hangar, "")
	s.menu.choose("back")
	assert_eq(_ids(s)[0], "group:ships", "Back: his top menu")


func test_upgrades_are_their_own_menu_once_you_own_a_ship() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	WorldState.credits = 5000
	s.talk()
	s.menu.choose("group:ships")
	s.menu.choose("buy:courier")
	s.menu.choose("back")
	assert_eq(_ids(s), ["group:ships", "group:upgrades", "tutorial"])
	s.menu.choose("group:upgrades")
	assert_true(_ids(s).has("fit:courier:shields"))
	assert_false(_ids(s).any(func(i): return i.begins_with("buy:")), "no ships in here")
	s.menu.choose("fit:courier:shields")
	assert_true(ShipUpgrades.has("courier", "shields"))
	assert_false(_ids(s).has("fit:courier:shields"), "fitted once, gone from the list")
	assert_eq(_ids(s)[-1], "back")


func _ids(s: ShipSalesman) -> Array:
	return s.menu.options.map(func(o): return str(o.id))


func test_bought_ship_is_saved() -> void:
	WorldState.hangar = "gunship"
	var d := WorldState.to_save()
	WorldState.reset()
	assert_eq(WorldState.hangar, "")
	WorldState.from_save(d)
	assert_eq(WorldState.hangar, "gunship")
	var t = _town()
	# Issue #368: your only ship is your primary: it waits on the pit pad, not his.
	assert_null(t.salesman.bought_ship, "not on his pad")
	assert_eq(t.pilot.berths[0].ship_id, "gunship", "on the pit pad when the town loads")
	assert_true(t.pilot.berth_flies(0))


func test_decor_parks_a_bought_ship_on_the_pad() -> void:
	var d = TownDemo.new()
	d.use_look = true
	d.lookdev_mode = true
	add_child_autofree(d)
	var pad: Dictionary = d.town.get_box("spare_pad")
	var n: int = d.decor.parked_ships.size()
	var ship: Node3D = d.decor.park_ship("freighter", pad)
	assert_not_null(ship)
	assert_eq(str(ship.get_meta("ship_id")), "freighter")
	assert_eq(d.decor.parked_ships.size(), n + 1)
	var a: AABB = TownDecor.visual_aabb(ship)
	assert_almost_eq(a.get_center().x, (float(pad.min[0]) + float(pad.max[0])) * 0.5, 0.3)
	assert_almost_eq(a.get_center().z, (float(pad.min[2]) + float(pad.max[2])) * 0.5, 0.3)


# ---- the AI salesman --------------------------------------------------------------

func _town_with_bar() -> Node:
	var t = _town()
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	t.salesman.attach_host(t.bar)
	return t


func test_his_card_has_every_ship_with_its_numbers() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var card := s.persona_card()
	assert_eq(card.ships.map(func(sh): return sh.id), s.stock(), "every ship he stocks, in order")
	var b := NpcBrain.new(null, card)
	var persona := str(b.builder.persona_message().content)
	for id in s.stock():
		assert_string_contains(persona, "%s: %d credits" % [s.ship_label(id), s.price(id)])
	var ship: Dictionary = s.content.get_ship("courier")
	assert_string_contains(persona, "Hull %d" % int(ship.hull), "real numbers from the ship file")
	assert_string_contains(persona, "Top speed %d" % int(ship.atmosphere.max_speed))
	var rules := str(b.builder.rules_message().content)
	assert_string_contains(rules, "offer_ship")
	assert_false(rules.contains("offer_job") or rules.contains("pour_drink"), "no jobs, no drinks")
	WorldState.hangar = "gunship"
	assert_string_contains(" ".join(s.pad_brief()), s.ship_label("gunship"), "he knows what is on your pad")


func test_offer_ship_takes_the_games_price() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var b := NpcBrain.new(null, s.persona_card())
	var ids: Dictionary = b.builder.briefing({}, b.rel, [], []).ids
	var v := ActionValidator.validate([{ "type": "offer_ship", "id": "courier", "price": 1 },
		{ "type": "offer_ship", "id": "remnant_fighter" }], ids, {})
	assert_eq(v.kept.size(), 1)
	assert_eq(int(v.kept[0].price), s.price("courier"), "never the model's price")
	assert_eq(str(v.dropped[0].why), "ship not for sale here")


func test_offline_he_still_recommends_a_real_ship() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var b := NpcBrain.new(null, s.persona_card())
	WorldState.credits = 5000
	var fight := b.canned_reply("Which ship should I get for fighting raiders?")
	assert_eq(str(fight.actions[0].type), "offer_ship")
	assert_eq(str(fight.actions[0].id), "gunship", "the fighter's ship")
	assert_string_contains(str(fight.say), s.ship_label("gunship"))
	var haul := b.canned_reply("I want to buy something to haul cargo")
	assert_eq(str(haul.actions[0].id), "freighter")
	WorldState.credits = s.price("courier")
	var short := b.canned_reply("Which ship should I get for fighting raiders?")
	assert_eq(str(short.actions[0].id), "courier", "the best one they can afford")
	assert_string_contains(str(short.say), s.ship_label("gunship"), "and what they should save up for")


func test_talk_from_his_shop_and_buy_on_the_price_card() -> void:
	var t = _town_with_bar()
	var s: ShipSalesman = t.salesman
	assert_true(t.bar.spots.has(s.spot), "one of the town's AI characters")
	t._player.global_position = s.pos + Vector3(1.5, 0, 0)
	assert_null(t.bar.spot_in_range(), "his own [E] (the shop) starts the talk, not the host's")
	WorldState.credits = 5000
	s.talk()
	assert_eq(str(s.menu.options[0].id), "chat", "Talk comes first")
	s.menu.choose("chat")
	assert_true(t.bar.is_talking())
	assert_eq(t.bar.active, s.spot)
	s.spot.brain.sale_offered.emit({ "id": "interceptor", "name": s.ship_label("interceptor"), "price": s.price("interceptor") })
	assert_true(t.bar.panel.job_open(), "the price card is up")
	t.bar.panel.answer_card(true)
	assert_eq(WorldState.hangar, "interceptor", "bought, onto the pad")
	assert_eq(WorldState.credits, 5000 - s.price("interceptor"))
	t.bar.end_talk()
	await wait_physics_frames(2)
	assert_false(t._player.locked, "free to walk again")


func test_he_is_solid_all_round() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var cs := s.body.get_child(0) as CollisionShape3D
	assert_true(cs.shape is CylinderShape3D, "the same whichever way he turns")
	assert_almost_eq((cs.shape as CylinderShape3D).height, 2.3, 0.01, "his full height")
	assert_true((s.body.collision_layer & 1) != 0, "on the layer the player collides with")
	await wait_physics_frames(2)
	var space := s.body.get_world_3d().direct_space_state
	for off in [Vector3(0.4, 0.3, 0), Vector3(-0.4, 1.8, 0), Vector3(0, 2.2, 0.4)]:
		var q := PhysicsPointQueryParameters3D.new()
		q.position = s.pos + off
		var hits := space.intersect_point(q)
		assert_true(hits.any(func(h): return h.collider == s.body), "solid at %s" % [off])
