extends GutTest
## Issue #328: AI characters off by default, the whole story with them off, and a
## cloud model that answers when they are on.
##
## Off: no provider is ever sent a request, every reply is a canned line from the
## character's card, each character has a topic menu, and a hint the player's
## words set off is told in the card's authored line. The story plays from the
## landing to free play that way. On: a model that is still loading is skipped
## (the turn is canned, the next one tries again), a turn with no first word in
## time is canned ("slow"), a cloud key picks its provider, and every failure has
## a reason in plain words. The Anthropic path runs over real HTTP against
## tools/llm/mock_llm_server.py when python3 is there.

const ODA := "res://content/core/npcs/cantina_owner_card.json"
const T89 := "res://content/core/npcs/t89_card.json"
const GENERAL := "res://content/core/npcs/general_card.json"
const SKRUGS := "res://content/core/npcs/skrugs_card.json"
const FENCE := "res://content/core/npcs/fence_card.json"
const MOCK := "res://tools/llm/mock_llm_server.py"
const MOCK_PORT := 8793
const GOOD_KEY := "sk-ant-mock-good-key-0000"
const NO_USER := "user://test_ai_off_no_user_config.json"
const KEYS := "user://test_ai_off_keys.cfg"

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownDemo := preload("res://scenes/town_demo.gd")

var spy: ScriptedProvider             ## sits in the "local" slot: AI off, it must never hear a thing
var _mock_pid := -1


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS))


func after_all() -> void:
	if _mock_pid > 0:
		OS.kill(_mock_pid)


func _cfg() -> LLMConfig:
	var c := LLMConfig.new()
	c.user_path = NO_USER
	c.keys_path = KEYS
	c.load_all()
	return c


## A service on the shipped defaults (AI off) with a spy in the local slot.
func _svc(cfg: LLMConfig = null) -> LLMService:
	var svc := LLMService.new()
	add_child_autofree(svc)
	svc.configure(cfg if cfg != null else _cfg())
	spy = ScriptedProvider.new("local", [{ "text": "{\"say\": \"From the model.\", \"tone\": \"warm\", \"then\": []}" }])
	svc.providers["local"] = spy
	svc._recheck_left = 999.0
	return svc


func _brain(svc: LLMService, card: String) -> NpcBrain:
	var b := NpcBrain.new(svc, card)
	b.log_transcripts = false
	return b


## Talk to `teller` the way the town does with AI off: their greeting (or the
## story's line), then every topic on their menu but goodbye. Returns the beat.
func _talk(svc: LLMService, card: String, teller: String) -> Dictionary:
	var b := _brain(svc, card)
	b.begin_visit()
	var beat := Story.beat(teller)
	var menu := b.topics()
	assert_false(menu.is_empty(), teller + " has a topic menu")
	for t in menu:
		if str(t.id) == "bye":
			continue
		assert_true(b.say_topic(str(t.id)), "%s answers %s" % [teller, t.id])
		assert_false(b.busy, "a canned answer is at once")
		assert_eq(str(b.last_turn.source), "canned", "%s / %s is a written line" % [teller, t.id])
		assert_ne(str(b.last_turn.say), "", "%s / %s says something" % [teller, t.id])
	b.end_visit()
	return beat


# ---- off by default ---------------------------------------------------------------

func test_a_fresh_install_has_ai_characters_off() -> void:
	var c := _cfg()
	assert_false(c.ai_enabled())
	assert_false(c.first_run_asked(), "the first launch asks")
	var svc := _svc(c)
	assert_false(svc.ai_on())
	assert_eq(svc.active_chain(), [], "nothing to ask")
	assert_false(svc.active_chain(true).is_empty(), "the settings panel's Test still can")
	var rep := svc.brain_report()
	assert_true(bool(rep.off))
	assert_true(str(rep.summary).contains("off"))


func test_off_starts_no_sidecar_and_runs_no_health_checks() -> void:
	var c := _cfg()
	c.set_value("profiles/local/sidecar/enabled", true)
	var svc := _svc(c)
	svc.start_sidecar()
	assert_null(svc.sidecar, "no llama-server while AI characters are off")
	svc._recheck_left = 0.0
	svc._process(0.1)
	assert_true(svc._health_reqs.is_empty(), "and nothing is probed")


func test_off_every_reply_is_canned_and_no_provider_hears_it() -> void:
	var svc := _svc()
	var b := _brain(svc, ODA)
	b.begin_visit()
	assert_true(b.say("Hello there, what's good here?"))
	assert_eq(str(b.last_turn.source), "canned")
	assert_false(b.busy)
	assert_eq(spy.requests.size(), 0, "the model was never asked")
	b.end_visit()
	await get_tree().process_frame
	assert_eq(spy.requests.size(), 0, "not even for the visit summary")


func test_turning_it_on_reaches_the_model() -> void:
	var svc := _svc()
	svc.set_ai_enabled(true)
	assert_true(svc.ai_on())
	assert_true(svc.active_chain().has("local"))
	var b := _brain(svc, ODA)
	b.begin_visit()
	b.say("Hello there")
	var t0 := Time.get_ticks_msec()
	while b.busy and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_eq(spy.requests.size(), 1)
	assert_eq(str(b.last_turn.source), "model")
	assert_eq(str(b.last_turn.say), "From the model.")


func test_the_first_run_answer_is_saved_and_never_asked_again() -> void:
	var path := "user://test_ai_off_first_run.json"
	var c := LLMConfig.new()
	c.user_path = path
	c.keys_path = KEYS
	c.load_all()
	c.set_first_run_asked()
	c.set_ai_enabled(true)
	assert_true(c.save_user())
	var again := LLMConfig.new()
	again.user_path = path
	again.load_all()
	assert_true(again.first_run_asked())
	assert_true(again.ai_enabled())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---- the topic menu ---------------------------------------------------------------

func test_each_character_gets_the_topics_their_card_can_answer() -> void:
	var svc := _svc()
	var ids := func(card): return _brain(svc, card).topics().map(func(t): return str(t.id))
	var oda: Array = ids.call(ODA)
	for t in ["job", "rumor", "drink", "vibe", "war", "bye"]:
		assert_true(oda.has(t), "Oda: " + t)
	assert_false(oda.has("recommend"), "she sells no ships")
	assert_true((ids.call(T89) as Array).has("recommend"), "T-89 recommends a ship")
	var sk: Array = ids.call(SKRUGS)
	assert_true(sk.has("buy") and sk.has("sell_ship"), "Skrugs sells speeders and buys ships")
	assert_false(sk.has("drink"))
	assert_false((ids.call(GENERAL) as Array).has("rumor"), "the general shares no rumors")


func test_a_topic_answers_with_real_data() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var svc := _svc()
	var b := _brain(svc, ODA)
	var offered := []
	b.job_offered.connect(func(j): offered.append(j))
	b.begin_visit()
	assert_true(b.say_topic("job"))
	assert_true(b.last_turn.applied.has("offer_job"), "a real job from the board")
	assert_eq(offered.size(), 1)
	var c0 := WorldState.credits
	assert_true(b.say_topic("drink"))
	assert_true(b.last_turn.applied.has("pour_drink"))
	assert_lt(WorldState.credits, c0, "and it is paid for")
	assert_false(b.say_topic("recommend"), "not her topic")
	assert_eq(spy.requests.size(), 0)


func test_a_hint_is_told_in_the_cards_own_words() -> void:
	var svc := _svc()
	var b := _brain(svc, ODA)
	b.begin_visit()
	b.say("What about the Remnant guards?")
	assert_false(b.last_hints.is_empty(), "the words set the hint off")
	var line := ""
	for h in b.card.hints:
		if str(h.event) == "heard_of_rifle":
			line = str(h.line)
	assert_ne(line, "")
	assert_true(str(b.last_turn.say).contains(line.substr(0, 30)), "she tells it: " + str(b.last_turn.say))
	assert_false(str(b.last_turn.say).contains("TELL THEM"), "never the model's instruction")


func test_every_hint_has_an_authored_line() -> void:
	for card in [ODA, T89, GENERAL, SKRUGS, FENCE]:
		var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(card))
		for h in c.get("hints", []):
			assert_ne(str(h.get("line", "")), "", "%s / %s" % [card.get_file(), h.get("event")])


func test_the_dialogue_box_shows_and_presses_topics() -> void:
	var p := DialoguePanel.new()
	add_child_autofree(p)
	var got := []
	p.topic_picked.connect(func(id): got.append(id))
	p.set_topics([{ "id": "job", "label": "Work" }, { "id": "bye", "label": "Goodbye" }])
	assert_eq(p.topic_ids(), ["job", "bye"])
	assert_true(p.press_topic("job"))
	p.set_input_enabled(false)
	assert_false(p.press_topic("bye"), "not while they are answering")
	assert_eq(got, ["job"])
	p.set_topics([])
	assert_eq(p.topic_ids(), [])
	await get_tree().process_frame       # the old buttons are freed


# ---- the whole story with AI off ----------------------------------------------------

func _smuggle_run(content) -> void:
	assert_true(WorldState.accept_job("j_smuggle_run"))
	var drop := WorldState.smuggle_drop()
	assert_true(WorldState.inventory.pick_up(drop))
	var fence: Dictionary = content.get_vendor("fence")
	var item: Dictionary = content.get_item(str(drop.item))
	for i in int(drop.count):
		WorldState.credits += WorldState.inventory.sell(str(drop.item), item, fence)
		WorldState.on_contraband_sold()


func _bounty_run() -> void:
	assert_true(WorldState.accept_job("j_bounty"))
	WorldState.on_bounty_killed()
	WorldState.collect_bounty()


func test_the_story_plays_landing_to_free_play_with_ai_off() -> void:
	var content = CoreContent.new()
	content.load_from()
	var svc := _svc()
	WorldState.new_game(WorldState.STORY)
	assert_eq(Story.chapter(), "land")
	Story.event("landed")
	assert_eq(Story.chapter(), "general")
	_talk(svc, GENERAL, "general")
	Story.event("general_done")          # his verdict (general_post: after turns_offline lines)
	assert_eq(Story.chapter(), "t89")
	assert_true(str(_talk(svc, T89, "t89").get("say", "")).contains("Oda"), "T-89 sends you to Oda")
	assert_eq(Story.chapter(), "meet_oda")
	_talk(svc, ODA, "cantina_owner")
	assert_eq(Story.chapter(), "range", "talking to her is meeting her")
	WorldState.on_range_visited()
	_talk(svc, ODA, "cantina_owner")
	WorldState.on_range_visited()
	assert_eq(Story.chapter(), "smuggle_1")
	var beat := _talk(svc, ODA, "cantina_owner")
	assert_eq(str(beat.get("job", "")), "j_smuggle_run", "the run comes with its job card")
	var remind := str(Story.beat("cantina_owner").get("say", ""))
	assert_true(remind.contains("tower"), "the jetpack hint, to the player: " + remind)
	assert_false(remind.contains("the player"), "not written to a model")
	_smuggle_run(content)
	assert_eq(Story.chapter(), "droid_merchant")
	_talk(svc, ODA, "cantina_owner")
	for i in 3:
		Story.on_droid_delivered()
	assert_eq(Story.chapter(), "bounty")
	_talk(svc, SKRUGS, "skrugs")
	assert_eq(str(_talk(svc, ODA, "cantina_owner").get("job", "")), "j_bounty")
	_bounty_run()
	assert_eq(Story.chapter(), "fleet")
	_talk(svc, ODA, "cantina_owner")
	assert_true(Story.ships_unlocked(), "she unlocks the ships")
	WorldState.on_cruiser_taken("General Test", CruiserHull.data().get("reward", {}), "%s fell.")
	assert_eq(Story.chapter(), "debrief")
	_talk(svc, ODA, "cantina_owner")
	assert_eq(Story.chapter(), "end")
	EndCard.close()
	assert_eq(Story.chapter(), "free")
	_talk(svc, FENCE, "fence")
	_talk(svc, ODA, "cantina_owner")
	assert_eq(spy.requests.size(), 0, "no model was asked anything, start to finish")


# ---- AI on: loading, giving up, plain reasons ----------------------------------------

func test_a_warming_model_is_skipped_and_the_next_turn_uses_it() -> void:
	var cfg := _cfg()
	cfg.set_ai_enabled(true)
	var svc := LLMService.new()
	add_child_autofree(svc)
	var slow := ScriptedProvider.new("warm_a", [{ "text": "{}", "ms_first": 300 }, { "text": "{\"say\": \"Loaded now.\", \"then\": []}" }])
	svc.configure(cfg, [slow])
	svc.warm("warm_a", [{ "role": "user", "content": "hi" }])
	assert_true(svc.loading(), "the model is loading")
	var b := _brain(svc, ODA)
	b.begin_visit()
	b.say("Hello")
	assert_eq(str(b.last_turn.source), "canned", "the turn does not wait for the load")
	var t0 := Time.get_ticks_msec()
	while svc.loading() and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_false(svc.loading(), "the warm-up answered")
	b.say("Hello again")
	t0 = Time.get_ticks_msec()
	while b.busy and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_eq(str(b.last_turn.source), "model", "the next turn tries it again")


func test_a_turn_with_no_first_word_in_time_is_canned_as_slow() -> void:
	var cfg := _cfg()
	cfg.set_ai_enabled(true)
	cfg.set_value("gen/give_up_ms", 250)
	var svc := LLMService.new()
	add_child_autofree(svc)
	svc.configure(cfg, [ScriptedProvider.new("slow_a", [{ "text": "{}", "ms_first": 5000 }])])
	var b := _brain(svc, ODA)
	b.begin_visit()
	b.say("Hello")
	var t0 := Time.get_ticks_msec()
	while b.busy and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_false(b.busy)
	assert_eq(str(b.last_turn.error), "slow")
	assert_eq(str(b.last_turn.source), "canned")
	assert_lt(int(b.last_turn.ms_total), 1500, "the player was not kept waiting")
	assert_true(svc.explain(b.last_turn).contains("next turn"))


func test_failures_in_plain_words() -> void:
	assert_true(LLMService.plain_reason("http 401 {\"type\":\"error\"}").contains("key was refused"))
	assert_true(LLMService.plain_reason("http 404 model").contains("unknown model"))
	assert_true(LLMService.plain_reason("http 429 slow down").contains("rate limited"))
	assert_true(LLMService.plain_reason("http 529 overloaded").contains("provider had an error"))
	assert_true(LLMService.plain_reason("timeout").contains("in time"))
	assert_true(LLMService.plain_reason("connect").contains("could not connect"))
	# The provider's own words, not its JSON (the F10 line used to end mid-JSON).
	var anth := "http 400 {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"`temperature` is deprecated for this model.\"},\"request_id\":\"req_1\"}"
	assert_eq(LLMService.plain_reason(anth), "the provider rejected the request (400: `temperature` is deprecated for this model.)")
	var oll := "http 404 {\"error\":{\"message\":\"model 'qwen3:30b-a3b' not found\",\"type\":\"not_found_error\"}}\n"
	assert_true(LLMService.plain_reason(oll).contains("model 'qwen3:30b-a3b' not found"))
	assert_true(LLMService.plain_reason("http 400 {\"error\":{\"message\":\"cut sho").contains("cut sho"), "a cut-off body still reads")
	var svc := _svc()
	var why := svc.explain({ "fell_back_from": [{ "provider": "local", "reason": "connect" }, { "provider": "cloud", "reason": "http 401 x" }] })
	assert_true(why.contains("local: could not connect"))
	assert_true(why.contains("cloud: the key was refused"))


func test_the_test_button_hears_back_even_with_nothing_to_try() -> void:
	var cfg := _cfg()
	cfg.set_ai_enabled(true)
	cfg.set_value("chain", [])
	var svc := _svc(cfg)
	var got := []
	var id := svc.chat([{ "role": "user", "content": "hi" }], { "force": true })
	svc.finished.connect(func(tid, r): if tid == id: got.append(r))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1, "the result arrives after the caller has its id")
	assert_false(bool(got[0].ok))
	assert_ne(LLMSettingsPanel.test_text(got[0], svc), "")


# ---- the cloud key picks its provider --------------------------------------------------

func test_a_key_picks_its_provider() -> void:
	var c := _cfg()
	assert_true(c.apply_key_preset("cloud", "sk-ant-abc"))
	assert_eq(str(c.profile("cloud").type), "anthropic")
	assert_eq(str(c.profile("cloud").base_url), "https://api.anthropic.com/v1")
	assert_true(c.apply_key_preset("cloud", "sk-or-abc"))
	assert_eq(str(c.profile("cloud").type), "openai_compat")
	assert_true(str(c.profile("cloud").base_url).contains("openrouter"))
	assert_false(c.apply_key_preset("cloud", "gsk_other"), "an unknown key changes nothing")


func test_a_stored_anthropic_key_fixes_the_cloud_profile_on_load() -> void:
	var c := LLMConfig.new()
	c.keys_path = KEYS
	assert_true(c.set_api_key("cloud", "sk-ant-stored-0000"))
	c.user_path = NO_USER
	c.data = {}
	c.load_all()
	assert_eq(str(c.profile("cloud").type), "anthropic", "the key's provider, not the OpenRouter default")
	assert_eq(c.key_mismatch("cloud"), "")
	assert_true(c.usable("cloud"), "on, with a key: auto can reach it")


func test_a_hand_set_profile_is_kept_and_a_mismatch_is_named() -> void:
	var path := "user://test_ai_off_hand.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "profiles": { "cloud": { "base_url": "https://openrouter.ai/api/v1" } } }))
	f.close()
	var c := LLMConfig.new()
	c.keys_path = KEYS
	c.set_api_key("cloud", "sk-ant-stored-0000")
	c.user_path = path
	c.load_all()
	assert_true(str(c.profile("cloud").base_url).contains("openrouter"), "the player's own choice stays")
	assert_true(c.key_mismatch("cloud").contains("api.anthropic.com"), "but the report says the key does not fit")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---- the Anthropic path over real HTTP ---------------------------------------------------

func _mock_up() -> bool:
	if _mock_pid > 0:
		return true
	var out := []
	if OS.execute("python3", ["-c", "print(1)"], out) != 0:
		return false
	_mock_pid = OS.create_process("python3", ["-I", ProjectSettings.globalize_path(MOCK), "--port", str(MOCK_PORT)])
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		var tcp := StreamPeerTCP.new()
		if tcp.connect_to_host("127.0.0.1", MOCK_PORT) == OK:
			while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
				tcp.poll()
				OS.delay_msec(10)
			if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				tcp.disconnect_from_host()
				return true
		OS.delay_msec(100)
	return false


## A cloud-only service pointed at the mock's `path` with `key`.
func _cloud(path: String, key: String) -> LLMService:
	var c := _cfg()
	c.set_ai_enabled(true)
	c.set_api_key("cloud", key)
	c.set_value("profiles/cloud/type", "anthropic")
	c.set_value("profiles/cloud/base_url", "http://127.0.0.1:%d/%s/v1" % [MOCK_PORT, path])
	c.set_value("gen/first_token_timeout_ms/cloud", 600)
	c.set_value("chain", ["cloud"])
	var svc := LLMService.new()
	add_child_autofree(svc)
	svc.configure(c)
	svc.set_mode("cloud")
	svc._recheck_left = 999.0
	return svc


func _turn(svc: LLMService) -> Dictionary:
	var b := _brain(svc, ODA)
	b.begin_visit()
	b.say("Is the cloud awake?")
	var t0 := Time.get_ticks_msec()
	while b.busy and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	return b.last_turn


func test_anthropic_streams_a_reply_end_to_end() -> void:
	if not _mock_up():
		pending("python3 not available")
		return
	var t: Dictionary = await _turn(_cloud("anth", GOOD_KEY))
	assert_eq(str(t.provider), "cloud")
	assert_eq(str(t.source), "model", "the forced tool's input parsed as her reply: " + str(t.error))
	assert_true(str(t.say).contains("Is the cloud awake?"), "the player's words reached it")


func test_anthropic_failures_are_named() -> void:
	if not _mock_up():
		pending("python3 not available")
		return
	for c in [["anth", "sk-ant-wrong-key-0000", "key was refused"], ["a404", GOOD_KEY, "unknown model"],
			["a429", GOOD_KEY, "rate limited"], ["hang", GOOD_KEY, "in time"]]:
		var svc := _cloud(c[0], c[1])
		var t: Dictionary = await _turn(svc)
		assert_eq(str(t.source), "canned", c[0])
		var why := svc.explain(t)
		assert_true(why.contains(c[2]), "%s: %s" % [c[0], why])
		var test_line := LLMSettingsPanel.test_text({ "ok": false, "fell_back_from": t.fell_back_from, "error": t.error }, svc)
		assert_true(test_line.contains(c[2]), "the Test button says it too: " + test_line)


## AI off, a topic picked from the menu is off it for the rest of the talk, and
## back on it the next time you talk.
func test_a_picked_topic_leaves_the_menu_until_the_next_talk() -> void:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	t._build_bar([], "")
	var bar: ConversationHost = t.bar
	bar.llm.mode = "auto"
	bar.llm.config = _cfg()
	assert_false(bar.llm.ai_on(), "the shipped default: AI characters off")
	var shown := func() -> Array:
		return bar.panel._topics.get_children().filter(func(b): return not b.is_queued_for_deletion()).map(func(b): return str(b.name))
	bar.start_talk()
	var first: Array = shown.call()
	assert_true(first.has("rumor"), "Oda's menu has rumours: %s" % [first])
	bar.brain.busy = false
	assert_true(bar.player_picks("rumor"))
	assert_false(shown.call().has("rumor"), "picked: off the menu")
	assert_eq(shown.call().size(), first.size() - 1, "the rest stay")
	bar.end_talk()
	bar.brain.busy = false
	bar.start_talk()
	assert_eq(shown.call(), first, "a new talk: the whole menu again")
	bar.end_talk()
