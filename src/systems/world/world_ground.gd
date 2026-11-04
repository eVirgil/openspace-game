class_name WorldGround
extends RefCounted
## What a ship can land on or fly into (M14). Pure and headless-testable: the
## terrain, the town's boxes (floors, roofs, walls, ramps) and the world's
## landmarks (mesas, spires, the outpost's buildings), all from data. The flight
## model asks it two questions every frame:
##
##   ground_at(x, z, below)  -- the highest surface under (x, z) at or below `below`
##                              (so a ship over a roof lands on the roof, a ship
##                              under the gate lintel lands on the street)
##   hit(p, r)               -- the first solid thing a sphere at p touches, or ""
##
## No physics engine involved, so the dogfight-style pure flight model can fly
## through the town in a headless trace exactly as in the game.

const RingWall := preload("res://src/systems/world/ring_wall.gd")
const FLOOR_KINDS := ["floor"]
## Box kinds that are not part of the world a ship flies through: the "ship" box
## in the town data is the parked ship itself; the "bowl" is the round pit's
## hollow shell (its square box would be a lid over the pit).
const SKIP_KINDS := ["ship", "bowl"]

var terrain: WorldTerrain
var boxes: Array = []        ## { id, kind, min: Vector3, max: Vector3, ramp_axis, ramp_sign, xf? }
var columns: Array = []      ## { id, center: Vector3 (base), radius, top, up?, h? }  (mesas, spires)
## Issue #77: on the home planet's ball, a box away from the town may lean with the
## ground: "xf" (Transform3D) is its own frame and min/max are in it. A column may
## too: "up" is its axis and "h" its height above its base. Town boxes and every
## box on a flat world have neither and are plain world-space boxes.
var world: Dictionary = {}
## Issue #93: the desert's boulders ({ center, up, radius, height }, from
## DesertLandforms). Each is a smooth hump of ground (wider than the rock: sand
## banks against it), so a speeder rides up a low one and launches off it; one
## taller than RAMP_MAX is also a wall a speeder or ship hits.
var boulders: Array = []
const RAMP_MAX := 3.0
const RAMP_SPREAD := 1.6


func add_boulders(list: Array) -> void:
	boulders.append_array(list)


## A boulder's hump: its height above its centre at `off` metres from its axis.
static func boulder_top(b: Dictionary, off: float) -> float:
	var r := float(b.radius) * RAMP_SPREAD
	if off >= r:
		return -INF
	return float(b.height) * (0.5 + 0.5 * cos(PI * off / r))


## Build from a world entry (content/core/worlds/*.json), the town it holds and
## the content (for location landmarks such as the outpost). Any part may be empty.
## `height_source` / `desert_extent`: the town's DesertTerrain.height_at and its
## extent, when the desert is on (see WorldTerrain).
func setup(world_cfg: Dictionary, town = null, content = null,
		height_source: Callable = Callable(), desert_extent: float = -1.0) -> void:
	world = world_cfg
	terrain = WorldTerrain.new(world_cfg.get("terrain", {}), height_source, desert_extent)
	boxes = []
	columns = []
	if town != null:
		for b in town.boxes():
			if str(b.kind) == "ring":
				# Issue #237: a round wall is its pieces, each a box in its own frame.
				var k := 0
				for p in RingWall.pieces(b):
					var h: Vector3 = p.size * 0.5
					add_box("%s_%d" % [str(b.id), k], "wall", -h, h, "", true, Transform3D(p.basis, p.center))
					k += 1
				continue
			add_box(str(b.id), str(b.kind), _v3(b.min), _v3(b.max), str(b.get("rise_toward", "")))
	for lm in world_cfg.get("landmarks", []):
		_add_landmark(lm, content)


func add_box(id: String, kind: String, mn: Vector3, mx: Vector3, rise: String = "", visual: bool = true,
		xf = null) -> void:
	if SKIP_KINDS.has(kind):
		return
	var b := { "id": id, "kind": kind, "min": mn, "max": mx, "rise": rise, "visual": visual }
	if xf is Transform3D and xf != Transform3D.IDENTITY:
		b.xf = xf
	boxes.append(b)


## The planet's ball, or null on a flat world.
func sphere() -> PlanetSphere:
	return terrain.sphere if terrain != null else null


## "Up" at p: the ground's on the home planet's ball, straight up elsewhere.
func up_at(p: Vector3) -> Vector3:
	var sp := sphere()
	return sp.up_at(p) if sp != null else Vector3.UP


## A box's own frame (identity for a plain world-space box).
static func box_xf(b: Dictionary) -> Transform3D:
	return b.get("xf", Transform3D.IDENTITY)


## How high p is over the highest surface beneath it (along up_at(p)): the sand,
## a roof, a mesa's top. Surfaces up to 0.5 m above p count (a step up), as in
## ground_at. Negative when p is under the ground.
##
## Spatially culled, with exactly the result of testing every box, column and
## boulder: an item only counts when its contribution is at least -0.5 (a step up)
## and only lowers h when it is below the current h, and the point it is measured
## to lies on the item itself, |contribution| * (the length of the axis it is
## measured along) from p. So an item whose bounding sphere is further than
## max(h, 0.5) * axis_length from p cannot change the answer and is skipped without
## running its own test; the tests that do run are the old ones, unchanged.
##
## From high up (a ship in orbit) that sphere reaches every item, so a wide query
## also uses the line the item is measured along: that point lies on the line
## through p along the item's axis (a box's own Y, a column's or boulder's up, the
## gravity up at p for a wreck plate), so an item whose sphere misses that line is
## skipped too. A cell is skipped when no item in it can reach the line (its
## items' axes are within `spread` of the cell's).
func height_above(p: Vector3) -> float:
	var sp := sphere()
	if sp == null:
		return p.y - ground_at(p.x, p.z, p.y)
	var h := sp.height_above_ground(p)
	if not is_finite(h):
		return _height_above_linear(p, h)
	if h < -0.5:
		return h            # every contribution is >= -0.5: none can lower it
	if _ix_stale():
		_build_index()
	if not _ix_ok:
		return _height_above_linear(p, h)
	# The cells that can hold a small item reaching p (they are binned by centre).
	var reach := maxf(h, 0.5) * _ix_small_scale + _ix_small_radius
	var rv := Vector3(reach, reach, reach)
	var lo := ((p - rv) / IX_CELL).floor()
	var hi := ((p + rv) / IX_CELL).floor()
	var cells := (hi.x - lo.x + 1.0) * (hi.y - lo.y + 1.0) * (hi.z - lo.z + 1.0)
	var wide := cells > IX_MAX_CELLS
	var wreck_up := up_at(p) if wide else Vector3.ZERO
	var wreck_up_set := wide
	var axis := _ix_axis
	var nb := _ix_nb
	var nc := _ix_nc
	var ctr := _ix_ctr
	var rad := _ix_rad
	var scl := _ix_scl
	var q := maxf(h, 0.5)
	# Big (and malformed) items first, then the grid cells in reach.
	var lists: Array = [_ix_big]
	if cells <= IX_MAX_CELLS:
		for cz in range(int(lo.z), int(hi.z) + 1):
			for cy in range(int(lo.y), int(hi.y) + 1):
				for cx in range(int(lo.x), int(hi.x) + 1):
					var ci: int = _ix_grid.get(_ix_key(cx, cy, cz), -1)
					if ci >= 0:
						lists.append(_ix_cells[ci])
	else:
		# Wide query: test each occupied cell's own sphere and line instead of
		# walking the grid.
		var qs := q * _ix_small_scale
		for ci in _ix_cells.size():
			var cc: Vector3 = _ix_cell_ctr[ci]
			var cr: float = _ix_cell_rad[ci]
			if p.distance_to(cc) > qs + cr:
				continue
			var rc := cc - p
			var near := false
			if _ix_cell_plain[ci]:
				var a: Vector3 = _ix_cell_axis[ci]
				var al := rc.dot(a)
				var lim := cr + (rc.length() + cr) * _ix_cell_spread[ci]
				near = rc.length_squared() - al * al <= lim * lim
			if not near and _ix_cell_wreck[ci]:
				var aw := rc.dot(wreck_up)
				near = rc.length_squared() - aw * aw <= cr * cr
			if near:
				lists.append(_ix_cells[ci])
	for list in lists:
		for i in (list as PackedInt32Array):
			if p.distance_to(ctr[i]) > q * scl[i] + rad[i]:
				continue
			if wide:
				var ri: Vector3 = ctr[i] - p
				var ai: Vector3 = axis[i]
				var along := ri.dot(wreck_up if ai == Vector3.ZERO else ai)
				if ri.length_squared() - along * along > rad[i] * rad[i]:
					continue
			if i < nb:
				var b: Dictionary = boxes[i]
				if b.has("wreck_finish"):
					if not wreck_up_set:
						wreck_up = up_at(p)
						wreck_up_set = true
					h = minf(h, box_height_below(b, p, wreck_up))
				else:
					h = _box_contrib(b, p, h)
			elif i < nb + nc:
				h = _column_contrib(columns[i - nb], p, h)
			else:
				h = _boulder_contrib(boulders[i - nb - nc], p, h)
			q = maxf(h, 0.5)
	return h


## What a plain box does to h (a wreck plate is handled by the caller).
static func _box_contrib(b: Dictionary, p: Vector3, h: float) -> float:
	var lp := p
	if b.has("xf"):
		lp = box_xf(b).affine_inverse() * p
	var mn: Vector3 = b.min
	var mx: Vector3 = b.max
	if lp.x < mn.x or lp.x > mx.x or lp.z < mn.z or lp.z > mx.z:
		return h
	var top := box_top(b, lp.x, lp.z)
	if top <= lp.y + 0.5:
		return minf(h, lp.y - top)
	return h


static func _column_contrib(c: Dictionary, p: Vector3, h: float) -> float:
	var up: Vector3 = c.get("up", Vector3.UP)
	var rel: Vector3 = p - (c.center as Vector3)
	var along := rel.dot(up)
	if (rel - up * along).length() > float(c.radius):
		return h
	var top: float = c.get("h", float(c.top) - (c.center as Vector3).y)
	if top <= along + 0.5:
		return minf(h, along - top)
	return h


static func _boulder_contrib(bd: Dictionary, p: Vector3, h: float) -> float:
	var bu: Vector3 = bd.up
	var rel: Vector3 = p - (bd.center as Vector3)
	if rel.length_squared() > pow(float(bd.radius) * RAMP_SPREAD + float(bd.height) + 50.0, 2.0):
		return h
	var along := rel.dot(bu)
	var bt := boulder_top(bd, (rel - bu * along).length())
	if bt > -INF and bt <= along + 0.5:
		return minf(h, along - bt)
	return h


## The plain test of every box, column and boulder (the index falls back to this
## for a query too wide for it to help, and it is what the index must equal). A box
## with no frame of its own is tested in the world frame directly: identical to
## multiplying by the inverse of the identity, without building it.
func _height_above_linear(p: Vector3, h_start: float) -> float:
	var h := h_start
	var wreck_up := up_at(p)
	for b in boxes:
		if b.has("wreck_finish"):
			h = minf(h, box_height_below(b, p, wreck_up))
			continue
		var lp := p
		if b.has("xf"):
			lp = box_xf(b).affine_inverse() * p
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if lp.x < mn.x or lp.x > mx.x or lp.z < mn.z or lp.z > mx.z:
			continue
		var top := box_top(b, lp.x, lp.z)
		if top <= lp.y + 0.5:
			h = minf(h, lp.y - top)
	for c in columns:
		var up: Vector3 = c.get("up", Vector3.UP)
		var rel: Vector3 = p - (c.center as Vector3)
		var along := rel.dot(up)
		if (rel - up * along).length() > float(c.radius):
			continue
		var top: float = c.get("h", float(c.top) - (c.center as Vector3).y)
		if top <= along + 0.5:
			h = minf(h, along - top)
	for bd in boulders:
		var bu: Vector3 = bd.up
		var rel: Vector3 = p - (bd.center as Vector3)
		if rel.length_squared() > pow(float(bd.radius) * RAMP_SPREAD + float(bd.height) + 50.0, 2.0):
			continue
		var along := rel.dot(bu)
		var bt := boulder_top(bd, (rel - bu * along).length())
		if bt > -INF and bt <= along + 0.5:
			h = minf(h, along - bt)
	return h


# ---------------------------------------------------------------- spatial index

## Items (boxes, then columns, then boulders; one list, numbered in that order) get
## a world-space bounding sphere each. Small ones are binned by centre into a sparse
## 3D grid; big ones (floors, mesas, wreck plates) and malformed ones are kept in a
## short list tested by sphere. Built lazily on the first height_above after the
## geometry changes.
const IX_CELL := 96.0
const IX_SMALL_RADIUS := 48.0      ## items with a bigger sphere go to the big list
const IX_SLACK := 2.0              ## metres added to every sphere: float rounding is nowhere near it
const IX_MAX_CELLS := 48.0         ## a query touching more cells than this tests the occupied cells' spheres and lines
const IX_MIN_ITEMS := 24           ## fewer items than this: scanning is as cheap

var _ix_ok := false                ## the index is built and usable
var _ix_built := false
var _ix_boxes: Array
var _ix_columns: Array
var _ix_boulders: Array
var _ix_nb := 0
var _ix_nc := 0
var _ix_nbd := 0
var _ix_ctr := PackedVector3Array()
var _ix_rad := PackedFloat64Array()
var _ix_scl := PackedFloat64Array()
var _ix_axis := PackedVector3Array()   ## unit axis each item is measured along (ZERO: the gravity up at p)
var _ix_big := PackedInt32Array()
var _ix_grid := {}                 ## cell key -> index into _ix_cells
var _ix_cells: Array = []          ## per occupied cell: PackedInt32Array of item numbers
var _ix_cell_ctr := PackedVector3Array()
var _ix_cell_rad := PackedFloat64Array()
var _ix_cell_axis := PackedVector3Array()      ## the mean axis of a cell's own-axis items
var _ix_cell_spread := PackedFloat64Array()    ## how far any of their axes is from it
var _ix_cell_plain := PackedByteArray()        ## the cell has items with an axis of their own
var _ix_cell_wreck := PackedByteArray()        ## ... and wreck plates (measured along the gravity up)
var _ix_small_radius := 0.0
var _ix_small_scale := 1.0


## Geometry edited after it was registered (a box's min/max/xf, a column's or
## boulder's centre/radius/top/up/height, or an item swapped for another one) is
## not noticed: call this so the next query rebuilds the index. Adding or removing
## items, or replacing the arrays, is noticed by itself.
func invalidate_index() -> void:
	_ix_built = false


func _ix_stale() -> bool:
	return not _ix_built or boxes.size() != _ix_nb or columns.size() != _ix_nc \
		or boulders.size() != _ix_nbd or not is_same(boxes, _ix_boxes) \
		or not is_same(columns, _ix_columns) or not is_same(boulders, _ix_boulders)


static func _ix_key(cx: int, cy: int, cz: int) -> int:
	return (cx + 4096) | ((cy + 4096) << 13) | ((cz + 4096) << 26)


func _build_index() -> void:
	_ix_built = true
	_ix_boxes = boxes
	_ix_columns = columns
	_ix_boulders = boulders
	_ix_nb = boxes.size()
	_ix_nc = columns.size()
	_ix_nbd = boulders.size()
	var n := _ix_nb + _ix_nc + _ix_nbd
	_ix_ctr = PackedVector3Array()
	_ix_ctr.resize(n)
	_ix_rad = PackedFloat64Array()
	_ix_rad.resize(n)
	_ix_scl = PackedFloat64Array()
	_ix_scl.resize(n)
	_ix_axis = PackedVector3Array()
	_ix_axis.resize(n)
	_ix_big = PackedInt32Array()
	_ix_grid = {}
	_ix_cells = []
	_ix_small_radius = 0.0
	_ix_small_scale = 1.0
	_ix_ok = n >= IX_MIN_ITEMS
	if not _ix_ok:
		return
	for i in n:
		var s := _item_sphere(i)       # (centre.xyz, radius); its axis length goes to _ix_scl[i], its direction to _ix_axis[i]
		var ok := is_finite(s.w) and is_finite(s.x) and is_finite(s.y) and is_finite(s.z) \
			and is_finite(_ix_scl[i]) and absf(s.x) < 390000.0 and absf(s.y) < 390000.0 \
			and absf(s.z) < 390000.0
		if not ok:
			# Always tested: infinite reach, nothing assumed about it.
			_ix_ctr[i] = Vector3.ZERO
			_ix_rad[i] = INF
			_ix_scl[i] = 1.0
			_ix_axis[i] = Vector3.UP
			_ix_big.append(i)
			continue
		_ix_ctr[i] = Vector3(s.x, s.y, s.z)
		_ix_rad[i] = s.w + IX_SLACK
		if s.w > IX_SMALL_RADIUS or _ix_scl[i] > 4.0:
			_ix_big.append(i)
			continue
		_ix_small_radius = maxf(_ix_small_radius, _ix_rad[i])
		_ix_small_scale = maxf(_ix_small_scale, _ix_scl[i])
		var key := _ix_key(int(floorf(s.x / IX_CELL)), int(floorf(s.y / IX_CELL)), int(floorf(s.z / IX_CELL)))
		var ci: int = _ix_grid.get(key, -1)
		if ci < 0:
			ci = _ix_cells.size()
			_ix_grid[key] = ci
			_ix_cells.append(PackedInt32Array())
		var cell: PackedInt32Array = _ix_cells[ci]
		cell.append(i)
		_ix_cells[ci] = cell
	# A sphere round each occupied cell's items.
	_ix_cell_ctr = PackedVector3Array()
	_ix_cell_ctr.resize(_ix_cells.size())
	_ix_cell_rad = PackedFloat64Array()
	_ix_cell_rad.resize(_ix_cells.size())
	_ix_cell_axis = PackedVector3Array()
	_ix_cell_axis.resize(_ix_cells.size())
	_ix_cell_spread = PackedFloat64Array()
	_ix_cell_spread.resize(_ix_cells.size())
	_ix_cell_plain = PackedByteArray()
	_ix_cell_plain.resize(_ix_cells.size())
	_ix_cell_wreck = PackedByteArray()
	_ix_cell_wreck.resize(_ix_cells.size())
	for ci in _ix_cells.size():
		var items: PackedInt32Array = _ix_cells[ci]
		var c := Vector3.ZERO
		var a := Vector3.ZERO
		for i in items:
			c += _ix_ctr[i]
			a += _ix_axis[i]
			if _ix_axis[i] == Vector3.ZERO:
				_ix_cell_wreck[ci] = 1
			else:
				_ix_cell_plain[ci] = 1
		c /= items.size()
		a = a.normalized() if a.length() > 0.001 else Vector3.UP
		var r := 0.0
		var spread := 0.0
		for i in items:
			r = maxf(r, c.distance_to(_ix_ctr[i]) + _ix_rad[i])
			if _ix_axis[i] != Vector3.ZERO:
				spread = maxf(spread, a.distance_to(_ix_axis[i]))
		_ix_cell_ctr[ci] = c
		_ix_cell_rad[ci] = r
		_ix_cell_axis[ci] = a
		_ix_cell_spread[ci] = spread


## Bounding sphere (x, y, z, r) of item i, and the length of the axis its height is
## measured along in _ix_scl[i]. A column or boulder whose axis is not a unit vector
## (the witness argument needs one) is NaN, which sends it to the always-tested list.
func _item_sphere(i: int) -> Vector4:
	if i < _ix_nb:
		var b: Dictionary = boxes[i]
		var xf := box_xf(b)
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var ctr := xf * ((mn + mx) * 0.5)
		var r := 0.0
		for k in 8:
			var corner := Vector3(mx.x if k & 1 else mn.x, mx.y if k & 2 else mn.y, mx.z if k & 4 else mn.z)
			r = maxf(r, ctr.distance_to(xf * corner))
		# A plain box is measured along its own Y, a wreck plate along the unit up.
		_ix_scl[i] = maxf(1.0, xf.basis.y.length())
		_ix_axis[i] = Vector3.ZERO if b.has("wreck_finish") else xf.basis.y.normalized()
		return Vector4(ctr.x, ctr.y, ctr.z, r)
	if i < _ix_nb + _ix_nc:
		var c: Dictionary = columns[i - _ix_nb]
		var up: Vector3 = c.get("up", Vector3.UP)
		var base: Vector3 = c.center
		var top: float = c.get("h", float(c.top) - base.y)
		_ix_scl[i] = up.length()
		if absf(up.length() - 1.0) > 0.001:
			return Vector4(NAN, NAN, NAN, NAN)
		_ix_axis[i] = up
		var ctr2 := base + up * (top * 0.5)
		return Vector4(ctr2.x, ctr2.y, ctr2.z, sqrt(top * top * 0.25 + float(c.radius) * float(c.radius)))
	var bd: Dictionary = boulders[i - _ix_nb - _ix_nc]
	var bu: Vector3 = bd.up
	_ix_scl[i] = bu.length()
	if absf(bu.length() - 1.0) > 0.001:
		return Vector4(NAN, NAN, NAN, NAN)
	var hh := float(bd.height)
	var rr := float(bd.radius) * RAMP_SPREAD
	_ix_axis[i] = bu
	var ctr3: Vector3 = (bd.center as Vector3) + bu * (hh * 0.5)
	return Vector4(ctr3.x, ctr3.y, ctr3.z, sqrt(hh * hh * 0.25 + rr * rr))


## The ground point under p along up_at(p).
func surface_below(p: Vector3) -> Vector3:
	return p - up_at(p) * height_above(p)


func _add_landmark(lm: Dictionary, content) -> void:
	if str(lm.get("kind", "")) == "wreck":
		StarcruiserWreck.add_to_ground(self, lm)
		return
	if str(lm.get("kind", "")) == CruiserHull.LANDMARK_KIND:
		CruiserHull.add_to_ground(self, lm)         # issue #193: in orbit, not on the ground
		return
	var at := _v3(lm.get("at", [0, 0, 0]))
	if sphere() != null:
		_add_landmark_on_ball(lm, content, at)
		return
	var base := terrain.height_at(at.x, at.z)
	match str(lm.get("kind", "")):
		"mesa", "spire":
			columns.append({ "id": str(lm.get("id", "")), "kind": str(lm.kind),
				"center": Vector3(at.x, base, at.z), "radius": float(lm.get("radius", 100.0)),
				"top": base + float(lm.get("height", 100.0)) })
		"location":
			var loc: Dictionary = content.get_location(str(lm.get("location", ""))) if content != null else {}
			var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
			for b in pieces(loc):
				var s := _v3(b.get("size", [4, 4, 4]))
				var p := _v3(b.get("position", [0, 0, 0])).rotated(Vector3.UP, yaw)
				var c := Vector3(at.x + p.x, base, at.z + p.z)
				# Axis-aligned footprint that covers the rotated building.
				var hx := (absf(cos(yaw)) * s.x + absf(sin(yaw)) * s.z) * 0.5
				var hz := (absf(sin(yaw)) * s.x + absf(cos(yaw)) * s.z) * 0.5
				# Issue #42: a building may be a ramp ("rise": the side its top slopes up
				# to, in the world frame; ramps are ground, not obstacles) and may skip
				# the placeholder box when something else dresses it ("visual": false).
				# Issue #295: its position's y lifts it off the sand (a garage roof).
				add_box(str(lm.get("id", "")) + "/" + str(b.get("id", "")), "solid",
					Vector3(c.x - hx, base + p.y, c.z - hz), Vector3(c.x + hx, base + p.y + s.y, c.z + hz),
					str(b.get("rise", "")), bool(b.get("visual", true)))


## Issue #77: a landmark at map (at.x, at.z) on the ball, standing along the ground's
## up there: buildings become boxes in its own frame (no footprint growth from the
## yaw), mesas and spires columns along its up.
func _add_landmark_on_ball(lm: Dictionary, content, at: Vector3) -> void:
	var sp := sphere()
	var base := sp.surface_at(at.x, at.z)
	var up := sp.up_at(base)
	var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
	match str(lm.get("kind", "")):
		"mesa", "spire":
			var h := float(lm.get("height", 100.0))
			columns.append({ "id": str(lm.get("id", "")), "kind": str(lm.kind), "center": base,
				"radius": float(lm.get("radius", 100.0)), "up": up, "h": h, "top": base.y + h })
		"location":
			var loc: Dictionary = content.get_location(str(lm.get("location", ""))) if content != null else {}
			var xf := Transform3D(PlanetSphere.tilt_to(up) * Basis(Vector3.UP, yaw), base)
			for b in pieces(loc):
				var s := _v3(b.get("size", [4, 4, 4]))
				var c := _v3(b.get("position", [0, 0, 0]))
				# "rise" is in the world frame on a flat world; here the box's own frame
				# carries the yaw, so turn it back into the landmark's frame.
				add_box(str(lm.get("id", "")) + "/" + str(b.get("id", "")), "solid",
					Vector3(c.x - s.x * 0.5, c.y, c.z - s.z * 0.5), Vector3(c.x + s.x * 0.5, c.y + s.y, c.z + s.z * 0.5),
					_rise_local(str(b.get("rise", "")), yaw), bool(b.get("visual", true)), xf)


## A location's buildings as solid boxes. Issue #309: a control room (a building
## with "room") is its walls and roof, with a doorway (OutpostRoom.shell).
static func pieces(loc: Dictionary) -> Array:
	var out: Array = []
	for b in loc.get("buildings", []):
		out.append_array(OutpostRoom.shell(b))
	return out


## A world-frame ramp side ("+x", "-z", ...) as seen from a frame turned by yaw.
static func _rise_local(rise: String, yaw: float) -> String:
	if rise == "":
		return ""
	var dir := { "+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+z": Vector3.BACK, "-z": Vector3.FORWARD }[rise] as Vector3
	var l := Basis(Vector3.UP, yaw).inverse() * dir
	if absf(l.x) >= absf(l.z):
		return "+x" if l.x > 0.0 else "-x"
	return "+z" if l.z > 0.0 else "-z"


## The desert's mesas and hoodoos (content/look/desert_landforms.json, the data
## DesertLandforms builds them from), as columns a ship can hit or land on top of.
## Same skip rule as DesertLandforms: nothing within keep_out (grown by the data's
## margin), so the columns are exactly the rocks on screen. Sizes follow its meshes:
##   mesa   -- tapered shelf, its feet buried 2 m under the ground
##   hoodoo -- column 0.55r..r, h tall, centred 0.45h up, capped by a 0.9r stone
func add_landforms(data: Dictionary, keep_out: Rect2) -> void:
	var clear := keep_out.grow(float(data.get("keep_out_margin", 25.0)))
	if sphere() != null:
		_add_landforms_on_ball(data, clear)
		return
	for m in data.get("mesas", []):
		if not clear.grow(float(m[2])).has_point(Vector2(m[0], m[1])):
			var gy := terrain.height_at(m[0], m[1])
			columns.append({ "id": "mesa_%d_%d" % [int(m[0]), int(m[1])], "kind": "mesa",
				"center": Vector3(m[0], gy, m[1]), "radius": float(m[2]) * 0.9,
				"top": gy + float(m[3]) * 0.92 - DesertLandforms.MESA_BURY })
	for hd in data.get("hoodoos", []):
		if not clear.grow(float(hd[2])).has_point(Vector2(hd[0], hd[1])):
			var gy := terrain.height_at(hd[0], hd[1])
			columns.append({ "id": "hoodoo_%d_%d" % [int(hd[0]), int(hd[1])], "kind": "hoodoo",
				"center": Vector3(hd[0], gy, hd[1]), "radius": float(hd[2]) * 0.9,
				"top": gy + float(hd[3]) * 0.95 + float(hd[2]) * 0.4 })


## Issue #77: the same columns, standing along the ball's up at their map spot
## (where DesertLandforms puts them).
func _add_landforms_on_ball(data: Dictionary, clear: Rect2) -> void:
	var sp := sphere()
	var planet_mesas: Array = data.get("planet_mesas", [])
	var use_planet_mesas := not planet_mesas.is_empty()
	if not use_planet_mesas:
		planet_mesas = data.get("mesas", [])
	for m in planet_mesas:
		var map := sp.map_from_lat_lon(float(m[0]), float(m[1])) if use_planet_mesas \
			else Vector2(float(m[0]), float(m[1]))
		if not clear.grow(float(m[2])).has_point(map):
			var base := sp.surface_at(map.x, map.y)
			var h := float(m[3]) * 0.92 - DesertLandforms.MESA_BURY
			columns.append({ "id": "mesa_%d_%d" % [int(m[0]), int(m[1])], "kind": "mesa", "center": base,
				"radius": float(m[2]) * 0.9, "up": sp.up_at(base), "h": h, "top": base.y + h })
	for hd in data.get("hoodoos", []):
		if not clear.grow(float(hd[2])).has_point(Vector2(hd[0], hd[1])):
			var base := sp.surface_at(hd[0], hd[1])
			var h := float(hd[3]) * 0.95 + float(hd[2]) * 0.4
			columns.append({ "id": "hoodoo_%d_%d" % [int(hd[0]), int(hd[1])], "kind": "hoodoo", "center": base,
				"radius": float(hd[2]) * 0.9, "up": sp.up_at(base), "h": h, "top": base.y + h })


## Somewhere a ship may set down: inside the desert (beyond it there is sand to
## see but nothing to walk on).
func landable(x: float, z: float) -> bool:
	if terrain == null or terrain.in_desert(x, z):
		return true
	# Issue #45: a platform town (no desert): only on its own floors and roofs.
	for b in boxes:
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if x >= mn.x and x <= mx.x and z >= mn.z and z <= mx.z and str(b.kind) in ["floor", "roof", "ship"]:
			return true
	return false


## The world's atmosphere settings (where space starts, etc.).
func atmosphere() -> Dictionary:
	return world.get("atmosphere", {})


func space_altitude() -> float:
	return float(atmosphere().get("space_altitude", 8000.0))


func altitude(p: Vector3) -> float:
	return terrain.altitude(p) if terrain != null else p.y


## Distance down a gravity ray to a wreck plate. A steeply leaning deck must be
## measured along the planet's up, not the plate's local Y. The slab intersection
## also handles the slanted shell facets, without inventing a lid over the breach.
static func box_height_below(b: Dictionary, p: Vector3, up: Vector3) -> float:
	var inv := box_xf(b).affine_inverse()
	var local := inv * p
	var dir := inv.basis * up
	var enter := -INF
	var leave := INF
	var mn: Vector3 = b.min
	var mx: Vector3 = b.max
	for axis in 3:
		if absf(dir[axis]) < 0.000001:
			if local[axis] < mn[axis] or local[axis] > mx[axis]:
				return INF
			continue
		var a := (local[axis] - mx[axis]) / dir[axis]
		var z := (local[axis] - mn[axis]) / dir[axis]
		enter = maxf(enter, minf(a, z))
		leave = minf(leave, maxf(a, z))
		if leave < enter:
			return INF
	return enter if enter >= -0.5 else INF


## Top of a box at (x, z) (ramps slope along their rise axis).
static func box_top(b: Dictionary, x: float, z: float) -> float:
	var mn: Vector3 = b.min
	var mx: Vector3 = b.max
	match str(b.get("rise", "")):
		"+x":
			return lerpf(mn.y, mx.y, clampf((x - mn.x) / maxf(mx.x - mn.x, 0.001), 0.0, 1.0))
		"-x":
			return lerpf(mx.y, mn.y, clampf((x - mn.x) / maxf(mx.x - mn.x, 0.001), 0.0, 1.0))
		"+z":
			return lerpf(mn.y, mx.y, clampf((z - mn.z) / maxf(mx.z - mn.z, 0.001), 0.0, 1.0))
		"-z":
			return lerpf(mx.y, mn.y, clampf((z - mn.z) / maxf(mx.z - mn.z, 0.001), 0.0, 1.0))
	return mx.y


## The highest surface under (x, z) whose top is at or below `below` (+0.5 m of
## step-up). Terrain, box tops and column tops all count.
func ground_at(x: float, z: float, below: float = INF) -> float:
	var g := terrain.height_at(x, z) if terrain != null else 0.0
	var limit := below + 0.5
	for b in boxes:
		if b.has("wreck_finish"):
			var ray_y := below
			if not is_finite(ray_y):
				var xf := box_xf(b)
				var half: Vector3 = ((b.max as Vector3) - (b.min as Vector3)) * 0.5
				ray_y = (xf * ((b.min as Vector3) + half)).y + absf(xf.basis.x.y) * half.x \
					+ absf(xf.basis.y.y) * half.y + absf(xf.basis.z.y) * half.z + 1.0
			g = maxf(g, ray_y - box_height_below(b, Vector3(x, ray_y, z), Vector3.UP))
			continue
		if b.has("xf"):
			continue            # leans with the ball: height_above() asks it
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if x < mn.x or x > mx.x or z < mn.z or z > mx.z:
			continue
		var top := box_top(b, x, z)
		if top <= limit and top > g:
			g = top
	for bd in boulders:
		var bc: Vector3 = bd.center
		if (bd.up as Vector3) != Vector3.UP or absf(x - bc.x) > float(bd.radius) * RAMP_SPREAD \
				or absf(z - bc.z) > float(bd.radius) * RAMP_SPREAD:
			continue
		var bt := bc.y + boulder_top(bd, Vector2(x - bc.x, z - bc.z).length())
		if bt <= limit and bt > g:
			g = bt
	for c in columns:
		if c.has("up"):
			continue
		var cc: Vector3 = c.center
		if Vector2(x - cc.x, z - cc.z).length() <= float(c.radius):
			var top: float = c.top
			if top <= limit and top > g:
				g = top
	return g


## The first box or column a sphere touches, or "" when clear. Floors and ramps are
## ground, not obstacles (ground_at handles them), and so are surfaces the sphere's
## bottom is resting on from above.
func hit(p: Vector3, r: float) -> String:
	for b in boxes:
		if FLOOR_KINDS.has(b.kind) or str(b.get("rise", "")) != "":
			continue
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var lp := p
		if b.has("xf"):
			# Issue #193: a box in its own frame keeps its bounding sphere and inverse
			# (made on first use), so the hundreds on the wreck and the cruiser cost a
			# distance each when the ship is nowhere near them.
			if not b.has("hit_inv"):
				var xf := box_xf(b)
				b["hit_c"] = xf * ((mn + mx) * 0.5)
				b["hit_r"] = ((mx - mn) * 0.5).length()
				b["hit_inv"] = xf.affine_inverse()
			var rr: float = float(b.hit_r) + r
			if p.distance_squared_to(b.hit_c) > rr * rr:
				continue
			lp = (b.hit_inv as Transform3D) * p
		if lp.y - r * 0.5 >= mx.y:
			continue            # above it: that is landing, not hitting
		var q := Vector3(clampf(lp.x, mn.x, mx.x), clampf(lp.y, mn.y, mx.y), clampf(lp.z, mn.z, mx.z))
		if q.distance_squared_to(lp) <= r * r:
			return str(b.id)
	for bd in boulders:
		if float(bd.height) <= RAMP_MAX:
			continue                # low: a ramp, ridden over, not hit
		var bu: Vector3 = bd.up
		var rel: Vector3 = p - (bd.center as Vector3)
		var along := rel.dot(bu)
		if along - r * 0.5 >= float(bd.height) * 0.85 or along + r < 0.0:
			continue
		if (rel - bu * along).length() <= float(bd.radius) * 0.8 + r:
			return "boulder"
	for c in columns:
		var cc: Vector3 = c.center
		if c.has("up"):
			var up: Vector3 = c.up
			var rel := p - cc
			var along := rel.dot(up)
			if along - r * 0.5 >= float(c.h) or along + r < 0.0:
				continue
			if (rel - up * along).length() <= float(c.radius) + r:
				return str(c.id)
			continue
		if p.y - r * 0.5 >= float(c.top) or p.y + r < cc.y:
			continue
		if Vector2(p.x - cc.x, p.z - cc.z).length() <= float(c.radius) + r:
			return str(c.id)
	return ""


static func _v3(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
