extends GutTest
## V's third view: the cinematic camera cuts to a new shot every few seconds,
## trails its subject between cuts and never sits behind a wall. A story opens in
## it, and says V changes it eight seconds in.

const Shots := preload("res://src/systems/camera/cinematic_shots.gd")
const TownDemo := preload("res://scenes/town_demo.gd")


func test_cuts_to_a_new_shot_every_shot_time() -> void:
	var c = Shots.new()
	c.update(0.1, Vector3.ZERO, Vector3.FORWARD)
	assert_eq(c.cuts, 1, "the first frame is a cut")
	var first: int = c.shot
	for i in 38:
		c.update(0.1, Vector3.ZERO, Vector3.FORWARD)
	assert_eq(c.cuts, 1, "a shot holds for its four seconds")
	c.update(0.25, Vector3.ZERO, Vector3.FORWARD)
	assert_eq(c.cuts, 2, "then cuts")
	assert_ne(c.shot, first, "never to the shot already on screen")


func test_frames_and_trails_the_subject() -> void:
	var c = Shots.new()
	c.update(0.016, Vector3.ZERO, Vector3.FORWARD)
	var cam0: Vector3 = c.xform.origin
	var at := Vector3.ZERO
	for i in 60:
		at += Vector3(0, 0, -3.0 * 0.016)
		c.update(0.016, at, Vector3.FORWARD)
	assert_eq(c.cuts, 1)
	assert_gt(c.xform.origin.distance_to(cam0), 0.1, "the camera drifts after the subject")
	var to_subject: Vector3 = (at - c.xform.origin).normalized()
	assert_gt(-c.xform.basis.z.dot(to_subject), 0.95, "and keeps looking at it")


func test_a_fast_subject_does_not_cut_the_shot_every_second() -> void:
	# A speeder (50 m/s, shots 6 m to the unit) and a ship (180 m/s, 9 m): both
	# hold a shot for its four seconds, like a runner, instead of outrunning it.
	for rig in [[50.0, 6.0], [180.0, 9.0]]:
		var c = Shots.new()
		c.scale = rig[1]
		var at := Vector3.ZERO
		c.update(0.016, at, Vector3.FORWARD)
		for i in 180:   # about 3 seconds
			at += Vector3(0, 0, -rig[0] * 0.016)
			c.update(0.016, at, Vector3.FORWARD)
		assert_eq(c.cuts, 1, "%d m/s holds its shot for the full time" % rig[0])
		var to_subject: Vector3 = (at - c.xform.origin).normalized()
		assert_gt(-c.xform.basis.z.dot(to_subject), 0.95, "and still frames the subject")


func test_cuts_early_when_the_subject_gets_away() -> void:
	var c = Shots.new()
	c.update(0.016, Vector3.ZERO, Vector3.FORWARD)
	c.update(0.016, Vector3(0, 0, -100), Vector3.FORWARD)
	assert_eq(c.cuts, 2)


func test_a_wall_pulls_the_shot_in_front_of_it() -> void:
	var c = Shots.new()
	# Everything more than 2 m from the subject is behind a wall.
	c.blocked = func(from: Vector3, to: Vector3) -> Vector3:
		return to if from.distance_to(to) <= 2.0 else from + (to - from).normalized() * 2.0
	c.update(0.016, Vector3.ZERO, Vector3.FORWARD)
	assert_lte(c.xform.origin.length(), 2.01, "the shot sits on the near side of the wall")


func test_a_story_opens_in_the_cinematic_view_and_names_v_and_j_after_8s() -> void:
	WorldState.new_game(WorldState.STORY)
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	await wait_physics_frames(3)
	var pilot = t.pilot
	assert_true(pilot.opening, "a story opens with the landing")
	assert_true(pilot.chase.is_cinematic(), "filmed in the cinematic view")
	assert_eq(pilot.hud.prompt.text, "", "nothing on screen for its first seconds")
	assert_false(pilot.hud.sim.visible, "no reticle or ladder over a cinematic shot")
	assert_eq(Sound.lib().radio, "dust_lounge", "the radio comes on to the desert cantina mix")
	pilot.opening_t = float(Story.data().get("opening_cinematic_secs", 8.0))
	pilot._physics_process(1.0 / 60.0)
	assert_eq(pilot.hud.prompt.text, "Press V to switch views    Press J to change radio")
	pilot.chase.toggle_mode()
	assert_false(pilot.chase.is_cinematic(), "V moves on to the chase view")
	assert_eq(Sound.radio_next(), "salvage_rave", "J moves the radio on to the next station")
	Sound.lib().set_radio("")
	WorldState.reset()


func test_on_foot_v_reaches_cinematic_and_the_guns_still_aim_ahead() -> void:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	await wait_process_frames(3)
	var rig = t._rig
	rig.set_view(rig.CameraRig.Mode.TPV)
	await wait_process_frames(2)
	var shoulder: Transform3D = rig.camera().global_transform
	rig.toggle_view()
	assert_true(rig.is_cinematic(), "V after third person is cinematic")
	await wait_process_frames(2)
	assert_eq(rig.cine.cuts, 1)
	assert_gt(rig.camera().global_position.distance_to(shoulder.origin), 0.5, "the camera is off the shoulder")
	assert_almost_eq(rig.aim_transform().basis.z, shoulder.basis.z, Vector3.ONE * 0.01, "the aim is the third person view's")
	rig.toggle_view()
	assert_true(rig.rig.is_first_person(), "and V after cinematic is first person")
