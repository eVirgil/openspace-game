extends GutTest
## The cockpit's seeker warning: an enemy lock or seeker on the player's ship sounds
## an alarm (and flashes a lamp) for 5 s, then it is quiet for 1 s, then it may go off
## again if the threat is still there. Not annoying: one alarm at a time, never faster.

const SeekerWarning := preload("res://src/systems/flight/seeker_warning.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")


func _warning() -> SeekerWarning:
	var w := SeekerWarning.new()
	w.configure(5.0, 1.0, 2.0)
	return w


## Run `secs` of frames with the threat as given; returns the seconds it sounded.
func _run(w: SeekerWarning, secs: float, threat: bool) -> float:
	var sounded := 0.0
	var dt := 1.0 / 60.0
	for i in int(round(secs / dt)):
		w.update(dt, threat)
		if w.sounding:
			sounded += dt
	return sounded


func test_quiet_without_a_threat() -> void:
	var w := _warning()
	assert_almost_eq(_run(w, 10.0, false), 0.0, 0.001)
	assert_eq(w.sounds, 0)
	assert_false(w.lamp_on())


func test_sounds_for_five_seconds_then_shuts_off() -> void:
	var w := _warning()
	w.update(0.016, true)
	assert_true(w.sounding, "goes off the moment there is a lock")
	_run(w, 4.9, true)
	assert_true(w.sounding, "still going at 4.9 s")
	_run(w, 0.3, true)
	assert_false(w.sounding, "off by 5 s, with the threat still there")
	assert_eq(w.sounds, 1)


func test_cannot_go_again_for_one_second() -> void:
	var w := _warning()
	_run(w, 5.1, true)
	assert_false(w.sounding)
	_run(w, 0.8, true)
	assert_false(w.sounding, "still resting 0.9 s after it shut off")
	_run(w, 0.4, true)
	assert_true(w.sounding, "goes again once the second is up and the threat remains")
	assert_eq(w.sounds, 2)


func test_does_not_go_again_when_the_threat_is_gone() -> void:
	var w := _warning()
	_run(w, 5.1, true)
	_run(w, 3.0, false)
	assert_false(w.sounding)
	assert_eq(w.sounds, 1)


func test_losing_the_threat_cuts_it_off_and_the_rest_applies() -> void:
	var w := _warning()
	_run(w, 2.0, true)
	assert_true(w.sounding)
	w.update(0.016, false)
	assert_false(w.sounding, "the lock broke: the alarm stops")
	_run(w, 0.5, true)
	assert_false(w.sounding, "a fresh lock inside the rest second does not set it off")
	_run(w, 0.6, true)
	assert_true(w.sounding, "and does after it")


func test_a_long_chase_alarms_five_seconds_in_every_six() -> void:
	var w := _warning()
	var sounded := _run(w, 60.0, true)
	assert_almost_eq(sounded, 50.0, 1.0)
	assert_between(w.sounds, 9, 11)


func test_the_lamp_flashes_only_while_it_sounds() -> void:
	var w := _warning()
	w.update(0.016, true)
	assert_true(w.lamp_on(), "lit as it goes off")
	_run(w, 0.3, true)
	assert_false(w.lamp_on(), "dark in the second half of a flash")
	_run(w, 0.25, true)
	assert_true(w.lamp_on(), "lit again on the next")
	_run(w, 6.0, false)
	assert_false(w.lamp_on(), "dark once it is off")


# ---- the director's side --------------------------------------------------------

func _fight() -> Dogfight:
	var content := CoreContent.new()
	content.load_from()
	var df := Dogfight.new(content, "orbital_skirmish", 1)
	df.start()
	return df


func test_no_enemy_lock_or_seeker_at_the_start() -> void:
	var df := _fight()
	var s := df.seekers_on_player()
	assert_eq(int(s.locks) + int(s.missiles), 0)


func test_an_enemy_lock_on_her_counts() -> void:
	var df := _fight()
	for i in 600:      # the first wave arrives after its timer
		if not df.alive_on(Dogfight.TEAM_HOSTILE).is_empty():
			break
		df.step(0.05)
	var foes := df.alive_on(Dogfight.TEAM_HOSTILE)
	assert_false(foes.is_empty(), "a hostile has arrived")
	if foes.is_empty():
		return
	var foe: Dictionary = foes.front()
	foe.lock.target_id = df.player_id
	foe.lock.progress = foe.lock.lock_time
	assert_eq(int(df.seekers_on_player().locks), 1)
	foe.lock.target_id = -1
	assert_eq(int(df.seekers_on_player().locks), 0, "locked on someone else: not her")


func test_an_enemy_seeker_in_flight_at_her_counts_but_hers_do_not() -> void:
	var df := _fight()
	var me: Dictionary = df.get_ship(df.player_id)
	var spawn := { "kind": "missile", "homing": true, "target_id": df.player_id,
		"origin": me.flight.position + Vector3(0, 0, -500), "velocity": Vector3(0, 0, 100) }
	df.projectiles.add(spawn, 999, Dogfight.TEAM_HOSTILE)
	assert_eq(int(df.seekers_on_player().missiles), 1)
	df.projectiles.items.clear()
	df.projectiles.add(spawn, df.player_id, Dogfight.TEAM_PLAYER)
	assert_eq(int(df.seekers_on_player().missiles), 0, "her own seeker is not a warning")
	df.projectiles.items.clear()
	df.projectiles.add(spawn, 999, Dogfight.TEAM_HOSTILE)
	df.player_sheltered = true
	assert_eq(int(df.seekers_on_player().missiles), 0, "nothing while she is out of the fight")


# ---- data -----------------------------------------------------------------------

func test_the_text_and_numbers_are_data() -> void:
	assert_eq(GameFlow.label("seeker_warning"), "ENEMY LOCK - MISSILES INBOUND")
	assert_eq(GameFlow.setting("seeker_alarm_secs", 0.0), 5.0)
	assert_eq(GameFlow.setting("seeker_alarm_rest", 0.0), 1.0)


func test_the_hud_shows_the_text_and_the_dash_gets_the_lamp() -> void:
	var hud := FlightHud.new()
	add_child_autofree(hud)
	hud.set_seeker_warning(true, true)
	assert_true(hud.warn_label.visible)
	assert_true(bool(hud.values.get("seeker_lamp")), "the dash's lamp is lit")
	hud.show_values({ "speed": 10.0 })
	assert_true(bool(hud.values.get("seeker_lamp")), "and stays lit through the next read-out")
	hud.set_seeker_warning(true, false)
	assert_false(bool(hud.values.get("seeker_lamp")), "dark in the off half of a flash")
	hud.set_seeker_warning(false, false)
	assert_false(hud.warn_label.visible)


func test_the_cockpit_view_has_the_lamp_but_not_the_text() -> void:
	var hud := FlightHud.new()
	add_child_autofree(hud)
	hud.set_cockpit(true)
	hud.set_seeker_warning(true, true)
	assert_false(hud.warn_label.visible, "no text in the cockpit view")
	assert_true(bool(hud.values.get("seeker_lamp")), "the lamp flashes")
	hud.set_cockpit(false)
	hud.set_seeker_warning(true, true)
	assert_true(hud.warn_label.visible, "the chase view shows the text")


# ---- on the planet, with or without a space fight ---------------------------------

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0


## A stolen ship in the air over the port, the Remnant interceptor up and hunting.
func _hunted() -> Node:
	GameFlow.reset()
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	var t = TownDemo.new()
	t.use_look = false
	t.nav_async = false
	add_child_autofree(t)
	await wait_physics_frames(2)
	var i := -1
	for k in t.pilot.berths.size():
		if str(t.pilot.berths[k].get("outpost", "")) == "remnant_outpost_near":
			i = k
	var v: Node3D = t.pilot.berths[i].visual
	t._player.global_position = v.global_position + Vector3(6, -float(t.pilot.berths[i].clearance), 0)
	t.pilot.board()
	t.pilot.takeoff()
	_fly(t, 8.0, { "throttle": 0.4 })
	# It may already have launched on its own; start from clean air and no lock.
	for b in get_tree().get_nodes_in_group("bolts"):
		if is_instance_valid(b) and "seek" in b and b.seek == t.pilot.hull:
			b.queue_free()
	t.interceptor.lock.reset()
	await wait_physics_frames(2)
	t.pilot.seeker_warning.reset()
	t.pilot._seeker_step(DT)
	return t


func _fly(t, secs: float, cmd: Dictionary = {}) -> void:
	t.pilot.set_physics_process(false)
	t.interceptor.set_physics_process(false)
	if not cmd.is_empty():
		t.pilot.set_external_command(cmd)
	for i in int(secs / DT):
		t.pilot._physics_process(DT)
		t.interceptor.step(DT)


func test_the_interceptor_s_lock_sets_the_warning_off_on_the_planet() -> void:
	var t = await _hunted()
	var f: AtmoFighter = t.interceptor
	assert_eq(f.mode, AtmoFighter.Mode.HUNTING)
	assert_null(t.pilot.fight, "no space fight: this is the planet")
	assert_false(t.pilot.seeker_warning.sounding)
	f.lock.target_id = 1
	f.lock.progress = f.lock.lock_time
	assert_eq(int(f.seekers_on_player().locks), 1)
	t.pilot._seeker_step(DT)
	assert_true(t.pilot.seeker_warning.sounding, "the lock sounds the alarm")
	assert_true(t.pilot.hud.warn_label.visible, "and shows the text in the chase view")
	f.lock.reset()
	t.pilot._seeker_step(DT)
	assert_false(t.pilot.seeker_warning.sounding, "it stops when the lock goes")


func test_a_seeker_in_the_air_at_your_ship_sets_it_off_too() -> void:
	var t = await _hunted()
	var f: AtmoFighter = t.interceptor
	var spawns: Array = f.guns.fire(DT, f.atmo.transform(), Vector3.ZERO, false, true, 1)
	var made := 0
	var before := f.seekers
	for s in spawns:
		if str(s.kind) == "missile":
			f._launch_seeker(s)
			made += 1
	assert_eq(made, 1, "its rack launched one")
	assert_eq(f.seekers, before + 1)
	await wait_physics_frames(2)
	assert_eq(int(f.seekers_on_player().missiles), 1, "the seeker is after your hull")
	t.pilot._seeker_step(DT)
	assert_true(t.pilot.seeker_warning.sounding, "missiles inbound")


func test_it_is_data_whether_the_interceptor_uses_seekers() -> void:
	var content := CoreContent.new()
	content.load_from()
	assert_true(bool(content.get_pilot("remnant_hunter").get("missile_use", false)))
	assert_gt(float(content.get_ship("remnant_interceptor").scramble.get("seeker_gap_s", 0.0)), 0.0)
