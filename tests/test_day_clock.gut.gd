extends GutTest
## Issue #381: the time of day moves on with the game (day_clock.gd, pure). On
## Auto each trigger steps the day on; a fixed pick holds it; a story save
## follows its chapters until the cruiser is won, then the picker unlocks on
## Auto; the pick is saved with the world.


func before_each() -> void:
	WorldState.new_game(WorldState.FREEPLAY)


func after_all() -> void:
	WorldState.reset()


func test_freeplay_steps_the_day_on_at_each_trigger() -> void:
	assert_eq(WorldState.time_of_day, "golden")
	assert_eq(WorldState.day_pick, DayClock.AUTO)
	assert_eq(DayClock.trigger("indoors"), "noon")
	assert_eq(DayClock.trigger("respawn"), "golden")
	assert_eq(DayClock.trigger("travel"), "dusk")
	assert_eq(DayClock.trigger("indoors"), "golden")
	assert_eq(WorldState.time_of_day, "golden")


func test_a_step_never_lands_on_the_time_you_are_in() -> void:
	for i in 12:
		var was := WorldState.time_of_day
		assert_ne(DayClock.trigger("indoors"), was)


func test_after_the_light_is_moved_by_hand_the_day_goes_on_from_there() -> void:
	assert_true(DayClock.set_by_hand("dusk"))
	WorldState.time_of_day = "dusk"
	WorldState.day_pick = DayClock.AUTO
	assert_eq(DayClock.trigger("indoors"), "golden")


func test_a_fixed_pick_holds_the_time() -> void:
	assert_eq(DayClock.pick("noon"), "noon")
	assert_eq(WorldState.time_of_day, "noon")
	for t in ["indoors", "respawn", "travel", "indoors"]:
		assert_eq(DayClock.trigger(t), "", t)
	assert_eq(DayClock.on_arrival("travel"), "noon")
	assert_eq(WorldState.time_of_day, "noon")
	assert_true(DayClock.set_by_hand("dusk"), "the L key or the slider moves the pick")
	assert_eq(WorldState.day_pick, "dusk")


func test_the_seamless_hop_to_the_moon_keeps_the_time() -> void:
	assert_eq(DayClock.on_arrival("handoff"), "golden")
	assert_eq(DayClock.on_arrival(""), "golden")
	assert_eq(DayClock.on_arrival("travel"), "noon", "a faded trip moves it on")


func test_a_story_save_follows_its_chapters() -> void:
	WorldState.new_game(WorldState.STORY)
	assert_true(DayClock.locked())
	var want := { "land": "golden", "general": "golden", "t89": "golden", "meet_oda": "golden",
		"range": "golden", "remote": "golden", "smuggle_1": "dusk", "droid_merchant": "noon", "bounty": "golden" }
	for id in want:
		if Story.index(str(id)) > Story.index(Story.chapter()):
			Story.skip_to(str(id))
		DayClock.story_due()
		assert_eq(Story.chapter(), str(id))
		assert_eq(WorldState.time_of_day, str(want[id]), str(id))
		assert_eq(DayClock.on_arrival(""), str(want[id]), "a load opens on it: " + str(id))
	assert_true(WorldState.accept_job("j_bounty"), "the bounty taken")
	assert_eq(DayClock.story_due(), "dusk", "dusk once you have the bounty")
	Story.skip_to("fleet")
	DayClock.story_due()
	assert_eq(WorldState.time_of_day, "dusk")


func test_triggers_bring_in_the_chapters_time_and_never_more() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("smuggle_1")
	assert_eq(DayClock.trigger("respawn"), "dusk", "outdoors: at the next trigger")
	assert_eq(DayClock.trigger("indoors"), "", "and it stays the chapter's")
	assert_eq(DayClock.on_arrival("travel"), "dusk")


func test_the_story_locks_the_controls_until_the_cruiser_is_won() -> void:
	WorldState.new_game(WorldState.STORY)
	assert_false(DayClock.set_by_hand("noon"), "no L key")
	assert_eq(DayClock.pick("noon"), "", "no picker")
	assert_eq(WorldState.day_pick, DayClock.AUTO)
	WorldState.set_flag("cruiser_taken")
	assert_false(DayClock.locked(), "unlocked once the cruiser is won")
	assert_eq(WorldState.day_pick, DayClock.AUTO, "on Auto")
	var was := WorldState.time_of_day
	assert_ne(DayClock.trigger("indoors"), "", "the debrief's walk into the cantina moves it on")
	assert_ne(WorldState.time_of_day, was)
	var want := "dusk" if WorldState.time_of_day != "dusk" else ""
	assert_eq(DayClock.pick("dusk"), want, "the picker works")
	assert_eq(WorldState.day_pick, "dusk")


func test_the_pick_is_saved() -> void:
	DayClock.pick("dusk")
	var d := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(JSON.parse_string(JSON.stringify(d)))
	assert_eq(WorldState.day_pick, "dusk")
	assert_eq(WorldState.time_of_day, "dusk")


func test_an_old_save_loads_on_auto() -> void:
	var d := WorldState.to_save()
	d.erase("day_pick")
	d.erase("day_step")
	WorldState.from_save(JSON.parse_string(JSON.stringify(d)))
	assert_eq(WorldState.day_pick, DayClock.AUTO)
	assert_eq(DayClock.trigger("indoors"), "noon")
