extends RefCounted
## Issue #315: what is in the space station's floors (StationHull is the shell).
## One floor at a time, by its "use" in the station config's "fill" block:
##   homes     the open homes (StationHull.rooms_of: the rest are locked) each a
##             long studio: a lounge by the door (rug, couch, table, lamp, screen,
##             shelves), a kitchen half way (counter, fridge, table and stools), a
##             partition with a doorway, a bedroom by the big window onto space
##             (bed, nightstand, wardrobe, plant), light panels in the ceiling
##   market    rings of the town's market stalls (TownMarket: tables, canopies,
##             wares) from the walkway out to the glass, and the town's small huts
##             in the station's grey metal in the outer ring, with lanes kept clear
##             to every tunnel door
##   engines   the engine deck's rooms by turn ("rooms" in its block): reactors,
##             cargo holds (one with the drop hatch, sealed until #317), pump
##             rooms and workshops; pipes round the walkway's ceiling
##
## The render rules (docs/station/STATION_FILL.md): every part goes through the
## town's building kit (TownBuildings) and is then merged into one mesh a
## material (_collect: boxes, cylinders and spheres built from their own numbers,
## never read back from the GPU); the kit's own ArrayMeshes and the stalls' cloth
## are one MultiMesh a mesh and material. A whole floor is a few dozen draw calls.
## No lights, only glowing materials, and nothing casts a shadow. The few things
## you would walk into (counters, beds, couches, stall tables, huts, machines) get
## a box collider in the floor's one Props body; the rest is only drawn.
## SpaceStation builds a floor a little each physics tick (begin, step: a time
## budget a tick, so nothing hitches) and shows it only near the camera.
##
## Pure layout in each piece's frame: x out from the tower's middle (a room's or a
## stall's radius), y up from the floor, z across. Numbers are the config's.

const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const TownMarket := preload("res://src/systems/world/town_market.gd")
const StationRemnant := preload("res://src/systems/world/station_remnant.gd")
const UP := Vector3.UP
const FABRICS := [Color("#2f5d8a"), Color("#7a3b2e"), Color("#4f6b3a"), Color("#5b3f6e"), Color("#8a6a2e"), Color("#2f6f6a")]
const HUTS := ["hut_block", "hut_round", "hut_stepped"]
const PAINTS := [Color("#8a4a32"), Color("#3f6f6a"), Color("#b08a3a"), Color("#6a6e72"), Color("#7a3b4e"), Color("#4a5a7a")]
const NEONS := [Color("#ff4fa3"), Color("#38e1ff"), Color("#ffd23f"), Color("#7dff6a")]
const VELVETS := [Color("#5a1e1a"), Color("#2e1e4a"), Color("#1e3a44"), Color("#4a1e36")]

var kit: TownBuildings
var mats: LookMaterials
var hull: StationHull
var cfg: Dictionary = {}            ## the station's "fill" block
var market: TownMarket
var finish: Callable                ## finish name -> the station's own material (SpaceStation._mat)
var counts := {}                    ## what was placed, by kind (tests, review)
var draws := 0                      ## meshes the last floor ended up as (review)
var nets := {}                      ## "<tower>/<floor>" -> { alleys: [angle], stops: [{ a, r, face_r }] }: where the crowd walks
var slowest_ms := 0.0               ## the longest single job (review)
var slowest := ""
var _rng := RandomNumberGenerator.new()
var _glows := {}
var _q: Array = []                  ## the floor being built: what is left to do (Callables)
var group := ""                     ## the Remnant deck's faction materials' group (faction_mats)
var faction := {}                   ## role -> its registered material (LookMaterials.repaint repaints them)
var _parent: Node3D


func _init(building_kit: TownBuildings, station_hull: StationHull, station_finish: Callable) -> void:
	kit = building_kit
	kit.trim = station_finish.call("trim")         # the huts' and stalls' trim in the station's metal
	kit.clutter = false                            # no jars by the huts' doors: their plaster is a shader the station never compiles
	mats = kit.mats
	hull = station_hull
	cfg = hull.cfg.get("fill", {})
	finish = station_finish
	market = TownMarket.new(kit)


## The fill block of floor `floor_id` ({} when the floor is left empty).
func floor_cfg(floor_id: String) -> Dictionary:
	return cfg.get("floors", {}).get(floor_id, {})


## Start building floor `i` of tower `t` under `parent` (which sits in the
## station's frame); step() does the work, a little at a time. False when the
## floor has nothing to dress.
func begin(parent: Node3D, t: Dictionary, i: int) -> bool:
	var f: Dictionary = t.floors[i]
	var fc := floor_cfg(str(f.id))
	_rng.seed = hash(str(t.id) + "/" + str(f.id))
	_parent = parent
	_q = []
	match str(fc.get("use", "")):
		"homes":
			_homes(t, f, fc)
		"market":
			_market(parent, t, f, fc)
		"engines":
			_engines(t, f, fc)
		"favela":
			_favela(t, f, fc)
		"suites":
			_suites(t, f, fc)
		"remnant":
			_remnant(t, f)
		_:
			return false
	_q.append(_collect)
	return true


## Do the floor's work for up to `budget_ms`; true once it is all built.
func step(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	while not _q.is_empty():
		var job: Callable = _q.pop_front()
		var j0 := Time.get_ticks_usec()
		job.call()
		var ms := (Time.get_ticks_usec() - j0) / 1000.0
		if ms > slowest_ms:
			slowest_ms = ms
			slowest = job.get_method()
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return _q.is_empty()


## Build the whole floor now (tests, tools).
func dress(parent: Node3D, t: Dictionary, i: int) -> void:
	if begin(parent, t, i):
		while not step(1000.0):
			pass


## Every primitive part queued for the floor, by material, merged into one mesh
## each a few thousand vertices at a time (the kit's own meshes, which have no CPU
## copy, a MultiMesh each); then the colliders, the cloth, and no shadows.
func _collect() -> void:
	var by_mat := {}
	for key in kit._groups:
		var g: Array = kit._groups[key]
		if not mergeable(g[0]):
			_q.append(_multimesh.bind(g[0], g[1], g[2]))     # an ArrayMesh: no CPU copy to merge from
			continue
		var mid: int = (g[1] as Material).get_instance_id()
		if not by_mat.has(mid):
			by_mat[mid] = [g[1], []]
		for xf in g[2]:
			by_mat[mid][1].append([g[0], xf])
	kit._groups.clear()
	draws = 0
	var chunk := int(cfg.get("merge_verts", 4000))
	for mid in by_mat:
		var acc := { "v": [], "n": [], "uv": [] }    # transformed pieces, joined once at commit
		var part: Array = []
		var n := 0
		for it in by_mat[mid][1]:
			part.append(it)
			n += 1
			if n >= chunk / 60:            # about chunk vertices of small props
				_q.append(_append.bind(acc, part))
				part = []
				n = 0
		if not part.is_empty():
			_q.append(_append.bind(acc, part))
		_q.append(_commit.bind(acc, by_mat[mid][0]))
	_q.append(_finish)


var _flats := {}                    ## mesh instance id -> [vertices, normals, uvs], unindexed


## A box's, cylinder's or sphere's triangles as plain arrays, made once a mesh from
## its own numbers. Not read back from the mesh: that waits on the GPU (about 8 ms
## a mesh, however small), even for a primitive. Boxes keep BoxMesh's UV layout
## (its six faces on a 3 x 2 grid), which the station's screens are painted on.
func _flat(mesh: Mesh) -> Array:
	var k := mesh.get_instance_id()
	if _flats.has(k):
		return _flats[k]
	var out := [[], [], []]                 # plain Arrays while building (a packed one read out of an Array is a copy)
	if mesh is BoxMesh:
		_box_tris(out, (mesh as BoxMesh).size * 0.5)
	elif mesh is CylinderMesh:
		var c := mesh as CylinderMesh
		_cyl_tris(out, c.top_radius, c.bottom_radius, c.height, c.radial_segments, c.cap_top, c.cap_bottom)
	elif mesh is SphereMesh:
		var sm := mesh as SphereMesh
		_sphere_tris(out, sm.radius, sm.height, sm.radial_segments, sm.rings, sm.is_hemisphere)
	_flats[k] = [PackedVector3Array(out[0]), PackedVector3Array(out[1]), PackedVector2Array(out[2])]
	return _flats[k]


## Only the shapes _flat can build are merged; the rest are drawn as MultiMeshes.
static func mergeable(mesh: Mesh) -> bool:
	return mesh is BoxMesh or mesh is CylinderMesh or mesh is SphereMesh


## A triangle, clockwise seen from `n`'s side (Godot's front faces).
static func _tri(out: Array, a: Vector3, b: Vector3, c: Vector3, n: Array, uv: Array) -> void:
	var swap := (b - a).cross(c - a).dot((n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)) > 0.0
	var order := [0, 2, 1] if swap else [0, 1, 2]
	var pts := [a, b, c]
	for i in order:
		(out[0] as Array).append(pts[i])
		(out[1] as Array).append(n[i])
		(out[2] as Array).append(uv[i])


static func _quad(out: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Array, uv: Array) -> void:
	_tri(out, a, b, c, [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]])
	_tri(out, a, c, d, [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]])


static func _box_tris(out: Array, h: Vector3) -> void:
	# face: normal, its two axes across, its cell on BoxMesh's 3 x 2 UV grid
	var faces := [[Vector3.BACK, Vector3.RIGHT, Vector3.UP, Vector2(0, 0)], [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, Vector2(1, 0)],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP, Vector2(2, 0)], [Vector3.LEFT, Vector3.BACK, Vector3.UP, Vector2(0, 1)],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, Vector2(1, 1)], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, Vector2(2, 1)]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var cell: Vector2 = f[3]
		var uv := func(x: float, y: float) -> Vector2: return Vector2((cell.x + x) / 3.0, (cell.y + 1.0 - y) / 2.0)
		_quad(out, c - du - dv, c + du - dv, c + du + dv, c - du + dv, [n, n, n, n],
			[uv.call(0, 0), uv.call(1, 0), uv.call(1, 1), uv.call(0, 1)])


static func _cyl_tris(out: Array, rt: float, rb: float, h: float, seg: int, cap_top: bool, cap_bottom: bool) -> void:
	var hy := h * 0.5
	var slope := (rb - rt) / maxf(h, 0.001)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		_quad(out, d0 * rb - Vector3(0, hy, 0), d1 * rb - Vector3(0, hy, 0), d1 * rt + Vector3(0, hy, 0), d0 * rt + Vector3(0, hy, 0),
			[n0, n1, n1, n0], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)])
		if cap_top and rt > 0.0:
			_tri(out, Vector3(0, hy, 0), d0 * rt + Vector3(0, hy, 0), d1 * rt + Vector3(0, hy, 0), [Vector3.UP, Vector3.UP, Vector3.UP],
				[Vector2(0.5, 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)])
		if cap_bottom and rb > 0.0:
			_tri(out, Vector3(0, -hy, 0), d0 * rb - Vector3(0, hy, 0), d1 * rb - Vector3(0, hy, 0), [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN],
				[Vector2(0.5, 0.5), Vector2(0.5 + d0.x * 0.5, 0.5 + d0.z * 0.5), Vector2(0.5 + d1.x * 0.5, 0.5 + d1.z * 0.5)])


static func _sphere_tris(out: Array, r: float, h: float, seg: int, rings: int, hemi: bool) -> void:
	var sy := h / (2.0 * r) if r > 0.0 else 1.0           # SphereMesh squashes to its height
	var top := PI * 0.5
	var bot := 0.0 if hemi else -PI * 0.5
	var p := func(i: int, j: int) -> Vector3:
		var lat := lerpf(top, bot, float(j) / rings)
		var lon := TAU * i / seg
		return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	for i in seg:
		for j in rings:
			var a: Vector3 = p.call(i, j)
			var b: Vector3 = p.call(i + 1, j)
			var c: Vector3 = p.call(i + 1, j + 1)
			var d: Vector3 = p.call(i, j + 1)
			var sc := Vector3(r, r * sy, r)
			var uv := [Vector2(float(i) / seg, float(j) / rings), Vector2(float(i + 1) / seg, float(j) / rings),
				Vector2(float(i + 1) / seg, float(j + 1) / rings), Vector2(float(i) / seg, float(j + 1) / rings)]
			_quad(out, a * sc, b * sc, c * sc, d * sc, [a, b, c, d], uv)


## Parts `items` ([mesh, transform]) onto the pieces `acc` of their material.
func _append(acc: Dictionary, items: Array) -> void:
	for it in items:
		var f := _flat(it[0])
		var xf: Transform3D = it[1]
		(acc.v as Array).append(xf * (f[0] as PackedVector3Array))
		(acc.n as Array).append(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * (f[1] as PackedVector3Array))
		(acc.uv as Array).append(f[2])


## One mesh and material drawn `xfs` times: one draw call.
func _multimesh(mesh: Mesh, mat: Material, xfs: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fill_mm_%d" % draws
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent.add_child(mmi)
	draws += 1


func _commit(acc: Dictionary, mat: Material) -> void:
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	for p in acc.v:
		v.append_array(p)
	for p in acc.n:
		nn.append_array(p)
	for p in acc.uv:
		uv.append_array(p)
	if v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nn
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Fill_%d" % draws
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent.add_child(mi)
	draws += 1


func _finish() -> void:
	kit.flush(_parent)                 # nothing left to draw: only the Props body
	merge_cloth(_parent)


## Nothing in the fill casts a shadow.
func _no_shadows() -> void:
	for c in _parent.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A fixed glow (not driven by the day's lamps), one material a colour.
func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := c.to_html() + str(energy)
	if not _glows.has(key):
		var m := mats.glow(c)
		m.emission_energy_multiplier = energy
		_glows[key] = m
	return _glows[key]


func _m(name: String) -> Material:
	return finish.call(name)


func _count(kind: String) -> void:
	counts[kind] = int(counts.get(kind, 0)) + 1


## The frame of a piece at angle `a` round tower `t`'s middle on floor height `y`:
## x out along the angle, y up, z across (StationHull's own boxes' frame).
static func radial(t: Dictionary, y: float, a: float) -> Transform3D:
	var c: Vector2 = t.c
	var x := Vector3(cos(a), 0, sin(a))
	return Transform3D(Basis(x, UP, x.cross(UP)), Vector3(c.x, y, c.y))


## A part in the current frame (kit._xf); `solid` gives it a collider.
func _p(mesh: Mesh, mat: Material, pos: Vector3, solid := false, basis := Basis.IDENTITY) -> void:
	if solid:
		kit.solid_part(mesh, mat, pos, basis)
	else:
		kit.part(mesh, mat, pos, basis)


# ------------------------------------------------------------------ homes

## Each open home on the floor: a long studio from the door on the walkway out
## to the window.
func _homes(t: Dictionary, f: Dictionary, fc: Dictionary) -> void:
	var r0 := hull.gap_r + hull.walk + 0.4                   # inside the door
	var r1 := float(f.r) - StationHull.WALL                  # the window
	var k := 0
	for room in hull.rooms_of(str(t.id), str(f.id)):
		if not bool(room.open):
			continue
		_q.append(_home.bind(radial(t, float(f.y), float(room.a)), r0, r1, float(room.half), k, fc))
		k += 1
		_count("home")


## Half the room's width at radius `r`, inside its divider walls.
static func _half_w(r: float, half: float) -> float:
	return r * tan(half) - StationHull.INNER_WALL - 0.15


func _home(at: Transform3D, r0: float, r1: float, half: float, k: int, fc: Dictionary) -> void:
	kit._xf = at
	var depth := r1 - r0
	var fabric: Color = FABRICS[k % FABRICS.size()]
	var accent: Color = FABRICS[(k + 3) % FABRICS.size()]
	var cloth := mats.cloth(fabric)
	var trim := _m("trim")
	var wall := _m("wall")
	var ceil_y := hull.floor_h - 0.06
	var flip := 1.0 if k % 2 == 0 else -1.0                  # which wall the kitchen is on
	# The lounge, just inside the door: a rug, a couch facing the door, a low table, a lamp.
	var lr := r0 + depth * float(fc.get("lounge_at", 0.22))
	var lw := minf(_half_w(lr, half), 3.0)
	_p(kit.box(3.4, 0.02, lw * 1.5), mats.cloth(accent.darkened(0.35)), Vector3(lr, 0.01, 0))
	_p(kit.box(0.9, 0.45, 2.2), cloth, Vector3(lr + 1.0, 0.225, 0), true)
	_p(kit.box(0.25, 0.55, 2.2), cloth, Vector3(lr + 1.42, 0.72, 0))
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.9, 0.62, 0.2), cloth, Vector3(lr + 1.0, 0.31, s * 1.2))
	_p(kit.box(0.6, 0.38, 1.1), trim, Vector3(lr - 0.35, 0.19, 0), true)
	_lamp(Vector3(lr + 1.2, 0, flip * minf(1.7, lw)), kit.window_glow)
	_p(kit.box(1.6, 0.05, 0.5), kit.window_glow, Vector3(lr, ceil_y, 0))
	# The kitchen half way: a counter along one wall, its top, a cooktop, a sink,
	# cupboards over it, a fridge at its end; a table and two stools.
	var kr := r0 + depth * float(fc.get("kitchen_at", 0.45))
	var kw := _half_w(kr, half)
	var z := flip * (kw - 0.35)
	_p(kit.box(3.6, 0.9, 0.65), wall, Vector3(kr, 0.45, z), true)
	_p(kit.box(3.7, 0.05, 0.7), trim, Vector3(kr, 0.925, z))
	_p(kit.box(0.6, 0.012, 0.42), _glow(Color("#ff6a2a")), Vector3(kr - 0.9, 0.955, z))
	_p(kit.box(0.5, 0.02, 0.4), _m("console"), Vector3(kr + 0.8, 0.955, z))
	_p(kit.box(3.6, 0.7, 0.4), wall, Vector3(kr, 1.95, flip * (kw - 0.22)))
	_p(kit.box(0.8, 2.0, 0.7), _m("hull"), Vector3(kr + 2.3, 1.0, z), true)
	_p(kit.box(0.04, 0.6, 0.5), kit.door_glow, Vector3(kr + 1.88, 1.4, z))
	var tz := -flip * minf(1.0, kw * 0.4)
	_p(kit.box(1.0, 0.06, 1.0), trim, Vector3(kr, 0.75, tz))
	_p(kit.cyl(0.08, 0.08, 0.72, 6), trim, Vector3(kr, 0.36, tz), true)
	for s: float in [-1.0, 1.0]:
		_p(kit.cyl(0.2, 0.2, 0.45, 8), cloth, Vector3(kr + s * 0.75, 0.225, tz))
	_p(kit.box(1.6, 0.05, 0.5), kit.window_glow, Vector3(kr, ceil_y, 0))
	# A wall screen over the lounge and shelves by it, on the wall across from the kitchen.
	var sw := _half_w(lr + 1.0, half)
	_p(kit.box(1.8, 1.0, 0.06), _m("screen"), Vector3(lr - 0.2, 1.8, -flip * (sw - 0.05)))
	for q in 3:
		_p(kit.box(1.4, 0.05, 0.35), trim, Vector3(lr + 3.2, 0.9 + q * 0.55, -flip * (_half_w(lr + 3.2, half) - 0.2)))
		_p(kit.box(0.3, 0.25, 0.25), mats.cloth(FABRICS[(k + q) % FABRICS.size()]), Vector3(lr + 3.0 + q * 0.2, 1.05 + q * 0.55, -flip * (_half_w(lr + 3.2, half) - 0.25)))
	# A partition across the room with a doorway, between the living space and the
	# bedroom, lit along its top.
	var pr := r1 - float(fc.get("partition_from_window", 13.0))
	var pw := _half_w(pr, half) + 0.15
	var gap := 0.9                                           # half the doorway
	var seg := (pw - gap) * 0.5
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.18, 3.0, pw - gap), wall, Vector3(pr, 1.5, s * (gap + seg)), true)
		_p(kit.box(0.22, 0.06, pw - gap), kit.door_glow, Vector3(pr, 3.03, s * (gap + seg)))
	# The bed by the window, its head toward the door, a nightstand and its lamp.
	var br := r1 - float(fc.get("bed_from_window", 5.5))
	_p(kit.box(1.4, 2.2, 0.6), wall, Vector3(br - 2.4, 1.1, flip * (_half_w(br - 2.4, half) - 0.3)), true)
	_p(kit.box(0.04, 1.9, 0.02), trim, Vector3(br - 2.4, 1.1, flip * (_half_w(br - 2.4, half) - 0.61)))
	_p(kit.box(2.2, 0.35, 1.7), trim, Vector3(br, 0.175, 0), true)
	_p(kit.box(2.0, 0.22, 1.6), mats.cloth(Color("#d9d4c8")), Vector3(br, 0.46, 0))
	_p(kit.box(1.25, 0.07, 1.64), cloth, Vector3(br + 0.35, 0.6, 0))
	_p(kit.box(0.42, 0.12, 1.2), mats.cloth(Color("#ece6d8")), Vector3(br - 0.72, 0.62, 0))
	_p(kit.box(0.12, 0.95, 1.8), wall, Vector3(br - 1.12, 0.6, 0))
	_p(kit.box(0.45, 0.5, 0.45), trim, Vector3(br - 0.85, 0.25, -flip * 1.25))
	_p(kit.ball(0.12, 0.2, false, 8), kit.window_glow, Vector3(br - 0.85, 0.6, -flip * 1.25))
	_p(kit.box(1.6, 0.05, 0.5), kit.window_glow, Vector3(br, ceil_y, 0))
	# A plant in the window's corner.
	var plant_z := _half_w(r1 - 1.2, half) - 0.5
	_p(kit.cyl(0.26, 0.2, 0.5, 8), _m("hull"), Vector3(r1 - 1.2, 0.25, flip * plant_z), true)
	_p(kit.ball(0.5, 0.8, false, 8), mats.flat(Color("#3f6b34"), 0.8), Vector3(r1 - 1.2, 0.9, flip * plant_z))


## A floor lamp: a thin post and a glowing shade.
func _lamp(at: Vector3, glow: Material) -> void:
	_p(kit.cyl(0.03, 0.03, 1.4, 6), _m("trim"), at + Vector3(0, 0.7, 0))
	_p(kit.cyl(0.14, 0.2, 0.25, 8), glow, at + Vector3(0, 1.5, 0))


# ------------------------------------------------------------------ market

## Rings of stalls round the walkway, facing in (to the walkway or the aisle in
## front of them) or out, and huts in a ring of their own; nothing in a lane to
## any tunnel door.
func _market(parent: Node3D, t: Dictionary, f: Dictionary, fc: Dictionary) -> void:
	var y := float(f.y)
	var lanes := _lanes(t, f, fc)
	var net := _net(t, f, lanes)
	var stalls: Array = []
	var ri := 0
	for ring in fc.get("rings", []):
		var r := float(ring.get("r", 25.0))
		if r > float(f.r) - 2.0:
			continue
		if bool(ring.get("pack", false)):
			_pack_ring(t, y, ring, lanes, ri, net)
			ri += 1
			continue
		var every := float(ring.get("every_m", 7.0))
		var n := maxi(1, floori(TAU * r / every))
		var out := str(ring.get("face", "in")) == "out"
		var huts := bool(ring.get("huts", false))
		var size := Vector3(float(ring.get("depth", 1.2)), float(ring.get("height", 1.0)), float(ring.get("length", 3.0)))
		var start := float(ri) * 0.37                       # rings do not line up
		for k in n:
			var a := start + TAU * k / n
			if not _clear(a, r, size.z * 0.5 + 0.3, lanes):
				continue
			var xf := radial(t, y, a) * Transform3D(Basis.IDENTITY, Vector3(r, 0, 0))
			if not out:
				xf = xf * Transform3D(Basis(UP, PI), Vector3.ZERO)   # +X back toward the middle
			if huts and k % 2 == 0:
				_q.append(_hut.bind(xf, "%s_%s_hut_%d_%d" % [str(t.id), str(f.id), ri, k], ring, _rng.randi()))
				continue
			stalls.append({ "id": "%s_%s_stall_%d_%d" % [str(t.id), str(f.id), ri, k], "xf": xf, "size": size })
			kit.add_collider(xf * Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)), size)
			_stop(net, a, r, size.x, out)
			_count("stall")
		ri += 1
	var batch := 4
	var j := 0
	while j < stalls.size():
		_q.append(market.dress_at.bind(parent, stalls.slice(j, j + batch), j))
		j += batch


# ------------------------------------------------------------------ where people walk

## A floor's walking net for the crowd (StationCrowd): its clear lanes out from
## the walkway (alleys and tunnel lanes, angles), and the spots in front of every
## stall, booth and shack door, each on the aisle in front of its ring.
func _net(t: Dictionary, f: Dictionary, lanes: Array) -> Dictionary:
	var net := { "alleys": lanes.map(func(l): return float(l[0])), "stops": [] }
	nets[str(t.id) + "/" + str(f.id)] = net
	return net


## A customer's spot in front of a piece at angle `a`, ring radius `r`, `d` deep,
## its front facing out (`out`) or in: on the aisle a little past its front.
static func _stop(net: Dictionary, a: float, r: float, d: float, out: bool) -> void:
	if net.is_empty():
		return
	var aisle := r + d * 0.5 + 0.9 if out else r - d * 0.5 - 0.9
	(net.stops as Array).append({ "a": a, "r": aisle, "face_r": r })


## One of the town's small huts (a home among the stalls) in the station's own grey
## metal (its "wall" finish: no new shader to compile aboard), its door to the
## aisle; solid all through.
func _hut(xf: Transform3D, hid: String, ring: Dictionary, seed: int) -> void:
	_rng.seed = seed
	var look: String = HUTS[_rng.randi() % HUTS.size()]
	var w := _rng.randf_range(4.5, 5.5)
	var d := _rng.randf_range(4.0, 4.8)
	var hs: Array = ring.get("hut_h", [3.8, 4.6])
	var h := float(hs[_rng.randi() % hs.size()])          # a few heights, so the huts share their materials
	if look == "hut_round":
		d = w
	kit.build_at({ "id": hid, "look": look, "wall_mat": _m("wall") }, xf, d, w, h)
	kit.add_collider(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(d, h, w))
	_count("hut")


# ------------------------------------------------------------------ the favela

## A painted metal in one of a few colours (shared: a few materials a floor).
func _paint(k: int) -> Material:
	return mats.painted(PAINTS[absi(k) % PAINTS.size()], 0.7, 0.3)


## What a packed floor keeps clear, as [angle, half width in metres]: its tunnel
## doors (lane_half) and `alleys` radial alleys (alley_half) out from the walkway.
func _lanes(t: Dictionary, f: Dictionary, fc: Dictionary) -> Array:
	var out: Array = []
	for d in hull.door_angles(t, float(f.y)):
		out.append([float(d), float(fc.get("lane_half", 4.0))])
	var n := int(fc.get("alleys", 0))
	for k in n:
		out.append([float(fc.get("alley_start", 0.2)) + TAU * k / n, float(fc.get("alley_half", 1.3))])
	return out


static func _clear(a: float, r: float, half_w: float, lanes: Array) -> bool:
	for l in lanes:
		if absf(wrapf(a - float(l[0]), -PI, PI)) * r < float(l[1]) + half_w:
			return false
	return true


## The lower homes: rings of shacks, booths and the town's huts packed shoulder to
## shoulder, back to back in pairs with an alley between each pair, radial alleys
## out from the walkway, some shacks built on top of others, and cables, string
## lights and washing strung over the alleys.
func _favela(t: Dictionary, f: Dictionary, fc: Dictionary) -> void:
	var lanes := _lanes(t, f, fc)
	var net := _net(t, f, lanes)
	var rings: Array = fc.get("rings", [])
	for ri in rings.size():
		_pack_ring(t, float(f.y), rings[ri], lanes, ri, net)
	_q.append(_lines.bind(t, float(f.y), fc, lanes))


## One ring of packed pieces at `ring.r`, doors facing in (or out).
func _pack_ring(t: Dictionary, y: float, ring: Dictionary, lanes: Array, ri: int, net: Dictionary = {}) -> void:
	var r := float(ring.get("r", 30.0))
	var depth: Array = ring.get("depth", [3.0, 3.6])
	var width: Array = ring.get("width", [3.0, 4.5])
	var hs: Array = ring.get("h", [2.8, 3.6])
	var gap := float(ring.get("gap", 0.5))
	var booth := float(ring.get("booth_share", 0.25))
	var hut := float(ring.get("hut_share", 0.1))
	var stack := float(ring.get("stack_share", 0.3))
	var out := str(ring.get("face", "in")) == "out"
	var a := float(ri) * 0.53
	var end := a + TAU
	while a < end:
		var w := snappedf(_rng.randf_range(float(width[0]), float(width[1])), 0.25)
		var da := (w + gap) / r
		if a + da > end:
			break
		var mid := a + da * 0.5
		a += da
		var roll := _rng.randf()
		var seed := _rng.randi()
		if not _clear(mid, r, w * 0.5 + 0.3, lanes):
			continue
		var d := snappedf(_rng.randf_range(float(depth[0]), float(depth[1])), 0.25)
		var xf := radial(t, y, mid) * Transform3D(Basis.IDENTITY, Vector3(r, 0, 0))
		if not out:
			xf = xf * Transform3D(Basis(UP, PI), Vector3.ZERO)       # +X, its door, back toward the middle
		_stop(net, mid, r, d, out)
		if roll < booth:
			_q.append(_booth.bind(xf, d, w, seed))
		elif roll < booth + hut and w >= 4.0:
			_q.append(_town_hut.bind(xf, seed))
		else:
			var h := snappedf(_rng.randf_range(float(hs[0]), float(hs[1])), 0.25)
			_q.append(_shack.bind(xf, d, w, h, _rng.randf() < stack, seed))


## A shack `d` deep (x, its door side +X) and `w` wide: painted walls, a tilted tin
## roof, a door with its light, a lit window, an awning now and then, a barrel or
## a tank on the roof; `stacked`, a smaller one on top with a ladder up to it.
func _shack(xf: Transform3D, d: float, w: float, h: float, stacked: bool, seed: int) -> void:
	kit._xf = xf
	_rng.seed = seed
	var paint := _paint(_rng.randi())
	var tin := _paint(_rng.randi() + 3)
	_p(kit.box(d, h, w), paint, Vector3(0, h * 0.5, 0), true)
	var tilt := Basis(Vector3.BACK, 0.07 if _rng.randf() < 0.5 else -0.07)
	_p(kit.box(d + 0.5, 0.1, w + 0.3), tin, Vector3(0, h + 0.1, 0), false, tilt)
	var dz := snappedf(_rng.randf_range(-w * 0.25, w * 0.25), 0.25)
	_p(kit.box(0.08, 2.0, 0.9), _m("hull"), Vector3(d * 0.5 + 0.02, 1.0, dz))
	_p(kit.box(0.1, 0.06, 1.0), kit.door_glow, Vector3(d * 0.5 + 0.05, 2.12, dz))
	if w >= 3.25:
		var wz := -signf(dz + 0.01) * (w * 0.5 - 0.7)
		_p(kit.box(0.06, 0.55, 0.8), kit.window_glow, Vector3(d * 0.5 + 0.03, 1.6, wz))
	if _rng.randf() < 0.4:
		_p(kit.box(1.0, 0.05, w * 0.8), mats.cloth(FABRICS[_rng.randi() % FABRICS.size()]), Vector3(d * 0.5 + 0.45, 2.45, 0), false,
			Basis(Vector3.BACK, -0.3))
	if not stacked and _rng.randf() < 0.5:
		if _rng.randf() < 0.6:
			_p(kit.cyl(0.3, 0.3, 0.8, 8), tin, Vector3(-d * 0.2, h + 0.55, w * 0.25))
		else:
			_p(kit.cyl(0.55, 0.55, 1.0, 10), _m("hull"), Vector3(-d * 0.2, h + 0.65, -w * 0.2))
	_count("shack")
	if not stacked:
		return
	var d2 := snappedf(d * 0.75, 0.25)
	var w2 := snappedf(w * 0.8, 0.25)
	var h2 := 2.5
	var y2 := h + 0.15
	var top := _paint(_rng.randi() + 1)
	_p(kit.box(d2, h2, w2), top, Vector3(-(d - d2) * 0.5, y2 + h2 * 0.5, 0), true)
	_p(kit.box(d2 + 0.4, 0.1, w2 + 0.3), tin, Vector3(-(d - d2) * 0.5, y2 + h2 + 0.08, 0), false, tilt.inverse())
	var ux := -(d - d2) * 0.5 + d2 * 0.5
	_p(kit.box(0.08, 1.9, 0.8), _m("hull"), Vector3(ux + 0.02, y2 + 0.95, 0))
	_p(kit.box(0.1, 0.06, 0.9), kit.door_glow, Vector3(ux + 0.05, y2 + 2.0, 0))
	# The ladder up the front, beside the door below.
	var lz := (w * 0.5 - 0.45) * (1.0 if dz <= 0.0 else -1.0)
	for s: float in [-0.22, 0.22]:
		_p(kit.box(0.05, y2, 0.05), _m("rail"), Vector3(d * 0.5 + 0.25, y2 * 0.5, lz + s))
	var ry := 0.4
	while ry < y2:
		_p(kit.box(0.05, 0.04, 0.48), _m("rail"), Vector3(d * 0.5 + 0.25, ry, lz))
		ry += 0.4
	_count("stacked")


## A booth: a counter to the alley under a tilted awning, walls behind and either
## side, wares on the counter, a neon sign.
func _booth(xf: Transform3D, d: float, w: float, seed: int) -> void:
	kit._xf = xf
	_rng.seed = seed
	var paint := _paint(_rng.randi())
	var cloth := mats.cloth(FABRICS[_rng.randi() % FABRICS.size()])
	_p(kit.box(0.8, 1.0, w - 0.3), kit.crate_woods[_rng.randi() % 3], Vector3(d * 0.5 - 0.4, 0.5, 0), true)
	_p(kit.box(0.15, 2.6, w), paint, Vector3(-d * 0.5 + 0.08, 1.3, 0), true)
	for s: float in [-1.0, 1.0]:
		_p(kit.box(d, 2.6, 0.12), paint, Vector3(0, 1.3, s * (w * 0.5 - 0.06)), true)
	_p(kit.box(d + 0.7, 0.05, w + 0.2), cloth, Vector3(0.3, 2.75, 0), false, Basis(Vector3.BACK, -0.12))
	_p(kit.box(0.05, 0.32, w * 0.6), _glow(NEONS[_rng.randi() % NEONS.size()], 3.0), Vector3(d * 0.5 + 0.05, 3.05, 0))
	var n := 3 + _rng.randi() % 3
	for k in n:
		var z := (float(k) + 0.5) / n * (w - 0.8) - (w - 0.8) * 0.5
		var c: Color = FABRICS[(k + seed) % FABRICS.size()]
		if k % 2 == 0:
			_p(kit.box(0.3, 0.22, 0.3), mats.flat(c, 0.7), Vector3(d * 0.5 - 0.4, 1.11, z))
		else:
			_p(kit.ball(0.14, 0.24, false, 8), mats.flat(c.lightened(0.2), 0.6), Vector3(d * 0.5 - 0.4, 1.12, z))
	_count("booth")


## One of the town's small huts, at one of two sizes (so they share their meshes),
## in a painted metal.
func _town_hut(xf: Transform3D, seed: int) -> void:
	_rng.seed = seed
	var big := _rng.randf() < 0.5
	var look := "hut_stepped" if big else "hut_block"
	var d := 4.0 if big else 3.5
	var w := 4.5 if big else 4.0
	var h := 3.6 if big else 3.2
	kit.build_at({ "id": "fv_%d" % seed, "look": look, "wall_mat": _paint(_rng.randi()) }, xf, d, w, h)
	kit.add_collider(xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(d, h, w))
	_count("hut")


## Over the alleys: cables from one ring to the next with bulbs along them, and
## washing lines; nothing on a lane.
func _lines(t: Dictionary, y: float, fc: Dictionary, lanes: Array) -> void:
	var rings: Array = fc.get("rings", [])
	var per := int(fc.get("lines_per_ring", 18))
	var bulbs: Array = NEONS.map(func(c): return _glow(c, 3.0))
	for ri in range(1, rings.size()):
		var r0 := float(rings[ri - 1].get("r", 30.0))
		var r1 := float(rings[ri].get("r", 30.0))
		for k in per:
			var a := TAU * (k + _rng.randf()) / per
			if not _clear(a, (r0 + r1) * 0.5, 0.5, lanes):
				continue
			kit._xf = radial(t, y, a)
			var hy := _rng.randf_range(4.2, 5.4)
			var span := absf(r1 - r0)
			_p(kit.box(span, 0.03, 0.03), _m("rail"), Vector3((r0 + r1) * 0.5, hy, 0))
			var washing := _rng.randf() < 0.4
			var n := maxi(2, floori(span / 0.9))
			for j in n:
				var x := minf(r0, r1) + (j + 0.5) * span / n
				if washing:
					_p(kit.box(0.4, 0.55, 0.02), mats.cloth(FABRICS[(j + k) % FABRICS.size()]), Vector3(x, hy - 0.3, 0))
				else:
					_p(kit.ball(0.06, 0.12, false, 6), bulbs[(j + k + ri) % bulbs.size()], Vector3(x, hy - 0.08, 0))
	_count("lines")


# ------------------------------------------------------------------ the suites

## The upper homes: a few big suites, every one open, dressed like the cantina's
## club and the party barge.
func _suites(t: Dictionary, f: Dictionary, fc: Dictionary) -> void:
	var r0 := hull.gap_r + hull.walk + 0.4
	var r1 := float(f.r) - StationHull.WALL
	var k := 0
	for room in hull.rooms_of(str(t.id), str(f.id)):
		if not bool(room.open):
			continue
		_q.append(_suite.bind(radial(t, float(f.y), float(room.a)), r0, r1, float(room.half), k))
		k += 1
		_count("suite")


## A suite: dark wood floors and panelling with a gold rail, neon lines along the
## walls, a bar with lit bottles and an aquarium by the door, two velvet booths
## round cocktail tables under chandeliers, a light-up dance floor between them
## ringed by cocktail tables, a long sofa, a piano in every other one, a round bed
## with a gold canopy by the window, plants in gold pots.
func _suite(at: Transform3D, r0: float, r1: float, half: float, k: int) -> void:
	kit._xf = at
	var depth := r1 - r0
	var velvet := mats.flat(VELVETS[k % VELVETS.size()], 0.55)
	var velvet2 := mats.flat(VELVETS[(k + 1) % VELVETS.size()].darkened(0.1), 0.55)
	var gold := mats.flat(Color("#d4af37"), 0.25, 1.0)
	var wood := mats.wood(Color("#4a2e22"), 0.55)
	var black := mats.flat(Color("#141216"), 0.12, 0.4)
	var neon := _glow(NEONS[k % NEONS.size()], 3.0)
	var ceil_y := hull.floor_h
	# The floor: dark planks; velvet rugs under the lounges.
	for j in 5:
		var x := r0 + depth * (j + 0.5) / 5.0
		var w := 2.0 * _half_w(x - depth * 0.1, half) + 0.2
		_p(kit.box(depth / 5.0, 0.03, w), wood, Vector3(x, 0.015, 0))
	# Panelling up both walls, a gold rail, a neon line under the ceiling.
	var xm := (r0 + r1) * 0.5
	var span := depth / cos(half)
	for s: float in [-1.0, 1.0]:
		var b := Basis(UP, -s * half)
		var z := s * (xm * tan(half) - StationHull.INNER_WALL - 0.12)
		_p(kit.box(span, 1.3, 0.08), wood, Vector3(xm, 0.65, z), false, b)
		_p(kit.box(span, 0.06, 0.12), gold, Vector3(xm, 1.33, z), false, b)
		_p(kit.box(span, 0.06, 0.06), neon, Vector3(xm, ceil_y - 0.45, z), false, b)
		_p(kit.box(span, 0.06, 0.06), neon, Vector3(xm, 0.08, z - s * 0.06), false, b)
	# The bar by the door, lit bottles on gold shelves behind it, stools.
	var bx := r0 + 4.0
	var bz := _half_w(bx, half) - 0.6
	_p(kit.box(3.4, 1.05, 0.7), wood, Vector3(bx, 0.52, bz), true)
	_p(kit.box(3.5, 0.06, 0.8), black, Vector3(bx, 1.08, bz))
	_p(kit.box(3.4, 0.05, 0.06), gold, Vector3(bx, 0.95, bz - 0.38))
	_p(kit.box(3.4, 0.04, 0.04), neon, Vector3(bx, 0.1, bz - 0.36))
	var sz := _half_w(bx, half) - 0.1
	for q in 3:
		_p(kit.box(3.0, 0.04, 0.3), gold, Vector3(bx, 1.5 + q * 0.5, sz))
	for j in 15:
		var c: Color = NEONS[(j + k) % NEONS.size()]
		_p(kit.cyl(0.05, 0.06, 0.32, 6), _glow(c.darkened(0.25), 1.6), Vector3(bx - 1.35 + (j % 5) * 0.68, 1.68 + (j / 5) * 0.5, sz))
	for j in 3:
		var stz := bz - 0.85
		_p(kit.cyl(0.04, 0.06, 0.72, 6), gold, Vector3(bx - 1.0 + j * 1.0, 0.36, stz))
		_p(kit.cyl(0.22, 0.22, 0.08, 10), velvet, Vector3(bx - 1.0 + j * 1.0, 0.76, stz))
	# An aquarium along the other wall by the door, glowing blue.
	var az := -(_half_w(bx, half) - 0.45)
	_p(kit.box(3.0, 0.5, 0.7), black, Vector3(bx, 0.25, az), true)
	_p(kit.box(2.9, 1.3, 0.6), _glow(Color("#2a8fd8"), 1.2), Vector3(bx, 1.15, az))
	_p(kit.box(3.0, 0.08, 0.7), gold, Vector3(bx, 1.84, az))
	# Two lounges: a velvet booth round a cocktail table under a chandelier.
	for li in 2:
		var lx := r0 + depth * (0.3 if li == 0 else 0.68)
		var vm := velvet if li == 0 else velvet2
		_p(kit.box(5.5, 0.02, minf(6.0, 2.0 * _half_w(lx - 2.75, half))), mats.flat(VELVETS[(k + li + 2) % VELVETS.size()].darkened(0.3), 0.9), Vector3(lx, 0.04, 0))
		_lounge(lx, vm, gold, black)
		_chandelier(lx + 0.4, ceil_y, gold)
	# A light-up dance floor between the lounges, like the barge's.
	var dx := r0 + depth * 0.49
	for i in 5:
		for j in 5:
			var c2: Color = NEONS[(k + (i + j) % 2) % NEONS.size()]
			_p(kit.box(0.95, 0.04, 0.95), _glow(c2.darkened(0.35), 1.4), Vector3(dx + (i - 2) * 1.0, 0.05, (j - 2) * 1.0))
	_p(kit.box(5.2, 0.03, 5.2), black, Vector3(dx, 0.03, 0))
	# Cocktail tables round the floor, a candle on each; a long sofa along the wall.
	for j in 4:
		var tx := dx + (j - 1.5) * 1.8
		var tz := (_half_w(tx, half) - 1.6) * (1.0 if j % 2 == 0 else -1.0)
		_p(kit.cyl(0.4, 0.4, 0.04, 12), black, Vector3(tx, 1.05, tz))
		_p(kit.cyl(0.04, 0.06, 1.05, 6), gold, Vector3(tx, 0.52, tz), true)
		_p(kit.cyl(0.035, 0.035, 0.1, 6), _glow(Color("#ffb46a"), 3.0), Vector3(tx, 1.12, tz))
	var fx := r0 + depth * 0.58
	var fz := _half_w(fx, half) - 0.55
	_p(kit.box(4.5, 0.45, 0.8), velvet2, Vector3(fx, 0.225, fz), true, Basis(UP, -half))
	_p(kit.box(4.5, 0.8, 0.2), velvet2, Vector3(fx, 0.75, fz + 0.4), false, Basis(UP, -half))
	# A grand piano in every other suite, across from the sofa.
	if k % 2 == 0:
		var px := r0 + depth * 0.58
		var pz := -(_half_w(px, half) - 1.4)
		_p(kit.box(1.6, 0.35, 1.4), black, Vector3(px, 0.9, pz), true)
		_p(kit.box(1.5, 0.04, 1.3), black, Vector3(px - 0.2, 1.4, pz), false, Basis(Vector3.BACK, 0.45))
		_p(kit.box(0.2, 0.06, 1.2), mats.flat(Color("#ece6d8"), 0.4), Vector3(px + 0.85, 0.98, pz))
		for s: float in [-0.55, 0.55]:
			_p(kit.cyl(0.05, 0.05, 0.75, 6), gold, Vector3(px, 0.37, pz + s))
	# The round bed by the window under a gold canopy, nightstands with lamps.
	var rx := r1 - 4.5
	_p(kit.cyl(1.8, 1.8, 0.5, 16), velvet, Vector3(rx, 0.25, 0), true)
	_p(kit.cyl(1.7, 1.7, 0.1, 16), mats.flat(VELVETS[(k + 1) % VELVETS.size()].lightened(0.15), 0.8), Vector3(rx, 0.55, 0))
	_p(kit.box(0.5, 0.18, 1.6), mats.flat(Color("#ece6d8"), 0.8), Vector3(rx - 1.1, 0.68, 0))
	for j in 4:
		var a := PI * 0.25 + j * PI * 0.5
		_p(kit.cyl(0.05, 0.05, 2.8, 6), gold, Vector3(rx + cos(a) * 1.9, 1.4, sin(a) * 1.9))
	_ring_of(rx, 1.9, 2.8, 0.08, gold, 12)
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.5, 0.55, 0.5), black, Vector3(rx - 1.2, 0.28, s * 2.4), true)
		_p(kit.cyl(0.18, 0.12, 0.3, 10), kit.window_glow, Vector3(rx - 1.2, 0.85, s * 2.4))
	# Plants in gold pots in the window's corners.
	for s: float in [-1.0, 1.0]:
		var pz2 := s * (_half_w(r1 - 1.2, half) - 0.6)
		_p(kit.cyl(0.3, 0.22, 0.55, 10), gold, Vector3(r1 - 1.2, 0.28, pz2), true)
		_p(kit.ball(0.55, 0.9, false, 8), mats.flat(Color("#3f6b34"), 0.8), Vector3(r1 - 1.2, 1.0, pz2))


## A velvet booth (a U of seats and high backs) round a black cocktail table with a candle.
func _lounge(lx: float, vm: Material, gold: Material, black: Material) -> void:
	_p(kit.box(0.65, 0.45, 2.8), vm, Vector3(lx + 1.35, 0.225, 0), true)
	_p(kit.box(0.22, 1.05, 2.8), vm, Vector3(lx + 1.75, 0.75, 0))
	for s: float in [-1.0, 1.0]:
		_p(kit.box(1.8, 0.45, 0.65), vm, Vector3(lx + 0.6, 0.225, s * 1.4), true)
		_p(kit.box(1.8, 1.05, 0.22), vm, Vector3(lx + 0.6, 0.75, s * 1.8))
	_p(kit.box(2.2, 0.05, 0.06), gold, Vector3(lx + 0.6, 1.3, 1.8))
	_p(kit.box(2.2, 0.05, 0.06), gold, Vector3(lx + 0.6, 1.3, -1.8))
	_p(kit.cyl(0.6, 0.6, 0.05, 14), black, Vector3(lx + 0.4, 0.74, 0))
	_p(kit.cyl(0.05, 0.08, 0.72, 6), gold, Vector3(lx + 0.4, 0.36, 0), true)
	_p(kit.cyl(0.04, 0.04, 0.1, 6), _glow(Color("#ffb46a"), 3.0), Vector3(lx + 0.4, 0.82, 0))


## A chandelier hanging from the ceiling at (x, 0): a gold dish and a ring of lit globes.
func _chandelier(x: float, ceil_y: float, gold: Material) -> void:
	_p(kit.cyl(0.02, 0.02, 2.4, 6), gold, Vector3(x, ceil_y - 1.2, 0))
	_p(kit.cyl(0.9, 0.5, 0.15, 12), gold, Vector3(x, ceil_y - 2.45, 0))
	for j in 8:
		var a := TAU * j / 8.0
		_p(kit.ball(0.11, 0.22, false, 8), kit.window_glow, Vector3(x + cos(a) * 0.8, ceil_y - 2.6, sin(a) * 0.8))
	_p(kit.ball(0.16, 0.32, false, 8), kit.window_glow, Vector3(x, ceil_y - 2.75, 0))


# ------------------------------------------------------------------ the Remnant deck

## The Remnant deck's colours, registered with the look's materials under `g` (so
## LookMaterials.repaint paints them over when the locals take it): "mark" for
## banners and stripes, "lamp" for the lights, "band" for the barricades' bands.
## Made at once, before the floor is built, so a repaint can come first.
func faction_mats(g: String) -> void:
	group = g
	faction = {
		"mark": mats.faction_flat("mark", g, 0.65, 0.1),
		"band": mats.faction_flat("band", g, 0.6, 0.3),
		"lamp": mats.faction_glow("lamp", g),
	}
	(faction.lamp as StandardMaterial3D).emission_energy_multiplier = 2.5


func _fm(role: String) -> Material:
	if faction.is_empty():
		faction_mats("station")
	return faction[role]


## One whole floor of the Remnant: its rooms by use (StationRemnant.rooms) and its
## walkway in their colours, with a barricade and a checkpoint at the tunnel.
func _remnant(t: Dictionary, f: Dictionary) -> void:
	for r in StationRemnant.rooms(hull):
		_q.append(_remnant_room.bind(r))
		_count(str(r.use))
	_q.append(_remnant_walkway.bind(t, f))


func _remnant_room(r: Dictionary) -> void:
	kit._xf = r.frame
	var r0 := float(r.r0)
	var r1 := float(r.r1)
	var half := float(r.half)
	# Every room: a stripe down the middle of the floor, red lamps along the walls.
	_p(kit.box(r1 - r0 - 1.0, 0.02, 0.5), _fm("mark"), Vector3((r0 + r1) * 0.5, 0.03, 0))
	for s: float in [-1.0, 1.0]:
		var xm := (r0 + r1) * 0.5
		_p(kit.box((r1 - r0) / cos(half), 0.08, 0.08), _fm("lamp"), Vector3(xm, hull.floor_h - 0.6, s * (xm * tan(half) - StationHull.INNER_WALL - 0.1)),
			false, Basis(UP, -s * half))
	match str(r.use):
		"control":
			var cr := StationRemnant.control_room(hull, r)
			kit._xf = cr.frame
			for p in OutpostRoom.inside(cr.b):
				var id := str(p.id)
				if id.begins_with("lining"):
					continue
				var c: Vector3 = p.center
				if id == "floor":
					c.y += 0.05
				var m: Material = _glow(Color("#e8f6ff"), 3.0) if str(p.finish) == "glow" else _m(str(p.finish))
				_p(kit.box((p.size as Vector3).x, (p.size as Vector3).y, (p.size as Vector3).z), m, c, bool(p.solid), p.basis)
			kit._xf = r.frame
			_p(kit.box(0.08, 4.0, 1.6), _fm("mark"), Vector3(r1 - 0.4, 6.0, 0))
		"bunks":
			_bunks(r0, r1, half)
		"armoury":
			_armoury(r0, r1, half)
		"command":
			_command(r0, r1, half)
		"mess":
			_mess(r0, r1, half)


## Two-high bunks down both sides (posts, frames, mattresses, pillows), a
## footlocker at each foot, lockers at the window end: the barracks' bunk room.
func _bunks(r0: float, r1: float, half: float) -> void:
	var frame := mats.painted(Color("#3b3f45"), 0.5, 0.6)
	var cloth := mats.flat(Color("#59604c"), 0.95)
	var pillow := mats.flat(Color("#c9c3b2"), 0.95)
	var steel := mats.painted(Color("#4c5259"), 0.45, 0.55)
	var x := r0 + 2.5
	while x < r1 - 5.0:
		for s: float in [-1.0, 1.0]:
			var z := s * (_half_w(x, half) - 1.1)
			for dx: float in [-0.95, 0.95]:
				for dz: float in [-0.42, 0.42]:
					_p(kit.box(0.06, 2.0, 0.06), frame, Vector3(x + dx, 1.0, z + dz))
			for y: float in [0.38, 1.38]:
				_p(kit.box(2.0, 0.08, 0.9), frame, Vector3(x, y, z))
				_p(kit.box(1.9, 0.14, 0.82), cloth, Vector3(x, y + 0.11, z))
				_p(kit.box(0.32, 0.1, 0.65), pillow, Vector3(x - 0.75, y + 0.23, z))
			kit.add_collider(kit._xf * Transform3D(Basis.IDENTITY, Vector3(x, 1.0, z)), Vector3(2.0, 2.0, 0.9))
			_p(kit.box(0.5, 0.45, 0.8), steel, Vector3(x + 1.3, 0.22, z), true)
		x += 2.7
	var lz := _half_w(r1 - 1.0, half) - 1.0
	var n := maxi(2, floori(lz * 2.0 / 0.7))
	for k in n:
		var z := -lz + (k + 0.5) * lz * 2.0 / n
		_p(kit.box(0.55, 2.0, 0.6), steel, Vector3(r1 - 0.6, 1.0, z), true)
		_p(kit.box(0.02, 0.05, 0.5), _fm("band"), Vector3(r1 - 0.9, 1.7, z))


## Rifle racks down both sides, ammunition crates, a workbench, a red cage at the end.
func _armoury(r0: float, r1: float, half: float) -> void:
	var dark := mats.painted(Color("#1d1f22"), 0.4, 0.7)
	var x := r0 + 3.0
	while x < r1 - 6.0:
		for s: float in [-1.0, 1.0]:
			var z := s * (_half_w(x, half) - 0.5)
			_p(kit.box(2.4, 2.0, 0.4), _m("trim"), Vector3(x, 1.0, z), true)
			for k in 6:
				_p(kit.box(0.08, 1.15, 0.14), dark, Vector3(x - 1.0 + k * 0.4, 1.0, z - s * 0.26))
			_p(kit.box(2.4, 0.06, 0.06), _fm("lamp"), Vector3(x, 2.05, z - s * 0.22))
		x += 3.2
	for k in 6:
		var cx := r0 + 4.0 + (k % 3) * 1.4
		var cz := -1.2 + (k / 3) * 2.4
		_p(kit.box(1.0, 0.7, 0.8), _m("cargo"), Vector3(cx, 0.35 + (0.7 if k == 4 else 0.0), cz), true)
	_p(kit.box(2.6, 0.95, 1.0), _m("console"), Vector3(r1 - 7.0, 0.48, 0), true)
	_p(kit.box(2.6, 0.06, 1.1), _m("trim"), Vector3(r1 - 7.0, 0.98, 0))
	var cw := _half_w(r1 - 3.0, half) - 0.8
	for k in 9:
		var z := -cw + k * cw * 2.0 / 8.0
		_p(kit.box(0.06, 3.0, 0.06), _fm("band"), Vector3(r1 - 4.0, 1.5, z))
	_p(kit.box(0.08, 0.08, cw * 2.0), _fm("lamp"), Vector3(r1 - 4.0, 3.0, 0))


## The commander's office: a desk to the door with a chair, a wall of screens, a
## map table and the Remnant's banners either side.
func _command(r0: float, r1: float, half: float) -> void:
	var dx := r0 + 12.0
	_p(kit.box(1.1, 0.8, 3.0), _m("console"), Vector3(dx, 0.4, 0), true)
	_p(kit.box(1.2, 0.06, 3.1), _m("trim"), Vector3(dx, 0.82, 0))
	_p(kit.box(0.6, 1.3, 0.6), _m("hull"), Vector3(dx + 1.0, 0.65, 0), true)
	_p(kit.box(0.08, 2.4, 5.0), _m("screen"), Vector3(r1 - 1.2, 2.6, 0))
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.08, 4.5, 1.4), _fm("mark"), Vector3(r1 - 1.3, 6.0, s * 3.6))
	_p(kit.box(2.4, 0.9, 1.6), _m("console"), Vector3(r0 + 5.0, 0.45, 0), true)
	_p(kit.box(2.2, 0.04, 1.4), _fm("lamp"), Vector3(r0 + 5.0, 0.92, 0))
	for s: float in [-1.0, 1.0]:
		var z := s * (_half_w(r0 + 8.0, half) - 0.3)
		_p(kit.box(4.0, 0.9, 0.05), _m("screen"), Vector3(r0 + 8.0, 1.8, z))


## The mess: two long tables with benches, a serving counter, a screen.
func _mess(r0: float, r1: float, half: float) -> void:
	for s: float in [-1.0, 1.0]:
		var z := s * 2.6
		_p(kit.box(8.0, 0.08, 1.2), _m("trim"), Vector3(r0 + 9.0, 0.76, z))
		for lx: float in [-3.6, 0.0, 3.6]:
			_p(kit.box(0.1, 0.72, 0.9), _m("hull"), Vector3(r0 + 9.0 + lx, 0.36, z), lx == 0.0)
		for bz: float in [-0.95, 0.95]:
			_p(kit.box(8.0, 0.08, 0.4), _m("hull"), Vector3(r0 + 9.0, 0.45, z + bz), true)
	_p(kit.box(1.0, 1.05, 6.0), _m("console"), Vector3(r1 - 6.0, 0.52, 0), true)
	_p(kit.box(1.1, 0.06, 6.1), _m("trim"), Vector3(r1 - 6.0, 1.08, 0))
	_p(kit.box(0.08, 1.5, 3.0), _m("screen"), Vector3(r1 - 1.2, 2.5, 0))


## The walkway in the Remnant's colours: a stripe round it, a banner each side of
## every room's door, and at the tunnel's mouth a staggered barricade (solid, with a
## way through round its sides) and a checkpoint arch with red lamps.
func _remnant_walkway(t: Dictionary, f: Dictionary) -> void:
	var y := float(f.y)
	var rr := hull.gap_r + hull.walk
	var n := 48
	for k in n:
		var a := TAU * k / n
		kit._xf = radial(t, y, a)
		_p(kit.box(0.4, 0.02, 2.0 * rr * tan(PI / n)), _fm("mark"), Vector3(rr - 0.8, 0.03, 0))
	for r in StationRemnant.rooms(hull):
		var room: Dictionary = r.room
		for s: float in [-1.0, 1.0]:
			kit._xf = radial(t, y, float(room.a) + s * 2.6 / rr)
			_p(kit.box(0.06, 4.0, 1.1), _fm("mark"), Vector3(rr - 0.26, 7.5, 0))
			_p(kit.box(0.08, 0.08, 1.2), _fm("lamp"), Vector3(rr - 0.28, 9.6, 0))
	for d in hull.door_angles(t, y):
		kit._xf = radial(t, y, float(d))
		for b in [[rr - 3.5, 2.3], [rr - 3.5, -2.3], [rr - 6.0, 0.0]]:
			_p(kit.box(0.7, 1.2, 2.4), _m("hull"), Vector3(float(b[0]), 0.6, float(b[1])), true)
			_p(kit.box(0.72, 0.12, 2.42), _fm("band"), Vector3(float(b[0]), 1.0, float(b[1])))
			_p(kit.box(0.74, 0.04, 2.0), _fm("lamp"), Vector3(float(b[0]), 1.22, float(b[1])))
		for s: float in [-1.0, 1.0]:
			_p(kit.box(0.35, 3.4, 0.35), _m("trim"), Vector3(rr - 1.2, 1.7, s * 2.9), true)
		_p(kit.box(0.4, 0.4, 6.2), _m("trim"), Vector3(rr - 1.2, 3.6, 0))
		_p(kit.box(0.42, 0.1, 5.6), _fm("lamp"), Vector3(rr - 1.2, 3.35, 0))


# ------------------------------------------------------------------ the engine deck

func _engines(t: Dictionary, f: Dictionary, fc: Dictionary) -> void:
	var r0 := hull.gap_r + hull.walk + 0.4
	var r1 := float(f.r) - StationHull.WALL
	var uses: Array = fc.get("rooms", ["engine", "cargo", "pumps", "workshop"])
	var k := 0
	var hatch := false
	for room in hull.rooms_of(str(t.id), str(f.id)):
		var at := radial(t, float(f.y), float(room.a))
		var use := str(uses[k % uses.size()])
		var mid := (r0 + r1) * 0.5
		match use:
			"engine":
				_q.append(_in.bind(at, _reactor.bind(mid + 1.5, float(room.half))))
			"cargo":
				_q.append(_in.bind(at, _cargo.bind(r0, r1, float(room.half), not hatch, _rng.randi())))
				hatch = true
			"pumps":
				_q.append(_in.bind(at, _pumps.bind(mid, float(room.half))))
			"workshop":
				_q.append(_in.bind(at, _workshop.bind(r0, r1, float(room.half))))
		_count(use)
		k += 1
	_q.append(_pipes.bind(t, f))


## Run `job` with the kit's frame at `at`.
func _in(at: Transform3D, job: Callable) -> void:
	kit._xf = at
	job.call()


## A reactor: a plinth, a tall core in rings of glow, conduits up into the ceiling,
## a railing round it and a console by the door.
func _reactor(r: float, half: float) -> void:
	var glow := _glow(Color("#5fd0ff"), 3.0)
	var hull_m := _m("hull")
	_p(kit.cyl(4.2, 4.6, 0.6, 16), _m("grate"), Vector3(r, 0.3, 0), true)
	_p(kit.cyl(2.6, 2.9, 9.0, 16), hull_m, Vector3(r, 5.1, 0), true)
	for j in 4:
		_p(kit.cyl(2.75, 2.75, 0.35, 16), glow, Vector3(r, 1.8 + j * 2.2, 0))
	_p(kit.cyl(1.6, 2.6, 1.6, 16), _m("trim"), Vector3(r, 10.4, 0))
	for j in 4:
		var a := PI * 0.25 + j * PI * 0.5
		_p(kit.cyl(0.25, 0.25, 3.6, 8), _m("rail"), Vector3(r + cos(a) * 1.3, 12.4, sin(a) * 1.3))
	_ring_of(r, 3.9, 1.1, 0.12, _m("rail"), 16)
	_ring_of(r, 3.9, 1.15, 0.08, glow, 16)
	var cz := clampf(r * tan(half) - 2.0, 1.5, 6.0)
	_p(kit.box(0.8, 1.1, 2.0), _m("console"), Vector3(r - 5.5, 0.55, cz), true)
	_p(kit.box(0.05, 0.6, 1.8), _m("screen"), Vector3(r - 5.9, 1.3, cz))


## A ring of `n` short boxes round (r, 0) in this room's frame: a railing, `rad` out.
func _ring_of(r: float, rad: float, y: float, thick: float, mat: Material, n: int) -> void:
	for j in n:
		var a := TAU * j / n
		var w := 2.0 * rad * tan(PI / n) + 0.05
		var x := Vector3(cos(a), 0, sin(a))
		_p(kit.box(thick, thick, w), mat, Vector3(r, y, 0) + x * rad, false, Basis(x, UP, x.cross(UP)))


## A cargo hold: containers in rows, crates stacked by them, a lift pallet; the
## first one has the drop hatch in its floor (sealed: the wrecks below are #317).
func _cargo(r0: float, r1: float, half: float, with_hatch: bool, seed: int) -> void:
	_rng.seed = seed
	var cargo := _m("cargo")
	var rows := 0
	var r := r0 + 3.5
	while r < r1 - 3.0:
		var w := _half_w(r, half)
		var z := -w + 1.6
		while z < w - 1.6:
			if not (with_hatch and absf(r - (r0 + r1) * 0.5) < 4.0 and absf(z) < 4.0):
				var tall := 2.4 if _rng.randf() < 0.6 else 1.2
				_p(kit.box(2.4, tall, 2.4), cargo if _rng.randf() < 0.7 else kit.crate_woods[_rng.randi() % 3],
					Vector3(r, tall * 0.5, z), true, Basis(UP, _rng.randf_range(-0.08, 0.08)))
				_count("crate")
			z += 3.4
		r += 4.2
		rows += 1
	if with_hatch:
		var hr := (r0 + r1) * 0.5
		var lock := _glow(Color("#ffb04a"), 2.5)
		_p(kit.box(4.4, 0.04, 4.4), _m("grate"), Vector3(hr, 0.02, 0))
		for s: float in [-1.0, 1.0]:
			_p(kit.box(4.8, 0.06, 0.2), lock, Vector3(hr, 0.04, s * 2.3))
			_p(kit.box(0.2, 0.06, 4.8), lock, Vector3(hr + s * 2.3, 0.04, 0))
		_count("drop_hatch")


## A pump room: horizontal pumps on plinths, pipes up into the ceiling, gauges.
func _pumps(r: float, half: float) -> void:
	var w := _half_w(r, half)
	var hull_m := _m("hull")
	for j in 3:
		var z := (j - 1) * minf(3.2, w * 0.6)
		_p(kit.box(3.2, 0.5, 1.4), _m("grate"), Vector3(r, 0.25, z), true)
		_p(kit.cyl(0.6, 0.6, 2.8, 12), hull_m, Vector3(r, 1.15, z), true, TownBuildings.AXIS_X)
		_p(kit.cyl(0.65, 0.65, 0.2, 12), _m("trim"), Vector3(r - 0.9, 1.15, z), false, TownBuildings.AXIS_X)
		_p(kit.cyl(0.65, 0.65, 0.2, 12), _m("trim"), Vector3(r + 0.9, 1.15, z), false, TownBuildings.AXIS_X)
		_p(kit.cyl(0.18, 0.18, hull.floor_h - 1.7, 8), _m("rail"), Vector3(r + 1.2, (hull.floor_h + 1.7) * 0.5, z))
		_p(kit.box(0.05, 0.3, 0.3), _glow(Color("#7dff9a")), Vector3(r - 1.62, 1.3, z))


## A workshop: two benches with tools, a rack of glowing parts on the wall, a
## droid half built on a stand, a hanging lamp.
func _workshop(r0: float, r1: float, half: float) -> void:
	var trim := _m("trim")
	var mid := (r0 + r1) * 0.5
	for j in 2:
		var r := mid - 3.0 + j * 6.0
		var w := _half_w(r, half)
		var z := (w - 0.6) * (1.0 if j == 0 else -1.0)
		_p(kit.box(2.4, 0.9, 0.9), _m("wall"), Vector3(r, 0.45, z), true)
		_p(kit.box(2.5, 0.06, 1.0), trim, Vector3(r, 0.93, z))
		for q in 4:
			_p(kit.box(0.25, 0.12 + q * 0.04, 0.2), _m("console") if q % 2 == 0 else trim,
				Vector3(r - 0.9 + q * 0.6, 1.0 + q * 0.02, z))
		_p(kit.box(2.4, 1.2, 0.08), _m("screen"), Vector3(r, 1.9, z + signf(z) * 0.4))
	_p(kit.cyl(0.6, 0.7, 0.3, 12), _m("grate"), Vector3(mid, 0.15, 0), true)
	_p(kit.cyl(0.25, 0.3, 1.0, 8), _m("hull"), Vector3(mid, 0.8, 0))
	_p(kit.ball(0.35, 0.6, false, 10), _m("hull"), Vector3(mid, 1.5, 0))
	_p(kit.box(0.1, 0.1, 0.1), _glow(Color("#ff4a32"), 3.0), Vector3(mid - 0.3, 1.55, 0))
	_p(kit.cyl(0.03, 0.03, hull.floor_h - 4.0, 6), trim, Vector3(mid, (hull.floor_h + 4.0) * 0.5, 0))
	_p(kit.cyl(0.4, 0.15, 0.3, 10), kit.window_glow, Vector3(mid, 3.9, 0))


## Pipes round the walkway's ceiling, with brackets.
func _pipes(t: Dictionary, f: Dictionary) -> void:
	var r := hull.gap_r + hull.walk - 1.0
	var n := 40
	for k in n:
		var a := TAU * k / n
		kit._xf = radial(t, float(f.y), a)
		var w := 2.0 * r * tan(PI / n) + 0.02
		for j in 2:
			_p(kit.box(0.3, 0.3, w), _m("rail") if j == 0 else _m("hull"), Vector3(r - j * 0.5, hull.floor_h - 1.4 - j * 0.15, 0))
		if k % 4 == 0:
			_p(kit.box(0.9, 0.08, 0.12), _m("trim"), Vector3(r - 0.25, hull.floor_h - 1.15, 0))


# ------------------------------------------------------------------ batching

## The stalls' cloth (canopies and fringes, one MeshInstance3D each; TownMarket
## shares one mesh between canopies of a size) as one MultiMesh a mesh and colour:
## a ring of stalls is a few draw calls, not hundreds. Then the shadows off.
func merge_cloth(parent: Node3D) -> void:
	var groups := {}
	for c in parent.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or str(mi.name).begins_with("Fill_"):
			continue
		var key := "%d:%d" % [mi.mesh.get_instance_id(), mi.material_override.get_instance_id() if mi.material_override != null else 0]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	for key in groups:
		var list: Array = groups[key]
		if list.size() >= 2:
			_q.append(_merge_cloth_group.bind(parent, list))
	_q.append(_no_shadows)


func _merge_cloth_group(parent: Node3D, list: Array) -> void:
	var first := list[0] as MeshInstance3D
	var mesh := first.mesh
	var mat := first.material_override
	var xfs := list.map(func(mi): return mi.transform)
	for mi: MeshInstance3D in list:
		parent.remove_child(mi)
		mi.free()
	_multimesh(mesh, mat, xfs)
