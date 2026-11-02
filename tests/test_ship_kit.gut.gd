extends GutTest
## M10: ship looks. Every ship's look id resolves to an entry in content/look/ships.json
## and builds a visible ship with engine glows, noses point down -Z like the flight
## model, an unknown look still builds something visible, and a look with a "scene"
## path uses that model instead of the stand-in -- the hook for real designs later.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const ShipNode := preload("res://src/systems/flight/ship_node.gd")
const FlightModel := preload("res://src/systems/flight/flight_model.gd")

var kit: ShipKit


func before_each() -> void:
	kit = ShipKit.new()


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Local-space bounds of every mesh under `root`.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_every_ship_look_resolves() -> void:
	var content = CoreScript.new()
	content.load_from()
	for sid in content.ships:
		var look := str(content.get_ship(sid).look)
		assert_true(kit.has_look(look), "%s look '%s' exists in ships.json" % [sid, look])


func test_every_look_builds_with_engines_and_a_forward_nose() -> void:
	for id in kit.look_ids():
		var ship := kit.build(id)
		add_child_autofree(ship)
		assert_eq(ship.get_meta("look_id"), id)
		var engines := ship.get_node_or_null("Engines")
		assert_not_null(engines, "%s has an Engines node" % id)
		# Issue #43: the fleet's looks are Hyper3D models (their glows are painted on).
		if str(kit.looks[id].get("scene", "")) != "":
			assert_eq(ship.get_meta("source"), "scene", "%s uses its model" % id)
			assert_gt(_meshes(ship).size(), 0, "%s has geometry" % id)
		else:
			assert_eq(ship.get_meta("source"), "kit", "%s uses the stand-in" % id)
			assert_gt(_meshes(ship).size(), 5, "%s has real geometry" % id)
			assert_gt(engines.get_child_count(), 0, "%s has engine glows" % id)
		var b := _bounds(ship)
		var length := float(kit.looks[id].get("length", 1.0))
		assert_lt(b.position.z, -length * 0.3, "%s nose reaches toward -Z" % id)
		for g in engines.get_children():
			assert_gt((g as Node3D).position.z, 0.0, "%s engines sit at the back (+Z)" % id)


func test_unknown_look_still_builds_something_visible() -> void:
	var ship := kit.build("no_such_look")
	add_child_autofree(ship)
	assert_gt(_meshes(ship).size(), 0, "a missing look falls back to a stand-in")


func test_scene_path_swaps_in_a_real_model() -> void:
	# Build a tiny "model", save it, point a look at it: the kit must use it as-is.
	var model := Node3D.new()
	model.name = "Imported"
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	model.add_child(mi)
	mi.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	var path := "user://m10_test_model.tscn"
	assert_eq(ResourceSaver.save(packed, path), OK)
	var custom := ShipKit.new(null, { "looks": { "custom": { "scene": path, "frame": "dart" } } })
	var ship := custom.build("custom")
	add_child_autofree(ship)
	assert_eq(ship.get_meta("source"), "scene", "the model replaced the stand-in")
	assert_not_null(ship.get_node_or_null("Model"), "the model is mounted under the root")
	assert_null(ship.get_node_or_null("Body"), "no stand-in geometry was built")
	assert_not_null(ship.get_node_or_null("Engines"), "the root contract still holds")


func test_missing_model_falls_back_to_the_stand_in() -> void:
	var custom := ShipKit.new(null, { "looks": { "custom": { "scene": "res://nope/missing.glb", "frame": "blade" } } })
	var ship := custom.build("custom")
	add_child_autofree(ship)
	assert_eq(ship.get_meta("source"), "kit", "a bad model path never leaves a ship invisible")


func test_bolt_styles_build() -> void:
	for style in ["player", "hostile", "missile"]:
		var b := kit.build_bolt(style)
		add_child_autofree(b)
		assert_eq(_meshes(b).size(), 1, "%s bolt has one glow mesh" % style)


func test_ship_node_follows_the_flight_model() -> void:
	var node = ShipNode.new()
	add_child_autofree(node)
	node.setup(kit, "interceptor", 1, "player")
	var f = FlightModel.new({})
	f.position = Vector3(10, 20, 30)
	f.face(Vector3(1, 0, 0))
	node.sync(f, true)
	assert_almost_eq(node.global_position.distance_to(f.position), 0.0, 0.0001, "position copied")
	assert_almost_eq((-node.global_transform.basis.z).dot(f.forward()), 1.0, 0.0001, "facing copied")
	node.sync(f, false)
	assert_false(node.visible, "a destroyed ship is hidden")


## The locals' ships are the Remnant's models in a small colour change: no new render.
func test_locals_hold_their_own_paint_of_the_dark_ships() -> void:
	assert_eq(kit.look_for("interceptor_dark", "locals"), "interceptor_locals")
	assert_eq(kit.look_for("freighter_dark", "locals"), "freighter_locals")
	assert_eq(kit.look_for("interceptor_dark", "remnant"), "interceptor_dark", "the Remnant keep theirs")
	assert_eq(kit.look_for("courier", "locals"), "courier", "a look with no locals' paint stays")
	for id in ["interceptor_locals", "freighter_locals"]:
		assert_eq(kit.looks[id].scene, kit.looks[id.replace("_locals", "")].scene, "%s is the player's model, repainted" % id)


func _accent_colours(ship: Node3D) -> Array:
	var out: Array = []
	for mi in _meshes(ship):
		for i in mi.mesh.get_surface_count():
			var m := (mi.get_surface_override_material(i) if mi.get_surface_override_material(i) != null else mi.mesh.surface_get_material(i)) as BaseMaterial3D
			if m != null:
				out.append(m.albedo_color)
	return out


func test_the_locals_interceptor_turns_the_blue_and_saffron_green_and_bone() -> void:
	var plain := kit.build("interceptor")
	var locals := kit.build("interceptor_locals")
	add_child_autofree(plain)
	add_child_autofree(locals)
	var green := LookMaterials.faction_color("locals", "band")
	var a := _accent_colours(plain)
	var b := _accent_colours(locals)
	assert_eq(a.size(), b.size())
	var cobalt := Color("#062ea8")
	var turned := 0
	for i in a.size():
		if kit._near(a[i], cobalt):
			assert_almost_eq(b[i].g, green.g, 0.01, "cobalt parts are the locals' green")
			turned += 1
		elif not kit._near(a[i], Color("#fca80e")):
			assert_eq(b[i], a[i], "the silver hull, glass and glow are untouched")
	assert_gt(turned, 0, "the interceptor has cobalt parts to turn")


func test_repainting_an_outpost_ship_keeps_its_place_and_follows_the_holder() -> void:
	var ship := kit.build("interceptor_dark")
	add_child_autofree(ship)
	ship.position = Vector3(3, 2, 1)
	kit.repaint(ship, kit.look_for("interceptor_dark", "locals"))
	assert_eq(ship.get_meta("look_id"), "interceptor_locals")
	assert_eq(ship.position, Vector3(3, 2, 1))
	assert_not_null(ship.get_node_or_null("Model"))
	kit.repaint(ship, kit.look_for("interceptor_dark", "remnant"))
	assert_eq(ship.get_meta("look_id"), "interceptor_dark")
