extends GutTest
## Issue #200: every save is a story save or a freeplay save, picked on New Game
## and kept in the save.

const WeaponHolder := preload("res://src/systems/combat/weapon_holder.gd")


func after_each() -> void:
	WorldState.reset()


func test_a_story_save_starts_neutral_with_the_pistol_only() -> void:
	WorldState.new_game(WorldState.STORY)
	assert_true(WorldState.story_mode())
	assert_eq(Story.chapter(), Story.chapter_ids()[0])
	for f in WorldState.FACTIONS:
		assert_eq(int(WorldState.standing[f]), 0, f + " is neutral")
	assert_true(WorldState.weapon_allowed("pistol_blaster"))
	assert_false(WorldState.weapon_allowed("rifle_blaster"))
	assert_false(WorldState.weapon_allowed("energy_blade"))
	WorldState.set_flag("weapon_rifle_blaster")
	assert_true(WorldState.weapon_allowed("rifle_blaster"), "a flag hands it over")


func test_a_freeplay_save_is_the_free_chapter_with_everything() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	assert_false(WorldState.story_mode())
	assert_eq(Story.chapter(), "free")
	assert_true(Story.ships_unlocked())
	assert_false(Story.remnant_hostile(), "the garrison is still in town")
	assert_eq(WorldState.standing, WorldState.DEFAULT_STANDING)
	for id in ["pistol_blaster", "rifle_blaster", "energy_blade"]:
		assert_true(WorldState.weapon_allowed(id), id)


func test_the_mode_survives_save_and_load() -> void:
	WorldState.new_game(WorldState.STORY)
	var d := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(d)
	assert_true(WorldState.story_mode())
	assert_eq(int(WorldState.standing.locals), 0)
	d.erase("mode")
	WorldState.from_save(d)
	assert_false(WorldState.story_mode(), "an old save is freeplay")


func test_a_locked_weapon_is_never_drawn() -> void:
	var h := WeaponHolder.new(["pistol_blaster", "energy_blade", "rifle_blaster"])
	h.can_draw = func(id): return id == "pistol_blaster"
	h.request_slot(3)
	assert_eq(h.pending, "", "the rifle stays holstered")
	h.cycle(1)
	assert_eq(h.pending, "pistol_blaster", "the wheel skips to what it may draw")


func test_a_story_save_wears_only_the_smugglers_pieces() -> void:
	WorldState.new_game(WorldState.STORY)
	var o := PlayerOutfit.sanitize({ "head": "player", "torso": "guard:gunmetal" })
	assert_false(o.has("torso"), "no other character's pieces")
	assert_eq(o.get("head"), "player")
	WorldState.new_game(WorldState.FREEPLAY)
	WorldState.inventory.add("quantonium_armour")      # free roam opens the guard's pieces with its armour
	assert_eq(PlayerOutfit.sanitize({ "torso": "guard:gunmetal" }).get("torso"), "guard:gunmetal")
