class_name ShipHull
extends StaticBody3D
## The hull a ship carries round with it (issue #55): you bump into it parked, and
## bolts hit it parked or flying. bolt.gd calls apply_damage on whatever it hits;
## this passes the damage to `on_damage` (ShipPilot), which decides if it counts.
##
## Issue #181: the owner stamps `damage_usec` when it does count a hit, and sets
## `dead` once the ship is down, so HitFeedback can tell a hit that hurt it (and a
## kill) from one it shrugged off, as it does for NPCs.

var on_damage: Callable
var damage_usec := 0             ## clock time of the last hit the owner counted
var dead := false


func apply_damage(amount: float) -> void:
	apply_damage_from(amount, null)


## Issue #64: who shot it matters (another ship can destroy a parked one).
func apply_damage_from(amount: float, shooter: Node) -> void:
	if on_damage.is_valid():
		on_damage.call(amount, shooter)


## The owner counted the hit that just landed.
func took_damage() -> void:
	damage_usec = Time.get_ticks_usec()


# ------------------------------------------------------------------ shape

## The ship's own shape, not one box round it: bolts that pass between the wings
## miss, and you can walk under a wing or up to the nose. The model is cut into a
## grid of cells ("hull_fit" in content/look/ships.json) and each cell's share of
## the mesh is wrapped in its own convex hull; a small low-poly part (a stand-in's
## box, cylinder or prism, a bolted-on gun) is convex already and keeps its own
## hull. Worked out once per look and shared by every ship that wears it.
const LOOKS_PATH := "res://content/look/ships.json"
const FIT_DEFAULTS := {
	"cell": 1.2, "overlap": 0.12, "max_cells": 10, "max_points": 600,
	"part_verts": 300, "min_thickness": 0.06,
}

static var _fits := {}             ## cache key -> Array of ConvexPolygonShape3D
static var _fit_cfg := {}


## Fill this hull with convex pieces fitted to the meshes under `model`, in
## `model`'s own frame (the hull is placed at the model's root). False, and nothing
## added, when the model has no meshes (the greybox): the caller sizes a box.
func fit(model: Node3D) -> bool:
	var pieces := shape_of(model)
	for i in pieces.size():
		var cs := CollisionShape3D.new()
		cs.name = "Piece%d" % i
		cs.shape = pieces[i]
		add_child(cs)
	return not pieces.is_empty()


## A plain box: the greybox, or a model with nothing to fit.
func fit_box(size: Vector3, center: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Box"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = center
	add_child(cs)


## The convex pieces for a model (cached by its look, mesh count and bounds, so a
## ship dressed with upgrades gets its own). Empty with no meshes.
static func shape_of(model: Node3D) -> Array:
	var parts: Array = []        # [{"xf": Transform3D, "mesh": Mesh}]
	_gather(model, Transform3D.IDENTITY, parts)
	if parts.is_empty():
		return []
	var bounds := AABB()
	for p: Dictionary in parts:
		bounds = bounds.merge((p.xf as Transform3D) * (p.mesh as Mesh).get_aabb())
	var key := "%s/%d/%s" % [str(model.get_meta("look_id", model.scene_file_path)), parts.size(), str(bounds)]
	if _fits.has(key):
		return _fits[key]
	var pieces := _fit_parts(parts)
	_fits[key] = pieces
	return pieces


static func _cfg(k: String) -> float:
	if _fit_cfg.is_empty():
		_fit_cfg = FIT_DEFAULTS.duplicate()
		var f := FileAccess.open(LOOKS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary and (d as Dictionary).get("hull_fit") is Dictionary:
			_fit_cfg.merge(d.hull_fit, true)
	return float(_fit_cfg.get(k, FIT_DEFAULTS.get(k, 0.0)))


## Every visible mesh under `n` with its transform in the root's frame. Engine
## flames (meta no_bounds) are light, not metal, and only there under throttle.
static func _gather(n: Node, xf: Transform3D, out: Array) -> void:
	for c in n.get_children():
		if c.has_meta("no_bounds") or c is ShipHull:
			continue
		var t := xf
		if c is Node3D:
			if not (c as Node3D).visible:
				continue
			t = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append({"xf": t, "mesh": (c as MeshInstance3D).mesh})
		_gather(c, t, out)


static func _fit_parts(parts: Array) -> Array:
	var pieces: Array = []
	var pool := PackedVector3Array()           # points of the big meshes, cut into cells
	var part_verts := int(_cfg("part_verts"))
	for p: Dictionary in parts:
		var mesh: Mesh = p.mesh
		var xf: Transform3D = p.xf
		var pts := PackedVector3Array()
		for s in mesh.get_surface_count():
			var vs: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vs:
				pts.append(xf * v)
		if pts.is_empty():
			continue
		if pts.size() <= part_verts:
			var hull := _hull(pts)
			if hull != null:
				pieces.append(hull)
		else:
			pool.append_array(pts)
	if not pool.is_empty():
		pieces.append_array(_fit_cells(pool))
	return pieces


## Cut a point cloud into a grid of cells and wrap each cell's points. Points near
## a cell wall go into both cells, so the pieces meet with no seam between them.
static func _fit_cells(pool: PackedVector3Array) -> Array:
	var box := AABB(pool[0], Vector3.ZERO)
	for v in pool:
		box = box.expand(v)
	var cell := maxf(0.2, _cfg("cell"))
	var max_cells := maxi(1, int(_cfg("max_cells")))
	var n := Vector3i(
		clampi(ceili(box.size.x / cell), 1, max_cells),
		clampi(ceili(box.size.y / cell), 1, max_cells),
		clampi(ceili(box.size.z / cell), 1, max_cells))
	var step := Vector3(box.size.x / n.x, box.size.y / n.y, box.size.z / n.z)
	var lap := Vector3.ONE * _cfg("overlap")
	var cells := {}                    # Vector3i -> Array of Vector3 (by reference, unlike a packed array)
	for v in pool:
		var lo := _cell_of(v - lap, box.position, step, n)
		var hi := _cell_of(v + lap, box.position, step, n)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var k := Vector3i(x, y, z)
					if not cells.has(k):
						cells[k] = []
					(cells[k] as Array).append(v)
	var pieces: Array = []
	var max_points := maxi(8, int(_cfg("max_points")))
	for k: Vector3i in cells:
		var pts := PackedVector3Array(cells[k] as Array)
		if pts.size() < 4:
			continue
		if pts.size() > max_points:
			var thin := PackedVector3Array()
			var every := float(pts.size()) / max_points
			var i := 0.0
			while int(i) < pts.size():
				thin.append(pts[int(i)])
				i += every
			pts = thin
		var hull := _hull(pts)
		if hull != null:
			pieces.append(hull)
	return pieces


static func _cell_of(v: Vector3, origin: Vector3, step: Vector3, n: Vector3i) -> Vector3i:
	var r := v - origin
	return Vector3i(
		clampi(int(floor(r.x / step.x)) if step.x > 0.0 else 0, 0, n.x - 1),
		clampi(int(floor(r.y / step.y)) if step.y > 0.0 else 0, 0, n.y - 1),
		clampi(int(floor(r.z / step.z)) if step.z > 0.0 else 0, 0, n.z - 1))


## The convex hull of some points. A flat set (one panel of a wing) is given a
## little thickness first, or there is no hull to make. Null if it still fails.
static func _hull(pts: PackedVector3Array) -> ConvexPolygonShape3D:
	var box := AABB(pts[0], Vector3.ZERO)
	for v in pts:
		box = box.expand(v)
	var t := _cfg("min_thickness")
	for axis in 3:
		if box.size[axis] < t:
			var off := Vector3.ZERO
			off[axis] = t * 0.5
			var thick := PackedVector3Array()
			for v in pts:
				thick.append(v + off)
				thick.append(v - off)
			pts = thick
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var cloud := ArrayMesh.new()
	cloud.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var shape := cloud.create_convex_shape(true, false)
	if shape == null or shape.points.size() < 4:
		return null
	return shape
