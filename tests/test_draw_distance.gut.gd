extends GutTest
## Distance rules: small things stop drawing first, big things always draw,
## lights fade, anything that walks takes the person rule, and what is built
## under a watched root later gets its range too. No renderer needed.

const DrawDistance := preload("res://src/systems/look/draw_distance.gd")

var dd: DrawDistance
var root: Node3D


func before_each() -> void:
	dd = DrawDistance.new()
	dd.setup()
	add_child(dd)
	root = Node3D.new()
	add_child(root)


func after_each() -> void:
	dd.queue_free()
	root.queue_free()


func _box(size: float, parent: Node = root) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3.ONE * size / sqrt(3.0)      # corner to corner = size
	mi.mesh = b
	parent.add_child(mi)
	return mi


func test_the_rules_are_the_ones_the_game_already_used() -> void:
	var outdoor: Dictionary = dd.rules.outdoor
	assert_eq(DrawDistance.end_for(outdoor, 0.3), 120.0, "trim, like the camps' canister rims")
	assert_eq(DrawDistance.end_for(outdoor, 1.0), 220.0, "props, like the camps' canisters")
	assert_eq(DrawDistance.end_for(outdoor, 5.0), 1500.0, "small parts, like the wreck field's")
	assert_eq(DrawDistance.end_for(outdoor, 12.0), 0.0, "buildings always draw")
	assert_eq(DrawDistance.end_for(dd.rules.interior, 3.0), 140.0, "rooms, like the barge's props")
	assert_eq(dd.light_begin_for(dd.rules.interior, 9.0), 90.0, "lights, like the barge's")
	assert_eq(dd.light_begin_for(dd.rules.interior, 30.0), 120.0, "a far-reaching light fades further off")


func test_watch_sets_ranges_and_keeps_ones_already_set() -> void:
	var small := _box(1.0)
	var big := _box(20.0)
	var own := _box(1.0)
	own.visibility_range_end = 55.0
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	root.add_child(lamp)
	dd.watch("outdoor", [root])
	assert_eq(small.visibility_range_end, 220.0)
	assert_eq(small.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
	assert_eq(big.visibility_range_end, 0.0)
	assert_eq(own.visibility_range_end, 55.0)
	assert_true(lamp.distance_fade_enabled)
	assert_eq(lamp.distance_fade_begin, 300.0)


func test_walkers_take_the_person_rule_and_late_builds_are_caught() -> void:
	dd.watch("outdoor", [root])
	var body := CharacterBody3D.new()
	root.add_child(body)
	var torso := _box(1.9, body)
	var later := _box(1.0)
	await wait_process_frames(3)
	assert_eq(torso.visibility_range_end, 320.0, "people draw as far as they are awake")
	assert_eq(later.visibility_range_end, 220.0)


func test_nothing_outside_a_watched_root_is_touched() -> void:
	var free := Node3D.new()
	add_child(free)
	var mi := _box(1.0, free)
	dd.watch("outdoor", [root])
	await wait_process_frames(3)
	assert_eq(mi.visibility_range_end, 0.0)
	free.queue_free()
