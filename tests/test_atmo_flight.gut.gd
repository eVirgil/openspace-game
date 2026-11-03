extends GutTest
## M14: flying in the planet's air. Parks on the ground, lifts off to its height,
## hovers at zero throttle, goes faster as the air thins and slower nose-up,
## touches down gently or crashes hard, bumps or crashes into buildings, lands on
## command only when low, and leaves the atmosphere in 30-40 seconds at full power.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const FlightModel := preload("res://src/systems/flight/flight_model.gd")
const DT := 1.0 / 60.0

class CountingGround extends WorldGround:
	var height_queries := 0

	func height_above(p: Vector3) -> float:
		height_queries += 1
		return super.height_above(p)

var content
var ground: WorldGround
var a: AtmoFlight


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()
	var town = TownLayout.new()
	town.load_town("port_town", "port_square")   # issue #237: flights over the square port's main street
	ground = WorldGround.new()
	ground.setup(content.get_world("port_desert"), town, content)
	a = AtmoFlight.new()
	a.setup(content.get_ship("interceptor"), ground)


func _run(seconds: float, cmd: Dictionary = {}) -> Array:
	var ev: Array = []
	for i in int(seconds * 60.0):
		if not cmd.is_empty():
			a.set_command(float(cmd.get("pitch", 0.0)), 0, 0, float(cmd.get("throttle", 0.0)), bool(cmd.get("boost", false)))
		ev.append_array(a.step(DT))
	return ev


func _types(ev: Array) -> Array:
	return ev.map(func(e): return e.type)


func test_tuning_comes_from_the_ship_atmosphere_block() -> void:
	var atmo: Dictionary = content.get_ship("interceptor").atmosphere
	assert_eq(a.flight.max_speed(), float(atmo.max_speed))
	assert_eq(a.flight.min_speed(), 0.0, "zero throttle hovers")
	assert_eq(a.space_altitude, float(content.get_world("port_desert").atmosphere.space_altitude))


func test_parks_belly_on_the_ground() -> void:
	a.park(Vector3(40, 5, 0), 0.0)
	assert_eq(a.state, AtmoFlight.State.PARKED)
	assert_almost_eq(a.agl(), 0.0, 0.01)


func test_liftoff_rises_to_its_height_then_hovers() -> void:
	a.park(Vector3(40, 0, 0), 0.0)
	assert_true(a.takeoff())
	assert_false(a.takeoff(), "only from parked")
	var ev := _run(6.0)
	assert_true(_types(ev).has("airborne"))
	assert_eq(a.state, AtmoFlight.State.FLYING)
	assert_almost_eq(a.agl(), float(a.cfg.liftoff_height), 0.1)
	_run(2.0, { "throttle": 0.0 })
	assert_almost_eq(a.speed(), 0.0, 0.001, "zero throttle hovers in place")


func test_thin_air_is_faster_and_climbing_is_slower() -> void:
	a.place_flying(Vector3(40, 300, 0), Vector3.FORWARD, 0.0, 1.0)
	assert_almost_eq(a.air_scale(), 1.0, 0.001, "thick air near the ground")
	a.place_flying(Vector3(40, a.space_altitude - 10.0, 0), Vector3.FORWARD, 0.0, 1.0)
	assert_gt(a.air_scale(), float(a.cfg.edge_speed_mult) * 0.95, "much faster at the edge of space")
	a.place_flying(Vector3(40, 300, 0), Vector3.FORWARD, 0.0, 1.0)
	_run(8.0, { "throttle": 1.0 })
	var level: float = a.speed()
	a.place_flying(Vector3(40, 300, 0), Vector3(0, 1, -0.01).normalized(), 0.0, 1.0)
	_run(1.0, { "throttle": 1.0 })
	a.flight.position.y = 300.0
	_run(1.0, { "throttle": 1.0 })
	assert_lt(a.flight.target_speed(), level, "nose up costs speed")


func test_gentle_touchdown_lands() -> void:
	a.place_flying(Vector3(40, 3.0, 0), Vector3(0, -0.4, -1).normalized(), 5.0, 0.03)
	var ev := _run(2.0, { "throttle": 0.03, "pitch": 0.0 })
	assert_true(_types(ev).has("landed"))
	assert_eq(a.state, AtmoFlight.State.PARKED)


func test_hard_impact_crashes() -> void:
	a.place_flying(Vector3(40, 30, 0), Vector3(0, -1, -0.3).normalized(), 150.0, 1.0)
	var ev := _run(2.0, { "throttle": 1.0 })
	assert_true(_types(ev).has("crashed"))
	assert_eq(a.state, AtmoFlight.State.CRASHED)


func test_buildings_bump_slow_ships_and_crash_fast_ones() -> void:
	a.place_flying(Vector3(0, 3.0, 66), Vector3.BACK, 6.0, 0.03)       # creeping at the north wall
	var ev := _run(3.0, { "throttle": 0.03 })
	assert_true(_types(ev).has("bump"), "slow: bumped")
	assert_ne(a.state, AtmoFlight.State.CRASHED)
	a.place_flying(Vector3(0, 3.0, 40), Vector3.BACK, 120.0, 1.0)
	ev = _run(1.0, { "throttle": 1.0 })
	assert_true(_types(ev).has("crashed"), "fast: crashed")


func test_land_only_when_low_and_settles_on_what_is_below() -> void:
	a.place_flying(Vector3(40, 400, 0), Vector3.FORWARD, 0.0, 0.0)
	assert_false(a.land(), "too high to land")
	var roof: Dictionary = ground.boxes.filter(func(b): return b.id == "watchtower")[0]
	var c: Vector3 = ((roof.min as Vector3) + (roof.max as Vector3)) * 0.5
	a.place_flying(Vector3(c.x, (roof.max as Vector3).y + 40.0, c.z), Vector3.FORWARD, 0.0, 0.0)
	assert_true(a.land())
	var ev := _run(15.0)
	assert_true(_types(ev).has("landed"))
	assert_almost_eq(a.position().y - a.clearance, float((roof.max as Vector3).y), 0.05, "on the watchtower's top")


func test_landing_called_off_coasts_to_a_stop() -> void:
	a.place_flying(Vector3(40, 100, 0), Vector3.FORWARD, 40.0, 0.5)
	assert_false(a.abort_landing(), "only while landing")
	assert_true(a.land())
	_run(0.2)
	var moving: float = a.speed()
	assert_gt(moving, 20.0)
	assert_true(a.abort_landing())
	assert_eq(a.state, AtmoFlight.State.FLYING)
	_run(1.0, { "throttle": 0.0 })
	assert_between(a.speed(), moving * 0.3, moving * 0.7, "still moving, slowing")
	_run(1.1, { "throttle": 0.0 })
	assert_almost_eq(a.speed(), 0.0, 0.01, "stopped after the coast")
	assert_eq(a.state, AtmoFlight.State.FLYING, "hovering, not landing")


func test_can_land_reuses_the_current_clearance_when_supplied() -> void:
	var counted := CountingGround.new()
	var town := TownLayout.new()
	town.load_town("port_town", "port_square")   # issue #237: flights over the square port's main street
	counted.setup(content.get_world("port_desert"), town, content)
	a.setup(content.get_ship("interceptor"), counted)
	a.place_flying(Vector3(40.0, 20.0, 0.0), Vector3.FORWARD, 0.0, 0.0)
	var before_clearance := counted.height_queries
	var clearance := a.agl()
	assert_eq(counted.height_queries - before_clearance, 5,
		"AGL samples the belly and four points around the ship")
	var after_clearance := counted.height_queries
	a.can_land(clearance)
	assert_eq(counted.height_queries, after_clearance,
		"the HUD landing prompt reuses its five-point clearance sample")


func test_rests_on_the_high_side_of_a_slope() -> void:
	var ramp: Dictionary = ground.boxes.filter(func(b): return b.id == "ramp_ne")[0]
	var mid := ((ramp.min as Vector3) + (ramp.max as Vector3)) * 0.5
	a.park(Vector3(mid.x, mid.y, mid.z), 0.0)
	assert_gte(a.position().y - a.clearance, ground.ground_at(mid.x, mid.z) - 0.001,
		"never sinks into the slope")


func test_leaves_the_atmosphere_once_in_30_to_40_seconds() -> void:
	a.park(Vector3(0.3, -6, 0), -PI * 0.5)
	a.takeoff()
	var t := 0.0
	var seen := 0
	var want := sin(deg_to_rad(80.0))
	for i in 60 * 70:
		var fy: float = a.flight.forward().y
		var pc := clampf((want - fy) * 4.0, -1.0, 1.0) if a.state == AtmoFlight.State.FLYING else 0.0
		a.set_command(pc, 0, 0, 1.0, false)
		var ev := a.step(DT)
		t += DT
		seen += _types(ev).count("reached_space")
		if seen > 0 and t > 45.0:
			break
	assert_eq(seen, 1, "the edge of space is reported once")
	assert_true(a.reached_space)


func test_full_power_climb_time() -> void:
	for boost in [true, false]:
		var f := AtmoFlight.new()
		f.setup(content.get_ship("interceptor"), ground)
		f.park(Vector3(0.3, -6, 0), -PI * 0.5)
		f.takeoff()
		var t := 0.0
		var want := sin(deg_to_rad(80.0))
		while t < 90.0 and not f.reached_space:
			var pc := clampf((want - f.flight.forward().y) * 4.0, -1.0, 1.0) if f.state == AtmoFlight.State.FLYING else 0.0
			f.set_command(pc, 0, 0, 1.0, boost)
			f.step(DT)
			t += DT
		assert_between(t, 30.0, 40.0, "takeoff to space in 30-40 s (boost %s): %.1f s" % [boost, t])


func test_dogfight_flight_is_unchanged() -> void:
	var fm = FlightModel.new(content.get_ship("interceptor").flight)
	assert_eq(fm.speed_scale, 1.0)
	assert_eq(fm.max_speed(), float(content.get_ship("interceptor").flight.max_speed),
		"space speeds are the M10 numbers")
