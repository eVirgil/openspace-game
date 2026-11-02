class_name CruiserHull
extends RefCounted
## Issue #193: the Remnant's star cruiser, holding orbit over the home planet. The
## wreck in the desert (StarcruiserWreck) remade whole and clean: a 690 m hull with
## a landing bay in its starboard flank, a corridor aft to a stack of ramps by the
## engines, and the bridge on top in a tower of windows.
##
## Pure: every part is a box in the cruiser's own frame, and every place the crew,
## the pads and the docking autopilot use is a point in it. The same parts are what
## you walk on (WorldScenery's landmark colliders), what a ship lands on and flies
## into (WorldGround) and what you see (RemnantCruiser merges them into a few
## meshes). Its numbers and its crew are data: content/core/cruiser/remnant_cruiser.json.
##
## The frame: x to starboard (the bay side, turned to face the port), y up, z from
## the bow (-) to the stern (+). The cruiser holds its own attitude in orbit: its
## decks are level with the port's (world up), not with the ball under it, and its
## gravity is square to them (PlanetSphere.gravity_zones). So aboard, up is world up,
## exactly as in town, and everything that walks, sees and paths (the crew, their
## navmesh, the droids, the player) works there unchanged. Seen from outside it
## rides rolled to the ground below it, its bay turned to the planet and the port.
##
## The parts are { id, size, xf (its own frame in the cruiser's), finish, kind:
## "floor" (stood on: a deck, a ramp, a landing) or "solid", nav (part of the
## walkable interior the crew's navmesh is baked from) }.

const DATA_PATH := "res://content/core/cruiser/remnant_cruiser.json"
const LANDMARK_KIND := "cruiser"

## The hull's cross-section, starboard half, at full size (x, y): the flat flank
## wall the bay opens in, the shoulder up to the flat dorsal deck, the lower slope
## down to the flat keel. Mirrored for port.
const HULL := [Vector2(54, -14), Vector2(54, 14), Vector2(26, 42), Vector2(-26, 42),
	Vector2(-54, 14), Vector2(-54, -14), Vector2(-30, -36), Vector2(30, -36)]
const FACETS := ["flank_s", "shoulder_s", "top", "shoulder_p", "flank_p", "lower_p", "keel", "lower_s"]
## Stations along the keel: z, then the cross-section's x and y scale there. The bow
## is a wedge (narrower than it is flat); aft of z = -150 the hull is full size.
const STATIONS := [[-345.0, 0.08, 0.30], [-305.0, 0.30, 0.48], [-265.0, 0.48, 0.62],
	[-225.0, 0.65, 0.76], [-188.0, 0.82, 0.88], [-150.0, 1.0, 1.0], [-90.0, 1.0, 1.0],
	[-30.0, 1.0, 1.0], [30.0, 1.0, 1.0], [90.0, 1.0, 1.0], [150.0, 1.0, 1.0],
	[210.0, 1.0, 1.0], [270.0, 1.0, 1.0], [330.0, 1.0, 1.0]]
const PLATE := 2.0                 ## hull plating thickness

const DECK_Y := -14.0              ## the bay, corridor and shaft floors (their top)
## The bay: open to space along the starboard flank, between these.
const BAY_X := Vector2(-48.0, 54.0)
const BAY_Z := Vector2(-146.0, 26.0)
const BAY_TOP := 34.0
const APRON_X := 62.0              ## the bay floor runs out past the flank as a landing apron
## The corridor aft from the bay to the ramp shaft.
const HALL_HALF := 5.0
const HALL_TOP := -4.0
## The ramp shaft by the engines: six flights up to the bridge.
const SHAFT_X := 24.0
const SHAFT_Z := Vector2(270.0, 326.0)
const FLIGHT_Z := Vector2(278.0, 318.0)
const FLIGHT_RISE := 12.0
const FLIGHTS := 6
const FLIGHT_X := 8.0              ## even flights climb aft at +x, odd ones fore at -x
const FLIGHT_W := 8.0
const LANDING_HALF := 14.0
## The bridge, in the tower on the dorsal deck.
const BRIDGE_Y := DECK_Y + FLIGHT_RISE * FLIGHTS     ## 58: the top landing's floor
const BRIDGE_X := 28.0
const BRIDGE_Z := Vector2(216.0, 270.0)
const BRIDGE_TOP := 72.0
const PIT_Y := BRIDGE_Y - 3.0      ## the crew pits either side of the walkway
const WALK_HALF := 7.0
const TOWER_X := 30.0
const TOWER_Z := Vector2(212.0, 330.0)
const TOWER_TOP := 76.0
## The engines on the stern: their housings' fore and aft faces, and how far each
## main bell runs (an aux bell half that) back to its mouth, out past its housing.
const HOUSING_Z := Vector2(333.0, 347.0)
const BELL_LENGTH := 20.0
## Where the cruiser's own gravity holds (its frame): the hull and a margin round it.
const GRAVITY_BOX := AABB(Vector3(-80, -60, -380), Vector3(160, 160, 760))

static var _parts: Array = []
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else {}
	return _data


# ------------------------------------------------------------------ the frame

## Where the cruiser hangs over the ball and how it is turned: over map point `at`
## ([east, south] metres along the ground from the port), `altitude` metres up, level
## with the port (its y is world up), its starboard flank (the bay) turned toward
## the port across the sky, then `yaw_deg` about its up.
static func frame_for(sp: PlanetSphere, lm: Dictionary) -> Transform3D:
	var at := WorldGround._v3(lm.get("at", [6500, 0, 0]))
	var dir := sp.map_dir(at.x, at.z)
	var pos := sp.center + dir * (sp.radius + float(lm.get("altitude", 7000.0)))
	var to_port := Vector3(-pos.x, 0.0, -pos.z)
	if to_port.length() < 0.01:
		to_port = Vector3.LEFT
	var x := to_port.normalized().rotated(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0))))
	return Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), pos)


## Issue #193: register the cruiser with the world's ground (called by WorldGround for
## a landmark of kind "cruiser"): every part as a box in its own frame, kept off the
## landmark look (RemnantCruiser draws it), and its frame on each box so the scene
## can find it again (frame()). Nothing on a world with no ball.
static func add_to_ground(ground: WorldGround, lm: Dictionary) -> void:
	var sp := ground.sphere()
	if sp == null:
		return
	var xf := frame_for(sp, lm)
	var prefix := str(lm.get("id", "remnant_cruiser")) + "/"
	for p in parts():
		if str(p.kind) == "decor":
			continue                  # drawn only
		ground.add_box(prefix + str(p.id), str(p.kind), -(p.size as Vector3) * 0.5, (p.size as Vector3) * 0.5,
			"", false, xf * (p.xf as Transform3D))
		ground.boxes[-1]["cruiser_frame"] = xf
	sp.add_gravity_zone(xf, GRAVITY_BOX)


## The cruiser's frame from the ground's boxes, or identity when it is not there.
static func frame(ground: WorldGround, id: String = "remnant_cruiser") -> Transform3D:
	if ground == null:
		return Transform3D.IDENTITY
	for b in ground.boxes:
		if b.has("cruiser_frame") and str(b.id).begins_with(id + "/"):
			return b.cruiser_frame
	return Transform3D.IDENTITY


static func has_cruiser(ground: WorldGround, id: String = "remnant_cruiser") -> bool:
	return frame(ground, id) != Transform3D.IDENTITY


## The cruiser's landmark in a world (content/core/worlds/*.json), or {}.
static func landmark(world: Dictionary) -> Dictionary:
	for lm in world.get("landmarks", []):
		if str(lm.get("kind", "")) == LANDMARK_KIND:
			return lm
	return {}


# ------------------------------------------------------------------ places

## A landing pad by id (the data's "pads"): { id, at: Vector3 (on the deck), yaw,
## radius, ship, scale }.
static func pads() -> Array:
	var out: Array = []
	for p in data().get("pads", []):
		var c := WorldGround._v3(p.get("at", [0, 0, 0]))
		out.append({ "id": str(p.get("id", "")), "at": Vector3(c.x, DECK_Y, c.z),
			"yaw": deg_to_rad(float(p.get("yaw_deg", 90.0))), "radius": float(p.get("radius", 11.0)),
			"ship": str(p.get("ship", "")), "scale": float(p.get("scale", 1.0)), "flyable": bool(p.get("flyable", false)) })
	return out


static func pad(id: String) -> Dictionary:
	for p in pads():
		if p.id == id:
			return p
	return {}


## The empty pad Z sets your ship down on.
static func dock_pad() -> Dictionary:
	return pad(str(data().get("dock", {}).get("pad", "")))


## Inside the walkable interior (the bay, the corridor and its rooms, the shaft, the
## bridge), in the cruiser's frame. For the detail tier and the fall guard.
static func aboard(local: Vector3) -> bool:
	if local.y < DECK_Y - 3.0 or local.y > TOWER_TOP:
		return false
	if local.x >= BAY_X.x and local.x <= BAY_X.y and local.z >= BAY_Z.x and local.z <= BAY_Z.y and local.y <= BAY_TOP:
		return true
	if absf(local.x) <= 27.0 and local.z >= BAY_Z.y and local.z <= SHAFT_Z.x and local.y <= HALL_TOP:
		return true
	if absf(local.x) <= SHAFT_X and local.z >= SHAFT_Z.x and local.z <= SHAFT_Z.y:
		return true
	return absf(local.x) <= TOWER_X and local.z >= BRIDGE_Z.x - 2.0 and local.z <= BRIDGE_Z.y and local.y >= BRIDGE_Y - 4.0


## The foot of the ramp stack: where the first flight leaves the shaft's floor
## (the fleet chapter's "infiltrate" waypoint).
static func stairs_foot() -> Vector3:
	return Vector3(FLIGHT_X, DECK_Y, FLIGHT_Z.x)


## In the ramp shaft (cruiser frame), at any height: the stairs are reached.
static func at_stairs(local: Vector3) -> bool:
	return absf(local.x) <= SHAFT_X and local.z >= SHAFT_Z.x and local.z <= SHAFT_Z.y \
		and local.y >= DECK_Y - 3.0 and local.y <= TOWER_TOP


## The docking path from `local` (the ship, cruiser frame) to above the dock pad:
## round the hull (over it from the port side, under it from below), out to a point
## off the bay's mouth, in through it, and over the pad. The last point is where
## the normal landing takes over.
static func dock_path(local: Vector3) -> Array:
	var dc: Dictionary = data().get("dock", {})
	var p := dock_pad()
	var pz: float = p.get("at", Vector3.ZERO).z
	var px: float = p.get("at", Vector3.ZERO).x
	var hold := float(dc.get("hold_y", 2.0))
	var off := float(dc.get("approach_x", 230.0))
	var over := float(dc.get("over_y", 150.0))
	var under := float(dc.get("under_y", -90.0))
	var out: Array = []
	var beside := absf(local.z) <= 360.0
	if local.x < 70.0 and beside:
		if local.y >= 45.0 or (local.x < -70.0 and local.y > -40.0):
			out.append(Vector3(local.x, maxf(local.y, over), local.z))
			out.append(Vector3(off, maxf(local.y, over), pz))
		elif local.y <= -40.0:
			out.append(Vector3(local.x, minf(local.y, under), local.z))
			out.append(Vector3(off, minf(local.y, under), pz))
		else:
			out.append(Vector3(off, local.y, local.z))     # fore or aft of the bay, alongside
	out.append(Vector3(off, hold, pz))
	out.append(Vector3(APRON_X + 10.0, hold, pz))
	out.append(Vector3(px, hold, pz))
	return out


# ------------------------------------------------------------------ parts

static func parts() -> Array:
	if _parts.is_empty():
		_parts = _build()
	return _parts


static func _build() -> Array:
	var out: Array = []
	_hull(out)
	_bay(out)
	_hall(out)
	_shaft(out)
	_bridge(out)
	_computers(out)
	_tower(out)
	_dorsal(out)
	return out


## Plates between consecutive stations, facet by facet, each tilted to meet the next
## station's, so the bow is one smooth wedge. The starboard flank is open over the
## bay; the dorsal deck under the tower is the tower's floor.
static func _hull(out: Array) -> void:
	for s in STATIONS.size() - 1:
		var a: Array = STATIONS[s]
		var b: Array = STATIONS[s + 1]
		for f in HULL.size():
			var facet: String = FACETS[f]
			if facet == "flank_s" and float(a[0]) >= BAY_Z.x - 5.0 and float(b[0]) <= BAY_Z.y + 5.0:
				continue
			if facet == "top" and float(a[0]) >= TOWER_Z.x - 5.0:
				continue
			var p0 := _corner(f, a)
			var q0 := _corner((f + 1) % HULL.size(), a)
			var p1 := _corner(f, b)
			var q1 := _corner((f + 1) % HULL.size(), b)
			_plate(out, "hull_%d_%s" % [s, facet], p0, q0, p1, q1, "hull")
		# A raised armour band at each full-size station: the hull's ribs, from outside.
		if float(a[1]) >= 1.0:
			for f in HULL.size():
				if FACETS[f] == "flank_s" and float(a[0]) > BAY_Z.x and float(a[0]) < BAY_Z.y:
					continue
				if FACETS[f] == "top" and float(a[0]) >= TOWER_Z.x - 5.0:
					continue
				var p := _corner(f, a)
				var q := _corner((f + 1) % HULL.size(), a)
				var mid := (p + q) * 0.5
				var n := _normal(p, q)
				_box(out, "band_%d_%s" % [s, FACETS[f]], Vector3((q - p).length() + 1.0, 1.2, 4.0),
					mid + n * 1.4, "trim", _plate_basis(q - p, Vector3(0, 0, 1)))
	# The bow's point and the stern's bulkhead close the hull.
	var tip: Array = STATIONS[0]
	_box(out, "bow_cap", Vector3(108.0 * float(tip[1]) + 2.0, 78.0 * float(tip[2]), PLATE),
		Vector3(0, 3.0 * float(tip[2]), float(tip[0]) - 1.0), "trim")
	_stern_cap(out, float((STATIONS[-1] as Array)[0]) + PLATE)


## The stern's bulkhead at z, the hull's own cross-section (a box would stick out
## past its corners): one box per facet, from the facet in to the keel's middle
## line. Each covers the wedge between its facet and the middle, so together they
## fill the section exactly, and none reaches outside it.
static func _stern_cap(out: Array, z: float) -> void:
	for f in HULL.size():
		var p := Vector3((HULL[f] as Vector2).x, (HULL[f] as Vector2).y, z)
		var q := Vector3((HULL[(f + 1) % HULL.size()] as Vector2).x, (HULL[(f + 1) % HULL.size()] as Vector2).y, z)
		var n := _normal(p, q)
		var depth := Vector3(p.x, p.y, 0).dot(n)        # from the facet in to the middle line
		_box(out, "stern_bulkhead_%s" % FACETS[f], Vector3((q - p).length() + 0.8, depth, PLATE * 2.0),
			(p + q) * 0.5 - n * depth * 0.5, "hull", _plate_basis(q - p, Vector3(0, 0, 1)))


## A hull corner `i` at station `st` ([z, sx, sy]).
static func _corner(i: int, st: Array) -> Vector3:
	var v: Vector2 = HULL[i]
	return Vector3(v.x * float(st[1]), v.y * float(st[2]) + (1.0 - float(st[2])) * 6.0, float(st[0]))


## The outward normal of the facet edge p -> q (the cross-section is wound anticlockwise).
static func _normal(p: Vector3, q: Vector3) -> Vector3:
	var e := q - p
	return Vector3(e.y, -e.x, 0).normalized()


## A basis whose x runs along `along` and whose z is as close to `length_dir` as it
## can be while square to it.
static func _plate_basis(along: Vector3, length_dir: Vector3) -> Basis:
	var x := along.normalized()
	var z := (length_dir - x * length_dir.dot(x)).normalized()
	return Basis(x, z.cross(x), z)


## A hull plate from edge p0-q0 (one station) to edge p1-q1 (the next), as one box
## tilted between them.
static func _plate(out: Array, id: String, p0: Vector3, q0: Vector3, p1: Vector3, q1: Vector3, finish: String) -> void:
	var m0 := (p0 + q0) * 0.5
	var m1 := (p1 + q1) * 0.5
	var along := ((q0 - p0) + (q1 - p1)) * 0.5
	var basis := _plate_basis(along, m1 - m0)
	var width := maxf((q0 - p0).length(), (q1 - p1).length()) + 0.8
	var n := _normal(p0 + (p1 - p0) * 0.5, q0 + (q1 - q0) * 0.5)
	if basis.y.dot(n) < 0.0:
		basis = Basis(basis.x, -basis.y, -basis.z)
	_box(out, id, Vector3(width, PLATE, (m1 - m0).length() + 0.6), (m0 + m1) * 0.5 - n * PLATE * 0.5, finish, basis)


## The landing bay: a deck 172 m long running out over the flank as an apron, a
## ceiling, its port, bow and stern walls (a door aft to the corridor), a gantry
## along the port wall reached by a ramp, the pads, and cargo stacked for cover.
static func _bay(out: Array) -> void:
	var length := BAY_Z.y - BAY_Z.x
	var mid_z := (BAY_Z.x + BAY_Z.y) * 0.5
	_slab(out, "bay_deck", Vector2(BAY_X.x, APRON_X), BAY_Z, DECK_Y, "deck", 3.0)
	_box(out, "bay_ceiling", Vector3(30.0 - BAY_X.x, 2, length), Vector3((BAY_X.x + 30.0) * 0.5, BAY_TOP + 1.0, mid_z), "wall")
	_wall(out, "bay_port_wall", Vector3(BAY_X.x - 1.0, DECK_Y, BAY_Z.x), Vector3(BAY_X.x - 1.0, BAY_TOP, BAY_Z.y), 2.0)
	_wall(out, "bay_bow_wall", Vector3(BAY_X.x, DECK_Y, BAY_Z.x - 1.0), Vector3(BAY_X.y, BAY_TOP, BAY_Z.x - 1.0), 2.0)
	# The stern wall, with the corridor's door in it.
	_wall(out, "bay_stern_wall_p", Vector3(BAY_X.x, DECK_Y, BAY_Z.y + 1.0), Vector3(-HALL_HALF - 1.0, BAY_TOP, BAY_Z.y + 1.0), 2.0)
	_wall(out, "bay_stern_wall_s", Vector3(HALL_HALF + 1.0, DECK_Y, BAY_Z.y + 1.0), Vector3(BAY_X.y, BAY_TOP, BAY_Z.y + 1.0), 2.0)
	_wall(out, "bay_stern_lintel", Vector3(-HALL_HALF - 1.0, HALL_TOP, BAY_Z.y + 1.0), Vector3(HALL_HALF + 1.0, BAY_TOP, BAY_Z.y + 1.0), 2.0)
	# The lip of the flank above the opening, and the deck's edge below it.
	_box(out, "bay_lintel", Vector3(3, 4, length + 4.0), Vector3(BAY_X.y, 14.0, mid_z), "trim")
	# The port gantry: a deck along the wall at mid height and a ramp up to it.
	var g_y := DECK_Y + 16.0
	_slab(out, "bay_gantry", Vector2(BAY_X.x, BAY_X.x + 8.0), Vector2(BAY_Z.x + 6.0, -16.0), g_y, "grate", 0.6)
	_ramp(out, "bay_gantry_ramp", Vector3(BAY_X.x + 4.0, g_y, -16.0), Vector3(BAY_X.x + 4.0, DECK_Y, 20.0), 8.0)
	_rail(out, "bay_gantry_rail", Vector3(BAY_X.x + 8.0, g_y, BAY_Z.x + 6.0), Vector3(BAY_X.x + 8.0, g_y, -16.0))
	_rail(out, "bay_gantry_ramp_rail", Vector3(BAY_X.x + 8.0, g_y, -16.0), Vector3(BAY_X.x + 8.0, DECK_Y, 20.0))
	_rail(out, "bay_gantry_end_rail", Vector3(BAY_X.x, g_y, BAY_Z.x + 6.0), Vector3(BAY_X.x + 8.0, g_y, BAY_Z.x + 6.0))
	for i in 6:
		var z := BAY_Z.x + 14.0 + i * 24.0
		_box(out, "bay_gantry_strut_%d" % i, Vector3(0.8, g_y - DECK_Y - 0.6, 0.8),
			Vector3(BAY_X.x + 7.4, (DECK_Y + g_y - 0.6) * 0.5, z), "trim", Basis.IDENTITY, true)
	# Columns down the bay's middle hold the ceiling up, and frame it from the mouth.
	for i in 5:
		var z := BAY_Z.x + 18.0 + i * 34.0
		_box(out, "bay_column_%d" % i, Vector3(2.4, BAY_TOP - DECK_Y, 2.4), Vector3(-26.0, (DECK_Y + BAY_TOP) * 0.5, z), "trim", Basis.IDENTITY, true)
	# Pads: painted plates a hand's breadth over the deck.
	for p in pads():
		var r: float = p.radius
		_box(out, "pad_" + str(p.id), Vector3(r * 2.0, 0.1, r * 2.0), (p.at as Vector3) + Vector3(0, 0.05, 0), "pad")
		out[-1]["kind"] = "floor"
	# Cargo along the port side: cover for a fight, and scale.
	var rng := RandomNumberGenerator.new()
	rng.seed = 193
	for i in 9:
		var at := Vector3(BAY_X.x + 12.0 + rng.randf_range(0.0, 10.0), DECK_Y, BAY_Z.x + 12.0 + i * 18.0)
		var s := Vector3(rng.randf_range(2.4, 4.2), rng.randf_range(1.4, 2.6), rng.randf_range(2.4, 4.2))
		_box(out, "bay_cargo_%d" % i, s, at + Vector3(0, s.y * 0.5, 0), "cargo",
			Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), true)
		if i % 3 == 0:
			_box(out, "bay_cargo_top_%d" % i, s * Vector3(0.8, 0.9, 0.8), at + Vector3(0, s.y * 1.45, 0), "cargo",
				Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), true)


## The corridor aft to the shaft: walls with door frames every 24 m, a ceiling, and
## two rooms off it (an armoury to starboard, a crew room to port).
static func _hall(out: Array) -> void:
	var z0 := BAY_Z.y + 2.0
	var z1 := SHAFT_Z.x
	# From under the bay's stern door (no gap between the decks) to the shaft's floor.
	_slab(out, "hall_deck", Vector2(-HALL_HALF - 1.0, HALL_HALF + 1.0), Vector2(BAY_Z.y - 1.0, z1 + 1.0), DECK_Y, "deck", 2.0)
	_box(out, "hall_ceiling", Vector3(HALL_HALF * 2.0 + 2.0, 1, z1 - z0), Vector3(0, HALL_TOP + 0.5, (z0 + z1) * 0.5), "wall")
	var rooms := [["armoury", 1.0, Vector2(110, 134)], ["crew", -1.0, Vector2(176, 200)]]
	for side: float in [-1.0, 1.0]:
		var gaps: Array = []
		for r in rooms:
			if float(r[1]) == side:
				gaps.append(r[2])
		var from := z0
		for gz in gaps + [Vector2(z1, z1)]:
			var g: Vector2 = gz
			if g.x - from > 0.5:
				_wall(out, "hall_wall_%s_%d" % ["s" if side > 0 else "p", int(from)],
					Vector3(side * (HALL_HALF + 0.5), DECK_Y, from), Vector3(side * (HALL_HALF + 0.5), HALL_TOP, g.x), 1.0)
			if g.y > g.x:
				# The room's door: a gap of 6 m in the middle of its span.
				var door := Vector2((g.x + g.y) * 0.5 - 3.0, (g.x + g.y) * 0.5 + 3.0)
				_wall(out, "hall_wall_%s_%d_a" % ["s" if side > 0 else "p", int(g.x)],
					Vector3(side * (HALL_HALF + 0.5), DECK_Y, g.x), Vector3(side * (HALL_HALF + 0.5), HALL_TOP, door.x), 1.0)
				_wall(out, "hall_wall_%s_%d_b" % ["s" if side > 0 else "p", int(g.x)],
					Vector3(side * (HALL_HALF + 0.5), DECK_Y, door.y), Vector3(side * (HALL_HALF + 0.5), HALL_TOP, g.y), 1.0)
			from = g.y
	for r in rooms:
		var side: float = r[1]
		var zs: Vector2 = r[2]
		var xs := Vector2(HALL_HALF + 1.0, 26.0) if side > 0 else Vector2(-26.0, -HALL_HALF - 1.0)
		var room := str(r[0])
		_slab(out, "%s_deck" % room, xs, zs, DECK_Y, "deck", 2.0)
		_box(out, "%s_ceiling" % room, Vector3(xs.y - xs.x, 1, zs.y - zs.x), Vector3((xs.x + xs.y) * 0.5, HALL_TOP + 0.5, (zs.x + zs.y) * 0.5), "wall")
		var outer := side * 26.5
		_wall(out, "%s_outer" % room, Vector3(outer, DECK_Y, zs.x), Vector3(outer, HALL_TOP, zs.y), 1.0)
		_wall(out, "%s_fore" % room, Vector3(xs.x, DECK_Y, zs.x - 0.5), Vector3(xs.y, HALL_TOP, zs.x - 0.5), 1.0)
		_wall(out, "%s_aft" % room, Vector3(xs.x, DECK_Y, zs.y + 0.5), Vector3(xs.y, HALL_TOP, zs.y + 0.5), 1.0)
		# Lockers or bunks along the outer wall, a table in the middle.
		for i in 4:
			var z := zs.x + 3.5 + i * 5.6
			_box(out, "%s_rack_%d" % [room, i], Vector3(1.6, 3.0, 4.0), Vector3(side * 24.6, DECK_Y + 1.5, z), "console", Basis.IDENTITY, true)
		_box(out, "%s_table" % room, Vector3(4.0, 1.0, 8.0), Vector3(side * 15.0, DECK_Y + 0.5, (zs.x + zs.y) * 0.5), "cargo", Basis.IDENTITY, true)
	# Door frames down the corridor, and a light strip along the ceiling (drawn only).
	for i in int((z1 - z0) / 24.0) + 1:
		var z := z0 + 6.0 + i * 24.0
		if z > z1 - 2.0:
			break
		for side: float in [-1.0, 1.0]:
			_box(out, "hall_frame_%d_%s" % [i, "s" if side > 0 else "p"], Vector3(0.8, HALL_TOP - DECK_Y, 1.2),
				Vector3(side * (HALL_HALF - 0.4), (DECK_Y + HALL_TOP) * 0.5, z), "trim", Basis.IDENTITY, true)
		_box(out, "hall_frame_top_%d" % i, Vector3(HALL_HALF * 2.0, 0.8, 1.2), Vector3(0, HALL_TOP - 0.4, z), "trim")
	_box(out, "hall_light", Vector3(1.2, 0.1, z1 - z0 - 4.0), Vector3(0, HALL_TOP - 0.05, (z0 + z1) * 0.5), "glow")
	out[-1]["kind"] = "decor"


## The ramp shaft: six flights switching back up a tall well by the stern bulkhead,
## with landings at both ends, rails on every open edge, and the reactor glowing
## through the grille in the aft wall.
static func _shaft(out: Array) -> void:
	var z0 := SHAFT_Z.x
	var z1 := SHAFT_Z.y
	var top := TOWER_TOP
	_slab(out, "shaft_floor", Vector2(-SHAFT_X, SHAFT_X), Vector2(z0, z1), DECK_Y, "deck", 2.0)
	for side: float in [-1.0, 1.0]:
		_wall(out, "shaft_wall_%s" % ("s" if side > 0 else "p"), Vector3(side * (SHAFT_X + 1.0), DECK_Y, z0),
			Vector3(side * (SHAFT_X + 1.0), top, z1), 2.0)
	# Fore wall: the corridor comes in at the bottom; above it the bridge's own wall.
	_wall(out, "shaft_fore_p", Vector3(-SHAFT_X, DECK_Y, z0 - 1.0), Vector3(-HALL_HALF - 1.0, HALL_TOP, z0 - 1.0), 2.0)
	_wall(out, "shaft_fore_s", Vector3(HALL_HALF + 1.0, DECK_Y, z0 - 1.0), Vector3(SHAFT_X, HALL_TOP, z0 - 1.0), 2.0)
	_wall(out, "shaft_fore_mid", Vector3(-SHAFT_X, HALL_TOP, z0 - 1.0), Vector3(SHAFT_X, BRIDGE_Y - 4.0, z0 - 1.0), 2.0)
	_wall(out, "shaft_aft", Vector3(-SHAFT_X, DECK_Y, z1 + 1.0), Vector3(SHAFT_X, top, z1 + 1.0), 2.0)
	# The reactor grille: a lit panel on the aft wall with bars across it.
	_box(out, "reactor_glow", Vector3(30, 44, 0.3), Vector3(0, 12.0, z1 - 0.3), "reactor")
	out[-1]["kind"] = "decor"
	for i in 9:
		_box(out, "reactor_bar_%d" % i, Vector3(0.8, 46, 0.8), Vector3(-14.0 + i * 3.5, 12.0, z1 - 0.9), "trim")
	for i in 5:
		_box(out, "reactor_rung_%d" % i, Vector3(32, 0.8, 0.8), Vector3(0, -8.0 + i * 10.0, z1 - 1.2), "trim")
	# The flights and their landings.
	for k in FLIGHTS:
		var y0 := DECK_Y + k * FLIGHT_RISE
		var y1 := y0 + FLIGHT_RISE
		var aft := k % 2 == 0
		var x := FLIGHT_X if aft else -FLIGHT_X
		var a := Vector3(x, y0, FLIGHT_Z.x if aft else FLIGHT_Z.y)
		var b := Vector3(x, y1, FLIGHT_Z.y if aft else FLIGHT_Z.x)
		_ramp(out, "flight_%d" % k, a, b, FLIGHT_W)
		var outer := x + signf(x) * FLIGHT_W * 0.5
		var inner := x - signf(x) * FLIGHT_W * 0.5
		_rail(out, "flight_%d_rail_out" % k, Vector3(outer, y0, a.z), Vector3(outer, y1, b.z))
		_rail(out, "flight_%d_rail_in" % k, Vector3(inner, y0, a.z), Vector3(inner, y1, b.z))
		# The landing it arrives on, across the shaft at its far end.
		var lz := Vector2(FLIGHT_Z.y, z1) if aft else Vector2(z0, FLIGHT_Z.x)
		if k < FLIGHTS - 1:
			_slab(out, "landing_%d" % k, Vector2(-LANDING_HALF, LANDING_HALF), lz, y1, "grate", 0.8)
			var edge := lz.x if aft else lz.y
			# Rails on its open side, leaving the gaps where flights leave and arrive.
			_gapped_rail(out, "landing_%d_rail" % k, edge, y1, LANDING_HALF)
			for sx: float in [-1.0, 1.0]:
				_rail(out, "landing_%d_rail_end_%d" % [k, int(sx)], Vector3(sx * LANDING_HALF, y1, lz.x), Vector3(sx * LANDING_HALF, y1, lz.y))
		# A light under every landing, drawn only.
		_box(out, "flight_%d_lamp" % k, Vector3(6, 0.2, 0.6), Vector3(0, y1 - 1.0, lz.x + 1.0 if aft else lz.y - 1.0), "glow")
		out[-1]["kind"] = "decor"


## The bridge: a long room on the tower's top deck. A walkway down its middle from
## the top of the ramps to a dais at the great window, sunken crew pits either side
## with rows of consoles, a holo table, and the window wall all round the bow end.
static func _bridge(out: Array) -> void:
	var z0 := BRIDGE_Z.x
	var z1 := BRIDGE_Z.y
	var pit_z := Vector2(z0 + 10.0, z1 - 8.0)
	_slab(out, "bridge_dais", Vector2(-TOWER_X, TOWER_X), Vector2(z0 - 2.0, pit_z.x), BRIDGE_Y, "bridge", 4.0)
	_slab(out, "bridge_walk", Vector2(-WALK_HALF, WALK_HALF), pit_z, BRIDGE_Y, "bridge", 4.0)
	_slab(out, "bridge_rear", Vector2(-TOWER_X, TOWER_X), Vector2(pit_z.y, z1 + 8.0), BRIDGE_Y, "bridge", 4.0)
	# The top of the ramps is the rear deck's aft end: rails over the shaft but where the last flight arrives.
	var arrive := Vector2(-FLIGHT_X - FLIGHT_W * 0.5, -FLIGHT_X + FLIGHT_W * 0.5)
	_rail(out, "top_landing_rail_p", Vector3(-SHAFT_X, BRIDGE_Y, z1 + 8.0), Vector3(arrive.x, BRIDGE_Y, z1 + 8.0))
	_rail(out, "top_landing_rail_s", Vector3(arrive.y, BRIDGE_Y, z1 + 8.0), Vector3(SHAFT_X, BRIDGE_Y, z1 + 8.0))
	for side: float in [-1.0, 1.0]:
		var xs := Vector2(WALK_HALF, BRIDGE_X) if side > 0 else Vector2(-BRIDGE_X, -WALK_HALF)
		var tag := "s" if side > 0 else "p"
		_slab(out, "pit_%s" % tag, xs, pit_z, PIT_Y, "deck", 1.0)
		# Steps down into the pit at its aft end.
		_ramp(out, "pit_%s_steps" % tag, Vector3(side * WALK_HALF, BRIDGE_Y, pit_z.y - 4.0),
			Vector3(side * (WALK_HALF + 7.0), PIT_Y, pit_z.y - 4.0), 5.0)
		# Rails along the walkway's edge, open at the steps; and round the dais's edge.
		_rail(out, "pit_%s_rail" % tag, Vector3(side * WALK_HALF, BRIDGE_Y, pit_z.x), Vector3(side * WALK_HALF, BRIDGE_Y, pit_z.y - 7.0))
		_rail(out, "dais_%s_rail" % tag, Vector3(side * WALK_HALF, BRIDGE_Y, pit_z.x), Vector3(side * BRIDGE_X, BRIDGE_Y, pit_z.x))
		_rail(out, "rear_%s_rail" % tag, Vector3(side * WALK_HALF, BRIDGE_Y, pit_z.y), Vector3(side * BRIDGE_X, BRIDGE_Y, pit_z.y))
		# Three rows of consoles in each pit, facing the window.
		for i in 3:
			var z := pit_z.x + 6.0 + i * 9.0
			_box(out, "console_%s_%d" % [tag, i], Vector3(xs.y - xs.x - 6.0, 1.2, 1.6),
				Vector3((xs.x + xs.y) * 0.5 + side * 1.0, PIT_Y + 0.6, z), "console", Basis.IDENTITY, true)
			_box(out, "screen_%s_%d" % [tag, i], Vector3(xs.y - xs.x - 7.0, 0.7, 0.1),
				Vector3((xs.x + xs.y) * 0.5 + side * 1.0, PIT_Y + 1.5, z + 0.5), "screen", Basis(Vector3.RIGHT, deg_to_rad(-25.0)))
			out[-1]["kind"] = "decor"
	# The holo table half way down the walkway, and its map glowing over it.
	var hz := holo_table().z
	_box(out, "holo_table", Vector3(5.0, 1.1, 5.0), Vector3(0, BRIDGE_Y + 0.55, hz), "console", Basis.IDENTITY, true)
	_box(out, "holo_top", Vector3(4.4, 0.08, 4.4), Vector3(0, BRIDGE_Y + 1.14, hz), "screen")
	out[-1]["kind"] = "decor"
	# The command rail at the window.
	_rail(out, "window_rail", Vector3(-BRIDGE_X + 2.0, BRIDGE_Y, z0 + 2.0), Vector3(BRIDGE_X - 2.0, BRIDGE_Y, z0 + 2.0))
	# The ceiling, and the bulkhead to the ramps behind, with its great door.
	_box(out, "bridge_ceiling", Vector3(BRIDGE_X * 2.0 + 4.0, 1.5, z1 - z0 + 4.0), Vector3(0, BRIDGE_TOP + 0.75, (z0 + z1) * 0.5), "wall")
	_wall(out, "bridge_aft_p", Vector3(-TOWER_X, BRIDGE_Y, z1 + 1.0), Vector3(-12.0, BRIDGE_TOP, z1 + 1.0), 2.0)
	_wall(out, "bridge_aft_s", Vector3(12.0, BRIDGE_Y, z1 + 1.0), Vector3(TOWER_X, BRIDGE_TOP, z1 + 1.0), 2.0)
	_wall(out, "bridge_aft_lintel", Vector3(-12.0, BRIDGE_Y + 8.0, z1 + 1.0), Vector3(12.0, BRIDGE_TOP, z1 + 1.0), 2.0)
	# Overhead light bars, drawn only.
	for i in 4:
		_box(out, "bridge_light_%d" % i, Vector3(BRIDGE_X * 1.6, 0.15, 0.8), Vector3(0, BRIDGE_TOP - 0.1, z0 + 8.0 + i * 13.0), "glow")
		out[-1]["kind"] = "decor"


## Computers all through the ship: monitors over the bridge's console rows and
## banks along the pits' outer edges, a screen on every rack in the corridor's two
## rooms and a terminal on each room's fore wall, terminals down the corridor's
## walls between the door frames, and one on every landing of the ramp shaft.
## Casings are "console" and solid (in the crew's navmesh too), their displays
## "screen" (drawn only, flush on a casing, each a live picture).
static func _computers(out: Array) -> void:
	var pit_z := Vector2(BRIDGE_Z.x + 10.0, BRIDGE_Z.y - 8.0)
	for side: float in [-1.0, 1.0]:
		var tag := "s" if side > 0 else "p"
		var mid_x := side * ((WALK_HALF + BRIDGE_X) * 0.5 + 1.0)
		for i in 3:
			var z := pit_z.x + 6.0 + i * 9.0
			for k in 3:
				var x := mid_x + (k - 1) * 5.0
				_box(out, "monitor_%s_%d_%d" % [tag, i, k], Vector3(2.4, 1.3, 0.08), Vector3(x, PIT_Y + 2.35, z - 0.15),
					"screen", Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
				out[-1]["kind"] = "decor"
				_box(out, "monitor_%s_%d_%d_stand" % [tag, i, k], Vector3(0.2, 0.8, 0.2), Vector3(x, PIT_Y + 1.5, z - 0.1), "trim")
				out[-1]["kind"] = "decor"
		# Banks of computers along the pit's outer edge, their screens facing in.
		for j in 3:
			var z := pit_z.x + 5.0 + j * 10.0
			var bx := side * (BRIDGE_X - 0.8)
			_box(out, "bank_%s_%d" % [tag, j], Vector3(1.6, 2.8, 6.0), Vector3(bx, PIT_Y + 1.4, z), "console", Basis.IDENTITY, true)
			_box(out, "bank_%s_%d_screen" % [tag, j], Vector3(0.08, 1.3, 4.6), Vector3(bx - side * 0.84, PIT_Y + 1.9, z), "screen")
			out[-1]["kind"] = "decor"
	# The corridor's rooms: a screen on each rack, a terminal on the fore wall.
	for r in [["armoury", 1.0, Vector2(110, 134)], ["crew", -1.0, Vector2(176, 200)]]:
		var side: float = r[1]
		var zs: Vector2 = r[2]
		var room := str(r[0])
		for i in 4:
			var z := zs.x + 3.5 + i * 5.6
			_box(out, "%s_rack_%d_screen" % [room, i], Vector3(0.08, 1.0, 2.8), Vector3(side * (24.6 - 0.84), DECK_Y + 2.1, z), "screen")
			out[-1]["kind"] = "decor"
		_box(out, "%s_terminal" % room, Vector3(4.0, 1.1, 1.2), Vector3(side * 16.0, DECK_Y + 0.55, zs.x + 0.9), "console", Basis.IDENTITY, true)
		_box(out, "%s_terminal_screen" % room, Vector3(3.6, 1.6, 0.08), Vector3(side * 16.0, DECK_Y + 2.3, zs.x + 0.1), "screen")
		out[-1]["kind"] = "decor"
	# Terminals down the corridor, between the door frames, on alternate walls.
	var z0 := BAY_Z.y + 2.0
	var i := 0
	var z := z0 + 18.0
	while z < SHAFT_Z.x - 4.0:
		var side := 1.0 if i % 2 == 0 else -1.0
		var wx := side * HALL_HALF
		_box(out, "hall_terminal_%d" % i, Vector3(0.5, 1.6, 1.8), Vector3(wx - side * 0.25, DECK_Y + 1.7, z), "console",
			Basis.IDENTITY, true)
		_box(out, "hall_terminal_%d_screen" % i, Vector3(0.06, 0.9, 1.4), Vector3(wx - side * 0.53, DECK_Y + 1.95, z), "screen",
			Basis(Vector3.FORWARD, side * deg_to_rad(8.0)))
		out[-1]["kind"] = "decor"
		i += 1
		z += 24.0
	# A terminal on every landing of the ramp shaft, at its wall-side end.
	for k in FLIGHTS - 1:
		var y1 := DECK_Y + (k + 1) * FLIGHT_RISE
		var aft := k % 2 == 0
		var lz := SHAFT_Z.y - 1.0 if aft else SHAFT_Z.x + 1.0
		var face := -1.0 if aft else 1.0
		for sx: float in [-1.0, 1.0]:
			var at := Vector3(sx * (LANDING_HALF - 1.6), y1, lz)
			_box(out, "landing_%d_terminal_%d" % [k, int(sx)], Vector3(2.2, 1.2, 0.9), at + Vector3(0, 0.6, 0), "console", Basis.IDENTITY, true)
			_box(out, "landing_%d_terminal_%d_screen" % [k, int(sx)], Vector3(2.0, 1.1, 0.06),
				at + Vector3(0, 1.85, -face * 0.25), "screen", Basis(Vector3.RIGHT, face * deg_to_rad(-15.0)))
			out[-1]["kind"] = "decor"


## The tower round the bridge and the shaft's top: window walls on the bridge's bow
## end and sides, plated walls aft, a roof with masts, and the plinth it stands on.
static func _tower(out: Array) -> void:
	var z0 := TOWER_Z.x
	var z1 := TOWER_Z.y
	var hull_top: float = (HULL[2] as Vector2).y
	# The plinth from the dorsal deck up under the bridge floor, closing the hull's top
	# there (aft of the bridge the shaft runs on up through it). Its top is the pits'
	# underside, not their floor, so the two never share a face and flicker.
	var plinth_top := PIT_Y - 1.0
	_box(out, "tower_plinth", Vector3(TOWER_X * 2.0 + 4.0, plinth_top - hull_top + 2.0, BRIDGE_Z.y - z0),
		Vector3(0, (hull_top - 2.0 + plinth_top) * 0.5, (z0 + BRIDGE_Z.y) * 0.5), "hull")
	# Over the shaft, between its walls and the tower's: a deck closing the hull's top.
	for side: float in [-1.0, 1.0]:
		_box(out, "tower_shaft_cap_%s" % ("s" if side > 0 else "p"), Vector3(TOWER_X - SHAFT_X + 2.0, 2.0, z1 - BRIDGE_Z.y),
			Vector3(side * (SHAFT_X + TOWER_X + 2.0) * 0.5, hull_top, (BRIDGE_Z.y + z1) * 0.5), "hull")
	# The bow wall: a sill, the great window in panes, and a header.
	var win := Vector2(BRIDGE_Y + 1.4, BRIDGE_TOP - 1.0)
	_box(out, "tower_bow_sill", Vector3(TOWER_X * 2.0 + 4.0, win.x - BRIDGE_Y + 4.0, 2.0),
		Vector3(0, (BRIDGE_Y - 4.0 + win.x) * 0.5, z0 + 1.0), "hull")
	_box(out, "tower_bow_header", Vector3(TOWER_X * 2.0 + 4.0, TOWER_TOP - win.y, 2.0),
		Vector3(0, (win.y + TOWER_TOP) * 0.5, z0 + 1.0), "hull")
	var panes := 9
	for i in panes:
		var x0 := -TOWER_X + i * TOWER_X * 2.0 / panes
		var x1 := x0 + TOWER_X * 2.0 / panes
		_box(out, "bow_glass_%d" % i, Vector3(x1 - x0, win.y - win.x, 0.3), Vector3((x0 + x1) * 0.5, (win.x + win.y) * 0.5, z0 + 1.0), "glass")
		_box(out, "bow_mullion_%d" % i, Vector3(0.6, win.y - win.x, 1.0), Vector3(x0, (win.x + win.y) * 0.5, z0 + 1.0), "trim")
	# The side walls: windows along the bridge, plated aft of it round the shaft.
	for side: float in [-1.0, 1.0]:
		var x := side * (TOWER_X + 1.0)
		var tag := "s" if side > 0 else "p"
		_box(out, "tower_%s_sill" % tag, Vector3(2.0, win.x - BRIDGE_Y + 4.0, BRIDGE_Z.y - z0),
			Vector3(x, (BRIDGE_Y - 4.0 + win.x) * 0.5, (z0 + BRIDGE_Z.y) * 0.5), "hull")
		_box(out, "tower_%s_header" % tag, Vector3(2.0, TOWER_TOP - win.y, BRIDGE_Z.y - z0),
			Vector3(x, (win.y + TOWER_TOP) * 0.5, (z0 + BRIDGE_Z.y) * 0.5), "hull")
		for i in 6:
			var za := z0 + i * (BRIDGE_Z.y - z0) / 6.0
			var zb := za + (BRIDGE_Z.y - z0) / 6.0
			_box(out, "side_glass_%s_%d" % [tag, i], Vector3(0.3, win.y - win.x, zb - za), Vector3(x, (win.x + win.y) * 0.5, (za + zb) * 0.5), "glass")
			_box(out, "side_mullion_%s_%d" % [tag, i], Vector3(1.0, win.y - win.x, 0.6), Vector3(x, (win.x + win.y) * 0.5, za), "trim")
		_box(out, "tower_%s_aft" % tag, Vector3(2.0, TOWER_TOP - hull_top + 4.0, z1 - BRIDGE_Z.y),
			Vector3(x, (hull_top - 4.0 + TOWER_TOP) * 0.5, (BRIDGE_Z.y + z1) * 0.5), "hull")
	_box(out, "tower_roof", Vector3(TOWER_X * 2.0 + 6.0, 2.5, z1 - z0 + 4.0), Vector3(0, TOWER_TOP + 1.25, (z0 + z1) * 0.5 + 1.0), "hull")
	_box(out, "tower_roof_cap", Vector3(TOWER_X * 1.2, 3.0, (z1 - z0) * 0.6), Vector3(0, TOWER_TOP + 4.0, (z0 + z1) * 0.5 + 12.0), "trim")
	for i in 3:
		var h := 18.0 + i * 7.0
		_box(out, "mast_%d" % i, Vector3(1.2, h, 1.2), Vector3(-12.0 + i * 12.0, TOWER_TOP + 5.5 + h * 0.5, z1 - 12.0 + i * 3.0), "trim")
		_box(out, "mast_%d_yard" % i, Vector3(8.0, 0.6, 0.6), Vector3(-12.0 + i * 12.0, TOWER_TOP + 5.5 + h * 0.8, z1 - 12.0 + i * 3.0), "trim")
		_box(out, "beacon_%d" % i, Vector3(1.0, 1.0, 1.0), Vector3(-12.0 + i * 12.0, TOWER_TOP + 6.0 + h, z1 - 12.0 + i * 3.0), "beacon")
		out[-1]["kind"] = "decor"


## Turrets along the dorsal deck, a long armoured spine, the superstructure
## stepping up toward the tower, a keel fin, the sensor globes' mounts and the
## engines (_engine_block). The bells and the globes themselves are drawn by
## RemnantCruiser.
static func _dorsal(out: Array) -> void:
	var top: float = (HULL[2] as Vector2).y
	_box(out, "spine", Vector3(12, 5, TOWER_Z.x + 120.0), Vector3(0, top + 2.5, (TOWER_Z.x - 120.0) * 0.5 - 10.0), "trim")
	# The superstructure: two stepped decks of armour rising aft to the tower.
	_box(out, "upper_works_1", Vector3(40, 12, TOWER_Z.x - 56.0), Vector3(0, top + 6.0, (TOWER_Z.x + 56.0) * 0.5), "hull")
	_box(out, "upper_works_1_lip", Vector3(42, 1.4, TOWER_Z.x - 54.0), Vector3(0, top + 12.4, (TOWER_Z.x + 56.0) * 0.5), "trim")
	_box(out, "upper_works_2", Vector3(28, 10, TOWER_Z.x - 118.0), Vector3(0, top + 17.0, (TOWER_Z.x + 118.0) * 0.5), "hull")
	_box(out, "upper_works_2_lip", Vector3(30, 1.4, TOWER_Z.x - 116.0), Vector3(0, top + 22.4, (TOWER_Z.x + 118.0) * 0.5), "trim")
	# The keel fin under the hull, from the bow taper to the engines.
	_box(out, "keel_fin", Vector3(4, 16, 300), Vector3(0, (HULL[6] as Vector2).y - 8.0, 60), "trim")
	# Mounts for the sensor globes on the tower's roof.
	for g in globes():
		_box(out, "globe_mount_%d" % int(g.i), Vector3(4, 6, 4), (g.at as Vector3) - Vector3(0, float(g.radius) + 2.0, 0), "trim")
	for i in 5:
		var z := -120.0 + i * 40.0
		for side: float in [-1.0, 1.0]:
			var c := Vector3(side * 16.0, top, z)
			_box(out, "turret_%d_%s_base" % [i, "s" if side > 0 else "p"], Vector3(8, 3, 8), c + Vector3(0, 1.5, 0), "trim")
			_box(out, "turret_%d_%s_head" % [i, "s" if side > 0 else "p"], Vector3(6, 3, 7), c + Vector3(0, 4.5, 0), "hull")
			for bx: float in [-1.4, 1.4]:
				_box(out, "turret_%d_%s_gun_%d" % [i, "s" if side > 0 else "p", int(bx * 10)], Vector3(0.7, 0.7, 9),
					c + Vector3(bx, 4.8, -7.5), "trim")
	_engine_block(out)


## The engines' housings on the stern: an armoured block round each bell, a frame
## round its mouth and cooling fins down the outer side; the two on each side are
## braced into one nacelle. The bells stand out past the housings: each has a box
## round it that a ship hits and that is not drawn (RemnantCruiser draws the bell).
static func _engine_block(out: Array) -> void:
	var hz := HOUSING_Z
	var mid := (hz.x + hz.y) * 0.5
	var deep := hz.y - hz.x
	for e in engines():
		var c: Vector3 = e.at
		var r: float = e.radius
		var i := int(e.i)
		var w := r * 2.7
		var h := r * 2.36
		_box(out, "engine_housing_%d" % i, Vector3(w, h, deep), Vector3(c.x, c.y, mid), "hull")
		# The frame round the mouth, on the housing's aft face.
		var fz := hz.y + 0.8
		_box(out, "engine_frame_%d_top" % i, Vector3(w + 2.0, 2.0, 1.6), Vector3(c.x, c.y + h * 0.5, fz), "trim")
		_box(out, "engine_frame_%d_bottom" % i, Vector3(w + 2.0, 2.0, 1.6), Vector3(c.x, c.y - h * 0.5, fz), "trim")
		for sx: float in [-1.0, 1.0]:
			_box(out, "engine_frame_%d_%d" % [i, int(sx)], Vector3(2.0, h, 1.6), Vector3(c.x + sx * w * 0.5, c.y, fz), "trim")
		var bell_len := BELL_LENGTH * (0.5 if bool(e.aux) else 1.0)
		var stand := c.z - hz.y
		_box(out, "engine_bell_%d" % i, Vector3(r * 2.0, r * 2.0, stand), Vector3(c.x, c.y, hz.y + stand * 0.5), "hidden")
		if bool(e.aux):
			continue
		# Cooling fins down the outer side.
		var side := signf(c.x)
		for k in 5:
			_box(out, "engine_fin_%d_%d" % [i, k], Vector3(3.0, 0.5, deep - 3.0),
				Vector3(c.x + side * (w * 0.5 + 1.5), c.y - h * 0.5 + 3.0 + k * (h - 6.0) / 4.0, mid), "trim")
	# Braces between the upper and lower housing on each side: one nacelle.
	for sx: float in [-1.0, 1.0]:
		_box(out, "engine_brace_%d" % int(sx), Vector3(28.0, 6.0, deep - 2.0), Vector3(sx * 25.0, 3.0, mid), "trim")


## The middle of the holo table's top, half way down the bridge's walkway: the
## planet map (CruiserHolo) floats over it.
static func holo_table() -> Vector3:
	return Vector3(0, BRIDGE_Y + 1.18, (BRIDGE_Z.x + 10.0 + BRIDGE_Z.y - 8.0) * 0.5)


## The two sensor globes on the tower's roof: centre and radius.
static func globes() -> Array:
	return [{ "i": 0, "at": Vector3(-17, TOWER_TOP + 13.0, 296), "radius": 7.0 },
		{ "i": 1, "at": Vector3(17, TOWER_TOP + 13.0, 296), "radius": 7.0 }]


## The engines on the stern: four mains in two nacelles and a small aux between
## them. Where each bell's mouth is, how big, and whether it is the aux.
static func engines() -> Array:
	var out: Array = []
	var i := 0
	for y: float in [-12.0, 18.0]:
		for x: float in [-25.0, 25.0]:
			out.append({ "i": i, "at": Vector3(x, y, HOUSING_Z.y + BELL_LENGTH * 0.45), "radius": 11.0, "aux": false })
			i += 1
	out.append({ "i": i, "at": Vector3(0, 3, HOUSING_Z.y + BELL_LENGTH * 0.25), "radius": 5.5, "aux": true })
	return out


# ------------------------------------------------------------------ builders

static func _box(out: Array, id: String, size: Vector3, center: Vector3, finish: String,
		basis: Basis = Basis.IDENTITY, nav := false) -> void:
	out.append({ "id": id, "size": size, "xf": Transform3D(basis, center), "finish": finish,
		"kind": "solid", "nav": nav })


## A level deck `thick` metres thick with its top at y.
static func _slab(out: Array, id: String, xs: Vector2, zs: Vector2, y: float, finish: String, thick := 1.0) -> void:
	_box(out, id, Vector3(xs.y - xs.x, thick, zs.y - zs.x), Vector3((xs.x + xs.y) * 0.5, y - thick * 0.5, (zs.x + zs.y) * 0.5), finish)
	out[-1]["kind"] = "floor"
	out[-1]["nav"] = true


## A wall from foot corner a to top corner b (they share x or z), `thick` through.
static func _wall(out: Array, id: String, a: Vector3, b: Vector3, thick: float) -> void:
	var size := (b - a).abs()
	if size.x < 0.01:
		size.x = thick
	if size.z < 0.01:
		size.z = thick
	_box(out, id, size, (a + b) * 0.5, "wall", Basis.IDENTITY, true)


## A straight ramp whose top runs from a to b, `width` wide, its top surface through
## both ends (as the wreck's ramps).
static func _ramp(out: Array, id: String, a: Vector3, b: Vector3, width: float) -> void:
	var run := b - a
	var flat := Vector2(run.x, run.z).length()
	var basis := Basis(Vector3.UP, atan2(run.x, run.z)) * Basis(Vector3.RIGHT, -atan2(run.y, flat))
	_box(out, id, Vector3(width, 1.0, run.length() + 0.6), (a + b) * 0.5 - basis.y * 0.5, "ramp", basis)
	out[-1]["kind"] = "floor"
	out[-1]["nav"] = true


## Rails across a landing's open edge (at z = `edge`, floor y) from -half to half,
## open where the flights leave and arrive (|x| between the flights' inner and outer edges).
static func _gapped_rail(out: Array, id: String, edge: float, y: float, half: float) -> void:
	var inner := FLIGHT_X - FLIGHT_W * 0.5
	var outer := FLIGHT_X + FLIGHT_W * 0.5
	_rail(out, id + "_p", Vector3(-half, y, edge), Vector3(-outer, y, edge))
	_rail(out, id + "_mid", Vector3(-inner, y, edge), Vector3(inner, y, edge))
	_rail(out, id + "_s", Vector3(outer, y, edge), Vector3(half, y, edge))


## A railing along a floor edge from `from` to `to` (floor heights): a solid 1.3 m
## barrier (a top rail and a kick plate drawn on it), sloping with a ramp.
static func _rail(out: Array, id: String, from: Vector3, to: Vector3) -> void:
	var span := to - from
	if span.length() < 0.2:
		return
	var flat := Vector2(span.x, span.z).length()
	var basis := Basis(Vector3.UP, atan2(span.x, span.z)) * Basis(Vector3.RIGHT, -atan2(span.y, flat))
	_box(out, id, Vector3(0.25, 1.3, span.length()), (from + to) * 0.5 + Vector3(0, 0.65, 0), "rail", basis, true)
