extends GutTest
## M9 addendum D5: the decor layer is visual (issue #55: plus its props' colliders), must
## dress every box it has a rule for, keep its lamps tracked and few, and stay out
## of character art. Art pass 2: buildings come from the building kit and market
## stalls get canopies and wares.

const TownDemo := preload("res://scenes/town_demo.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")

## Boxes the addendum's table deliberately leaves greybox (gate lintel: overhead
## in the perimeter zone has no row).
const SKIPPED_IDS := ["gate_lintel"]


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _demo(look_on: bool) -> Node:
	var d = TownDemo.new()
	d.use_look = look_on
	d.lookdev_mode = true        # no player, no pad: just the town
	add_child_autofree(d)
	return d


func _count(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count(c, cls)
	return n


func _all(node: Node, cls: String, out: Array) -> Array:
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		_all(c, cls, out)
	return out


## Issue #55: the decor's only collision is its props' (one "Props" body); the
## town's own boxes are untouched.
func test_decor_collision_is_only_its_props() -> void:
	var on = _demo(true)
	var off = _demo(false)
	# Issue #321: the barracks hall ("shell") is its pieces, each a box with a body.
	var n: int = on.town.boxes().filter(func(b): return str(b.kind) != "shell").size()
	assert_eq(_count(on.get_node("Town"), "StaticBody3D"), n, "one body per box with look on")
	assert_eq(_count(off.get_node("Town"), "StaticBody3D"), n, "and with look off")
	var props: Node = on.decor.get_node("Buildings/Props")
	assert_eq(_count(on.decor, "CollisionObject3D"), 1, "decor has one body: the props")
	assert_eq(_count(props, "CollisionShape3D"), on.decor.kit.solids, "one box per solid prop")
	assert_eq(_count(on.decor, "CollisionShape3D"), on.decor.kit.solids, "and no other shapes")


func test_props_are_solid() -> void:
	var d = _demo(true)
	var space: PhysicsDirectSpaceState3D = d.get_world_3d().direct_space_state
	var props: StaticBody3D = d.decor.get_node("Buildings/Props")
	assert_gt(d.decor.kit.solids, 200, "lamp posts, antennas, parapets, clutter")
	# Walk sideways into the first street lamp post: the ray stops on the props body.
	var street: Dictionary = {}
	for z in d.town.zones():
		if str(z.id) == "main_street":
			street = z
	var post := Vector3(float(street.min[0]) + 4.0, 1.0, float(street.min[1]) + 0.6)
	await wait_physics_frames(2)
	var q := PhysicsRayQueryParameters3D.create(post + Vector3(2.0, 0, 0), post)
	var hit := space.intersect_ray(q)
	assert_false(hit.is_empty(), "the lamp post is in the way")
	if not hit.is_empty():
		assert_eq(hit.collider, props, "and it is a prop")
	# Antennas on a roof: something to stand on above the building's own box.
	var top := 0
	for c in props.get_children():
		var cs := c as CollisionShape3D
		for b in d.town.boxes():
			if str(b.get("look", "")) != "" and cs.position.y > float(b.max[1]) \
					and cs.position.x > float(b.min[0]) and cs.position.x < float(b.max[0]) \
					and cs.position.z > float(b.min[2]) and cs.position.z < float(b.max[2]):
				top += 1
				break
	assert_gt(top, 50, "roof props collide")


func test_every_box_has_a_material_when_look_on() -> void:
	var d = _demo(true)
	for b in d.town.boxes():
		if str(b.kind) == "shell" or b.has("part_of"):
			continue                       # issue #321: the barracks hall is drawn by BarracksLook and the kit
		var body: Node = d.get_node("Town/" + str(b.id))
		var mi: MeshInstance3D = body.get_node("Mesh")
		if SKIPPED_IDS.has(str(b.id)):
			assert_null(mi.material_override, "%s keeps greybox on purpose" % b.id)
		else:
			assert_not_null(mi.material_override, "%s is dressed" % b.id)


func test_lamps_are_tracked_and_capped() -> void:
	var d = _demo(true)
	var omnis := _all(d, "OmniLight3D", [])
	assert_gt(omnis.size(), 0, "the town has lamps")
	assert_lte(omnis.size(), 12, "no more than 12 omni lights")
	for l in omnis:
		assert_true(d.look._lamps.has(l), "%s is tracked by LookEnvironment" % l.name)


func test_cloth_is_banners_and_awnings_no_character_art() -> void:
	var d = _demo(true)
	var banners := 0
	for mi in _all(d.decor, "MeshInstance3D", []):
		var m = mi.material_override
		if m is StandardMaterial3D and m.backlight_enabled:   # LookMaterials.cloth
			var kind := str(mi.get_meta("decor", ""))
			assert_true(kind in ["banner", "awning"], "%s is cloth but not a banner or awning" % mi.name)
			if kind == "banner":
				banners += 1
	assert_eq(banners, 2, "exactly the two watchtower banners")
	for n in _all(d, "Node3D", []):
		assert_false(n.get_script() == CharacterKit, "no CharacterKit nodes")
		assert_false(str(n.name).begins_with("Hooded"), "no hooded figures")
	# Markers stay capsules.
	for v in d.get_node("Markers").get_children():
		assert_true((v as MeshInstance3D).mesh is CapsuleMesh, "%s is a capsule" % v.name)


func test_buildings_drawn_by_the_kit() -> void:
	var d = _demo(true)
	var looks := 0
	for b in d.town.boxes():
		var look := str(b.get("look", ""))
		if look == "" or look == "stall" or look == "stall_back":
			continue          # the market dresses these, not the building kit
		looks += 1
		var mi: MeshInstance3D = d.get_node("Town/%s/Mesh" % b.id)
		assert_false(mi.visible, "%s: the greybox stand-in is hidden" % b.id)
	var built := 0
	for k in d.decor.kit.built:
		built += int(d.decor.kit.built[k])
	assert_eq(built, looks, "every box with a look is drawn")
	for k in ["hut_round", "hut_block", "hut_stepped", "hut_long", "tower_block", "tower_round", "bridge", "hall", "shop"]:
		assert_gt(int(d.decor.kit.built.get(k, 0)), 0, "at least one %s" % k)
	# Batched: one MultiMesh per (mesh, material), many parts in each.
	var mms := _all(d.decor, "MultiMeshInstance3D", [])
	var parts := 0
	for m in mms:
		parts += (m as MultiMeshInstance3D).multimesh.instance_count
	assert_gt(parts, 4000, "a lot of parts")
	assert_gt(float(parts) / mms.size(), 6.0, "drawn in far fewer batches")


func test_round_buildings_have_round_collision() -> void:
	var d = _demo(false)
	var round := 0
	for b in d.town.boxes():
		var shape: Shape3D = (d.get_node("Town/%s" % b.id).get_child(1) as CollisionShape3D).shape
		if str(b.get("shape", "")) == "round":
			round += 1
			assert_true(shape is CylinderShape3D, "%s collides as a cylinder" % b.id)
			assert_almost_eq((shape as CylinderShape3D).radius, (float(b.max[0]) - float(b.min[0])) * 0.5, 0.01)
		else:
			assert_false(shape is CylinderShape3D, "%s stays a box" % b.id)
	assert_gt(round, 5, "some buildings are round")


func test_market_stalls_have_shade_and_wares_and_differ() -> void:
	var d = _demo(true)
	var market = d.decor.market
	var stalls: Array = []
	for b in d.town.boxes():
		if str(b.get("look", "")) == "stall":
			stalls.append(str(b.id))
	assert_eq(stalls.size(), 12, "twelve stalls")
	stalls.sort()
	for id in stalls:
		assert_true(market.wares.has(id), "%s has wares on its table" % id)
		assert_true(market.canopies.has(id), "%s has a shade canopy" % id)
	for i in range(1, stalls.size()):
		var a: String = stalls[i - 1]
		var b: String = stalls[i]
		var same: bool = market.wares[a] == market.wares[b] and market.canopies[a] == market.canopies[b]
		assert_false(same, "%s and %s look different" % [a, b])
		assert_ne(market.wares[a], market.wares[b], "%s and %s sell different things" % [a, b])
	assert_gte(market.awnings.size(), 12, "canopy cloth on every stall")
	for a in market.awnings:
		assert_gt((a as Node3D).global_position.y, 2.2, "canopies clear a standing head")


## Issue #355: the stall each trader works from shows its trade and its items, and
## the stalls are textured.
func test_trader_stalls_show_their_trade() -> void:
	var d = _demo(true)
	var market = d.decor.market
	var shows := {}
	for id in market.wares:
		shows[market.wares[id]] = id
	for kind in ["food", "gear", "contraband", "droids"]:
		assert_true(shows.has(kind), "a trader's stall shows %s" % kind)
	if shows.has("gear"):
		assert_true(market.items.has(shows.gear), "the gear trader's items are on its counter")
		assert_gt(market.items.get(shows.gear, []).size(), 1, "more than one of them")
	assert_not_null((market._wood as StandardMaterial3D).albedo_texture, "planks have a texture")


func test_presets_switch() -> void:
	var d = _demo(true)
	var ys: Array = []
	for p in ["golden", "noon", "dusk"]:
		d.set_preset(p)
		assert_eq(d.look.current, p)
		ys.append(d.look.sun_dir.y)
	assert_ne(ys[0], ys[1], "golden to noon moves the sun")
	assert_ne(ys[1], ys[2], "noon to dusk moves the sun")


func test_town_shots_load() -> void:
	var d = _demo(true)
	for id in ["gate_approach", "plaza", "cantina_bar", "top_down",
			"gate_to_desert", "desert_look_back", "north_wall_outside", "desert_aerial"]:
		assert_true(d.show_shot(id), "shot %s exists" % id)


func test_port_ship_is_the_flight_ship_and_fits_its_box() -> void:
	var d = _demo(true)
	assert_eq(d.decor.parked_ships.size(), 3, "the player's ship and two other flyable ships (issue #58: one pad is empty)")
	var looks := {}
	for s in d.decor.parked_ships:
		looks[str(s.get_meta("look_id"))] = true
	assert_eq(looks.size(), 3, "every ship in the pit looks different")
	var ship: Node3D = d.decor.parked_ships[0]
	# Same model as the dogfight: the player ship's look from the pad's encounter.
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var enc: Dictionary = content.encounters[str(GameFlow.pad("town_pit").encounter)]
	var look_id := str(content.ships[str(enc.player.ship)].look)
	assert_eq(str(ship.get_meta("look_id")), look_id, "port ship uses the flight look")
	# The collision box matches the model, so there are no invisible walls.
	var box: Dictionary = d.town.get_box("ship")
	var bmin := Vector3(float(box.min[0]), float(box.min[1]), float(box.min[2]))
	var bmax := Vector3(float(box.max[0]), float(box.max[1]), float(box.max[2]))
	var a: AABB = TownDecor.visual_aabb(ship)
	for k in 3:
		assert_almost_eq(a.position[k], bmin[k], 0.4, "model min %d fits the box" % k)
		assert_almost_eq(a.end[k], bmax[k], 0.4, "model max %d fits the box" % k)
	var mi: MeshInstance3D = d.get_node("Town/ship/Mesh")
	assert_false(mi.visible, "the greybox stand-in is hidden")
	var has_shape := false
	for c in d.get_node("Town/ship").get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			has_shape = true
	assert_true(has_shape, "collision stays")
