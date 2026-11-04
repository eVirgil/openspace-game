extends GutTest
## Issue #64: the main story line. T-89 sends you to Oda, Oda sends you to the
## range, two smuggling runs (her jetpack with the first if she is amused or
## warm), Skrugs and a bounty at one of the three Remnant outposts, the fleet in
## orbit (the ships unlock; winning pays 5000), then smuggling runs and bounty
## contracts on repeat. Also: the three outposts, the town's Remnant coming back
## behind the barracks, the garrison leaving town after the fleet, and "Reset
## story" in the settings.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownDemo := preload("res://scenes/town_demo.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")

var content


func before_each() -> void:
	WorldState.reset()
	ShipSalesman.greeted = false
	content = CoreContent.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _offers(id: String) -> bool:
	return WorldState.open_jobs("confidant").any(func(j): return str(j.id) == id)


## Pick up Oda's drop and sell it all to the fence, as GearController does.
func _smuggle_run() -> void:
	assert_true(WorldState.accept_job("j_smuggle_run"), "the run can be taken")
	var drop := WorldState.smuggle_drop()
	assert_true(WorldState.inventory.pick_up(drop))
	var fence: Dictionary = content.get_vendor("fence")
	var item: Dictionary = content.get_item(str(drop.item))
	for i in int(drop.count):
		WorldState.credits += WorldState.inventory.sell(str(drop.item), item, fence)
		WorldState.on_contraband_sold()


func _bounty_run() -> int:
	assert_true(_offers("j_bounty"), "a contract is on offer")
	var j := WorldState.job("j_bounty")
	assert_true(str(j.text).contains(str(WorldState.bounty.name)), "she names the officer")
	assert_true(str(j.text).contains(Story.outpost_label(str(WorldState.bounty.outpost))), "and the outpost")
	assert_true(WorldState.accept_job("j_bounty"))
	assert_false(WorldState.bounty_target().is_empty(), "the officer is out there")
	assert_false(_offers("j_bounty"), "one contract at a time")
	WorldState.on_bounty_killed()
	assert_true(WorldState.bounty_collectable(), "the fence owes you")
	assert_false(_offers("j_bounty"), "not until it is collected")
	var c0 := WorldState.credits
	var pay := WorldState.collect_bounty()
	assert_eq(WorldState.credits, c0 + pay, "the fence pays")
	return pay


# ---- the story, start to finish ------------------------------------------------

func test_the_whole_story_in_order() -> void:
	assert_eq(Story.chapter(), "meet_oda", "a new game starts with T-89")
	assert_false(Story.ships_unlocked(), "the ships are locked")
	assert_false(_offers("j_smuggle_run"), "no smuggling yet")
	assert_false(_offers("j_bounty"))

	var t89 := Story.beat("t89")
	assert_true(str(t89.say).contains("Oda"), "T-89 sends you to Oda")
	assert_eq(Story.beat("t89").say, Story.chapter_cfg().remind, "and reminds you after")

	var oda := Story.beat("cantina_owner")
	assert_eq(Story.chapter(), "range", "talking to her is meeting her")
	assert_true(str(oda.say).to_lower().contains("range"), "she sends you to the range")
	assert_eq(str(oda.job), "")
	WorldState.on_range_cleared()
	assert_eq(Story.chapter(), "range", "clearing the targets is not required: it is only practice")
	WorldState.on_range_visited()
	assert_eq(Story.chapter(), "remote", "going down to the range is")

	var c_practice := WorldState.credits
	oda = Story.beat("cantina_owner")
	assert_eq(WorldState.credits, c_practice + 40, "she pays for the practice")
	assert_true(str(oda.say).contains("five"), "and tells you about the sparring droid: block five")
	Story.beat("cantina_owner")
	assert_eq(WorldState.credits, c_practice + 40, "once")
	WorldState.on_range_visited()
	assert_eq(Story.chapter(), "smuggle_1", "back from the pit: on your honour")

	# Contraband sold before she gave you the run does not count as the run.
	WorldState.on_contraband_sold()
	assert_eq(Story.chapter(), "smuggle_1")

	oda = Story.beat("cantina_owner")
	assert_eq(str(oda.job), "j_smuggle_run", "the first run comes with its job card")
	_smuggle_run()
	assert_eq(Story.chapter(), "droid_merchant", "selling the drop ends the first run")
	# Issue #212: three cargo droids for Oda's friend instead of a second run.
	for i in 3:
		Story.on_droid_delivered()
	assert_eq(Story.chapter(), "heist", "issue #413: the heist before the bounty")
	oda = Story.beat("cantina_owner")
	assert_eq(str(oda.job), "j_heist", "the heist comes with its job card")
	Story.event("heist_paid")                  # the fence paid for the flasks (test_heists plays it through)
	assert_eq(Story.chapter(), "bounty")

	oda = Story.beat("cantina_owner")
	assert_true(str(oda.say).contains("Skrugs"), "she tells you about the speeder merchant")
	assert_eq(str(oda.job), "j_bounty", "and the bounty")
	assert_eq(str(WorldState.bounty.outpost), Story.OUTPOSTS[0], "the first bounty is at the nearest outpost")
	assert_eq(_bounty_run(), int(Story.bounty_cfg().first_pay))
	assert_eq(Story.chapter(), "fleet", "collecting it moves the story on")
	assert_false(Story.ships_unlocked(), "not until she tells you")

	oda = Story.beat("cantina_owner")
	assert_true(str(oda.say).contains("own ship"), "issue #214: take your own ship up")
	assert_true(Story.ships_unlocked())
	assert_true(_offers("j_patrol_bounty"), "the patrol job opens with the ships")

	assert_true(Story.cruiser_mission(), "the fleet chapter is the general on the cruiser")
	var c0 := WorldState.credits
	WorldState.on_flight_returned({ "outcome": "complete", "payout": 150 })
	assert_eq(WorldState.credits, c0 + 150, "the fighters on the way up pay their own payout")
	assert_eq(Story.chapter(), "fleet", "beating them is not the mission")
	assert_false(Story.remnant_hostile())
	var reward: Dictionary = CruiserHull.data().get("reward", {})
	c0 = WorldState.credits
	WorldState.on_cruiser_taken("General Test", reward, "%s fell.")
	assert_eq(WorldState.credits, c0 + int(reward.credits), "the general pays")
	assert_true(Story.remnant_hostile(), "the Remnant turn hostile")
	assert_false(Story.town_garrison(), "and leave town")
	assert_eq(Story.chapter(), "debrief", "issue #303: go back to Oda first")
	assert_true(WorldState.has_flag("remnant_fleet_beaten"), "the fleet is beaten at the kill")
	oda = Story.beat("cantina_owner")
	assert_true(str(oda.say).contains("dead"), "she tells the debrief")
	assert_eq(Story.chapter(), "end", "issue #214: the end card")
	EndCard.close()
	assert_eq(Story.chapter(), "free")

	# Free play: bounties and smuggling on repeat.
	oda = Story.beat("cantina_owner")
	assert_eq(str(oda.job), "j_bounty")
	var outposts := []
	for i in 6:
		Story.beat("cantina_owner")
		outposts.append(str(WorldState.bounty.outpost))
		var pay := _bounty_run()
		assert_between(pay, 900, 1600, "a lot of money")
		assert_true(_offers("j_smuggle_run"), "smuggling still runs")
	for i in range(1, outposts.size()):
		assert_ne(outposts[i], outposts[i - 1], "never the same outpost twice running")
		assert_true(Story.OUTPOSTS.has(outposts[i]))
	_smuggle_run()
	assert_eq(Story.chapter(), "free", "the last chapter never ends")


func test_a_later_flight_pays_as_before() -> void:
	var c0 := WorldState.credits
	WorldState.on_flight_returned({ "outcome": "complete", "payout": 150 })
	assert_eq(WorldState.credits, c0 + 150, "a sortie pays its own payout")
	assert_false(Story.remnant_hostile())


func test_oda_tells_you_about_the_jetpack_on_the_tower() -> void:
	Story.skip_to("smuggle_1")
	assert_true(Story.brief("cantina_owner").contains("tower"), "her briefing points at the cantina tower")
	assert_eq(Story.on_owner_mood("amused"), "", "she no longer lends hers")
	assert_false(WorldState.inventory.has("jetpack"))


func test_jetpack_not_outside_the_first_run() -> void:
	Story.skip_to("droid_merchant")
	assert_eq(Story.on_owner_mood("warm"), "")
	assert_false(WorldState.inventory.has("jetpack"))


func test_story_survives_a_save() -> void:
	Story.skip_to("bounty")
	Story.beat("cantina_owner")
	WorldState.accept_job("j_bounty")
	var b := WorldState.bounty.duplicate()
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	assert_eq(Story.chapter(), "bounty")
	assert_eq(str(WorldState.bounty_target().get("name", "")), str(b.name), "the contract is still out")
	assert_true(bool(WorldState.story.told), "and she does not repeat her intro")


func test_beats_only_for_their_teller() -> void:
	assert_true(Story.beat("skrugs").is_empty())
	Story.skip_to("range")
	assert_true(Story.beat("t89").is_empty(), "T-89 is done once you have met her")


func test_skipping_ahead_unlocks_what_playing_would() -> void:
	WorldState.new_game(WorldState.STORY)
	var c0 := WorldState.credits
	Story.skip_to("heist")
	assert_eq(WorldState.credits, c0 + int(Story.chapter_cfg("remote").pays), "Oda's practice fee")
	assert_eq(Quests.state("tower_blade"), "", "Oda has not told the heist chapter yet")
	Story.skip_to("bounty")
	c0 += int(Story.chapter_cfg("heist").skipped.credits)     # issue #413: the heist's pay
	assert_false(GearUpgrades.open_offers().any(func(o): return str(o.id) == "quantonium_armour"), "no bounty paid yet")
	assert_eq(Quests.state("tower_blade"), "open", "issue #413: Oda told of the blade in the heist chapter, skipped past")
	Story.skip_to("fleet")
	assert_eq(int(Story.chapter_cfg("bounty").skipped.credits), int(Story.bounty_cfg().first_pay), "the first bounty's pay")
	assert_eq(WorldState.credits, c0 + int(Story.chapter_cfg("remote").pays) + int(Story.bounty_cfg().first_pay))
	assert_true(GearUpgrades.open_offers().any(func(o): return str(o.id) == "quantonium_armour"), "the fence sells the armour")
	assert_eq(WorldState.count("merchant_droids"), 3)
	assert_eq(str(WorldState.jobs_taken.get("j_droid_merchant", "")), "done", "the droid merchant's card is not left open")
	assert_false(WorldState.open_jobs("confidant").any(func(j): return str(j.id) == "j_droid_merchant"))
	assert_eq(Quests.state("tower_blade"), "open", "the blade on the tower is offered")
	assert_true(Story.ships_unlocked())
	assert_false(Story.cruiser_taken(), "the fleet chapter is still to play")
	assert_eq(int(WorldState.standing.imperial_remnant), 0)


func test_skipping_past_the_fleet_is_the_cruiser_taken() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	var c0 := WorldState.credits
	Story.skip_to("free")
	assert_true(Story.cruiser_taken() and Story.remnant_gone() and WorldState.has_flag("locals_hero"))
	assert_true(bool(WorldState.story.told))
	var reward: Dictionary = CruiserHull.data().get("reward", {})
	var st: Dictionary = Story.chapter_cfg("fleet").skipped.standing
	for f in ["locals", "smuggler"]:
		assert_eq(int(st[f]), int(reward[f]), "the skip's %s standing is the cruiser's reward" % f)
	assert_eq(int(st.imperial_remnant), int(reward.remnant))
	assert_eq(int(WorldState.standing.imperial_remnant), int(reward.remnant))
	assert_eq(int(Story.chapter_cfg("fleet").skipped.credits), int(reward.credits))
	assert_eq(WorldState.credits, c0 + int(reward.credits), "the cruiser's reward")
	Story.skip_to("free")
	assert_eq(int(WorldState.standing.imperial_remnant), int(reward.remnant), "given once")
	assert_eq(WorldState.credits, c0 + int(reward.credits), "paid once")
	assert_eq(WorldState.count("bounties_paid"), 1, "at least one, not one more each skip")


func test_a_skip_does_not_pay_twice_for_what_was_played() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("remote")
	Story.beat("cantina_owner")
	var c0 := WorldState.credits
	Story.skip_to("smuggle_1")
	assert_eq(WorldState.credits, c0, "Oda paid for the practice when she told it")


# ---- data ----------------------------------------------------------------------

func test_three_outposts_further_and_further_out_the_front_gate() -> void:
	var world: Dictionary = content.world_for_town("port_town")
	var town := TownLayout.new()
	assert_true(town.load_town("port_town"))
	var gate := town.marker_pos("gate")
	var dists := []
	var looks := {}
	for id in Story.OUTPOSTS:
		var lm: Array = world.landmarks.filter(func(l): return str(l.get("location", "")) == id)
		assert_eq(lm.size(), 1, "%s is in the world" % id)
		var at := Vector3(float(lm[0].at[0]), 0, float(lm[0].at[2]))
		assert_gt(at.x, gate.x + 50.0, "%s is out the front gate" % id)
		dists.append(at.distance_to(gate))
		var loc: Dictionary = content.get_location(id)
		assert_eq((loc.buildings as Array).size(), 1, "one building")
		assert_false(str(loc.get("ship", "")) == "", "a cargo ship parked")
		assert_true(content.ships.has(str(loc.ship)))
		for p in ["guard_a", "guard_b", "guard_c", "target", "ship", "patrol"]:
			assert_true(loc.points.has(p), "%s has %s" % [id, p])
		looks[JSON.stringify([loc.buildings, loc.ship, loc.look])] = true
	assert_lt(dists[0], dists[1])
	assert_lt(dists[1], dists[2], "each further out")
	assert_gt(dists[0], 100.0, "further out than Skrugs's post")
	assert_eq(looks.size(), 3, "each a little different")


## Issue #76: crates, canisters and drums lie about each outpost, solid (cover),
## and its droids have their routes.
func test_outposts_have_props_and_droid_routes() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var o: RemnantOutposts = t.outposts
	for spec in o.droid_specs():
		for r in ["patrol", "floater", "cargo"]:
			assert_false((spec.routes.get(r, []) as Array).is_empty(), "%s has a %s route" % [spec.outpost, r])
	for op in o.outposts:
		var list: Array = o.props(op)
		assert_gte(list.size(), 8, "%s has props lying about" % op.id)
		var body: StaticBody3D = o.get_node_or_null("Props_" + str(op.id))
		assert_not_null(body, "and they are solid")
		assert_eq(body.get_child_count(), list.size(), "one shape each")
		var stacked: Array = list.filter(func(p): return int(p.level) == 1)
		assert_gt(stacked.size(), 0, "a crate on a crate")
		for p in stacked:
			assert_gt(float(p.base), 0.8, "sitting on the one below")


func test_target_and_trooper_profiles() -> void:
	var t: Dictionary = content.get_soldier("bounty_target")
	assert_eq(str(t.faction), "imperial_remnant")
	assert_eq(str(t.archetype), "remnant_marked", "the target is red")
	assert_gt(int(t.hp), int(content.get_soldier("outpost_trooper").hp))
	assert_ne(NameHooks.person(Story.target_naming(), "npc:bounty/test"), "", "targets get names")


## Issue #76: the officer carries a dark pistol; the outposts' troopers are tougher
## than the town's and every Remnant soldier is worth a kill reward.
func test_officer_pistol_and_tougher_outposts() -> void:
	var t: Dictionary = content.get_soldier("bounty_target")
	assert_eq(str(t.weapon.base), "pistol_blaster", "the officer shoots a pistol")
	var body: Node3D = CharacterKit.new(LookMaterials.new()).build("remnant_marked")
	add_child_autofree(body)
	assert_true(body.has_meta("weapon"), "and holds one")
	var w: Node3D = body.get_meta("weapon")
	assert_eq(str(w.get_meta("carry", "")), "pistol", "rested like a pistol")
	var dark := w.find_children("*", "MeshInstance3D", true, false).filter(
		func(m): return m.material_override is ShaderMaterial)
	assert_gt(dark.size(), 0, "the dark variant")
	var trooper: Dictionary = content.get_soldier("outpost_trooper")
	var town: Dictionary = content.get_soldier("gate_guard")
	assert_gt(int(trooper.hp), int(town.hp))
	assert_lt(float(trooper.combat.aim_error_deg), float(town.combat.aim_error_deg), "better shots")
	assert_lt(float(trooper.perception.reaction_s), float(town.perception.reaction_s), "quicker")
	for id in ["gate_guard", "tower_sentry", "yard_trooper", "outpost_trooper", "bounty_target"]:
		assert_eq(int(content.get_soldier(id).get("kill_reward", 0)), 20, "%s is worth 20 cr" % id)
	assert_eq(int(content.get_soldier("local_resident").get("kill_reward", 0)), 0, "locals are not")


# ---- the town ------------------------------------------------------------------

func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.nav_async = false
	add_child_autofree(t)
	return t


func test_outposts_in_the_town_with_guards_droids_and_target() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var o: RemnantOutposts = t.outposts
	assert_not_null(o, "the town builds the outposts")
	assert_eq(o.outposts.size(), 3)
	assert_eq(o.guards.size(), 9, "three troopers each (issue #76)")
	for g in o.guards:
		var og: Garrison = o.garrisons.get(str(g.get_meta("outpost")))
		assert_not_null(og, "each outpost has its own garrison")
		assert_true(og.members.has(g), "they answer to their outpost's garrison")
		assert_false(t.garrison.members.has(g), "not the town's: a fight out there is not the town's alarm")
	assert_eq(o.garrisons.size(), 3)
	assert_true(t.garrison.handles_player, "the town's handles the player being knocked out")
	for og in o.garrisons.values():
		assert_false(og.handles_player)
	var outpost_droids: Array = t.droids.remnant.filter(func(u): return u.spec.has("outpost")) if t.droids != null else []
	if t.droids != null:
		assert_eq(outpost_droids.size(), 9, "an assassin, a floating and a cargo droid each (issue #76)")
	assert_null(o.target, "no target without a contract")
	Story.skip_to("bounty")
	Story.beat("cantina_owner")
	WorldState.accept_job("j_bounty")
	await wait_physics_frames(2)
	assert_not_null(o.target, "the contract puts the officer at the outpost")
	var at: Dictionary = o.outpost(str(WorldState.bounty.outpost))
	assert_lt(o.target.global_position.distance_to(at.origin), 30.0, "at the outpost it names")
	var tg: Garrison = o.garrisons[str(WorldState.bounty.outpost)]
	assert_true(tg.members.has(o.target), "the target joins its outpost's garrison")
	o.target.process_mode = Node.PROCESS_MODE_INHERIT
	o.target.apply_damage(9999.0)
	await wait_physics_frames(2)
	assert_true(WorldState.bounty_collectable(), "killing them makes the bounty collectable")
	assert_eq(o.bounty_kills, 1)
	assert_true(tg.respawns.filter(func(r): return r.has("outpost") and str(r.post).ends_with("target")).is_empty(),
		"the target never comes back")


func test_killing_a_trooper_pays_twenty_credits() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var mine = t.npc("trooper_yard_a")
	var other = t.npc("trooper_yard_b")
	assert_not_null(mine)
	assert_not_null(other)
	var c0 := WorldState.credits
	mine.last_hit_by = t._player
	mine.apply_damage(9999.0)
	await wait_physics_frames(2)
	assert_eq(WorldState.credits, c0 + 20, "the player's kill pays 20 cr")
	assert_eq(t.garrison.rewards_paid, 20)
	other.apply_damage(9999.0)          # nobody we know shot it
	await wait_physics_frames(2)
	assert_eq(WorldState.credits, c0 + 20, "a kill that was not the player's pays nothing")


func test_town_troopers_come_back_behind_the_barracks() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var g = t.npc("trooper_yard_a")
	assert_not_null(g)
	var n0: int = t.garrison.members.size()
	g.apply_damage(9999.0)
	await wait_physics_frames(2)
	assert_eq(t.garrison.respawns.size(), 1, "queued")
	var r: Dictionary = t.garrison.respawns[0]
	assert_almost_eq(float(r.t) - t.garrison._clock, 60.0, 1.0, "a minute later")
	assert_eq(r.at, t.town.marker_pos("remnant_respawn"), "behind the barracks")
	t.garrison.alarm.state = TownAlarm.State.CALM      # the fight is over
	t.garrison._clock = float(r.t) + 0.1
	await wait_physics_frames(2)
	assert_eq(t.garrison.respawned, 1)
	assert_eq(t.garrison.members.size(), n0 + 1, "a new trooper joined")
	var back: NpcBody = t.garrison.members[t.garrison.members.size() - 1]
	assert_eq(back.post_pos, g.post_pos, "and walks back to the dead one's post")
	assert_lt(back.global_position.distance_to(t.town.marker_pos("remnant_respawn")), 3.0)


func test_roof_riflemen_come_back_on_the_roof() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var g = t.npc("trooper_roof_c")
	assert_not_null(g, "the barracks roof is manned from the start")
	assert_eq(t.garrison.members.filter(func(n): return n.soldier_id == "roof_rifleman").size(), 3)
	g.apply_damage(9999.0)
	await wait_physics_frames(2)
	var r: Dictionary = t.garrison.respawns[0]
	assert_almost_eq(float(r.t) - t.garrison._clock, 60.0, 1.0, "a minute later, like the others")
	assert_eq(r.at, g.post_pos, "at its post: no way up from behind the barracks")
	t.garrison.alarm.state = TownAlarm.State.CALM
	t.garrison._clock = float(r.t) + 0.1
	await wait_physics_frames(2)
	assert_eq(t.garrison.respawned, 1)
	var back: NpcBody = t.garrison.members[t.garrison.members.size() - 1]
	assert_eq(back.soldier_id, "roof_rifleman")
	assert_lt(back.global_position.distance_to(g.post_pos), 1.5, "back on the roof")


func test_after_the_fleet_the_town_is_free_and_outposts_shoot_on_sight() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var town_troopers: int = t.npcs.filter(func(n): return not n.has_meta("outpost")).size()
	assert_gt(town_troopers, 0)
	Story.skip_to("fleet")
	WorldState.on_cruiser_taken("General Test", {})
	await wait_physics_frames(3)
	assert_eq(t.npcs.filter(func(n): return is_instance_valid(n) and not n.has_meta("outpost")).size(), 0, "the garrison left town")
	assert_null(t.garrison.members.filter(func(n): return is_instance_valid(n) and not n.dead).front() if not t.garrison.members.is_empty() else null, "the town's garrison is empty")
	assert_eq(t.outposts.garrisons.size(), 3, "the outposts keep theirs")
	assert_false(WorldState.has_flag("gate_checkpoint_up"))
	if t.droids != null:
		assert_true(t.droids.remnant.all(func(u): return u.spec.has("outpost")), "the town's droids went too")
	assert_true(t.respawn_rule(t.outposts.guards[0]).has("delay"), "outpost troopers still come back")
	# A dead outpost trooper: a few minutes, not a minute.
	var r: Dictionary = t.respawn_rule(t.outposts.guards[0])
	assert_eq(float(r.delay), float(Story.remnant_cfg().outpost_respawn_s))
	assert_gte(float(r.delay), 120.0)


func test_a_new_town_after_the_fleet_has_no_garrison() -> void:
	Story.skip_to("free")
	var t = _town()
	await wait_physics_frames(2)
	assert_eq(t.npcs.filter(func(n): return not n.has_meta("outpost")).size(), 0)
	assert_null(t.garrison, "no town garrison at all")
	assert_eq(t.outposts.garrisons.size(), 3)
	assert_true(t.outposts.garrisons.values()[0].handles_player, "an outpost's handles the player being knocked out")


func test_ships_locked_until_oda_says() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var p = t._player
	var home: Vector3 = t.pilot.home
	p.global_position = Vector3(home.x + 4.0, p.global_position.y, home.z)
	await wait_physics_frames(2)
	if t.pilot.nearest_berth() < 0:
		pass_test("no berth in reach in the greybox (layout)")
		return
	assert_false(t.pilot.board(), "locked")
	WorldState.set_flag("ships_unlocked")
	assert_true(t.pilot.board(), "the keys are in it")


func test_new_story_game_starts_over() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("free")
	WorldState.credits = 9000
	WorldState.inventory.add("jetpack")
	WorldState.hangar = "courier"
	WorldState.standing["locals"] = 80
	var names := WorldState.names
	var panel := DevSettingsPanel.new()
	add_child_autofree(panel)
	panel.new_game(WorldState.STORY, false)
	assert_eq(Story.chapter(), "land", "issue #202: a story opens with the landing")
	assert_eq(WorldState.credits, 60)
	assert_false(WorldState.inventory.has("jetpack"), "equipment gone")
	assert_eq(WorldState.hangar, "")
	assert_eq(WorldState.droids.owned.size(), 0, "droids gone")
	assert_eq(int(WorldState.standing.locals), 0, "a story starts neutral")
	assert_false(Story.ships_unlocked())
	assert_false(Story.remnant_hostile())
	assert_eq(WorldState.names, names, "the story save's names are kept")
	assert_false(ShipSalesman.greeted, "T-89 says hello again")


func test_an_outpost_fight_is_not_the_towns_alarm() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var og: Garrison = t.outposts.garrisons.values()[0]
	og._raise("attacked")
	await wait_physics_frames(2)
	assert_true(og.alarm.active(), "the outpost is fighting")
	assert_false(t.garrison.alarm.active(), "the town is not")


func test_respawns_wait_for_the_alarm_and_do_not_remember_you() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var g = t.npc("trooper_yard_a")
	g.apply_damage(9999.0)
	await wait_physics_frames(2)
	t.garrison._raise("attacked")
	t.garrison._clock = float(t.garrison.respawns[0].t) + 0.1
	await wait_physics_frames(2)
	assert_eq(t.garrison.respawned, 0, "nobody comes back in the middle of a fight")
	t.garrison.alarm.state = TownAlarm.State.CALM
	await wait_physics_frames(2)
	assert_eq(t.garrison.respawned, 1)
	assert_true(t.garrison.alarm.remembers(), "the garrison still remembers the fight")
	var back: NpcBody = t.garrison.members[t.garrison.members.size() - 1]
	assert_true(back.has_meta("fresh"), "but the new trooper never saw your face")


## Dying ends it: you wake in the pit to a calm town, not a spawn camp. Every
## garrison's alarm (and the klaxon) stops, they forget your face, a droid you
## shot lets it go, and Remnant standing comes up to the lowest they tolerate,
## whoever landed the last shot.
func test_dying_calms_the_remnant() -> void:
	var t = _town()
	await wait_physics_frames(2)
	WorldState.standing["imperial_remnant"] = -80
	var og: Garrison = t.outposts.garrisons.values()[0]
	t.garrison._raise("attacked")
	og._raise("attacked")
	var bots: Array = t.droids.remnant if t.droids != null else []
	for u in bots:
		u.provoked = true
	await wait_physics_frames(2)
	assert_true(t.garrison.alarm.active(), "the town is fighting")
	t._player.invulnerable_left = 0.0
	t._player.apply_damage(99999.0)
	await wait_physics_frames(2)
	t.garrison._ko_left = 0.001          # skip the blackout
	await wait_physics_frames(3)
	assert_false(t._player.is_downed, "back on your feet in the pit")
	for g in [t.garrison, og]:
		assert_false(g.alarm.active(), "%s stood down" % g.name)
		assert_false(g.alarm.remembers(), "%s forgot your face" % g.name)
		assert_eq(g.checkpoint.memory_left, 0.0)
	assert_eq(t.garrison.klaxon_left, 0.0, "the klaxon is off")
	for u in bots:
		assert_false(u.provoked, "the droids let it go")
	assert_eq(int(WorldState.standing.imperial_remnant), t.garrison.checkpoint.lowest_tolerated())
	await wait_physics_frames(60)
	assert_false(t.garrison.alarm.active(), "and nobody starts it again at the pit")
