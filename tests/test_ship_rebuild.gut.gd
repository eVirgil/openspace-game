extends GutTest
## Issue #206: in a story save the ship you land in is a wreck. T-89 rebuilds it
## for 500, or 1 credit once you tell him you can't stand the Remnant; then it is
## yours to fly. No free keys in the pit.

var s: ShipSalesman


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)
	s = ShipSalesman.new()          # on his own: no town, no body
	add_child_autofree(s)


func after_each() -> void:
	WorldState.reset()


func test_talking_quotes_the_rebuild_and_offers_the_quest() -> void:
	assert_string_contains(s._repair_line(), "500")
	assert_eq(Quests.state("rebuild_ship"), "open")
	assert_true(s.top_options().any(func(o): return o.id == "rebuild"))


func test_500_credits_rebuild_it() -> void:
	assert_eq(s.rebuild(), "cant_afford", "60 cr is not enough")
	WorldState.credits = 600
	assert_eq(s.rebuild(), "rebuilt")
	assert_eq(WorldState.credits, 100)
	assert_true(WorldState.owns_ship())
	assert_eq(Quests.state("rebuild_ship"), "done")
	assert_eq(s.rebuild(), "", "only once")


func test_a_comrade_pays_1_credit() -> void:
	assert_true(s.comrade())
	assert_eq(s.rebuild_price(), 1)
	assert_false(s.top_options().any(func(o): return o.id == "comrade"), "said once")
	assert_eq(s.rebuild(), "rebuilt")
	assert_eq(WorldState.credits, 59)


func test_his_story_then_down_with_the_tyrants_makes_a_comrade() -> void:
	s.talk()
	s.menu.choose("comrade")
	for i in s.remnant_pages().size():
		assert_string_contains(s.said, "(%d/%d)" % [i + 1, s.remnant_pages().size()], "his story, a page at a time")
		s.menu.choose("next")
	assert_eq(s.said, s._line("remnant_question"), "then he asks")
	s.menu.choose("down")
	assert_true(WorldState.has_flag(WorldState.COMRADE))
	assert_eq(s.rebuild_price(), 1)
	assert_false(s.menu.options.any(func(o): return o.id == "comrade"), "back on his menu, said once")


func test_siding_with_the_remnant_gets_nothing_but_you_can_ask_again() -> void:
	s.talk()
	s.menu.choose("comrade")
	s.menu.choose("skip")
	s.menu.choose("side")
	assert_false(WorldState.has_flag(WorldState.COMRADE), "no discount")
	assert_eq(s.rebuild_price(), 500)
	assert_eq(s.said, s._line("sided_remnant"), "buy a ship or leave him be")
	assert_true(s.menu.options.any(func(o): return o.id == "group:ships"), "back on his menu")
	s.menu.choose("comrade")
	s.menu.choose("skip")
	s.menu.choose("down")
	assert_true(WorldState.has_flag(WorldState.COMRADE), "the second try counts")


func test_only_your_own_ship_flies_and_it_stays_yours() -> void:
	assert_false(ShipPilot.berth_open({}, 0), "a wreck")
	assert_false(ShipPilot.berth_open({}, 1), "no free keys")
	assert_true(ShipPilot.berth_open({ "owned": true }, 2), "bought from T-89")
	WorldState.credits = 600
	s.rebuild()
	WorldState.from_save(WorldState.to_save())
	assert_true(ShipPilot.berth_open({}, 0), "rebuilt, and saved")
	assert_false(ShipPilot.berth_open({}, 1))
	WorldState.new_game(WorldState.FREEPLAY)
	assert_true(ShipPilot.berth_open({}, 1), "freeplay keys as today")
	assert_false(ShipSalesman.needs_rebuild())


func test_the_wreck_looks_it_until_rebuilt() -> void:
	var ship := Node3D.new()
	add_child_autofree(ship)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	ship.add_child(mi)
	WreckLook.apply(ship)
	assert_not_null(mi.material_overlay, "grime over the hull")
	assert_true(ship.get_children().any(func(c): return c is Decal), "scorch marks")
	WreckLook.remove(ship)
	assert_null(mi.material_overlay, "rebuilt: as it was")
	assert_false(ship.get_children().any(func(c): return c is Decal and not c.is_queued_for_deletion()))
