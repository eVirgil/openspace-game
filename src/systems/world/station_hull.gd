class_name StationHull
extends RefCounted
## A space station you fly to, land in and walk round (the plan on issue #311:
## docs/station/nitrogen_belt_plan.svg). Two towers of tall round floors, the top
## floor the biggest, open space between floors, an elevator up the middle of
## each tower in a glass tube, glass-walled tunnels between the towers and a
## covered landing bay at the end of its own tunnel.
##
## A component, not part of any planet: everything is one config file
## (content/core/stations/<id>.json), and where it hangs is a "kind": "station"
## landmark naming that file, in whichever world or planet config has it. Take the
## landmark out and the station is gone; put it in another planet's landmarks and it
## is there. Today it is in the ringed giant's (content/core/planets/ringed_giant.json),
## over the top of the ball where its town was; it started over the moon's far side.
##
## Pure: every part is a box in the station's own frame, and every place the
## elevator, the pads and the docking autopilot use is a point in it. The same
## boxes are what you walk on (WorldScenery's landmark colliders), what a ship lands
## on and flies into (WorldGround) and what you see (SpaceStation merges them by
## finish). Like the cruiser (CruiserHull), the station holds its own attitude: its
## floors are level with world up and its gravity is square to them
## (PlanetSphere.gravity_zones), so aboard, up is world up, as in town.
##
## The parts are { id, size, xf (its frame in the station's), kind: "floor" (stood
## on), "solid" or "decor" (drawn only), finish }. The frame: y up, the main tower's
## middle at x = z = 0, y = 0 the market floor and the bay's deck.

const DATA_DIR := "res://content/core/stations/"
const LANDMARK_KIND := "station"
const UP := Vector3.UP
const WALL := 0.6                  ## outer walls
const INNER_WALL := 0.4            ## room walls and dividers
const GLASS := 0.3                 ## the shaft and the tube
const RAIL_H := 1.1
const MARGIN := 40.0               ## the gravity box past the outermost part

static var _cache: Dictionary = {}     ## id -> StationHull

var id := ""
var cfg: Dictionary = {}
var seg := 48
var floor_h := 14.0
var plate := 1.0
var gap_r := 12.0
var walk := 7.0
var shaft_r := 5.5
var tunnel_w := 6.0
var tunnel_h := 5.0
var towers: Array = []             ## { id, c: Vector2 (x, z), floors: [{ id, y, r, rooms }] (bottom up) }
var tunnels: Array = []            ## { id, from, to, y, xf (x along it), length }
var bay: Dictionary = {}           ## { xf (x out to the mouth), c, dir, r, mouth (half angle), height, apron }
var parts: Array = []
var doors: Array = []              ## { tower, floor (index), xf, size }: the shaft's doors, opened by SpaceStation
var hatches: Array = []            ## { tunnel, xf, size }: the shield in each tunnel's roof (you pass, the air does not)
var _built := false


## The station of config `id` (content/core/stations/<id>.json), read and built once
## a session. Null when there is no such file.
static func for_id(station_id: String) -> StationHull:
	if _cache.has(station_id):
		return _cache[station_id]
	var f := FileAccess.open(DATA_DIR + station_id + ".json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (d is Dictionary):
		push_warning("StationHull: no station config %s" % station_id)
		return null
	var h := StationHull.new()
	h.setup(d)
	_cache[station_id] = h
	return h


func setup(d: Dictionary) -> void:
	cfg = d
	id = str(d.get("id", "station"))
	seg = int(d.get("segments", 48))
	floor_h = float(d.get("floor_height", 14.0))
	plate = float(d.get("plate", 1.0))
	gap_r = float(d.get("gap_radius", 12.0))
	walk = float(d.get("walkway", 7.0))
	shaft_r = float(d.get("shaft_radius", 5.5))
	tunnel_w = float(d.get("tunnel", {}).get("width", 6.0))
	tunnel_h = float(d.get("tunnel", {}).get("height", 5.0))
	towers = []
	for t in d.get("towers", []):
		var at: Array = t.get("at", [0, 0])
		var fl: Array = []
		for f in t.get("floors", []):
			fl.append({ "id": str(f.get("id", "")), "y": float(f.get("y", 0.0)), "r": float(f.get("radius", 40.0)),
				"rooms": bool(f.get("rooms", true)) })
		fl.sort_custom(func(a, b): return float(a.y) < float(b.y))
		towers.append({ "id": str(t.get("id", "")), "c": Vector2(float(at[0]), float(at[1])), "floors": fl })
	_read_bay(d.get("bay", {}))
	_read_tunnels(d.get("tunnels", []))
	_build()


func tower(tower_id: String) -> Dictionary:
	for t in towers:
		if str(t.id) == tower_id:
			return t
	return {}


## The floor of tower `t` whose plate is at `y` (within a metre), or {}.
static func floor_at(t: Dictionary, y: float) -> Dictionary:
	for f in t.get("floors", []):
		if absf(float(f.y) - y) < 1.0:
			return f
	return {}


## Ceiling top (the floor's height plus its plate) and the lowest plate bottom.
func top_y() -> float:
	var y := -INF
	for t in towers:
		for f in t.floors:
			y = maxf(y, float(f.y) + floor_h + plate)
	return maxf(y, float(bay.get("height", 0.0)) + plate) if not bay.is_empty() else y


func bottom_y() -> float:
	var y := INF
	for t in towers:
		for f in t.floors:
			y = minf(y, float(f.y) - plate)
	return y


## Where the station's own gravity holds (its frame): every part and a margin.
func gravity_box() -> AABB:
	var box := AABB()
	var first := true
	for p in parts:
		var xf: Transform3D = p.xf
		var h: Vector3 = (p.size as Vector3) * 0.5
		var b := xf * AABB(-h, h * 2.0)
		box = b if first else box.merge(b)
		first = false
	return box.grow(MARGIN)


# ------------------------------------------------------------------ the frame

## Where the station hangs and how it is turned. "side": "far": over the far side of
## this planet's ball from the body it is near (the moon's far side from the home
## planet), `altitude` metres up. Otherwise like the cruiser: over map point `at`
## ([east, south] metres along the ground from the port), `altitude` up. Level with
## the port (its y is world up), its bay's mouth turned toward the port across the
## sky, then `yaw_deg` about its up.
func frame_for(sp: PlanetSphere, lm: Dictionary, world: Dictionary = {}) -> Transform3D:
	var dir := Vector3.ZERO
	if str(lm.get("side", "")) == "far":
		var parent = _parent_center(str(world.get("planet", "")))
		if parent != null:
			dir = (sp.center - (parent as Vector3)).normalized()
	if dir == Vector3.ZERO:
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		dir = sp.map_dir(at.x, at.z)
	var pos := sp.center + dir * (sp.radius + float(lm.get("altitude", 1400.0)))
	var to_port := Vector3(-pos.x, 0.0, -pos.z)
	if to_port.length() < 0.01:
		to_port = Vector3.LEFT
	var mouth := bay_out()
	var turn := atan2(to_port.x, to_port.z) - atan2(mouth.x, mouth.z) + deg_to_rad(float(lm.get("yaw_deg", 0.0)))
	return Transform3D(Basis(UP, turn), pos)


## A planet whose town is this station (its config's "station_town": the landmark
## id): the town is only the station's bay, in the planet's own coordinates. The
## ship's pad box ("ship") on the dock pad, where you arrive, and "player_spawn"
## beside it on the bay's deck (where a save loaded here puts you), standing on
## a painted plate (kind "pad": the town validator wants a marker to stand on a
## town box; the station's own deck is what you walk on). No wall, no deck, no
## cantina: everything else is the station.
static func town_for(town_id: String, lm: Dictionary, sp: PlanetSphere, world: Dictionary = {}) -> Dictionary:
	var h := for_id(str(lm.get("station", "")))
	if h == null:
		return {}
	var xf := h.frame_for(sp, lm, world)
	var pad := h.dock_pad()
	if pad.is_empty():
		return {}
	var c: Vector3 = xf * (pad.at as Vector3)
	var dims := [8.82, 2.36, 7.8]                 # the pad ship's box (town_kit.json ship_boxes.pad)
	var hx := float(dims[0]) * 0.5
	var hz := float(dims[2]) * 0.5
	var sp_at: Vector3 = xf * h.spawn_point()
	var deck_y := c.y
	sp_at.y = deck_y + 0.02
	var yaw := rad_to_deg(float(pad.yaw) + xf.basis.get_euler().y)
	var boxes := [
		{ "id": "ship", "zone": "landing_bay", "kind": "ship", "min": [c.x - hx, deck_y, c.z - hz], "max": [c.x + hx, deck_y + float(dims[1]), c.z + hz],
			"parked_yaw_deg": yaw },
		{ "id": "spawn_plate", "zone": "landing_bay", "kind": "pad", "standable": true, "hidden": true,
			"min": [sp_at.x - 1.0, deck_y, sp_at.z - 1.0], "max": [sp_at.x + 1.0, sp_at.y, sp_at.z + 1.0] },
	]
	var x0 := minf(c.x - hx, sp_at.x - 1.0) - 2.0
	var x1 := maxf(c.x + hx, sp_at.x + 1.0) + 2.0
	var z0 := minf(c.z - hz, sp_at.z - 1.0) - 2.0
	var z1 := maxf(c.z + hz, sp_at.z + 1.0) + 2.0
	return {
		"id": town_id,
		"kind": "station",
		"units": "meters",
		"note": "Made by StationHull.town_for: this planet's town is the space station's bay.",
		"bounds": { "min": [x0, z0], "max": [x1, z1] },
		"player_clearance": 0.6,
		"walk_speed_hint": 4.5,
		"blocking_kinds": ["wall", "solid", "cover", "counter", "ship"],
		"zones": [{ "id": "landing_bay", "min": [x0, z0], "max": [x1, z1] }],
		"boxes": boxes,
		"markers": [{ "id": "player_spawn", "pos": [sp_at.x, sp_at.y, sp_at.z], "role": "spawn" }],
		"routes": [],
		"garrison": {},
		"locals": {},
		"counts": { "guards": 0, "residents": 0, "roamers": 0, "stalls": 0, "merchants": 0, "bays": 1 },
		"club": {},
		"station_town": str(lm.get("id", "")),
	}


## The centre of the ball planet `planet_id` is near, in its own scene's
## coordinates (PlanetGen.neighbours: the one that is not a child), or null.
static func _parent_center(planet_id: String):
	if planet_id == "":
		return null
	for n in PlanetGen.neighbours(planet_id):
		if not bool(n.get("child", true)) and not n.has("via"):
			return n.at
	return null


## The bay's way out to space, in the station's frame (level).
func bay_out() -> Vector3:
	if bay.is_empty():
		return Vector3.LEFT
	return (bay.xf as Transform3D).basis.x


## Register the station with the world's ground (WorldGround, for a landmark of kind
## "station"): every part as a box in its own frame (drawn by SpaceStation, not the
## landmark look), its frame on each so the scene finds it again (frame()), and its
## gravity. Nothing on a world with no ball.
static func add_to_ground(ground: WorldGround, lm: Dictionary) -> void:
	var sp := ground.sphere()
	var h := for_id(str(lm.get("station", "")))
	if sp == null or h == null:
		return
	var xf := h.frame_for(sp, lm, ground.world)
	var prefix := str(lm.get("id", h.id)) + "/"
	for p in h.parts:
		if str(p.kind) == "decor":
			continue
		ground.add_box(prefix + str(p.id), str(p.kind), -(p.size as Vector3) * 0.5, (p.size as Vector3) * 0.5,
			"", false, xf * (p.xf as Transform3D))
		ground.boxes[-1]["station_frame"] = xf
	sp.add_gravity_zone(xf, h.gravity_box())


## A landmark's station frame from the ground's boxes, or identity when it is not there.
static func frame(ground: WorldGround, landmark_id: String) -> Transform3D:
	if ground == null:
		return Transform3D.IDENTITY
	for b in ground.boxes:
		if b.has("station_frame") and str(b.id).begins_with(landmark_id + "/"):
			return b.station_frame
	return Transform3D.IDENTITY


## Every station landmark in a world (content/core/worlds/*.json or a planet's).
static func landmarks(world: Dictionary) -> Array:
	return (world.get("landmarks", []) as Array).filter(func(lm): return str(lm.get("kind", "")) == LANDMARK_KIND)


# ------------------------------------------------------------------ places

## The landing pads: { id, at: Vector3 (on the deck, station frame), yaw (nose out),
## radius }.
func pads() -> Array:
	var out: Array = []
	if bay.is_empty():
		return out
	var bx: Transform3D = bay.xf
	var yaw := atan2(-bay_out().x, -bay_out().z)     # a ship's nose is its -z
	for p in cfg.get("pads", []):
		var a: Array = p.get("at", [0, 0])
		out.append({ "id": str(p.get("id", "")), "at": bx * Vector3(float(a[0]), 0.0, float(a[1])), "yaw": yaw,
			"radius": float(p.get("radius", 12.0)), "local": Vector2(float(a[0]), float(a[1])) })
	return out


func pad(pad_id: String) -> Dictionary:
	for p in pads():
		if p.id == pad_id:
			return p
	return {}


func dock_pad() -> Dictionary:
	return pad(str(cfg.get("dock", {}).get("pad", "dock")))


## Where a walker is put back aboard: on the deck beside the dock pad, toward the back.
func spawn_point() -> Vector3:
	var p := dock_pad()
	if p.is_empty():
		return Vector3(0, 0.2, 0)
	return (bay.xf as Transform3D) * Vector3((p.local as Vector2).x - 18.0, 0.2, (p.local as Vector2).y)


## The elevator's stops in each tower: { tower, c: Vector2, stops: [y, ...] }.
func elevators() -> Array:
	var out: Array = []
	for t in towers:
		var ys: Array = t.floors.map(func(f): return float(f.y))
		if ys.size() >= 2:
			out.append({ "tower": str(t.id), "c": t.c, "stops": ys })
	return out


## Which way a floor's bridges run: along x (east-west) or z (north-south),
## alternating floor by floor from the bottom.
static func bridge_angles(floor_index: int) -> Array:
	return [PI * 0.5, PI * 1.5] if floor_index % 2 == 0 else [0.0, PI]


## Inside the walkable interior (a floor, the shaft and tube, a tunnel, the bay), in
## the station's frame.
func aboard(local: Vector3) -> bool:
	for t in towers:
		var c: Vector2 = t.c
		var d := Vector2(local.x - c.x, local.z - c.y).length()
		var fl: Array = t.floors
		for f in fl:
			if d <= float(f.r) and local.y >= float(f.y) - 2.0 and local.y <= float(f.y) + floor_h + 0.5:
				return true
		if not fl.is_empty() and d <= gap_r and local.y >= float(fl[0].y) - 2.0 \
				and local.y <= float(fl[-1].y) + floor_h + 0.5:
			return true
	for tn in tunnels:
		var l := (tn.xf as Transform3D).affine_inverse() * local
		if l.x >= -1.0 and l.x <= float(tn.length) + 1.0 and absf(l.z) <= tunnel_w * 0.5 + 0.5 \
				and l.y >= -2.0 and l.y <= tunnel_h + 0.5:
			return true
	if not bay.is_empty():
		var c: Vector2 = bay.c
		if Vector2(local.x - c.x, local.z - c.y).length() <= float(bay.r) + 0.5 \
				and local.y >= -2.0 and local.y <= float(bay.height):
			return true
	return false


## The points the docking autopilot flies through from `local` (the station's frame):
## round the towers first when starting behind the bay's mouth (over them from
## above their middle, under them from below), out off the mouth at hold height,
## in over the apron, and to a stop over the dock pad.
func dock_path(local: Vector3) -> Array:
	var dc: Dictionary = cfg.get("dock", {})
	var p := dock_pad()
	if bay.is_empty() or p.is_empty():
		return []
	var bx: Transform3D = bay.xf
	var lp: Vector2 = p.local
	var hold := float(dc.get("hold_y", 9.0))
	var off := float(bay.r) + float(dc.get("approach", 220.0))
	var b := bx.affine_inverse() * local
	var out: Array = []
	if b.x < float(bay.r) + 40.0:
		var mid := (top_y() + bottom_y()) * 0.5
		var y := maxf(local.y, float(dc.get("over_y", 150.0))) if local.y >= mid else minf(local.y, float(dc.get("under_y", -110.0)))
		out.append(Vector3(local.x, y, local.z))
		var o := bx * Vector3(off, 0.0, lp.y)
		out.append(Vector3(o.x, y, o.z))
	out.append(bx * Vector3(off, hold, lp.y))
	out.append(bx * Vector3(float(bay.r) + float(bay.apron) + 6.0, hold, lp.y))
	out.append(bx * Vector3(lp.x, hold, lp.y))
	return out


## The curved shield across the bay's round mouth, in the station's frame: { xf (its
## middle, x out of the mouth), size (its box: x the arc's bulge, y its height, z its
## chord), r (the wall's radius, from the bay's middle), half (the mouth's half angle),
## pieces: [{ xf, size }] (thin boxes along the arc, for its collider) }. Its own
## points: (r cos(t) - xf's x, y, r sin(t)) for t across the mouth, in the bay's frame
## shifted to xf.
func shield() -> Dictionary:
	if bay.is_empty():
		return {}
	var h := float(bay.height)
	var r := float(bay.r) + 0.5
	var half := float(bay.mouth)
	var mid := r * (1.0 + cos(half)) * 0.5
	var bx: Transform3D = bay.xf
	var pieces: Array = []
	var n := 10
	for k in n:
		var t := -half + (k + 0.5) * 2.0 * half / n
		var x := Vector3(cos(t), 0, sin(t))
		var w := 2.0 * r * tan(half / n) + 0.2
		pieces.append({ "xf": bx * Transform3D(Basis(x, UP, x.cross(UP)), x * r + Vector3(0, h * 0.5, 0)), "size": Vector3(0.4, h, w) })
	return { "xf": bx * Transform3D(Basis.IDENTITY, Vector3(mid, h * 0.5, 0)), "r": r, "half": half,
		"size": Vector3(r * (1.0 - cos(half)) + 0.4, h, 2.0 * r * sin(half)), "pieces": pieces }


# ------------------------------------------------------------------ reading

func _read_bay(b: Dictionary) -> void:
	bay = {}
	if b.is_empty():
		return
	var from := tower(str(b.get("from", "")))
	var at: Array = b.get("at", [-120, 0])
	var c := Vector2(float(at[0]), float(at[1]))
	var dir := Vector2(-1, 0)
	if not from.is_empty() and (c - (from.c as Vector2)).length() > 0.1:
		dir = (c - (from.c as Vector2)).normalized()
	var x := Vector3(dir.x, 0, dir.y)
	bay = { "xf": Transform3D(Basis(x, UP, x.cross(UP)), Vector3(c.x, 0, c.y)), "c": c, "dir": dir,
		"r": float(b.get("radius", 38.0)), "mouth": deg_to_rad(float(b.get("mouth_deg", 70.0))) * 0.5,
		"height": float(b.get("height", 30.0)), "apron": float(b.get("apron", 12.0)), "from": str(b.get("from", "")) }


func _read_tunnels(list: Array) -> void:
	tunnels = []
	for tn in list:
		var a := tower(str(tn.get("from", "")))
		var y := float(tn.get("y", 0.0))
		var fa := floor_at(a, y)
		if fa.is_empty():
			push_warning("StationHull %s: tunnel %s has no floor at %.0f in %s" % [id, str(tn.get("id", "")), y, str(tn.get("from", ""))])
			continue
		var ca: Vector2 = a.c
		var start := Vector2.ZERO
		var end := Vector2.ZERO
		var to_id := str(tn.get("to", ""))
		if to_id == "bay":
			if bay.is_empty():
				continue
			var dir: Vector2 = bay.dir
			start = ca + dir * (float(fa.r) - 0.4)
			end = (bay.c as Vector2) - dir * (float(bay.r) - 0.3)
		else:
			var b := tower(to_id)
			var fb := floor_at(b, y)
			if fb.is_empty():
				push_warning("StationHull %s: tunnel %s has no floor at %.0f in %s" % [id, str(tn.get("id", "")), y, to_id])
				continue
			var dir := ((b.c as Vector2) - ca).normalized()
			start = ca + dir * (float(fa.r) - 0.4)
			end = (b.c as Vector2) - dir * (float(fb.r) - 0.4)
		var d := (end - start)
		var x := Vector3(d.x, 0, d.y).normalized()
		tunnels.append({ "id": str(tn.get("id", "")), "from": str(tn.get("from", "")), "to": to_id, "y": y,
			"xf": Transform3D(Basis(x, UP, x.cross(UP)), Vector3(start.x, y, start.y)), "length": d.length() })


## The angles (round tower `t`'s middle, 0 = +x, PI/2 = +z) where tunnels leave its
## floor at `y`.
func _door_angles(t: Dictionary, y: float) -> Array:
	var out: Array = []
	var c: Vector2 = t.c
	for tn in tunnels:
		if absf(float(tn.y) - y) > 1.0:
			continue
		var xf: Transform3D = tn.xf
		var s := Vector2(xf.origin.x, xf.origin.z)
		var e3 := xf * Vector3(float(tn.length), 0, 0)
		var e := Vector2(e3.x, e3.z)
		if str(tn.from) == str(t.id):
			out.append((s - c).angle())
		elif str(tn.to) == str(t.id):
			out.append((e - c).angle())
	return out


# ------------------------------------------------------------------ building

func _build() -> void:
	parts = []
	doors = []
	hatches = []
	for t in towers:
		var fl: Array = t.floors
		for i in fl.size():
			_floor(t, i)
		_tower_dressing(t)
	for tn in tunnels:
		_tunnel(tn)
	_bay()
	_built = true


func _add(pid: String, xf: Transform3D, size: Vector3, kind: String, finish: String) -> void:
	parts.append({ "id": pid, "xf": xf, "size": size, "kind": kind, "finish": finish })


## A box of `size` centred on `at`, its x along angle `a` (round the station's y).
func _at_angle(pid: String, at: Vector3, a: float, size: Vector3, kind: String, finish: String) -> void:
	var x := Vector3(cos(a), 0, sin(a))
	_add(pid, Transform3D(Basis(x, UP, x.cross(UP)), at), size, kind, finish)


## An annulus round `c` (x, z) from r0 to r1, between y0 and y1, as boxes no wider
## than one segment each, with `gaps` ([angle, half width in metres at the middle
## radius]) left open. Each box spans r0 to r1 along its middle angle; its sides
## meet the next box's at r1 (inside that they overlap, never open).
func _ring(pid: String, c: Vector2, r0: float, r1: float, y0: float, y1: float, kind: String, finish: String,
		gaps: Array = [], n: int = -1) -> void:
	var count := n if n > 0 else seg
	var step := TAU / count
	var rm := maxf((r0 + r1) * 0.5, 0.5)
	var spans: Array = [Vector2(0.0, TAU)]
	for g in gaps:
		var half := float(g[1]) / rm
		var a := fposmod(float(g[0]), TAU)
		spans = _cut(spans, a - half, a + half)
	var k := 0
	for s: Vector2 in spans:
		var pieces := maxi(1, ceili((s.y - s.x) / step - 0.001))
		var da := (s.y - s.x) / pieces
		for j in pieces:
			var m := s.x + da * (j + 0.5)
			var w := 2.0 * r1 * tan(da * 0.5)
			var at := Vector3(c.x + cos(m) * (r0 + r1) * 0.5, (y0 + y1) * 0.5, c.y + sin(m) * (r0 + r1) * 0.5)
			_at_angle("%s_%d" % [pid, k], at, m, Vector3(r1 - r0, y1 - y0, w), kind, finish)
			k += 1


## The spans left of `spans` (angles 0..TAU) with [a0, a1] taken out (wrapping).
static func _cut(spans: Array, a0: float, a1: float) -> Array:
	var cuts: Array = []
	if a0 < 0.0:
		cuts = [Vector2(a0 + TAU, TAU), Vector2(0.0, a1)]
	elif a1 > TAU:
		cuts = [Vector2(a0, TAU), Vector2(0.0, a1 - TAU)]
	else:
		cuts = [Vector2(a0, a1)]
	var out := spans
	for cut: Vector2 in cuts:
		var next: Array = []
		for s: Vector2 in out:
			if cut.y <= s.x or cut.x >= s.y:
				next.append(s)
				continue
			if cut.x > s.x + 0.0001:
				next.append(Vector2(s.x, cut.x))
			if cut.y < s.y - 0.0001:
				next.append(Vector2(cut.y, s.y))
		out = next
	return out


## A straight box along angle `a` from `c`, from r0 to r1 out, `width` across,
## `side` metres to the left of the line (along +z of its frame).
func _radial(pid: String, c: Vector2, a: float, r0: float, r1: float, y0: float, y1: float, width: float,
		kind: String, finish: String, side := 0.0) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	var at := Vector3(c.x, (y0 + y1) * 0.5, c.y) + dir * (r0 + r1) * 0.5 + dir.cross(UP) * side
	_at_angle(pid, at, a, Vector3(r1 - r0, y1 - y0, width), kind, finish)


## One round floor of tower `t`: its plate, the glass floor over the gap, the
## ceiling (and the tube up to the next floor, or the skylight on top), the glass
## outer wall with doors to its tunnels, the railing and bridges round the gap,
## the elevator shaft with its doors, and the rooms.
func _floor(t: Dictionary, i: int) -> void:
	var fl: Array = t.floors
	var f: Dictionary = fl[i]
	var c: Vector2 = t.c
	var y := float(f.y)
	var r := float(f.r)
	var top := i == fl.size() - 1
	var pre := "%s_%s" % [str(t.id), str(f.id)]
	var doors_at := _door_angles(t, y)
	var door_gaps: Array = doors_at.map(func(a): return [a, tunnel_w * 0.5])
	var ceil_y := y + floor_h
	# The plate, the gap's glass floor (the shaft's own floor at the bottom).
	_ring(pre + "_plate", c, gap_r, r, y - plate, y, "floor", "deck")
	_ring(pre + "_gap_glass", c, shaft_r, gap_r, y - 0.4, y, "floor", "glass_floor", [], 24)
	if i == 0:
		_ring(pre + "_pit", c, 0.0, shaft_r, y - plate, y, "floor", "deck", [], 12)
	# A glowing band round the plate's edge outside, and the underside's trim.
	_ring(pre + "_edge_glow", c, r + 0.05, r + 0.35, y - 0.75, y - 0.45, "decor", "glow")
	_ring(pre + "_ceiling", c, gap_r, r, ceil_y, ceil_y + plate, "solid", "hull")
	if top:
		_ring(pre + "_skylight", c, shaft_r, gap_r, ceil_y, ceil_y + 0.3, "solid", "glass", [], 24)
		_ring(pre + "_shaft_cap", c, 0.0, shaft_r, ceil_y, ceil_y + plate, "solid", "hull", [], 12)
	else:
		var next_y := float(fl[i + 1].y) - plate
		_ring(pre + "_tube", c, gap_r - GLASS * 0.5, gap_r + GLASS * 0.5, ceil_y, next_y, "solid", "glass", [], 32)
		for k in 3:
			var ry := ceil_y + plate + (next_y - ceil_y - plate) * (k + 1) / 4.0
			_ring(pre + "_tube_rib_%d" % k, c, gap_r + 0.15, gap_r + 0.45, ry - 0.2, ry + 0.2, "decor", "trim", [], 32)
	# The outer wall: a band of hull, tall glass, a band of hull, with lintels over the
	# tunnels' doors; mullions on the joints.
	var ro := r - WALL * 0.5
	var ri := r + WALL * 0.5
	_ring(pre + "_window", c, ro, ri, y, ceil_y, "solid", "glass", door_gaps)       # the collider: one box a segment
	_ring(pre + "_wall_base", c, ro - 0.05, ri + 0.05, y, y + 1.2, "decor", "hull", door_gaps)
	_ring(pre + "_wall_top", c, ro - 0.05, ri + 0.05, ceil_y - 1.0, ceil_y, "decor", "hull", door_gaps)
	for a in doors_at:
		var half := (tunnel_w * 0.5 + 0.3) / r
		_ring(pre + "_lintel_%d" % int(rad_to_deg(a)), c, ro, ri, y + tunnel_h, ceil_y, "solid", "hull",
			[[a + PI, PI * r - tunnel_w * 0.5 - 0.3]], maxi(1, ceili(half * 2.0 / (TAU / seg))))
	for k in seg:
		var a := TAU * k / seg
		var blocked := false
		for d in doors_at:
			if absf(wrapf(a - float(d), -PI, PI)) * r < tunnel_w * 0.5 + 0.5:
				blocked = true
		if not blocked:
			_radial("%s_mullion_%d" % [pre, k], c, a, r + 0.1, r + 0.5, y + 1.2, ceil_y - 1.0, 0.35, "decor", "trim")
	# The railing round the gap, open where the bridges cross; the bridges.
	var bridges := bridge_angles(i)
	var rail_gaps: Array = bridges.map(func(a): return [a, 1.7])
	_ring(pre + "_rail", c, gap_r - 0.1, gap_r + 0.1, y, y + RAIL_H, "solid", "rail", rail_gaps, 32)
	_ring(pre + "_rail_top", c, gap_r - 0.14, gap_r + 0.14, y + RAIL_H, y + RAIL_H + 0.08, "decor", "glow", rail_gaps, 32)
	for a in bridges:
		_radial("%s_bridge_%d" % [pre, int(rad_to_deg(a))], c, a, shaft_r, gap_r + 0.6, y, y + 0.08, 3.2, "floor", "grate")
		for side: float in [-1.6, 1.6]:
			_radial("%s_bridge_rail_%d_%d" % [pre, int(rad_to_deg(a)), int(side)], c, a, shaft_r + 0.4, gap_r - 0.1,
				y, y + RAIL_H, 0.12, "solid", "rail", side)
	# The shaft: glass round the car, doors at the bridges' ends, a full ring above
	# them up to the next floor (or the cap).
	var el: Dictionary = cfg.get("elevator", {})
	var dw := float(el.get("door_width", 3.2))
	var dh := float(el.get("door_height", 4.0))
	var shaft_top := ceil_y if top else float(fl[i + 1].y)
	_ring(pre + "_shaft", c, shaft_r - GLASS * 0.5, shaft_r + GLASS * 0.5, y, y + dh, "solid", "glass",
		bridges.map(func(a): return [a, dw * 0.5]), 24)
	_ring(pre + "_shaft_up", c, shaft_r - GLASS * 0.5, shaft_r + GLASS * 0.5, y + dh, shaft_top, "solid", "glass", [], 24)
	_ring(pre + "_shaft_frame", c, shaft_r + 0.15, shaft_r + 0.4, y + dh, y + dh + 0.35, "decor", "trim", [], 24)
	for a in bridges:
		var dir := Vector3(cos(a), 0, sin(a))
		var x := dir
		doors.append({ "tower": str(t.id), "floor": i, "size": Vector3(GLASS, dh, dw),
			"xf": Transform3D(Basis(x, UP, x.cross(UP)), Vector3(c.x, y + dh * 0.5, c.y) + dir * shaft_r) })
	if bool(f.rooms):
		_rooms(t, i, doors_at)


## The rooms round the outside of a floor: an inner wall at the walkway's edge with
## a door into each room, dividers between them, and corridors from the walkway out
## to each tunnel.
func _rooms(t: Dictionary, i: int, doors_at: Array) -> void:
	var f: Dictionary = t.floors[i]
	var c: Vector2 = t.c
	var y := float(f.y)
	var r := float(f.r)
	var ceil_y := y + floor_h
	var pre := "%s_%s" % [str(t.id), str(f.id)]
	var rc: Dictionary = cfg.get("rooms", {})
	var n := int(rc.get("count", 8))
	var dw := float(rc.get("door_width", 2.6))
	var dh := float(rc.get("door_height", 4.0))
	var rr := gap_r + walk
	var corr := tunnel_w * 0.5 + 0.4
	var gaps: Array = []
	var room_doors: Array = []
	for k in n:
		var a := TAU * (k + 0.5) / n
		var near := false
		for d in doors_at:
			if absf(wrapf(a - float(d), -PI, PI)) * rr < corr + dw:
				near = true
		if not near:
			room_doors.append(a)
			gaps.append([a, dw * 0.5])
	for d in doors_at:
		gaps.append([d, corr])
	_ring(pre + "_room_wall", c, rr - INNER_WALL * 0.5, rr + INNER_WALL * 0.5, y, ceil_y, "solid", "wall", gaps)
	for a in room_doors:
		_ring(pre + "_door_head_%d" % int(rad_to_deg(a)), c, rr - INNER_WALL * 0.5, rr + INNER_WALL * 0.5, y + dh, ceil_y,
			"solid", "wall", [[a + PI, PI * rr - dw * 0.5 - 0.05]], 1)
		_radial("%s_door_light_%d" % [pre, int(rad_to_deg(a))], c, a, rr - 0.35, rr - 0.25, y + dh + 0.1, y + dh + 0.3,
			dw, "decor", "glow")
	for d in doors_at:
		_ring(pre + "_corr_head_%d" % int(rad_to_deg(d)), c, rr - INNER_WALL * 0.5, rr + INNER_WALL * 0.5, y + tunnel_h, ceil_y,
			"solid", "wall", [[d + PI, PI * rr - corr - 0.05]], 1)
		for side: float in [-corr, corr]:
			_radial("%s_corr_wall_%d_%d" % [pre, int(rad_to_deg(d)), int(side)], c, d, rr, r - WALL * 0.5, y, ceil_y,
				INNER_WALL, "solid", "wall", side)
	for k in n:
		var a := TAU * k / n
		var clear := true
		for d in doors_at:
			if absf(wrapf(a - float(d), -PI, PI)) * (rr + r) * 0.5 < corr + 3.0:
				clear = false
		if clear:
			_radial("%s_divider_%d" % [pre, k], c, a, rr, r - WALL * 0.5, y, ceil_y, INNER_WALL, "solid", "wall")


## The outside of a tower: a spire of shrinking plates under its lowest floor and a
## mast with beacons on its roof.
func _tower_dressing(t: Dictionary) -> void:
	var fl: Array = t.floors
	if fl.is_empty():
		return
	var c: Vector2 = t.c
	var low: Dictionary = fl[0]
	var high: Dictionary = fl[-1]
	var y0 := float(low.y) - plate
	var r0 := float(low.r) * 0.55
	for k in 4:
		var rr := r0 * (1.0 - k * 0.22)
		_ring("%s_keel_%d" % [str(t.id), k], c, 0.0, rr, y0 - (k + 1) * 3.0, y0 - k * 3.0, "solid", "hull", [], 24)
	_ring("%s_keel_glow" % str(t.id), c, r0 * 0.3, r0 * 0.36, y0 - 13.0, y0 - 12.0, "decor", "glow", [], 24)
	var roof := float(high.y) + floor_h + plate
	var mast_h := float(high.r) * 0.45
	_add("%s_mast" % str(t.id), Transform3D(Basis.IDENTITY, Vector3(c.x, roof + mast_h * 0.5, c.y)),
		Vector3(1.6, mast_h, 1.6), "solid", "trim")
	for k in 3:
		var yy := roof + mast_h * (0.35 + k * 0.22)
		_add("%s_mast_bar_%d" % [str(t.id), k], Transform3D(Basis(UP, k * 0.9), Vector3(c.x, yy, c.y)),
			Vector3(14.0 - k * 3.0, 0.5, 0.5), "decor", "trim")
	_add("%s_beacon" % str(t.id), Transform3D(Basis.IDENTITY, Vector3(c.x, roof + mast_h + 0.6, c.y)),
		Vector3(1.4, 1.2, 1.4), "decor", "beacon")
	_ring("%s_roof_ring" % str(t.id), c, float(high.r) * 0.35, float(high.r) * 0.42, roof, roof + 1.2, "solid", "trim", [], 32)


## A tunnel: deck, roof, glass walls between hull bands, ribs along it. In the
## middle of its roof a hatch closed by a shield you pass through (hatch in the
## config): jump up through it (the jetpack) and you are out on the roof, a walkway
## between railings over the tunnel, out in space.
func _tunnel(tn: Dictionary) -> void:
	var xf: Transform3D = tn.xf
	var l := float(tn.length)
	var w := tunnel_w
	var h := tunnel_h
	var pre := str(tn.id)
	var hc: Dictionary = cfg.get("hatch", {})
	var hl := minf(float(hc.get("length", 4.0)), l - 4.0)
	var hw := minf(float(hc.get("width", 4.0)), w - 1.0)
	var rt := 0.6                                   # the roof's thickness
	var box := func(nm: String, at: Vector3, size: Vector3, kind: String, finish: String):
		_add(pre + "_" + nm, xf * Transform3D(Basis.IDENTITY, at), size, kind, finish)
	box.call("deck", Vector3(l * 0.5, -plate * 0.5, 0), Vector3(l, plate, w + 1.0), "floor", "deck")
	# The roof, round the hatch: fore and aft of it, and either side of it.
	var a0 := (l - hl) * 0.5
	var a1 := (l + hl) * 0.5
	box.call("roof_a", Vector3(a0 * 0.5, h + rt * 0.5, 0), Vector3(a0, rt, w + 1.0), "floor", "hull")
	box.call("roof_b", Vector3((a1 + l) * 0.5, h + rt * 0.5, 0), Vector3(l - a1, rt, w + 1.0), "floor", "hull")
	for s: float in [-1.0, 1.0]:
		var side := (w + 1.0 - hw) * 0.5
		box.call("roof_side_%d" % int(s), Vector3(l * 0.5, h + rt * 0.5, s * (hw + side) * 0.5), Vector3(hl, rt, side), "floor", "hull")
		box.call("hatch_rim_%d" % int(s), Vector3(l * 0.5, h + rt + 0.1, s * (hw * 0.5 + 0.15)), Vector3(hl + 0.6, 0.2, 0.3), "decor", "glow")
	for e: float in [a0, a1]:
		box.call("hatch_end_%d" % int(e), Vector3(e, h + rt + 0.1, 0), Vector3(0.3, 0.2, hw + 0.6), "decor", "glow")
	hatches.append({ "tunnel": pre, "xf": xf * Transform3D(Basis.IDENTITY, Vector3(l * 0.5, h + rt * 0.5, 0)),
		"size": Vector3(hl, 0.1, hw) })
	# The walls: glass between hull bands.
	for s: float in [-1.0, 1.0]:
		var z := s * (w * 0.5 + 0.2)
		box.call("base_%d" % int(s), Vector3(l * 0.5, 0.5, z), Vector3(l, 1.0, 0.4), "solid", "hull")
		box.call("glass_%d" % int(s), Vector3(l * 0.5, (1.0 + h - 0.4) * 0.5, z), Vector3(l, h - 1.4, 0.3), "solid", "glass")
		box.call("top_%d" % int(s), Vector3(l * 0.5, h - 0.2, z), Vector3(l, 0.4, 0.4), "solid", "hull")
		box.call("strip_%d" % int(s), Vector3(l * 0.5, 0.05, s * (w * 0.5 - 0.4)), Vector3(l, 0.06, 0.2), "decor", "glow")
		# The roof walk's railings, along both edges.
		box.call("roof_rail_%d" % int(s), Vector3(l * 0.5, h + rt + RAIL_H * 0.5, s * (w * 0.5 + 0.35)), Vector3(l, RAIL_H, 0.12), "solid", "rail")
		box.call("roof_rail_top_%d" % int(s), Vector3(l * 0.5, h + rt + RAIL_H + 0.04, s * (w * 0.5 + 0.35)), Vector3(l, 0.08, 0.18), "decor", "glow")
	var ribs := maxi(1, floori(l / 8.0))
	for k in ribs + 1:
		var x := l * k / ribs
		for s: float in [-1.0, 1.0]:
			box.call("rib_%d_%d" % [k, int(s)], Vector3(x, h * 0.5, s * (w * 0.5 + 0.45)), Vector3(0.5, h + 0.6, 0.3), "decor", "trim")


## Out on a tunnel's roof walk (the station's frame): between its railings, up to
## a few metres over it. Not aboard (you are outside), but not fallen out either.
func on_roof(local: Vector3) -> bool:
	for tn in tunnels:
		var l := (tn.xf as Transform3D).affine_inverse() * local
		if l.x >= -1.0 and l.x <= float(tn.length) + 1.0 and absf(l.z) <= tunnel_w * 0.5 + 1.0 \
				and l.y >= tunnel_h - 0.5 and l.y <= tunnel_h + 6.0:
			return true
	return false


## The covered landing bay: round, the port pit's size. A round deck with an apron
## out past the mouth, a curved wall open on the far side from its tower (the mouth,
## closed by the curved shield: SpaceStation) and at the back (the tunnel's door), a
## roof with a raised crown, glow round the floor, radial beams and the pads.
func _bay() -> void:
	if bay.is_empty():
		return
	var xf: Transform3D = bay.xf
	var c: Vector2 = bay.c
	var r := float(bay.r)
	var h := float(bay.height)
	var ap := float(bay.apron)
	var half := float(bay.mouth)
	var out := (bay.dir as Vector2).angle()
	var chord := 2.0 * r * sin(half)
	var mouth_gap := [out, r * half + 0.3]               # gaps are half widths along the arc
	var door_gap := [out + PI, tunnel_w * 0.5 + 0.1]
	var box := func(nm: String, at: Vector3, size: Vector3, kind: String, finish: String):
		_add("bay_" + nm, xf * Transform3D(Basis.IDENTITY, at), size, kind, finish)
	_ring("bay_deck", c, 0.0, r + 0.5, -plate, 0.0, "floor", "deck")
	box.call("apron", Vector3(r * cos(half) + (r - r * cos(half) + ap) * 0.5, -plate * 0.5, 0),
		Vector3(r - r * cos(half) + ap, plate, chord + 2.0), "floor", "deck")
	_ring("bay_wall", c, r, r + 1.0, 0.0, h, "solid", "hull", [mouth_gap, door_gap])
	_ring("bay_door_head", c, r, r + 1.0, tunnel_h, h, "solid", "hull",
		[[out, PI * (r + 0.5) - tunnel_w * 0.5 - 0.2]], 1)
	_ring("bay_band", c, r - 0.12, r, 6.0, 6.4, "decor", "glow", [mouth_gap, door_gap])
	_ring("bay_floor_glow", c, r - 2.2, r - 1.8, 0.0, 0.06, "decor", "glow", [mouth_gap, door_gap])
	# The roof, its crown, and the lip over the mouth.
	_ring("bay_roof", c, 0.0, r + 1.0, h, h + plate, "solid", "hull")
	_ring("bay_crown", c, 0.0, r * 0.62, h + plate, h + plate + 3.0, "solid", "hull", [], 32)
	_ring("bay_crown_glow", c, r * 0.62, r * 0.64, h + plate + 1.0, h + plate + 1.6, "decor", "glow", [], 32)
	_ring("bay_lip", c, r - 0.4, r + 1.6, h - 1.0, h + plate + 0.6, "solid", "trim", [[out + PI, PI * r - r * half - 0.3]])
	_ring("bay_lip_glow", c, r - 0.5, r - 0.4, h - 1.2, h - 0.9, "decor", "glow", [[out + PI, PI * r - r * half]])
	for s: float in [-1.0, 1.0]:
		var a := out + s * half
		_radial("bay_post_%d" % int(s), c, a, r - 0.6, r + 1.8, -plate, h + plate + 0.6, 2.4, "solid", "trim")
		box.call("guide_%d" % int(s), Vector3((r * cos(half) + ap) * 0.5, 0.04, s * (chord * 0.5 - 3.0)),
			Vector3(r * cos(half) + ap, 0.06, 0.5), "decor", "glow")
	box.call("door_glow", Vector3(-r + 0.25, tunnel_h + 0.3, 0), Vector3(0.1, 0.3, tunnel_w + 0.2), "decor", "glow")
	# Radial beams under the roof, and the pads.
	for k in 8:
		_radial("bay_beam_%d" % k, c, out + PI / 8.0 + k * PI / 4.0, 2.0, r - 0.2, h - 1.6, h, 1.2, "decor", "trim")
	for p in pads():
		var lp: Vector2 = p.local
		var pr := float(p.radius)
		box.call("pad_" + str(p.id), Vector3(lp.x, 0.06, lp.y), Vector3(pr * 2.0, 0.12, pr * 2.0), "floor", "pad")
