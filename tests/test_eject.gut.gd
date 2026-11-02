extends GutTest
## Issue #271: eject from the ship in flight.
##   #274 falls hurt the player: nothing under the safe speed, a straight line up to
##        lethal, a capped fall speed, and a jetpack burn can save you.
##   #275 B held in the air throws you clear of the ship, falling on foot.
##   #276 the empty ship carries on ADRIFT at zero throttle: damaged by the fall she
##        crashes and is towed home; slow enough, she comes to rest where she lands.

const FallDamage := preload("res://src/systems/combat/fall_damage.gd")
const CharacterBody := preload("res://src/systems/player/character_body.gd")
const Jetpack := preload("res://src/systems/player/jetpack.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0

var content


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ #274 fall damage

func test_the_damage_curve_comes_from_data() -> void:
	var c := FallDamage.cfg()
	assert_false(c.is_empty(), "falls.json is read")
	var safe := float(c.safe_speed)
	var lethal := float(c.lethal_speed)
	assert_eq(FallDamage.damage(safe, c), 0, "nothing at the safe speed")
	assert_eq(FallDamage.damage(sqrt(40.0 * 3.0), c), 0, "a 3 m drop is nothing")
	assert_gt(FallDamage.damage(safe + 4.0, c), 0, "a little over hurts")
	assert_lt(FallDamage.damage(safe + 4.0, c), int(c.lethal_damage), "but does not kill")
	assert_eq(FallDamage.damage(lethal, c), int(c.lethal_damage), "lethal at the lethal speed")
	assert_gt(FallDamage.terminal_speed(c), lethal, "falling from high up is lethal")


## A player standing on a floor, dropped from `height` metres.
func _dropped(height: float) -> CharacterBody3D:
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	floor.add_child(cs)
	add_child_autofree(floor)
	var p := CharacterBody.new()
	p.fall_damage = FallDamage.cfg()
	p.position = Vector3(0, height, 0)
	add_child_autofree(p)
	p.set_command(Vector2.ZERO, false, false, false)
	return p


func _fall(p: CharacterBody3D, max_s: float, jet_below := -1.0) -> void:
	for i in int(max_s * 60.0):
		await wait_physics_frames(1)
		if jet_below > 0.0 and p.global_position.y < jet_below:
			p.set_command(Vector2.ZERO, false, false, false, true)    # hold jump: the pack lights
		if p.is_on_floor() and i > 2:
			return


func test_short_drops_do_nothing_long_ones_hurt_and_high_ones_kill() -> void:
	var p := _dropped(4.0)
	await _fall(p, 3.0)
	assert_true(p.is_on_floor())
	assert_eq(p.health.hp, p.max_health, "a 4 m drop is free")
	p.global_position = Vector3(0, 15.0, 0)
	p.align_to_ground(true)
	await _fall(p, 4.0)
	assert_lt(p.health.hp, p.max_health, "15 m hurts")
	assert_false(p.is_downed, "but you walk away")
	p.revive(0.0)
	p.global_position = Vector3(0, 120.0, 0)
	p.align_to_ground(true)
	await _fall(p, 8.0)
	assert_almost_eq(p.fall_speed, FallDamage.terminal_speed(FallDamage.cfg()), 1.0, "you never fall faster than terminal speed")
	assert_true(p.is_downed, "120 m kills")


func test_a_jetpack_burn_saves_you() -> void:
	var p := _dropped(160.0)
	p.jetpack = Jetpack.new(content.get_item("jetpack").get("jetpack", {}))
	await _fall(p, 10.0, 75.0)
	assert_true(p.is_on_floor())
	assert_gt(p.jetpack.burned, 1.0, "the pack burned")
	assert_false(p.is_downed, "it took enough off the fall (landed at %.1f m/s)" % p.fall_speed)


func test_guards_never_take_fall_damage() -> void:
	var p := _dropped(120.0)
	p.fall_damage = {}
	await _fall(p, 8.0)
	assert_eq(p.health.hp, p.max_health, "only the player is given falls.json")


# ------------------------------------------------------------------ #276 the ship adrift

func _atmo() -> AtmoFlight:
	var town = TownLayout.new()
	town.load_town("port_town")
	var ground := WorldGround.new()
	ground.setup(content.get_world("port_desert"), town, content)
	var a := AtmoFlight.new()
	a.setup(content.get_ship("interceptor"), ground)
	return a


func _drift(a: AtmoFlight, seconds: float) -> Array:
	var ev: Array = []
	for i in int(seconds * 60.0):
		for e in a.step(DT):
			ev.append(e.type)
		if a.state != AtmoFlight.State.ADRIFT:
			break
	return ev


func test_only_a_ship_in_the_air_can_be_abandoned() -> void:
	var a := _atmo()
	a.park(Vector3(40, 0, 0), 0.0)
	assert_false(a.abandon(), "parked: nothing to drift")
	a.place_flying(Vector3(40, 200, 0), Vector3.FORWARD, 50.0, 0.6)
	assert_true(a.abandon())
	assert_eq(a.state, AtmoFlight.State.ADRIFT)
	assert_almost_eq(a.drift.length(), 50.0, 0.01, "she keeps her way on")
	assert_eq(float(a._command.throttle), 0.0, "zero throttle")


func test_adrift_she_keeps_going_and_falls() -> void:
	var a := _atmo()
	a.place_flying(Vector3(40, 1500, 0), Vector3.FORWARD, 80.0, 0.6)
	var start := a.position()
	a.abandon()
	_drift(a, 2.0)
	assert_eq(a.state, AtmoFlight.State.ADRIFT, "still coming down")
	var moved := a.position() - start
	assert_gt(-moved.z, 100.0, "carried on the way she was going")
	assert_lt(moved.y, -20.0, "and dropping: nothing holds her up")
	assert_lt(a.flight.forward().y, -0.1, "nose dropping with her fall")


func test_a_hard_landing_damages_her_and_she_crashes() -> void:
	var a := _atmo()
	a.place_flying(Vector3(40, 400, 0), Vector3(0, -0.5, -1).normalized(), 100.0, 0.6)
	a.abandon()
	var ev := _drift(a, 30.0)
	assert_true(ev.has("crashed"), "came down faster than crash_speed")
	assert_eq(a.state, AtmoFlight.State.CRASHED)


func test_a_slow_low_drop_sets_her_down_intact() -> void:
	var a := _atmo()
	a.park(Vector3(40, 0, 0), 0.0)
	var gy := a.ground_below()
	a.place_flying(Vector3(40, gy + a.clearance + 8.0, 0), Vector3.FORWARD, 0.0, 0.0)
	a.abandon()
	var ev := _drift(a, 10.0)
	assert_false(ev.has("crashed"))
	assert_true(ev.has("landed"))
	assert_eq(a.state, AtmoFlight.State.PARKED, "resting where she came down")
	assert_almost_eq(a.agl(), 0.0, 0.05)


# ------------------------------------------------------------------ #275 ejecting, in the town

func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


## The town's navigation finishes building first (a test that ends sooner frees
## the town under its wait for the map).
func _settled(t) -> void:
	for i in 300:
		if t.nav == null or t.nav.is_ready:
			return
		await wait_physics_frames(1)


## Seated in the pit's ship, then put in the air `agl` metres up at `speed`.
func _flying(t, agl: float, speed: float, facing := Vector3.FORWARD) -> ShipPilot:
	var pilot: ShipPilot = t.pilot
	var p = t._player
	var s: Vector3 = pilot.visual.global_position
	p.global_position = s + Vector3(6.0, -float(pilot.berths[pilot.berth].clearance), 0.0)
	assert_true(pilot.board(), "boards the pit's ship")
	var up := pilot.atmo.up()
	pilot.atmo.place_flying(pilot.atmo.position() + up * agl, facing, speed, 0.0)
	pilot._throttle = 0.0
	pilot.set_external_command({ "throttle": 0.0 })
	return pilot


func test_no_ejecting_on_the_ground_or_in_the_opening() -> void:
	var t = _town()
	await _settled(t)
	var pilot: ShipPilot = t.pilot
	var p = t._player
	p.global_position = pilot.visual.global_position + Vector3(6.0, -float(pilot.berths[pilot.berth].clearance), 0.0)
	assert_true(pilot.board())
	assert_false(pilot.can_eject(), "parked: E gets you out")
	pilot.atmo.place_flying(pilot.atmo.position() + Vector3.UP * 100.0, Vector3.FORWARD, 0.0, 0.0)
	assert_true(pilot.can_eject())
	pilot.opening = true
	assert_false(pilot.can_eject(), "the story's opening landing keeps you seated")
	pilot.opening = false
	pilot.atmo.place_flying(Vector3(0, pilot.atmo.space_altitude + 50.0, 0), Vector3.FORWARD, 0.0, 0.0)
	assert_false(pilot.can_eject(), "not in space")


func test_eject_throws_you_clear_and_the_empty_ship_crashes_and_is_towed_home() -> void:
	var t = _town()
	await _settled(t)
	var pilot := _flying(t, 300.0, 90.0, Vector3(0, -0.3, -1).normalized())
	var p = t._player
	await wait_physics_frames(2)
	var ship_at := pilot.atmo.position()
	assert_true(pilot.eject())
	assert_false(pilot.piloting, "out of the seat")
	assert_false(p.piloting)
	assert_true(p.visible)
	assert_eq(p.process_mode, Node.PROCESS_MODE_INHERIT, "your own body again")
	assert_false(pilot.hud.visible, "no flight HUD")
	assert_gt((p.global_position - ship_at).dot(pilot.atmo.up()), pilot.atmo.clearance, "thrown clear above her")
	assert_eq(pilot.atmo.state, AtmoFlight.State.ADRIFT)
	assert_eq(pilot.ejections, 1)
	assert_false(pilot.eject(), "only once")
	var up := pilot.atmo.up()
	var ship_climb := pilot.atmo.drift.dot(up)
	await wait_physics_frames(1)
	assert_gt(p.velocity.dot(up), ship_climb + 8.0, "kicked up out of her way")
	assert_gt(p.controller.push.length(), 30.0, "carried on with her speed")
	var towed := false
	for i in 60 * 30:
		await wait_physics_frames(1)
		if pilot.log_events.any(func(e): return e.type == "crashed") and pilot.is_parked_home():
			towed = true
			break
	assert_true(towed, "she crashed and was towed back to her pad")
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED)
	assert_true(pilot.visual.visible, "back on the pad, seen")
	for i in 60 * 10:
		if p.is_on_floor() or p.is_downed:
			break
		await wait_physics_frames(1)
	assert_true(p.is_downed, "a 300 m fall with no jetpack is fatal (landed at %.1f m/s)" % p.fall_speed)


func test_ejecting_low_and_slow_she_lands_where_she_comes_down() -> void:
	var t = _town()
	await _settled(t)
	var pilot := _flying(t, 8.0, 0.0)
	await wait_physics_frames(2)
	assert_true(pilot.eject())
	for i in 60 * 6:
		await wait_physics_frames(1)
		if pilot.atmo.state != AtmoFlight.State.ADRIFT:
			break
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "set down intact")
	assert_false(pilot.log_events.any(func(e): return e.type == "crashed"))
	assert_false(t._player.is_downed, "an 8 m hop out does not kill you")


# ------------------------------------------------ your own ship flies home, a stolen one crashes

func test_ejecting_from_your_own_ship_flies_her_home() -> void:
	WorldState.hangar = "courier"
	var t = _town()
	await _settled(t)
	var pilot := _flying(t, 300.0, 90.0, Vector3(0, -0.3, -1).normalized())
	await wait_physics_frames(2)
	assert_eq(pilot.berth_key(), Fleet.T89)
	assert_true(pilot.ejecting_flies_home())
	assert_true(pilot.eject())
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "no fall to simulate: she is on her pad")
	assert_true(pilot.is_parked_home())
	assert_true(pilot.visual.visible)
	for i in 60 * 5:
		await wait_physics_frames(1)
	assert_false(pilot.log_events.any(func(e): return e.type == "crashed"), "she never crashes")
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED)
	var p = t._player
	p.global_position = pilot.visual.global_position + Vector3(40.0, 0.0, 0.0)
	assert_eq(pilot.call_ship(), "", "Call (the ledger's button, I) brings her back")


func test_ejecting_from_a_stolen_ship_still_crashes_her() -> void:
	WorldState.hangar = "courier"
	var t = _town()
	await _settled(t)
	var pilot := _flying(t, 300.0, 90.0, Vector3(0, -0.3, -1).normalized())
	pilot.berths[pilot.berth]["stolen"] = true
	assert_false(pilot.ejecting_flies_home(), "not yours to send home")
	await wait_physics_frames(2)
	assert_true(pilot.eject())
	assert_eq(pilot.atmo.state, AtmoFlight.State.ADRIFT)
