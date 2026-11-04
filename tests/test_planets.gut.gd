extends GutTest
## Issue #45: the planet generator, pure. Every town size from 1 to 100 passes the
## town validator; sizes scale the way the issue says (50 = the port, 100 = 5x,
## 1 = a cantina with a stage, a guard at its door, a merchant in front and locals
## in the street); every planet type
## builds; the style kit reads presets and plain words; a new planet is a config
## file and nothing else.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const AsteroidWorld := preload("res://src/systems/planets/asteroid_world.gd")
const PlanetSphere := preload("res://src/systems/planets/planet_sphere.gd")

var cc


func before_all() -> void:
	cc = CoreContent.new()
	cc.load_from()


func after_each() -> void:
	PlanetGen.clear_cache()
	GameFlow.reset()


func _town(size: int, seed: int = 1) -> TownLayout:
	var t := TownLayout.new()
	t.load_from_dict(TownGen.generate("t%d_%d" % [size, seed], size, seed))
	return t


func test_every_size_from_1_to_100_is_a_valid_town() -> void:
	var bad := PackedStringArray()
	for s in range(1, 101):
		for seed in [1, 45]:
			var errs := _town(s, seed).validate()
			if not errs.is_empty():
				bad.append("size %d seed %d: %s" % [s, seed, errs[0]])
	assert_eq(bad.size(), 0, str(bad.slice(0, 5)))


func test_size_scales_like_the_issue_says() -> void:
	var g := TownGen.new()
	assert_almost_eq(g.area_factor(50), 1.0, 0.001, "50 is the port's scale")
	assert_almost_eq(g.area_factor(100), 5.0, 0.01, "100 is 5x")
	var a50: Dictionary = _town(50).data.bounds
	var a100: Dictionary = _town(100).data.bounds
	var area := func(b): return (float(b.max[0]) - float(b.min[0])) * (float(b.max[1]) - float(b.min[1]))
	assert_between(area.call(a50), 25000.0, 40000.0, "about the port's 200 x 150")
	assert_between(area.call(a100) / area.call(a50), 4.0, 6.0)
	assert_gt(_town(100).boxes().size(), _town(50).boxes().size() * 3)


func test_size_1_is_a_cantina_a_guard_a_merchant_in_front_and_locals() -> void:
	var t := _town(1)
	var counts: Dictionary = t.data.counts
	assert_eq(int(counts.guards), 1)
	assert_eq(int(counts.merchants), 1)
	assert_eq(int(counts.residents), 0)
	assert_gte(int(counts.roamers), 3, "locals walking the street")
	assert_gte(t.routes().size(), 3)
	assert_eq(int(counts.bays), 1, "and a bay to land on")
	assert_false(t.get_box("bar_counter").is_empty(), "a cantina")
	assert_false(t.get_marker("cantina_owner").is_empty())
	var guards := t.markers_with_role("trooper_post")
	assert_eq(guards.size(), 1)
	assert_lt(_v(guards[0].pos).distance_to(t.marker_pos("cantina_door")), 5.0, "at the cantina door")
	var vendor := t.get_marker("vendor_1")
	assert_gt(float(vendor.pos[0]), float(t.get_box("cantina_wall_e_s").max[0]), "in front of the cantina")
	assert_false(t.get_box("cantina_stage").is_empty(), "a stage")
	assert_eq(t.boxes().filter(func(b): return str(b.get("look", "")).begins_with("hut")).size(), 0, "no houses")
	assert_false(t.get_box("ship").is_empty())
	assert_false(t.get_marker("player_spawn").is_empty())


func test_big_towns_have_everything() -> void:
	var t := _town(60)
	assert_gt(t.markers_with_role("trooper_post").size(), 4)
	assert_false(t.get_box("barracks_hall").is_empty())
	assert_false(t.get_box("watchtower").is_empty())
	assert_gt(t.boxes().filter(func(b): return str(b.get("look", "")) == "stall").size(), 8)
	assert_gt(t.routes().size(), 3, "residents strolling")
	assert_eq(t.data.garrison.klaxon_marker, "trooper_tower")
	assert_false(t.get_box("cantina_stage").is_empty(), "a stage")
	var door := float(t.get_box("cantina_wall_e_s").max[0])
	for i in int(t.data.counts.merchants):
		var v := t.get_marker("vendor_%d" % (i + 1))
		assert_between(float(v.pos[0]), door, door + 40.0, "every merchant in front of the cantina")


func test_a_pit_town() -> void:
	var t := TownLayout.new()
	t.load_from_dict(TownGen.generate("p", 1, 45, { "bay": "pit", "pit_clear": 1.45 }))
	assert_eq(t.validate().size(), 0, str(t.validate().slice(0, 3)))
	assert_false(t.get_box("pit_bowl").is_empty(), "the port's pit")
	assert_gt(float(t.get_box("pit_bowl").min[0]), float(t.data.bounds.max[0]), "outside the walls")
	assert_lt(float(t.get_marker("player_spawn").pos[1]), -5.0, "you start in the pit")
	assert_false(t.get_box("ship").is_empty())


## Issue #143: Grit Station's dancer stands on the stage (a cover box), and V7
## refused the whole town, so flying to the station built nothing.
func test_every_authored_planet_town_is_valid() -> void:
	for id in PlanetGen.ids(cc):
		var t := TownLayout.new()
		t.load_from_dict(PlanetGen.build(id, cc).town)
		assert_eq(t.validate().size(), 0, "%s: %s" % [id, str(t.validate().slice(0, 3))])


func test_the_same_seed_is_the_same_town() -> void:
	assert_eq(JSON.stringify(TownGen.generate("a", 40, 9)), JSON.stringify(TownGen.generate("a", 40, 9)))
	assert_ne(JSON.stringify(TownGen.generate("a", 40, 9).boxes), JSON.stringify(TownGen.generate("a", 40, 10).boxes))


func test_every_planet_type_builds() -> void:
	var types: Dictionary = PlanetGen.types().types
	assert_eq(types.size(), 8)
	for type in types:
		var p := PlanetGen.make({ "id": "test_" + type, "type": type, "town_size": 12, "seed": 2 }, cc)
		assert_eq(p.type, type)
		assert_false(p.town.is_empty(), type)
		var t := TownLayout.new()
		t.load_from_dict(p.town)
		assert_eq(t.validate().size(), 0, type)
		assert_true(p.ground in ["terrain", "platform", "ball"], type)
		assert_gt(float(p.world.atmosphere.space_altitude), 0.0, type)
		if p.ground != "terrain":
			assert_true((types[type] as Dictionary).has("surface"), type)
		if p.ground == "platform":
			assert_ne(str(types[type].fall_text), "", type + " says how you died")
		if p.ground == "ball":
			assert_gt(float(p.world.terrain.sphere_radius), 0.0, type + " is a real ball")


func test_the_port_is_unchanged() -> void:
	var p := PlanetGen.build("port_desert", cc)
	assert_eq(p.town_id, "port_town", "the hand-built town")
	assert_eq(p.town.boxes.size(), cc.get_location("port_town").boxes.size())
	assert_eq(p.world.id, "port_desert", "the hand-built world")
	assert_eq(p.ground, "terrain")
	assert_true(TownStyle.parse(p.style).is_identity(), "the port's own look")
	assert_eq(PlanetGen.home_id(), "port_desert")


## Issue #237: the port is built to a saved layout, picked by id and size, and
## keeps its id (port_town) whichever layout it is.
func test_the_port_picks_a_saved_layout() -> void:
	var p := PlanetGen.build("port_desert", cc)
	assert_eq(str(p.town.layout), str(cc.planets.port_desert.town_layout), "the layout its file names")
	assert_eq(int(p.town.size), int(p.size), "at the layout's size")
	assert_eq(str(p.town.id), "port_town", "the place keeps its id")
	assert_true("port_square" in PlanetGen.layouts(cc), "today's port is saved as port_square")
	var sq: Dictionary = cc.town_from_layout("port_square", "port_town")
	assert_eq(int(sq.size), 50, "port_square is size 50")
	assert_eq(str(cc.towns.port_square.id), "port_square", "the saved layout itself is untouched")
	PlanetGen.set_layout("port_desert", "port_square")
	var o := PlanetGen.build("port_desert", cc)
	assert_eq(str(o.town.layout), "port_square", "F11 builds it to another layout")
	PlanetGen.set_layout("port_desert", "")
	assert_false(PlanetGen.layout_override.has("port_desert"), "and back")


func test_only_grit_station_gets_one_dancer_next_to_its_stage() -> void:
	var station := PlanetGen.build("grit_station", cc)
	var station_town := TownLayout.new()
	station_town.load_from_dict(station.town)
	var dancers: Array = station_town.markers().filter(func(m): return str(m.get("soldier", "")) == "cantina_dancer")
	assert_eq(dancers.size(), 1, "the station has exactly one dancer")
	# Issue #261: the DJ has the stage; she dances on the floor beside it.
	var dancer_pos: Vector3 = station_town.marker_pos("cantina_dancer")
	var stage: Dictionary = station_town.get_box("cantina_stage")
	assert_almost_eq(dancer_pos.y, 0.0, 0.001, "on the floor, not the stage")
	var c := Vector2((float(stage.min[0]) + float(stage.max[0])) * 0.5, (float(stage.min[2]) + float(stage.max[2])) * 0.5)
	var r := (float(stage.max[0]) - float(stage.min[0])) * 0.5
	assert_between(Vector2(dancer_pos.x, dancer_pos.z).distance_to(c), r, r + 4.0, "next to the stage")
	var other := PlanetGen.make({ "id": "dance_test", "type": "sand", "town_size": 1, "seed": 45 }, cc)
	var other_town := TownLayout.new()
	other_town.load_from_dict(other.town)
	assert_eq(other_town.markers().filter(func(m): return str(m.get("soldier", "")) == "cantina_dancer").size(), 0,
		"generated towns without the station flag stay unchanged")


func test_the_station_dome_is_one_big_rave() -> void:
	var station_town := TownLayout.new()
	station_town.load_from_dict(PlanetGen.build("grit_station", cc).town)
	assert_eq(station_town.validate(), [], "the station town still validates")
	assert_eq(str(station_town.data.club.style), "rave")
	for id in ["cantina_wall_w", "cantina_wall_n", "cantina_wall_s", "cantina_wall_e_s", "cantina_wall_e_n", "cantina_roof"]:
		assert_true(station_town.get_box(id).is_empty(), "no cantina building: " + id)
	assert_eq(station_town.boxes().filter(func(b): return str(b.id).begins_with("cantina_home_")).size(), 0, "no homes in the rave")
	assert_false(station_town.get_box("bar_counter").is_empty(), "the bar stays")
	assert_false(station_town.get_box("stall_fn1").is_empty(), "the merchant's table stays")
	var zone: Dictionary = station_town.data.zones.filter(func(z): return z.id == "cantina")[0]
	var st: Dictionary = station_town.data.station
	assert_almost_eq(float(zone.max[0]) - float(zone.min[0]), float(st.radius) * 2.0, 0.01, "the club is the whole dome")
	# Walking in from the pad (the gate is on +x, so you face -x) the stage is on
	# your right: -z.
	var stage: Dictionary = station_town.get_box("cantina_stage")
	assert_lt(float(stage.max[2]), 0.0, "the stage is to the right of the way in")
	var band := station_town.markers().filter(func(m): return str(m.get("soldier", "")).begins_with("club_"))
	assert_eq(band.size(), 1, "only a DJ")
	assert_eq(str(band[0].prop), "dj_desk")
	assert_gte(station_town.markers().filter(func(m): return str(m.get("soldier", "")) == "local_raver").size(), 8)


func test_the_asteroid_station() -> void:
	var p := PlanetGen.build("grit_station", cc)
	assert_eq(p.type, "asteroid")
	assert_eq(p.size, 1)
	assert_eq(p.ground, "ball", "a real ball, like the home planet (issue #99)")
	assert_eq(float(p.world.terrain.sphere_radius), 1500.0)
	var stn: Dictionary = p.town.station
	assert_false(stn.is_empty(), "a sealed round station")
	assert_true(p.town.boxes.filter(func(b): return str(b.id).begins_with("wall_")).is_empty(), "no square walls")
	assert_false(p.town.boxes.filter(func(b): return b.id == "hall_floor").is_empty(), "a hallway to the pit")
	assert_true(p.town.boxes.filter(func(b): return b.id == "ramp_ne").is_empty(), "one way into the pit")
	assert_eq(p.style, "metallic")
	assert_eq(p.encounter, "", "quiet sky over the station")
	var om: Dictionary = p.town.markers.filter(func(m): return m.id == "cantina_owner")[0]
	assert_false(om.has("card"), "her own generated Oda")
	assert_eq(om.planet, "grit_station")
	assert_false(p.town.boxes.filter(func(b): return b.id == "pit_bowl").is_empty(), "the port's pit, outside")
	assert_eq(p.world.naming.town, "town_station", "a station's name, not a desert town's")
	var n: Array = p.neighbours
	assert_eq(n.size(), 1)
	assert_eq(n[0].id, "port_desert", "you can fly home")
	var home := PlanetGen.build("port_desert", cc)
	assert_eq(home.neighbours.map(func(x): return x.id), ["grit_station", "cinder_station"], "and the port sees the station (and the lava moon, #272)")
	assert_eq(home.neighbours[0].at, Vector3(9000, 5200, -6500))
	# Issue #99: one map. The station's port is on top of its ball; from the station
	# the port's ball is exactly where the shift between the two scenes puts it.
	var off: Vector3 = home.neighbours[0].offset
	assert_eq(off, Vector3(9000, 6700, -6500))
	assert_eq(n[0].offset, -off, "the same shift, back the other way")
	assert_eq(n[0].at, Vector3(0, -5000, 0) - off, "the home ball's centre, seen from the station")


func test_asteroid_station_walls_have_panel_detail() -> void:
	var p := PlanetGen.build("grit_station", cc)
	var station := AsteroidWorld.new()
	station.build_exterior(p.town.station, LookMaterials.new())
	add_child_autofree(station)
	assert_not_null(station.get_node_or_null("RingWallExteriorPanels/PanelPlates"), "the town wall is panelled")
	assert_not_null(station.get_node_or_null("LinerExteriorPanels/PanelPlates"), "the landing pit is panelled")
	var ring: MultiMesh = station.get_node("RingWallExteriorPanels/PanelPlates").multimesh
	var liner: MultiMesh = station.get_node("LinerExteriorPanels/PanelPlates").multimesh
	assert_gt(ring.instance_count, 40, "repeated hull plates around the whole station")
	assert_gt(liner.instance_count, 30, "repeated hull plates around the landing pad")


func test_asteroid_boulders_are_globe_wide_deterministic_and_clear_of_station() -> void:
	var surface: Dictionary = PlanetGen.types().types.asteroid.surface
	assert_eq(int(surface.boulders), 20, "the station planet config keeps only twenty rocks")
	var sphere := PlanetSphere.new(1500.0)
	sphere.site_rect = Rect2(Vector2(-120.0, -120.0), Vector2(240.0, 240.0))
	var a := AsteroidWorld.new()
	a.sphere = sphere
	a.surface = surface
	a._place_boulders()
	var b := AsteroidWorld.new()
	b.sphere = sphere
	b.surface = surface
	b._place_boulders()
	assert_eq(a.boulders.size(), 20)
	assert_eq(a.boulders, b.boulders, "same seed produces the same rocks")
	var north := -1.0
	var south := 1.0
	for rock in a.boulders:
		var pos: Vector3 = rock.xform.origin
		var dir := pos.normalized()
		north = maxf(north, dir.y)
		south = minf(south, dir.y)
		assert_false(sphere.site_rect.grow(14.0).has_point(sphere.world_to_map(pos)),
			"no boulder is in the station keep-out")
	assert_gt(north, 0.9, "rocks reach the far northern latitudes")
	assert_lt(south, -0.9, "rocks reach the far southern latitudes")


func test_asteroid_ambient_fill_scale_preserves_the_preset() -> void:
	var look := LookEnvironment.new()
	look.apply(look.default_preset)
	var base := look.env.ambient_light_energy
	look.set_ambient_energy_scale(1.25)
	assert_almost_eq(look.env.ambient_light_energy, base * 1.25, 0.001,
		"sealed station can be brighter without replacing time-of-day settings")
	look.set_ambient_energy_scale(1.0)
	assert_almost_eq(look.env.ambient_light_energy, base, 0.001, "reset keeps the original preset level")
	look.free()


func test_a_new_planet_is_only_a_config() -> void:
	var p := PlanetGen.make({ "id": "frost_reach", "name": "Frost Reach", "type": "snow", "town_size": 18,
		"style": "pale blue glossy ceramic with gold trim", "near": "port_desert", "at": [-12000, 6000, 4000] }, cc)
	assert_eq(p.type, "snow")
	assert_eq(p.town_id, "frost_reach_town")
	var book := NameBook.new()
	assert_eq(PlanetGen.display_name(p, book), "Frost Reach", "its own name, reserved")
	assert_false(book.name_for("planet", "planet:another") == "Frost Reach")
	var st := TownStyle.parse(p.style)
	assert_eq(st.unknown.size(), 0, str(st.unknown))
	assert_eq(p.neighbours[0].id, "port_desert")


func test_style_presets() -> void:
	assert_true(TownStyle.parse("desert").is_identity())
	assert_true(TownStyle.parse("").is_identity())
	var m := TownStyle.parse("metallic")
	assert_true(m.metal_walls)
	assert_gt(m.metallic, 0.5)
	assert_not_null(m.accent)
	var s := TownStyle.parse("snowy")
	assert_true(s.snow)
	assert_gt((s.wall(Color("#d8c2a0"))).v, 0.85, "white walls")
	var p := TownStyle.parse("pastel")
	assert_eq(p.palette.size(), 6)
	var walls := {}
	for c in [Color("#d8c2a0"), Color("#c9a77c"), Color("#b9a48a"), Color("#e0d0b0"), Color("#a08060")]:
		walls[p.wall(c).to_html()] = true
	assert_gt(walls.size(), 1, "buildings in different colours")


func test_style_words() -> void:
	var r := TownStyle.parse("red matte metal")
	assert_eq(r.unknown.size(), 0)
	assert_true(r.metal_walls)
	assert_almost_eq(r.roughness, 0.95, 0.001, "matte")
	assert_gt((r.main as Color).r, (r.main as Color).g * 1.5, "red")
	var b := TownStyle.parse("pale blue glossy ceramic with gold trim")
	assert_eq(b.unknown.size(), 0)
	assert_false(b.metal_walls)
	assert_almost_eq(b.roughness, 0.25, 0.001)
	assert_gt((b.main as Color).b, (b.main as Color).r)
	assert_gt((b.accent as Color).r, (b.accent as Color).b, "gold trim")
	var odd := TownStyle.parse("purple sparkly metal")
	assert_eq(Array(odd.unknown), ["sparkly"], "an unknown word is reported, not fatal")
	assert_true(odd.metal_walls)


func test_styled_materials_change_and_the_port_does_not() -> void:
	var plain := LookMaterials.new()
	var styled := LookMaterials.new()
	styled.style = TownStyle.parse("red matte metal")
	var a := plain.plaster(0.0, 1.0, LookMaterials.CLOTH_TEAL)
	var b := styled.plaster(0.0, 1.0, LookMaterials.CLOTH_TEAL)
	assert_eq(a.shader, LookMaterials.PLASTER)
	assert_eq(b.shader, LookMaterials.HULL, "metal walls")
	var ident := LookMaterials.new()
	ident.style = TownStyle.parse("desert")
	var c := ident.plaster(0.0, 1.0, LookMaterials.CLOTH_TEAL)
	assert_eq(c.get_shader_parameter("plaster"), a.get_shader_parameter("plaster"), "desert = the port, unchanged")
	var snow := LookMaterials.new()
	snow.style = TownStyle.parse("snowy")
	assert_gt((snow.paving().get_shader_parameter("plaster") as Color).v, 0.85)


func test_game_flow_travel() -> void:
	var went := []
	GameFlow.change_scene = func(p): went.append(p)
	assert_eq(GameFlow.current_planet_id(), "port_desert")
	GameFlow.travel(null, "grit_station", "courier", "Tonve II")
	assert_eq(GameFlow.current_planet_id(), "grit_station")
	assert_eq(GameFlow.flown_ship, "courier")
	assert_eq(GameFlow.arrival.mode, "travel")
	assert_eq(GameFlow.arrival.from, "port_desert")
	assert_eq(went, ["res://scenes/town_demo.tscn"], "the same scene: a planet is data")
	assert_true(GameFlow.arrival_text(GameFlow.arrival).contains("Tonve II"))
	GameFlow.reset()
	assert_eq(GameFlow.current_planet_id(), "port_desert")


func test_every_planet_has_its_own_oda() -> void:
	var p := PlanetGen.build("grit_station", cc)
	var book := NameBook.new()
	var card := PlanetOwner.card(p, book)
	var oda: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/npcs/cantina_owner_card.json"))
	assert_eq(card.id, "cantina_owner_grit_station", "her own brain and save entry")
	assert_ne(card.id, oda.id)
	assert_true(str(card.name).begins_with("Oda "), "a new iteration of Oda")
	assert_ne(card.name, oda.name, "with a generated last name")
	assert_true(str(card.identity).contains(PlanetGen.display_name(p, book)), "the planet's name in her prompt")
	assert_true((card.actions as Array).has("offer_job"), "she always has jobs")
	assert_eq(card.drinks, oda.drinks, "Oda's own trade")
	assert_eq(PlanetOwner.card(p, book).name, card.name, "the same name every time")
	assert_true(book.is_taken(card.name), "and nothing else gets it")
	for r in card.rules:
		assert_false(str(r).contains("Skrugs"), "nobody from the port's stalls")
	var looks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/look/characters.json")).archetypes
	assert_eq(looks.cantina_owner_station.base, "cantina_owner", "Oda's body, re-tinted")


func test_jobs_are_always_offered_off_the_home_planet() -> void:
	GameFlow.reset()
	WorldState.reset()
	var home := WorldState.open_jobs("stranger")
	var home_kinds := home.map(func(j): return str(j.get("kind", "")))
	assert_false(home_kinds.has("bounty"), "at the port the story opens contracts")
	assert_false(home.map(func(j): return str(j.get("id", ""))).has("j_station_smuggle_run"),
		"the station's drop is not offered at the port")
	GameFlow.planet_id = "grit_station"
	var jobs := WorldState.open_jobs("stranger")
	var kinds := jobs.map(func(j): return str(j.get("kind", "")))
	assert_true(kinds.has("smuggle"), "a smuggling run")
	assert_true(kinds.has("bounty"), "and a contract")
	var runs := jobs.filter(func(j): return str(j.get("kind", "")) == "smuggle")
	assert_eq(runs.size(), 1, "only the station's own run")
	assert_eq(str(runs[0].get("id", "")), "j_station_smuggle_run")
	assert_eq(str(runs[0].get("location", "")), "grit_station_town")
	WorldState.reset()
	GameFlow.reset()


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
