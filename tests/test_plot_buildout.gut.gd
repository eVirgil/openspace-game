extends GutTest
## The plot plan's build-out (issues #202-#205, #208-#215): the story line from the
## landing to the end card, the general, the hidden gear, the fence's upgrades and
## armour, the nomads, the droid merchant. Tiny and headless.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const Health := preload("res://src/systems/combat/health.gd")

var content


class FakePlayer extends CharacterBody3D:
	var max_health := 100
	var health = preload("res://src/systems/combat/health.gd").new(100)
	var jetpack
	var piloting := false
	var locked := false


## Just enough of the town's ConversationHost for the pit meeting.
class FakeHost extends ConversationHost:
	func add_spot(s: TalkSpot) -> void:
		spots.append(s)
	func start_talk(s: TalkSpot = null) -> void:
		talking = true
		active = s
	func end_talk() -> void:
		talking = false
		active = null


## Just enough of the town for the general's walk out of the pit.
class FakeDemo extends Node:
	var nav = FakeNav.new()
	var town = null


class FakeNav extends RefCounted:
	func path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, from + Vector3(0, 0, 6), to])


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)
	content = CoreContent.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


func _general() -> GeneralPost:
	var g := GeneralPost.new()
	add_child_autofree(g)
	return g


# ---- #215: the chapters, walked by their events -----------------------------------

func test_the_story_walks_every_chapter() -> void:
	assert_eq(Story.chapter(), "land")
	var steps := [["landed", "general"], ["general_done", "t89"]]
	for s in steps:
		assert_true(Story.event(s[0]), s[0])
		assert_eq(Story.chapter(), s[1])
	Story.beat("t89")
	assert_eq(Story.chapter(), "meet_oda", "T-89 told it: Oda next")
	Story.beat("cantina_owner")
	assert_eq(Story.chapter(), "range")
	for s in [["range_visited", "remote"], ["range_visited", "smuggle_1"]]:
		Story.event(s[0])
		assert_eq(Story.chapter(), s[1])
	WorldState.story.took_run = true
	Story.event("smuggle_sold")
	assert_eq(Story.chapter(), "droid_merchant")
	for i in 3:
		Story.on_droid_delivered()
	assert_eq(Story.chapter(), "heist")
	for s in [["heist_paid", "bounty"], ["bounty_paid", "fleet"], ["cruiser_taken", "debrief"], ["told:debrief", "end"]]:
		Story.event(s[0])
		assert_eq(Story.chapter(), s[1])
	EndCard.close()
	assert_eq(Story.chapter(), "free")
	assert_string_contains(str(Story.beat("cantina_owner").say), "native tribes")


func test_freeplay_skips_the_story_only_chapters_and_old_saves_rename() -> void:
	WorldState.reset()
	assert_eq(Story.chapter(), "meet_oda")
	var d := WorldState.to_save()
	d.story = { "chapter": "smuggle_2", "told": false }
	WorldState.from_save(d)
	assert_eq(Story.chapter(), "droid_merchant")


# ---- #203: the general ---------------------------------------------------------------

func test_the_general_meets_you_in_the_pit_and_moves_to_the_barracks() -> void:
	Story.event("landed")
	assert_eq(GeneralPost.station(), "pit")
	var g := _general()
	assert_not_null(g.body)
	g.talk_ended()
	assert_eq(Story.chapter(), "t89")
	assert_eq(GeneralPost.station(), "barracks")
	WorldState.reset()
	assert_eq(GeneralPost.station(), "barracks", "issue #310: free roam too, in the barracks yard (never the pit)")


func test_the_pit_meeting_ends_in_a_search_and_a_hint_at_work() -> void:
	Story.event("landed")
	var g := _general()
	g._begin_meeting()
	for i in 3:
		g._on_line({ "applied": [] })
	assert_eq(g.verdict, "", "three lines: still talking")
	g._on_line({ "applied": [] })
	assert_eq(g.verdict, "search", "four lines: newcomers are searched")
	assert_eq(int(WorldState.standing.imperial_remnant), 0, "a routine search costs nothing")
	assert_eq(g.said, g._line("droid_hint"), "he closes with the hint")
	assert_eq(Quests.state("general_droids"), "open")
	g.talk_ended()
	assert_eq(Story.chapter(), "t89")
	assert_true(g.take_job())
	g.hand_over(int(WorldState.droids.add("assassin", "").uid))
	assert_eq(Quests.state("general_droids"), "done", "the first droid finishes it")


func test_the_meeting_opens_the_moment_you_climb_out_wherever_you_stand() -> void:
	Story.event("landed")
	var g := _general()
	var h := FakeHost.new()
	h.autosave = false                  # never the real save
	add_child_autofree(h)
	var p := FakePlayer.new()
	add_child_autofree(p)
	p.global_position = g.body.global_position + Vector3(14, 0, -8)
	g.player = p
	g.attach_host(h)
	g._physics_process(0.016)
	assert_true(g.meeting, "out of the ship, 16 m off: he is on you")
	assert_eq(h.active, g.spot, "the talk is open")
	assert_ne(g.spot.hold_line, "", "and you can't walk away")


func test_after_the_search_he_walks_out_and_you_stay_put() -> void:
	Story.event("landed")
	var demo := FakeDemo.new()
	add_child_autofree(demo)
	var g := GeneralPost.new()
	g.demo = demo
	add_child_autofree(g)
	var p := FakePlayer.new()
	add_child_autofree(p)
	p.global_position = Vector3(10, 0, 5)
	g.player = p
	g._begin_meeting()
	for i in 4:
		g._on_line({ "applied": [] })
	assert_eq(g.verdict, "search")
	var tod := WorldState.time_of_day
	var pit: Vector3 = g.body.global_position
	var him := g.body
	g.talk_ended()
	assert_eq(Story.chapter(), "t89")
	assert_true(g.leaving(), "he walks out, no cut")
	assert_eq(g.body, him, "the same man, not one at the barracks")
	for i in 30:
		g._physics_process(0.1)
	assert_gt(him.global_position.distance_to(pit), 2.0, "on his way")
	assert_almost_eq((him as MerchantNPC).move_speed, 1.6, 0.01, "walking legs")
	for i in 2000:
		if not g.leaving():
			break
		g._physics_process(0.1)
	assert_false(g.leaving(), "in at the barracks")
	assert_eq(g._where, "barracks")
	assert_almost_eq(g.body.global_position.distance_to(g._spot(g.cfg.barracks)), 0.0, 0.01, "stood where he walked to")
	assert_eq(p.global_position, Vector3(10, 0, 5), "you stand where you stood")
	assert_eq(WorldState.time_of_day, tod, "the same time of day")


func test_an_insolent_newcomer_is_searched_at_a_cost() -> void:
	Story.event("landed")
	var g := _general()
	g._begin_meeting()
	g.on_insult()
	for i in 4:
		g._on_line({ "applied": [] })
	assert_eq(g.verdict, "search")
	assert_eq(int(WorldState.standing.imperial_remnant), -15, "the insult and the search")


func test_polite_is_neutral_and_insults_get_you_searched() -> void:
	var g := _general()
	var brain := NpcBrain.new(null, GeneralPost.CARD_PATH)
	assert_false(brain.filter.is_hostile("Just passing through, sir."))
	assert_true(brain.filter.is_hostile("shut up, you fascist"))
	WorldState.inventory.add("holocrystals", 2)
	assert_false(g.on_insult(), "one insult: standing only")
	assert_eq(int(WorldState.standing.imperial_remnant), -5)
	assert_true(g.on_insult(), "two: searched on the spot")
	assert_false(WorldState.inventory.has("holocrystals"), "contraband taken")


# ---- #204, #205: droids for the general, the crash site tip -------------------------

func test_droid_jobs_pay_three_times_and_raise_standing() -> void:
	var g := _general()
	assert_true(g.take_job())
	var d := WorldState.droids.add("assassin", "")
	var c0 := WorldState.credits
	assert_eq(g.hand_over(int(d.uid)), 3 * DroidRoster.resale("assassin"))
	assert_eq(WorldState.credits, c0 + 3 * DroidRoster.resale("assassin"))
	assert_eq(int(WorldState.standing.imperial_remnant), 5)
	assert_false(g.job_active(), "open again for the next droid")
	WorldState.standing.imperial_remnant = -39
	assert_true(g.take_job(), "-39 still gets jobs")
	WorldState.jobs_taken.erase(GeneralPost.job_id())
	WorldState.standing.imperial_remnant = -40
	assert_false(g.take_job(), "hostile: no work")


func test_good_standing_tips_the_crash_site_and_the_saber_finishes_it() -> void:
	var g := _general()
	assert_false(g.maybe_tip())
	WorldState.standing.imperial_remnant = 20
	assert_true(g.maybe_tip())
	assert_eq(Quests.state("crashed_cruiser"), "open")
	assert_true(Quests.waypoint().is_empty(), "waypoint off by default")
	var saber := _pickup("wreck_red_saber")
	Story.event(str(saber.event))
	assert_eq(Quests.state("crashed_cruiser"), "done")


# ---- #210: hidden gear ------------------------------------------------------------------

func _pickup(id: String) -> Dictionary:
	for e in content.get_pickups("port_town"):
		if str(e.id) == id:
			return e
	return {}


func test_hints_open_quests_and_the_hidden_gear_unlocks_weapons() -> void:
	var oda := NpcBrain.new(null, "res://content/core/npcs/cantina_owner_card.json")
	assert_false(oda.hints_for("What do you know about the Remnant guards?").is_empty())
	assert_eq(Quests.state("barracks_rifle"), "open")
	var skrugs := NpcBrain.new(null, "res://content/core/npcs/skrugs_card.json")
	skrugs.hints_for("Any nomad packs out there?")
	assert_eq(Quests.state("nomad_trade"), "open")
	assert_false(WorldState.weapon_allowed("rifle_blaster"))
	var rifle := _pickup("barracks_rifle")
	assert_true(WorldState.inventory.pick_up(rifle))
	Story.event(str(rifle.event))
	assert_true(WorldState.weapon_allowed("rifle_blaster"))
	assert_eq(Quests.state("barracks_rifle"), "done")
	assert_eq(str(_pickup("pit_jetpack").get("inside", "")), "pit_hauler", "free play: the jetpack is inside the cargo droid")


## A story save finds the jetpack on the cantina's lookout floor, by the blade,
## under the same id (so a save that took it from the droid keeps it taken).
func test_story_jetpack_lies_on_the_cantina_tower() -> void:
	for layout in ["", "port_round"]:
		var by_id := {}
		for e in content.get_pickups("port_town", layout, WorldState.STORY):
			by_id[str(e.id)] = e
		var jet: Dictionary = by_id.pit_jetpack
		var blade: Dictionary = by_id.tower_blade
		assert_eq(str(jet.get("inside", "")), "", "not inside the droid (%s)" % layout)
		assert_eq(str(jet.marker), str(blade.marker), "on the blade's marker (%s)" % layout)
		var d := Vector3(float(jet.offset[0]), float(jet.offset[1]), float(jet.offset[2])) \
			- Vector3(float(blade.offset[0]), float(blade.offset[1]), float(blade.offset[2]))
		assert_almost_eq(d.y, 0.0, 0.01, "on the lookout floor with it (%s)" % layout)
		assert_almost_eq(d.length(), 1.0, 0.01, "a metre from it (%s)" % layout)
	var free: Array = content.get_pickups("port_town", "port_round", WorldState.FREEPLAY).filter(func(e): return str(e.id) == "pit_jetpack")
	assert_eq(str(free[0].get("inside", "")), "pit_hauler", "free play keeps it in the droid")
	assert_true(WorldState.rumors("stranger", [], 99).any(func(r): return str(r.id) == "r_tower_jetpack"), "the story's rumor names the tower")
	assert_false(WorldState.rumors("stranger", [], 99).any(func(r): return str(r.id) == "r_pit_hauler"), "not the droid")


# ---- #212: the droid merchant ----------------------------------------------------------

func test_three_droids_end_the_chapter_and_oda_tells_of_the_blade() -> void:
	Story.skip_to("droid_merchant")
	assert_eq(Story.droids_wanted(), 3)
	assert_eq(Story.droid_wanted_kind(), "cargo")
	Story.on_droid_delivered()
	assert_string_contains(Story.line_of(Story.chapter_cfg(), "remind"), "2 more")
	Story.on_droid_delivered()
	Story.on_droid_delivered()
	assert_eq(Story.chapter(), "heist", "issue #413: the heist comes before the bounty")
	Story.beat("cantina_owner")
	assert_eq(Quests.state("tower_blade"), "open", "Oda tells you about the blade on the tower")


# ---- #211: the nomads ----------------------------------------------------------------------

func test_nomads_win_over_in_a_minute_and_trade_goods_for_meat() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/species/dune_nomads.json"))
	assert_almost_eq(float(d.hostile.survive_s), 60.0, 0.1)
	WorldState.inventory.add("food", 30)
	assert_false(NativesDirector.swap_food("jetpack", 31), "not enough meat")
	assert_true(NativesDirector.swap_food("jetpack", 30))
	assert_true(WorldState.inventory.has("jetpack"))
	assert_eq(WorldState.inventory.count("food"), 0)


# ---- #208, #209: the fence -------------------------------------------------------------------

func test_gun_and_jetpack_upgrades() -> void:
	WorldState.credits = 1000
	var pistol: Dictionary = CharacterKit._read_json("res://content/core/weapons/pistol_blaster.json")
	assert_eq(GearUpgrades.buy("pistol_damage"), "bought")
	assert_eq(GearUpgrades.buy("pistol_damage"), "", "one-time")
	assert_almost_eq(float(GearUpgrades.apply(pistol, "pistol_blaster").damage), float(pistol.damage) * 1.75, 0.01)
	GearUpgrades.buy("jetpack_fuel")
	var jet: Dictionary = content.get_item("jetpack")
	WorldState.from_save(WorldState.to_save())
	assert_almost_eq(float(GearUpgrades.apply(jet, "jetpack").jetpack.fuel), float(jet.jetpack.fuel) * 2.0, 0.01, "saved")
	assert_eq(WorldState.credits, 1000 - 150 - 250)


func test_the_gear_trader_sells_the_legal_goods_and_the_fence_the_armour() -> void:
	var gear := GearController.new()
	gear.content = content
	gear.labels = CharacterKit._read_json("res://content/core/flow/gear.json").labels
	var rows := func(id: String) -> Array:
		return gear.trade_options(content.get_vendor(id)).map(func(r): return str(r.id))
	var trader: Array = rows.call("gear_trader")
	for id in ["pistol_damage", "rifle_rate", "jetpack_fuel", "sniper_rifle"]:
		assert_true(trader.has("offer:" + id), "the gear trader sells " + id)
	assert_true(trader.has("buy:jetpack"), "and jetpacks")
	assert_false(trader.has("locked:quantonium_armour"), "not the fence's armour")
	var fence: Array = rows.call("fence")
	assert_true(fence.has("locked:quantonium_armour"), "the fence's armour")
	assert_false(fence.any(func(r): return str(r).begins_with("offer:")), "and no upgrades at the fence")
	assert_eq(gear.offer_wares(), [], "nothing for him to offer in the chat before the bounty")
	gear.free()
	var card := NpcBrain.new(null, "res://content/core/npcs/fence_card.json")
	assert_string_contains(str(card.card.rules), "gear trader", "he sends you there for upgrades")


func test_the_fence_shows_the_armour_locked_until_the_bounty() -> void:
	var ids := func(a: Array): return a.map(func(o): return str(o.id))
	assert_true(ids.call(GearUpgrades.locked_offers()).has("quantonium_armour"), "on the menu, locked")
	assert_false(ids.call(GearUpgrades.open_offers()).has("quantonium_armour"))
	var labels: Dictionary = CharacterKit._read_json("res://content/core/flow/gear.json").labels
	var o := GearUpgrades.offer("quantonium_armour")
	assert_string_contains(str(labels.offer_locked) % [str(o.label), int(o.price), str(o.locked)], "bounty")
	var gear := GearController.new()
	gear.content = content
	gear.labels = labels
	var fence_cfg: Dictionary = CharacterKit._read_json(GearUpgrades.FENCE_PATH)
	var rows: Array = gear.trade_options(fence_cfg).map(func(r): return str(r.id))
	assert_true(rows.has("locked:quantonium_armour"), "the stall's menu shows it locked")
	gear._trade_said = ""
	gear.last_trade = ""
	gear.menu = DroidMenu.new()
	gear._on_trade("locked:quantonium_armour", fence_cfg)
	assert_eq(gear.last_trade, "locked", "picking it buys nothing")
	assert_string_contains(gear._trade_said, "after your first bounty")
	assert_false(WorldState.inventory.has("quantonium_armour"))
	gear.menu.free()
	gear.free()
	WorldState.bump("bounties_paid")
	assert_false(ids.call(GearUpgrades.locked_offers()).has("quantonium_armour"), "unlocked")
	assert_true(ids.call(GearUpgrades.open_offers()).has("quantonium_armour"))
	var fence := NpcBrain.new(null, "res://content/core/npcs/fence_card.json")
	assert_string_contains(str(fence.card.voice), "quantonium armour", "he is always selling it")


func test_armour_after_the_bounty_triples_health() -> void:
	WorldState.credits = 1000
	assert_eq(GearUpgrades.buy("quantonium_armour"), "", "locked before the bounty")
	WorldState.bump("bounties_paid")
	assert_eq(GearUpgrades.buy("quantonium_armour"), "bought")
	assert_eq(WorldState.credits, 500)
	var gear := GearController.new()
	gear.content = content
	var p := FakePlayer.new()
	add_child_autofree(p)
	gear.player = p
	assert_eq(gear.toggle_item("quantonium_armour"), "attached")
	assert_eq(p.health.max_hp, 300)
	assert_eq(gear.toggle_item("quantonium_armour"), "detached")
	assert_eq(p.health.max_hp, 100)
	gear.free()
	WorldState.from_save(WorldState.to_save())
	assert_true(WorldState.inventory.has("quantonium_armour"))
	# He never runs out: sell it back to him and buy it again, as often as you like.
	var fence: Dictionary = content.get_vendor("fence")
	var it: Dictionary = content.get_item("quantonium_armour")
	for i in 2:
		assert_true(GearUpgrades.open_offers().has(GearUpgrades.offer("quantonium_armour")), "still on his stall")
		var paid := WorldState.inventory.sell("quantonium_armour", it, fence)
		assert_eq(paid, int(round(float(it.value) * float(fence.any_rate))), "he buys it back")
		assert_false(WorldState.inventory.has("quantonium_armour"))
		WorldState.credits = 1000
		assert_eq(GearUpgrades.buy("quantonium_armour"), "bought", "and sells it again")
		assert_true(WorldState.inventory.has("quantonium_armour"))
	assert_lt(Inventory.sell_price(it, fence), int(GearUpgrades.offer("quantonium_armour").price), "no profit in the loop")
	# An old save that marked it bought still sees it on sale.
	WorldState.gear_fits.append("quantonium_armour")
	assert_false(GearUpgrades.bought("quantonium_armour"))


# ---- #213: who the first bounty is on ---------------------------------------------------------

func test_the_first_bounty_is_the_general_at_minus_15() -> void:
	Story.skip_to("bounty")
	WorldState.standing.imperial_remnant = -15
	WorldState.job("j_bounty")
	assert_true(bool(WorldState.bounty.get("general", false)))
	assert_eq(str(WorldState.bounty.name), "General Vask")
	assert_true(WorldState.accept_job("j_bounty"))
	assert_eq(GeneralPost.station(), "", "he is out at the outpost")
	WorldState.on_bounty_killed()
	assert_true(WorldState.has_flag("general_dead"))
	assert_string_contains(EndCard.text(), "general dead")


func test_above_minus_15_the_officer_and_the_general_lives() -> void:
	Story.skip_to("bounty")
	WorldState.standing.imperial_remnant = -14
	WorldState.job("j_bounty")
	assert_false(bool(WorldState.bounty.get("general", false)))
	assert_string_contains(EndCard.text(), "the general stays")
	Story.skip_to("free")
	assert_eq(GeneralPost.station(), "barracks", "still buying droids after the Remnant leave")


# ---- #186 / #214: own ship, upgrades, saved -----------------------------------------------------

func test_earn_rebuild_upgrade_save_load() -> void:
	var s := ShipSalesman.new()
	add_child_autofree(s)
	WorldState.credits = 2500
	assert_eq(s.rebuild(), "rebuilt")
	assert_true(ShipPilot.berth_open({}, 0), "the fleet chapter has your own ship")
	assert_false(ShipPilot.berth_open({}, 1), "and no free keys")
	assert_eq(s.fit(WorldState.wreck_ship, "hull"), "fitted")
	assert_eq(GearUpgrades.buy("pistol_rate"), "bought")
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	assert_true(WorldState.owns_ship())
	assert_true(ShipUpgrades.has(WorldState.wreck_ship, "hull"))
	assert_true(GearUpgrades.bought("pistol_rate"))
	assert_eq(WorldState.credits, 2500 - 500 - 1200 - 150)
