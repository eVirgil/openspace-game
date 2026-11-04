class_name OutpostRoom
extends RefCounted
## Issue #309: an outpost's control room. A building with a "room" block in its
## location file is not one solid box but walls, a roof and a doorway in its +x
## face (the side toward the town), on the same footprint; inside are rows of
## consoles, a holo table and screens like the star cruiser's bridge
## (CruiserHull._bridge), and one console that can be hacked (Heist).
##
## Pure geometry in the outpost's local frame (x toward the door, y up; a
## building's "position" is the middle of its floor). WorldGround makes the shell
## the solid boxes ships and speeders hit (and WorldScenery their colliders);
## RemnantOutposts builds the inside's colliders, nav and look from inside().
##
## "room" keys (all optional): wall (thickness), door (width), door_h (height),
## rows (1, or 2 for a second bank of consoles across the room).

const WALL := 0.3
const DOOR := 2.0
const DOOR_H := 2.5
const BACK_DEPTH := 0.9       ## the console row along the back wall, front to back
const SIDE_DEPTH := 0.75      ## the rows along the side walls
const STAND := 0.55           ## how far in front of the hack console you stand


static func is_room(b: Dictionary) -> bool:
	return b.get("room", null) is Dictionary


static func _r(b: Dictionary, key: String, fallback: float) -> float:
	return float((b.get("room", {}) as Dictionary).get(key, fallback))


## The solid boxes building `b` is made of: `b` itself, or a room's walls and
## roof. Each is a building entry ({ id, shape, size, position, visual }) plus
## "nav": false for the pieces overhead (the lintel and the roof), which must
## not cut the floor out of the navmesh.
static func shell(b: Dictionary) -> Array:
	if not is_room(b):
		return [b]
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	var p := WorldGround._v3(b.get("position", [0, 0, 0]))
	var w := _r(b, "wall", WALL)
	var door := _r(b, "door", DOOR)
	var dh := minf(_r(b, "door_h", DOOR_H), s.y - w - 0.2)
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var id := str(b.get("id", "block"))
	var jamb := (s.z - 2.0 * w - door) * 0.5            # front wall either side of the door
	var jz := hz - w - jamb * 0.5
	return [
		_piece(b, id + "_back", Vector3(w, s.y, s.z - 2.0 * w), p + Vector3(-hx + w * 0.5, 0, 0)),
		_piece(b, id + "_left", Vector3(s.x, s.y, w), p + Vector3(0, 0, -hz + w * 0.5)),
		_piece(b, id + "_right", Vector3(s.x, s.y, w), p + Vector3(0, 0, hz - w * 0.5)),
		_piece(b, id + "_front_l", Vector3(w, s.y, jamb), p + Vector3(hx - w * 0.5, 0, -jz)),
		_piece(b, id + "_front_r", Vector3(w, s.y, jamb), p + Vector3(hx - w * 0.5, 0, jz)),
		_piece(b, id + "_lintel", Vector3(w, s.y - dh, door), p + Vector3(hx - w * 0.5, dh, 0), false),
		_piece(b, id + "_roof", Vector3(s.x - 2.0 * w, w, s.z - 2.0 * w), p + Vector3(0, s.y - w, 0), false),
	]


static func _piece(b: Dictionary, id: String, size: Vector3, bottom_mid: Vector3, nav := true) -> Dictionary:
	return { "id": id, "shape": "box", "size": [size.x, size.y, size.z],
		"position": [bottom_mid.x, bottom_mid.y, bottom_mid.z], "visual": bool(b.get("visual", true)), "nav": nav }


## The room's inside, its floor at local y = 0: [{ id, size, center, finish,
## solid, basis? }]. Finishes are CruiserHull's ("console", "screen", "bridge",
## "wall", "glow"); solid parts are colliders, nav obstructions and cover. The
## console tagged "hack" is the one Heist opens.
static func inside(b: Dictionary) -> Array:
	var out: Array = []
	if not is_room(b):
		return out
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	var p := WorldGround._v3(b.get("position", [0, 0, 0]))
	var w := _r(b, "wall", WALL)
	var ix0 := -s.x * 0.5 + w                 # the inside face of the back wall
	var ix1 := s.x * 0.5 - w                  # ... of the front wall
	var iz := s.z * 0.5 - w                   # ... of the side walls
	var top := s.y - w                        # the ceiling
	var bx := ix0 + BACK_DEPTH * 0.5
	# The back row: the hack console in the middle, a casing either side.
	_add(out, "hack", Vector3(BACK_DEPTH, 1.2, 1.4), p + Vector3(bx, 0.6, 0), "console", true)
	out[-1]["hack"] = true
	_add(out, "hack_screen", Vector3(0.06, 0.8, 1.3), p + Vector3(ix0 + 0.04, 1.85, 0), "screen")
	var seg := iz - 0.85
	for side: float in [-1.0, 1.0]:
		var tag := "l" if side < 0.0 else "r"
		var zc := side * (0.75 + seg * 0.5)
		if seg > 0.4:
			_add(out, "back_%s" % tag, Vector3(BACK_DEPTH, 1.05, seg), p + Vector3(bx, 0.525, zc), "console", true)
			_add(out, "back_%s_screen" % tag, Vector3(0.06, 0.7, seg - 0.3), p + Vector3(ix0 + 0.04, 1.75, zc), "screen")
		# A row along each side wall, short of the back row and the front corners.
		var x0 := ix0 + BACK_DEPTH + 0.2
		var x1 := ix1 - 0.6
		if x1 - x0 > 1.0:
			var sz := side * (iz - SIDE_DEPTH * 0.5)
			_add(out, "side_%s" % tag, Vector3(x1 - x0, 1.0, SIDE_DEPTH), p + Vector3((x0 + x1) * 0.5, 0.5, sz), "console", true)
			var n := maxi(1, int((x1 - x0) / 1.8))
			for k in n:
				var x := x0 + (x1 - x0) * (float(k) + 0.5) / float(n)
				_add(out, "side_%s_screen_%d" % [tag, k], Vector3(1.4, 0.75, 0.06), p + Vector3(x, 1.65, side * (iz - 0.04)), "screen")
	# Rows = 2: a second bank across the room, open in the middle to walk through.
	if int(_r(b, "rows", 1.0)) >= 2:
		var rx := ix0 + 2.7
		var span := iz - 1.0 - 0.9
		if span > 0.6:
			for side: float in [-1.0, 1.0]:
				var tag := "l" if side < 0.0 else "r"
				var zc := side * (0.9 + span * 0.5)
				_add(out, "bank_%s" % tag, Vector3(SIDE_DEPTH, 1.0, span), p + Vector3(rx, 0.5, zc), "console", true)
				_add(out, "bank_%s_screen" % tag, Vector3(0.06, 0.6, span - 0.2), p + Vector3(rx + SIDE_DEPTH * 0.5 + 0.03, 1.15, zc),
					"screen", false, Basis(Vector3.BACK, deg_to_rad(20.0)))
	# The holo table between the door and the consoles, and its map on top.
	var hx := holo(b).x
	_add(out, "holo_table", Vector3(1.3, 0.95, 1.3), p + Vector3(hx, 0.475, 0), "console", true)
	_add(out, "holo_top", Vector3(1.15, 0.06, 1.15), p + Vector3(hx, 0.98, 0), "screen")
	# The floor's lines and the ceiling's light bars (drawn only).
	_add(out, "floor", Vector3(ix1 - ix0, 0.1, iz * 2.0), p + Vector3((ix0 + ix1) * 0.5, -0.05, 0), "bridge")
	for k in 2:
		var lx := ix0 + (ix1 - ix0) * (0.3 + 0.4 * k)
		_add(out, "light_%d" % k, Vector3(0.5, 0.08, iz * 1.6), p + Vector3(lx, top - 0.05, 0), "glow")
	# Bulkhead panels lining the walls inside.
	_add(out, "lining_back", Vector3(0.04, top, iz * 2.0), p + Vector3(ix0 + 0.02, top * 0.5, 0), "wall")
	for side: float in [-1.0, 1.0]:
		_add(out, "lining_%s" % ("l" if side < 0.0 else "r"), Vector3(ix1 - ix0, top, 0.04),
			p + Vector3((ix0 + ix1) * 0.5, top * 0.5, side * (iz - 0.02)), "wall")
	return out


static func _add(out: Array, id: String, size: Vector3, center: Vector3, finish: String, solid := false,
		basis := Basis.IDENTITY) -> void:
	out.append({ "id": id, "size": size, "center": center, "finish": finish, "solid": solid, "basis": basis })


## The middle of the holo table's foot (local).
static func holo(b: Dictionary) -> Vector3:
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	var p := WorldGround._v3(b.get("position", [0, 0, 0]))
	var w := _r(b, "wall", WALL)
	var ix0 := -s.x * 0.5 + w + BACK_DEPTH
	var ix1 := s.x * 0.5 - w
	return p + Vector3((ix0 + ix1) * 0.5 + 0.3, 0, 0)


## Where you stand to hack the console (local, on the floor).
static func stand(b: Dictionary) -> Vector3:
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	var p := WorldGround._v3(b.get("position", [0, 0, 0]))
	return p + Vector3(-s.x * 0.5 + _r(b, "wall", WALL) + BACK_DEPTH + STAND, 0, 0)


## Inside the walls (local, any height under the roof)?
static func contains(b: Dictionary, local: Vector3) -> bool:
	if not is_room(b):
		return false
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	var d := local - WorldGround._v3(b.get("position", [0, 0, 0]))
	var w := _r(b, "wall", WALL)
	return absf(d.x) < s.x * 0.5 - w and absf(d.z) < s.z * 0.5 - w


## The doorway's middle at floor level (local).
static func doorway(b: Dictionary) -> Vector3:
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	return WorldGround._v3(b.get("position", [0, 0, 0])) + Vector3(s.x * 0.5, 0, 0)


static func door_width(b: Dictionary) -> float:
	return _r(b, "door", DOOR)


static func wall(b: Dictionary) -> float:
	return _r(b, "wall", WALL)


static func door_height(b: Dictionary) -> float:
	var s := WorldGround._v3(b.get("size", [1, 1, 1]))
	return minf(_r(b, "door_h", DOOR_H), s.y - _r(b, "wall", WALL) - 0.2)
