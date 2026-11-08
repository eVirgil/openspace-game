extends GutTest
## Issue #147: player-made stall keepers (content/community/npcs, CommunityNpc).
## Every file in the folder must pass the builder's own checks, build into a card
## a brain can run on, and keep to talk only. Runs on every pull request that adds one.

const PORT := "res://content/core/towns/port_round.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")


class FakeTown:
	var data: Dictionary
	func _init(d: Dictionary) -> void:
		data = d
	func markers() -> Array:
		return data.get("markers", [])


func _good() -> Dictionary:
	var n := CommunityNpc.blank("port_town", "vendor_5", "someone")
	n["id"] = "dorrin_vale"
	n["name"] = "Dorrin Vale"
	n["label"] = "Water seller"
	n["wares"] = "water"
	n["identity"] = "A water seller who knows every well in the district by taste."
	n["backstory"] = "Lost a brother to the desert and never lets anyone leave thirsty."
	n["speech"] = ["Speaks slowly.", "Never wastes a word."]
	n["knows"] = { "fence": "Cheats everyone but pays on time." }
	n["greetings"] = { "stranger": ["Water?"], "regular": [] }
	n["lines"] = { "small_talk": ["Hot one.", "Wells are low."], "bye": ["Drink up."] }
	return n


func _fields(errs: Array) -> Array:
	return errs.map(func(e): return str(e.field))


# ------------------------------------------------------------------ the folder

func test_every_file_is_valid_and_named_by_its_id() -> void:
	var files := CommunityNpc.load_files()
	assert_gt(files.size(), 0, "the folder has at least the sample stall keeper")
	var seen: Array = []
	for e in files:
		var d: Dictionary = e.data
		assert_false(d.is_empty(), "%s parses as a JSON object" % e.file)
		assert_eq(str(d.get("id", "")) + ".json", str(e.file), "%s is named by its id" % e.file)
		var errs := CommunityNpc.validate(d, seen)
		assert_eq(errs, [], "%s passes every check" % e.file)
		seen.append(d)


func test_every_file_builds_a_card_that_only_talks() -> void:
	for e in CommunityNpc.load_files():
		var c := CommunityNpc.card(e.data)
		assert_eq(str(c.id), "community_" + str(e.data.id))
		assert_true(bool(c.get("community", false)))
		for banned in ["offer_job", "offer_item", "pour_drink", "offer_speeder", "offer_ship", "club_vibe"]:
			assert_false((c.actions as Array).has(banned), "%s can not %s" % [e.file, banned])
		assert_eq(c.hears, ["market"], "they hear the market")
		assert_false((c.canned.default as Array).is_empty(), "small talk with no model")
		assert_false((c.greetings.stranger as Array).is_empty())
		var brain := NpcBrain.new(null, c)
		var persona: String = brain.builder.persona_message().content
		assert_string_contains(persona, str(c.name))
		assert_string_contains(str(brain.builder.rules_message().content), "<player_says>", "the template's rules are in")
		assert_false((brain.builder.actions() as Array).has("offer_job"), "the brain offers no jobs")


# ------------------------------------------------------------------ checks

func test_a_good_file_passes() -> void:
	assert_eq(CommunityNpc.validate(_good()), [])


func test_a_blank_file_lists_what_is_missing() -> void:
	var f := _fields(CommunityNpc.validate(CommunityNpc.blank("port_town", "vendor_5", "")))
	for want in ["id", "author", "label", "identity", "greetings_stranger", "small_talk", "bye"]:
		assert_has(f, want, "a blank file is missing %s" % want)


func test_franchise_words_are_caught() -> void:
	var blocked: Array = CommunityNpc._blocklist().get("terms", [])
	var n := _good()
	n["backstory"] = "Once flew a " + str(blocked[0]) + " for a living."
	assert_has(_fields(CommunityNpc.validate(n)), "text")


func test_an_authored_name_is_taken() -> void:
	var n := _good()
	n["name"] = CommunityNpc.knowable().values()[0]
	n["id"] = CommunityNpc.slug(n.name)
	assert_has(_fields(CommunityNpc.validate(n)), "name")


func test_two_files_can_not_share_a_name_or_id() -> void:
	var a := _good()
	var b := _good()
	b["label"] = "Other"
	var f := _fields(CommunityNpc.validate(b, [a]))
	assert_has(f, "id")
	assert_has(f, "name")


func test_remnant_armour_and_unknown_fields_are_refused() -> void:
	var n := _good()
	n["look"]["torso"] = "guard:gunmetal"
	n["price"] = 10
	var f := _fields(CommunityNpc.validate(n))
	assert_has(f, "look", "no Remnant armour on a stall keeper")
	assert_has(f, "schema", "no fields the builder does not make")


func test_unknown_people_are_refused() -> void:
	var n := _good()
	n["knows"] = { "the_emperor": "Hates him." }
	assert_has(_fields(CommunityNpc.validate(n)), "knows")


# ------------------------------------------------------------------ the card

func test_no_name_means_known_by_their_trade() -> void:
	var n := _good()
	n["name"] = ""
	var c := CommunityNpc.card(n)
	assert_eq(str(c.name), "The Water seller")
	assert_true(" ".join(PackedStringArray(c.voice)).contains("never give your name"))


func test_a_secret_adds_the_hint_tool_and_a_trusted_secret() -> void:
	var n := _good()
	assert_false((CommunityNpc.card(n).actions as Array).has("hint_secret"))
	n["secret"] = "Waters down the barrels for troopers."
	var c := CommunityNpc.card(n)
	assert_true((c.actions as Array).has("hint_secret"))
	assert_eq(str(c.secrets[0].tier), "trusted")


func test_the_briefing_puts_them_at_a_stall() -> void:
	var brain := NpcBrain.new(null, CommunityNpc.card(_good()))
	var b: Dictionary = brain.builder.briefing({ "place": { "town": "Dustwell", "planet": "Ochre" } }, Relationship.new(), [], [])
	assert_string_contains(str(b.message.content), "you keep a stall in the market of Dustwell")


func test_a_draft_has_its_own_id() -> void:
	assert_eq(str(CommunityNpc.card(_good(), true).id), "community_draft_dorrin_vale")


# ------------------------------------------------------------------ stalls

func test_the_port_has_eight_free_stalls() -> void:
	var town := FakeTown.new(CommunityNpc._read(PORT))
	var cc := CoreContent.new()
	cc.load_from()
	var free := CommunityNpc.free_stalls(town, "port_town", cc)
	assert_eq(free.size(), 8, "vendor_5 to vendor_12: the merchants with nothing to sell")
	for used in ["vendor_1", "vendor_2", "vendor_3", "vendor_4"]:
		assert_does_not_have(free, used, "%s is a vendor's" % used)
	assert_eq(CommunityNpc.free_stalls(town, "moon_town", cc), [], "V1: the port only")


func test_clashes_are_settled_by_id() -> void:
	var a := { "id": "aaa", "stall": "s2" }
	var b := { "id": "bbb", "stall": "s2" }
	var c := { "id": "ccc", "stall": "nowhere" }
	var d := { "id": "ddd", "stall": "s1" }
	var got := CommunityNpc.assign([d, c, b, a], ["s1", "s2", "s3"])
	assert_eq(str(got.s2.id), "aaa", "the first id keeps the stall it asked for")
	assert_eq(str(got.s1.id), "ddd")
	assert_eq(str(got.s3.id), "bbb", "the next takes the first stall left")
	assert_eq(got.size(), 3, "no stall for the last one")


# ------------------------------------------------------------------ send

func test_the_link_opens_github_with_the_file() -> void:
	var n := _good()
	var link := CommunityNpc.pr_url(n)
	assert_true(bool(link.full))
	assert_string_starts_with(str(link.url), "https://github.com/wr-max52/dune-game/new/main?filename=content%2Fcommunity%2Fnpcs%2Fdorrin_vale.json&value=")
	var value := str(link.url).get_slice("&value=", 1).uri_decode()
	assert_eq(value, CommunityNpc.to_json(n))


func test_a_long_file_goes_as_a_blank_page() -> void:
	var n := _good()
	n["backstory"] = "x".repeat(9000)
	var link := CommunityNpc.pr_url(n)
	assert_false(bool(link.full))
	assert_false(str(link.url).contains("&value="))


func test_the_file_reads_back_the_same() -> void:
	var n := _good()
	var text := CommunityNpc.to_json(n)
	assert_string_starts_with(text, "{\n  \"schema\": 1,")
	var back = JSON.parse_string(text)
	assert_eq(CommunityNpc.validate(back), [])
	assert_eq(CommunityNpc.to_json(back), text, "stable: the same file every time")
