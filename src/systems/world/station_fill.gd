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
const RAIL := StationHull.RAIL_H
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
var _room_c := Vector2.ZERO         ## the floor being built: its tower's middle and how many rooms round it,
var _room_n := 0                    ## the frame the room finishes are laid out in (_t; 0: open floors)
var _win_r := 0.0                   ## the floor being built: the window's inside, where its rooms end
var _texs := {}


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
	_room_c = t.c
	_win_r = float(f.r) - StationHull.WALL
	var here: Array = hull.rooms_of(str(t.id), str(f.id))
	_room_n = roundi(PI / float(here[0].half)) if not here.is_empty() else 0
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
	var cap := int(cfg.get("mesh_verts", 24000))
	for mid in by_mat:
		var acc := { "v": [], "n": [], "uv": [] }    # transformed pieces, joined once at commit
		var part: Array = []
		var n := 0
		var verts := 0
		for it in by_mat[mid][1]:
			part.append(it)
			n += 1
			verts += _verts_of(it[0])
			if n >= chunk / 60 or verts >= cap:            # about chunk vertices of small props
				_q.append(_append.bind(acc, part))
				part = []
				n = 0
			if verts >= cap:                                # a big material (a floor's paving): a mesh a few ms to commit, not one
				_q.append(_commit.bind(acc, by_mat[mid][0]))
				acc = { "v": [], "n": [], "uv": [] }
				verts = 0
		if not part.is_empty():
			_q.append(_append.bind(acc, part))
		if verts > 0:
			_q.append(_commit.bind(acc, by_mat[mid][0]))
	_q.append(_finish)


var _flats := {}                    ## mesh instance id -> [vertices, normals, uvs], unindexed


## How many vertices _flat will give `mesh`, from its numbers (nothing built).
static func _verts_of(mesh: Mesh) -> int:
	if mesh is CylinderMesh:
		return (mesh as CylinderMesh).radial_segments * 12
	if mesh is SphereMesh:
		return (mesh as SphereMesh).radial_segments * (mesh as SphereMesh).rings * 6
	return 36


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


## A room finish (the station shader's 14 up: carpet, tile, plate, marble, velvet,
## veneer...) in colour `tint`, laid out in the frame of the room it is in (the
## floor being built: its tower's middle and room count), so tiles, planks and
## panels run with that room's walls. One material a finish, colour and floor
## frame, so a floor draws a few more meshes, not one a piece. No new shader: the
## station's own (SpaceStation._mat).
func _t(name: String, tint := Color.WHITE) -> Material:
	var key := "%s/%s/%s/%d" % [name, tint.to_html(), _room_c, _room_n]
	if _texs.has(key):
		return _texs[key]
	var base: Material = finish.call(name)
	var m := base
	if base is ShaderMaterial:
		var sm := (base as ShaderMaterial).duplicate() as ShaderMaterial
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("room_c", _room_c)
		sm.set_shader_parameter("room_n", float(_room_n))
		m = sm
	_texs[key] = m
	return m


## How far across from a room's middle line its side wall's face is at `x` out,
## less `off` metres (the room's frame; `half` is half the room's angle).
static func _wall_z(x: float, half: float, off := 0.0) -> float:
	return x * tan(half) - (StationHull.INNER_WALL * 0.5 + off) / cos(half)


## The turn that lays a box's length along side `s`'s wall.
static func _along(s: float, half: float) -> Basis:
	return Basis(UP, -s * half)


## The radius of a room floor's inner wall's face (its door's side).
func _rin() -> float:
	return hull.gap_r + hull.walk + StationHull.INNER_WALL * 0.5


## The room's floor from x0 to x1 out in `mat` (x0 at the door, r0, means from the
## inner wall): strips `step` deep across the room, cut to its shape (the inner
## wall's arc by the door, the side walls, the window's arc; _skirt hides the
## steps along the walls).
func _cover(x0: float, x1: float, half: float, mat: Material, y := 0.0, step := 0.8) -> void:
	var rin := _rin()
	if x0 <= rin + 0.5:
		x0 = rin * cos(half)
	x1 = minf(x1, _win_r)
	var x := x0
	while x < x1 - 0.05:
		var d := minf(step, x1 - x)
		var xm := x + d * 0.5
		var zo := minf(_wall_z(xm, half) + 0.05, sqrt(maxf(0.0, _win_r * _win_r - (x + d) * (x + d))))
		var zi := sqrt(maxf(0.0, rin * rin - x * x))
		if zi < 0.05:
			_p(kit.box(d, 0.02, snappedf(2.0 * zo, 0.01)), mat, Vector3(xm, y + 0.01, 0))
		elif zo > zi + 0.05:
			for s: float in [-1.0, 1.0]:
				_p(kit.box(d, 0.02, snappedf(zo - zi, 0.01)), mat, Vector3(xm, y + 0.01, s * (zo + zi) * 0.5))
		x += d


## A box `h` tall and `t` thick along both side walls, from radius r0 to r1 along
## them (cut to the inner wall and the window), its foot at `y0`, `off` metres off
## the wall (a skirting, a wainscot, a rail, a pipe run, a catwalk).
func _liner(r0: float, r1: float, half: float, y0: float, h: float, t: float, mat: Material, off := 0.0, solid := false) -> void:
	var a := maxf(r0, _rin() + 0.05)
	var b := minf(r1, _win_r - 0.05)
	var xm := (a + b) * 0.5 * cos(half)
	for s: float in [-1.0, 1.0]:
		_p(kit.box(b - a, h, t), mat, Vector3(xm, y0 + h * 0.5, s * _wall_z(xm, half, off + t * 0.5)), solid, _along(s, half))


## A spot `back` metres in from the window along side `s`'s wall, `side` metres
## off it (a room's corners by the window, where its walls meet the glass's arc).
func _corner(half: float, s: float, back: float, side: float) -> Vector3:
	var rho := _win_r - back
	var o := side + StationHull.INNER_WALL * 0.5
	return Vector3(rho * cos(half) + o * sin(half), 0, s * (rho * sin(half) - o * cos(half)))


## A skirting board along both walls: hides where the floor's strips meet them.
func _skirt(r0: float, r1: float, half: float, mat: Material) -> void:
	_liner(r0, r1, half, 0.0, 0.14, 0.3, mat)


## A ring of floor from radius r0 to r1 round the tower's middle (a walkway's
## runner, a market's paving), in bands `band` deep and `per` pieces a turn (a
## multiple of the floor's rooms, so no piece crosses into the next room's frame).
func _ring_floor(t: Dictionary, y: float, r0: float, r1: float, mat: Material, per := 96, band := 2.0, lanes: Array = []) -> void:
	var r := r0
	while r < r1 - 0.05:
		var d := minf(band, r1 - r)
		var rm := r + d * 0.5
		var w := 2.0 * (r + d) * tan(PI / per) + 0.04
		for k in per:
			var a := TAU * (k + 0.5) / per
			kit._xf = radial(t, y, a)
			_p(kit.box(d, 0.02, w), mat, Vector3(rm, 0.01, 0))
		r += d


## A lamp hanging on a cord from the ceiling to `y`: a cord, a shade, its glow.
func _pendant(at: Vector3, ceil_y: float, shade: Material, r := 0.35) -> void:
	_p(kit.cyl(0.015, 0.015, ceil_y - at.y, 4), _m("rail"), Vector3(at.x, (ceil_y + at.y) * 0.5, at.z))
	_p(kit.cyl(r * 0.35, r, r * 0.7, 10), shade, at + Vector3(0, r * 0.35, 0))
	_p(kit.ball(r * 0.4, r * 0.5, false, 8), kit.window_glow, at)


## A plant in a pot: the pot, soil, a ball of leaves (and a second, smaller one).
func _plant(at: Vector3, pot: Material, size := 1.0, solid := true) -> void:
	_p(kit.cyl(0.3 * size, 0.22 * size, 0.55 * size, 10), pot, at + Vector3(0, 0.28 * size, 0), solid)
	_p(kit.ball(0.55 * size, 0.9 * size, false, 8), _t("foliage", Color("#4f7a3c")), at + Vector3(0, 1.0 * size, 0))
	_p(kit.ball(0.35 * size, 0.6 * size, false, 8), _t("foliage", Color("#5d8a44")), at + Vector3(0.15 * size, 1.45 * size, 0.1 * size))


## A drum standing at `at` in colour `c` (barrel finish), solid.
func _barrel(at: Vector3, c: Color, h := 0.9, r := 0.3) -> void:
	_p(kit.cyl(r, r, h, 10), _t("barrel", c), at + Vector3(0, h * 0.5, 0), true)


## A shelving rack `l` long (along local z after `b`), `d` deep, `h` tall with
## `n` shelves: uprights, shelves, and stock on them from `stock` (materials).
func _rack(at: Vector3, b: Basis, l: float, d: float, h: float, n: int, frame: Material, stock: Array, seed: int) -> void:
	var was := kit._xf
	kit._xf = kit._xf * Transform3D(b, at)
	_rng.seed = seed
	for zs: float in [-0.5, 0.5]:
		for xs: float in [-0.5, 0.5]:
			_p(kit.box(0.08, h, 0.08), frame, Vector3(xs * (d - 0.08), h * 0.5, zs * (l - 0.08)))
	kit.add_collider(kit._xf * Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)), Vector3(d, h, l))
	var gap := (h - 0.2) / maxf(1.0, n - 1.0)          # between shelves; the top one is the rack's roof
	for k in n:
		var y := 0.12 + k * gap
		_p(kit.box(d, 0.05, l), frame, Vector3(0, y, 0))
		if k == n - 1:
			break
		var z := -l * 0.5 + 0.15
		while z < l * 0.5 - 0.3:
			var w := snappedf(_rng.randf_range(0.3, 0.7), 0.1)        # a few sizes, so they share meshes
			var tall := snappedf(minf(_rng.randf_range(0.25, 0.6), gap - 0.1), 0.05)
			if _rng.randf() < 0.8:
				_p(kit.box(d * 0.8, tall, w), stock[_rng.randi() % stock.size()], Vector3(0, y + 0.025 + tall * 0.5, z + w * 0.5))
			z += w + 0.08
	kit._xf = was


## A table with chairs round it: a top `l` by `w` on legs, `n` chairs a side.
func _dining(at: Vector3, l: float, w: float, n: int, top: Material, leg: Material, seat: Material) -> void:
	_p(kit.box(l, 0.06, w), top, at + Vector3(0, 0.76, 0))
	for xs: float in [-1.0, 1.0]:
		for zs: float in [-1.0, 1.0]:
			_p(kit.box(0.08, 0.73, 0.08), leg, at + Vector3(xs * (l * 0.5 - 0.15), 0.365, zs * (w * 0.5 - 0.15)))
	kit.add_collider(kit._xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.4, 0)), Vector3(l, 0.8, w))
	for s: float in [-1.0, 1.0]:
		for j in n:
			var x := -l * 0.5 + (j + 0.5) * l / n
			var cz := s * (w * 0.5 + 0.35)
			_p(kit.box(0.45, 0.08, 0.45), seat, at + Vector3(x, 0.46, cz))
			_p(kit.box(0.45, 0.55, 0.06), seat, at + Vector3(x, 0.76, cz + s * 0.22))
			for lx: float in [-0.18, 0.18]:
				_p(kit.box(0.04, 0.42, 0.04), leg, at + Vector3(x + lx, 0.21, cz))


## A framed picture on side `s`'s wall at `x` out, its middle `y` up.
func _art(x: float, half: float, s: float, y: float, w: float, h: float, tint: Color) -> void:
	_p(kit.box(w, h, 0.06), _t("art", tint), Vector3(x, y, s * _wall_z(x, half, 0.05)), false, _along(s, half))


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
	_q.append(_market_floor.bind(t, f))
	_q.append(_market_stock.bind(t, f, fc, lanes))
	_q.append(_market_lamps.bind(t, f, fc, lanes))


## A market floor's paving: dark tiles round the walkway, stone flags out to the
## glass (one material each for the whole floor, in the station's own axes).
func _market_floor(t: Dictionary, f: Dictionary) -> void:
	var y := float(f.y)
	var rw := hull.gap_r + hull.walk
	_ring_floor(t, y, hull.gap_r + 0.2, rw, _t("tile", Color("#4a4d52")))
	_ring_floor(t, y, rw, _win_r, _t("pavers", Color("#8a8072")))


## Stock piled in the gaps behind back-to-back rings of stalls (a ring facing in
## with the next facing out): crates, drums, sacks and tarped heaps, every
## `stock_every_m` round, none on a lane.
func _market_stock(t: Dictionary, f: Dictionary, fc: Dictionary, lanes: Array) -> void:
	var y := float(f.y)
	var rings: Array = fc.get("rings", [])
	var every := float(fc.get("stock_every_m", 4.5))
	var drums := [Color("#8a3a2a"), Color("#2f5d8a"), Color("#b08a3a"), Color("#3f6f6a")]
	for i in range(rings.size() - 1):
		var ra: Dictionary = rings[i]
		var rb: Dictionary = rings[i + 1]
		if str(ra.get("face", "in")) != "in" or str(rb.get("face", "in")) != "out" or bool(rb.get("pack", false)):
			continue
		var r := (float(ra.r) + float(rb.r)) * 0.5
		var n := floori(TAU * r / every)
		for k in n:
			var a := (k + 0.5) * TAU / n
			if not _clear(a, r, 1.6, lanes):
				continue
			kit._xf = radial(t, y, a) * Transform3D(Basis.IDENTITY, Vector3(r, 0, 0))
			_rng.seed = hash("%s_%s_stock_%d" % [str(t.id), str(f.id), k])
			match _rng.randi() % 4:
				0:
					_p(kit.box(1.0, 0.8, 1.0), kit.crate_woods[k % 3], Vector3(-0.3, 0.4, -0.4), true, Basis(UP, 0.1))
					_p(kit.box(0.9, 0.7, 0.9), kit.crate_woods[(k + 1) % 3], Vector3(0.6, 0.35, 0.5), true)
					_p(kit.box(0.7, 0.6, 0.7), kit.crate_woods[(k + 2) % 3], Vector3(-0.3, 1.1, -0.4), true, Basis(UP, -0.2))
				1:
					for j in 4:
						_barrel(Vector3((j % 2) * 0.65 - 0.3, 0, (j / 2) * 0.65 - 0.3), drums[(j + k) % drums.size()])
				2:
					var sack := mats.canvas(Color("#a08a62"))
					for j in 5:
						_p(kit.ball(0.4, 0.45, false, 8), sack, Vector3((j % 3) * 0.6 - 0.6, 0.22 + (j / 3) * 0.38, (j / 3) * 0.2 - 0.1))
					_p(kit.box(1.0, 0.8, 1.0), kit.crate_woods[k % 3], Vector3(0.4, 0.4, 0.9), true)
				3:
					_p(kit.box(1.8, 0.9, 1.4), kit.crate_woods[k % 3], Vector3(0, 0.45, 0), true)
					_p(kit.box(2.0, 0.08, 1.6), mats.canvas(FABRICS[k % FABRICS.size()]), Vector3(0, 0.95, 0), false, Basis(Vector3.BACK, 0.06))
					_barrel(Vector3(0.2, 0, -1.2), drums[k % drums.size()])
			_count("stock")


## Lamp posts round the walkway's edge, `lamps` of them (planters at every other),
## and `banners` hung from the ceiling over the gap behind the first rings.
func _market_lamps(t: Dictionary, f: Dictionary, fc: Dictionary, lanes: Array) -> void:
	var y := float(f.y)
	var rl := hull.gap_r + hull.walk + 0.7
	var n := int(fc.get("lamps", 16))
	for k in n:
		var a := (k + 0.25) * TAU / n
		if not _clear(a, rl, 1.0, lanes):
			continue
		kit._xf = radial(t, y, a)
		_p(kit.cyl(0.22, 0.28, 0.3, 10), _m("trim"), Vector3(rl, 0.15, 0), true)
		_p(kit.cyl(0.07, 0.07, 4.6, 8), _m("rail"), Vector3(rl, 2.6, 0), true)
		_p(kit.box(1.0, 0.06, 0.06), _m("trim"), Vector3(rl - 0.4, 4.8, 0))
		_p(kit.cyl(0.1, 0.25, 0.25, 10), _m("trim"), Vector3(rl - 0.85, 4.7, 0))
		_p(kit.ball(0.16, 0.2, false, 8), kit.window_glow, Vector3(rl - 0.85, 4.55, 0))
		if k % 2 == 0:
			_plant(Vector3(rl, 0, 1.0), _t("barrel", Color("#6a4a32")), 0.9)
		_count("lamp")
	var rings: Array = fc.get("rings", [])
	if rings.size() < 2:
		return
	var rb := (float(rings[0].r) + float(rings[1].r)) * 0.5
	var nb := int(fc.get("banners", 24))
	var top := hull.floor_h - 0.3
	for k in nb:
		var a := (k + 0.5) * TAU / nb
		kit._xf = radial(t, y, a)
		var h := 4.0 + (k % 3) * 0.8
		_p(kit.box(0.06, h, 1.4), mats.canvas(FABRICS[k % FABRICS.size()]), Vector3(rb, top - h * 0.5, 0))
		_p(kit.box(0.08, 0.08, 1.6), _m("rail"), Vector3(rb, top, 0))
		_p(kit.box(0.08, 0.06, 1.4), _m("trim"), Vector3(rb, top - h, 0))
		_count("banner")


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
## club and the party barge; a carpet runner round the walkway.
func _suites(t: Dictionary, f: Dictionary, fc: Dictionary) -> void:
	var r0 := hull.gap_r + hull.walk + 0.4
	var r1 := float(f.r) - StationHull.WALL
	var k := 0
	for room in hull.rooms_of(str(t.id), str(f.id)):
		if not bool(room.open):
			continue
		var at := radial(t, float(f.y), float(room.a))
		_q.append(_suite.bind(at, r0, r1, float(room.half), k))
		_q.append(_suite_more.bind(at, r0, r1, float(room.half), k))
		k += 1
		_count("suite")
	_q.append(_ring_floor.bind(t, float(f.y), hull.gap_r + 0.2, hull.gap_r + hull.walk - 0.25, _t("carpet", Color("#3a1f2a")), _room_n * 10))


## A suite's materials, shared by its two halves: k picks its velvets.
func _suite_mats(k: int) -> Dictionary:
	return {
		"velvet": _t("velvet", VELVETS[k % VELVETS.size()].lightened(0.1)),
		"velvet2": _t("velvet", VELVETS[(k + 1) % VELVETS.size()].lightened(0.05)),
		"gold": _t("brass", Color("#d4af37")),
		"wood": _t("veneer", Color("#5a3826")),
		"black": _t("marble", Color("#1b1a1f")),
		"white": _t("marble", Color("#e9e4da")),
		"linen": _t("cloth", Color("#e6e0d2")),
		"neon": _glow(NEONS[k % NEONS.size()], 3.0),
	}


## A suite: a marble foyer and lacquered plank floors, veneer panelling with a
## brass rail under a fabric wall, neon lines along the walls, a bar with lit
## bottles and an aquarium by the door, two velvet booths on rugs under
## chandeliers, a light-up dance floor between them ringed by cocktail tables, a
## long sofa, a piano in every other one, a round bed with a gold canopy by the
## window, plants in gold pots.
func _suite(at: Transform3D, r0: float, r1: float, half: float, k: int) -> void:
	kit._xf = at
	var depth := r1 - r0
	var m := _suite_mats(k)
	var velvet: Material = m.velvet
	var velvet2: Material = m.velvet2
	var gold: Material = m.gold
	var wood: Material = m.wood
	var black: Material = m.black
	var neon: Material = m.neon
	var ceil_y := hull.floor_h
	# The floor: white marble in the foyer by the door, then lacquered planks.
	_cover(r0, r0 + 6.0, half, m.white)
	_cover(r0 + 6.0, r1, half, _t("woodfloor", Color("#6a4630")))
	_skirt(r0, r1, half, wood)
	# Veneer panelling to 2.4 m with a brass rail, fabric above it to 9 m and a
	# second rail; neon lines along the floor and under the ceiling.
	_liner(r0, r1, half, 0.14, 2.26, 0.08, wood)
	_liner(r0, r1, half, 2.4, 0.08, 0.14, gold)
	_liner(r0, r1, half, 2.48, 6.5, 0.04, _t("cloth", Color("#3a2a30")))
	_liner(r0, r1, half, 8.98, 0.08, 0.12, gold)
	_liner(r0, r1, half, ceil_y - 0.5, 0.06, 0.06, neon)
	_liner(r0, r1, half, 0.14, 0.03, 0.05, neon, 0.2)
	# The bar by the door, lit bottles on brass shelves behind it, stools.
	var bx := r0 + 4.0
	var bz := _half_w(bx, half) - 0.6
	_p(kit.box(3.4, 1.05, 0.7), wood, Vector3(bx, 0.52, bz), true)
	_p(kit.box(3.5, 0.06, 0.8), black, Vector3(bx, 1.08, bz))
	_p(kit.box(3.4, 0.05, 0.06), gold, Vector3(bx, 0.95, bz - 0.38))
	_p(kit.box(3.4, 0.04, 0.04), neon, Vector3(bx, 0.1, bz - 0.36))
	var sz := _half_w(bx, half) - 0.1
	_p(kit.box(3.2, 2.2, 0.08), _t("marble", Color("#2a2430")), Vector3(bx, 2.05, sz + 0.06))
	for q in 3:
		_p(kit.box(3.0, 0.04, 0.3), gold, Vector3(bx, 1.5 + q * 0.5, sz))
	for j in 15:
		var c: Color = NEONS[(j + k) % NEONS.size()]
		_p(kit.cyl(0.05, 0.06, 0.32, 6), _glow(c.darkened(0.25), 1.6), Vector3(bx - 1.35 + (j % 5) * 0.68, 1.68 + (j / 5) * 0.5, sz))
	for j in 3:
		var stz := bz - 0.85
		_p(kit.cyl(0.04, 0.06, 0.72, 6), gold, Vector3(bx - 1.0 + j * 1.0, 0.36, stz))
		_p(kit.cyl(0.22, 0.22, 0.08, 10), velvet, Vector3(bx - 1.0 + j * 1.0, 0.76, stz))
	# An aquarium along the other wall by the door: lit water on a marble plinth.
	var az := -(_half_w(bx, half) - 0.45)
	_p(kit.box(3.0, 0.5, 0.7), black, Vector3(bx, 0.25, az), true)
	_p(kit.box(2.9, 1.3, 0.6), _t("water", Color("#2a8fd8")), Vector3(bx, 1.15, az))
	_p(kit.box(3.0, 0.08, 0.7), gold, Vector3(bx, 1.84, az))
	for j in 5:
		_p(kit.box(0.04, 0.3 + (j % 3) * 0.15, 0.04), _t("foliage", Color("#4f7a3c")), Vector3(bx - 1.1 + j * 0.55, 0.7 + (j % 3) * 0.07, az))
	# Two lounges: a velvet booth round a cocktail table on a rug, a chandelier over it.
	for li in 2:
		var lx := r0 + depth * (0.3 if li == 0 else 0.68)
		var vm := velvet if li == 0 else velvet2
		_p(kit.box(5.5, 0.02, minf(6.0, 2.0 * _half_w(lx - 2.75, half))), _t("rug", VELVETS[(k + li + 2) % VELVETS.size()].lightened(0.1)), Vector3(lx, 0.035, 0))
		_lounge(lx, vm, gold, black)
		_chandelier(lx + 0.4, ceil_y, 5.6, gold)
	# A light-up dance floor between the lounges, like the barge's, a chandelier over it.
	var dx := r0 + depth * 0.49
	for i in 5:
		for j in 5:
			var c2: Color = NEONS[(k + (i + j) % 2) % NEONS.size()]
			_p(kit.box(0.95, 0.04, 0.95), _glow(c2.darkened(0.35), 1.4), Vector3(dx + (i - 2) * 1.0, 0.05, (j - 2) * 1.0))
	_p(kit.box(5.2, 0.03, 5.2), black, Vector3(dx, 0.035, 0))
	_chandelier(dx, ceil_y, 6.4, gold, 1.4)
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
	for s: float in [-1.0, 1.0]:                                  # side tables and lamps at its ends
		var ex := fx + s * 2.75
		var ez := _half_w(ex, half) - 0.6
		_p(kit.box(0.5, 0.55, 0.5), wood, Vector3(ex, 0.28, ez), true)
		_p(kit.cyl(0.16, 0.2, 0.3, 10), m.linen, Vector3(ex, 0.95, ez))
		_p(kit.cyl(0.03, 0.05, 0.3, 6), gold, Vector3(ex, 0.7, ez))
		_p(kit.ball(0.1, 0.14, false, 6), kit.window_glow, Vector3(ex, 0.95, ez))
	# A grand piano in every other suite, across from the sofa.
	if k % 2 == 0:
		var px := r0 + depth * 0.58
		var pz := -(_half_w(px, half) - 1.4)
		var lacquer := mats.flat(Color("#141216"), 0.12, 0.4)
		_p(kit.box(1.6, 0.35, 1.4), lacquer, Vector3(px, 0.9, pz), true)
		_p(kit.box(1.5, 0.04, 1.3), lacquer, Vector3(px - 0.2, 1.4, pz), false, Basis(Vector3.BACK, 0.45))
		_p(kit.box(0.2, 0.06, 1.2), mats.flat(Color("#ece6d8"), 0.4), Vector3(px + 0.85, 0.98, pz))
		for s: float in [-0.55, 0.55]:
			_p(kit.cyl(0.05, 0.05, 0.75, 6), gold, Vector3(px, 0.37, pz + s))
		_p(kit.box(0.4, 0.5, 1.0), velvet, Vector3(px + 1.4, 0.25, pz), true)
	# The round bed by the window under a gold canopy, on a rug; nightstands with lamps.
	var rx := r1 - 4.5
	_p(kit.box(5.6, 0.02, 5.6), _t("rug", Color("#c9b48a")), Vector3(rx, 0.035, 0))
	_p(kit.cyl(1.8, 1.8, 0.5, 16), velvet, Vector3(rx, 0.25, 0), true)
	_p(kit.cyl(1.7, 1.7, 0.1, 16), m.linen, Vector3(rx, 0.55, 0))
	_p(kit.cyl(1.3, 1.3, 0.04, 16), velvet2, Vector3(rx + 0.4, 0.62, 0))
	for s: float in [-0.45, 0.45]:
		_p(kit.box(0.4, 0.2, 0.7), m.linen, Vector3(rx - 1.1, 0.7, s))
	for j in 4:
		var a := PI * 0.25 + j * PI * 0.5
		_p(kit.cyl(0.05, 0.05, 2.8, 6), gold, Vector3(rx + cos(a) * 1.9, 1.4, sin(a) * 1.9))
	_ring_of(rx, 1.9, 2.8, 0.08, gold, 12)
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.5, 0.55, 0.5), wood, Vector3(rx - 1.2, 0.28, s * 2.4), true)
		_p(kit.cyl(0.18, 0.12, 0.3, 10), kit.window_glow, Vector3(rx - 1.2, 0.85, s * 2.4))
	# Plants in gold pots in the window's corners.
	for s: float in [-1.0, 1.0]:
		_plant(_corner(half, s, 1.0, 0.7), gold)


## The rest of a suite: a dining table under pendants, a lounge round a wall
## screen, bookcases, a reading nook, a hot tub and loungers by the window, drapes
## at the glass, statues at the dance floor's corners, pictures on the walls.
func _suite_more(at: Transform3D, r0: float, r1: float, half: float, k: int) -> void:
	kit._xf = at
	var m := _suite_mats(k)
	var ceil_y := hull.floor_h
	var gold: Material = m.gold
	var wood: Material = m.wood
	var depth := r1 - r0
	# The dining table across from the bar's side, six chairs, a rug, pendants.
	var ex := r0 + 9.6
	var ez := -(_half_w(ex, half) - 3.2)
	_p(kit.box(4.8, 0.02, 3.2), _t("rug", Color("#7a6a52")), Vector3(ex, 0.035, ez))
	_dining(Vector3(ex, 0, ez), 3.2, 1.2, 3, wood, gold, m.velvet)
	for j in 3:
		_pendant(Vector3(ex - 1.0 + j * 1.0, 3.1, ez), ceil_y, gold, 0.28)
	# A screen on the wall over the bar's side, a sofa facing it, a low table, a rug.
	var tx := r0 + 9.6
	var tw := _half_w(tx, half)
	_p(kit.box(3.4, 1.9, 0.06), _m("screen"), Vector3(tx, 3.6, _wall_z(tx, half, 0.04)), false, _along(1.0, half))
	_p(kit.box(4.4, 0.02, 3.0), _t("rug", Color("#2f3c4a")), Vector3(tx, 0.035, tw - 2.6))
	_p(kit.box(3.2, 0.45, 0.85), m.velvet2, Vector3(tx, 0.225, tw - 3.6), true)
	_p(kit.box(3.2, 0.7, 0.22), m.velvet2, Vector3(tx, 0.7, tw - 4.0))
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.22, 0.62, 0.85), m.velvet2, Vector3(tx + s * 1.6, 0.31, tw - 3.6))
	_p(kit.box(1.4, 0.4, 0.7), m.black, Vector3(tx, 0.2, tw - 2.4), true)
	_lamp(Vector3(tx + 2.2, 0, tw - 3.8), kit.window_glow)
	# Two bookcases along the piano's wall, toward the window.
	for j in 2:
		var cx := r0 + depth * 0.71 + j * 2.6
		var cz := -_wall_z(cx, half, 0.25)
		var b := _along(-1.0, half)
		_p(kit.box(2.5, 2.8, 0.5), wood, Vector3(cx, 1.4, cz - 0.02), true, b)
		_p(kit.box(2.3, 2.4, 0.04), _t("books", Color("#2a1c14")), Vector3(cx, 1.4, cz + 0.25 / cos(half)), false, b)
	# A reading nook on the sofa's side toward the window: two armchairs, a table, a lamp.
	var nx := r0 + depth * 0.76
	var nz := _half_w(nx, half) - 2.0
	for s: float in [-1.0, 1.0]:
		var cxx := nx + s * 0.9
		_p(kit.box(0.85, 0.42, 0.85), m.velvet, Vector3(cxx, 0.21, nz), true)
		_p(kit.box(0.85, 0.75, 0.2), m.velvet, Vector3(cxx, 0.7, nz + 0.4))
		for e: float in [-0.4, 0.4]:
			_p(kit.box(0.14, 0.62, 0.85), m.velvet, Vector3(cxx + e, 0.31, nz))
	_p(kit.cyl(0.32, 0.32, 0.04, 12), m.white, Vector3(nx, 0.6, nz - 0.3))
	_p(kit.cyl(0.04, 0.06, 0.6, 6), gold, Vector3(nx, 0.3, nz - 0.3), true)
	_lamp(Vector3(nx, 0, nz + 0.9), kit.window_glow)
	# A hot tub by the window on the sofa's side, loungers on the other.
	var hx := r1 - 3.6
	var hz := _half_w(hx, half) - 3.6
	_p(kit.cyl(1.7, 1.8, 0.75, 20), m.white, Vector3(hx, 0.375, hz), true)
	_p(kit.cyl(1.5, 1.5, 0.04, 20), _t("water", Color("#2a8fd8")), Vector3(hx, 0.74, hz))
	_p(kit.box(0.6, 0.3, 1.2), m.white, Vector3(hx - 2.0, 0.15, hz))
	for j in 2:
		var lz := -(_half_w(hx, half) - 2.6 - j * 1.4)
		_p(kit.box(2.0, 0.3, 0.75), wood, Vector3(hx - 0.6, 0.15, lz), true)
		_p(kit.box(1.4, 0.1, 0.7), m.linen, Vector3(hx - 0.35, 0.35, lz))
		_p(kit.box(0.6, 0.1, 0.7), m.linen, Vector3(hx - 1.3, 0.5, lz), false, Basis(Vector3.BACK, -0.5))
	# Drapes either side of the glass and two between, hung from its top band.
	var rd := r1 - 0.45
	for zz: float in [-0.88, -0.4, 0.4, 0.88]:
		var z := zz * _half_w(rd * cos(half), half)
		var x := sqrt(rd * rd - z * z)
		_p(kit.box(0.14, ceil_y - 1.1, 1.4), m.velvet2, Vector3(x, (ceil_y - 1.1) * 0.5 + 0.05, z), false, Basis(UP, -atan2(z, x)))
	# Statues on marble plinths at the dance floor's corners.
	var dx := r0 + depth * 0.49
	for xs: float in [-3.1, 3.1]:
		for zs: float in [-3.5, 3.5]:
			var p := Vector3(dx + xs, 0, zs)
			_p(kit.box(0.7, 1.1, 0.7), m.white, p + Vector3(0, 0.55, 0), true)
			_p(kit.cyl(0.08, 0.12, 0.9, 8), gold, p + Vector3(0, 1.55, 0))
			_p(kit.ball(0.3, 0.6, false, 12), gold, p + Vector3(0, 2.2, 0))
			_p(kit.cyl(0.22, 0.1, 0.25, 8), m.black, p + Vector3(0, 1.22, 0))
	# Pictures on both walls over the panelling.
	var tints := [Color("#b0484a"), Color("#3f7a8a"), Color("#c99a3a"), Color("#6a4a8a")]
	for j in 3:
		var px := r0 + depth * (0.2 + j * 0.3)
		for s: float in [-1.0, 1.0]:
			if s > 0.0 and j == 0:
				continue                              # the screen is on that wall there
			_art(px, half, s, 4.8, 2.6, 1.7, tints[(j + k + (1 if s > 0.0 else 0)) % tints.size()])
	# More plants along the walls.
	for px: float in [r0 + 7.0, r0 + depth * 0.82]:
		for s: float in [-1.0, 1.0]:
			_plant(Vector3(px, 0, s * (_half_w(px, half) - 0.6)), gold, 1.1)


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


## A chandelier hanging from the ceiling at (x, 0) down to `y`: a gold dish, a
## ring of lit globes and a second, smaller ring under it, `size` across.
func _chandelier(x: float, ceil_y: float, y: float, gold: Material, size := 1.0) -> void:
	_p(kit.cyl(0.02, 0.02, ceil_y - y, 6), gold, Vector3(x, (ceil_y + y) * 0.5, 0))
	_p(kit.cyl(0.9 * size, 0.5 * size, 0.15, 12), gold, Vector3(x, y, 0))
	for j in 8:
		var a := TAU * j / 8.0
		_p(kit.ball(0.11, 0.22, false, 8), kit.window_glow, Vector3(x + cos(a) * 0.8 * size, y - 0.15, sin(a) * 0.8 * size))
	for j in 6:
		var a := TAU * (j + 0.5) / 6.0
		_p(kit.ball(0.08, 0.16, false, 8), kit.window_glow, Vector3(x + cos(a) * 0.45 * size, y - 0.55, sin(a) * 0.45 * size))
	_p(kit.cyl(0.5 * size, 0.2 * size, 0.1, 10), gold, Vector3(x, y - 0.45, 0))
	_p(kit.ball(0.16, 0.32, false, 8), kit.window_glow, Vector3(x, y - 0.3, 0))


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
	_q.append(_ring_floor.bind(t, float(f.y), hull.gap_r + 0.2, hull.gap_r + hull.walk - 0.25, _t("plate", Color("#4a4e55")), _room_n * 12))


func _remnant_room(r: Dictionary) -> void:
	kit._xf = r.frame
	var r0 := float(r.r0)
	var r1 := float(r.r1)
	var half := float(r.half)
	var use := str(r.use)
	# Every room: its floor (by use), a skirting and a steel rail round it, a
	# stripe down the middle, red lamps along the walls, lamps hung down the middle.
	var floors := { "control": ["plate", "#4a4e55"], "bunks": ["rubber", "#5a5e55"], "armoury": ["plate", "#4a4e55"],
		"command": ["carpet", "#4a5470"], "mess": ["tile", "#c9c6bd"] }
	var fl: Array = floors.get(use, ["plate", "#4a4e55"])
	_cover(r0, r1, half, _t(str(fl[0]), Color(str(fl[1]))))
	_skirt(r0, r1, half, _m("trim"))
	_liner(r0, r1, half, 1.2, 0.1, 0.1, _m("trim"))
	_p(kit.box(r1 - r0 - 1.0, 0.02, 0.5), _fm("mark"), Vector3((r0 + r1) * 0.5, 0.03, 0))
	_liner(r0, r1, half, hull.floor_h - 0.64, 0.08, 0.08, _fm("lamp"), 0.1)
	if use != "control":
		for j in 3:
			_pendant(Vector3(r0 + 6.0 + j * (r1 - r0 - 10.0) / 2.0, 4.6, 0.0), hull.floor_h, _m("trim"), 0.45)
	match use:
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
			_control_more(r0, r1, half)
		"bunks":
			_bunks(r0, r1, half)
		"armoury":
			_armoury(r0, r1, half)
		"command":
			_command(r0, r1, half)
		"mess":
			_mess(r0, r1, half)


## Round the control room: racks of computers along both walls, crates and drums
## in the window's corners.
func _control_more(r0: float, r1: float, half: float) -> void:
	var x := r0 + 2.0
	while x < r0 + 18.0:
		for s: float in [-1.0, 1.0]:
			_p(kit.box(1.2, 2.3, 0.7), _m("console"), Vector3(x, 1.15, s * _wall_z(x, half, 0.4)), true, _along(s, half))
			_p(kit.box(1.0, 0.06, 0.06), _fm("lamp"), Vector3(x, 2.35, s * _wall_z(x, half, 0.8)), false, _along(s, half))
		x += 1.6
	var drums := [Color("#3b3f45"), Color("#59604c")]
	for s: float in [-1.0, 1.0]:
		var c := _corner(half, s, 1.6, 1.4)
		_p(kit.box(1.2, 1.0, 1.2), _m("cargo"), c + Vector3(0, 0.5, 0), true)
		_p(kit.box(1.0, 0.8, 1.0), _m("cargo"), c + Vector3(0, 1.4, 0), true)
		for j in 3:
			_barrel(_corner(half, s, 1.0, 3.0 + j * 0.7), drums[j % 2])


## Two-high bunks down both sides (posts, frames, mattresses, pillows), a
## footlocker at each foot, a reading light over each, lockers along the window,
## a screen over them, card tables down the middle, a rifle rack by the door.
func _bunks(r0: float, r1: float, half: float) -> void:
	var frame := mats.painted(Color("#3b3f45"), 0.5, 0.6)
	var cloth := _t("cloth", Color("#59604c"))
	var pillow := _t("cloth", Color("#c9c3b2"))
	var steel := _t("locker", Color("#4c5259"))
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
			_p(kit.box(0.3, 0.06, 0.12), kit.window_glow, Vector3(x - 0.7, 2.1, z + s * 0.4))
		x += 2.7
	# Lockers round the window's arc, facing in, a screen over the middle ones.
	var rho := _win_r - 0.4
	var span := half - asin(1.2 / rho)
	var n := maxi(2, floori(2.0 * span * rho / 0.65))
	for k in n:
		var a := -span + (k + 0.5) * 2.0 * span / n
		var at := Vector3(cos(a), 0, sin(a)) * rho
		_p(kit.box(0.6, 2.0, 0.6), steel, at + Vector3(0, 1.0, 0), true, Basis(UP, -a))
		_p(kit.box(0.02, 0.05, 0.5), _fm("band"), at + Vector3(-0.31 * cos(a), 1.7, -0.31 * sin(a)), false, Basis(UP, -a))
	_p(kit.box(0.08, 1.7, 3.0), _m("screen"), Vector3(rho - 0.2, 3.4, 0))
	# Card tables down the middle, cups and cards on them.
	var seat := _t("cloth", Color("#59604c"))
	for tx: float in [r0 + 10.0, r0 + 17.0]:
		_dining(Vector3(tx, 0, 0), 2.4, 1.0, 2, _t("plate", Color("#8a8f96")), frame, seat)
		for j in 4:
			_p(kit.box(0.09, 0.01, 0.06), mats.flat(Color("#e8e4da"), 0.5), Vector3(tx - 0.6 + j * 0.35, 0.795, 0.1 * (j % 2)))
		_p(kit.cyl(0.04, 0.035, 0.1, 6), steel, Vector3(tx + 0.8, 0.84, 0.25))
	# A rifle rack against the inner wall beside the door.
	var rz := -(2.6 + 1.6)
	var rx := sqrt(maxf(0.0, pow(_rin() + 0.25, 2.0) - rz * rz))
	_p(kit.box(0.35, 1.8, 2.4), _m("trim"), Vector3(rx, 0.9, rz), true)
	for k in 6:
		_p(kit.box(0.14, 1.15, 0.08), mats.painted(Color("#1d1f22"), 0.4, 0.7), Vector3(rx + 0.26, 1.0, rz - 1.0 + k * 0.4))


## Rifle racks down both sides, ammunition crates, a workbench with rifles in
## pieces, armour on stands, a hazard line before a cage at the end with racks of
## ammunition in it.
func _armoury(r0: float, r1: float, half: float) -> void:
	var dark := mats.painted(Color("#1d1f22"), 0.4, 0.7)
	var x := r0 + 3.0
	while x < r1 - 6.0:
		for s: float in [-1.0, 1.0]:
			var z := s * (_half_w(x, half) - 0.5)
			_p(kit.box(2.4, 2.0, 0.4), _t("locker", Color("#4c5259")), Vector3(x, 1.0, z), true)
			for k in 6:
				_p(kit.box(0.08, 1.15, 0.14), dark, Vector3(x - 1.0 + k * 0.4, 1.0, z - s * 0.26))
			_p(kit.box(2.4, 0.06, 0.06), _fm("lamp"), Vector3(x, 2.05, z - s * 0.22))
			if int(x) % 2 == 0:
				_p(kit.box(1.6, 0.5, 0.6), _m("cargo"), Vector3(x, 0.25, z - s * 1.0), true)
		x += 3.2
	for k in 6:
		var cx := r0 + 4.0 + (k % 3) * 1.4
		var cz := -1.2 + (k / 3) * 2.4
		_p(kit.box(1.0, 0.7, 0.8), _m("cargo"), Vector3(cx, 0.35 + (0.7 if k == 4 else 0.0), cz), true)
	_p(kit.box(2.6, 0.95, 1.0), _m("console"), Vector3(r1 - 7.0, 0.48, 0), true)
	_p(kit.box(2.6, 0.06, 1.1), _t("plate", Color("#8a8f96")), Vector3(r1 - 7.0, 0.98, 0))
	for k in 5:
		_p(kit.box(0.12 + (k % 2) * 0.5, 0.06, 0.1), dark, Vector3(r1 - 7.9 + k * 0.42, 1.04, -0.2 + (k % 3) * 0.15))
	_p(kit.box(0.25, 0.2, 0.2), _m("hull"), Vector3(r1 - 5.9, 1.11, 0.3))
	# Armour on stands, two rows of four.
	var white := _t("cloth", Color("#c9c3b2"))
	for s: float in [-1.0, 1.0]:
		for j in 4:
			var p := Vector3(r0 + 12.0 + j * 2.0, 0, s * 5.0)
			_p(kit.cyl(0.35, 0.35, 0.06, 10), _m("trim"), p + Vector3(0, 0.03, 0), true)
			_p(kit.cyl(0.04, 0.04, 1.2, 6), _m("rail"), p + Vector3(0, 0.6, 0))
			_p(kit.box(0.3, 0.6, 0.5), white, p + Vector3(0, 1.45, 0))
			_p(kit.box(0.32, 0.2, 0.56), white, p + Vector3(0, 1.82, 0))
			_p(kit.ball(0.15, 0.3, false, 10), white, p + Vector3(0, 2.1, 0))
			_p(kit.box(0.02, 0.05, 0.2), _fm("band"), p + Vector3(-0.16, 1.5, 0))
	# The cage: a hazard line before it, bars, and ammunition racks inside.
	var cw := _half_w(r1 - 3.0, half) - 0.8
	_p(kit.box(0.5, 0.02, cw * 2.0), _t("hazard", Color("#e0b030")), Vector3(r1 - 4.8, 0.03, 0))
	for k in 9:
		var z := -cw + k * cw * 2.0 / 8.0
		_p(kit.box(0.06, 3.0, 0.06), _fm("band"), Vector3(r1 - 4.0, 1.5, z))
	_p(kit.box(0.08, 0.08, cw * 2.0), _fm("lamp"), Vector3(r1 - 4.0, 3.0, 0))
	var stock := [_m("cargo"), _t("hazard", Color("#e0b030")), _t("locker", Color("#4c5259"))]
	for j in 3:
		var z := (j - 1) * 5.5
		var rx := minf(r1 - 2.0, sqrt(_win_r * _win_r - pow(absf(z) + 2.2, 2.0)) - 0.9)
		_rack(Vector3(rx, 0, z), Basis.IDENTITY, 3.6, 0.9, 2.4, 4, _m("trim"), stock, 900 + j)


## The commander's office: a desk to the door with a chair on a rug, a wall of
## screens, a map table and the Remnant's banners either side; carpet, veneer
## panelling, bookcases, a conference table, a drinks cabinet, a globe, armchairs
## in the window's corners.
func _command(r0: float, r1: float, half: float) -> void:
	var dx := r0 + 12.0
	var wood := _t("veneer", Color("#3a2a22"))
	var leather := _t("velvet", Color("#3a2418"))
	_liner(r0, r1, half, 0.14, 2.06, 0.08, wood)
	_p(kit.box(4.0, 0.02, 5.0), _t("rug", Color("#3a3f52")), Vector3(dx + 0.3, 0.035, 0))
	_p(kit.box(1.1, 0.8, 3.0), wood, Vector3(dx, 0.4, 0), true)
	_p(kit.box(1.2, 0.06, 3.1), _t("marble", Color("#1b1a1f")), Vector3(dx, 0.82, 0))
	_p(kit.box(0.6, 0.5, 0.6), leather, Vector3(dx + 1.0, 0.45, 0), true)
	_p(kit.box(0.15, 0.9, 0.6), leather, Vector3(dx + 1.3, 1.1, 0))
	_p(kit.box(0.4, 0.3, 0.05), _m("screen"), Vector3(dx - 0.1, 1.0, 0.8), false, Basis(UP, PI * 0.5))
	_p(kit.box(0.08, 2.4, 5.0), _m("screen"), Vector3(r1 - 1.2, 2.6, 0))
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.08, 4.5, 1.4), _fm("mark"), Vector3(r1 - 1.3, 6.0, s * 3.6))
	_p(kit.box(2.4, 0.9, 1.6), _m("console"), Vector3(r0 + 5.0, 0.45, 0), true)
	_p(kit.box(2.2, 0.04, 1.4), _fm("lamp"), Vector3(r0 + 5.0, 0.92, 0))
	for s: float in [-1.0, 1.0]:
		var z := s * (_half_w(r0 + 8.0, half) - 0.3)
		_p(kit.box(4.0, 0.9, 0.05), _m("screen"), Vector3(r0 + 8.0, 1.8, z))
	# Bookcases down both walls toward the window.
	for s: float in [-1.0, 1.0]:
		for j in 3:
			var cx := r0 + 14.5 + j * 2.6
			var cz := s * _wall_z(cx, half, 0.25)
			_p(kit.box(2.5, 3.0, 0.5), wood, Vector3(cx, 1.5, cz), true, _along(s, half))
			_p(kit.box(2.3, 2.6, 0.04), _t("books", Color("#2a1c14")), Vector3(cx, 1.5, cz - s * 0.25 / cos(half)), false, _along(s, half))
	# The conference table under two lamps, chairs round it.
	var tx := r0 + 18.5
	_dining(Vector3(tx, 0, 0), 4.0, 1.4, 4, wood, _m("trim"), leather)
	for j in 2:
		_pendant(Vector3(tx - 1.0 + j * 2.0, 2.8, 0.0), hull.floor_h, _m("trim"), 0.35)
	# A drinks cabinet by the door, a globe by the desk.
	var cbx := r0 + 3.0
	var cbz := -(_half_w(cbx, half) - 0.4)
	_p(kit.box(1.6, 1.0, 0.5), wood, Vector3(cbx, 0.5, cbz), true)
	_p(kit.box(1.7, 0.05, 0.55), _t("marble", Color("#1b1a1f")), Vector3(cbx, 1.02, cbz))
	for j in 4:
		_p(kit.cyl(0.04, 0.05, 0.28, 6), _glow(NEONS[j % NEONS.size()].darkened(0.4), 1.2), Vector3(cbx - 0.5 + j * 0.32, 1.19, cbz))
	_p(kit.cyl(0.2, 0.3, 0.06, 10), _m("trim"), Vector3(dx - 1.6, 0.03, 3.0), true)
	_p(kit.cyl(0.03, 0.03, 0.9, 6), _m("rail"), Vector3(dx - 1.6, 0.45, 3.0))
	_p(kit.ball(0.35, 0.7, false, 14), _t("art", Color("#3f6f8a")), Vector3(dx - 1.6, 1.2, 3.0))
	# Armchairs round a low table in the window's corners.
	for s: float in [-1.0, 1.0]:
		var c := _corner(half, s, 3.2, 2.2)
		for e: float in [-0.9, 0.9]:
			_p(kit.box(0.85, 0.42, 0.85), leather, c + Vector3(e, 0.21, 0), true)
			_p(kit.box(0.2, 0.75, 0.85), leather, c + Vector3(e + 0.42 * signf(e), 0.7, 0))
		_p(kit.box(0.6, 0.4, 0.6), wood, c + Vector3(0, 0.2, 0), true)
		_plant(c + Vector3(0, 0, -s * 1.6), _m("trim"))


## The mess: long tables with benches and trays on them, a serving counter with
## hot food under glass, the kitchen behind it (cooktops under a hood, fridges,
## shelves of pots), tile on the walls, bins and a water dispenser by the door.
func _mess(r0: float, r1: float, half: float) -> void:
	var tile := _t("tile", Color("#d8d6cf"))
	_liner(r0, r1, half, 0.14, 1.46, 0.04, tile)
	var top := _t("plate", Color("#8a8f96"))
	var tray := mats.flat(Color("#6a7a8a"), 0.6)
	var bowl := mats.flat(Color("#e8e4da"), 0.5)
	var food := [mats.flat(Color("#b0703a"), 0.9), mats.flat(Color("#6a8a3a"), 0.9), mats.flat(Color("#c9a04a"), 0.9)]
	for z0: float in [-7.2, -2.6, 2.6, 7.2]:
		_p(kit.box(8.0, 0.08, 1.2), top, Vector3(r0 + 9.0, 0.76, z0))
		for lx: float in [-3.6, 0.0, 3.6]:
			_p(kit.box(0.1, 0.72, 0.9), _m("hull"), Vector3(r0 + 9.0 + lx, 0.36, z0), lx == 0.0)
		for bz: float in [-0.95, 0.95]:
			_p(kit.box(8.0, 0.08, 0.4), _m("hull"), Vector3(r0 + 9.0, 0.45, z0 + bz), true)
		for j in 5:
			if (j + int(z0)) % 3 == 0:
				continue
			for side: float in [-0.3, 0.3]:
				var p := Vector3(r0 + 5.8 + j * 1.6, 0.81, z0 + side)
				_p(kit.box(0.42, 0.02, 0.3), tray, p)
				_p(kit.cyl(0.08, 0.06, 0.06, 8), bowl, p + Vector3(-0.08, 0.04, 0))
				_p(kit.box(0.1, 0.04, 0.1), food[(j + int(side * 10.0)) % 3], p + Vector3(0.1, 0.03, 0))
		_pendant(Vector3(r0 + 9.0, 3.2, z0), hull.floor_h, _m("trim"), 0.3)
	# The serving counter: steel, hot food under glass along it.
	_p(kit.box(1.0, 1.05, 6.0), _t("locker", Color("#9aa0a6")), Vector3(r1 - 6.0, 0.52, 0), true)
	_p(kit.box(1.1, 0.06, 6.1), top, Vector3(r1 - 6.0, 1.08, 0))
	for j in 5:
		_p(kit.box(0.6, 0.08, 0.9), _glow(Color("#ff9a4a"), 1.2), Vector3(r1 - 6.0, 1.14, -2.4 + j * 1.2))
		_p(kit.box(0.5, 0.06, 0.8), food[j % 3], Vector3(r1 - 6.0, 1.2, -2.4 + j * 1.2))
	_p(kit.box(0.04, 0.5, 6.0), _m("glass"), Vector3(r1 - 6.45, 1.4, 0), false, Basis(Vector3.BACK, 0.3))
	# The kitchen behind it: a back counter with cooktops under a hood, fridges at
	# its ends, shelves of pots.
	var kx := r1 - 3.2
	_p(kit.box(1.0, 0.9, 8.0), _t("locker", Color("#9aa0a6")), Vector3(kx, 0.45, 0), true)
	_p(kit.box(1.05, 0.05, 8.05), top, Vector3(kx, 0.925, 0))
	for j in 4:
		_p(kit.box(0.6, 0.02, 0.6), _glow(Color("#ff6a2a"), 2.0), Vector3(kx, 0.96, -2.4 + j * 1.6))
		_p(kit.cyl(0.18, 0.16, 0.22, 10), _m("trim"), Vector3(kx, 1.07, -2.4 + j * 1.6))
	_p(kit.box(1.2, 0.5, 7.0), _t("locker", Color("#9aa0a6")), Vector3(kx + 0.1, 2.6, 0))
	for s: float in [-1.0, 1.0]:
		_p(kit.box(0.8, 2.1, 1.0), _t("locker", Color("#9aa0a6")), Vector3(kx, 1.05, s * 4.6), true)
	for q in 2:
		_p(kit.box(0.4, 0.04, 6.0), _m("trim"), Vector3(kx + 0.3, 1.6 + q * 0.5, 0))
		for j in 6:
			_p(kit.cyl(0.13, 0.13, 0.2, 8), _m("trim"), Vector3(kx + 0.3, 1.72 + q * 0.5, -2.5 + j * 1.0))
	_p(kit.box(0.08, 1.5, 3.0), _m("screen"), Vector3(r1 - 1.2, 3.4, 0))
	# Bins and a water dispenser in the door's corners.
	var bx := r0 + 1.5
	var bz := _half_w(bx, half) - 0.6
	for j in 3:
		_barrel(Vector3(bx + j * 0.7, 0, bz), Color("#3b3f45"), 0.8, 0.28)
	_p(kit.box(0.5, 1.3, 0.5), _t("locker", Color("#9aa0a6")), Vector3(bx, 0.65, -bz), true)
	_p(kit.cyl(0.18, 0.18, 0.45, 10), _t("water", Color("#5fb0e0")), Vector3(bx, 1.52, -bz))


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
		var half := float(room.half)
		_q.append(_in.bind(at, _engine_shell.bind(r0, r1, half, k, use)))
		match use:
			"engine":
				_q.append(_in.bind(at, _reactor.bind(mid + 1.5, half)))
				_q.append(_in.bind(at, _reactor_more.bind(r0, r1, mid + 1.5, half)))
			"cargo":
				_q.append(_in.bind(at, _cargo.bind(r0, r1, half, not hatch, _rng.randi())))
				hatch = true
			"pumps":
				_q.append(_in.bind(at, _pumps.bind(mid, half)))
				_q.append(_in.bind(at, _pumps_more.bind(r0, r1, mid, half)))
			"workshop":
				_q.append(_in.bind(at, _workshop.bind(r0, r1, half)))
				_q.append(_in.bind(at, _workshop_more.bind(r0, r1, half)))
		_count(use)
		k += 1
	_q.append(_pipes.bind(t, f))
	_q.append(_ring_floor.bind(t, float(f.y), hull.gap_r + 0.2, hull.gap_r + hull.walk - 0.25, _t("plate", Color("#5a6068")), _room_n * 12))
	_q.append(_walk_stock.bind(t, f))


## Run `job` with the kit's frame at `at`.
func _in(at: Transform3D, job: Callable) -> void:
	kit._xf = at
	job.call()


## Every engine room: tread plate on the floor, a hazard line across it inside
## the door, pipe runs along both walls, a catwalk round them at 6 m (railed,
## with a ladder up), a cable tray down the middle with lamps hung from it.
func _engine_shell(r0: float, r1: float, half: float, k: int, use: String) -> void:
	_cover(r0, r1, half, _t("plate", Color("#5a6068")))
	_skirt(r0, r1, half, _m("trim"))
	_p(kit.box(0.5, 0.02, 2.0 * _half_w(r0 + 0.9, half)), _t("hazard", Color("#e0b030")), Vector3(r0 + 0.9, 0.03, 0))
	var cat_y := 6.0
	# Pipe runs along both walls (from the inner wall to the window, as _liner).
	var a := _rin() + 0.05
	var b := _win_r - 0.05
	var xm := (a + b) * 0.5 * cos(half)
	for s: float in [-1.0, 1.0]:
		var pipe := _along(s, half) * TownBuildings.AXIS_X
		for pr in [[2.6, 0.12, "hull"], [3.0, 0.12, "rail"], [4.6, 0.26, "hull"], [9.5, 0.2, "trim"]]:
			_p(kit.cyl(float(pr[1]), float(pr[1]), b - a, 8), _m(str(pr[2])), Vector3(xm, float(pr[0]), s * _wall_z(xm, half, float(pr[1]) + 0.12)),
				false, pipe)
	# The catwalk: a grate deck off both walls, brackets under it, a railing.
	_liner(r0, r1, half, cat_y - 0.08, 0.08, 1.4, _m("grate"), 0.0, true)
	_liner(r0, r1, half, cat_y + RAIL - 0.06, 0.06, 0.06, _m("rail"), 1.32)
	_liner(r0, r1, half, cat_y + RAIL * 0.5, 0.04, 0.04, _m("trim"), 1.34)
	var rho := r0 + 1.0
	while rho < _win_r - 0.6:
		var x := rho * cos(half)
		for s: float in [-1.0, 1.0]:
			_p(kit.box(0.06, RAIL, 0.06), _m("trim"), Vector3(x, cat_y + RAIL * 0.5, s * _wall_z(x, half, 1.35)))
			_p(kit.box(0.1, 0.5, 1.3), _m("trim"), Vector3(x, cat_y - 0.33, s * _wall_z(x, half, 0.7)), false, _along(s, half))
		rho += 3.0
	# A ladder up to the catwalk by the door, on the side k picks.
	var ls := 1.0 if k % 2 == 0 else -1.0
	var lx := r0 + 2.4
	var lz := ls * _wall_z(lx, half, 1.6)
	for e: float in [-0.25, 0.25]:
		_p(kit.box(0.06, cat_y + 1.0, 0.06), _m("rail"), Vector3(lx + e, (cat_y + 1.0) * 0.5, lz))
	var ry := 0.35
	while ry < cat_y:
		_p(kit.box(0.5, 0.04, 0.04), _m("rail"), Vector3(lx, ry, lz))
		ry += 0.35
	if use == "engine":
		return                                  # the reactor stands up through the middle
	# The cable tray down the middle, lamps hung from it.
	_p(kit.box(r1 - r0 - 2.0, 0.15, 0.8), _m("grate"), Vector3((r0 + r1) * 0.5, 9.0, 0))
	for j in 5:
		_pendant(Vector3(r0 + 2.5 + j * (r1 - r0 - 5.0) / 4.0, 7.2, 0.0), 9.0, _m("trim"), 0.4)


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


## Round the reactor: a hazard ring on the floor, two coolant tanks by the window
## piped to its crown, a bank of consoles by the door, drums in a corner.
func _reactor_more(r0: float, r1: float, r: float, half: float) -> void:
	var hz := _t("hazard", Color("#e0b030"))
	for j in 24:
		var a := TAU * j / 24.0
		var x := Vector3(cos(a), 0, sin(a))
		_p(kit.box(0.7, 0.02, 2.0 * 5.2 * tan(PI / 24.0) + 0.05), hz, Vector3(r, 0.03, 0) + x * 5.2, false, Basis(x, UP, x.cross(UP)))
	for s: float in [-1.0, 1.0]:
		var tc := _corner(half, s, 2.2, 2.2)
		var tx := tc.x
		var tz := tc.z
		var white := _t("barrel", Color("#c9ccd0"))
		_p(kit.cyl(1.5, 1.5, 7.0, 16), white, Vector3(tx, 3.7, tz), true)
		_p(kit.ball(1.5, 1.4, true, 16), _m("hull"), Vector3(tx, 7.2, tz))
		_p(kit.cyl(1.7, 1.7, 0.4, 16), _m("grate"), Vector3(tx, 0.2, tz), true)
		_p(kit.cyl(0.04, 0.04, 2.2, 6), _m("rail"), Vector3(tx - 1.55, 3.0, tz))
		_p(kit.box(0.05, 0.4, 0.3), _glow(Color("#7dff9a")), Vector3(tx - 1.55, 1.6, tz))
		# The coolant line: out of the tank, along under the ceiling, down into the crown.
		var px := (tx + r) * 0.5
		var pz := tz * 0.5
		var d := Vector3(r - tx, 0, -tz)
		var b := Basis(UP, -atan2(d.z, d.x)) * TownBuildings.AXIS_X
		_p(kit.cyl(0.3, 0.3, d.length(), 10), _m("hull"), Vector3(px, 11.2, pz), false, b)
		_p(kit.cyl(0.3, 0.3, 3.4, 10), _m("hull"), Vector3(tx, 9.4, tz))
		_p(kit.cyl(0.42, 0.42, 0.3, 10), _m("trim"), Vector3(tx, 11.2, tz))
	# Consoles by the door, on the other side from the one there.
	var cx := r - 5.5
	var cz := -clampf(r * tan(half) - 2.0, 1.5, 6.0)
	for j in 3:
		var z := cz + (j - 1) * 1.1
		_p(kit.box(0.8, 1.0, 1.0), _m("console"), Vector3(cx, 0.5, z), true)
		_p(kit.box(0.05, 0.7, 0.9), _m("screen"), Vector3(cx - 0.35, 1.45, z), false, Basis(Vector3.BACK, 0.25))
	_p(kit.cyl(0.25, 0.25, 0.5, 8), _m("trim"), Vector3(cx - 1.0, 0.25, cz))
	var bx := r0 + 2.0
	var bz := -(_half_w(bx + 3.0, half) - 1.6)
	var drums := [Color("#8a3a2a"), Color("#2f5d8a"), Color("#b08a3a")]
	for j in 7:
		_barrel(Vector3(bx + 2.0 + (j % 4) * 0.65, 0, bz + (j / 4) * 0.65), drums[j % 3])


## A cargo hold: containers in rows, crates stacked by them, a lift pallet; the
## first one has the drop hatch in its floor (sealed: the wrecks below are #317).
## Pallet racks along both walls under the catwalks, a loader by the door, a
## gantry crane over the containers, drums by the window.
func _cargo(r0: float, r1: float, half: float, with_hatch: bool, seed: int) -> void:
	_rng.seed = seed
	var cargo := _m("cargo")
	var rows := 0
	var r := r0 + 6.0
	while r < r1 - 3.0:
		var w := _half_w(r, half) - 1.8                  # the walls' racks
		var z := -w + 1.6
		while z < w - 1.6:
			if not (with_hatch and absf(r - (r0 + r1) * 0.5) < 4.0 and absf(z) < 4.0):
				var tall := 2.4 if _rng.randf() < 0.6 else 1.2
				_p(kit.box(2.4, tall, 2.4), cargo if _rng.randf() < 0.7 else kit.crate_woods[_rng.randi() % 3],
					Vector3(r, tall * 0.5, z), true, Basis(UP, _rng.randf_range(-0.08, 0.08)))
				if tall < 2.0 and _rng.randf() < 0.5:
					_p(kit.box(1.2, 0.9, 1.2), kit.crate_woods[_rng.randi() % 3], Vector3(r, tall + 0.45, z), true)
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
	# Pallet racks along both walls, stocked with crates and cases.
	var orange := _t("barrel", Color("#d8a42a"))
	var stock := [cargo, kit.crate_woods[0], kit.crate_woods[1], _t("barrel", Color("#2f5d8a"))]
	for s: float in [-1.0, 1.0]:
		var x := r0 + 3.0
		while x + 4.0 < _win_r * cos(half) - 0.3:
			_rack(Vector3(x + 1.9, 0, s * _wall_z(x + 1.9, half, 0.75)), _along(s, half) * Basis(UP, PI * 0.5), 3.6, 1.2, 4.6, 4,
				orange, stock, _rng.randi())
			x += 4.2
	# A loader by the door: a body, a cab, a mast and forks.
	var yellow := _t("barrel", Color("#d8a42a"))
	var lx := r0 + 2.6
	var lz := -5.0
	_p(kit.box(2.0, 1.0, 1.3), yellow, Vector3(lx, 0.7, lz), true)
	_p(kit.box(0.9, 1.0, 1.2), _m("trim"), Vector3(lx - 0.3, 1.7, lz))
	for e: float in [-0.5, 0.5]:
		_p(kit.box(0.1, 2.6, 0.1), _m("rail"), Vector3(lx + 1.05, 1.3, lz + e))
		_p(kit.box(1.1, 0.06, 0.15), _m("trim"), Vector3(lx + 1.6, 0.2, lz + e))
		for wx: float in [-0.6, 0.6]:
			_p(kit.cyl(0.3, 0.3, 0.25, 10), _m("trim"), Vector3(lx + wx, 0.3, lz + e * 1.5), false, TownBuildings.AXIS_Z)
	# A gantry crane over the containers: a beam across, a trolley, the hook.
	var gx := (r0 + r1) * 0.5 + 2.0
	_p(kit.box(0.6, 0.8, 2.0 * _half_w(gx, half) - 3.0), yellow, Vector3(gx, 10.6, 0))
	_p(kit.box(1.4, 0.6, 1.2), _m("trim"), Vector3(gx, 10.0, 2.0))
	_p(kit.cyl(0.03, 0.03, 4.0, 4), _m("rail"), Vector3(gx, 7.7, 2.0))
	_p(kit.box(0.5, 0.4, 0.3), yellow, Vector3(gx, 5.5, 2.0))
	var drums := [Color("#8a3a2a"), Color("#2f5d8a"), Color("#b08a3a")]
	for j in 8:
		_barrel(Vector3(r1 - 1.0 - (j / 4) * 0.65, 0, -1.4 + (j % 4) * 0.7), drums[j % 3])


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


## Round the pumps: a hazard box round them, tanks along both walls with valve
## wheels, a manifold of pipes up the window wall, a gauge board by the door.
func _pumps_more(r0: float, r1: float, r: float, half: float) -> void:
	var w := _half_w(r, half)
	var hz := _t("hazard", Color("#e0b030"))
	var bz := minf(3.2, w * 0.6) + 1.3
	for s: float in [-1.0, 1.0]:
		_p(kit.box(4.4, 0.02, 0.4), hz, Vector3(r, 0.03, s * bz))
		_p(kit.box(0.4, 0.02, bz * 2.0 + 0.4), hz, Vector3(r + s * 2.2, 0.03, 0))
	var teal := _t("barrel", Color("#3f6f6a"))
	for s: float in [-1.0, 1.0]:
		var x := r0 + 3.5
		while x < r1 - 3.0:
			var z := s * _wall_z(x, half, 2.6)
			_p(kit.cyl(1.0, 1.0, 4.2, 14), teal, Vector3(x, 2.4, z), true)
			_p(kit.ball(1.0, 0.8, true, 14), _m("hull"), Vector3(x, 4.5, z))
			for lg in 4:
				var a := PI * 0.25 + lg * PI * 0.5
				_p(kit.box(0.12, 0.3, 0.12), _m("trim"), Vector3(x + cos(a) * 0.8, 0.15, z + sin(a) * 0.8))
			_p(kit.cyl(0.12, 0.12, 1.6, 8), _m("rail"), Vector3(x, 5.6, z))
			_p(kit.cyl(0.3, 0.3, 0.05, 12), _m("rail"), Vector3(x - 1.05, 1.4, z), false, TownBuildings.AXIS_X)
			x += 4.6
	# The manifold: pipes up the window wall, a header across them, valve wheels.
	var mw := 6.0
	for j in 7:
		var z := -mw + j * mw * 2.0 / 6.0
		var x := sqrt(_win_r * _win_r - z * z) - 0.5
		_p(kit.cyl(0.22, 0.22, hull.floor_h - 0.2, 8), _m("hull") if j % 2 == 0 else _m("rail"), Vector3(x, hull.floor_h * 0.5, z))
		_p(kit.cyl(0.32, 0.32, 0.06, 12), _m("trim"), Vector3(x - 0.4, 1.6, z), false, TownBuildings.AXIS_X)
	_p(kit.cyl(0.35, 0.35, mw * 2.0 + 0.8, 10), _m("hull"), Vector3(sqrt(_win_r * _win_r - 49.0) - 1.0, 3.2, 0), false, TownBuildings.AXIS_Z)
	var gx := r0 + 2.0
	var gz := _half_w(gx, half) - 0.4
	_p(kit.box(1.8, 1.4, 0.1), _m("console"), Vector3(gx, 1.5, gz))
	for j in 6:
		_p(kit.cyl(0.12, 0.12, 0.04, 10), _glow(Color("#e8f6ff"), 1.5), Vector3(gx - 0.6 + (j % 3) * 0.6, 1.25 + (j / 3) * 0.5, gz - 0.07), false, TownBuildings.AXIS_Z)


## A workshop: two benches with tools, a rack of glowing parts on the wall, a
## droid half built on a stand, a hanging lamp.
func _workshop(r0: float, r1: float, half: float) -> void:
	var trim := _m("trim")
	var mid := (r0 + r1) * 0.5
	for j in 2:
		var r := mid - 3.0 + j * 6.0
		var w := _half_w(r, half)
		var z := (w - 0.6) * (1.0 if j == 0 else -1.0)
		_p(kit.box(2.4, 0.9, 0.9), _t("locker", Color("#4c5259")), Vector3(r, 0.45, z), true)
		_p(kit.box(2.5, 0.06, 1.0), _t("plate", Color("#7a7f86")), Vector3(r, 0.93, z))
		for q in 4:
			_p(kit.box(0.25, 0.12 + q * 0.04, 0.2), _m("console") if q % 2 == 0 else trim,
				Vector3(r - 0.9 + q * 0.6, 1.0 + q * 0.02, z))
		_p(kit.box(2.4, 1.2, 0.08), _m("screen"), Vector3(r, 1.9, z + signf(z) * 0.4))
		_p(kit.box(2.6, 0.02, 1.4), _t("rubber", Color("#2a2c2e")), Vector3(r, 0.035, z - signf(z) * 1.1))
	_p(kit.cyl(0.6, 0.7, 0.3, 12), _m("grate"), Vector3(mid, 0.15, 0), true)
	_p(kit.cyl(0.25, 0.3, 1.0, 8), _m("hull"), Vector3(mid, 0.8, 0))
	_p(kit.ball(0.35, 0.6, false, 10), _m("hull"), Vector3(mid, 1.5, 0))
	_p(kit.box(0.1, 0.1, 0.1), _glow(Color("#ff4a32"), 3.0), Vector3(mid - 0.3, 1.55, 0))
	_p(kit.cyl(0.03, 0.03, hull.floor_h - 4.0, 6), trim, Vector3(mid, (hull.floor_h + 4.0) * 0.5, 0))
	_p(kit.cyl(0.4, 0.15, 0.3, 10), kit.window_glow, Vector3(mid, 3.9, 0))


## More of a workshop: tool cabinets and a lathe on one wall, a drill press, a
## welding cart and a parts rack on the other, a speeder up on a lift by the
## window, an engine on a stand, drums and crates in the corners.
func _workshop_more(r0: float, r1: float, half: float) -> void:
	var mid := (r0 + r1) * 0.5
	var red := _t("locker", Color("#8a2e2a"))
	var grey := _t("locker", Color("#4c5259"))
	for j in 3:
		var x := mid + 0.2 + j * 0.95
		var z := _half_w(x, half) - 0.35
		_p(kit.box(0.9, 1.1, 0.6), red, Vector3(x, 0.55, z), true, _along(1.0, half))
		_p(kit.box(0.9, 0.04, 0.62), _m("trim"), Vector3(x, 1.12, z), false, _along(1.0, half))
	# The lathe: a bed on a base, the head, the chuck, the tailstock.
	var lx := mid + 6.5
	var lz := _half_w(lx, half) - 1.0
	_p(kit.box(2.4, 0.85, 0.7), grey, Vector3(lx, 0.43, lz), true)
	_p(kit.box(2.2, 0.15, 0.4), _m("trim"), Vector3(lx, 0.95, lz))
	_p(kit.box(0.6, 0.55, 0.6), _m("hull"), Vector3(lx - 0.85, 1.3, lz))
	_p(kit.cyl(0.16, 0.16, 0.2, 10), _m("rail"), Vector3(lx - 0.45, 1.25, lz), false, TownBuildings.AXIS_X)
	_p(kit.box(0.3, 0.35, 0.35), _m("hull"), Vector3(lx + 0.85, 1.2, lz))
	# The drill press: a base, a column, the head and its handle.
	var dx := mid - 6.0
	var dz := -(_half_w(dx, half) - 0.8)
	_p(kit.box(0.6, 0.08, 0.6), _m("trim"), Vector3(dx, 0.04, dz), true)
	_p(kit.cyl(0.07, 0.07, 1.8, 8), _m("rail"), Vector3(dx - 0.15, 0.9, dz))
	_p(kit.box(0.5, 0.35, 0.3), grey, Vector3(dx, 1.65, dz))
	_p(kit.box(0.35, 0.04, 0.35), _m("trim"), Vector3(dx + 0.1, 0.9, dz))
	_p(kit.cyl(0.02, 0.02, 0.5, 4), _m("rail"), Vector3(dx, 1.6, dz + 0.35), false, TownBuildings.AXIS_Z)
	# The welding cart: a trolley, two gas bottles, a coiled hose.
	var wx := mid - 6.0
	var wz := _half_w(wx, half) - 1.4
	_p(kit.box(0.9, 0.7, 0.6), grey, Vector3(wx, 0.45, wz), true)
	_barrel(Vector3(wx - 0.25, 0.8, wz), Color("#3f6f6a"), 1.2, 0.12)
	_barrel(Vector3(wx + 0.05, 0.8, wz), Color("#8a3a2a"), 1.2, 0.12)
	_p(kit.cyl(0.18, 0.18, 0.06, 10), _m("trim"), Vector3(wx + 0.3, 0.83, wz))
	# A parts rack on the drill's wall toward the window.
	_rack(Vector3(mid + 5.5, 0, -_wall_z(mid + 5.5, half, 0.35)), _along(-1.0, half) * Basis(UP, PI * 0.5), 3.0, 0.6, 2.2, 4,
		_m("trim"), [_t("barrel", Color("#2f5d8a")), _t("barrel", Color("#b08a3a")), kit.crate_woods[1], _m("cargo")], 4117)
	# A speeder up on a lift by the window: the lift's posts and deck, its body.
	var sx := r1 - 5.0
	for e: float in [-0.9, 0.9]:
		_p(kit.box(0.2, 1.2, 0.2), _m("rail"), Vector3(sx, 0.6, e), true)
	_p(kit.box(3.4, 0.12, 2.0), _t("plate", Color("#8a8f96")), Vector3(sx, 1.2, 0))
	var paint := _paint(2)
	_p(kit.box(2.6, 0.5, 1.1), paint, Vector3(sx, 1.55, 0))
	_p(kit.box(0.9, 0.3, 0.9), paint, Vector3(sx + 1.55, 1.45, 0), false, Basis(Vector3.BACK, -0.2))
	_p(kit.box(0.7, 0.3, 0.8), _m("trim"), Vector3(sx - 0.3, 1.95, 0))
	for e: float in [-0.75, 0.75]:
		_p(kit.cyl(0.25, 0.25, 1.4, 10), _m("hull"), Vector3(sx - 0.6, 1.6, e), false, TownBuildings.AXIS_X)
		_p(kit.cyl(0.2, 0.2, 0.05, 10), _glow(Color("#5fd0ff"), 2.0), Vector3(sx - 1.32, 1.6, e), false, TownBuildings.AXIS_X)
	# An engine on a stand, beside the lift.
	var ex := r1 - 5.0
	var ez := _half_w(ex, half) - 3.0
	_p(kit.box(0.8, 0.7, 0.8), _m("trim"), Vector3(ex, 0.35, ez), true)
	_p(kit.cyl(0.4, 0.4, 1.4, 12), _m("hull"), Vector3(ex, 1.1, ez), false, TownBuildings.AXIS_X)
	_p(kit.cyl(0.45, 0.45, 0.1, 12), _m("rail"), Vector3(ex + 0.7, 1.1, ez), false, TownBuildings.AXIS_X)
	# Drums and crates in the window's corners, lamps over the benches.
	var drums := [Color("#8a3a2a"), Color("#2f5d8a"), Color("#b08a3a")]
	for s: float in [-1.0, 1.0]:
		for j in 3:
			_barrel(_corner(half, s, 0.9 + j * 0.7, 0.6), drums[(j + int(s) + 3) % 3])
		var cc := _corner(half, s, 1.3, 1.6)
		_p(kit.box(1.0, 0.8, 1.0), kit.crate_woods[0], cc + Vector3(0, 0.4, 0), true)
		_p(kit.box(0.7, 0.6, 0.7), kit.crate_woods[2], cc + Vector3(0, 1.1, 0), true)
	for j in 2:
		var r := mid - 3.0 + j * 6.0
		var z := (_half_w(r, half) - 1.0) * (1.0 if j == 0 else -1.0)
		_pendant(Vector3(r, 2.6, z), hull.floor_h, _m("trim"), 0.35)


## Along the engine deck's walkway, against the rooms' wall between the doors: a
## crate, a drum, a bin.
func _walk_stock(t: Dictionary, f: Dictionary) -> void:
	var y := float(f.y)
	var rr := hull.gap_r + hull.walk
	var doors: Array = hull.door_angles(t, y)
	var n := _room_n if _room_n > 0 else 8
	var drums := [Color("#8a3a2a"), Color("#2f5d8a"), Color("#b08a3a")]
	for k in n:
		var a := TAU * k / n
		var near := false
		for d in doors:
			if absf(wrapf(a - float(d), -PI, PI)) * rr < hull.tunnel_w * 0.5 + 2.5:
				near = true
		if near:
			continue
		kit._xf = radial(t, y, a)
		_p(kit.box(0.9, 0.8, 0.9), kit.crate_woods[k % 3], Vector3(rr - 0.75, 0.4, -0.6), true)
		_p(kit.cyl(0.3, 0.3, 0.9, 10), _t("barrel", drums[k % 3]), Vector3(rr - 0.7, 0.45, 0.6), true)
		_p(kit.box(0.6, 0.5, 0.6), kit.crate_woods[(k + 1) % 3], Vector3(rr - 0.75, 1.05, -0.6), true)


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
