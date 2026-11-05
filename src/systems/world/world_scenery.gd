class_name WorldScenery
extends Node3D
## What M14 adds to the desert around the port, beyond what the town's
## DesertTerrain and DesertLandforms already build (the sand, its walkable
## collider, the mesas and hoodoos):
##   - the world's location landmarks (the outpost's buildings): colliders always
##     (the CI greybox flies into them too), placeholder boxes with the look on,
##   - with the look on: the planet skirt, a ring beyond the desert's edge that
##     keeps falling away with the planet's curve, so a high ship sees a curved
##     horizon instead of the edge of the sand.
## Shapes come from WorldGround (the same boxes the ship collides with); colours
## from content/look/world.json.

const LOOK_PATH := "res://content/look/world.json"
const WRECK_SHADER := preload("res://src/systems/look/shaders/wreck_metal.gdshader")
const SMALL_PART := 6.0          ## metres corner to corner: a wreck plate this small is detail
const SMALL_PART_RANGE := 1500.0

var ground: WorldGround
var terrain: WorldTerrain
var look: Dictionary = {}
var _mats: LookMaterials
var _wreck_mats := {}
var _wreck_batches := {}         ## batch key -> { material, small, plates: [[mesh, xf]], ids }
var wreck_parts := {}            ## plate id -> the merged MeshInstance3D that draws it


func setup(world_ground: WorldGround) -> void:
	ground = world_ground
	terrain = world_ground.terrain


func _ready() -> void:
	name = "WorldScenery"
	look = ItemKit._read_json(LOOK_PATH)
	_build_landmark_colliders()


## Build the visible world. `sand` = the desert's own material (DesertTerrain.material),
## so the skirt carries on the same sand and its seam does not show from high up.
func build_visuals(mats: LookMaterials = null, sand: Material = null) -> void:
	_mats = mats if mats != null else LookMaterials.new()
	if terrain.sphere == null:
		_build_skirt(sand)       # a ball (issue #77) has sand all the way round already
	_build_landmark_visuals()


## The location landmarks' boxes (ids "<landmark>/<building>"); town boxes collide
## in the town already.
func landmark_boxes() -> Array:
	return ground.boxes.filter(func(b): return str(b.id).contains("/"))


func _build_landmark_colliders() -> void:
	var root := StaticBody3D.new()
	root.name = "LandmarkColliders"
	add_child(root)
	for b in landmark_boxes():
		if str(b.get("rise", "")) != "":
			continue                 # a ramp: its dresser builds the sloped collider
		var cs := CollisionShape3D.new()
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if bool(b.get("wreck_shard", false)):
			var shape := ConvexPolygonShape3D.new()
			shape.points = StarcruiserWreck.shard_vertices(mx - mn)
			cs.shape = shape
		else:
			var shape := BoxShape3D.new()
			shape.size = mx - mn
			cs.shape = shape
		# Issue #77: on the ball a box stands in its own (leaning) frame.
		cs.transform = WorldGround.box_xf(b) * Transform3D(Basis.IDENTITY, (mn + mx) * 0.5)
		root.add_child(cs)


## A ring beyond the desert that keeps falling away with the planet. It starts
## just inside the desert's edge, a metre under the skirt level, so the sand's
## corners cover it and its seam never flickers.
func _build_skirt(sand: Material = null) -> void:
	var r0 := terrain.extent * 0.97
	# Issue #46: out to the horizon seen from three times the edge of space, and no
	# further: on a smaller planet the rest is round the curve and never drawn.
	var horizon := terrain.curve_from + sqrt(2.0 * terrain.planet_radius * ground.space_altitude() * 3.0)
	var rings := [r0, terrain.extent * 1.5]
	for r in [14000.0, 24000.0, 40000.0, 60000.0, 100000.0]:
		if r < horizon:
			rings.append(r)
	rings.append(horizon)
	var seg := 96
	var base := terrain.skirt_height - 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings.size() - 1:
		var ra: float = rings[k]
		var rb: float = rings[k + 1]
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var p00 := Vector3(cos(a0) * ra, base - terrain.drop(ra), sin(a0) * ra)
			var p01 := Vector3(cos(a1) * ra, base - terrain.drop(ra), sin(a1) * ra)
			var p10 := Vector3(cos(a0) * rb, base - terrain.drop(rb), sin(a0) * rb)
			var p11 := Vector3(cos(a1) * rb, base - terrain.drop(rb), sin(a1) * rb)
			for v in [p00, p10, p11, p00, p11, p01]:      # wound to face up (the sand culls backs)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "PlanetSkirt"
	mi.mesh = st.commit()
	if sand != null:
		mi.material_override = sand
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(look.get("terrain", {}).get("skirt_color", "#b8916a")))
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1000.0
	add_child(mi)


func _build_landmark_visuals() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	var op: Dictionary = look.get("outpost", {})
	for b in landmark_boxes():
		if b.has("wreck_finish"):
			_add_wreck_plate(b)
			continue
		if not bool(b.get("visual", true)):
			continue                 # dressed elsewhere (issue #42: Skrugs's post)
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var bm := BoxMesh.new()
		bm.size = mx - mn + Vector3(0, 2.0, 0)       # a skirt of wall below the sand
		var mi := MeshInstance3D.new()
		mi.name = str(b.id).replace("/", "_")
		mi.mesh = bm
		mi.material_override = _mats.plaster(mn.y, mn.y + (mx.y - mn.y) * 0.75,
			Color(str(op.get("trim", "#6b1e1e"))), Color(str(op.get("color", "#b9a48a"))))
		mi.transform = WorldGround.box_xf(b) * Transform3D(Basis.IDENTITY, (mn + mx) * 0.5 - Vector3(0, 1.0, 0))
		root.add_child(mi)
	_merge_wreck_plates(root)


## Structural plates use the physics/flight boxes. Fracture lips use a pointed
## convex mesh for foot collision and small conservative bounds for flight.
## No wall skirt across the opening, nor an impostor that vanishes up close.
## The plates are gathered by material here and drawn merged (_merge_wreck_plates):
## the wreck field is about 2,500 plates, and a mesh each was a draw call each,
## from every kilometre the field can be seen.
func _add_wreck_plate(b: Dictionary) -> void:
	var size := (b.max as Vector3) - (b.min as Vector3)
	var mesh := _plate_arrays(bool(b.get("wreck_shard", false)), size)
	var finish := str(b.wreck_finish)
	var frame: Transform3D = b.wreck_frame
	var key := str(b.id).get_slice("/", 0) + "/" + finish
	# Ramp cleats and landing-pad paint are laid out on the plate itself.
	if finish in ["ramp", "pad"]:
		key += "/%s" % size
	if not _wreck_mats.has(key):
		var material := ShaderMaterial.new()
		material.shader = WRECK_SHADER
		material.set_shader_parameter("noise_tex", _mats.noise)
		material.set_shader_parameter("wreck_from_world", frame.affine_inverse())
		material.set_shader_parameter("level_from_world", (b.get("wreck_level", frame) as Transform3D).affine_inverse())
		material.set_shader_parameter("plate_half", size * 0.5)
		material.set_shader_parameter("finish", { "hull": 0, "rib": 1, "scorch": 2, "marking": 3, "nozzle": 4,
			"deck": 5, "grate": 6, "ramp": 7, "pad": 8 }.get(finish, 0))
		_wreck_mats[key] = material
	# Wreck field: four wrecks in sight of each other. Their small parts (railings,
	# vents, braces) are a pixel or two past SMALL_PART_RANGE; stop drawing them.
	var small := size.length() < SMALL_PART
	var batch_key := key + ("/small" if small else "")
	if not _wreck_batches.has(batch_key):
		_wreck_batches[batch_key] = { "material": _wreck_mats[key], "small": small, "plates": [], "ids": [] }
	var batch: Dictionary = _wreck_batches[batch_key]
	batch.plates.append([mesh, WorldGround.box_xf(b) * Transform3D(Basis.IDENTITY,
		((b.min as Vector3) + (b.max as Vector3)) * 0.5)])
	batch.ids.append(str(b.id))


## Issue #574: a plate's surface arrays, made on the CPU (a BoxMesh's own arrays,
## the shard's SurfaceTool arrays) and kept by shape and size. Reading them back
## from a built mesh (surface_get_arrays) waited on the GPU for every one of the
## field's ~2,500 plates: over 3 s on the home planet's first frame.
static var _plate_cache := {}


static func _plate_arrays(shard: bool, size: Vector3) -> Array:
	var key := "%s/%s" % [shard, size]
	if _plate_cache.has(key):
		return _plate_cache[key]
	var arrays: Array
	if shard:
		var points := StarcruiserWreck.shard_vertices(size)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
				[1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
			for i in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(points[face[i]])
		st.generate_normals()
		arrays = st.commit_to_arrays()
	else:
		var box := BoxMesh.new()
		box.size = size
		arrays = box.get_mesh_arrays()
	_plate_cache[key] = arrays
	return arrays


## Issue #574: the merged wreck meshes, kept for the session by world: a second
## arrival on the home planet puts the same meshes in, with nothing to merge.
static var _merged := {}               ## world key -> [{ name, mesh, material, small, origin, ids }]


## One mesh per wreck, material and size class. Each vertex keeps its plate's own
## position and normal (CUSTOM0, CUSTOM1) for wreck_metal's plate-space patterns
## (panel seams, ramp cleats, pad paint), so the merge looks the same as the plates.
func _merge_wreck_plates(root: Node3D) -> void:
	var wkey := "%s/%d" % [str(ground.world.get("id", "")), _wreck_batches.size()]
	if not _merged.has(wkey) and not _wreck_batches.is_empty():
		_merged[wkey] = _merge_batches()
	for m in _merged.get(wkey, []):
		var mi := MeshInstance3D.new()
		mi.name = str(m.name)
		mi.mesh = m.mesh
		mi.material_override = m.material
		if bool(m.small):
			mi.visibility_range_end = SMALL_PART_RANGE
		mi.transform = Transform3D(Basis.IDENTITY, m.origin)
		root.add_child(mi)
		for id in m.ids:
			wreck_parts[id] = mi
	_wreck_batches.clear()


func _merge_batches() -> Array:
	var out: Array = []
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for batch_key in _wreck_batches:
		var batch: Dictionary = _wreck_batches[batch_key]
		var origin: Vector3 = (batch.plates[0][1] as Transform3D).origin   # small numbers in the mesh
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var local_pos := PackedFloat32Array()
		var local_normal := PackedFloat32Array()
		var index := PackedInt32Array()
		for plate in batch.plates:
			var arrays: Array = plate[0]
			var xf: Transform3D = Transform3D(Basis.IDENTITY, -origin) * (plate[1] as Transform3D)
			var nb := xf.basis.inverse().transposed()
			var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for k in pv.size():
				verts.append(xf * pv[k])
				normals.append((nb * pn[k]).normalized())
				local_pos.append_array([pv[k].x, pv[k].y, pv[k].z, 0.0])
				local_normal.append_array([pn[k].x, pn[k].y, pn[k].z, 0.0])
			var pi = arrays[Mesh.ARRAY_INDEX]
			if pi is PackedInt32Array and not (pi as PackedInt32Array).is_empty():
				for k in (pi as PackedInt32Array):
					index.append(base + k)
			else:
				for k in pv.size():
					index.append(base + k)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_CUSTOM0] = local_pos
		arr[Mesh.ARRAY_CUSTOM1] = local_normal
		arr[Mesh.ARRAY_INDEX] = index
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
		out.append({ "name": str(batch_key).replace("/", "_"), "mesh": mesh, "material": batch.material,
			"small": bool(batch.small), "origin": origin, "ids": batch.ids })
	return out


## The merged mesh that draws wreck plate `id` ("<wreck>/<plate>"), or null.
func wreck_part(id: String) -> MeshInstance3D:
	return wreck_parts.get(id, null)
