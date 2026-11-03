extends GutTest
## A story save and a free roam save side by side (SaveSlots): each its own file
## and outfit, switched in F11 > Game > Saves, and nothing of one leaks into the
## other. Runs in its own folder, never the player's saves.

const ROOT := "user://test_save_slots/"


class FakeDemo:
	var bar: ConversationHost


var demo: FakeDemo
var panel: DevSettingsPanel
var _loaded_once := false


func before_each() -> void:
	_clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	SaveSlots.root = ROOT
	SaveSlots.active = ""
	PlayerOutfit.save_path = ""
	_loaded_once = ConversationHost._loaded_once
	WorldState.reset()
	GameFlow.reset()


func after_each() -> void:
	if demo != null and demo.bar != null:
		demo.bar.free()
	demo = null
	SaveSlots.root = "user://"
	SaveSlots.active = ""
	ConversationHost._loaded_once = _loaded_once
	WorldState.reset()
	GameFlow.reset()
	NpcBody.show_debug = false
	_clear()


func _clear() -> void:
	var d := DirAccess.open(ROOT)
	if d == null:
		return
	for sub in ["settings", ""]:
		var dd := DirAccess.open(ROOT + sub)
		if dd == null:
			continue
		for f in dd.get_files():
			dd.remove(f)
	d.remove("settings")


## A town that saves to disk, as the game's does: a real host on the slot's file.
func _playing(mode: String) -> void:
	SaveSlots.start(mode, NameBook.new())
	_host()


func _host() -> void:
	if demo != null and demo.bar != null:
		demo.bar.free()
	demo = FakeDemo.new()
	demo.bar = ConversationHost.new()
	demo.bar.save_path = SaveSlots.current_path()
	if panel == null:
		panel = DevSettingsPanel.new()
		add_child_autofree(panel)
	panel.demo = demo


## What a slot's file holds in its world block.
func _world(mode: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SaveSlots.path(mode)))
	return d.world if d is Dictionary else {}


func test_an_old_save_is_copied_into_its_slot_and_left_in_place() -> void:
	WorldState.new_game(WorldState.STORY)
	WorldState.credits = 321
	var f := FileAccess.open(ROOT + SaveSlots.LEGACY, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "version": 3, "world": WorldState.to_save() }))
	f.close()
	WorldState.reset()
	assert_eq(SaveSlots.current(), WorldState.STORY, "the old save was a story save")
	assert_true(SaveSlots.exists(WorldState.STORY))
	assert_false(SaveSlots.exists(WorldState.FREEPLAY), "no free roam save made up")
	assert_eq(int(_world(WorldState.STORY).credits), 321)
	assert_true(FileAccess.file_exists(ROOT + SaveSlots.LEGACY), "the old file stays for older builds")


func test_the_last_save_played_opens_next_launch() -> void:
	_playing(WorldState.FREEPLAY)
	panel.switch_save(WorldState.STORY, false)
	SaveSlots.active = ""            # a new launch
	assert_eq(SaveSlots.current(), WorldState.STORY)


func test_switching_to_a_slot_with_no_save_starts_a_clean_game_there() -> void:
	_playing(WorldState.FREEPLAY)
	WorldState.credits = 9999
	WorldState.set_flag("free_only")
	WorldState.inventory.add("jetpack")
	WorldState.hangar = "courier"
	WorldState.kept_ships = [{ "key": "kept_1", "ship": "courier" }]
	WorldState.standing["locals"] = 90
	WorldState.names._write("Zed Freeman", "test:free_only", "person")
	panel.switch_save(WorldState.STORY, false)
	assert_true(WorldState.story_mode())
	assert_eq(WorldState.credits, 60)
	assert_false(WorldState.has_flag("free_only"))
	assert_false(WorldState.inventory.has("jetpack"))
	assert_eq(WorldState.hangar, "")
	assert_true(WorldState.kept_ships.is_empty())
	assert_eq(int(WorldState.standing.locals), 0, "a story starts neutral")
	assert_false(WorldState.names.by_key.has("test:free_only"), "the free roam names stay there")
	assert_true(SaveSlots.exists(WorldState.STORY), "the new story game is on disk")
	var free := _world(WorldState.FREEPLAY)
	assert_eq(int(free.credits), 9999, "the free roam game was saved on the way out")
	assert_true(free.flags.has("free_only"))
	assert_false(demo.bar.autosave, "the town being left saves nothing more")


func test_each_save_comes_back_as_it_was_left() -> void:
	_playing(WorldState.FREEPLAY)
	WorldState.credits = 777
	WorldState.set_flag("free_only")
	panel.switch_save(WorldState.STORY, false)
	_host()
	WorldState.credits = 5
	WorldState.set_flag("story_only")
	Story.skip_to("meet_oda")
	panel.switch_save(WorldState.FREEPLAY, false)
	assert_false(WorldState.story_mode())
	assert_eq(WorldState.credits, 777)
	assert_true(WorldState.has_flag("free_only"))
	assert_false(WorldState.has_flag("story_only"))
	_host()
	panel.switch_save(WorldState.STORY, false)
	assert_true(WorldState.story_mode())
	assert_eq(WorldState.credits, 5)
	assert_eq(Story.chapter(), "meet_oda")
	assert_true(WorldState.has_flag("story_only"))
	assert_false(WorldState.has_flag("free_only"))


func test_a_new_game_never_touches_the_other_save() -> void:
	_playing(WorldState.FREEPLAY)
	WorldState.credits = 4242
	panel.switch_save(WorldState.STORY, false)
	var before := FileAccess.get_file_as_string(SaveSlots.path(WorldState.FREEPLAY))
	_host()
	WorldState.credits = 1
	panel.new_game(WorldState.STORY, false)
	assert_eq(WorldState.credits, 60, "the story starts over")
	assert_eq(FileAccess.get_file_as_string(SaveSlots.path(WorldState.FREEPLAY)), before, "free roam untouched")
	assert_eq(int(_world(WorldState.STORY).credits), 60, "the story's own slot holds the new game")


func test_a_new_game_in_the_other_mode_keeps_this_one_and_uses_that_ones_names() -> void:
	_playing(WorldState.STORY)
	WorldState.names._write("Ana Storyfolk", "test:story", "person")
	panel.switch_save(WorldState.FREEPLAY, false)
	WorldState.names._write("Zed Freeman", "test:free", "person")
	_host()
	panel.new_game(WorldState.STORY, false)
	assert_true(WorldState.story_mode())
	assert_true(WorldState.names.by_key.has("test:story"), "the story save's names are kept")
	assert_false(WorldState.names.by_key.has("test:free"), "not free roam's")
	assert_true(_world(WorldState.FREEPLAY).names.names.has("test:free"), "and free roam was saved first")


func test_what_a_run_keeps_goes_back_to_a_launch_on_a_switch() -> void:
	_playing(WorldState.FREEPLAY)
	GameFlow.planet_id = "grit_station"
	GameFlow.flown_ship = "courier"
	GameFlow.flown_key = "kept_1"
	GameFlow.resumed = true
	GameFlow.set_space_dogfight(false)
	NpcBody.show_debug = true
	PlanetGen.layout_override = { "home": "dense" }
	ShipSalesman.greeted = true
	panel.switch_save(WorldState.STORY, false)
	assert_eq(GameFlow.planet_id, "", "opens on its own save's planet")
	assert_eq(GameFlow.flown_ship, "")
	assert_eq(GameFlow.flown_key, "")
	assert_false(GameFlow.resumed, "the town reads the other save's spot")
	assert_true(GameFlow.space_dogfight(), "free roam's tweaks stay in free roam")
	assert_false(NpcBody.show_debug)
	assert_true(PlanetGen.layout_override.is_empty())
	assert_false(ShipSalesman.greeted, "T-89 says hello as on a launch")


func test_each_save_has_its_own_outfit() -> void:
	_playing(WorldState.FREEPLAY)
	var mix := { "torso": "player:rust" }
	PlayerOutfit.save_outfit(mix)
	var free_file := PlayerOutfit.path()
	panel.switch_save(WorldState.STORY, false)
	assert_ne(PlayerOutfit.path(), free_file)
	assert_eq(PlayerOutfit.load_outfit(), {}, "the story save wears its own")
	PlayerOutfit.save_outfit({})
	_host()
	panel.switch_save(WorldState.FREEPLAY, false)
	assert_eq(PlayerOutfit.path(), free_file)
	assert_eq(PlayerOutfit.load_outfit(), PlayerOutfit.sanitize(mix), "dressing in story left free roam's outfit alone")


func test_a_first_launch_pick_makes_no_save_for_the_other_mode() -> void:
	SaveSlots.boot()
	_host()
	demo.bar.fresh = true            # no save: the New Game menu is up
	panel.new_game(WorldState.STORY, false)
	assert_true(SaveSlots.exists(WorldState.STORY))
	assert_false(SaveSlots.exists(WorldState.FREEPLAY))


func test_a_town_that_does_not_save_writes_nothing() -> void:
	_playing(WorldState.FREEPLAY)
	var free_before := FileAccess.get_file_as_string(SaveSlots.path(WorldState.FREEPLAY))
	demo.bar.autosave = false        # a test's or a trace's town
	panel.switch_save(WorldState.STORY, false)
	assert_false(SaveSlots.exists(WorldState.STORY))
	assert_eq(FileAccess.get_file_as_string(SaveSlots.path(WorldState.FREEPLAY)), free_before)
	assert_true(WorldState.story_mode(), "the state still switches")
