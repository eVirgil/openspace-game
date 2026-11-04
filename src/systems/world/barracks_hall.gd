class_name BarracksHall
extends RefCounted
## Issue #321: a barracks hall you can walk into. A town box with
## "interior": "barracks" (the square port, the round port and every generated
## town with a barracks) is stamped, when its town loads, with one template
## (content/core/towns/barracks_interior.json): the box becomes kind "shell" (no
## collision; the building kit still draws its outside, TownBuildings._look_hall)
## and the town gains its pieces as ordinary boxes:
##   - walls, a roof (standable: the roof riflemen) and a doorway in its door face,
##   - a vestibule from the door to a corridor along the length of the hall,
##   - behind the corridor, straight in from the door: the office, the Remnant
##     cruiser's control room (OutpostRoom's consoles, screens and holo table) with
##     the story rifle hidden in its middle console,
##   - in front of the corridor beside the way in: the bunk room (two-high bunks,
##     footlockers, lockers),
##   - the rest: rooms that never open, solid, with locked doors on their faces.
## And markers and routes: the rifle's spot and the Remnant troopers walking a loop
## from the corridor into the office. Because the pieces are plain town boxes,
## the collision, WorldGround, the navmesh, the validator and the garrison's cover
## all see them with no code of their own.
##
## Pure: no nodes. Geometry is worked out in the hall's own frame (x from the back
## wall toward the door face, z along the door face, y up from its foot) and turned
## into the town's frame by the hall's "face" (a quarter turn, so boxes stay boxes).
## BarracksLook draws the inside from inside() and doors().

const PATH := "res://content/core/towns/barracks_interior.json"
const KIND := "barracks"
const YAW := { "+x": 0.0, "-x": PI, "+z": -PI * 0.5, "-z": PI * 0.5 }

static var _spec: Dictionary = {}


static func spec() -> Dictionary:
	if _spec.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_spec = d
	return _spec


static func n(key: String, fallback: float) -> float:
	return float(spec().get(key, fallback))


static func is_hall(b: Dictionary) -> bool:
	return str(b.get("interior", "")) == KIND


## Every hall in a town's box list.
static func halls(boxes: Array) -> Array:
	return boxes.filter(func(b): return is_hall(b))


# ------------------------------------------------------------------ stamping

## Stamp every hall in `town` (a town's data: boxes, markers, routes) with the
## template, in place. Twice is the same as once (a stamped hall is a "shell").
static func stamp(town: Dictionary) -> void:
	if town.is_empty():
		return
	var boxes: Array = town.get("boxes", [])
	var markers: Array = town.get("markers", [])
	var routes: Array = town.get("routes", [])
	for b in boxes.duplicate():
		if not is_hall(b) or str(b.get("kind", "")) == "shell":
			continue
		b["kind"] = "shell"
		b["hollow"] = true                  # its pieces sit inside it (TownLayout V5)
		boxes.append_array(pieces(b))
		markers.append_array(hall_markers(b))
		routes.append_array(hall_routes(b))
	town["boxes"] = boxes
	town["markers"] = markers
	town["routes"] = routes


# ------------------------------------------------------------------ the frame

## The hall's frame: local +x is its door face's outward direction, +z along it,
## the origin the middle of its foot.
static func frame(b: Dictionary) -> Transform3D:
	var mn := _v3(b.min)
	var mx := _v3(b.max)
	var yaw := float(YAW.get(str(b.get("face", "+x")), 0.0))
	return Transform3D(Basis(Vector3.UP, yaw), Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5))


## { d: depth (back wall to door face), l: length (along the door face), h }.
static func dims(b: Dictionary) -> Dictionary:
	var size := _v3(b.max) - _v3(b.min)
	var along_x := str(b.get("face", "+x")).ends_with("x")
	return { "d": size.x if along_x else size.z, "l": size.z if along_x else size.x, "h": size.y }


## Where along the door face the way in is: the door bay of the building kit's
## hall (TownBuildings._look_hall: a door in every other bay of about 5 m)
## nearest the middle.
static func door_z(length: float) -> float:
	var bays := maxi(1, int(length / 5.0))
	var bay := length / bays
	var best := INF
	for i in range(1, bays, 2):
		var z := -length * 0.5 + (i + 0.5) * bay
		if absf(z) < absf(best) - 0.001:
			best = z
	return 0.0 if best == INF else best


## The opening in the door frame (TownBuildings.door at scale s): { w, h }.
static func gap(s: float) -> Vector2:
	return Vector2(2.0 * (0.75 * s - 0.18 * s), 1.6 * s)


## Every number of the hall's layout, in its own frame.
static func layout(b: Dictionary) -> Dictionary:
	var dm := dims(b)
	var d: float = dm.d
	var l: float = dm.l
	var h: float = dm.h
	var w := n("wall", 0.3)
	var pw := n("partition", 0.25)
	var ix0 := -d * 0.5 + w
	var ix1 := d * 0.5 - w
	var iz := l * 0.5 - w
	var dz := door_z(l)
	var cor := n("corridor", 3.0)
	var band := (ix1 - ix0) - cor - 2.0 * pw
	var front := band * n("front_share", 0.45)
	var back := band - front
	var o := {
		"d": d, "l": l, "h": h, "w": w, "pw": pw, "ix0": ix0, "ix1": ix1, "iz": iz, "top": h - w,
		"dz": dz, "gap": gap(n("door_scale", 1.6)), "igap": gap(n("inner_door_scale", 1.4)),
		"front": front, "back": back,
		"p1": Vector2(ix1 - front - pw, ix1 - front),        # the wall between the corridor and the front rooms
		"p2": Vector2(ix0 + back, ix0 + back + pw),          # ... and the back rooms
	}
	o["cx"] = ((o.p2 as Vector2).y + (o.p1 as Vector2).x) * 0.5   # the corridor's middle
	var vh := n("vestibule", 3.0) * 0.5
	o["vest"] = Vector2(clampf(dz - vh, -iz + pw + 1.0, iz - pw - 1.0), clampf(dz + vh, -iz + pw + 1.0, iz - pw - 1.0))
	# The office: behind the corridor, centred on the way in where it fits.
	var ol := minf(float(spec().get("office", {}).get("length", 16.0)), 2.0 * iz)
	var oz0 := clampf(dz - ol * 0.5, -iz, iz - ol)
	o["office"] = Vector2(oz0, oz0 + ol)
	# The bunk room: in front of the corridor, on the longer side of the way in.
	var v: Vector2 = o.vest
	var left := (v.x - pw) - (-iz)
	var right := iz - (v.y + pw)
	var side := -1.0 if left >= right else 1.0
	var near := v.x - pw if side < 0.0 else v.y + pw
	var room := minf(maxf(left, right), float(spec().get("bunks", {}).get("length", 14.0)))
	o["bunk_side"] = side
	o["bunks"] = Vector2(minf(near, near + side * room), maxf(near, near + side * room))
	o["bunk_near"] = near
	o["bunk_far"] = near + side * room
	return o


# ------------------------------------------------------------------ the pieces

## The hall's pieces as town boxes (the town's frame), in the hall's zone. Walls
## and the rooms that never open are "wall" (blocking; "under_roof": the navmesh
## keeps the roof walkable over them), the roof and the lintels "overhead" (the
## roof "standable"), consoles, bunks and lockers "cover". Every one carries
## "part_of": the hall's id (BarracksLook draws them, TownDecor hides their greybox).
static func pieces(b: Dictionary) -> Array:
	var out: Array = []
	var o := layout(b)
	var d: float = o.d
	var l: float = o.l
	var w: float = o.w
	var pw: float = o.pw
	var top: float = o.top
	var ix0: float = o.ix0
	var ix1: float = o.ix1
	var iz: float = o.iz
	var dz: float = o.dz
	var g: Vector2 = o.gap
	var ig: Vector2 = o.igap
	var p1: Vector2 = o.p1
	var p2: Vector2 = o.p2
	var v: Vector2 = o.vest
	var off: Vector2 = o.office
	var bk: Vector2 = o.bunks
	var wall := func(id: String, x0: float, x1: float, z0: float, z1: float, y0 := 0.0, y1 := top, kind := "wall") -> void:
		if x1 - x0 > 0.02 and z1 - z0 > 0.02 and y1 - y0 > 0.02:
			out.append(_box(b, id, Vector3(x0, y0, z0), Vector3(x1, y1, z1), kind))
	# The shell: back, ends, the door face round the way in, the roof over all.
	wall.call("back", -d * 0.5, ix0, -l * 0.5, l * 0.5)
	wall.call("end_l", ix0, ix1, -l * 0.5, -iz)
	wall.call("end_r", ix0, ix1, iz, l * 0.5)
	wall.call("front_l", ix1, d * 0.5, -l * 0.5, dz - g.x * 0.5)
	wall.call("front_r", ix1, d * 0.5, dz + g.x * 0.5, l * 0.5)
	wall.call("door_lintel", ix1, d * 0.5, dz - g.x * 0.5, dz + g.x * 0.5, g.y, top, "overhead")
	wall.call("roof", -d * 0.5, d * 0.5, -l * 0.5, l * 0.5, top, o.h, "overhead")
	out[-1]["standable"] = true
	out[-1]["roof_of"] = str(b.id)
	# The way in: two walls from the door face back to the corridor.
	wall.call("vest_l", p1.x, ix1, v.x - pw, v.x)
	wall.call("vest_r", p1.x, ix1, v.y, v.y + pw)
	# The bunk room's corridor wall, with its doorway; the locked rooms either side.
	var bd := (bk.x + bk.y) * 0.5
	wall.call("bunk_wall_a", p1.x, p1.y, bk.x, bd - ig.x * 0.5)
	wall.call("bunk_wall_b", p1.x, p1.y, bd + ig.x * 0.5, bk.y)
	wall.call("bunk_lintel", p1.x, p1.y, bd - ig.x * 0.5, bd + ig.x * 0.5, ig.y, top, "overhead")
	if float(o.bunk_side) < 0.0:
		wall.call("front_block_far", p1.x, ix1, -iz, bk.x)
		wall.call("front_block", p1.x, ix1, v.y + pw, iz)
	else:
		wall.call("front_block_far", p1.x, ix1, bk.y, iz)
		wall.call("front_block", p1.x, ix1, -iz, v.x - pw)
	# The office's corridor wall, with its doorway; the locked rooms either side.
	var od := (off.x + off.y) * 0.5
	wall.call("office_wall_a", p2.x, p2.y, off.x, od - ig.x * 0.5)
	wall.call("office_wall_b", p2.x, p2.y, od + ig.x * 0.5, off.y)
	wall.call("office_lintel", p2.x, p2.y, od - ig.x * 0.5, od + ig.x * 0.5, ig.y, top, "overhead")
	wall.call("back_block_l", ix0, p2.y, -iz, off.x)
	wall.call("back_block_r", ix0, p2.y, off.y, iz)
	# The office's consoles and holo table (the cruiser's control room).
	for part in OutpostRoom.inside(office_room(b)):
		if bool(part.solid):
			var c: Vector3 = part.center
			var s: Vector3 = part.size
			out.append(_box(b, "office_" + str(part.id), c - s * 0.5, c + s * 0.5, "cover"))
	# The bunk room.
	for p in bunk_parts(b):
		var c: Vector3 = p.center
		var s: Vector3 = p.size
		out.append(_box(b, str(p.id), c - s * 0.5, c + s * 0.5, "cover"))
	return out


## One piece as a town box: local corners -> the town's frame (snapped to the mm,
## so pieces that touch never overlap by a rounding error).
static func _box(b: Dictionary, id: String, lo: Vector3, hi: Vector3, kind: String) -> Dictionary:
	var xf := frame(b)
	var a := xf * lo
	var c := xf * hi
	var mn := Vector3(minf(a.x, c.x), minf(a.y, c.y), minf(a.z, c.z))
	var mx := Vector3(maxf(a.x, c.x), maxf(a.y, c.y), maxf(a.z, c.z))
	var out := { "id": "%s_%s" % [str(b.id), id], "zone": str(b.get("zone", "")), "kind": kind,
		"min": [snappedf(mn.x, 0.001), snappedf(mn.y, 0.001), snappedf(mn.z, 0.001)],
		"max": [snappedf(mx.x, 0.001), snappedf(mx.y, 0.001), snappedf(mx.z, 0.001)],
		"part_of": str(b.id) }
	if kind == "wall" or kind == "overhead":
		out["under_roof"] = true
	return out


## The office as OutpostRoom's control room (its door face toward the corridor):
## a building whose inside faces are the hall's back wall, the corridor wall and
## the locked rooms either side.
static func office_room(b: Dictionary) -> Dictionary:
	var o := layout(b)
	var w := 0.3
	var x0: float = o.ix0
	var x1: float = (o.p2 as Vector2).x
	var off: Vector2 = o.office
	var rows := office_rows(b)
	return { "id": "office", "size": [x1 - x0 + 2.0 * w, o.h, off.y - off.x + 2.0 * w],
		"position": [(x0 + x1) * 0.5, 0.0, (off.x + off.y) * 0.5], "room": { "wall": w, "rows": rows } }


## OutpostRoom's console rows for the office: the data's, but one when the
## office is too shallow for a second bank and a walk round the holo table.
static func office_rows(b: Dictionary) -> int:
	var cfg: Dictionary = spec().get("office", {})
	return int(cfg.get("rows", 2)) if float(layout(b).back) >= float(cfg.get("two_rows_from", 9.0)) else 1


## The bunk room's furniture (local): { id, size, center, finish } for the bunks
## (two-high, in a row along each long wall), their footlockers and the lockers on
## the far wall. Finishes: "frame", "mattress", "locker" (BarracksLook's).
static func bunk_parts(b: Dictionary) -> Array:
	var out: Array = []
	var o := layout(b)
	var cfg: Dictionary = spec().get("bunks", {})
	var bw := float((cfg.get("bunk", [0.95, 2.0]) as Array)[0])
	var bl := float((cfg.get("bunk", [0.95, 2.0]) as Array)[1])
	var pitch := float(cfg.get("pitch", 1.75))
	var bh := float(cfg.get("height", 1.9))
	var fl: Array = cfg.get("footlocker", [0.8, 0.45, 0.45])
	var lk: Array = cfg.get("locker", [0.6, 2.0, 0.55])
	var side: float = o.bunk_side
	var near: float = o.bunk_near
	var far: float = o.bunk_far
	var room_x0: float = (o.p1 as Vector2).y
	var room_x1: float = o.ix1
	var ig: Vector2 = o.igap
	var bk: Vector2 = o.bunks
	var door := (bk.x + bk.y) * 0.5
	# Lockers against the far wall, in the aisle between the rows.
	var aisle0 := room_x0 + bl + float(fl[1]) + 0.3
	var aisle1 := room_x1 - bl - float(fl[1]) - 0.3
	var n_lock := mini(int(cfg.get("lockers", 4)), int((aisle1 - aisle0) / (float(lk[0]) + 0.05)))
	for i in maxi(n_lock, 0):
		var x := (aisle0 + aisle1) * 0.5 + (i - (n_lock - 1) * 0.5) * (float(lk[0]) + 0.05)
		out.append({ "id": "locker_%d" % i, "size": Vector3(float(lk[0]), float(lk[1]), float(lk[2])),
			"center": Vector3(x, float(lk[1]) * 0.5, far - side * float(lk[2]) * 0.5), "finish": "locker" })
	# The bunks, from near the way in toward the far wall.
	var z_from := near + side * float(cfg.get("near_clear", 1.4))
	var z_to := far - side * (0.5 if n_lock <= 0 else float(lk[2]) + 0.4)
	var count := 0
	var most := int(cfg.get("count", 16))
	for row in 2:
		var on_corridor := row == 1
		var x := room_x0 + bl * 0.5 if on_corridor else room_x1 - bl * 0.5
		var fx := room_x0 + bl + float(fl[1]) * 0.5 if on_corridor else room_x1 - bl - float(fl[1]) * 0.5
		var k := 0
		while count < most:
			var z := z_from + side * (bw * 0.5 + k * pitch)
			k += 1
			if side * (z + side * bw * 0.5) > side * z_to:
				break
			if on_corridor and absf(z - door) < ig.x * 0.5 + bw * 0.5 + 0.35:
				continue                          # keep the doorway clear
			out.append({ "id": "bunk_%d" % count, "size": Vector3(bl, bh, bw), "center": Vector3(x, bh * 0.5, z), "finish": "frame" })
			out.append({ "id": "footlocker_%d" % count, "size": Vector3(float(fl[1]), float(fl[2]), float(fl[0])),
				"center": Vector3(fx, float(fl[2]) * 0.5, z), "finish": "locker" })
			count += 1
	return out


# ------------------------------------------------------------------ markers, routes

## The rifle's spot and the troopers' posts (the town's frame).
static func hall_markers(b: Dictionary) -> Array:
	var out: Array = []
	var xf := frame(b)
	var rifle: Dictionary = spec().get("rifle", {})
	out.append({ "id": str(rifle.get("marker", "barracks_rifle_spot")), "pos": _arr(xf * rifle_spot(b)), "role": "interact",
		"part_of": str(b.id), "note": "Issue #321: in front of the barracks office's middle console, where the story rifle is hidden (pickups/port_town.json barracks_rifle)." })
	for t in spec().get("troopers", []):
		var pts := _route(b, int(t.get("end", -1)))
		out.append({ "id": str(t.id), "pos": [pts[0][0], 0.0, pts[0][1]], "role": "trooper_post", "soldier": str(t.get("soldier", "yard_trooper")),
			"patrol": "patrol_" + str(t.id), "part_of": str(b.id),
			"note": "Issue #321: a Remnant trooper inside the barracks hall, on a loop from the corridor into the office." })
	return out


static func hall_routes(b: Dictionary) -> Array:
	var out: Array = []
	for t in spec().get("troopers", []):
		out.append({ "id": "patrol_" + str(t.id), "points": _route(b, int(t.get("end", -1))), "part_of": str(b.id) })
	return out


## Where the rifle's search spot is (local, on the floor): in front of the
## office's middle console.
static func rifle_spot(b: Dictionary) -> Vector3:
	var o := layout(b)
	var off: Vector2 = o.office
	return Vector3(float(o.ix0) + OutpostRoom.BACK_DEPTH + float(spec().get("rifle", {}).get("out", 0.75)), 0.0, (off.x + off.y) * 0.5)


## The holo table's foot (local).
static func holo_spot(b: Dictionary) -> Vector3:
	return OutpostRoom.holo(office_room(b))


## A trooper's loop (the town's frame, [x, z] points): from near one end of the
## corridor along it to the office door, in, round the holo table, and back out.
static func _route(b: Dictionary, end: int) -> Array:
	var o := layout(b)
	var xf := frame(b)
	var cx: float = o.cx
	var off: Vector2 = o.office
	var od := (off.x + off.y) * 0.5
	var hx := holo_spot(b).x
	var p2: Vector2 = o.p2
	var r := 1.5                                    # the table is 1.3 across: 0.85 clear of it
	# Behind the table, clear of the consoles there (the second bank, or the back row).
	var rear := float(o.ix0) + (OutpostRoom.BACK_DEPTH if office_rows(b) < 2 else 2.7 + OutpostRoom.SIDE_DEPTH * 0.5) + 0.9
	var bx := maxf(hx - r, rear)
	var local := [
		Vector3(cx, 0, signf(float(end)) * (float(o.iz) - 1.6)),
		Vector3(cx, 0, od),
		Vector3(p2.x - 1.0, 0, od),
		Vector3(hx + r, 0, od + r),
		Vector3(bx, 0, od + r),
		Vector3(bx, 0, od - r),
		Vector3(hx + r, 0, od - r),
		Vector3(p2.x - 1.0, 0, od),
		Vector3(cx, 0, od),
	]
	var out: Array = []
	for p in local:
		var q: Vector3 = xf * (p as Vector3)
		out.append([snappedf(q.x, 0.01), snappedf(q.z, 0.01)])
	return out


# ------------------------------------------------------------------ the look's places

## The locked doors (local frames for TownBuildings.door: +x out of the wall face,
## origin at the foot): on the locked rooms' corridor faces, the corridor's ends,
## the office's front wall and the bunk room's near wall.
static func doors(b: Dictionary) -> Array:
	var out: Array = []
	var o := layout(b)
	var cfg: Dictionary = spec().get("locked_doors", {})
	var every := float(cfg.get("corridor_every", 7.0))
	var least := float(cfg.get("corridor_min", 2.6))
	var iz: float = o.iz
	var p1: Vector2 = o.p1
	var p2: Vector2 = o.p2
	var v: Vector2 = o.vest
	var off: Vector2 = o.office
	var bk: Vector2 = o.bunks
	var faces: Array = []                           # [x of the face, its normal along x, z0, z1]
	if float(o.bunk_side) < 0.0:
		faces.append([p1.x, -1.0, -iz, bk.x])
		faces.append([p1.x, -1.0, v.y + o.pw, iz])
	else:
		faces.append([p1.x, -1.0, bk.y, iz])
		faces.append([p1.x, -1.0, -iz, v.x - o.pw])
	faces.append([p2.y, 1.0, -iz, off.x])
	faces.append([p2.y, 1.0, off.y, iz])
	for f in faces:
		var span := float(f[3]) - float(f[2])
		if span < least:
			continue
		var k := maxi(1, int(span / every))
		for i in k:
			var z := float(f[2]) + span * (i + 0.5) / k
			out.append(Transform3D(Basis(Vector3.UP, 0.0 if float(f[1]) > 0.0 else PI), Vector3(float(f[0]), 0, z)))
	if bool(cfg.get("corridor_ends", true)):
		out.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(o.cx, 0, iz)))       # faces -z
		out.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(o.cx, 0, -iz)))     # faces +z
	var no := int(cfg.get("office", 2))
	for i in no:
		var t := (i + 0.5) / no
		var z := off.x + (off.y - off.x) * (0.18 + 0.64 * t)
		if absf(z - (off.x + off.y) * 0.5) < 2.2:
			continue                                   # not over the office's own doorway
		out.append(Transform3D(Basis(Vector3.UP, PI), Vector3(p2.x, 0, z)))
	if int(cfg.get("bunks", 1)) > 0:
		var near: float = o.bunk_near
		var x := ((p1.y) + float(o.ix1)) * 0.5
		var s: float = o.bunk_side
		out.append(Transform3D(Basis(Vector3.UP, -PI * 0.5 if s > 0.0 else PI * 0.5), Vector3(x, 0, near)))   # facing into the room
	return out


## The open doorways' frames (local, as doors()): the way in (outside and in), and
## the office's and the bunk room's (on the corridor side), with their scale.
static func doorways(b: Dictionary) -> Array:
	var o := layout(b)
	var off: Vector2 = o.office
	var bk: Vector2 = o.bunks
	var si := n("inner_door_scale", 1.4)
	return [
		{ "at": Transform3D(Basis.IDENTITY, Vector3(o.d * 0.5, 0, o.dz)), "scale": n("door_scale", 1.6), "outside": true },
		{ "at": Transform3D(Basis(Vector3.UP, PI), Vector3(o.ix1, 0, o.dz)), "scale": n("door_scale", 1.6) },
		{ "at": Transform3D(Basis.IDENTITY, Vector3((o.p2 as Vector2).y, 0, (off.x + off.y) * 0.5)), "scale": si },
		{ "at": Transform3D(Basis(Vector3.UP, PI), Vector3((o.p1 as Vector2).x, 0, (bk.x + bk.y) * 0.5)), "scale": si },
	]


## Inside the hall's walls (the town's frame, under its roof)?
static func contains(b: Dictionary, p: Vector3) -> bool:
	var l := frame(b).affine_inverse() * p
	var o := layout(b)
	return l.x > float(o.ix0) and l.x < float(o.ix1) and absf(l.z) < float(o.iz) and l.y > -1.0 and l.y < float(o.top)


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
