class_name TownNav
extends Node3D
## The town's walkable surface for NPCs. The navmesh is baked at load time from
## the same box data the collision comes from (content/core/locations/*.json), so
## moving a wall in the data moves it for the guards too, with no editor bake and
## no baked file to keep in sync.
##
## The bake takes about a quarter second for port_town, too long for one frame,
## so the live game bakes on a worker thread and NPCs stand still until
## `is_ready`. Traces and tests can bake synchronously.
##
## Desert locations can add small, local terrain regions through
## `add_terrain_region`; the planet is never baked as one enormous mesh.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const PitBowl := preload("res://src/systems/world/pit_bowl.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")

## Bake settings. Agent sizes are whole multiples of the cells so nothing gets
## rounded (Godot warns when they do). Radius 0.5 is the 0.4 capsule plus margin.
## Climb is what the body can really do, not what looks fine: the player's capsule
## (radius 0.4, 45 degree floor angle) rolls over about 0.12 m and treats anything
## taller as a wall. At 0.4 the mesh let guards step onto the side of the pit
## ramp near its foot, where they pinned themselves for good.
const DEFAULTS := {
	"cell_size": 0.25,
	"cell_height": 0.1,
	"agent_radius": 0.5,
	"agent_height": 1.8,
	"agent_max_climb": 0.1,
	"agent_max_slope": 40.0,
	"bounds_margin": 1.0,
}

signal baked

var region: NavigationRegion3D
var navmesh: NavigationMesh
var is_ready := false
var bake_ms := 0.0
var settings: Dictionary = DEFAULTS.duplicate()
var _bake_start := 0
var desert_regions: Array[NavigationRegion3D] = []


## Triangles for every box in the town, ramps tilted the way the scene builds them.
## Built as plain faces (not meshes) so the bake never reads geometry back from
## the GPU, which Godot warns is slow at runtime.
##
## Recast only sees surfaces, so the floor inside a closed box (a building, a
## crate) would bake as a walkable island, and a "nearest point" query could hand
## a guard a spot inside a wall. Every blocking box is also an obstruction, which
## clears its footprint, except a box something stands on (the watchtower top,
## the barracks hall roof): that one clears only below its top, so the roof keeps
## its floor and the inside still has none.
static func source_geometry(town) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(box_faces(town), Transform3D.IDENTITY)
	for b in obstruction_boxes(town):
		# Issue #321: a wall under a roof (the barracks hall's) clears only up to its
		# top, so the roof over it stays walkable for the riflemen.
		_obstruct(src, b, -0.05 if bool(b.get("under_roof", false)) else 0.5)
	for b in stood_on_boxes(town):
		_obstruct(src, b, -0.5)
	return src


## Clear a box's footprint from its foot to `over` metres above its top.
static func _obstruct(src: NavigationMeshSourceGeometryData3D, b: Dictionary, over: float) -> void:
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var outline := PackedVector3Array([Vector3(mn.x, 0, mn.z), Vector3(mx.x, 0, mn.z), Vector3(mx.x, 0, mx.z), Vector3(mn.x, 0, mx.z)])
	src.add_projected_obstruction(outline, mn.y, mx.y - mn.y + over, false)


## Blocking boxes (the town's blocking_kinds) that no marker stands on. Ramps are
## never obstructions.
static func obstruction_boxes(town) -> Array:
	return _blocking_boxes(town).filter(func(b): return not _stood_on(town, b))


## Blocking boxes a marker stands on (a post on a roof).
static func stood_on_boxes(town) -> Array:
	return _blocking_boxes(town).filter(func(b): return _stood_on(town, b))


static func _blocking_boxes(town) -> Array:
	var blocking: Array = town.data.get("blocking_kinds", ["wall", "solid", "cover", "counter", "ship"])
	# The stair tower and lookout are walked through, not into, but their
	# helix is not on the navmesh: guards keep out of the whole footprint.
	return town.boxes().filter(func(b): return str(b.kind) in blocking or str(b.kind) in ["spiral", "lookout"])


static func _stood_on(town, b: Dictionary) -> bool:
	for m in town.markers():
		var p: Array = m.pos
		if absf(float(b.max[1]) - float(p[1])) < 0.05 and float(p[0]) >= float(b.min[0]) and float(p[0]) <= float(b.max[0]) \
				and float(p[2]) >= float(b.min[2]) and float(p[2]) <= float(b.max[2]):
			return true
	return false


## Every box as 12 triangles (36 vertices), in world space. The round pit is a
## hollow shell, so it gives its real triangles instead (its box would be a lid);
## so does a round wall (its box is the whole town).
static func box_faces(town) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for b in town.boxes():
		if str(b.kind) == "shell":                # issue #321: the barracks hall is its pieces
			continue
		if str(b.kind) == "bowl":
			for m in PitBowl.parts(b, town).values():
				faces.append_array((m as ArrayMesh).get_faces())
			continue
		if str(b.kind) == "ring":                # issue #237: a round wall, piece by piece
			faces.append_array(RingWall.faces(b))
			continue
		var xf: Transform3D
		var half: Vector3
		if str(b.kind) == "ramp":
			var rt: Dictionary = TownLayout.ramp_transform(b)
			xf = Transform3D(rt.basis, rt.center)
			half = (rt.size as Vector3) * 0.5
		else:
			var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
			var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
			xf = Transform3D(Basis.IDENTITY, (mn + mx) * 0.5)
			half = (mx - mn) * 0.5
		var c := []
		for i in 8:
			c.append(xf * Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1)))
		# Quads as corner indices; each becomes two triangles.
		for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			faces.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))
	return faces


## The town's footprint (all boxes) plus a margin, as the bake limit.
static func town_bounds(town, margin: float = 1.0) -> AABB:
	var box := AABB()
	var first := true
	for b in town.boxes():
		var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
		var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
		var a := AABB(mn, mx - mn)
		box = a if first else box.merge(a)
		first = false
	return box.grow(margin)


## Issue #55: how far past the town's boxes a speeder or ship still counts as in
## town (the garrison shoots it there).
const VEHICLE_MARGIN := 20.0
static var _bounds_id := 0
static var _bounds := AABB()


## Inside the town's footprint (x and z only), grown by `margin`. The bounds are
## worked out once per town: vehicles ask every frame.
static func in_town(town, p: Vector3, margin: float = VEHICLE_MARGIN) -> bool:
	if town == null:
		return false
	if _bounds_id != town.get_instance_id():
		_bounds = town_bounds(town, 0.0)
		_bounds_id = town.get_instance_id()
	var b := _bounds.grow(margin)
	return p.x >= b.position.x and p.x <= b.end.x and p.z >= b.position.z and p.z <= b.end.z


func make_navmesh(town) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = float(settings.cell_size)
	nm.cell_height = float(settings.cell_height)
	nm.agent_radius = float(settings.agent_radius)
	nm.agent_height = float(settings.agent_height)
	nm.agent_max_climb = float(settings.agent_max_climb)
	nm.agent_max_slope = float(settings.agent_max_slope)
	nm.filter_baking_aabb = town_bounds(town, float(settings.bounds_margin))
	return nm


## A bounded patch of walkable terrain in a local tangent frame. Sampling the
## terrain's public ground API keeps nav geometry on the same surface as collision;
## on a planet the region is tilted to the local ground-up direction. `obstructions`
## contains { outline: PackedVector3Array, bottom: float, height: float } in that frame.
static func terrain_source(terrain: DesertTerrain, center: Vector3, half_extent: float,
	step: float, frame: Transform3D, obstructions: Array = []) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	var cells := int(ceil(half_extent * 2.0 / step))
	var sphere: PlanetSphere = (terrain as PlanetTerrain).sphere if terrain is PlanetTerrain else null
	var verts := PackedVector3Array()
	verts.resize((cells + 1) * (cells + 1))
	for j in cells + 1:
		for i in cells + 1:
			var lx := -half_extent + i * step
			var lz := -half_extent + j * step
			var sample: Vector3 = frame * Vector3(lx, 0.0, lz)
			var world: Vector3
			if sphere != null:
				var map := sphere.world_to_map(sample)
				world = sphere.surface_at(map.x, map.y)
			else:
				world = Vector3(sample.x, terrain.ground_at(sample.x, sample.z), sample.z)
			verts[j * (cells + 1) + i] = frame.affine_inverse() * world
	var faces := PackedVector3Array()
	var bottom := PackedVector3Array()
	bottom.resize(verts.size())
	for j in cells + 1:
		for i in cells + 1:
			var p: Vector3 = verts[j * (cells + 1) + i]
			bottom[j * (cells + 1) + i] = Vector3(p.x, -79.0, p.z)
	for j in cells:
		for i in cells:
			var a := j * (cells + 1) + i
			var b := a + 1
			var c := a + cells + 1
			var d := c + 1
			# Recast treats the walkable top as a solid when it is closed. The
			# buried underside and edge skirts are never walkable, but keep this
			# small terrain patch bakeable as a bounded volume.
			# Positive local Y winding (the terrain frame's ground-up axis).
			faces.append_array(PackedVector3Array([verts[a], verts[c], verts[b],
				verts[b], verts[c], verts[d]]))
			# The underside faces down.
			faces.append_array(PackedVector3Array([bottom[a], bottom[b], bottom[c],
				bottom[b], bottom[d], bottom[c]]))
	# Close the volume around its boundary with vertical, non-walkable skirts.
	for i in cells:
		var a := i
		var b := i + 1
		var c := cells * (cells + 1) + i
		var d := c + 1
		# z = -half_extent (outward -Z)
		faces.append_array(PackedVector3Array([verts[a], verts[b], bottom[a],
			verts[b], bottom[b], bottom[a]]))
		# z = +half_extent (outward +Z)
		faces.append_array(PackedVector3Array([verts[c], bottom[c], verts[d],
			verts[d], bottom[c], bottom[d]]))
		var left_a := i * (cells + 1)
		var left_c := left_a + cells + 1
		var right_a := left_a + cells
		var right_c := left_c + cells
		# x = -half_extent (outward -X)
		faces.append_array(PackedVector3Array([verts[left_a], bottom[left_a], verts[left_c],
			verts[left_c], bottom[left_a], bottom[left_c]]))
		# x = +half_extent (outward +X)
		faces.append_array(PackedVector3Array([verts[right_a], verts[right_c], bottom[right_a],
			verts[right_c], bottom[right_c], bottom[right_a]]))
	src.add_faces(faces, Transform3D.IDENTITY)
	for obstruction in obstructions:
		src.add_projected_obstruction(obstruction.outline, float(obstruction.bottom),
			float(obstruction.height), false)
	return src


## Add a small terrain tile to the shared navigation map (e.g. an outpost's
## walkable clearing). The local frame must map +Y to ground-up at `center`.
func add_terrain_region(terrain: DesertTerrain, center: Vector3, half_extent: float = 40.0,
	step: float = 2.0, frame: Transform3D = Transform3D.IDENTITY,
	obstructions: Array = []) -> NavigationRegion3D:
	var nm := NavigationMesh.new()
	nm.cell_size = float(settings.cell_size)
	nm.cell_height = float(settings.cell_height)
	nm.agent_radius = float(settings.agent_radius)
	nm.agent_height = float(settings.agent_height)
	nm.agent_max_climb = float(settings.agent_max_climb)
	nm.agent_max_slope = float(settings.agent_max_slope)
	nm.filter_baking_aabb = AABB(Vector3(-half_extent, -80.0, -half_extent),
		Vector3(half_extent * 2.0, 160.0, half_extent * 2.0))
	NavigationServer3D.bake_from_source_geometry_data(nm,
		terrain_source(terrain, center, half_extent, step, frame, obstructions))
	var tile := NavigationRegion3D.new()
	tile.name = "DesertNavRegion"
	tile.navigation_mesh = nm
	tile.transform = frame
	add_child(tile)
	desert_regions.append(tile)
	return tile


## Issue #193: a region baked from triangles in a frame of their own (the Remnant
## cruiser's decks, walls and ramps, in its frame), limited to `bounds` (in it). It
## bakes on a worker thread and joins the shared map when done; `done` (optional)
## gets the region. The frame must map +Y to the region's up.
func add_faces_region(faces: PackedVector3Array, frame: Transform3D, bounds: AABB,
		done: Callable = Callable()) -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = float(settings.cell_size)
	nm.cell_height = float(settings.cell_height)
	nm.agent_radius = float(settings.agent_radius)
	nm.agent_height = float(settings.agent_height)
	nm.agent_max_climb = float(settings.agent_max_climb)
	nm.agent_max_slope = float(settings.agent_max_slope)
	nm.filter_baking_aabb = bounds
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _on_faces_baked.bind(nm, frame, done))


func _on_faces_baked(nm: NavigationMesh, frame: Transform3D, done: Callable) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		call_deferred("_on_faces_baked", nm, frame, done)
		return
	if not is_inside_tree():
		return
	var tile := NavigationRegion3D.new()
	tile.name = "FacesNavRegion"
	tile.navigation_mesh = nm
	tile.transform = frame
	add_child(tile)
	desert_regions.append(tile)
	if done.is_valid():
		done.call(tile)


## Every box as 12 triangles in the frame its xf is given in (the corner and
## winding order box_faces uses). `boxes`: [{ size, xf }].
static func oriented_box_faces(boxes: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for b in boxes:
		var xf: Transform3D = b.xf
		var half: Vector3 = (b.size as Vector3) * 0.5
		var c := []
		for i in 8:
			c.append(xf * Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1)))
		for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			faces.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))
	return faces


## Build the region and bake. `async` = on a worker thread (the live game).
## The town may override any bake setting with a "nav" block in its data.
func build(town, async: bool = true) -> void:
	var over: Dictionary = town.data.get("nav", {}) if town.data is Dictionary else {}
	for k in over:
		settings[k] = over[k]
	is_ready = false
	navmesh = make_navmesh(town)
	var map := get_world_3d().navigation_map
	# The map's cells must match the mesh's, or the server warns and rounds.
	NavigationServer3D.map_set_cell_size(map, float(settings.cell_size))
	NavigationServer3D.map_set_cell_height(map, float(settings.cell_height))
	var src := source_geometry(town)
	_bake_start = Time.get_ticks_usec()
	if async:
		NavigationServer3D.bake_from_source_geometry_data_async(navmesh, src, _on_baked)
	else:
		NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
		_on_baked()


func _on_baked() -> void:
	# The async callback can arrive off the main thread; hand the result back.
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		call_deferred("_on_baked")
		return
	bake_ms = (Time.get_ticks_usec() - _bake_start) / 1000.0
	# The region joins the map only now, already holding the finished mesh. A
	# region added empty and filled later (after an async bake) was never picked
	# up by the map on Godot 4.7.
	region = NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = navmesh
	add_child(region)
	_wait_for_map()


## The server folds a new mesh into the map on its next sync, so a path query
## straight after assigning it comes back empty. The map also ticks once for the
## empty region, so "the iteration changed" is not enough: wait until the map
## says a point of our mesh belongs to our region.
func _wait_for_map() -> void:
	var map := get_world_3d().navigation_map
	var probe: Vector3 = navmesh.vertices[0] if navmesh.vertices.size() > 0 else Vector3.ZERO
	var frames := 0
	while NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_closest_point_owner(map, probe) != region.get_rid():
		frames += 1
		if frames > 600:
			push_warning("TownNav: the navigation map never picked up the town mesh")
			return
		await get_tree().physics_frame
	is_ready = true
	baked.emit()


func polygon_count() -> int:
	return navmesh.get_polygon_count() if navmesh != null else 0


## A walkable path from `from` to `to`, simplified to its corners. Both ends are
## snapped to the mesh. Empty until the bake is in.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if navmesh == null or region == null or not region.is_inside_tree():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)


## The nearest point on the mesh (Vector3.INF before the bake is in).
func closest(p: Vector3) -> Vector3:
	if not is_ready:
		return Vector3.INF
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
