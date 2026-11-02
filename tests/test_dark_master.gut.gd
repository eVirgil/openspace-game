extends GutTest
## Issue #303: the divergent endings, without a scene. The general's death is paid
## and saved and sends you back to Oda; the dark master's offer (join / refuse);
## the oath (clear the barracks' local guards, or break it by telling Oda first);
## the town changing hands; free roam; the friends-of-the-Remnant perks; and his
## sword fight (BladeFighter).

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var _saves: Array = []


func before_each() -> void:
	WorldState.reset()
	WorldState.checkpoint_hooks.clear()
	_saves.clear()
	WorldState.checkpoint_hooks.append(func(why): _saves.append(why))


func after_each() -> void:
	WorldState.checkpoint_hooks.clear()
	WorldState.reset()


func _story_at_kill() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}))


func _kill_barracks_guards() -> void:
	for post in Territory.barracks_posts():
		Territory.barracks_guard_died(str(post))


func _remnant() -> int:
	return int(WorldState.standing.get("imperial_remnant", 0))


# ------------------------------------------------------------------ the kill

func test_the_generals_death_pays_saves_and_sends_you_back_to_oda() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("fleet")
	var c0 := WorldState.credits
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}))
	assert_eq(WorldState.credits, c0 + int(CruiserHull.data().reward.credits), "paid at the kill")
	assert_true(_saves.has("cruiser_taken"), "and saved on the spot")
	assert_eq(Story.chapter(), "debrief")
	assert_true(Story.remnant_gone(), "the fleet is beaten at the kill")
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS, "the locals hold the barracks")
	assert_eq(str(Objective.current().target), "npc:cantina_owner", "the arrow points at Oda")
	var oda := Story.beat("cantina_owner")
	assert_string_contains(str(oda.say), "dead")
	assert_eq(Story.chapter(), "end", "her telling brings the end card")
	assert_false(EndCard.dark())
	assert_eq(EndCard.title(), "THE REMNANT LEAVE THE MOON")


func test_a_checkpoint_runs_every_hook_and_drops_dead_ones() -> void:
	assert_eq(WorldState.checkpoint("test"), 1)
	assert_eq(_saves, ["test"])


# ------------------------------------------------------------------ the offer

func test_he_waits_on_the_cruiser_to_make_his_offer() -> void:
	WorldState.new_game(WorldState.STORY)
	assert_false(DarkPact.on_cruiser(), "not before the general dies")
	_story_at_kill()
	assert_true(DarkPact.offer_due())
	assert_true(DarkPact.on_cruiser())
	assert_false(DarkPact.hostile_at("cruiser"), "he talks first")


func test_he_waits_just_out_of_the_corridor_door() -> void:
	var cr: Dictionary = DarkPact.cfg().get("cruiser", {})
	var at := DarkMasterPost._v(cr.get("at"))
	var door := Vector3(0, CruiserHull.DECK_Y, CruiserHull.BAY_Z.y)
	assert_eq(at.y, CruiserHull.DECK_Y, "on the bay deck")
	assert_lt(at.z, CruiserHull.BAY_Z.y, "in the bay, not the corridor")
	assert_lt(absf(at.x), CruiserHull.HALL_HALF, "in line with the door")
	assert_lt(at.distance_to(door), float(DarkPact.cfg().get("meet_reach", 9.0)), "walking out of the door opens his offer")
	assert_gt(DarkMasterPost._v(cr.get("face")).z, 0.0, "facing the door")


func test_join_makes_the_remnant_friends_and_opens_the_oath() -> void:
	_story_at_kill()
	assert_true(Story.remnant_hostile(), "before: the Remnant shoot on sight")
	assert_true(DarkPact.join())
	assert_false(DarkPact.join(), "once")
	assert_true(DarkPact.joined())
	assert_gte(_remnant(), 25, "Remnant standing is friendly")
	assert_eq(WorldState.standing_label(_remnant()), "friendly")
	assert_false(Story.remnant_hostile(), "the Remnant are on your side")
	assert_eq(Quests.state(DarkPact.QUEST), "open")
	assert_true(_saves.has("dark_pact"))
	assert_false(DarkPact.on_cruiser(), "he leaves the cruiser")
	var o := Objective.current()
	assert_eq(str(o.target), "marker:trooper_yard_a", "the oath comes before Oda")
	assert_string_contains(str(o.text), "local guards")


func test_clearing_the_barracks_on_the_oath_is_the_dark_ending() -> void:
	_story_at_kill()
	DarkPact.join()
	var posts := Territory.barracks_posts()
	assert_eq(posts.size(), 5, "four guards and a sentry")
	for i in posts.size() - 1:
		Territory.barracks_guard_died(str(posts[i]))
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS, "not until the last one")
	Territory.barracks_guard_died(str(posts[0]))
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS, "the same guard twice counts once")
	Territory.barracks_guard_died(str(posts[posts.size() - 1]))
	assert_true(DarkPact.town_retaken())
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.REMNANT, "the Remnant hold the town again")
	assert_true(Story.town_garrison())
	assert_eq(Quests.state(DarkPact.QUEST), "done")
	assert_eq(Story.chapter(), "end", "the debrief ends without Oda")
	assert_true(EndCard.dark())
	assert_eq(EndCard.title(), "THE REMNANT HOLD THE MOON")
	assert_true(Territory.remnant_planet(), "and every outpost is theirs")
	assert_true(DarkPact.on_roof(), "he stands on the barracks roof")
	assert_false(DarkPact.hostile_at("barracks"), "your friend, until you strike him")
	assert_eq(_remnant(), 100, "the Remnant who come back think the world of you")
	EndCard.close()
	assert_string_contains(str(Story.beat("cantina_owner").say), "barracks again", "Oda carries on, knowing")


func test_telling_oda_first_breaks_the_oath() -> void:
	_story_at_kill()
	DarkPact.join()
	Story.beat("cantina_owner")
	assert_eq(Quests.state(DarkPact.QUEST), "failed")
	assert_false(DarkPact.joined())
	assert_true(WorldState.has_flag("dark_oath_broken"))
	assert_lte(_remnant(), -40, "the Remnant turn on you")
	assert_true(Story.remnant_hostile())
	assert_eq(Story.chapter(), "end")
	assert_false(EndCard.dark(), "the light card")
	assert_true(DarkPact.on_cruiser(), "he waits aboard")
	assert_true(DarkPact.hostile_at("cruiser"), "as an enemy")
	_kill_barracks_guards()
	assert_false(EndCard.dark(), "too late for the dark ending")
	var entry: Dictionary = Quests.entries().filter(func(q): return q.id == DarkPact.QUEST).front()
	assert_true(entry.failed)


func test_refuse_and_he_fights_until_he_dies() -> void:
	_story_at_kill()
	assert_true(DarkPact.refuse())
	assert_false(DarkPact.joined())
	assert_true(DarkPact.on_cruiser())
	assert_true(DarkPact.hostile_at("cruiser"))
	assert_true(Story.remnant_hostile())
	DarkPact.on_killed("cruiser")
	assert_true(DarkPact.dead_at("cruiser"))
	assert_false(DarkPact.on_cruiser(), "dead stays dead")
	Story.beat("cantina_owner")
	assert_eq(Story.chapter(), "end")


func test_home_to_oda_without_meeting_him_and_the_offer_is_gone() -> void:
	_story_at_kill()
	Story.beat("cantina_owner")
	assert_true(DarkPact.offered())
	assert_false(DarkPact.offer_due())
	assert_false(DarkPact.on_cruiser())


func test_killing_him_on_the_roof_while_sworn_turns_the_remnant() -> void:
	_story_at_kill()
	DarkPact.join()
	_kill_barracks_guards()
	DarkPact.on_killed("barracks")
	assert_false(DarkPact.joined())
	assert_lte(_remnant(), -40)
	assert_true(Story.remnant_hostile())
	assert_false(DarkPact.on_roof())


func test_without_the_oath_the_town_still_falls_to_a_hostile_remnant() -> void:
	_story_at_kill()
	DarkPact.refuse()
	_kill_barracks_guards()
	assert_true(DarkPact.town_retaken())
	assert_true(Story.remnant_hostile(), "they come back shooting")
	assert_eq(Story.chapter(), "debrief", "and Oda still waits")
	assert_false(DarkPact.on_roof(), "the roof is his only on the oath, in a story save")


func test_driving_them_off_every_outpost_gives_the_town_back() -> void:
	_story_at_kill()
	DarkPact.join()
	_kill_barracks_guards()
	for id in Story.OUTPOSTS:
		Territory.take(str(id))
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS)
	assert_false(Territory.remnant_planet())


# ------------------------------------------------------------------ free roam

func test_free_roam_he_is_an_enemy_after_the_general() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	assert_false(DarkPact.on_cruiser())
	assert_false(Story.remnant_gone())
	WorldState.on_cruiser_taken("General Test", {})
	assert_true(Story.remnant_gone(), "the fleet breaks in free roam too")
	assert_true(DarkPact.on_cruiser())
	assert_true(DarkPact.hostile_at("cruiser"))
	assert_false(DarkPact.offer_due(), "no offer")
	assert_false(DarkPact.on_roof(), "the locals hold the barracks")
	_kill_barracks_guards()
	assert_true(Territory.remnant_planet())
	assert_true(DarkPact.on_roof(), "the Remnant hold the planet: he is on the roof too")
	assert_true(DarkPact.hostile_at("barracks"))
	assert_true(Story.remnant_hostile())


func test_friends_of_the_remnant_borrow_ships_in_free_play() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	WorldState.standing["imperial_remnant"] = 0
	assert_false(DarkPact.borrow_ok(), "neutral: it is stealing")
	WorldState.standing["imperial_remnant"] = 20
	assert_true(DarkPact.borrow_ok())
	assert_lt(DarkPact.borrow_cost(), 0, "it costs a little standing")
	WorldState.set_flag("remnant_fleet_beaten")
	assert_false(DarkPact.borrow_ok(), "not while they shoot on sight")


func test_droid_prices_follow_whose_side_you_are_on() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	for f in ["imperial_remnant", "locals"]:
		WorldState.standing[f] = 0
	for kind in ["cargo", "assassin"]:
		assert_eq(DarkPact.droid_price(kind, true), DroidRoster.price(kind), "neutral: list price")
		assert_eq(DarkPact.droid_price(kind, false), DroidRoster.price(kind))
	WorldState.standing["locals"] = 30
	assert_lt(DarkPact.droid_price("cargo", false), DroidRoster.price("cargo"), "the market deals with the locals' friends")
	assert_eq(DarkPact.droid_price("cargo", true), DroidRoster.price("cargo"), "the desert posts don't care")
	WorldState.standing["imperial_remnant"] = 30
	assert_lt(DarkPact.droid_price("cargo", true), DroidRoster.price("cargo"), "the desert posts deal with the Remnant's")
	for kind in ["floating", "cargo", "assassin"]:
		for post in [true, false]:
			assert_gte(DarkPact.droid_price(kind, post), DroidRoster.resale(kind), "never a buy-and-sell profit")
	var r := DroidRoster.new().buy("cargo", "", 1000, 7)
	assert_eq(int(r.cost), 7, "the roster charges what the stall asks")


func test_the_town_name_fills_his_lines() -> void:
	DarkPact.town_label = "Dustfall"
	assert_string_contains(DarkPact.line("joined"), "Dustfall")
	DarkPact.town_label = ""
	assert_string_contains(DarkPact.line("joined"), "the port")


# ------------------------------------------------------------------ his blade, and his talk

class FakePlayer extends CharacterBody3D:
	var is_downed := false
	var piloting := false
	var locked := false


## Just enough of the town's ConversationHost to see whom the post registers.
class FakeHost extends ConversationHost:
	var added: Array = []
	func add_spot(s: TalkSpot) -> void:
		added.append(s)
		spots.append(s)


func _his_body() -> NpcBody:
	var cc = CoreScript.new()
	cc.load_from()
	var n := NpcBody.new()
	n.setup(cc.get_soldier("dark_master"), Vector3.ZERO, 0.0, LookMaterials.new())
	add_child_autofree(n)
	return n


func test_his_blade_hangs_dark_on_his_hip_until_he_draws_it() -> void:
	var n := _his_body()
	var sword := n.hold_blade(Color("#ff1e1e"), "", -1.0, null, false)
	assert_not_null(sword, "a sword on the body")
	var bl := sword.get_node("Blade") as Node3D
	assert_eq(n.blade_out, 0.0, "holstered from the start")
	assert_false(bl.visible, "dark")
	assert_eq(n.hold_pose_weight(), 0.0, "arms at ease, not the guard")
	var hip := (n.joints.l_hip as Node3D).global_position
	var hand := n._blade_hand_xf().origin
	assert_lt(sword.global_position.distance_to(hip), 0.35, "the hilt at his left hip")
	assert_gt(sword.global_position.distance_to(hand), 0.3, "not in his hand")
	n.blade_drawn = true
	for i in 6:
		n._tick_blade(0.1)
		n._place_blade()
	assert_eq(n.blade_out, 1.0, "drawn")
	assert_true(bl.visible, "lit")
	assert_almost_eq(bl.scale.y, 1.0, 0.001)
	assert_eq(n.hold_pose_weight(), 1.0, "and the guard is up")
	assert_lt(sword.global_position.distance_to(n._blade_hand_xf().origin), 0.01, "in the fist")
	n.blade_drawn = false
	n._tick_blade(0.1)
	n._place_blade()
	assert_eq(n.blade_extent(), 0.5, "going back: the blade shortens first")
	for i in 5:
		n._tick_blade(0.1)
	n._place_blade()
	assert_false(bl.visible, "and the hilt hangs dark again")


func test_hold_blade_still_starts_lit_in_the_hand_by_default() -> void:
	var n := _his_body()
	var sword := n.hold_blade(Color("#ff1e1e"))
	assert_eq(n.blade_out, 1.0)
	assert_true((sword.get_node("Blade") as Node3D).visible)


func test_the_blade_comes_out_when_he_is_hostile_and_the_fight_is_on() -> void:
	var post := DarkMasterPost.new()
	post.cfg = DarkPact.cfg()
	var p := FakePlayer.new()
	add_child_autofree(p)
	var b := NpcBody.new()
	add_child_autofree(b)
	p.global_position = Vector3(5, 0, 0)
	assert_false(post.blade_wanted(false, b), "at ease: on the hip")
	post.player = p
	assert_true(post.blade_wanted(true, b), "hostile, five metres off: drawn")
	p.is_downed = true
	assert_false(post.blade_wanted(true, b), "you are down: he hangs it up")
	p.is_downed = false
	p.global_position = Vector3(200, 0, 0)
	assert_false(post.blade_wanted(true, b), "you are long gone: hung up")
	post.free()


## He joins the host through add_spot, as the general does: that gives his brain
## the AI service and the host's reply handlers. Appended to the host's list by
## hand, every answer was canned with AI on and the box locked after your first line.
func test_he_joins_the_host_through_add_spot() -> void:
	_story_at_kill()
	var post := DarkMasterPost.new()
	post.cfg = DarkPact.cfg()
	var h := FakeHost.new()
	h.autosave = false
	add_child_autofree(h)
	post.attach_host(h)
	assert_eq(h.added, [post.spot], "registered with the host")
	assert_true(post.spot.brain.line_done.is_connected(post._on_line), "his own line handler after the host's")
	post.free()


# ------------------------------------------------------------------ his answer (no scene)

func test_decide_join_and_refuse() -> void:
	_story_at_kill()
	var post := DarkMasterPost.new()
	post.cfg = DarkPact.cfg()
	assert_true(post.decide("join"))
	assert_false(post.decide("refuse"), "one answer")
	assert_true(DarkPact.joined())
	assert_string_contains(post.said, "local guards")
	post.free()
	WorldState.reset()
	_story_at_kill()
	post = DarkMasterPost.new()
	post.cfg = DarkPact.cfg()
	assert_true(post.decide("refuse"))
	assert_eq(post.said, "Then I must destroy you.")
	assert_true(bool(post.hostile.get(DarkMasterPost.CRUISER, false)))
	post.free()


func test_his_blade_falls_where_he_does_and_you_activate_it() -> void:
	_story_at_kill()
	var content = load("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var gear := GearController.new()
	gear.content = content
	gear.items = ItemKit.new()
	gear.labels = ItemKit._read_json(GearController.LABELS_PATH).get("labels", {})
	var item := str(DarkPact.cfg().get("drops", ""))
	var at := Vector3(3, -14, 20)
	var node = gear.drop_item({ "id": "dark_master_blade_cruiser", "item": item, "reach": 2.6 }, at)
	assert_not_null(node, "it lies where he fell")
	assert_eq((node as Node3D).position.x, at.x)
	assert_null(gear.drop_item({ "id": "dark_master_blade_cruiser", "item": item }, at), "once")
	assert_eq(gear._take(node), "picked_up")
	assert_true(WorldState.inventory.has(item))
	assert_false(WorldState.inventory.is_attached(item), "picked up, not switched on")
	assert_eq(gear.blade_color().a, 0.0, "your blue blade is still yours")
	assert_eq(gear.toggle_item(item), "attached", "activated in the inventory")
	assert_gt(gear.blade_color().r, 0.9, "now it is red")
	assert_true(WorldState.weapon_allowed("energy_blade"), "and it can be drawn")
	var saved := WorldState.inventory.to_save()
	WorldState.inventory = Inventory.new()
	assert_eq(gear.blade_color().a, 0.0)
	WorldState.inventory.from_save(saved)
	assert_gt(gear.blade_color().r, 0.9, "still red after a reload")
	assert_null(gear.drop_item({ "id": "dark_master_blade_cruiser", "item": item }, at), "taken stays taken")
	gear.free()


# ------------------------------------------------------------------ the sword fight

func _fighter() -> BladeFighter:
	return BladeFighter.new(DarkPact.cfg().get("blade", {}))


func test_he_runs_you_down_then_strikes() -> void:
	var f := _fighter()
	assert_eq(str(f.update(0.016, 6.0, 0.0).act), "chase", "out of reach, short of a bound")
	var out := f.update(0.016, 1.5, 0.0)
	assert_ne(str(out.start), "", "in reach: a blow starts")
	assert_false(bool(out.strike), "it lands part way through")
	var landed := false
	for i in 120:
		if bool(f.update(0.016, 1.5, 0.0).strike):
			landed = true
			break
	assert_true(landed)
	assert_eq(str(f.update(0.016, 1.5, 0.0).start), "", "a pause between blows")
	assert_eq(f.blows, 1)


func test_a_blocked_blow_staggers_him() -> void:
	var f := _fighter()
	f.on_parried()
	assert_eq(f.mode, "stagger")
	assert_eq(str(f.update(0.1, 1.5, 0.0).act), "hold")
	assert_eq(f.guard(10.0, true, false), 10.0, "open while he reels")


func test_after_a_rush_he_backs_off_circles_and_comes_again() -> void:
	var c: Dictionary = DarkPact.cfg().get("blade", {}).duplicate()
	c.flurry = [2, 2]
	var f := BladeFighter.new(c)
	var landed := 0
	for i in 300:
		if bool(f.update(0.016, 1.5, 0.0).strike):
			landed += 1
		if f.mode == "back_off":
			break
	assert_eq(landed, 2, "a rush of two blows")
	assert_eq(f.mode, "back_off", "then he gives ground")
	f._cd = 0.0
	assert_eq(str(f.update(0.016, 3.0, 0.0).act), "back_off", "out of reach, short of his spacing")
	assert_eq(str(f.update(0.016, f.spacing() + 0.5, 0.0).act), "circle", "at his spacing he circles")
	var acts := {}
	for i in 200:
		acts[str(f.update(0.016, f.spacing() + 0.5, 0.0).act)] = true
	assert_true(acts.has("chase"), "and comes again")


func test_stepping_into_his_reach_while_he_circles_draws_a_cut() -> void:
	var f := _fighter()
	f._back_off()
	f.update(0.016, f.spacing(), 0.0)
	assert_eq(f.mode, "circle")
	assert_ne(str(f.update(0.016, 1.5, 0.0).start), "", "he cuts at you")
	for i in 120:
		if bool(f.update(0.016, 1.5, 0.0).strike):
			break
	assert_eq(f.mode, "back_off", "one cut, then off again")


func test_a_blocked_blow_sends_him_back_after_he_reels() -> void:
	var f := _fighter()
	f.on_parried()
	for i in 60:
		f.update(0.016, 3.0, 0.0)          # (the clash shoved you out of his reach)
	assert_eq(f.mode, "back_off")


func test_a_clash_shoves_you_back_along_the_ground() -> void:
	var c := preload("res://src/systems/player/character_controller.gd").new()
	c.on_ground = true
	c.push = Vector3(7.0, 0.0, 0.0)
	c.velocity = c.push
	c.push_fade = 16.0
	c.push_holds = true
	for i in 60:
		c.on_ground = true
		c.step(0.016, 0.0, -INF)
	assert_gt(c.body_pos.x, 1.0, "slid back over a metre, feet on the ground")
	assert_eq(c.push, Vector3.ZERO, "and the shove fades out")
	assert_false(c.push_holds)


func test_he_bounds_off_a_roof_and_across_the_deck() -> void:
	var f := _fighter()
	assert_eq(str(f.update(0.016, 4.0, -6.0).act), "leap", "you are below him")
	for i in 60:
		f.update(0.016, 4.0, -6.0)
	assert_eq(f.leaps, 1)
	var g := _fighter()
	assert_eq(str(g.update(0.016, 15.0, 0.0).act), "leap", "a long way off on the level")
	assert_eq(str(_fighter().update(0.016, 40.0, 0.0).act), "chase", "too far for one bound")
	var to := f.leap_target(Vector3.ZERO, Vector3(10, -6, 0))
	assert_lt(to.distance_to(Vector3(10, -6, 0)), f.reach(), "he lands within reach")
	assert_gt(BladeFighter.leap_point(Vector3.ZERO, Vector3(10, 0, 0), 0.5, 3.0).y, 2.9, "an arc")


func test_his_blade_turns_most_bolts_from_the_front() -> void:
	var f := _fighter()
	var through := 0
	for i in 200:
		if f.guard(10.0, true, false) > 0.0:
			through += 1
	assert_between(through, 30, 90, "about three in ten get through")
	assert_eq(f.guard(10.0, false, false), 10.0, "from behind, every one")
	f.update(0.016, 1.5, 0.0)          # a blow starts
	assert_eq(f.guard(10.0, true, false), 10.0, "mid-blow he is open")


func test_the_cantina_hears_about_him_and_the_barracks() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var heard := func(): return WorldState.rumors("confidant", [], 99).map(func(r): return str(r.id))
	assert_false(heard.call().has("r_dark_master"))
	WorldState.on_cruiser_taken("General Test", {})
	assert_true(heard.call().has("r_dark_master"), "pilots talk about the one in black")
	_kill_barracks_guards()
	assert_true(heard.call().has("r_town_retaken"))
	assert_true(heard.call().has("r_dark_roof"), "the Remnant hold the planet: he's on the roof")
	assert_false(heard.call().has("r_dark_master"), "the town news is bigger")
	Territory.take(str(Story.OUTPOSTS[0]))
	assert_false(heard.call().has("r_dark_roof"), "an outpost lost: he's gone from the roof")
	DarkPact.on_killed("cruiser")
	assert_true(heard.call().has("r_dark_master_dead"))
