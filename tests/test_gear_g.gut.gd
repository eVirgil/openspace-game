extends GutTest
## [G] puts on and takes off the jetpack and the armour (a menu when you own both),
## and new equipment or a weapon toasts the key to press.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var content
var gear: GearController
var player


class FakePlayer extends CharacterBody3D:
	var max_health := 100
	var health = preload("res://src/systems/combat/health.gd").new(100)
	var jetpack
	var piloting := false
	var locked := false


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)
	content = CoreContent.new()
	content.load_from()
	player = FakePlayer.new()
	add_child_autofree(player)
	gear = GearController.new()
	gear.content = content
	gear.player = player
	gear.labels = ItemKit._read_json(GearController.LABELS_PATH).get("labels", {})
	gear.hud = GearHud.new()
	gear.menu = DroidMenu.new()
	add_child_autofree(gear.hud)
	add_child_autofree(gear.menu)
	WorldState.inventory.add("jetpack")
	WorldState.inventory.add("quantonium_armour")


func after_each() -> void:
	gear.free()
	WorldState.reset()


func test_g_with_only_the_armour_wears_and_removes_it() -> void:
	WorldState.inventory.remove("jetpack")
	assert_eq(gear.toggle_gear(), "attached")
	assert_eq(WorldState.inventory.in_slot("armour"), "quantonium_armour")
	assert_eq(player.health.max_hp, 300, "three times the health")
	assert_string_contains(gear.hud.toast_label.text, "off", "says how to take it off")
	assert_eq(gear.toggle_gear(), "detached")
	assert_eq(player.health.max_hp, 100)


func test_g_with_only_the_jetpack_is_as_before() -> void:
	WorldState.inventory.remove("quantonium_armour")
	assert_eq(gear.toggle_gear(), "attached")
	assert_eq(WorldState.inventory.in_slot("back"), "jetpack")
	assert_eq(gear.toggle_gear(), "detached")


func test_g_with_nothing_to_wear_says_so() -> void:
	WorldState.inventory.remove("jetpack")
	WorldState.inventory.remove("quantonium_armour")
	assert_eq(gear.toggle_gear(), "")
	assert_eq(gear.hud.toast_label.text, "No gear to put on")


func test_g_with_both_opens_a_menu_to_put_on_or_take_off_each() -> void:
	assert_eq(gear.toggle_gear(), "menu")
	assert_true(gear.menu.is_open())
	assert_true(player.locked, "you stand still while you choose")
	assert_eq(gear.menu.rows.size(), 2)
	assert_string_contains(str(gear.menu.rows[0]), "Put on")
	assert_string_contains(str(gear.menu.rows[0]), "Jetpack")
	assert_string_contains(str(gear.menu.rows[1]), "Quantonium armour")
	gear.menu.choose("quantonium_armour")
	assert_false(player.locked)
	assert_eq(WorldState.inventory.in_slot("armour"), "quantonium_armour")
	assert_eq(WorldState.inventory.in_slot("back"), "", "the jetpack stays in the pack")
	# Now the rows read Take off for what is worn.
	assert_eq(gear.toggle_gear(), "menu")
	assert_string_contains(str(gear.menu.rows[1]), "Take off")
	gear.menu.choose("quantonium_armour")
	assert_eq(WorldState.inventory.in_slot("armour"), "")


func test_walking_away_from_the_menu_changes_nothing() -> void:
	gear.toggle_gear()
	gear.menu.choose("")
	assert_false(player.locked)
	assert_eq(WorldState.inventory.in_slot("armour"), "")
	assert_eq(WorldState.inventory.in_slot("back"), "")


func test_armour_from_the_fence_toasts_to_press_g() -> void:
	WorldState.inventory.remove("quantonium_armour")
	WorldState.credits = 1000
	WorldState.bump("bounties_paid")
	assert_eq(gear.buy_offer("quantonium_armour"), "bought")
	assert_eq(WorldState.inventory.in_slot("armour"), "", "not worn until you say")
	gear.hud._process(10.0)
	assert_string_contains(gear.hud.toast_label.text, "New equipment")
	assert_string_contains(gear.hud.toast_label.text, "[G]")


func test_a_weapon_pickup_toasts_how_to_change_weapons() -> void:
	gear._tips_for("rifle_blaster")
	assert_string_contains(gear.hud.toast_label.text, "[Tab]")
	assert_string_contains(gear.hud.toast_label.text, "press & hold to see all weapons")


func test_tips_wait_for_the_pickup_toast_and_a_new_toast_drops_them() -> void:
	gear.hud.toast("Picked up: Rifle blaster", 4.0)
	gear._tips_for("rifle_blaster")
	assert_eq(gear.hud.toast_label.text, "Picked up: Rifle blaster")
	gear.hud._process(4.1)
	assert_string_contains(gear.hud.toast_label.text, "[Tab]")
	gear.hud.toast("Picked up: Food", 4.0)
	gear._tips_for("rifle_blaster")
	gear.hud.toast("Sold something", 3.0)
	gear.hud._process(3.1)
	assert_false(gear.hud.toast_label.visible, "the dropped tip does not come back")


func test_worn_gear_gets_no_new_equipment_tip() -> void:
	WorldState.inventory.attach("jetpack", content.get_item("jetpack"))
	gear.hud.toast("x", 1.0)
	gear._tips_for("jetpack")
	gear.hud._process(2.0)
	assert_false(gear.hud.toast_label.visible)


func test_menu_rows_follow_what_you_own_and_wear() -> void:
	# Neither worn: Put on for each, no Take off.
	gear.toggle_gear()
	assert_eq(gear.menu.rows.size(), 2)
	for r in gear.menu.rows:
		assert_string_contains(str(r), "Put on")
		assert_false(str(r).contains("Take off"))
	gear.menu.choose("")
	# Jetpack worn: it offers Take off only, the armour Put on only.
	WorldState.inventory.attach("jetpack", content.get_item("jetpack"))
	gear.toggle_gear()
	assert_eq(gear.menu.rows.size(), 2)
	assert_string_contains(str(gear.menu.rows[0]), "Take off Jetpack")
	assert_false(str(gear.menu.rows[0]).contains("Put on"))
	assert_string_contains(str(gear.menu.rows[1]), "Put on Quantonium armour")
	assert_false(str(gear.menu.rows[1]).contains("Take off"))
	gear.menu.choose("")
	# Both worn: Take off for each.
	WorldState.inventory.attach("quantonium_armour", content.get_item("quantonium_armour"))
	gear.toggle_gear()
	for r in gear.menu.rows:
		assert_string_contains(str(r), "Take off")
		assert_false(str(r).contains("Put on"))


## The move keys go up for 5 seconds once a run, the first time you are free on
## foot: not while a talk or a menu has you, and after a toast already up.
func test_the_move_hint_shows_once_when_you_are_free() -> void:
	GearController.move_hint_shown = false
	player.locked = true
	gear._tick_move_hint(2.0)
	assert_false(GearController.move_hint_shown, "a talk has you: not yet")
	player.locked = false
	gear._tick_move_hint(0.2)
	assert_false(GearController.move_hint_shown, "free a moment: still settling")
	gear.hud.toast("The general's hint", 5.0)
	gear._tick_move_hint(0.4)
	assert_true(GearController.move_hint_shown)
	assert_eq(gear.hud.toast_label.text, "The general's hint", "it waits for the toast already up")
	gear.hud._process(5.1)
	assert_eq(gear.hud.toast_label.text, "WASD or arrow keys to move")
	assert_eq(gear.hud._toast_left, GearController.MOVE_HINT_SECS, "for 5 seconds")
	gear.hud.toast_label.text = ""
	gear._tick_move_hint(1.0)
	assert_eq(gear.hud.toast_label.text, "", "once a run")


func test_free_roam_armour_sets_the_character_and_says_so() -> void:
	PlayerOutfit.save_path = "user://test_gear_g_outfit.json"
	WorldState.mode = WorldState.FREEPLAY
	WorldState.inventory.remove("jetpack")
	assert_eq(gear.toggle_gear(), "attached")
	assert_eq(PlayerOutfit.load_outfit(), { "head": "guard:desert", "torso": "guard:desert", "legs": "guard:desert" },
		"saved as the player's outfit (changed back in the builder)")
	assert_string_contains(gear.hud.toast_label.text, "off", "the put-on line first")
	gear.hud._process(10.0)
	assert_eq(gear.hud.toast_label.text, "Character set to Armor - Desert. Change in settings.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerOutfit.save_path))
	PlayerOutfit.save_path = ""
