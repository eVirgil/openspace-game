extends GutTest
## Issue #325: the bridge's holo table colours the port and the Remnant's seven
## outposts by who holds them, and recolours them live.

const NEAR := "remnant_outpost_near"
const MID := "remnant_outpost_mid"


func before_each() -> void:
	WorldState.new_game(WorldState.FREEPLAY)


func after_all() -> void:
	WorldState.reset()


func _holo() -> CruiserHolo:
	var home := PlanetGen.build(PlanetGen.home_id())
	var spec := _read_holo()
	var sp := PlanetSphere.new(5000.0)
	var h := CruiserHolo.new()
	h.setup(spec, sp, Transform3D(Basis(), sp.center + Vector3(0, 5000.0 + 7000.0, 0)), Vector3.ZERO, home.world, [], {})
	add_child_autofree(h)
	return h


func _read_holo() -> Dictionary:
	var f := FileAccess.open("res://content/core/cruiser/remnant_cruiser.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d.get("holo", {})


func _col(h: CruiserHolo, id: String) -> Color:
	return (h.places[id].mats[0] as ShaderMaterial).get_shader_parameter("color")


func test_the_town_and_every_outpost_are_coloured_by_who_holds_them() -> void:
	Territory.take(NEAR)
	Territory.take(MID)
	var h := _holo()
	var cols: Dictionary = h.spec.owner_colors
	assert_eq(h.places.size(), Story.OUTPOSTS.size() + 1, "the town and the seven outposts")
	assert_eq(_col(h, Territory.BARRACKS), Color(str(cols.remnant)), "the Remnant hold the town")
	for id in Story.OUTPOSTS:
		var want := Color(str(cols.locals)) if id in [NEAR, MID] else Color(str(cols.remnant))
		assert_eq(_col(h, str(id)), want, str(id))


func test_a_retake_turns_its_pin_live() -> void:
	Territory.take(NEAR)
	Territory.take(MID)
	var h := _holo()
	Territory.retake(NEAR)
	h.refresh_owners()
	assert_eq(_col(h, NEAR), Color(str(h.spec.owner_colors.remnant)), "back to the Remnant")
	assert_eq(_col(h, MID), Color(str(h.spec.owner_colors.locals)), "the other stays")
	assert_gt(float(h.places[NEAR].flash), 0.0, "and it flashes")
	Territory.tick(Territory.n("hold_s", 900.0) - Territory.n("supply_warn_s", 420.0) + 1.0)
	h.refresh_owners()
	assert_eq(_col(h, MID), Color(str(h.spec.owner_colors.short)), "running short")
	WorldState.set_flag("remnant_fleet_beaten")
	h.refresh_owners()
	assert_eq(_col(h, Territory.BARRACKS), Color(str(h.spec.owner_colors.locals)), "the town is the locals' once the fleet is beaten")
