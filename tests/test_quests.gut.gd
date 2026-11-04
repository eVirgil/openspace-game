extends GutTest
## Issue #201: optional quests in the job log, announced with a toast, with a
## waypoint the player switches on.


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func test_an_event_unlocks_a_quest_with_news_and_no_waypoint() -> void:
	Story.event("heard_of_rifle")
	assert_eq(Quests.state("barracks_rifle"), "open")
	var news := QuestNews.take()
	assert_eq(news.key, "quest_new", "the banner's news")
	assert_eq(news.sub, "Steal a rifle")
	assert_eq(QuestNews.take(), {}, "announced once")
	assert_true(Quests.waypoint().is_empty(), "no automatic waypoint")
	Story.event("heard_of_rifle")
	assert_eq(QuestNews.take(), {}, "not offered twice")


func test_the_waypoint_toggle_leads_the_pointer_one_at_a_time() -> void:
	Quests.unlock("barracks_rifle")
	Quests.unlock("tower_blade")
	assert_true(Quests.toggle_waypoint("barracks_rifle"))
	assert_eq(Objective.current().target, "marker:trooper_roof_c")
	assert_true(Quests.toggle_waypoint("tower_blade"))
	assert_false(bool(WorldState.quests.barracks_rifle.waypoint), "the other goes off")
	assert_false(Quests.toggle_waypoint("tower_blade"), "off again")
	assert_true(Quests.waypoint().is_empty())
	Quests.unlock("nomad_trade")
	assert_false(Quests.toggle_waypoint("nomad_trade"), "nowhere to point yet")


func test_done_clears_the_waypoint_and_survives_save_and_load() -> void:
	Quests.unlock("tower_blade")
	Quests.toggle_waypoint("tower_blade")
	Story.event("blade_taken")
	assert_eq(Quests.state("tower_blade"), "done")
	assert_true(Quests.waypoint().is_empty())
	Quests.unlock("barracks_rifle")
	var d := WorldState.to_save()
	WorldState.from_save(d)
	assert_eq(Quests.state("tower_blade"), "done")
	assert_eq(Quests.state("barracks_rifle"), "open")
	assert_eq(QuestNews.take(), {}, "a load is not news")


func test_the_log_lists_quests_with_a_toggle() -> void:
	Quests.unlock("barracks_rifle")
	var p := InventoryPanel.new()
	add_child_autofree(p)
	p.refresh()
	assert_true(p.job_rows.has(Objective.line("log_quests")))
	assert_true(p.quest_buttons.has("barracks_rifle"))
	p.quest_buttons.barracks_rifle.pressed.emit()
	assert_true(bool(WorldState.quests.barracks_rifle.waypoint), "the button switches it on")


func test_oda_offers_talk_to_skrugs_and_talking_to_him_ends_it() -> void:
	Story.event("talked:cantina_owner")
	assert_eq(Quests.state("talk_skrugs"), "open", "Oda's first chat offers it")
	assert_eq(QuestNews.take().sub, "Talk to Skrugs")
	assert_true(Quests.can_point("talk_skrugs"), "points at Skrugs")
	assert_eq(str(Quests.cfg("talk_skrugs").target), "npc:skrugs")
	Story.event("talked:skrugs")
	assert_eq(Quests.state("talk_skrugs"), "done")
	assert_eq(QuestNews.take().key, "quest_done")


func test_talking_to_skrugs_first_needs_no_quest() -> void:
	Story.event("talked:skrugs")
	assert_eq(Quests.state("talk_skrugs"), "done", "done before it was offered")
	assert_eq(QuestNews.take(), {}, "no news")
	Story.event("talked:cantina_owner")
	assert_eq(QuestNews.take(), {}, "Oda has nothing to offer then")
