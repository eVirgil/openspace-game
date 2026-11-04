extends Node3D
## Issue #314: the station's Remnant deck. One whole floor (the config's "remnant"
## block; the second tower's middle floor) is the Remnant's: the cruiser's control
## room with the planet map over its holo table, two bunk rooms, an armoury, a
## command office and a mess, Remnant red down the walkway and a barricade with a
## checkpoint at its tunnel from the favela. The look is StationFill's ("use":
## "remnant"); this node is the people and who holds it.
##
##   the Remnant's   a garrison of troopers and a commander at their posts (and two
##                   walking the walkway), built a body a frame once the camera
##                   comes within wake_within, asleep past sleep_m (the cruiser's
##                   way), run by a garrison of their own like an outpost's
##   taken           the last of them dead: Territory.take_station hands the deck to
##                   the locals for good (saved with the world), the red is painted
##                   over in the locals' colours (LookMaterials.repaint, group
##                   "station:<id>") and the locals' guards move in
##   the locals'     their guards at the posts, run by a Townsfolk of their own,
##                   every visit after
##
## Pure layout (rooms(), posts(), control_room()) is in the station's frame, so the
## look and the people agree, and the deck plays without the look layer.

const UP := Vector3.UP

var station                         ## SpaceStation
var demo
var hull: StationHull
var cfg: Dictionary = {}            ## the config's "remnant" block
var place := ""                     ## its Territory id ("station_<landmark id>")
var group := ""                     ## its faction materials' group (LookMaterials.repaint)
var troopers: Array = []            ## NpcBody, the Remnant's (the commander too)
var guards: Array = []              ## NpcBody, the locals' once they hold it
var garrison: Garrison
var woke := false
var taken_here := false             ## the last trooper died in this scene
var holo: Node3D

var _queue: Array = []
var _folk                           ## Townsfolk running the locals' guards
var _swap_t := -1.0                 ## seconds until the locals' guards move in (after a take)
var _holo_tried := false


func setup(space_station, town_demo, station_hull: StationHull) -> void:
	station = space_station
	demo = town_demo
	hull = station_hull
	cfg = hull.cfg.get("remnant", {})
	place = Territory.STATION + str(station.id)
	group = "station:" + str(station.id)
	name = "RemnantDeck"


## The floor it is on: [tower, floor index], or [] when the config has none.
static func deck(h: StationHull) -> Array:
	var rc: Dictionary = h.cfg.get("remnant", {})
	var t := h.tower(str(rc.get("tower", "")))
	if t.is_empty():
		return []
	for i in (t.floors as Array).size():
		if str(t.floors[i].id) == str(rc.get("floor", "")):
			return [t, i]
	return []


## The deck's rooms by use: [{ room (StationHull.rooms_of), use, frame (x out along
## the room, y up, z across, origin the tower's middle at the floor), r0 (inside the
## door), r1 (the window), half }]. Uses come from the config's "rooms" in turn.
static func rooms(h: StationHull) -> Array:
	var d := deck(h)
	if d.is_empty():
		return []
	var t: Dictionary = d[0]
	var f: Dictionary = t.floors[int(d[1])]
	var uses: Array = h.cfg.get("remnant", {}).get("rooms", ["control", "bunks", "armoury", "command", "bunks", "mess"])
	var out: Array = []
	var k := 0
	for room in h.rooms_of(str(t.id), str(f.id)):
		out.append({ "room": room, "use": str(uses[k % uses.size()]), "frame": _radial(t, float(f.y), float(room.a)),
			"r0": h.gap_r + h.walk + 0.4, "r1": float(f.r) - StationHull.WALL, "half": float(room.half) })
		k += 1
	return out


## A room's frame at angle `a` round tower `t`'s middle (StationFill.radial's).
static func _radial(t: Dictionary, y: float, a: float) -> Transform3D:
	var c: Vector2 = t.c
	var x := Vector3(cos(a), 0, sin(a))
	return Transform3D(Basis(x, UP, x.cross(UP)), Vector3(c.x, y, c.y))


## The control room in a room `r` (rooms()): OutpostRoom's room `b` and the frame
## its own local frame sits in (its +x toward the door, the walkway).
static func control_room(h: StationHull, r: Dictionary) -> Dictionary:
	var r0 := float(r.r0)
	var depth := minf(float(r.r1) - r0 - 2.0, 18.0)
	var width := minf(2.0 * ((r0 + 1.0) * tan(float(r.half)) - StationHull.INNER_WALL - 0.15) - 0.6, 12.0)
	var b := { "id": "station_control", "size": [depth, h.floor_h, width], "position": [0, 0, 0], "room": { "rows": 2, "door": 2.6 } }
	var frame: Transform3D = (r.frame as Transform3D) * Transform3D(Basis(UP, PI), Vector3(r0 + 1.0 + depth * 0.5, 0, 0))
	return { "b": b, "frame": frame }


## Where people stand: [{ id, at (station frame), face (a direction, station frame),
## soldier: "trooper" / "commander", patrol: [points] }]. Each room by its use, two at
## the barricade and two walking the walkway.
static func posts(h: StationHull) -> Array:
	var out: Array = []
	var d := deck(h)
	if d.is_empty():
		return out
	var t: Dictionary = d[0]
	var f: Dictionary = t.floors[int(d[1])]
	var c: Vector2 = t.c
	var y := float(f.y)
	var spots := {
		"control": [[6.0, 3.0], [12.0, -2.0]],
		"bunks": [[4.0, 1.5]],
		"armoury": [[3.0, -1.5]],
		"command": [[10.0, 0.0, "commander"], [3.0, 1.8]],
		"mess": [[6.0, -3.0], [8.0, 3.0]],
	}
	for r in rooms(h):
		var frame: Transform3D = r.frame
		for s in spots.get(str(r.use), []):
			var at := frame * Vector3(float(r.r0) + float(s[0]), 0.0, float(s[1]))
			out.append({ "id": "%s_%d" % [str(r.use), out.size()], "at": at, "face": -(frame.basis.x),
				"soldier": str(s[2]) if s.size() > 2 else "trooper" })
	# The barricade at the tunnel's mouth, facing it; two walking the walkway.
	var rr := h.gap_r + h.walk
	for a in h.door_angles(t, y):
		var dir := Vector3(cos(float(a)), 0, sin(float(a)))
		var side := dir.cross(UP)
		for s: float in [-1.6, 1.6]:
			out.append({ "id": "barricade_%d" % out.size(), "at": Vector3(c.x, y, c.y) + dir * (rr - 2.0) + side * s, "face": dir, "soldier": "trooper" })
	var rw := h.gap_r + h.walk * 0.5
	for k in 2:
		var pts: Array = []
		for j in 7:
			var a := k * PI + j * PI / 6.0
			pts.append(Vector3(c.x + cos(a) * rw, y, c.y + sin(a) * rw))
		out.append({ "id": "patrol_%d" % k, "at": pts[0], "face": Vector3.FORWARD, "soldier": "trooper", "patrol": pts })
	return out


# ------------------------------------------------------------------ each frame

func _process(dt: float) -> void:
	if station == null or deck(hull).is_empty():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at: Vector3 = cam.global_position if cam != null else Vector3.INF
	var d: float = station.distance(at) if at != Vector3.INF else 0.0
	if not woke and d <= float(cfg.get("wake_within", 700.0)):
		_wake()
	if not _queue.is_empty():
		(_queue.pop_front() as Callable).call()
	if _swap_t > 0.0:
		_swap_t -= dt
		if _swap_t <= 0.0:
			_locals_move_in()
	_sleep(at)
	_tick_holo(at)


## Your ship is close: whoever holds the deck takes their posts, a body a frame.
func _wake() -> void:
	woke = true
	if demo == null or not demo.has_method("make_soldier"):
		return
	if Territory.owner(place) == Territory.LOCALS:
		_repaint(Territory.LOCALS)
		_locals_move_in()
		return
	for p in posts(hull):
		_queue.append(_add_trooper.bind(p))


func _add_trooper(p: Dictionary) -> void:
	var profile := str(cfg.get("commander" if str(p.soldier) == "commander" else "trooper", "outpost_trooper"))
	var g: NpcBody = demo.make_soldier(profile, station.to_world(p.at) + Vector3(0, 0.05, 0), _yaw(p.face),
		"%s/%s" % [place, str(p.id)], "npc:%s/%s" % [place, str(p.id)], self)
	if g == null:
		return
	g.set_meta("outpost", place)
	g.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	g.nav = null
	g.free_walk = true                  # no navmesh aboard: straight across the deck
	troopers.append(g)
	g.died.connect(_on_trooper_died)
	if garrison == null:
		if not bool(demo.get("npc_brains")):
			return
		garrison = demo._make_garrison("Garrison_" + place, [g], false, station.to_world(p.at), true)
		if demo.get("outposts") != null:
			demo.outposts.garrisons[place] = garrison
	else:
		garrison.add_member(g)
	var route: Array = p.get("patrol", [])
	if route.size() >= 2 and garrison != null and garrison.brains.has(g):
		garrison.brains[g].patrol_points = route.map(func(r): return station.to_world(r))


## A facing in the station's frame as the soldiers' yaw (they face -Z).
func _yaw(face: Vector3) -> float:
	var f: Vector3 = station.frame.basis * face
	return atan2(-f.x, -f.z)


## Asleep (their process off) past sleep_m, as on the cruiser: awake while dying or
## just hit, so they fall or answer a shot from far off.
func _sleep(at: Vector3) -> void:
	if at == Vector3.INF:
		return
	var sleep := float(cfg.get("sleep_m", 120.0))
	var now := Time.get_ticks_usec()
	for g in troopers + guards:
		if not is_instance_valid(g):
			continue
		var awake: bool = g.dead or g.global_position.distance_to(at) <= sleep or now - g.damage_usec < 5000000
		g.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED


func _on_trooper_died() -> void:
	if not _queue.is_empty() or Territory.owner(place) == Territory.LOCALS:
		return
	for g in troopers:
		if is_instance_valid(g) and not g.dead:
			return
	taken_here = true
	Territory.take_station(place, station.label())
	_toast(Territory.line("station_taken") % station.label(), 6.0)
	_repaint(Territory.LOCALS)
	_swap_t = float(cfg.get("locals_after_s", 8.0))


## The locals' guards at the posts (fewer than the Remnant had: guard_share), run by
## a Townsfolk of the deck's own.
func _locals_move_in() -> void:
	if not guards.is_empty() or demo == null or not demo.has_method("make_soldier"):
		return
	var all := posts(hull)
	var every := maxi(1, roundi(1.0 / maxf(0.05, float(cfg.get("guard_share", 0.5)))))
	for i in all.size():
		if i % every != 0:
			continue
		_queue.append(_add_guard.bind(all[i]))


func _add_guard(p: Dictionary) -> void:
	var g: NpcBody = demo.make_soldier(str(cfg.get("guard", "local_guard")), station.to_world(p.at) + Vector3(0, 0.05, 0),
		_yaw(p.face), "%s/guard_%s" % [place, str(p.id)], "npc:%s/guard_%s" % [place, str(p.id)], self)
	if g == null:
		return
	g.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	g.nav = null
	g.free_walk = true
	guards.append(g)
	if not bool(demo.get("npc_brains")):
		return
	if _folk == null:
		_folk = demo.make_townsfolk("StationGuards_" + str(station.id), [])
	_folk.add_member(g)


func _repaint(owner: String) -> void:
	var fill = station.fill
	if fill != null and fill.mats != null:
		fill.mats.repaint(owner, group)


# ------------------------------------------------------------------ the holo map

## The planet map over the control room's holo table (BarracksLook's), built the
## first time the camera comes within holo.show_within, hidden and stopped past it.
func _tick_holo(at: Vector3) -> void:
	if demo == null or not bool(demo.get("use_look")) or at == Vector3.INF:
		return
	var spot := holo_spot()
	if spot == Vector3.INF:
		return
	var spec: Dictionary = BarracksHall.spec().get("holo", {})
	var near := at.distance_to(spot) <= float(spec.get("show_within", 45.0))
	if near and holo == null and not _holo_tried:
		_holo_tried = true
		holo = _make_holo(spot)
	if holo != null:
		holo.visible = near
		holo.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


## The top of the control room's holo table, in the world (INF: no control room).
func holo_spot() -> Vector3:
	for r in rooms(hull):
		if str(r.use) == "control":
			var cr := control_room(hull, r)
			return station.to_world((cr.frame as Transform3D) * (OutpostRoom.holo(cr.b) + Vector3(0, 1.01, 0)))
	return Vector3.INF


func _make_holo(spot: Vector3) -> Node3D:
	var planet: Dictionary = demo.get("planet") if demo.get("planet") is Dictionary else {}
	var world: Dictionary = planet.get("world", {})
	var pilot = demo.get("pilot")
	var sp: PlanetSphere = pilot.ground.sphere() if pilot != null and pilot.ground != null else null
	if sp == null:
		return null
	var spec: Dictionary = (CruiserHull.data().get("holo", {}) as Dictionary).duplicate(true)
	for k in BarracksHall.spec().get("holo", {}):
		spec[k] = BarracksHall.spec().holo[k]
	spec["no_cruiser"] = CruiserHull.landmark(world).is_empty()
	var frame := Transform3D(Basis.IDENTITY, sp.center + Vector3(0, sp.radius + 7000.0, 0))
	if not bool(spec.no_cruiser):
		frame = Transform3D(Basis.IDENTITY, CruiserHull.frame_for(sp, CruiserHull.landmark(world)).origin)
	var names := { "town": station.label(), "cruiser": NameHooks.vessel(CruiserHull.data(), "vessel:" + str(CruiserHull.data().get("id", "remnant_cruiser"))) }
	var moons: Array = []
	var travel = pilot.travel if pilot != null else null
	if travel != null:
		for body in travel.bodies:
			moons.append(body)
			names[str(body.id)] = str(body.name)
	var k := float(spec.get("scale", 0.42))
	var h := CruiserHolo.new()
	h.setup(spec, sp, frame, Vector3.ZERO, world, moons, names)
	add_child(h)
	h.global_transform = Transform3D(h.basis.scaled(Vector3.ONE * k), spot + Vector3(0, float(spec.get("lift", 1.75)) * k, 0))
	return h


func _toast(text: String, secs: float) -> void:
	if text == "" or demo == null:
		return
	var gear = demo.get("gear")
	if gear != null and gear.hud != null:
		gear.hud.toast(text, secs)
