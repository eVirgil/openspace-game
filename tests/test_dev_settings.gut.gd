extends GutTest
## F11 demo settings: the time-of-day blend, and the panel writing to the world.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	GameFlow.reset()


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	NpcBody.show_debug = false


func after_all() -> void:
	WorldState.reset()


func _town() -> Node:
	var scene = TownDemo.new()
	scene.use_look = false
	scene.with_npcs = false
	add_child_autofree(scene)
	return scene


func test_blend_mixes_numbers_and_colors() -> void:
	var a := { "x": 0.0, "c": "#000000", "on": true, "sub": { "y": 10 } }
	var b := { "x": 4.0, "c": "#ffffff", "on": false, "sub": { "y": 20 } }
	var m: Dictionary = LookEnvironment.blend(a, b, 0.25)
	assert_almost_eq(float(m.x), 1.0, 0.001)
	assert_almost_eq(Color.html(m.c).r, 0.25, 0.01)
	assert_true(m.on, "bools hold the first value until halfway")
	assert_almost_eq(float(m.sub.y), 12.5, 0.001)
	assert_false(LookEnvironment.blend(a, b, 0.75).on)


func test_hours_key_real_presets_in_order() -> void:
	var data := LookEnvironment.load_presets()
	var last := -1.0
	for e in data.get("hours", []):
		assert_true(data.presets.has(str(e.preset)), "hour key names a preset: " + str(e.preset))
		assert_gt(float(e.hour), last, "hour keys ascend")
		last = float(e.hour)


func test_apply_hour_blends_and_picks_nearest_preset() -> void:
	var look := LookEnvironment.new()
	add_child_autofree(look)
	var k := look.keys_at_hour(10.0)
	assert_eq(k.a, "golden")
	assert_eq(k.b, "noon")
	look.apply_hour(12.0)
	assert_eq(look.current, "noon")
	look.apply_hour(8.2)
	assert_eq(look.current, "golden")
	var golden_e := float(look.presets.golden.sun.energy)
	var noon_e := float(look.presets.noon.sun.energy)
	look.apply_hour(10.25)
	assert_between(look.sun.light_energy, minf(golden_e, noon_e), maxf(golden_e, noon_e))
	look.apply_hour(2.0)
	assert_eq(look.current, "dusk", "before the first key holds the first preset")
	look.apply("noon")
	assert_eq(look.hour, -1.0, "a plain preset clears the hour")


func test_panel_opens_pauses_and_closes() -> void:
	var town = _town()
	var p: DevSettingsPanel = town.dev_settings
	assert_not_null(p, "the town builds the F11 panel")
	assert_false(p.visible)
	p.toggle()
	assert_true(p.visible)
	assert_true(get_tree().paused, "the game pauses under the panel")
	p.toggle()
	assert_false(p.visible)
	assert_false(get_tree().paused)


func test_teleport_moves_player_to_marker() -> void:
	var town = _town()
	assert_true(town.dev_settings.teleport("cantina_door"))
	assert_almost_eq(town._player.global_position.x, town.town.marker_pos("cantina_door").x, 0.01)
	assert_false(town.dev_settings.teleport("no_such_marker"))


func test_known_flags_cover_content_conditions() -> void:
	var town = _town()
	WorldState.set_flag("my_custom")
	var flags: Array = town.dev_settings.known_flags()
	assert_true(flags.has("my_custom"), "flags already set are listed")
	assert_true(flags.has("remnant_patrol_beaten"), "flags rumors ask about are listed")


func test_pages_are_built_on_first_open_only() -> void:
	var town = _town()
	var p: DevSettingsPanel = town.dev_settings
	assert_false(p.tabs_built, "issue #121: the pages wait until the panel is opened")
	assert_eq(p.tabs.get_tab_count(), 0)
	p.open()
	assert_true(p.tabs_built)
	assert_eq(p.tabs.get_tab_count(), 6, "six pages once it opens")
	var titles: Array = []
	for i in p.tabs.get_tab_count():
		titles.append(p.tabs.get_tab_title(i))
	assert_eq(titles, ["Map", "Ledger", "Game", "Player", "Standing", "Options"])
	p.close()
	p.open_tab("LLM")
	assert_eq(p.tabs.get_tab_title(p.tabs.current_tab), "Options", "F10 lands on the AI brain, under Options")
	p.close()


func test_story_save_greys_out_the_cheats() -> void:
	var town = _town()
	var p: DevSettingsPanel = town.dev_settings
	WorldState.new_game(WorldState.STORY)
	p.open()
	assert_gt(p._cheats.size(), 0)
	for c in p._cheats:
		var live: bool = not c.disabled if c is BaseButton else bool(c.get("editable"))
		assert_false(live, "a story save locks " + str(c))
	for n in p._story_notes:
		assert_true(n.visible, "each page says why")
	assert_false(p.teleport("cantina_door"), "no teleport in a story save")
	p.close()
	WorldState.new_game(WorldState.FREEPLAY)
	p.open()
	for c in p._cheats:
		var live: bool = not c.disabled if c is BaseButton else bool(c.get("editable"))
		assert_true(live, "free roam gives it back: " + str(c))
	for n in p._story_notes:
		assert_false(n.visible)
	p.close()


func test_story_skip_asks_first_and_only_goes_ahead() -> void:
	var town = _town()
	var p: DevSettingsPanel = town.dev_settings
	WorldState.new_game(WorldState.STORY)
	p.open()
	var start := Story.chapter()
	assert_false(p.skip_chapter(start), "not to where you already are")
	assert_true(p.skip_chapter("range"))
	assert_true(p.skip_confirm.visible, "the stuck warning comes up")
	assert_string_contains(p.skip_confirm.dialog_text, "ask the interactive NPCs")
	assert_eq(Story.chapter(), start, "nothing moves until Yes")
	p.skip_confirm.hide()
	assert_eq(Story.chapter(), start, "No leaves the story where it was")
	p.skip_chapter("range")
	p.skip_confirm.confirmed.emit()
	assert_eq(Story.chapter(), "range", "Yes skips ahead")
	assert_false(p.skip_chapter("meet_oda"), "never back")
	p.close()


func test_new_story_game_drops_free_roam_tweaks() -> void:
	var town = _town()
	GameFlow.set_space_dogfight(false)
	NpcBody.show_debug = true
	town.dev_settings.new_game(WorldState.STORY, false)
	assert_true(GameFlow.space_dogfight(), "the fleet always meets you in orbit")
	assert_false(NpcBody.show_debug)


func test_new_free_roam_game_packs_the_rifle_and_blade_and_lands_without_the_general() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	assert_true(WorldState.inventory.has("rifle_blaster"), "the rifle is in the backpack")
	assert_true(WorldState.inventory.has("energy_blade"), "so is the blade")
	assert_true(WorldState.opening_due(), "it opens with the landing")
	assert_ne(GeneralPost.station(), "pit", "no general in the pit (issue #310: he is in the barracks yard)")
	WorldState.set_flag(WorldState.FREE_OPENING, false)    # out of the ship (ShipPilot.exit_ship)
	assert_false(WorldState.opening_due(), "the landing plays once")
	WorldState.new_game(WorldState.STORY)
	assert_false(WorldState.inventory.has("rifle_blaster"), "a story save starts with the pistol only")
	assert_true(WorldState.opening_due())
