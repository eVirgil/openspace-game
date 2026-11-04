extends GutTest
## The space station (StationHull, SpaceStation;
## content/core/stations/orbital_station.json), placed by the ringed giant's
## "station" landmark (it started over the moon's far side, PR #501). Its shape
## from data, where it hangs, that it is a component any planet can carry, that
## its floors stand, and in the giant's scene: Z docks you in its bay and its
## elevators carry you between floors.

const TownDemo := preload("res://scenes/town_demo.gd")
const ID := "orbital_station"
const HOST := "ringed_giant"       ## the planet that carries it

var _sphere_before: PlanetSphere


func before_each() -> void:
	WorldState.reset()
	_sphere_before = PlanetSphere.current


func after_each() -> void:
	PlanetSphere.current = _sphere_before
	GameFlow.reset()
	WorldState.reset()


func _hull() -> StationHull:
	return StationHull.for_id(ID)


## A ground on a ball of `radius` carrying `landmarks` (the station's boxes and gravity).
func _ground(radius: float, landmarks: Array, planet := "") -> WorldGround:
	PlanetSphere.current = PlanetSphere.new(radius)
	var g := WorldGround.new()
	g.setup({ "terrain": { "sphere_radius": radius }, "landmarks": landmarks, "planet": planet })
	return g


func _host_landmark() -> Dictionary:
	for lm in StationHull.landmarks(PlanetGen.build(HOST).world):
		if str(lm.get("station", "")) == ID:
			return lm
	return {}


# ------------------------------------------------------------------ shape

func test_two_towers_of_round_floors_the_top_biggest() -> void:
	var h := _hull()
	assert_not_null(h)
	assert_eq(h.towers.size(), 2)
	var main := h.tower("main")
	var second := h.tower("second")
	assert_eq((main.floors as Array).size(), 4, "main: engines, markets, homes, top")
	assert_eq((second.floors as Array).size(), 3, "second: level with the main tower's top three")
	for t in h.towers:
		var fl: Array = t.floors
		for i in fl.size() - 1:
			assert_lt(float(fl[i].r), float(fl[i + 1].r), "%s: each floor below is smaller" % t.id)
			var open := float(fl[i + 1].y) - h.plate - (float(fl[i].y) + h.floor_h + h.plate)
			assert_gt(open, 5.0, "%s: open space between floors %d and %d" % [t.id, i, i + 1])
	for f in second.floors:
		assert_false(StationHull.floor_at(main, float(f.y)).is_empty(), "second tower's floor at %.0f has a main floor beside it" % f.y)


func test_tunnels_join_every_shared_level_and_the_bay() -> void:
	var h := _hull()
	var to_second := h.tunnels.filter(func(t): return str(t.to) == "second")
	var to_bay := h.tunnels.filter(func(t): return str(t.to) == "bay")
	assert_eq(to_second.size(), 3, "a tunnel at each of the three shared levels")
	assert_eq(to_bay.size(), 1, "and one to the bay")
	for tn in h.tunnels:
		assert_gt(float(tn.length), 10.0, str(tn.id))


func test_every_floor_has_two_shaft_doors_and_the_bridges_alternate() -> void:
	var h := _hull()
	var floors := 0
	for t in h.towers:
		floors += (t.floors as Array).size()
	assert_eq(h.doors.size(), floors * 2)
	assert_eq(StationHull.bridge_angles(0), [PI * 0.5, PI * 1.5], "north-south on the bottom floor")
	assert_eq(StationHull.bridge_angles(1), [0.0, PI], "east-west on the next")
	assert_eq(h.elevators().size(), 2, "an elevator in each tower")


# ------------------------------------------------------------------ where it hangs

func test_it_hangs_over_the_giant_where_its_town_was_inside_its_scene() -> void:
	var lm := _host_landmark()
	assert_false(lm.is_empty(), "the ringed giant's config carries the station")
	assert_true(StationHull.landmarks(PlanetGen.build("grit_station").world).is_empty(), "the moon gave it up")
	var g := PlanetGen.build(HOST)
	var r := PlanetGen.ball_radius(g.cfg, null)
	var sp := GasSphere.new(r, g.type_cfg.surface)
	var xf := _hull().frame_for(sp, lm, { "planet": HOST })
	var alt := float(lm.get("altitude", 0.0))
	assert_almost_eq(xf.origin.distance_to(sp.center), r + alt, 0.5)
	assert_almost_eq(Vector2(xf.origin.x, xf.origin.z).length(), 0.0, 0.5, "straight over the deck town's spot")
	assert_gt(alt + _hull().bottom_y() - 40.0, 30.0, "its lowest part well clear of the small deck below")
	var reach: float = _hull().top_y() - _hull().bottom_y() + 200.0
	assert_lt(alt + reach, PlanetGen.handoff_altitude(str(g.type)), "all of it in the giant's own scene")
	assert_eq(xf.basis.y, Vector3.UP, "level, like the cruiser")
	assert_eq(int(g.size), 1, "the town under it is only a landing deck")


func test_it_is_a_component_the_home_planet_does_not_have_and_another_can_take() -> void:
	assert_true(StationHull.landmarks(PlanetGen.build(PlanetGen.home_id()).world).is_empty(), "not on the home planet")
	var none := _ground(1500.0, [])
	assert_eq(StationHull.frame(none, ID), Transform3D.IDENTITY, "no landmark, no station")
	var lm := { "id": "moved", "kind": "station", "station": ID, "at": [3000, 0, 0], "altitude": 6000 }
	var g := _ground(5000.0, [lm])
	var xf := StationHull.frame(g, "moved")
	assert_ne(xf, Transform3D.IDENTITY, "the same block on another planet puts it there")
	assert_almost_eq(g.altitude(xf.origin), 6000.0, 1.0)
	assert_eq(g.up_at(xf.origin + Vector3(0, 30, 0)), Vector3.UP, "with its own gravity aboard")
	assert_gt(g.boxes.filter(func(b): return str(b.id).begins_with("moved/")).size(), 500)


func test_its_floors_tunnels_and_bay_stand() -> void:
	var lm := { "id": "st", "kind": "station", "station": ID, "at": [0, 0, 0], "altitude": 3000 }
	var g := _ground(1500.0, [lm])
	var xf := StationHull.frame(g, "st")
	var h := _hull()
	var pts := { "pad": h.dock_pad().at, "bay_tunnel": Vector3(-70, 0, 0), "tunnel_top": Vector3(88, 52, 0),
		"tunnel_markets": Vector3(85, 0, 0), "t2_top": Vector3(180, 52, 6) }
	for t in h.towers:
		var c: Vector2 = t.c
		for f in t.floors:
			pts["%s_%s_walkway" % [t.id, f.id]] = Vector3(c.x + h.gap_r + 3.0, float(f.y), c.y + 1.0)
			pts["%s_%s_glass" % [t.id, f.id]] = Vector3(c.x + 8.0, float(f.y), c.y + 4.0)
			pts["%s_%s_outer" % [t.id, f.id]] = Vector3(c.x - float(f.r) + 4.0, float(f.y), c.y + 2.0)
	for k in pts:
		var w: Vector3 = xf * ((pts[k] as Vector3) + Vector3(0, 1.0, 0))
		assert_almost_eq(g.height_above(w), 1.0, 0.35, "%s stands" % k)
		assert_true(h.aboard(xf.affine_inverse() * w), "%s is aboard" % k)
	assert_false(h.aboard(Vector3(30, 20, 0)), "between floors is space")
	assert_false(h.aboard(Vector3(0, 40, 300)), "and so is out past the towers")


func test_the_dock_path_ends_over_the_pad_and_goes_round_the_towers_from_behind() -> void:
	var h := _hull()
	var hold := float(h.cfg.dock.hold_y)
	var pad: Vector3 = h.dock_pad().at
	var front := h.dock_path(h.bay.xf * Vector3(900, 20, 0))
	var last: Vector3 = front[-1]
	assert_almost_eq(Vector2(last.x, last.z).distance_to(Vector2(pad.x, pad.z)), 0.0, 0.01)
	assert_almost_eq(last.y, pad.y + hold, 0.01)
	assert_eq(front.size(), 3, "from in front: straight to the mouth and in")
	var behind := h.dock_path(Vector3(500, 60, 50))
	assert_gt(behind.size(), 3)
	assert_gt((behind[0] as Vector3).y, h.top_y() + 30.0, "over the towers")
	assert_gt((behind[1] as Vector3).y, h.top_y() + 30.0)
	var under := h.dock_path(Vector3(500, -90, 50))
	assert_lt((under[0] as Vector3).y, h.bottom_y() - 30.0, "or under them from below")


func test_the_bay_is_round_with_a_curved_shield_across_its_mouth() -> void:
	var h := _hull()
	var c: Vector2 = h.bay.c
	var r := float(h.bay.r)
	var lm := { "id": "st", "kind": "station", "station": ID, "at": [0, 0, 0], "altitude": 3000 }
	var g := _ground(1500.0, [lm])
	var xf := StationHull.frame(g, "st")
	for k in 8:
		var a := TAU * k / 8.0
		var at := Vector3(c.x + cos(a) * (r - 4.0), 1.0, c.y + sin(a) * (r - 4.0))
		assert_almost_eq(g.height_above(xf * at), 1.0, 0.35, "the round deck stands at %d deg" % (k * 45))
		assert_true(h.aboard(at), "and is aboard")
	assert_false(h.aboard(Vector3(c.x, 5.0, c.y) + Vector3(h.bay_out().x, 0, h.bay_out().z) * (r + 6.0)), "out past the mouth is not")
	var sh := h.shield()
	var out := h.bay_out()
	assert_eq((sh.pieces as Array).size(), 10)
	for pc in sh.pieces:
		var o: Vector3 = (pc.xf as Transform3D).origin
		var d := Vector2(o.x - c.x, o.z - c.y)
		assert_almost_eq(d.length(), float(sh.r), 0.01, "on the wall's curve")
		assert_lt(absf(d.angle_to(Vector2(out.x, out.z))), float(sh.half) + 0.01, "across the mouth")
	var mid: Vector3 = (sh.xf as Transform3D).origin
	assert_gt(Vector2(mid.x - c.x, mid.z - c.y).dot(Vector2(out.x, out.z)), r * 0.8, "facing out, away from the tower")
	var pad: Vector3 = h.dock_pad().at
	assert_lt(Vector2(pad.x - c.x, pad.z - c.y).length() + float(h.dock_pad().radius), r + 6.0, "the pad fits inside")


func test_every_tunnel_has_a_roof_hatch_and_a_roof_walk() -> void:
	var h := _hull()
	assert_eq(h.hatches.size(), h.tunnels.size(), "a hatch over every tunnel")
	var lm := { "id": "st", "kind": "station", "station": ID, "at": [0, 0, 0], "altitude": 3000 }
	var g := _ground(1500.0, [lm])
	var xf := StationHull.frame(g, "st")
	for tn in h.tunnels:
		var txf: Transform3D = tn.xf
		var l := float(tn.length)
		var roof := txf * Vector3(l * 0.2, h.tunnel_h + 0.6 + 1.0, 0)
		assert_almost_eq(g.height_above(xf * roof), 1.0, 0.35, "%s: its roof walk stands" % tn.id)
		assert_false(h.aboard(roof), "%s: out on the roof is outside" % tn.id)
		assert_true(h.on_roof(roof), "%s: but on its walk" % tn.id)
		var through := txf * Vector3(l * 0.5, h.tunnel_h + 1.0, 0)
		assert_gt(g.height_above(xf * through), h.tunnel_h, "%s: the hatch is open down to the deck" % tn.id)


# ------------------------------------------------------------------ in the giant's scene

func _host() -> Node:
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.planet_id = HOST
	GameFlow.change_scene = func(_p: String) -> void: pass
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func _station(t):
	for i in 120:
		if not t.stations.is_empty():
			return t.stations[0]
		await wait_physics_frames(1)
	return null


func test_z_docks_you_in_the_bay_from_behind_the_towers() -> void:
	var t = _host()
	var s = await _station(t)
	assert_not_null(s, "the giant's scene builds the station")
	if s == null:
		return
	assert_ne(s.label(), "", "it has a name")
	var pilot: ShipPilot = t.pilot
	pilot._seat_arriving()
	pilot.atmo.place_flying(s.frame * Vector3(600, 60, 80), Vector3.FORWARD, 0.0, 0.5)
	pilot._set_hull(true)
	await wait_physics_frames(2)
	assert_true(pilot.near_dock(), "in reach of its bay")
	assert_eq(pilot.dock_target(), s)
	assert_true(pilot.dock())
	for i in 60 * 40:
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
		await wait_physics_frames(1)
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "down on the pad")
	var pad: Vector3 = s.dock_point()
	var at := pilot.atmo.position()
	assert_almost_eq(Vector2(at.x, at.z).distance_to(Vector2(pad.x, pad.z)), 0.0, 1.0)
	assert_eq(pilot.dockings, 1)
	assert_true(pilot.exit_ship())
	await wait_physics_frames(30)
	var p = t._player
	assert_true(s.aboard(p.global_position), "you step out aboard")
	assert_true(p.is_on_floor())
	assert_true(t.indoors(p.global_position), "and you are indoors")


func test_the_elevator_carries_you_up_with_its_doors_shut_on_the_way() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var car: Dictionary = s.cars[0]
	var stops: Array = car.stops
	car.at = float(stops[0])
	car.i = 0
	car.dir = 1
	car.moving = false
	car.wait = 1.0
	(car.body as Node3D).position = Vector3((car.c as Vector2).x, float(stops[0]), (car.c as Vector2).y)
	var p = t._player
	p.global_position = s.frame * Vector3(0, float(stops[0]) + 0.6, 0)
	var shut_while_moving := true
	for i in 60 * 40:
		await wait_physics_frames(1)
		if bool(car.moving):
			for d in car.doors:
				if (d[1] as CollisionShape3D).disabled:
					shut_while_moving = false
		if s.rides >= 2 and not bool(car.moving):
			break
	assert_eq(s.rides, 2, "it stopped at the next two floors with you aboard")
	assert_eq(int(car.i), 2, "on up, not back down")
	assert_almost_eq((s.inv * p.global_position).y, float(stops[2]), 0.3, "standing on it")
	assert_true(shut_while_moving, "every shaft door shut while it moved")
	await wait_physics_frames(2)
	for d in car.doors:
		assert_eq((d[1] as CollisionShape3D).disabled, int(d[0]) == int(car.i), "only its floor's doors open")


func test_standing_by_the_shaft_calls_the_car() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var car: Dictionary = s.cars[0]
	var stops: Array = car.stops
	var p = t._player
	var want := stops.size() - 1 if int(car.i) != stops.size() - 1 else 0
	p.global_position = s.frame * Vector3(s.hull.gap_r - 1.0, float(stops[want]) + 1.0, 0.5)
	for i in 60 * 40:
		await wait_physics_frames(1)
		p.global_position = s.frame * Vector3(s.hull.gap_r - 1.0, float(stops[want]) + 1.0, 0.5)
		if int(car.i) == want and not bool(car.moving):
			break
	assert_eq(int(car.i), want, "it came to your floor")
	assert_false(bool(car.moving))


func test_out_on_a_roof_walk_you_are_left_there() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var p = t._player
	var tn: Dictionary = s.hull.tunnels[0]
	p.global_position = s.frame * ((tn.xf as Transform3D) * Vector3(4.0, 1.0, 0))
	await wait_physics_frames(3)
	var roof: Vector3 = s.frame * ((tn.xf as Transform3D) * Vector3(float(tn.length) * 0.2, s.hull.tunnel_h + 1.6, 0))
	p.global_position = roof
	await wait_physics_frames(10)
	assert_eq(s.falls, 0, "not pulled back in")
	assert_lt(p.global_position.distance_to(roof), 2.0, "still on the roof")


func test_falling_out_puts_you_back_in_the_bay() -> void:
	var t = _host()
	var s = await _station(t)
	if s == null:
		fail_test("no station")
		return
	var p = t._player
	p.global_position = s.frame * (s.hull.spawn_point() + Vector3(0, 0.5, 0))
	await wait_physics_frames(3)
	p.global_position = s.frame * Vector3(30, 20, 0)       # out between the floors
	await wait_physics_frames(3)
	assert_eq(s.falls, 1)
	assert_true(s.aboard(p.global_position), "back aboard")
