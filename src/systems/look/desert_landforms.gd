class_name DesertLandforms
extends Node3D
## Mesas, hoodoos and boulders on the desert around the playable town, so the sand
## outside the gate leads somewhere and the horizon is not empty. Same recipes as
## the beauty corner's `_build_landforms` (the beauty corner is the art reference
## and is not edited, so this is a copy driven by content/look/desert_landforms.json).
##
## Mesas and hoodoos are solid (the player can walk up to them). Boulders are one
## MultiMesh to draw, and (issue #93) each also has its own convex collider, so you
## can stand on them; `boulders` lists them for WorldGround, where the low ones are
## ramps for a speeder and the tall ones stop it.

const DATA_PATH := "res://content/look/desert_landforms.json"
const MESA_BURY := 2.0             ## sink the broad feet into the sand, not on top of it

var data: Dictionary = {}
var solid_count := 0          ## bodies added (read by tests)
var boulder_count := 0
var boulder_spots := PackedVector3Array()   ## where they went (the renderer may not say)
## { center: Vector3 (on the ground), up, radius, height } for WorldGround.add_boulders.
var boulders: Array = []
## The ball's mesas where they went, { map: Vector2, radius, height } each, and
## on which planet, for the F11 map's ground (GlobeTerrain): kept after the scene
## goes, so the map can show that planet's ground from another one.
static var mesa_spots: Array = []
static var mesa_planet := ""

## Made once a session: the port is built again when you fly home from the moon,
## and its rocks never change (~110 ms of noise, meshes and colliders on that
## handoff's first frame). Rock meshes by recipe, their trimesh shapes by mesh, and
## the boulders' hulls by where they stand.
static var _meshes := {}
static var _shapes := {}
static var _boulder_hulls := {}


static func load_data(path: String = DATA_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DesertLandforms: cannot open %s" % path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Issue #64: more places to keep clear, [Vector2 centre, radius] each (the
## Remnant's desert outposts: the world's landmarks with a "clear" radius).
var clear_circles: Array = []


## `keep_out` = the town's floor area (xz); nothing is placed on or near it.
func build(terrain: DesertTerrain, mats: LookMaterials, keep_out: Rect2) -> void:
	name = "Landforms"
	data = load_data()
	if data.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("seed", 4242))
	var margin := float(data.get("keep_out_margin", 25.0))
	var clear := keep_out.grow(margin)
	var solid := bool(data.get("collision", true))
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.fractal_octaves = 3

	# On the home ball use small mesas distributed by latitude/longitude; flat
	# worlds keep the original nearby beauty-corner arrangement.
	if terrain is PlanetTerrain and data.has("planet_mesas"):
		_build_planet_mesas(terrain as PlanetTerrain, mats, clear, noise, rng, solid)
	else:
		_build_local_mesas(terrain, mats, clear, noise, rng, solid)

	# Hoodoos remain a close-to-town ring: [x, z, radius, height].
	for hd in data.get("hoodoos", []):
		var r: float = hd[2]
		var h: float = hd[3]
		if _hits(clear, hd[0], hd[1], r) or _in_circles(hd[0], hd[1], r):
			continue
		noise.frequency = 1.4 / r
		var base := _cyl(r * 0.55, r, h, 16)
		base.rings = 10
		var g := _ground(terrain, hd[0], hd[1])
		var gy := _ground_h(terrain, g, hd[0], hd[1])
		var mat := mats.rock(gy, 0.35)
		var col := _add(_cached("hoodoo/%s/%s/%s" % [r, h, hd[0]], func(): return LookMeshKit.rock(base, noise, 0.28, 3.0, float(hd[0]), 0.4)),
			mat, g, h * 0.45)
		var cap := SphereMesh.new()
		cap.radius = r * 0.9
		cap.height = r * 0.8
		cap.radial_segments = 12
		cap.rings = 6
		_add(_cached("hoodoo_cap/%s/%s" % [r, hd[1]], func(): return LookMeshKit.rock(cap, noise, 0.3, 0.0, float(hd[1]))), mat, g, h * 0.95,
			Vector3(0, 0, rng.randf_range(-12, 12)))
		if solid:
			_solid(col)

	# Boulders, scattered with a MultiMesh: one draw call for hundreds.
	var b: Dictionary = data.get("boulders", {})
	var want := int(b.get("count", 0))
	if want <= 0:
		return
	var boulder_src := BoxMesh.new()
	boulder_src.size = Vector3(2.0, 1.6, 1.8)
	boulder_src.subdivide_width = 2
	boulder_src.subdivide_height = 2
	boulder_src.subdivide_depth = 2
	noise.frequency = 0.9
	var xforms: Array[Transform3D] = []
	var min_dist := float(b.get("min_dist", 165.0))
	var spread := float(b.get("spread", 1500.0))
	for i in want:
		var ang := rng.randf() * TAU
		var dist := min_dist + pow(rng.randf(), 1.6) * spread
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var s := rng.randf_range(0.5, 1.0) * (1.0 + pow(rng.randf(), 3.0) * 5.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.8, 1.3)))
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		if _hits(clear, x, z, s * 2.0) or _in_circles(x, z, s * 2.0):
			continue
		var g := _ground(terrain, x, z)
		xforms.append(Transform3D(g.basis * basis, g.origin + g.basis.y * (-s * 0.25)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cached("boulder", func(): return LookMeshKit.rock(boulder_src, noise, 0.4, 0.0, 3.0))
	if solid:
		_solid_boulders(mm.mesh, xforms)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	boulder_count = xforms.size()
	for x in xforms:
		boulder_spots.append(x.origin)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Boulders"
	mmi.multimesh = mm
	mmi.material_override = mats.rock(0.0, 1.2)
	add_child(mmi)
	if terrain is PlanetTerrain:
		_on_ball((terrain as PlanetTerrain).sphere)


func _build_local_mesas(terrain: DesertTerrain, mats: LookMaterials, clear: Rect2,
		noise: FastNoiseLite, rng: RandomNumberGenerator, solid: bool) -> void:
	# [x, z, radius, height] entries remain for flat-world beauty corners.
	for m in data.get("mesas", []):
		var r: float = m[2]
		var h: float = m[3]
		if _hits(clear, m[0], m[1], r) or _in_circles(m[0], m[1], r):
			continue
		var so := float(m[0]) * 0.01 + float(m[1]) * 0.003
		var mesh := _cached("mesa/%s/%s/%s" % [r, h, so], func(): return _mesa_mesh(r, h, noise, so))
		var g := _ground(terrain, m[0], m[1])
		var gy := _ground_h(terrain, g, m[0], m[1])
		var mi := _add(mesh, mats.rock(gy, 0.11), g, h * 0.46 - MESA_BURY,
			Vector3(0, rng.randf_range(0, 360), 0))
		if solid:
			_solid(mi)


func _build_planet_mesas(terrain: PlanetTerrain, mats: LookMaterials, clear: Rect2,
		noise: FastNoiseLite, rng: RandomNumberGenerator, solid: bool) -> void:
	var sp := terrain.sphere
	mesa_spots = []
	mesa_planet = GameFlow.current_planet_id()
	for m in data.get("planet_mesas", []):
		var map := sp.map_from_lat_lon(float(m[0]), float(m[1]))
		var radius := float(m[2])
		var height := float(m[3])
		if _hits(clear, map.x, map.y, radius) or _in_circles(map.x, map.y, radius):
			continue
		var so := float(m[0]) * 0.01 + float(m[1]) * 0.003
		var mesh := _cached("mesa/%s/%s/%s" % [radius, height, so], func(): return _mesa_mesh(radius, height, noise, so))
		var g := _ground(terrain, map.x, map.y)
		var gy := _ground_h(terrain, g, map.x, map.y)
		var placed := _add(mesh, mats.rock(gy, 0.11), g, height * 0.46 - MESA_BURY,
			Vector3(0, rng.randf_range(0, 360), 0))
		if solid:
			_solid(placed)
		mesa_spots.append({ "map": map, "radius": radius, "height": height })


## The rock shader's ground height on the ball is metres above the bare ball.
static func _ground_h(terrain: DesertTerrain, g: Transform3D, x: float, z: float) -> float:
	if terrain is PlanetTerrain:
		return (terrain as PlanetTerrain).sphere.altitude(g.origin)
	return terrain.height_at(x, z)


## Every rock material here: strata and dusk follow the ball (issue #77).
func rock_materials() -> Array:
	var out: Array = []
	for n in find_children("*", "GeometryInstance3D", true, false):
		var m = (n as GeometryInstance3D).material_override
		if m is ShaderMaterial and not out.has(m):
			out.append(m)
	return out


func _on_ball(sp: PlanetSphere) -> void:
	for m in rock_materials():
		m.set_shader_parameter("planet_center", sp.center)
		m.set_shader_parameter("planet_radius", sp.radius)
		m.set_shader_parameter("dusk_strength", 0.35)


static func _hits(r: Rect2, x: float, z: float, radius: float) -> bool:
	return r.grow(radius).has_point(Vector2(x, z))


func _in_circles(x: float, z: float, radius: float) -> bool:
	for c in clear_circles:
		if (c[0] as Vector2).distance_to(Vector2(x, z)) < float(c[1]) + radius:
			return true
	return false


func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## A broad, weathered plateau with broken shelves and cliff-cut gullies. The
## outline stays inside WorldGround's existing mesa column, so the improved
## silhouette does not change the ship's conservative landmark collision.
static func _mesa_mesh(radius: float, height: float, noise: FastNoiseLite, seed_offset: float) -> ArrayMesh:
	const SEGMENTS := 64
	const PROFILE := [
		Vector2(0.00, 0.76), Vector2(0.10, 0.84), Vector2(0.22, 0.82),
		Vector2(0.31, 0.78), Vector2(0.35, 0.73), Vector2(0.49, 0.72),
		Vector2(0.54, 0.67), Vector2(0.67, 0.66), Vector2(0.71, 0.61),
		Vector2(0.84, 0.60), Vector2(0.88, 0.56), Vector2(0.98, 0.55),
		Vector2(1.00, 0.52)
	]
	noise.frequency = 1.0
	var rings: Array[PackedVector3Array] = []
	for ring in PROFILE:
		var row := PackedVector3Array()
		var t := float(ring.x)
		var base_radius := float(ring.y)
		for i in SEGMENTS:
			var angle := TAU * float(i) / SEGMENTS
			var ca := cos(angle)
			var sa := sin(angle)
			var broad := noise.get_noise_2d(ca * 2.0 + seed_offset, sa * 2.0 + seed_offset)
			var fine := noise.get_noise_3d(ca * 5.0 + seed_offset, t * 3.0, sa * 5.0 + seed_offset)
			# Vertical flutes are strongest on the cliff face, not the broad cap.
			var cliff_band := smoothstep(0.12, 0.30, t) * (1.0 - smoothstep(0.72, 0.92, t))
			var gully := pow(maxf(0.0, cos(angle * 6.0 + broad * 0.55)), 8.0) * 0.045 * cliff_band
			var radial := base_radius + broad * 0.026 + fine * 0.009 - gully
			var cap_wave := 1.0 - smoothstep(0.92, 1.0, t)
			var y_noise := (broad * 0.012 + fine * 0.006) * cap_wave
			row.append(Vector3(
				ca * radius * radial,
				(t - 0.5) * height * 0.92 + y_noise * height,
				sa * radius * radial
			))
		rings.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for j in rings.size() - 1:
		for i in SEGMENTS:
			var next := (i + 1) % SEGMENTS
			var radial := Vector3(
				cos(TAU * (float(i) + 0.5) / SEGMENTS), 0.0,
				sin(TAU * (float(i) + 0.5) / SEGMENTS)
			)
			LookMeshKit.add_quad(st, rings[j][i], rings[j][next],
				rings[j + 1][next], rings[j + 1][i], radial)
	var cap_center := Vector3.ZERO
	for point in rings[-1]:
		cap_center += point
	cap_center /= SEGMENTS
	for i in SEGMENTS:
		var next := (i + 1) % SEGMENTS
		LookMeshKit.add_tri(st, cap_center, rings[-1][i], rings[-1][next], Vector3.UP)
	var base_center := Vector3.ZERO
	for point in rings[0]:
		base_center += point
	base_center /= float(SEGMENTS)
	for i in SEGMENTS:
		var next := (i + 1) % SEGMENTS
		LookMeshKit.add_tri(st, base_center, rings[0][next], rings[0][i], Vector3.DOWN)
	return st.commit()


## Where a landform at map (x, z) stands: the ground there, y along its up. On the
## home planet's ball (issue #77) that leans with the ground; on a flat desert it is
## just the height at x, z.
static func _ground(terrain: DesertTerrain, x: float, z: float) -> Transform3D:
	if terrain is PlanetTerrain:
		var sp: PlanetSphere = (terrain as PlanetTerrain).sphere
		var at := sp.surface_at(x, z)
		return Transform3D(PlanetSphere.tilt_to(sp.up_at(at)), at)
	return Transform3D(Basis.IDENTITY, Vector3(x, terrain.height_at(x, z), z))


## `up` metres above the ground frame g, turned by rot_deg within it.
func _add(mesh: Mesh, mat: Material, g: Transform3D, up: float, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(g.basis * Basis.from_euler(rot_deg * PI / 180.0), g.origin + g.basis.y * up)
	add_child(mi)
	return mi


## One static body per boulder: a convex hull of the very rock mesh drawn there (its
## points put through that boulder's transform), so what you stand on is what you see.
func _solid_boulders(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var key := "%d/%s/%s" % [xforms.size(), xforms[0], xforms[-1]] if not xforms.is_empty() else ""
	var made: Array = _boulder_hulls.get(key, [])      # [shape, top, rad] per rock
	if made.size() != xforms.size():
		made = _boulder_shapes(mesh, xforms)
		_boulder_hulls[key] = made
	var root := StaticBody3D.new()
	root.name = "BoulderColliders"
	add_child(root)
	for k in xforms.size():
		var xf := xforms[k]
		var shape: Shape3D = made[k][0]
		var top: float = made[k][1]
		var rad: float = made[k][2]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = xf.origin
		root.add_child(cs)
		# Up: the ground's (the transform also leans and turns the rock a little).
		var up := Vector3.UP
		if PlanetSphere.current != null:
			up = PlanetSphere.current.up_at(xf.origin)
		# Measured from the rock's origin, a little under the sand; the ground under
		# it counts wherever it is higher.
		boulders.append({ "center": xf.origin, "up": up, "radius": rad * 0.85, "height": top })


## One convex hull per boulder: the very rock mesh drawn there (its points put
## through that boulder's transform), with its height and reach along its up.
static func _boulder_shapes(mesh: Mesh, xforms: Array[Transform3D]) -> Array:
	var pts := PackedVector3Array()
	var seen := {}
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var key := v.snapped(Vector3.ONE * 0.01)
		if not seen.has(key):
			seen[key] = true
			pts.append(v)
	var out: Array = []
	for xf in xforms:
		var hull := PackedVector3Array()
		hull.resize(pts.size())
		var top := 0.0
		var rad := 0.0
		for i in pts.size():
			var w: Vector3 = xf.basis * pts[i]
			hull[i] = w
			top = maxf(top, w.dot(xf.basis.y.normalized()))
			rad = maxf(rad, (w - xf.basis.y.normalized() * w.dot(xf.basis.y.normalized())).length())
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		out.append([shape, top, rad])
	return out


## The same as mi.create_trimesh_collision(), with the shape made once a session.
func _solid(mi: MeshInstance3D) -> void:
	var shape: Shape3D = _shapes.get(mi.mesh)
	if shape == null:
		shape = mi.mesh.create_trimesh_shape()
		_shapes[mi.mesh] = shape
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	solid_count += 1


static func _cached(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]
