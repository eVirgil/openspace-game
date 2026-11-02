extends GutTest
## Issue #193: the Remnant star cruiser in orbit, without a scene. Its shapes
## (CruiserHull), where it hangs and how it is turned, the docking path, its
## gravity, and Oda's last chapter: the general's death pays once and ends the
## story. The whole flight, landing, walk and fight are scenes/cruiser_trace.gd.


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func _sphere() -> PlanetSphere:
	return PlanetSphere.new(5000.0)


func _landmark() -> Dictionary:
	var world: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	return CruiserHull.landmark(world)


func test_the_home_world_has_one_cruiser_in_orbit_past_the_curve() -> void:
	var lm := _landmark()
	assert_false(lm.is_empty(), "the home world lists the cruiser")
	var sp := _sphere()
	var xf := CruiserHull.frame_for(sp, lm)
	assert_almost_eq(sp.altitude(xf.origin), float(lm.altitude), 1.0, "it holds its altitude")
	assert_gt(sp.altitude(xf.origin), 4000.0, "above the edge of space")
	# The line from the port to it passes through the ball: not seen from town.
	var d := xf.origin.normalized()
	assert_lt((sp.center - d * sp.center.dot(d)).length(), sp.radius, "hidden from the port by the curve")
	assert_gt(xf.origin.x, 5000.0, "far to the east")


func test_it_is_level_with_the_port_and_its_bay_faces_it() -> void:
	var xf := CruiserHull.frame_for(_sphere(), _landmark())
	assert_almost_eq(xf.basis.y.dot(Vector3.UP), 1.0, 0.0001, "decks square to world up")
	var to_port := Vector3(-xf.origin.x, 0.0, -xf.origin.z).normalized()
	assert_gt(xf.basis.x.dot(to_port), 0.99, "the bay (starboard) faces the port across the sky")


func test_its_gravity_is_its_own_aboard_and_the_balls_outside() -> void:
	var sp := _sphere()
	var xf := CruiserHull.frame_for(sp, _landmark())
	sp.add_gravity_zone(xf, CruiserHull.GRAVITY_BOX)
	sp.add_gravity_zone(xf, CruiserHull.GRAVITY_BOX)
	assert_eq(sp.gravity_zones.size(), 1, "the same zone twice is one zone")
	assert_almost_eq(sp.up_at(xf * Vector3(0, CruiserHull.DECK_Y + 1.0, 100)).dot(Vector3.UP), 1.0, 0.0001)
	var outside := xf.origin + Vector3(0, 0, 2000)
	assert_lt(sp.up_at(outside).dot(Vector3.UP), 0.5, "away from it, up is the ball's again")


func test_the_parts_are_solid_and_floored() -> void:
	var parts := CruiserHull.parts()
	assert_gt(parts.size(), 300, "a whole hull of plates")
	var ids := {}
	for p in parts:
		assert_false(ids.has(p.id), "unique part id " + str(p.id))
		ids[p.id] = true
		assert_true(str(p.kind) in ["floor", "solid", "decor"], str(p.id))
	for id in ["bay_deck", "hall_deck", "shaft_floor", "bridge_walk", "bridge_dais", "flight_0", "flight_5"]:
		assert_true(ids.has(id), "has " + id)


## The computers you can walk up to stop you: every terminal, bank and rack is a
## solid casing in the crew's navmesh; only the screens on them are drawn only.
func test_the_computers_are_solid() -> void:
	var casings := 0
	for p in CruiserHull.parts():
		var id := str(p.id)
		if id.ends_with("_screen") or id.ends_with("_stand") or id.begins_with("monitor_") or id.begins_with("screen_"):
			continue
		if "terminal" in id or id.begins_with("bank_") or "_rack_" in id:
			assert_eq(str(p.kind), "solid", id)
			assert_true(bool(p.nav), id + " is in the navmesh")
			casings += 1
	assert_gt(casings, 30, "terminals down the corridor, on the landings, in the rooms, banks on the bridge")


func test_six_flights_climb_from_the_deck_to_the_bridge() -> void:
	assert_eq(CruiserHull.DECK_Y + CruiserHull.FLIGHTS * CruiserHull.FLIGHT_RISE, CruiserHull.BRIDGE_Y)
	var run := CruiserHull.FLIGHT_Z.y - CruiserHull.FLIGHT_Z.x
	assert_lt(rad_to_deg(atan2(CruiserHull.FLIGHT_RISE, run)), 30.0, "each flight is walkable")


func test_the_stairs_foot_is_aboard_on_the_deck_in_the_shaft() -> void:
	var foot := CruiserHull.stairs_foot()
	assert_true(CruiserHull.aboard(foot), "walkable")
	assert_true(CruiserHull.at_stairs(foot))
	assert_eq(foot.y, CruiserHull.DECK_Y, "on the deck")
	assert_false(CruiserHull.at_stairs(CruiserHull.dock_pad().at), "the bay is not the stairs")
	assert_false(CruiserHull.at_stairs(Vector3(0, CruiserHull.BRIDGE_Y, 240)), "nor the bridge")


func test_the_bay_has_two_interceptors_a_frigate_and_an_empty_pad() -> void:
	var pads := CruiserHull.pads()
	assert_eq(pads.filter(func(p): return p.ship == "remnant_interceptor").size(), 2)
	assert_eq(pads.filter(func(p): return p.ship == "remnant_freighter").size(), 1, "the frigate")
	var dock := CruiserHull.dock_pad()
	assert_false(dock.is_empty(), "Z has a pad to land on")
	assert_eq(str(dock.ship), "", "and it is empty")
	for p in pads:
		var at: Vector3 = p.at
		assert_true(CruiserHull.aboard(at + Vector3(0, 1, 0)), "pad %s is in the bay" % p.id)


func test_docking_from_the_far_side_goes_over_the_hull_and_ends_over_the_pad() -> void:
	var path := CruiserHull.dock_path(Vector3(-400, 120, -60))
	assert_gt(path.size(), 3)
	for p in path.slice(0, path.size() - 2):
		var w: Vector3 = p
		assert_false(absf(w.x) < 70.0 and absf(w.z) < 360.0 and w.y < 100.0, "clear of the hull: %s" % w)
	var last: Vector3 = path[path.size() - 1]
	var pad: Vector3 = CruiserHull.dock_pad().at
	assert_almost_eq(Vector2(last.x, last.z).distance_to(Vector2(pad.x, pad.z)), 0.0, 0.01, "over the pad")
	assert_between(last.y - pad.y, 5.0, 40.0, "low enough to set down, under the bay's ceiling")


func test_the_docking_curve_leaves_along_her_heading_and_comes_in_straight_through_the_shield() -> void:
	var from := Vector3(-400, 120, -60)
	var pts := CruiserHull.dock_path(from)
	var curve := ShipPilot.dock_curve(from, Vector3.FORWARD, pts)
	var length := curve.get_baked_length()
	assert_almost_eq(curve.sample_baked(0.0).distance_to(from), 0.0, 0.01, "starts where she is")
	var lead := curve.sample_baked(1.0) - from
	assert_gt(lead.normalized().dot(Vector3.FORWARD), 0.95, "and carries on the way she was going")
	var last: Vector3 = pts[pts.size() - 1]
	assert_almost_eq(curve.sample_baked(length).distance_to(last), 0.0, 0.01, "ends over the pad")
	var pz: float = CruiserHull.dock_pad().at.z
	var through := curve.get_closest_offset(Vector3(CruiserHull.BAY_X.y + 0.5, last.y, pz))
	var s := through - 120.0
	while s < length:
		var w := curve.sample_baked(s, true)
		assert_almost_eq(w.z, pz, 0.5, "in line with the pad from off the mouth: %s" % w)
		assert_almost_eq(w.y, last.y, 0.5, "at the shield's height: %s" % w)
		s += 10.0


func test_the_general_ends_the_fleet_chapter_and_the_dogfight_does_not() -> void:
	var ids := Story.chapter_ids()
	assert_eq(ids.find("cruiser"), -1, "one chapter: the fleet is the general on the cruiser")
	Story.skip_to("fleet")
	assert_true(Story.cruiser_mission(), "the climb out meets the cruiser's escort")
	WorldState.on_flight_returned({ "outcome": "complete", "payout": 0 })
	assert_eq(Story.chapter(), "fleet", "the dogfight is only in the way")
	assert_false(Story.remnant_hostile(), "the garrison stays")
	WorldState.on_cruiser_taken("General Test", {})
	assert_eq(Story.chapter(), "debrief", "issue #303: back to Oda before the end card")
	assert_true(Story.remnant_hostile(), "the garrison leaves town")
	assert_false(Story.cruiser_mission())


func test_the_generals_death_pays_once() -> void:
	Story.skip_to("free")
	WorldState.set_flag("cruiser_taken", false)
	var reward: Dictionary = CruiserHull.data().get("reward", {})
	var credits := WorldState.credits
	var locals := int(WorldState.standing.get("locals", 0))
	var paid := WorldState.on_cruiser_taken("General Test", reward, "%s fell.")
	assert_eq(paid, int(reward.credits))
	assert_eq(WorldState.credits, credits + int(reward.credits))
	assert_gt(int(WorldState.standing.get("locals", 0)), locals + 40, "the locals love you for it")
	assert_true(Story.cruiser_taken())
	assert_false(Story.cruiser_mission())
	assert_eq(WorldState.on_cruiser_taken("General Test", reward), 0, "never paid twice")


func test_taken_before_oda_asked_skips_her_chapter() -> void:
	Story.skip_to("bounty")
	WorldState.set_flag("cruiser_taken")
	Story.event("bounty_paid")
	assert_eq(Story.chapter(), "debrief")
	assert_true(Story.remnant_hostile())


func test_an_old_save_with_the_general_dead_catches_up() -> void:
	Story.skip_to("fleet")
	WorldState.set_flag("cruiser_taken")
	WorldState.from_save(WorldState.to_save())
	assert_eq(Story.chapter(), "debrief", "the save's fleet chapter ends on load")
	assert_true(Story.remnant_hostile(), "and the garrison leaves town")