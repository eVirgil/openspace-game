extends GutTest
## Look-dev regression tests. They run headless: geometry, data and IK are checked
## here; the look itself is checked with tools/lookdev/shoot.sh screenshots.

const BeautyCorner := preload("res://scenes/lookdev/beauty_corner.gd")


func test_every_preset_has_the_keys_the_environment_reads() -> void:
	var data := LookEnvironment.load_presets()
	assert_true(data.has("presets"), "time_of_day.json has presets")
	for id in ["golden", "noon", "dusk"]:
		var p: Dictionary = data["presets"].get(id, {})
		for key in ["sun", "sky", "ambient", "fog", "volumetric", "post"]:
			assert_true(p.has(key), "%s preset has %s" % [id, key])


func test_sun_direction_matches_elevation() -> void:
	var d := LookEnvironment.direction(0.0, 90.0)
	assert_almost_eq(d.y, 1.0, 0.0001, "90 degrees elevation points straight up")
	var low := LookEnvironment.direction(-58.0, 8.0)
	assert_almost_eq(rad_to_deg(asin(low.y)), 8.0, 0.01)


func test_ring_segment_faces_point_outward() -> void:
	# A wrong winding renders walls inside out; check the outer wall's normals.
	var mesh := LookMeshKit.ring_segment(10.0, 12.0, 0.0, 2.0, 0.0, PI * 0.5, 8)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var checked := 0
	for i in verts.size():
		var r := Vector2(verts[i].x, verts[i].z).length()
		var ang := atan2(verts[i].z, verts[i].x)
		var inside_arc := ang > 0.05 and ang < PI * 0.5 - 0.05   # skip the end caps
		if absf(r - 12.0) < 0.01 and absf(norms[i].y) < 0.1 and inside_arc:
			var radial := Vector3(verts[i].x, 0, verts[i].z).normalized()
			assert_gt(norms[i].dot(radial), 0.9, "outer wall normal points outward")
			checked += 1
	assert_gt(checked, 0)


func test_terrain_is_flat_inside_the_port_and_drops_to_the_basin() -> void:
	var t := DesertTerrain.new()
	assert_almost_eq(t.height_at(0.0, 0.0), t.port_height, 0.001)
	assert_lt(t.height_at(0.0, -900.0), -10.0, "the basin sits well below the port")
	t.free()


func test_every_archetype_builds_with_a_full_skeleton() -> void:
	var kit := CharacterKit.new(LookMaterials.new())
	assert_eq(kit.archetypes().size(), 8, "issue #45 added cantina_owner_station (a variant of cantina_owner)")
	for a in kit.archetypes():
		var c := kit.build(a)
		var joints: Dictionary = c.get_meta("joints")
		for j in ["pelvis", "chest", "head", "l_wrist", "r_wrist", "l_ankle", "r_ankle"]:
			assert_true(joints.has(j), "%s has joint %s" % [a, j])
		c.free()


func _hand_error(kit: CharacterKit, body: Node3D, side: String, target: Vector3) -> float:
	var wrist: Node3D = body.get_meta("joints")[side + "_wrist"]
	var hand := kit._rel(body, wrist) * Vector3(0, -CharacterKit.HAND_REACH, 0)
	return hand.distance_to(target)


func test_ik_puts_both_hands_on_the_rifle() -> void:
	var kit := CharacterKit.new(LookMaterials.new())
	var trooper := kit.build("remnant_trooper")
	var rifle: Node3D = trooper.get_meta("weapon")
	var grips: Dictionary = rifle.get_meta("grips")
	assert_lt(_hand_error(kit, trooper, "r", kit._rel(trooper, rifle) * (grips["r"] as Vector3)), 0.02, "right hand on the grip")
	assert_lt(_hand_error(kit, trooper, "l", kit._rel(trooper, rifle) * (grips["l"] as Vector3)), 0.02, "left hand on the foregrip")
	# Issue #82: the rendered rifle the player carries, not the box one.
	var model: Node3D = rifle.get_child(0)
	assert_eq(model.scene_file_path, "res://assets/gear/rifle.glb")
	assert_gt(model.find_children("*", "MeshInstance3D", true, false).size(), 0)
	trooper.free()


func test_duelist_holds_a_yellow_energy_sword_by_default() -> void:
	var kit := CharacterKit.new(LookMaterials.new())
	var duelist := kit.build("duelist")
	var sword: Node3D = duelist.get_meta("weapon")
	assert_eq(sword.name, "EnergySword")
	var light: OmniLight3D = sword.get_node("Blade/BladeLight")
	var c := light.light_color
	assert_true(c.r > 0.9 and c.g > 0.7 and c.b < 0.4, "default blade is yellow, got %s" % c)
	var grips: Dictionary = sword.get_meta("grips")
	assert_lt(_hand_error(kit, duelist, "r", kit._rel(duelist, sword) * (grips["r"] as Vector3)), 0.02, "two-handed grip")
	assert_lt(_hand_error(kit, duelist, "l", kit._rel(duelist, sword) * (grips["l"] as Vector3)), 0.02, "two-handed grip")
	duelist.free()


func test_beauty_corner_builds_headless_with_every_review_shot() -> void:
	var scene = BeautyCorner.new()
	scene.lookdev_mode = true
	scene.terrain_resolution = 48
	add_child_autofree(scene)
	for id in ["hero_vista", "street", "dune_return", "wreck_close", "lineup"]:
		assert_true(scene.show_shot(id), "shot %s exists" % id)
	for preset in ["golden", "noon", "dusk"]:
		scene.set_preset(preset)
		assert_eq(scene.look.current, preset)


## Issue #393: the Remnant's red marks repaint in the locals' colours, in place, by
## group: the town with the barracks, each outpost on its own; the homes keep their red.
func test_faction_materials_repaint_with_the_owner() -> void:
	var mats := LookMaterials.new()
	var band := mats.faction_plaster(0.0, 2.0, "band")
	var wall := mats.faction_plaster(0.0, 5.2, "wall")
	var cloth := mats.faction_cloth("band")
	var home := mats.plaster(0.0, 2.0, LookMaterials.CLOTH_MADDER)
	var mark := mats.faction_flat("mark", "remnant_outpost_near", 0.6, 0.2)
	var lamp := mats.faction_glow("lamp", "remnant_outpost_near")
	var red := LookMaterials.faction_color("remnant", "band")
	var green := LookMaterials.faction_color("locals", "band")
	assert_ne(red, green, "town_styles.json factions has both sides")
	assert_eq(band.get_shader_parameter("band_color"), red, "built Remnant red")
	assert_eq(mats.repaint("locals"), 3, "band, wall and banner cloth are the town's group")
	assert_eq(band.get_shader_parameter("band_color"), green)
	assert_eq(wall.get_shader_parameter("band_color"), LookMaterials.faction_color("locals", "wall"))
	assert_eq(cloth.albedo_color, green)
	assert_eq(home.get_shader_parameter("band_color"), LookMaterials.CLOTH_MADDER, "the homes keep their red")
	assert_eq(mark.albedo_color, LookMaterials.faction_color("remnant", "mark"), "an outpost is its own group")
	assert_eq(mats.repaint("locals", "remnant_outpost_near"), 2)
	assert_eq(mark.albedo_color, LookMaterials.faction_color("locals", "mark"))
	assert_eq(lamp.emission, LookMaterials.faction_color("locals", "lamp"))
	mats.repaint("remnant")
	assert_eq(band.get_shader_parameter("band_color"), red, "and back")
	assert_eq(mark.albedo_color, LookMaterials.faction_color("locals", "mark"), "the outpost is not the town")
