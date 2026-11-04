extends RefCounted
## Town layout (M9). Reads port_town from the data layer and validates it. Issue
## #237: the town is built to a saved layout (content/core/towns/: port_square).
## Pure: no nodes. The scene builder (town_demo.gd) and the walk trace use it.
## The validator mirrors docs/town/validate_town.py rule for rule (V1 to V9).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")

var data: Dictionary = {}


## `layout` (issue #237): build the town to that saved layout (content/core/towns/)
## instead of the one its planet picks, e.g. load_town("port_town", "port_square").
func load_town(town_id: String = "port_town", layout: String = "") -> bool:
	var cc := CoreContent.new()
	if not cc.load_from():
		return false
	data = cc.town_from_layout(layout, town_id) if layout != "" else cc.get_location(town_id)
	BarracksHall.stamp(data)
	return not data.is_empty()


## Issue #321: a barracks hall with an interior is stamped with its pieces here
## (in place; a stamped town is left as it is).
func load_from_dict(d: Dictionary) -> void:
	data = d
	BarracksHall.stamp(data)


func boxes() -> Array:
	return data.get("boxes", [])


func markers() -> Array:
	return data.get("markers", [])


func routes() -> Array:
	return data.get("routes", [])


func zones() -> Array:
	return data.get("zones", [])


func get_box(id: String) -> Dictionary:
	return _find(boxes(), id)


func get_marker(id: String) -> Dictionary:
	return _find(markers(), id)


func get_route(id: String) -> Dictionary:
	return _find(routes(), id)


func _find(list: Array, id: String) -> Dictionary:
	for item in list:
		if str(item.get("id", "")) == id:
			return item
	return {}


func marker_pos(id: String) -> Vector3:
	var p = get_marker(id).get("pos", [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func spawn_pos() -> Vector3:
	var list := markers_with_role("spawn")
	return marker_pos(str(list[0].id)) if list.size() > 0 else Vector3.ZERO


func markers_with_role(role: String) -> Array:
	var out: Array = []
	for m in markers():
		if str(m.get("role", "")) == role:
			out.append(m)
	return out


func route_points_3d(route_id: String) -> Array:
	var out: Array = []
	for p in get_route(route_id).get("points", []):
		out.append(Vector3(float(p[0]), 0.0, float(p[1])))
	return out


func route_length(route_id: String) -> float:
	var pts := route_points_3d(route_id)
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i - 1] as Vector3).distance_to(pts[i])
	return total


## Every rule broken, as "Vn ..." strings. Empty means the town is valid.
func validate() -> Array:
	var errs: Array = []
	var clearance := float(data.get("player_clearance", 0.6))
	var blocking: Array = data.get("blocking_kinds", [])
	var zone_by_id := {}
	for z in zones():
		zone_by_id[str(z.id)] = z

	# V1 unique ids
	var seen := {}
	for item in boxes() + markers():
		var id := str(item.get("id", ""))
		if seen.has(id):
			errs.append("V1 duplicate id: " + id)
		seen[id] = true

	for b in boxes():
		var mn := _v3(b.min)
		var mx := _v3(b.max)
		# V2 min < max
		if not (mn.x < mx.x and mn.y < mx.y and mn.z < mx.z):
			errs.append("V2 bad min/max: " + str(b.id))
		# V3 overhead height
		if str(b.kind) == "overhead" and mn.y < 2.2:
			errs.append("V3 overhead too low: " + str(b.id))
		# V4 inside zone
		var zid := str(b.get("zone", ""))
		if zid != "ground" and zid != "perimeter":
			if not zone_by_id.has(zid):
				errs.append("V4 unknown zone: " + str(b.id))
			else:
				var z: Dictionary = zone_by_id[zid]
				var inside := mn.x >= float(z.min[0]) and mx.x <= float(z.max[0]) \
					and mn.z >= float(z.min[1]) and mx.z <= float(z.max[1])
				if not inside:
					errs.append("V4 outside zone: " + str(b.id))

	# V5 no 3D overlap (strict, so touching is fine). A "hollow" box (the round
	# pit) is a shell other boxes sit inside, so it is left out. Issue #237: a round
	# box (shape "round", a stair tower, a lookout) is its circle, not its square.
	var bs := boxes()
	for i in bs.size():
		for j in range(i + 1, bs.size()):
			if bs[i].get("hollow", false) or bs[j].get("hollow", false):
				continue
			if _aabb_overlap(bs[i], bs[j]):
				errs.append("V5 overlap: %s / %s" % [bs[i].id, bs[j].id])

	# V6 marker not blocked, V7 marker supported (a floor or solid top, or any box
	# marked "standable", like the cantina stage the station's dancer is on)
	for m in markers():
		var p := _v3(m.pos)
		var supported := false
		for b in bs:
			var mn := _v3(b.min)
			var mx := _v3(b.max)
			if str(b.kind) in blocking and mn.y <= p.y and p.y < mx.y:
				if _point_rect_dist(p.x, p.z, b) <= clearance:
					errs.append("V6 marker blocked: %s by %s" % [m.id, b.id])
			var standable: bool = str(b.kind) == "floor" or str(b.kind) == "solid" or bool(b.get("standable", false))
			if standable and absf(mx.y - p.y) < 0.05 \
					and p.x >= mn.x and p.x <= mx.x and p.z >= mn.z and p.z <= mx.z:
				supported = true
		if not supported:
			errs.append("V7 marker unsupported: " + str(m.id))

	# V8 routes clear of blocking boxes (issue #321: on the ground; a box 2.2 m or
	# more up, on a roof, is over the walker's head)
	for r in routes():
		var pts: Array = r.points
		for k in range(1, pts.size()):
			for b in bs:
				if str(b.kind) in blocking and float(b.min[1]) < 2.2:
					if _segment_rect_dist(pts[k - 1], pts[k], b) <= clearance:
						errs.append("V8 route %s segment %d hits %s" % [r.id, k, b.id])

	# V9 (issue #237) a round wall (kind "ring") blocks like a wall, piece by
	# piece, and is open only at its gaps: no marker within clearance of a piece
	# (at a height the wall stands at), no route segment either.
	for b in bs:
		if str(b.kind) != "ring":
			continue
		var t := RingWall.info(b)
		var ps := RingWall.pieces(b)
		for m in markers():
			var p := _v3(m.pos)
			if float(t.y0) <= p.y and p.y < float(t.y1) and RingWall.distance(b, p.x, p.z, ps, t) <= clearance:
				errs.append("V9 marker blocked: %s by %s" % [m.id, b.id])
		for r in routes():
			var pts: Array = r.points
			for k in range(1, pts.size()):
				var a := Vector2(float(pts[k - 1][0]), float(pts[k - 1][1]))
				var c := Vector2(float(pts[k][0]), float(pts[k][1]))
				var n := maxi(2, int(a.distance_to(c) / 0.1))
				for s in n + 1:
					var q := a.lerp(c, float(s) / float(n))
					if RingWall.distance(b, q.x, q.y, ps, t) <= clearance:
						errs.append("V9 route %s segment %d hits %s" % [r.id, k, b.id])
						break
	return errs


func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _aabb_overlap(a, b) -> bool:
	for k in 3:
		if not (float(a.min[k]) < float(b.max[k]) and float(b.min[k]) < float(a.max[k])):
			return false
	var ra := _is_round(a)
	var rb := _is_round(b)
	if not ra and not rb:
		return true
	var ca := Vector2((float(a.min[0]) + float(a.max[0])) * 0.5, (float(a.min[2]) + float(a.max[2])) * 0.5)
	var cb := Vector2((float(b.min[0]) + float(b.max[0])) * 0.5, (float(b.min[2]) + float(b.max[2])) * 0.5)
	if ra and rb:
		return ca.distance_to(cb) < _round_r(a) + _round_r(b) - 0.001
	var c := ca if ra else cb
	var r := _round_r(a) if ra else _round_r(b)
	return _point_rect_dist(c.x, c.y, b if ra else a) < r - 0.001


## Upright cylinders in their box: radius half the box's narrower side.
static func _is_round(b) -> bool:
	return str(b.get("shape", "")) == "round" or str(b.kind) in ["spiral", "lookout"]


static func _round_r(b) -> float:
	return minf(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2])) * 0.5


## 2D distance from point (x, z) to a box footprint. 0 if inside.
func _point_rect_dist(x: float, z: float, b) -> float:
	var dx := maxf(maxf(float(b.min[0]) - x, 0.0), x - float(b.max[0]))
	var dz := maxf(maxf(float(b.min[2]) - z, 0.0), z - float(b.max[2]))
	return sqrt(dx * dx + dz * dz)


## 2D distance from segment p->q (each [x, z]) to a box footprint.
## Sampled every 0.1 m, the same method as the Python reference.
func _segment_rect_dist(p, q, b) -> float:
	var a := Vector2(float(p[0]), float(p[1]))
	var c := Vector2(float(q[0]), float(q[1]))
	var n := maxi(2, int(a.distance_to(c) / 0.1))
	var best := INF
	for s in n + 1:
		var t := float(s) / float(n)
		var pt := a.lerp(c, t)
		best = minf(best, _point_rect_dist(pt.x, pt.y, b))
	return best


## A ramp box is the space the ramp fills. Returns the center, size and basis of a
## slab whose TOP face runs from the low edge to the high edge along rise_toward.
static func ramp_transform(box: Dictionary, thickness: float = 0.4) -> Dictionary:
	var mn := Vector3(float(box.min[0]), float(box.min[1]), float(box.min[2]))
	var mx := Vector3(float(box.max[0]), float(box.max[1]), float(box.max[2]))
	var rise := mx.y - mn.y
	var dir: String = str(box.get("rise_toward", "+x"))
	var along_x := dir == "+x" or dir == "-x"
	var run := (mx.x - mn.x) if along_x else (mx.z - mn.z)
	var width := (mx.z - mn.z) if along_x else (mx.x - mn.x)
	var slope_len := sqrt(run * run + rise * rise)
	var angle := atan2(rise, run)

	var basis := Basis.IDENTITY
	var size := Vector3.ZERO
	if along_x:
		# Rotating about Z by +angle lifts the +X end. "-x" lifts the -X end.
		var signed := angle if dir == "+x" else -angle
		basis = Basis(Vector3(0, 0, 1), signed)
		size = Vector3(slope_len, thickness, width)
	else:
		# Rotating about X by -angle lifts the +Z end. "-z" lifts the -Z end.
		var signed := -angle if dir == "+z" else angle
		basis = Basis(Vector3(1, 0, 0), signed)
		size = Vector3(width, thickness, slope_len)

	# Middle of the top surface is the middle of the box. Push the slab down by half
	# its thickness along its own up axis, so its TOP face is the walking surface.
	var top_mid := (mn + mx) * 0.5
	var center := top_mid - basis.y * (thickness * 0.5)
	return { "center": center, "size": size, "basis": basis, "angle": angle }
