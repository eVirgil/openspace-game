extends GutTest
## The objective pointer and the job log (Objective, ObjectiveHud, the job log on
## the inventory screen). Walks the story and checks the pointer names the right
## thing and the right place at every step, that the log lists what is on, and
## that reading either never rolls a job or moves the story on.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")

var content


func before_each() -> void:
	WorldState.reset()
	GameFlow.reset()
	content = CoreContent.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


func _target() -> String:
	return str(Objective.current().get("target", ""))


func _text() -> String:
	return str(Objective.current().get("text", ""))


func _log_text() -> String:
	return "\n".join(Objective.log_entries().map(func(e): return str(e.title) + " " + str(e.text)))


func test_every_chapter_has_an_objective_and_a_target() -> void:
	var cfg := Objective.cfg()
	assert_false(cfg.is_empty(), "the lines are in the story data")
	for id in Story.chapter_ids():
		var o: Dictionary = cfg.chapters.get(id, {})
		assert_ne(str(o.get("text", "")), "", "chapter %s says what to do" % id)
		assert_ne(str(o.get("target", "")), "", "chapter %s points somewhere" % id)


func test_a_new_game_points_at_oda() -> void:
	assert_eq(_target(), "npc:cantina_owner")
	assert_string_contains(_text(), "Oda")


func test_the_pointer_follows_the_story() -> void:
	Story.beat("cantina_owner")                # meets Oda, she tells the range
	assert_eq(Story.chapter(), "range")
	assert_eq(_target(), "range", "off to the range")
	WorldState.on_range_visited()
	assert_eq(Story.chapter(), "remote")
	assert_eq(_target(), "npc:cantina_owner", "a chapter Oda has not told yet: go and see her")
	Story.beat("cantina_owner")
	assert_eq(_target(), "remote", "then the sparring droid")
	Story.skip_to("fleet")
	WorldState.story.told = true
	assert_eq(_target(), "cruiser:bay", "the fleet: first land in the cruiser's bay")


## The fleet chapter is three steps, each with its own waypoint: land in the bay,
## reach the stairs, kill the general; the log lists them and ticks them off.
func test_the_fleet_is_three_steps_with_their_own_waypoints() -> void:
	Story.skip_to("fleet")
	assert_eq(_target(), "npc:cantina_owner", "untold: go and see Oda")
	Story.beat("cantina_owner")
	assert_eq(_target(), "cruiser:bay", "first land in its bay")
	assert_string_contains(_text(), "bay")
	assert_true(Story.event("cruiser_landed"), "landing is a step")
	assert_eq(Story.chapter(), "fleet", "a step is not the chapter")
	assert_eq(_target(), "cruiser:stairs", "then find the stairs")
	assert_string_contains(_text(), "stairs")
	assert_true(Story.event("cruiser_infiltrated"))
	assert_eq(_target(), "cruiser:general", "then the general")
	var who := Story.cruiser_general_name()
	assert_ne(who, "", "the general has a name before you meet him")
	assert_string_contains(_text(), who, "by name")
	assert_string_contains(_log_text(), "DESTROY THE FLEET", "the log names the quest")
	assert_string_contains(_log_text(), Objective.line("step_done") + "Land", "and ticks the steps done")
	assert_string_contains(_log_text(), Objective.line("step_open") + "Kill")
	assert_false(Story.event("cruiser_landed"), "a step done is done")
	WorldState.on_cruiser_taken(who, {})
	assert_eq(Story.chapter(), "debrief", "the general ends the chapter as before")


func test_reaching_the_stairs_counts_the_landing_too() -> void:
	Story.skip_to("fleet")
	Story.beat("cantina_owner")
	Story.event("cruiser_infiltrated")
	assert_eq(_target(), "cruiser:general")
	assert_true(WorldState.has_flag("fleet_land"))


func test_the_steps_survive_a_save() -> void:
	Story.skip_to("fleet")
	Story.beat("cantina_owner")
	Story.event("cruiser_landed")
	WorldState.from_save(WorldState.to_save())
	assert_eq(_target(), "cruiser:stairs")


func test_a_smuggling_run_points_at_the_drop_area_then_the_fence() -> void:
	Story.skip_to("smuggle_1")
	Story.beat("cantina_owner")
	assert_eq(_target(), "npc:cantina_owner", "the job is on offer: ask Oda")
	assert_true(WorldState.accept_job("j_smuggle_run"))
	var drop := WorldState.smuggle_drop()
	assert_eq(_target(), "drop:" + str(drop.marker), "near the drop (its area's marker until it is placed)")
	assert_string_contains(_text(), str(WorldState.smuggle.hint))
	assert_string_contains(_log_text(), WorldState.smuggle_goods_text(), "the log says what the goods are")
	assert_true(WorldState.inventory.pick_up(drop))
	assert_eq(_target(), "marker:" + str(content.get_vendor("fence").marker), "then the fence's stall")
	assert_string_contains(_log_text(), Objective.line("log_carry"))


func test_a_bounty_points_at_its_outpost_then_the_fence() -> void:
	Story.skip_to("bounty")
	Story.beat("cantina_owner")
	assert_true(WorldState.accept_job("j_bounty"))
	var b := WorldState.bounty
	assert_eq(_target(), "outpost:" + str(b.outpost))
	assert_string_contains(_text(), str(b.name))
	assert_string_contains(_log_text(), str(b.crime), "the log keeps the officer's crime")
	WorldState.on_bounty_killed()
	assert_eq(_target(), "marker:" + str(content.get_vendor("fence").marker))
	assert_string_contains(_log_text(), str(int(b.pay)))


func test_reading_never_rolls_a_job_or_moves_the_story() -> void:
	Story.skip_to("smuggle_1")
	var before := [WorldState.smuggle.duplicate(true), WorldState.bounty.duplicate(true), WorldState.story.duplicate(true)]
	for i in 3:
		Objective.current()
		Objective.log_entries()
	assert_eq([WorldState.smuggle, WorldState.bounty, WorldState.story], before)


func test_taken_board_jobs_are_in_the_log() -> void:
	assert_true(WorldState.accept_job("j_range_bet"))
	assert_string_contains(_log_text(), str(WorldState.job("j_range_bet").title).to_upper())


func test_the_free_chapter_log_is_never_empty() -> void:
	Story.skip_to("free")
	assert_false(Objective.log_entries().is_empty())
	assert_ne(Objective.tally(), "")


func test_the_hud_resolves_markers_and_draws_a_line() -> void:
	var demo := Node3D.new()
	demo.set_script(load("res://scenes/town_demo.gd"))
	var town := TownLayout.new()
	town.load_town("port_town")
	demo.town = town
	var hud := ObjectiveHud.new()
	hud.demo = demo
	add_child_autofree(hud)
	assert_eq(hud.where("marker:vendor_3"), town.marker_pos("vendor_3"))
	assert_eq(hud.where("npc:cantina_owner"), town.marker_pos("cantina_owner"), "no body yet: her marker")
	assert_eq(hud.where("marker:nowhere"), Vector3.INF)
	assert_eq(hud.where(""), Vector3.INF)
	hud.refresh()
	assert_string_contains(hud.label.text, "Oda")
	demo.free()


func test_the_inventory_panel_shows_the_job_log() -> void:
	var panel := InventoryPanel.new()
	panel.content = content
	add_child_autofree(panel)
	panel.refresh()
	assert_eq(panel.job_rows[0], Objective.line("log_story"))
	assert_true(panel.job_rows.size() >= 3, "story title, its line and the tally")
	assert_eq(panel.job_rows[-1], Objective.tally())


func test_the_ledger_picks_which_job_is_the_waypoint() -> void:
	Story.skip_to("bounty")
	Story.beat("cantina_owner")
	assert_true(WorldState.accept_job("j_bounty"))
	var b := WorldState.bounty
	assert_eq(Objective.current_key(), "bounty", "unpicked: the most urgent")
	assert_true(Objective.can_pin("story"))
	assert_true(Objective.pin("story"))
	assert_eq(Objective.current_key(), "story", "the story's objective is the waypoint now")
	assert_eq(_target(), str(Objective.of("story").target))
	WorldState.from_save(WorldState.to_save())
	assert_eq(Objective.current_key(), "story", "saved")
	assert_false(Objective.pin("story"), "the same button again hands it back")
	assert_eq(_target(), "outpost:" + str(b.outpost))
	Objective.pin("story")
	GlobeMap.set_waypoint(GlobeMap.spot_pin(Vector2(10, 20)), GameFlow.current_planet_id())
	assert_eq(WorldState.objective_pin, "", "one pointer at a time: the map's wins")
	assert_eq(Objective.current_key(), "map")


func test_the_ledger_lights_the_card_the_pointer_is_on() -> void:
	Story.skip_to("bounty")
	Story.beat("cantina_owner")
	assert_true(WorldState.accept_job("j_bounty"))
	var panel := InventoryPanel.new()
	panel.content = content
	add_child_autofree(panel)
	panel.refresh()
	assert_true(panel.point_buttons.has("story") and panel.point_buttons.has("bounty"))
	assert_true(panel.point_buttons.bounty.button_pressed, "the most urgent is lit")
	panel.point_buttons.story.pressed.emit()
	assert_eq(WorldState.objective_pin, "story")
	assert_true(panel.point_buttons.story.button_pressed)
	assert_false(panel.point_buttons.bounty.button_pressed)
