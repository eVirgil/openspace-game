extends RefCounted
## Building kit for the port town (town art pass 2). Draws a box that has a
## `look` in port_town.json as one of a few building variants, on top of the
## box's own collision. It never moves a box; the only collision it adds is the
## props' (issue #55, below).
##
## Every building shares the same small parts, so the town reads as one place:
##   - a rounded sci-fi door (arched frame, recessed panel, a glowing light bar)
##   - a simple window (framed amber pane with a visor; a porthole on round walls)
##   - a short + tall antenna relay on the roof (dish mast, lattice mast, beacon)
##
## Looks: hut_round, hut_block, hut_stepped, hut_long (market side), tower_block,
## tower_round, tower_wide (barracks side), shop, hall, upper, watchtower, bridge,
## cistern. `face` ("+x", "-x", "+z", "-z") is the door side. `style: "garrison"`
## paints a building in Remnant colours (issue #393: in the locals' once they hold the
## barracks; LookMaterials.repaint).
##
## Parts are not nodes: each (mesh, material) pair is gathered and drawn as one
## MultiMesh by `flush`, so a hundred buildings cost a few dozen draw calls.
##
## Issue #55: props you would bump into or climb on (antennas, parapets, door
## clutter, roof blocks; the decor's lamp posts and pit clutter) are put while
## `solid` is on, and `flush` gives each one a box collider in one "Props" body.

const DOOR_LIGHT := Color("#58e6d4")
const BEACON := Color("#ff4a32")
const BANDS := [LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_MADDER,
	LookMaterials.CLOTH_SAFFRON, LookMaterials.CLOTH_SAND]
const TINTS := [Color("#d8c2a0"), Color("#e2d0b0"), Color("#cdb08a")]
const FLOOR_H := 3.2          ## storey height on towers (ledges, window rows)
const StairTower := preload("res://src/systems/world/stair_tower.gd")

var mats: LookMaterials
var look: LookEnvironment
var town                      ## TownLayout, for looks that need a second box (the lookout)
var built := {}               ## look id -> how many drawn (tests, review)
var window_glow: StandardMaterial3D
var door_glow: StandardMaterial3D
var beacon_glow: StandardMaterial3D
var trim: Material
var panel: Material
var metal: Material
var seam: Material
var crate_woods: Array = []   ## issue #355: plank crates in three woods (StallTextures)
var crate_band: Material      ## and the painted iron bands round them

var solid := false            ## issue #55: while on, `put` parts also collide (see flush)
var solids := 0               ## colliders the last flush made (tests, review)
var _groups := {}             ## "mesh:mat" -> [mesh, mat, Array[Transform3D]]
var _solids: Array = []        ## [Transform3D, Vector3 size] per solid box part
var _cyls: Array = []          ## [Transform3D, CylinderShape3D] per solid dome cap
var _meshes := {}
var _xf := Transform3D.IDENTITY   ## the building being drawn: local +X is its door side
var _rng := RandomNumberGenerator.new()


func _init(m: LookMaterials, l: LookEnvironment) -> void:
	mats = m
	look = l
	window_glow = mats.glow(Color("#ffb46a"))
	look.track_glow(window_glow)
	# Door lights and beacons are on day and night: fixed, not driven by the lamps.
	door_glow = mats.glow(DOOR_LIGHT)
	door_glow.emission_energy_multiplier = 2.2
	beacon_glow = mats.glow(BEACON)
	beacon_glow.emission_energy_multiplier = 3.0
	trim = mats.hull(0.0, 0.8)
	panel = mats.flat(Color("#5e5955"), 0.4, 0.55)
	metal = mats.flat(Color("#4a4440"), 0.55, 0.5)
	seam = mats.flat(Color("#141211"), 0.9)
	crate_woods = [mats.wood(Color("#8a7350"), 0.85), mats.wood(Color("#6b6a4a"), 0.85), mats.wood(Color("#7a4a32"), 0.85)]
	crate_band = mats.painted(Color("#4a4440"), 0.55, 0.5)


# ---------------------------------------------------------------- batching

## Queue one part. `xf` is in the current building's local frame.
func part(mesh: Mesh, mat: Material, pos: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	put(mesh, mat, _xf * Transform3D(basis, pos))


## Queue one part in world space.
func put(mesh: Mesh, mat: Material, world: Transform3D) -> void:
	var key := "%d:%d" % [mesh.get_instance_id(), mat.get_instance_id()]
	if not _groups.has(key):
		_groups[key] = [mesh, mat, []]
	_groups[key][2].append(world)
	if solid:
		_add_solid(mesh, world)


## The part's bounding box, turned with it. Wisps (a lattice bar, a cable stay)
## are left out: nobody stands on those, and they would only snag.
func _add_solid(mesh: Mesh, world: Transform3D) -> void:
	var a := mesh.get_aabb()
	var size := a.size * world.basis.get_scale()
	if size.x * size.y * size.z < 0.002:
		return
	_solids.append([Transform3D(world.basis.orthonormalized(), world * a.get_center()), size])


## A cylinder collider at the dome's footprint, so the dome cap collides. The dome
## sits on top of the box (whose top is the wall height); the cap spans its height
## from `pos`. `pos` is in the current building's local frame.
func solid_dome(r: float, h: float, pos: Vector3) -> void:
	_cyls.append([_xf * Transform3D(Basis.IDENTITY, pos + Vector3(0, h * 0.5, 0)), r, h])


## Put with `solid` on for just this part.
func solid_part(mesh: Mesh, mat: Material, pos: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var was := solid
	solid = true
	part(mesh, mat, pos, basis)
	solid = was


## Draw everything queued so far as MultiMeshes under `parent`.
func flush(parent: Node3D) -> int:
	var n := 0
	for key in _groups:
		var g: Array = _groups[key]
		var xfs: Array = g[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g[0]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = g[1]
		parent.add_child(mmi)
		n += xfs.size()
	_groups.clear()
	solids = _solids.size() + _cyls.size()
	var has := not _solids.is_empty() or not _cyls.is_empty()
	if has:
		var body := StaticBody3D.new()
		body.name = "Props"
		for sp in _solids:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = sp[1]
			cs.shape = shape
			cs.transform = sp[0]
			body.add_child(cs)
		for d in _cyls:
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = d[1]
			shape.height = d[2]
			cs.shape = shape
			cs.transform = d[0]
			body.add_child(cs)
		parent.add_child(body)
		_solids.clear()
		_cyls.clear()
	return n


# ---------------------------------------------------------------- meshes (cached)

func box(x: float, y: float, z: float) -> BoxMesh:
	var k := "b%.2f_%.2f_%.2f" % [x, y, z]
	if not _meshes.has(k):
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		_meshes[k] = b
	return _meshes[k]


func cyl(top: float, bottom: float, h: float, seg: int = 16) -> CylinderMesh:
	var k := "c%.2f_%.2f_%.2f_%d" % [top, bottom, h, seg]
	if not _meshes.has(k):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_meshes[k] = c
	return _meshes[k]


func ball(r: float, h: float, hemi: bool = false, seg: int = 16) -> SphereMesh:
	var k := "s%.2f_%.2f_%s_%d" % [r, h, hemi, seg]
	if not _meshes.has(k):
		var s := SphereMesh.new()
		s.radius = r
		s.height = h
		s.is_hemisphere = hemi
		s.radial_segments = seg
		s.rings = maxi(4, seg / 2)
		_meshes[k] = s
	return _meshes[k]


func ring(r_in: float, r_out: float, y0: float, y1: float, seg: int = 28) -> ArrayMesh:
	var k := "r%.2f_%.2f_%.2f_%.2f_%d" % [r_in, r_out, y0, y1, seg]
	if not _meshes.has(k):
		_meshes[k] = LookMeshKit.ring_segment(r_in, r_out, y0, y1, 0.0, TAU, seg)
	return _meshes[k]


func frustum(w: float, d: float, h: float, lean: float) -> ArrayMesh:
	var k := "f%.2f_%.2f_%.2f_%.3f" % [w, d, h, lean]
	if not _meshes.has(k):
		_meshes[k] = LookMeshKit.frustum(w, d, h, lean)
	return _meshes[k]


const AXIS_X := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))   ## cylinder axis along X
const AXIS_Z := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))   ## cylinder axis along Z


# ---------------------------------------------------------------- shared parts

## The rounded sci-fi door. `at` is a frame on the wall face: +X out of the wall,
## origin at the foot of the door. Scale 1 is 1.5 m wide, 2.35 m to the arch top.
func door(at: Transform3D, s: float = 1.0, open: bool = false) -> void:
	var w := 1.5 * s
	var hr := 1.6 * s
	var r := w * 0.5
	var jw := 0.18 * s
	var pr := r - jw
	var pw := pr * 2.0
	# Frame: two jambs and a half-ring arch, standing proud of the wall.
	for side in [-1.0, 1.0]:
		_at(at, box(0.44, hr, jw), trim, Vector3(0.02, hr * 0.5, side * (r - jw * 0.5)))
	_at(at, arch(pr, r, 0.44), trim, Vector3(0.02, hr, 0))
	if open:
		# A doorway you walk through: frame and light, no panel.
		_at(at, box(0.05, 0.07 * s, pw * 0.7), door_glow, Vector3(0.24, hr + r + 0.12, 0))
		return
	# Recessed panel with an arched top and a centre seam: the doors slide apart.
	_at(at, box(0.3, hr, pw), panel, Vector3(-0.1, hr * 0.5, 0))
	_at(at, cyl(pr, pr, 0.3, 20), panel, Vector3(-0.1, hr, 0), AXIS_X)
	_at(at, box(0.02, hr + pr * 0.9, 0.035), seam, Vector3(0.055, (hr + pr * 0.9) * 0.5, 0))
	# The light: a bar across the arch and a status dot on the frame.
	_at(at, box(0.04, 0.07 * s, pw * 0.6), door_glow, Vector3(0.065, hr + pr * 0.45, 0))
	_at(at, ball(0.06 * s, 0.12 * s, false, 8), door_glow, Vector3(0.25, hr * 0.55, r - jw * 0.5))
	_at(at, box(0.6, 0.1, w + 0.3), trim, Vector3(0.3, 0.05, 0))          # step


## Half ring standing up in the YZ plane (an arch), `depth` thick along X, base at y = 0.
func arch(r_in: float, r_out: float, depth: float) -> ArrayMesh:
	var k := "a%.2f_%.2f_%.2f" % [r_in, r_out, depth]
	if not _meshes.has(k):
		var flat := LookMeshKit.ring_segment(r_in, r_out, -depth * 0.5, depth * 0.5, -PI * 0.5, PI * 0.5, 14)
		# The ring lies in XZ around Y; turn it so Y runs along X and X points up.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(flat, 0, Transform3D(AXIS_X, Vector3.ZERO))
		_meshes[k] = st.commit()
	return _meshes[k]


## A simple window. Porthole when `round` (curved walls), else a framed pane with a visor.
func window(at: Transform3D, w: float = 1.2, h: float = 0.7, round: bool = false) -> void:
	if round:
		_at(at, cyl(0.5, 0.5, 0.3, 18), trim, Vector3.ZERO, AXIS_X)
		_at(at, cyl(0.36, 0.36, 0.3, 18), window_glow, Vector3(-0.04, 0, 0), AXIS_X)
		_at(at, box(0.04, 0.72, 0.05), trim, Vector3(0.18, 0, 0))
		return
	_at(at, box(0.3, h + 0.24, w + 0.24), trim, Vector3.ZERO)
	_at(at, box(0.3, h, w), window_glow, Vector3(-0.04, 0, 0))
	_at(at, box(0.04, h, 0.05), trim, Vector3(0.18, 0, 0))
	_at(at, box(0.42, 0.08, w + 0.44), trim, Vector3(0.08, -h * 0.5 - 0.16, 0))
	_at(at, box(0.5, 0.07, w + 0.5), trim, Vector3(0.12, h * 0.5 + 0.2, 0), Basis(Vector3.BACK, -0.25))


## The rooftop relay: a short mast with a dish and a tall lattice mast with a beacon,
## both on one plinth. `pos` is on the roof (local frame), `tall` the tall mast's height.
func antennas(pos: Vector3, tall: float = 3.2, yaw: float = 0.0) -> void:
	var at := Transform3D(Basis(Vector3.UP, yaw), pos)
	var was := solid
	solid = true
	_at(at, box(0.9, 0.3, 1.5), trim, Vector3(0, 0.15, 0))
	# Short: dish mast.
	_at(at, cyl(0.045, 0.065, 1.3, 6), metal, Vector3(0, 0.95, -0.42))
	_at(at, ball(0.34, 0.17, true, 12), metal, Vector3(0.08, 1.62, -0.42), Basis(Vector3.BACK, deg_to_rad(115)))
	_at(at, box(0.2, 0.22, 0.2), trim, Vector3(0, 0.45, -0.42))
	# Tall: lattice mast with cross bars, a module and the beacon.
	_at(at, cyl(0.035, 0.07, tall, 6), metal, Vector3(0, 0.3 + tall * 0.5, 0.4))
	for f in [0.55, 0.8]:
		_at(at, box(0.04, 0.04, 0.8), metal, Vector3(0, 0.3 + tall * f, 0.4))
		_at(at, box(0.6, 0.04, 0.04), metal, Vector3(0, 0.3 + tall * f + 0.12, 0.4))
	_at(at, box(0.2, 0.34, 0.2), trim, Vector3(0, 0.3 + tall * 0.32, 0.4))
	_at(at, ball(0.08, 0.16, false, 8), beacon_glow, Vector3(0, 0.36 + tall, 0.4))
	solid = was


## Low wall around a flat roof, so the roof reads as a terrace.
func parapet(w: float, d: float, y: float, h: float, mat: Material) -> void:
	var t := 0.22
	solid_part(box(w, h, t), mat, Vector3(0, y + h * 0.5, d * 0.5 - t * 0.5))
	solid_part(box(w, h, t), mat, Vector3(0, y + h * 0.5, -d * 0.5 + t * 0.5))
	solid_part(box(t, h, d - 2 * t), mat, Vector3(w * 0.5 - t * 0.5, y + h * 0.5, 0))
	solid_part(box(t, h, d - 2 * t), mat, Vector3(-w * 0.5 + t * 0.5, y + h * 0.5, 0))


func _at(at: Transform3D, mesh: Mesh, mat: Material, pos: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	put(mesh, mat, _xf * at * Transform3D(basis, pos))


## A frame on a flat wall at local (x, y, z) facing +X (door / window helpers).
static func on_wall(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## A frame on a round wall of radius r, `a` radians round from the front.
static func on_round(r: float, y: float, a: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r, y, sin(a) * r))


## Where a battered wall (frustum with `lean`) is at height y, from the centre.
static func wall_at(half: float, y: float, h: float, lean: float) -> float:
	return half * (1.0 - lean * y / h)


# ---------------------------------------------------------------- buildings

## Draw box `b` if it has a look. Returns false if this kit has no such look.
func build(b: Dictionary) -> bool:
	var kind := str(b.get("look", ""))
	if not has_method("_look_" + kind):
		return false
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var size := mx - mn
	var face := str(b.get("face", "+x"))
	var along_x := face.ends_with("x")
	var yaw: float = { "+x": 0.0, "-x": PI, "+z": -PI * 0.5, "-z": PI * 0.5 }.get(face, 0.0)
	_xf = Transform3D(Basis(Vector3.UP, yaw), Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5))
	_rng.seed = hash(str(b.id))
	var lx := size.x if along_x else size.z
	var lz := size.z if along_x else size.x
	call("_look_" + kind, b, lx, lz, size.y)
	built[kind] = int(built.get(kind, 0)) + 1
	return true


func _plaster(b: Dictionary, band_y: float) -> Material:
	if str(b.get("style", "")) == "garrison":       # issue #393: repainted with the barracks' owner
		return mats.faction_plaster(0.0, band_y, "band", Color("#cbb594"))
	if str(b.get("style", "")) == "gray":
		return mats.plaster(0.0, band_y, Color("#84898b"), Color("#55595b"))
	var i := absi(hash(str(b.id)))
	return mats.plaster(0.0, snappedf(band_y, 0.5), BANDS[i % BANDS.size()], TINTS[(i / 7) % TINTS.size()])


func _look_hut_block(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := _plaster(b, h - 0.5)
	const LEAN := 0.08
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	parapet(lx * (1.0 - LEAN), lz * (1.0 - LEAN), h, 0.45, mat)
	var dz := clampf(-lz * 0.2, -lz * 0.5 + 1.0, 0.0)
	door(on_wall(wall_at(lx * 0.5, 1.2, h, LEAN) - 0.02, 0, dz))
	part(box(0.8, 0.1, 2.0), trim, Vector3(lx * 0.5 + 0.25, 2.65, dz))   # visor over the door
	var wy := minf(h * 0.58, h - 1.0)
	window(on_wall(wall_at(lx * 0.5, wy, h, LEAN), wy, minf(lz * 0.28, lz * 0.5 - 0.9)), 1.0, 0.6)
	antennas(Vector3(-lx * 0.28, h, -lz * 0.25), 2.6 + _rng.randf() * 1.2, PI * 0.5)
	_door_clutter(lx * 0.5, dz, lz)


func _look_hut_round(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var r := minf(lx, lz) * 0.5
	var mat := _plaster(b, h - 0.5)
	part(cyl(r * 0.97, r, h, 28), mat, Vector3(0, h * 0.5, 0))
	part(ring(r - 0.1, r + 0.22, h - 0.05, h + 0.28), mat, Vector3.ZERO)
	var dr := r * 0.86
	var dh := r * 0.5
	part(ball(dr, dh, true, 24), mat, Vector3(0, h, 0))
	solid_dome(dr, dh, Vector3(0, h, 0))
	part(cyl(0.22, 0.32, 0.35, 10), trim, Vector3(0, h + r * 0.5 + 0.1, 0))
	door(on_round(r - 0.04, 0, 0.0))
	window(on_round(r - 0.02, minf(h * 0.6, h - 0.9), 0.85), 0.0, 0.0, true)
	antennas(Vector3(-r * 0.9, h + 0.28, 0), 2.4 + _rng.randf() * 1.2)
	_door_clutter(r - 0.15, 0.0, r * 1.2)


func _look_hut_stepped(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := _plaster(b, h - 0.5)
	const LEAN := 0.06
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	# The upper storey sits at the back, leaving a terrace at the front.
	var ux := lx * 0.48
	var uz := lz * 0.62
	var cx := -lx * 0.22
	solid_part(frustum(ux, uz, 2.4, 0.08), mat, Vector3(cx, h + 1.2, 0))
	solid_part(box(ux * 0.92 + 0.3, 0.18, uz * 0.92 + 0.3), trim, Vector3(cx, h + 2.49, 0))
	solid_part(box(0.22, 0.45, lz * (1.0 - LEAN)), mat, Vector3(lx * 0.5 * (1.0 - LEAN) - 0.11, h + 0.22, 0))
	var dz := clampf(lz * 0.18, 0.0, lz * 0.5 - 1.0)
	door(on_wall(wall_at(lx * 0.5, 1.2, h, LEAN) - 0.02, 0, dz))
	window(on_wall(cx + ux * 0.5 * 0.96, h + 1.3, 0), 1.0, 0.55)
	antennas(Vector3(cx - ux * 0.15, h + 2.58, 0), 2.8 + _rng.randf() * 1.4, PI * 0.5)
	_door_clutter(lx * 0.5, dz, lz)


func _look_hut_long(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := _plaster(b, h - 0.5)
	const LEAN := 0.04
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	# Barrel-vault roof along the long side, with ribs.
	var long_z := lz >= lx
	var short := minf(lx, lz) * (1.0 - LEAN)
	var length := maxf(lx, lz) * (1.0 - LEAN) - 0.1
	var vr := short * 0.46
	var axis := AXIS_Z if long_z else AXIS_X
	part(cyl(vr, vr, length, 20), mat, Vector3(0, h - 0.05, 0), axis)
	var n := int(length / 1.6)
	for i in n:
		var t := -length * 0.5 + (i + 0.5) * length / n
		part(cyl(vr + 0.06, vr + 0.06, 0.18, 20), trim, Vector3(0 if long_z else t, h - 0.05, t if long_z else 0), axis)
	var dz := clampf(-lz * 0.22, -lz * 0.5 + 1.0, 0.0)
	door(on_wall(wall_at(lx * 0.5, 1.2, h, LEAN) - 0.02, 0, dz))
	var wy := minf(h * 0.55, h - 1.0)
	window(on_wall(wall_at(lx * 0.5, wy, h, LEAN), wy, minf(lz * 0.25, lz * 0.5 - 0.9)), 1.1, 0.6)
	var end := length * 0.5 - 0.8
	antennas(Vector3(0 if long_z else -end, h + vr - 0.15, -end if long_z else 0), 2.4 + _rng.randf(), 0.0 if long_z else PI * 0.5)
	_door_clutter(lx * 0.5, dz, lz)


func _look_tower_block(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var garrison := str(b.get("style", "")) == "garrison"
	var mat := _plaster(b, 2.9)
	const LEAN := 0.025
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	var y := FLOOR_H
	while y < h - 1.0:
		var k := 1.0 - LEAN * y / h
		part(box(lx * k + 0.45, 0.22, lz * k + 0.45), trim if garrison else mat, Vector3(0, y, 0))
		y += FLOOR_H
	parapet(lx * (1.0 - LEAN) + 0.2, lz * (1.0 - LEAN) + 0.2, h, 0.6, mat)
	var dz := clampf(-lz * 0.18, -lz * 0.5 + 1.0, 0.0)
	door(on_wall(lx * 0.5 - 0.02, 0, dz), 1.15)
	window(on_wall(lx * 0.5, 1.7, minf(lz * 0.3, lz * 0.5 - 0.9)), 1.0, 0.6)
	# Upper floors: one window per storey on the front and on one side.
	var f := 1
	while f * FLOOR_H + 1.6 < h - 0.8:
		var wy := f * FLOOR_H + 1.6
		var hx := wall_at(lx * 0.5, wy, h, LEAN)
		var hz := wall_at(lz * 0.5, wy, h, LEAN)
		window(on_wall(hx, wy, lz * (0.22 if f % 2 == 0 else -0.22)), 1.3, 0.75)
		window(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(lx * (0.18 if f % 2 == 1 else -0.18), wy, hz)), 1.3, 0.75)
		f += 1
	solid_part(box(1.8, 1.3, 1.5), trim, Vector3(-lx * 0.22, h + 0.65, lz * 0.22))     # roof hatch block
	antennas(Vector3(-lx * 0.25, h, -lz * 0.2), 4.0 + _rng.randf() * 1.8, PI * 0.5)


func _look_tower_wide(b: Dictionary, lx: float, lz: float, h: float) -> void:
	_look_tower_block(b, lx, lz, h)


func _look_tower_round(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var r := minf(lx, lz) * 0.5
	var mat := _plaster(b, 2.9)
	part(cyl(r * 0.98, r, h, 32), mat, Vector3(0, h * 0.5, 0))
	var y := FLOOR_H
	while y < h - 1.0:
		part(ring(r - 0.1, r + 0.3, y - 0.11, y + 0.11, 32), mat, Vector3.ZERO)
		y += FLOOR_H
	part(ring(r - 0.25, r + 0.08, h, h + 0.6, 32), mat, Vector3.ZERO)
	solid_part(cyl(r * 0.35, r * 0.4, 1.0, 16), trim, Vector3(r * 0.2, h + 0.5, 0))
	door(on_round(r - 0.04, 0, 0.0), 1.15)
	window(on_round(r - 0.02, 1.8, 0.75), 0.0, 0.0, true)
	var f := 1
	while f * FLOOR_H + 1.6 < h - 0.8:
		window(on_round(r - 0.02, f * FLOOR_H + 1.6, 0.45 if f % 2 == 0 else -0.45), 0.0, 0.0, true)
		window(on_round(r - 0.02, f * FLOOR_H + 1.6, PI * 0.5 + (0.3 if f % 2 == 0 else -0.3)), 0.0, 0.0, true)
		f += 1
	antennas(Vector3(-r * 0.55, h, 0), 4.0 + _rng.randf() * 1.8)


func _look_shop(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := mats.plaster(0.0, 1.4, LookMaterials.CLOTH_SAFFRON)
	const LEAN := 0.04
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	parapet(lx * (1.0 - LEAN), lz * (1.0 - LEAN), h, 0.5, mat)
	door(on_wall(lx * 0.5 - 0.02, 0, -lz * 0.22), 1.25)
	window(on_wall(wall_at(lx * 0.5, 1.9, h, LEAN), 1.9, lz * 0.18), 3.0, 1.0)
	# A flat metal awning on two struts along the shop front.
	part(box(1.7, 0.12, lz * 0.82), trim, Vector3(lx * 0.5 + 0.85, 3.05, 0))
	for s in [-1.0, 1.0]:
		part(box(1.75, 0.08, 0.08), metal, Vector3(lx * 0.5 + 0.8, 2.75, s * lz * 0.38), Basis(Vector3.BACK, 0.35))
	antennas(Vector3(-lx * 0.25, h, lz * 0.2), 3.0 + _rng.randf() * 1.5, PI * 0.5)


## Barracks hall: long, buttressed, three big doors onto the yard, a window in every other bay.
func _look_hall(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := _plaster(b, 1.4)
	const LEAN := 0.02
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	part(box(lx + 0.4, 0.6, lz + 0.4), trim, Vector3(0, 0.3, 0))
	parapet(lx * (1.0 - LEAN) + 0.3, lz * (1.0 - LEAN) + 0.3, h, 0.7, mat)
	var bays := int(lz / 5.0)
	var bay := lz / bays
	for i in bays + 1:
		part(box(0.8, h + 0.5, 0.9), mat, Vector3(lx * 0.5 + 0.2, (h + 0.5) * 0.5, -lz * 0.5 + i * bay))
	for i in bays:
		var z := -lz * 0.5 + (i + 0.5) * bay
		if i % 2 == 1:
			door(on_wall(lx * 0.5 - 0.02, 0, z), 1.35)
			part(box(0.9, 0.12, 2.6), trim, Vector3(lx * 0.5 + 0.35, 3.4, z))
		else:
			window(on_wall(lx * 0.5, 3.4, z), 2.0, 0.8)
	for i in 3:
		antennas(Vector3(-lx * 0.38, h, -lz * 0.36 + i * lz * 0.36), 4.5 + i * 0.8, PI * 0.5)


## The block stacked on the hall roof: a row of windows, relays on top.
func _look_upper(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := _plaster(b, float(b.min[1]) + 0.6)
	const LEAN := 0.03
	part(frustum(lx, lz, h, LEAN), mat, Vector3(0, h * 0.5, 0))
	part(box(lx * (1.0 - LEAN * 0.5) + 0.45, 0.22, lz * (1.0 - LEAN * 0.5) + 0.45), trim, Vector3(0, h * 0.5, 0))
	parapet(lx * (1.0 - LEAN) + 0.2, lz * (1.0 - LEAN) + 0.2, h, 0.6, mat)
	for i in 3:
		window(on_wall(wall_at(lx * 0.5, 2.0, h, LEAN), 2.0, -lz * 0.3 + i * lz * 0.3), 1.6, 0.8)
		window(on_wall(wall_at(lx * 0.5, 5.0, h, LEAN), 5.0, -lz * 0.3 + i * lz * 0.3), 1.6, 0.8)
	antennas(Vector3(-lx * 0.25, h, lz * 0.25), 6.0, PI * 0.5)
	antennas(Vector3(-lx * 0.25, h, -lz * 0.15), 3.5, PI * 0.5)


func _look_watchtower(b: Dictionary, lx: float, lz: float, h: float) -> void:
	var mat := _plaster(b, 2.9)
	const LEAN := 0.04
	# The plaster stops inside the crown, not flush with its top (they flickered).
	part(frustum(lx, lz, h - 0.2, LEAN), mat, Vector3(0, (h - 0.2) * 0.5, 0))
	var y := FLOOR_H
	while y < h - 1.0:
		var k := 1.0 - LEAN * y / h
		part(box(lx * k + 0.45, 0.22, lz * k + 0.45), trim, Vector3(0, y, 0))
		y += FLOOR_H
	# A heavier crown: the sentry stands up here.
	part(box(lx + 0.7, 0.4, lz + 0.7), trim, Vector3(0, h - 0.2, 0))
	parapet(lx + 0.7, lz + 0.7, h, 0.9, mat)
	door(on_wall(lx * 0.5 - 0.02, 0, 0), 1.1)
	for f in [1, 2]:
		window(on_wall(wall_at(lx * 0.5, f * FLOOR_H + 1.5, h, LEAN), f * FLOOR_H + 1.5, 0), 0.5, 0.9)
	antennas(Vector3(-lx * 0.5 + 0.2, h, lz * 0.5 - 0.9), 5.0)


## A rooftop bridge: deck, keel beam, rails and edge lights, a door at each end.
func _look_bridge(b: Dictionary, _lx: float, _lz: float, _h: float) -> void:
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var along_x := str(b.get("axis", "x")) == "x"
	_xf = Transform3D(Basis(Vector3.UP, 0.0 if along_x else -PI * 0.5), Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5))
	var length := (mx.x - mn.x) if along_x else (mx.z - mn.z)
	var width := (mx.z - mn.z) if along_x else (mx.x - mn.x)
	var t := mx.y - mn.y
	var deck := mats.hull(-50.0, 1.2)
	part(box(length, t, width), deck, Vector3(0, t * 0.5, 0))
	part(box(length, 0.4, 0.5), trim, Vector3(0, -0.2, 0))
	var n := maxi(2, int(length / 1.6) + 1)
	for s in [-1.0, 1.0]:
		var z: float = s * (width * 0.5 - 0.06)
		part(box(length, 0.06, 0.06), metal, Vector3(0, t + 1.0, z))
		part(box(length, 0.05, 0.05), metal, Vector3(0, t + 0.5, z))
		part(box(length, 0.05, 0.05), door_glow, Vector3(0, t + 0.03, z + s * 0.04))
		for i in n:
			part(box(0.06, 1.0, 0.06), metal, Vector3(-length * 0.5 + 0.1 + i * (length - 0.2) / (n - 1), t + 0.5, z))
	# Doors where the bridge meets each roof, facing along the bridge.
	for s in [-1.0, 1.0]:
		var at := Transform3D(Basis(Vector3.UP, 0.0 if s < 0 else PI), Vector3(s * length * 0.5, t, 0))
		door(at, 0.9)


func _look_cistern(b: Dictionary, lx: float, _lz: float, h: float) -> void:
	var r := lx * 0.5
	var mat := mats.plaster(0.0, 0.6, LookMaterials.CLOTH_TEAL)
	part(cyl(r * 0.95, r, h, 20), mat, Vector3(0, h * 0.5, 0))
	part(ring(r - 0.15, r + 0.08, h, h + 0.12, 20), trim, Vector3.ZERO)
	part(cyl(r - 0.15, r - 0.15, 0.04, 20), mats.flat(Color("#1d4a4c"), 0.15, 0.2), Vector3(0, h - 0.08, 0))
	solid_part(cyl(0.06, 0.08, 1.4, 6), metal, Vector3(-r + 0.25, h + 0.7, 0))
	solid_part(box(0.55, 0.08, 0.08), metal, Vector3(-r + 0.5, h + 1.3, 0))


## Barrels, crates and jars against the wall beside the door (huts only).
func _door_clutter(wall_x: float, door_z: float, lz: float) -> void:
	if _rng.randf() < 0.35:
		return
	var z := door_z - 1.35 if door_z - 1.35 > -lz * 0.5 + 0.35 else door_z + 1.35
	if absf(z) > lz * 0.5 - 0.3:
		return
	var x := wall_x + 0.32
	var was := solid
	solid = true
	match _rng.randi() % 3:
		0:
			part(cyl(0.28, 0.3, 0.8, 12), mats.flat(Color("#6a5848").lerp(LookMaterials.CLOTH_TEAL, _rng.randf() * 0.4), 0.7, 0.3), Vector3(x, 0.4, z))
			if _rng.randf() < 0.5:
				part(cyl(0.24, 0.26, 0.7, 12), mats.flat(Color("#5d4b3e"), 0.7, 0.3), Vector3(x + 0.1, 0.35, z + signf(z - door_z) * 0.55))
		1:
			part(box(0.6, 0.55, 0.7), crate_woods[_rng.randi() % 3], Vector3(x, 0.275, z), Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)))
			part(box(0.45, 0.4, 0.5), crate_woods[_rng.randi() % 3], Vector3(x, 0.75, z), Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)))
		2:
			var jar := mats.plaster(-1000.0, -1000.0, LookMaterials.CLOTH_TEAL, Color("#b07a52"))
			part(ball(0.26, 0.7, false, 12), jar, Vector3(x, 0.35, z))
			part(ball(0.2, 0.5, false, 12), jar, Vector3(x + 0.05, 0.25, z + signf(z - door_z) * 0.45))
	solid = was


# ---------------------------------------------------------------- the cantina

## The stair tower behind the bar: the same triangles it collides with, dressed.
func _look_stair_tower(b: Dictionary, _lx: float, _lz: float, _h: float) -> void:
	_xf = Transform3D.IDENTITY
	var t := StairTower.info(b)
	var parts := StairTower.tower_parts(b)
	var c: Vector3 = t.c
	var r: float = t.r
	var top: float = c.y + float(t.h)
	var wall := mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
	part(parts.wall, wall, Vector3.ZERO)
	part(parts.ramp, mats.hull(-50.0, 1.0), Vector3.ZERO)
	part(parts.core, trim, Vector3.ZERO)
	# Ledges round the outside, one per turn of the ramp inside.
	var y := c.y + float(t.rise)
	while y < top - 0.5:
		part(ring(r - 0.05, r + 0.25, y - 0.1, y + 0.1, 32), trim, Vector3(c.x, 0, c.z))
		# Issue #237: a lit band under each ledge, so the climb reads from the square at night.
		part(ring(r - 0.02, r + 0.06, y - 0.2, y - 0.12, 32), window_glow, Vector3(c.x, 0, c.z))
		y += float(t.rise)
	# Slit windows that climb with the ramp, and lights on the core at head height.
	var th: float = t.th0 + 0.6
	while th < float(t.th_end) - 0.4:
		var on_door := absf(wrapf(th - float(t.door_th), -PI, PI)) < 0.6
		var p := StairTower.ramp_point(t, r, th)
		if not on_door and p.y > 1.0:
			var at := Transform3D(Basis(Vector3.UP, -th), p + Vector3(0, 1.5, 0))
			_at(at, box(0.3, 0.9, 0.28), trim, Vector3(-0.02, 0, 0))
			_at(at, box(0.3, 0.7, 0.14), window_glow, Vector3(-0.06, 0, 0))
		var lp := StairTower.ramp_point(t, float(t.rc) + 0.03, th) + Vector3(0, 1.9, 0)
		put(ball(0.12, 0.2, false, 10), window_glow, Transform3D(Basis.IDENTITY, lp))      # issue #237: brighter lamps up the core
		th += PI * 0.5
	# The doorway: same frame and light as every door in town, left open.
	var dth: float = t.door_th
	door(Transform3D(Basis(Vector3.UP, -dth), c + Vector3(cos(dth), 0, sin(dth)) * (r - 0.12)), 1.1, true)


## The lookout: open on all sides, a dome and an antenna relay on the roof.
func _look_lookout(b: Dictionary, _lx: float, _lz: float, _h: float) -> void:
	_xf = Transform3D.IDENTITY
	var tower: Dictionary = town.get_box(str(b.get("stair", ""))) if town != null else {}
	if tower.is_empty():
		return
	var t := StairTower.info(tower)
	var parts := StairTower.lookout_parts(b, tower)
	var c: Vector3 = t.c
	var cc := Vector3(c.x, 0, c.z)
	var fy := float(b.min[1])
	var rr := minf(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2])) * 0.5
	var shell := mats.plaster(0.0, fy + 0.55, LookMaterials.CLOTH_TEAL)
	part(parts.floor, mats.hull(-50.0, 1.0), Vector3.ZERO)
	part(parts.parapet, shell, Vector3.ZERO)
	part(parts.posts, trim, Vector3.ZERO)
	part(parts.pillar, trim, Vector3.ZERO)
	part(parts.roof, shell, Vector3.ZERO)
	var roof_y := fy + StairTower.ROOM_H + 0.3
	part(ring(rr + 0.2, rr + 0.4, fy + StairTower.ROOM_H - 0.05, fy + StairTower.ROOM_H + 0.05, 40), door_glow, cc)
	part(ball(rr * 0.72, rr * 0.4, true, 28), shell, cc + Vector3(0, roof_y, 0))
	solid_dome(rr * 0.72, rr * 0.4, cc + Vector3(0, roof_y, 0))
	part(cyl(0.3, 0.45, 0.4, 12), trim, cc + Vector3(0, roof_y + rr * 0.4 + 0.15, 0))
	part(ring(rr * 0.72 - 0.05, rr + 0.1, roof_y, roof_y + 0.15, 40), trim, cc)
	antennas(cc + Vector3(-rr * 0.82, roof_y, 0), 5.5)
	# A rail round the open stairwell.
	var a0: float = float(t.th_end) + TAU * (1.0 - StairTower.OPEN_SPAN)
	var a1: float = float(t.th_end) + TAU
	var ri: float = float(t.ri)
	var n := 14
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		put(cyl(0.03, 0.03, 1.0, 6), metal, Transform3D(Basis.IDENTITY, cc + Vector3(cos(a) * ri, fy + 0.5, sin(a) * ri)))
	for i in n:
		var a := lerpf(a0, a1, float(i) / n)
		var b2 := lerpf(a0, a1, float(i + 1) / n)
		var p := cc + Vector3(cos(a) * ri, fy + 1.0, sin(a) * ri)
		var q := cc + Vector3(cos(b2) * ri, fy + 1.0, sin(b2) * ri)
		put(box(p.distance_to(q), 0.05, 0.05), metal, Transform3D(Basis(Vector3.UP, -atan2(q.z - p.z, q.x - p.x)), (p + q) * 0.5))


## The round stage in the middle of the cantina: lit rim, a step all round,
## speakers at the back and a microphone (not with a band on it, "band": their
## instruments and the club's speakers stand there instead), and a lighting ring
## hung from the ceiling.
func _look_stage(b: Dictionary, lx: float, _lz: float, h: float) -> void:
	var r := lx * 0.5
	var ceiling := 9.0
	if town != null and not town.get_box("cantina_roof").is_empty():
		ceiling = float(town.get_box("cantina_roof").min[1])
	part(cyl(r, r, h - 0.06, 40), mats.plaster(0.0, h * 0.5, LookMaterials.CLOTH_MADDER), Vector3(0, (h - 0.06) * 0.5, 0))
	part(cyl(r - 0.05, r - 0.05, 0.06, 40), mats.flat(Color("#2a2522"), 0.35, 0.3), Vector3(0, h - 0.03, 0))
	part(ring(r - 0.12, r + 0.02, h - 0.02, h + 0.03, 40), door_glow, Vector3.ZERO)
	part(ring(r, r + 0.45, 0.0, 0.22, 40), trim, Vector3.ZERO)
	for s in ([] if bool(b.get("band", false)) else [-1.0, 1.0]):
		var at := Transform3D(Basis(Vector3.UP, s * 0.35), Vector3(-r * 0.62, h, s * r * 0.5))
		_at(at, box(0.7, 1.3, 0.75), panel, Vector3(0, 0.65, 0))
		_at(at, cyl(0.24, 0.24, 0.06, 16), seam, Vector3(0.36, 0.42, 0), AXIS_X)
		_at(at, cyl(0.12, 0.12, 0.06, 12), seam, Vector3(0.36, 1.0, 0), AXIS_X)
		_at(at, box(0.04, 0.05, 0.5), door_glow, Vector3(0.36, 1.22, 0))
	if not bool(b.get("band", false)):          # issue #261: a band's instruments stand there instead
		part(cyl(0.02, 0.02, 1.5, 6), metal, Vector3(r * 0.55, h + 0.75, 0))
		part(cyl(0.18, 0.2, 0.03, 12), metal, Vector3(r * 0.55, h + 0.015, 0))
		part(ball(0.05, 0.12, false, 8), seam, Vector3(r * 0.55, h + 1.55, 0))
	# The lighting ring, hung on three rods, with lamps aimed down at the empty stage.
	var ry := ceiling - 2.6
	part(ring(r - 0.6, r - 0.35, ry - 0.12, ry + 0.12, 40), trim, Vector3.ZERO)
	for i in 3:
		var a := TAU * i / 3.0
		part(cyl(0.025, 0.025, ceiling - ry, 6), metal, Vector3(cos(a) * (r - 0.47), (ceiling + ry) * 0.5, sin(a) * (r - 0.47)))
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector3(cos(a) * (r - 0.47), ry - 0.28, sin(a) * (r - 0.47))
		part(cyl(0.11, 0.14, 0.3, 10), panel, p)
		part(cyl(0.1, 0.1, 0.02, 10), window_glow, p + Vector3(0, -0.16, 0))


## A crate stack on a cover box's footprint: never squared up. Each crate is turned
## a little and shrunk until the turn still fits inside the collision box. Issue
## #355: plank crates with painted iron bands.
func _look_crates(_b: Dictionary, lx: float, lz: float, h: float) -> void:
	var woods := crate_woods
	var two_low := lx > 1.9 and _rng.randf() < 0.5
	var h1 := h if _rng.randf() < 0.3 else h * _rng.randf_range(0.55, 0.65)
	if two_low:
		for s in [-1.0, 1.0]:
			_crate(Vector3(s * lx * 0.25, 0, 0), lx * 0.48, lz, h1 * _rng.randf_range(0.85, 1.0), woods[_rng.randi() % woods.size()])
	else:
		_crate(Vector3.ZERO, lx, lz, h1, woods[_rng.randi() % woods.size()])
	if h1 < h - 0.2:
		var off := Vector3(_rng.randf_range(-0.2, 0.2) * lx, h1, _rng.randf_range(-0.2, 0.2) * lz)
		_crate(off, lx * 0.6, lz * 0.6, h - h1, woods[_rng.randi() % woods.size()])


func _crate(base: Vector3, w: float, d: float, h: float, mat: Material) -> void:
	var yaw := _rng.randf_range(-0.45, 0.45)
	var cw := w * 0.9
	var cd := d * 0.9
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	var k := minf(1.0, minf(w / (cw * c + cd * s), d / (cw * s + cd * c)))
	cw = snappedf(cw * k, 0.05)
	cd = snappedf(cd * k, 0.05)
	var hh := snappedf(h, 0.05)
	var at := Basis(Vector3.UP, yaw)
	part(box(cw, hh, cd), mat, base + Vector3(0, hh * 0.5, 0), at)
	part(box(cw + 0.04, 0.08, cd + 0.04), crate_band, base + Vector3(0, hh * 0.3, 0), at)
	part(box(cw + 0.04, 0.08, cd + 0.04), crate_band, base + Vector3(0, hh * 0.75, 0), at)

