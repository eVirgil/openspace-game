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


## Low graphics (F11 > Options): the expensive features go, the shadows shorten, the
## 3D world draws at a lower scale, and turning it off gives every one of them back.
## The setting is saved to the player's graphics.cfg, so the file is put back after.
func test_low_graphics_turns_the_expensive_features_off_and_back_on() -> void:
	var path := LookEnvironment.SETTINGS_PATH
	var had := FileAccess.file_exists(path)
	var saved := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	var was := {}
	for pc in LookEnvironment.pieces():
		was[pc.id] = LookEnvironment.cut(pc.id)
	var cfg := LookEnvironment.low_cfg()
	var look := LookEnvironment.new()
	add_child_autofree(look)
	look.set_low_graphics(false)
	look.apply("golden")
	var ambient := look.env.ambient_light_energy
	assert_true(look.env.sdfgi_enabled or LookEnvironment.indirect_level() == 0.0, "SDFGI on by default")
	assert_true(look.env.volumetric_fog_enabled and look.env.ssao_enabled)

	look.set_low_graphics(true)
	assert_true(LookEnvironment.low_graphics())
	assert_false(look.env.sdfgi_enabled, "no SDFGI")
	assert_false(look.env.ssil_enabled, "no SSIL")
	assert_false(look.env.ssao_enabled, "no SSAO")
	assert_false(look.env.volumetric_fog_enabled, "no volumetric fog")
	assert_true(look.sun.shadow_enabled, "the sun still casts shadows")
	assert_true(look.env.glow_enabled, "bloom is not part of Low graphics")
	assert_eq(look.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_almost_eq(look.sun.directional_shadow_max_distance, float(cfg["shadow_m"]), 0.01)
	assert_almost_eq(look.env.ambient_light_energy, ambient * float(cfg["ambient"]), 0.001)
	assert_almost_eq(look.env.ambient_light_sky_contribution, 1.0 - float(cfg["bounce_share"]), 0.001, "sand bounce in the fill")
	assert_almost_eq(look.get_viewport().scaling_3d_scale, float(cfg["render_scale"]), 0.001)
	assert_eq(look.get_viewport().scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	look.apply("dusk")
	assert_false(look.env.sdfgi_enabled, "a new preset keeps it low")

	look.set_low_graphics(false)
	look.apply("golden")
	assert_true(look.env.volumetric_fog_enabled and look.env.ssao_enabled, "everything back")
	assert_eq(look.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_gt(look.sun.directional_shadow_max_distance, float(cfg["shadow_m"]))
	assert_almost_eq(look.env.ambient_light_energy, ambient, 0.001)
	assert_almost_eq(look.env.ambient_light_sky_contribution, 1.0, 0.001)
	assert_ne(look.get_viewport().scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)

	for id in was:
		LookEnvironment.save_cut(id, was[id])
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## One piece at a time (F11 > Options, under Low graphics): cutting the fog leaves
## everything else as it was, and bloom, which Low graphics leaves alone, has its own.
func test_one_piece_cut_on_its_own() -> void:
	var path := LookEnvironment.SETTINGS_PATH
	var had := FileAccess.file_exists(path)
	var saved := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	var was := {}
	for pc in LookEnvironment.pieces():
		was[pc.id] = LookEnvironment.cut(pc.id)
	var look := LookEnvironment.new()
	add_child_autofree(look)
	look.set_low_graphics(false)
	look.set_cut("bloom", false)
	look.apply("golden")
	var shadow_m := look.sun.directional_shadow_max_distance
	var scale := look.get_viewport().scaling_3d_scale

	look.set_cut("fog", true)
	assert_false(look.env.volumetric_fog_enabled, "no fog volumes")
	assert_true(look.env.ssao_enabled, "corner shadows kept")
	assert_true(look.env.sdfgi_enabled or LookEnvironment.indirect_level() == 0.0, "bounce light kept")
	assert_eq(look.sun.directional_shadow_max_distance, shadow_m, "sun shadows kept")
	assert_almost_eq(look.get_viewport().scaling_3d_scale, scale, 0.001, "full resolution kept")
	assert_false(LookEnvironment.low_graphics(), "one piece is not Low graphics")
	look.apply("noon")
	assert_false(look.env.volumetric_fog_enabled, "a new preset keeps the piece cut")

	look.set_cut("bloom", true)
	assert_false(look.env.glow_enabled, "no bloom")
	look.set_low_graphics(true)
	assert_true(LookEnvironment.low_graphics())
	assert_true(LookEnvironment.cut("bloom"), "Low graphics leaves bloom as it was")
	look.set_low_graphics(false)
	look.set_cut("bloom", false)
	assert_true(look.env.glow_enabled and look.env.volumetric_fog_enabled, "everything back")

	for id in was:
		LookEnvironment.save_cut(id, was[id])
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Issue #534: full graphics draws the world through the temporal upscaler (MetalFX
## where the renderer has it, FSR 2 otherwise) at full_graphics.render_scale; Low
## graphics' resolution piece is FSR 1 with FXAA; Temporal anti-aliasing off is full
## size with FXAA. The settings file is put back after.
func test_render_scale_and_anti_aliasing_follow_the_settings() -> void:
	var path := LookEnvironment.SETTINGS_PATH
	var had := FileAccess.file_exists(path)
	var saved := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	var was_res := LookEnvironment.cut("resolution")
	var was_taa := LookEnvironment.taa()
	var look := LookEnvironment.new()
	add_child_autofree(look)
	var vp := look.get_viewport()
	var full := LookEnvironment.full_cfg()
	assert_almost_eq(float(full.get("render_scale", 0.0)), 0.77, 0.001, "time_of_day.json full_graphics.render_scale")

	look.set_cut("resolution", false)
	look.set_taa(true)
	assert_true(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2
		or vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, "a temporal upscaler")
	assert_eq(vp.scaling_3d_mode, LookEnvironment.temporal_mode())
	assert_almost_eq(vp.scaling_3d_scale, float(full["render_scale"]), 0.001)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "the upscaler is the anti-aliasing")

	look.set_cut("resolution", true)
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR, "Low keeps FSR 1")
	assert_almost_eq(vp.scaling_3d_scale, float(LookEnvironment.low_cfg()["render_scale"]), 0.001)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "and adds FXAA")

	look.set_cut("resolution", false)
	look.set_taa(false)
	assert_false(LookEnvironment.taa())
	assert_eq(vp.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "anti-aliasing off: no upscaler")
	assert_almost_eq(vp.scaling_3d_scale, 1.0, 0.001, "at full size")
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "with FXAA")

	LookEnvironment.save_cut("resolution", was_res)
	LookEnvironment.save_taa(was_taa)
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
