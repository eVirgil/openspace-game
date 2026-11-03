extends GutTest
## Issue #368: your ships. The ones you own (T-89's sale, the rebuilt wreck, stolen
## ones Skrugs cleaned up) are one saved list with a primary. The primary stands on
## the pit pad when the town loads and whenever you wake in the pit, patched up for
## T-89's fee if it was shot to pieces; the others stay where you left them. Call
## flies the primary to clear ground by where you called from, nobody chasing it.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	GameFlow.flown_ship = ""
	GameFlow.flown_key = ""
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


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---- the list ----------------------------------------------------------------

func test_owned_ships_and_the_primary_are_saved() -> void:
	assert_eq(Fleet.primary(), "", "nothing owned, no primary")
	WorldState.hangar = "courier"
	assert_eq(Fleet.primary(), Fleet.T89, "the first ship becomes the primary on its own")
	var k := Fleet.keep("remnant_fighter")
	assert_eq(Fleet.owned().map(func(e): return str(e.key)), [Fleet.T89, k])
	assert_true(ShipUpgrades.owned().has("remnant_fighter"), "T-89 can upgrade a kept stolen ship")
	assert_true(Fleet.set_primary(k))
	Fleet.remember(Fleet.T89, Transform3D(Basis(Vector3.UP, 0.5), Vector3(10, 2, -30)))
	var d := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(d)
	assert_eq(Fleet.primary(), k)
	assert_eq(Fleet.ship_of(k), "remnant_fighter")
	var xf := Fleet.spot_xf(Fleet.spot(Fleet.T89))
	assert_almost_eq(xf.origin.x, 10.0, 0.01, "where it was left, saved")
	assert_almost_eq(xf.basis.get_euler().y, 0.5, 0.01)
	Fleet.lose(k)
	assert_eq(Fleet.primary(), Fleet.T89, "the primary gone: the next one takes over")


# ---- the pit -------------------------------------------------------------------

func test_the_primary_waits_on_the_pit_pad_when_the_town_loads() -> void:
	WorldState.hangar = "courier"
	var t = _town()
	assert_eq(str(t.pilot.berths[0].ship_id), "courier", "your primary on the pit pad")
	assert_eq(t.pilot.berth_key(0), Fleet.T89)
	assert_null(t.salesman.bought_ship, "not on T-89's pad as well")


func test_waking_puts_the_primary_on_the_pad_and_moves_the_other_aside() -> void:
	WorldState.hangar = "courier"
	var k := Fleet.keep("gunship")
	Fleet.set_primary(k)
	var t = _town()
	var pilot: ShipPilot = t.pilot
	assert_eq(pilot.berth_key(0), k, "the gunship is the pit's")
	var c: int = pilot.berth_of(Fleet.T89)
	assert_gt(c, 0, "the courier is on T-89's pad")
	var spare: Vector3 = (pilot.berths[c].visual as Node3D).global_position
	var pad := pilot._pad_foot()
	assert_true(pilot.set_primary(Fleet.T89))
	pilot.woke_in_pit()
	assert_lt(_flat_dist((pilot.berths[c].visual as Node3D).global_position, pad), 1.0, "the courier is on the pit pad")
	var g: Vector3 = (pilot.berths[0].visual as Node3D).global_position
	assert_gt(_flat_dist(g, pad), 15.0, "the gunship moved off it")
	assert_gt(_flat_dist(g, spare), 10.0, "and not onto the courier's old spot either")
	assert_almost_eq(Fleet.spot_xf(Fleet.spot(k)).origin.x, g.x, 0.1, "where it stands now is where it stays")


func test_a_primary_shot_to_pieces_is_back_for_t89s_fee() -> void:
	WorldState.hangar = "courier"
	var t = _town()
	var pilot: ShipPilot = t.pilot
	pilot._wreck_berth(0, true)
	assert_true(bool(pilot.berths[0].destroyed))
	assert_eq(WorldState.hangar, "courier", "not lost for good")
	assert_true(WorldState.has_flag(Fleet.WRECKED))
	WorldState.credits = 1000
	pilot.woke_in_pit()
	assert_false(bool(pilot.berths[0].destroyed), "back on the pad")
	assert_eq(WorldState.credits, 1000 - Fleet.repair_fee("courier"), "T-89's fee paid")
	pilot._wreck_berth(0, true)
	WorldState.credits = 0
	pilot.woke_in_pit()
	assert_false(bool(pilot.berths[0].destroyed), "back even with no credits")
	assert_eq(WorldState.credits, 0)


func test_a_ship_that_is_not_the_primary_shot_to_pieces_is_gone() -> void:
	WorldState.hangar = "courier"
	var k := Fleet.keep("gunship")
	var t = _town()
	var c: int = t.pilot.berth_of(k)
	assert_gt(c, 0, "the kept gunship stands by the pit (no spot yet)")
	t.pilot._wreck_berth(c, true)
	assert_false(Fleet.owns(k), "gone from your ships")


# ---- calling ------------------------------------------------------------------

func test_call_brings_the_primary_down_by_where_you_called_from() -> void:
	WorldState.hangar = "courier"
	var t = _town()
	var pilot: ShipPilot = t.pilot
	var pad := pilot._pad_foot()
	var u := pilot.ground.up_at(pad)
	var away := pilot.ground.surface_below(pad + Vector3(260, 0, 180) + u * 300.0)
	t._player.global_position = away + u * 0.05
	assert_eq(pilot.call_ship(), "")
	assert_true(pilot.calling)
	assert_false(bool(pilot.call_state().ok), "no second call until she is down")
	assert_eq(pilot.nearest_berth(), -1, "nothing to board while she flies herself")
	var seen_up := false
	for i in 3000:
		pilot._call_step(0.05)
		if pilot.atmo.state == AtmoFlight.State.FLYING:
			seen_up = true
			assert_false(pilot.targetable(), "nobody fights a ship flying herself")
			assert_false(pilot.hostile_in_town())
		if not pilot.calling:
			break
	assert_true(seen_up, "she flew")
	assert_false(pilot.calling, "she landed")
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED)
	assert_eq(pilot.calls, 1)
	var d := _flat_dist(pilot.atmo.position(), away)
	assert_lt(d, GameFlow.setting("call_land_radius", 150.0), "down within reach of the call point (%.0f m)" % d)
	assert_almost_eq(Fleet.spot_xf(Fleet.spot(Fleet.T89)).origin.x, pilot.atmo.position().x, 0.1, "remembered there")
	assert_eq(pilot.call_ship(), "call_here", "already beside you")


func test_call_from_another_planet_comes_down_out_of_the_sky() -> void:
	WorldState.hangar = "courier"
	Fleet.remember(Fleet.T89, Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)))
	WorldState.ship_spots[Fleet.T89]["planet"] = "somewhere_else"
	WorldState.story = { "chapter": "free", "told": true }
	WorldState.mode = WorldState.STORY           # the pit pad stays the wreck's: the courier is not here
	var t = _town()
	var pilot: ShipPilot = t.pilot
	assert_eq(pilot.berth_of(Fleet.T89), -1, "left on another planet")
	assert_eq(pilot.call_ship(), "")
	var i := pilot.berth_of(Fleet.T89)
	assert_gt(i, -1, "she is here now, in the sky")
	assert_gt(pilot.atmo.agl(), 200.0)
	for n in 3000:
		pilot._call_step(0.05)
		if not pilot.calling:
			break
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "and down")


# ---- free roam's own interceptor ------------------------------------------------

func test_a_free_roam_game_owns_its_interceptor_and_can_call_it() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	WorldState.set_flag(WorldState.FREE_OPENING, false)
	assert_eq(Fleet.primary(), Fleet.FREE, "yours from the start")
	assert_eq(Fleet.ship_of(Fleet.FREE), "interceptor")
	var t = _town()
	var pilot: ShipPilot = t.pilot
	assert_eq(pilot.berth_key(0), Fleet.FREE, "the pit pad's ship is yours")
	var pad := pilot._pad_foot()
	var u := pilot.ground.up_at(pad)
	t._player.global_position = pilot.ground.surface_below(pad + Vector3(200, 0, 150) + u * 300.0) + u * 0.05
	assert_true(bool(pilot.call_state().ok))
	assert_eq(pilot.call_ship(), "", "Call works in free roam")
	assert_true(pilot.calling)


func test_a_free_roam_save_from_before_gets_its_interceptor_and_a_story_save_does_not() -> void:
	WorldState.story = { "chapter": "free", "told": true }
	var d := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(d)
	assert_true(Fleet.owns(Fleet.FREE), "an older free roam save")
	Fleet.lose(Fleet.FREE)
	assert_false(Fleet.owns(Fleet.FREE), "sold or lost for good")
	d = WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(d)
	assert_false(Fleet.owns(Fleet.FREE), "and it stays gone")
	WorldState.new_game(WorldState.STORY)
	assert_false(Fleet.owns(Fleet.FREE), "a story save earns its ship")


# ---- Skrugs --------------------------------------------------------------------

func test_skrugs_cleans_up_a_stolen_ship_for_you_to_keep() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	var v := Node3D.new()
	t.add_child(v)
	v.global_position = post.world_point("ship_sell")
	var i: int = t.pilot.add_outpost_berth(v, "remnant_fighter", "test_outpost")
	t.pilot.berths[i].stolen = true
	var price := post.keep_price("remnant_fighter")
	assert_eq(price, int(round(ShipSalesman.list_price("remnant_fighter") * 0.5)), "keep_rate times the list price")
	WorldState.credits = price - 1
	assert_eq(post.keep_ship(), -1, "not without the credits")
	assert_true(bool(t.pilot.berths[i].stolen))
	WorldState.credits = price + 5
	assert_eq(post.keep_ship(), price)
	assert_eq(WorldState.credits, 5)
	var b: Dictionary = t.pilot.berths[i]
	assert_false(bool(b.get("stolen", false)), "nobody hunts it")
	assert_false(b.has("outpost"), "no outpost's any more: boarding it sets off nothing")
	assert_true(Fleet.owns(t.pilot.berth_key(i)), "yours")
	assert_eq(Fleet.primary(), t.pilot.berth_key(i), "your first ship: the primary")
	assert_eq(str(post.ship_offer().get("kind", "")), "owned", "he would buy it back now, honestly")
