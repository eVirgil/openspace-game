extends GutTest
## Issue #48: the player's outfit from the kit pieces. Picked in the character
## builder (F11, Character), saved by PlayerOutfit, worn by PlayerAvatar.

const SAVE := "user://test_player_outfit.json"
const MIX := { "head": "player", "torso": "guard:gunmetal", "legs": "player:rust" }
const ARMOUR := "quantonium_armour"
const GUARD_COLOURS := ["black", "blood", "desert", "gunmetal", "locals", "navy", "oxblood", "void", "white"]


func before_each() -> void:
	PlayerOutfit.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	WorldState.reset()
	WorldState.inventory.add(ARMOUR)     # the guard's pieces open (they are locked without it)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	PlayerOutfit.save_path = ""
	WorldState.reset()


func _meshes(body: Node3D) -> Array:
	var skin: SkinnedBody = body.get_meta("skin")
	var names := []
	for mi in skin.model.find_children("*", "MeshInstance3D", true, false):
		names.append(String(mi.name))
	names.sort()
	return names


func _texture(body: Node3D, mesh: String) -> String:
	var skin: SkinnedBody = body.get_meta("skin")
	var mi := skin.model.find_child(mesh, true, false) as MeshInstance3D
	var m := mi.get_surface_override_material(0) as BaseMaterial3D
	return m.albedo_texture.resource_path.get_file() if m != null and m.albedo_texture != null else ""


func test_catalog_lists_every_kit_piece_and_colour() -> void:
	var cat := PlayerOutfit.catalog()
	assert_eq(cat.head.keys(), ["player", "goggles", "nomad", "nomad_crest", "nomad_maw", "nomad_horn", "guard", "cantina_owner", "local"],
		"the player's own piece first, then the kit's (the sand nomad head and its variations among them)")
	assert_eq(cat.torso.keys(), ["player", "guard", "cantina_owner", "local"])
	assert_eq(cat.legs.keys(), ["player", "cantina_owner", "guard", "local"])
	assert_eq(cat.head.player, ["black", "dusk", "olive", "rust", "sand"], "the player's head has its own textures")
	assert_eq(cat.torso.player, ["black", "dusk", "olive", "rust", "sand"])
	# Issue #303: the generals' bright blood red and the dark master's void black too.
	assert_eq(cat.legs.guard, ["black", "blood", "desert", "gunmetal", "locals", "navy", "oxblood", "void", "white"])
	assert_eq(cat.head.goggles, ["oxblood", "sand", "violet"])
	assert_eq(cat.head.nomad, [], "the nomad heads are baked sand: no colour variants")


func test_save_survives_a_restart() -> void:
	assert_eq(PlayerOutfit.load_outfit(), {}, "nothing saved: the default")
	assert_true(PlayerOutfit.save_outfit(MIX))
	assert_eq(PlayerOutfit.load_outfit(), MIX, "read back from the file")


func test_unknown_pieces_and_colours_are_dropped() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "head": "helmet", "torso": "guard:pink", "legs": "guard:desert", "hat": "x" }))
	f.close()
	assert_eq(PlayerOutfit.load_outfit(), { "legs": "guard:desert" })


func test_avatar_wears_the_saved_outfit() -> void:
	PlayerOutfit.save_outfit(MIX)
	var a := PlayerAvatar.new()
	add_child_autofree(a)
	assert_eq(a.worn_outfit(), MIX)
	assert_eq(_meshes(a.body), ["guard_torso", "player_head", "player_legs"])
	assert_eq(_texture(a.body, "guard_torso"), "guard_gunmetal.png")
	assert_eq(_texture(a.body, "player_legs"), "player_rust.png")


func test_set_outfit_swaps_the_body_and_keeps_what_it_holds() -> void:
	var a := PlayerAvatar.new(null, {})
	add_child_autofree(a)
	a.build_weapons(["pistol_blaster", "energy_blade"])
	var old_body := a.body
	a.set_outfit({ "head": "goggles:violet", "torso": "player:dusk", "legs": "guard" })
	assert_ne(a.body, old_body, "a new body")
	assert_false(is_instance_valid(old_body), "the old one is freed")
	assert_eq(a.get_children().filter(func(c): return c.name == "Body").size(), 1)
	assert_eq(_meshes(a.body), ["goggles_head", "guard_legs", "player_torso"])
	assert_eq(_texture(a.body, "player_torso"), "player_dusk.png")
	assert_eq(_texture(a.body, "goggles_head"), "goggles_violet.png")
	for id in a.weapons:
		assert_eq(a.weapons[id].get_parent(), a.joints.chest, id + " rides the new chest")
	assert_eq(a.joints.chest.get_children().filter(func(c): return str(c.name).begins_with("W_")).size(), 2)


func test_builder_saves_each_pick_and_sends_it_out() -> void:
	var b := CharacterBuilder.new()
	add_child_autofree(b)
	watch_signals(b)
	var piece: OptionButton = b._pieces.torso
	for i in piece.item_count:
		if piece.get_item_metadata(i) == "guard":
			piece.select(i)
			piece.item_selected.emit(i)
	var colour: OptionButton = b._colours.torso
	assert_eq(colour.item_count, 10, "Original and the guard's nine colours")
	for i in colour.item_count:
		if colour.get_item_metadata(i) == "oxblood":
			colour.select(i)
			colour.item_selected.emit(i)
	assert_eq(PlayerOutfit.load_outfit().get("torso"), "guard:oxblood", "saved")
	assert_signal_emitted(b, "outfit_changed")
	assert_eq(b.outfit.torso, "guard:oxblood")
	assert_has(_meshes(b.preview), "guard_torso", "the preview wears it")
	b.randomize_outfit()
	assert_eq(PlayerOutfit.load_outfit(), b.outfit, "random picks are saved too")


# ------------------------------------------------------------------ the guard's armour, locked in free roam

func test_free_roam_locks_the_guards_pieces_until_you_have_its_armour() -> void:
	WorldState.reset()
	assert_false(WorldState.story_mode())
	assert_true(PlayerOutfit.catalog().torso.has("guard"), "the kit has them")
	for part in PlayerOutfit.PARTS:
		assert_false(PlayerOutfit.pickable()[part].has("guard"), part + ": not pickable without the armour")
	assert_eq(PlayerOutfit.locked_items(), [ARMOUR])
	PlayerOutfit.save_outfit(MIX)
	assert_eq(PlayerOutfit.load_outfit(), { "head": "player", "legs": "player:rust" }, "the guard's torso can not be worn")
	assert_eq(PlayerOutfit.sanitize(MIX, false), MIX, "another player's outfit keeps it (theirs to open)")
	WorldState.inventory.add(ARMOUR)
	for part in PlayerOutfit.PARTS:
		assert_eq(PlayerOutfit.pickable()[part].get("guard"), GUARD_COLOURS, part + ": every colour once you have it")
	assert_eq(PlayerOutfit.locked_items(), [])
	WorldState.inventory.remove(ARMOUR)
	assert_true(PlayerOutfit.pickable().torso.has("guard"), "open for good, even once it is sold")
	var saved := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(saved)
	assert_true(PlayerOutfit.pickable().head.has("guard"), "and after a load")


func test_builder_shows_the_guard_once_the_armour_is_had() -> void:
	WorldState.reset()
	var b := CharacterBuilder.new()
	add_child_autofree(b)
	var torso := func() -> Array:
		var out := []
		for i in b._pieces.torso.item_count:
			out.append(b._pieces.torso.get_item_metadata(i))
		return out
	assert_false(torso.call().has("guard"))
	assert_true(b._locked_note.visible and b._locked_note.text.contains("Quantonium armour"), "says what opens it")
	WorldState.inventory.add(ARMOUR)
	b.show_outfit(b.outfit)
	assert_true(torso.call().has("guard"), "filled again when shown")
	assert_false(b._locked_note.visible)
