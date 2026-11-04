extends GutTest
## Issue #310: heists on the board. The locals' (Oda, the fence, Skrugs, T-89) on
## an outpost the Remnant hold; the general's (free roam only) on one the locals
## hold, not while Remnant standing is hostile. One at a time; take, hack and pay
## pays the stash less the crew's cut, on each side.

const CARDS := {
	"cantina_owner": "res://content/core/npcs/cantina_owner_card.json",
	"fence": "res://content/core/npcs/fence_card.json",
	"skrugs": "res://content/core/npcs/skrugs_card.json",
	"t89": "res://content/core/npcs/t89_card.json",
	"general": "res://content/core/npcs/general_card.json",
}


func before_each() -> void:
	WorldState.reset()
	WorldState.mode = WorldState.FREEPLAY
	WorldState.story = { "chapter": "free", "told": true }      # a new free roam game's (new_game)
	GameFlow.planet_id = ""


func after_each() -> void:
	WorldState.reset()


## Who of CARDS has `job` among the jobs they would offer now.
func _givers(job: String) -> Array:
	var out: Array = []
	for who in CARDS:
		var b := NpcBrain.new(null, CARDS[who])
		if b.my_jobs("stranger").any(func(j): return str(j.id) == job):
			out.append(who)
	return out


func test_who_offers_a_heist_in_free_roam() -> void:
	assert_eq(_givers(Heist.LOCALS_JOB), ["cantina_owner", "fence", "skrugs", "t89"], "the locals' four offer it")
	assert_eq(_givers(Heist.REMNANT_JOB), [], "the general has nothing to hit while the locals hold none")
	Territory.take("remnant_outpost_mid")
	WorldState.standing["imperial_remnant"] = 0
	assert_eq(_givers(Heist.REMNANT_JOB), ["general"], "one outpost held by the locals, standing 0: the general offers it")
	assert_true(str(WorldState.job(Heist.REMNANT_JOB).text).contains(Story.outpost_label("remnant_outpost_mid")),
		"his job names the outpost the locals hold")
	WorldState.standing["imperial_remnant"] = -50
	assert_eq(_givers(Heist.REMNANT_JOB), [], "hostile: he does not")
	for id in Story.OUTPOSTS:
		Territory.take(str(id))
	assert_eq(_givers(Heist.LOCALS_JOB), [], "every outpost the locals': nothing for the locals to rob")


func test_story_save_locals_only() -> void:
	WorldState.mode = WorldState.STORY
	WorldState.story = { "chapter": "smuggle_1", "told": true }
	Territory.take("remnant_outpost_mid")
	WorldState.standing["imperial_remnant"] = 0
	assert_eq(_givers(Heist.LOCALS_JOB), [], "not before the story reaches it")
	assert_eq(_givers(Heist.REMNANT_JOB), [], "never the general in a story save")
	WorldState.story = { "chapter": "heist", "told": true }
	assert_eq(_givers(Heist.LOCALS_JOB), ["cantina_owner", "fence", "skrugs", "t89"], "the locals once it is reached")
	assert_eq(_givers(Heist.REMNANT_JOB), [], "still never the general")


func _room(id: String) -> RemnantOutposts:
	var ro := RemnantOutposts.new()
	autofree(ro)
	var b := { "id": "block", "size": [10, 5.5, 7], "position": [0, 0, 0], "room": {} }
	ro.outposts = [{ "id": id, "label": Story.outpost_label(id), "xf": Transform3D.IDENTITY,
		"room": { "b": b, "lift": 0.0, "stand": OutpostRoom.stand(b) } }]
	return ro


## Take job `job`, hold the console 5 s, stay a minute, pick the stash up. Returns the outpost.
func _rob(job: String) -> String:
	assert_true(WorldState.accept_job(job), "took " + job)
	assert_true(Heist.on())
	var id := Heist.target()
	var ro := _room(id)
	var at := ro.console_point(ro.outposts[0])
	var state := ""
	for i in 51:
		state = ro.hack_step(0.1, true, at)
	assert_eq(state, "started", "the hack starts")
	for i in 599:
		state = ro.hack_step(0.1, false, at)
	assert_eq(state, "running", "59.9 s: still running")
	assert_eq(ro.hack_step(0.2, false, at), "done", "hacked")
	WorldState.inventory.pick_up(Heist.stash_entry())
	assert_eq(Heist.carrying(), 15, "15 flasks in hand")
	return id


func test_locals_heist_take_hack_pay() -> void:
	var before := WorldState.credits
	var id := _rob(Heist.LOCALS_JOB)
	assert_eq(Territory.owner(id), Territory.REMNANT, "it hits a Remnant outpost")
	assert_eq(WorldState.open_jobs("stranger").filter(func(j): return Heist.is_job(j)).size(), 0, "one heist at a time")
	assert_false(Heist.collectable("general"), "the general does not pay the locals' heist")
	var p := Heist.collect("fence")
	var each := Inventory.sell_price(WorldState._item("refined_quantonium"), WorldState._fence("port_town"))
	assert_eq(int(p.gross), 15 * each, "the fence's price for 15 flasks")
	assert_eq(int(p.cut), roundi(15 * each * Heist.cut()), "the crew's cut off the top")
	assert_eq(WorldState.credits - before, 15 * each - int(p.cut), "paid the rest")
	assert_eq(WorldState.inventory.count("refined_quantonium"), 0, "the flasks are the fence's")
	assert_false(Heist.on(), "over")
	assert_eq(Territory.owner(id), Territory.REMNANT, "a heist never flips an outpost")
	assert_true(WorldState.open_jobs("stranger").any(func(j): return str(j.id) == Heist.LOCALS_JOB), "a new one is offered")


func test_general_heist_take_hack_pay() -> void:
	Territory.take("remnant_outpost_far")
	WorldState.standing["imperial_remnant"] = 0
	var before := WorldState.credits
	var id := _rob(Heist.REMNANT_JOB)
	assert_eq(id, "remnant_outpost_far", "the outpost the locals hold")
	var standing := int(WorldState.standing["imperial_remnant"])
	var p := Heist.collect("general")
	var each := Inventory.sell_price(WorldState._item("refined_quantonium"), WorldState._fence("port_town"))
	assert_eq(int(p.gross), roundi(1.5 * 15 * each), "pay_mult times the fence's price")
	assert_eq(WorldState.credits - before, int(p.gross) - int(p.cut), "less the cut")
	assert_gt(int(WorldState.standing["imperial_remnant"]), standing, "the Remnant like it")
	assert_false(Heist.on())


func test_downed_or_lost_ends_it() -> void:
	assert_true(WorldState.accept_job(Heist.LOCALS_JOB))
	assert_true(Heist.on_downed(), "downed: off")
	assert_false(Heist.on())
	_rob(Heist.LOCALS_JOB)
	while WorldState.inventory.has("refined_quantonium"):
		WorldState.inventory.remove("refined_quantonium")      # the gate took them
	assert_true(Heist.check_lost(), "the flasks are gone: off")
	assert_false(Heist.on())


# ---- issue #413: the story's heist chapter ----------------------------------------------

func _story_heist(kill_all: bool) -> String:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("droid_merchant")
	Story.on_droid_delivered()
	Story.on_droid_delivered()
	Story.on_droid_delivered()
	assert_eq(Story.chapter(), "heist", "the droids done: the heist chapter")
	var beat := Story.beat("cantina_owner")
	assert_eq(str(beat.get("job", "")), Heist.LOCALS_JOB, "Oda puts the heist's card in front of you")
	assert_eq(Quests.state("tower_blade"), "open", "the blade she promised comes with it")
	var id := _rob(Heist.LOCALS_JOB)
	assert_eq(id, Heist.STORY_FIRST, "the first story heist hits the broken ridge outpost")
	if kill_all:
		Territory.take(id)                    # what killing every trooper there does (RemnantOutposts)
	Heist.collect("fence")
	assert_eq(Story.chapter(), "bounty", "paid at the fence: the bounty next")
	return id


func test_story_heist_then_bounty_whatever_you_killed() -> void:
	var id := _story_heist(true)
	assert_eq(Territory.owner(id), Territory.LOCALS, "killed them all: the locals have it")
	WorldState.job("j_bounty")             # Oda rolls the first contract
	assert_ne(str(WorldState.bounty.get("outpost", "")), id, "the first bounty is another outpost")
	id = _story_heist(false)
	assert_eq(Territory.owner(id), Territory.REMNANT, "sneaked: still the Remnant's")


func test_skipping_past_the_heist() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("heist")
	var c0 := WorldState.credits
	Story.skip_to("bounty")
	assert_eq(WorldState.count("heists_paid"), 1, "a heist counted as paid")
	assert_eq(WorldState.credits - c0, int(Story.chapter_cfg("heist").skipped.credits), "its pay as credits")
	assert_eq(Territory.held().size(), 0, "no outpost flipped")
	assert_false(Heist.on())
