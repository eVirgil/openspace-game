extends GutTest
## The quest banner (QuestNews, QuestBanner): a few big words with a sound when a
## quest or job starts, moves on or ends.


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func test_every_key_has_a_headline_and_a_known_sound() -> void:
	var sfx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/look/sound.json")).sfx
	var news: Dictionary = Story.data().get("quest_news", {})
	for key in ["quest_new", "quest_done", "quest_failed", "job_taken", "job_done", "target_new", "target_killed",
			"bounty_paid", "cargo_found", "cargo_delivered", "supplies_delivered", "droid_delivered", "objective"]:
		assert_true(news.has(key), key)
		assert_ne(str(news.get(key, {}).get("head", "")), "", key + " has a headline")
		assert_true(sfx.has(str(news.get(key, {}).get("sound", ""))), key + "'s sound is in the library")


func test_push_queues_dedups_and_caps() -> void:
	QuestNews.push("no_such_key", "x")
	assert_eq(QuestNews.take(), {}, "an unknown key is not news")
	QuestNews.push("cargo_found", "2 crates")
	QuestNews.push("cargo_found", "2 crates")
	assert_eq(QuestNews.queue.size(), 1, "the same banner twice in a row is one")
	for k in 6:
		QuestNews.push("job_done", "job %d" % k)
	assert_eq(QuestNews.queue.size(), QuestNews.MAX, "the oldest drop off")
	assert_eq(QuestNews.take().sub, "job 2")


func test_a_quest_done_is_news_only_once_it_was_offered() -> void:
	Quests.complete("barracks_rifle")
	assert_eq(QuestNews.take(), {}, "done before it was offered: no banner")
	Quests.unlock("tower_blade")
	assert_eq(QuestNews.take().key, "quest_new")
	Quests.complete("tower_blade")
	var n := QuestNews.take()
	assert_eq(n.key, "quest_done")
	assert_eq(n.head, "Quest Complete")


func test_a_job_taken_and_finished() -> void:
	assert_true(WorldState.accept_job("j_range_bet"))
	assert_eq(QuestNews.take(), { "key": "job_taken", "head": "New Job", "sub": "The range bet", "hint": "", "sound": "quest_start" })
	WorldState.on_range_record(12.0)
	assert_eq(QuestNews.take().key, "job_done")


func test_a_bounty_killed_and_paid() -> void:
	WorldState.bounty = { "run": 1, "key": "npc:bounty/1", "name": "Vel Doran", "crime": "x", "outpost": Story.OUTPOSTS[0], "pay": 1500, "state": "out" }
	WorldState.on_bounty_killed()
	var n := QuestNews.take()
	assert_eq([n.key, n.sub], ["target_killed", "Vel Doran"])
	assert_eq(WorldState.collect_bounty(), 1500)
	n = QuestNews.take()
	assert_eq([n.key, n.sub], ["bounty_paid", "+1500 cr"])


## Oda telling the fleet is news: the quest by its title, then its first step; each
## step done says the next.
func test_oda_telling_the_fleet_is_news() -> void:
	Story.skip_to("fleet")
	QuestNews.clear()
	Story.beat("cantina_owner")
	var n := QuestNews.take()
	assert_eq([n.key, n.sub], ["quest_new", "Destroy the fleet"])
	n = QuestNews.take()
	assert_eq(n.key, "objective")
	assert_string_contains(n.sub, "bay")
	assert_eq(QuestNews.take(), {}, "and that is all")
	Story.event("cruiser_landed")
	n = QuestNews.take()
	assert_eq(n.key, "objective")
	assert_string_contains(n.sub, "stairs")
	Story.event("cruiser_infiltrated")
	assert_string_contains(QuestNews.take().sub, "Kill")


## Any chapter Oda tells that sends you somewhere is news, and a "talk to Oda"
## banner still waiting from the chapter before is not shown: it was answered.
func test_oda_telling_the_range_is_news_and_not_talk_to_oda() -> void:
	QuestNews.clear()
	Story.beat("cantina_owner")           # meets Oda, told the range
	var n := QuestNews.take()
	assert_eq(n.key, "objective")
	assert_string_contains(n.sub, "range")
	assert_eq(QuestNews.take(), {})


func test_the_banner_shows_one_at_a_time_and_clears() -> void:
	var b := QuestBanner.new()
	add_child_autofree(b)
	QuestNews.push("cargo_found", "2 cases of holocrystals")
	QuestNews.push("target_killed", "Vel Doran")
	b._process(0.01)
	assert_eq(b.head.text, "CARGO FOUND")
	assert_eq(b.sub.text, "2 cases of holocrystals")
	assert_false(b.hint.visible)
	assert_eq(QuestNews.queue.size(), 1, "the next one waits")
	b._process(QuestBanner.IN + QuestBanner.HOLD + QuestBanner.OUT)
	assert_true(b.showing.is_empty())
	assert_false(b.band.visible)
	b._process(QuestBanner.GAP + 0.01)
	assert_eq(b.head.text, "TARGET KILLED")
