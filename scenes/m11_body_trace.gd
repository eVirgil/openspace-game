extends SceneTree
## M11 trace (headless): the player's body and hand weapons, end to end, with real
## physics. Writes test_results/m11_body_trace.txt (KEY=value lines) for
## tests/test_m11_body_weapons.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/m11_body_trace.gd

const OUT := "res://test_results/m11_body_trace.txt"

var demo
var kit: PlayerKit
var w: PlayerWeapons
var player
var rig
var lines := PackedStringArray()
var worst_ms := 0.0
var _last := 0


func _initialize() -> void:
	WorldState.reset()
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false   # M15: guards hold their posts; this trace is about something else
	demo.use_look = false
	get_root().add_child(demo)
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0 and _frames > 30:
		worst_ms = maxf(worst_ms, (now - _last) / 1000.0)
	_last = now
	_frames += 1
	return false

var _frames := 0


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func place(p: Vector3, yaw: float, pitch: float = 0.0) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.controller.body_pos = p
	player.controller.velocity = Vector3.ZERO
	rig.rig.yaw = yaw
	rig.rig.pitch = pitch
	kit.avatar.facing_yaw = yaw


func aim_at(target: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	var d := target - eye
	rig.rig.yaw = atan2(d.x, d.z)
	rig.rig.pitch = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	await frames(5)
	demo._attach_body()
	kit = demo.player_kit
	w = kit.weapons
	player = demo._player
	rig = demo._rig
	await frames(5)
	out("BODY_BUILT", kit.avatar.body != null and kit.avatar.joints.has("r_wrist"))
	out("WEAPON_MODELS", w.avatar.weapons.size())

	# ---- locomotion states
	place(Vector3(6, -6, 9), 0.0)
	player.set_command(Vector2(0, 1), false, false, false)
	await frames(40)
	out("WALK_SPEED", snappedf(Vector2(player.velocity.x, player.velocity.z).length(), 0.01))
	out("GAIT_PHASE_MOVED", kit.avatar.anim.phase > 0.0)
	player.set_command(Vector2(0, 1), true, false, false)
	place(Vector3(6, -6, 9), 0.0)
	player.set_command(Vector2(0, 1), true, false, false)
	await frames(40)
	out("SPRINT_SPEED", snappedf(Vector2(player.velocity.x, player.velocity.z).length(), 0.01))
	player.set_command(Vector2.ZERO, false, false, true)
	await frames(1)
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(80)
	player.set_command(Vector2.ZERO, false, true, false)
	await frames(30)
	out("CROUCH_PELVIS", snappedf(kit.avatar.anim.pelvis_y, 0.01))
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(20)
	out("STATES_SEEN", ",".join(PackedStringArray(kit.avatar.anim.states_seen.keys())))

	# ---- facing: free hands face travel, armed faces the camera
	rig.set_first_person(false)        # first person always faces the camera
	place(Vector3(0, -6, 12), 0.0)
	player.set_command(Vector2(1, 0), false, false, false)      # strafe
	await frames(60)
	var vel: Vector3 = player.velocity
	out("STRAFE_SPEED", snappedf(Vector2(vel.x, vel.z).length(), 0.01))
	out("FACING_ERR", snappedf(absf(wrapf(kit.avatar.facing_yaw - atan2(vel.x, vel.z), -PI, PI)), 0.01))
	out("FACES_TRAVEL", absf(wrapf(kit.avatar.facing_yaw - atan2(vel.x, vel.z), -PI, PI)) < 0.3)
	player.set_command(Vector2.ZERO, false, false, false)

	# ---- view toggles: spam 9 times (3 laps of FPV/TPV/cinematic) in 9 frames, must end where it started
	var start_fp: bool = rig.rig.is_first_person()
	for i in 9:
		rig.toggle_view()
		await frames(1)
	await frames(20)
	out("TOGGLE_SPAM_OK", rig.rig.is_first_person() == start_fp and kit.avatar.first_person == start_fp)
	rig.set_first_person(true)
	await frames(2)
	var hidden := 0
	for m in kit.avatar._other_meshes:
		if m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			hidden += 1
	# A rigged skin is one mesh; the primitive body is 20+.
	var skinned: bool = kit.avatar.skin != null
	out("FPV_BODY_SHADOW_ONLY", hidden == kit.avatar._other_meshes.size() and hidden >= (1 if skinned else 21))
	# The arms in first person are FpvArms (sleeves and gloves) for every body; the
	# kit's own forearms stay hidden over a skin.
	var fpv_meshes: Array = kit.avatar._fpv.meshes()
	var kit_arms_hidden := true
	if skinned:
		for m in kit.avatar._kit_arms:
			if m.visible:
				kit_arms_hidden = false
	out("FPV_ARMS_VISIBLE", fpv_meshes.size() > 4 and kit.avatar._fpv.visible and kit_arms_hidden)

	# ---- third person camera never ends up inside a wall
	rig.set_first_person(false)
	place(Vector3(16.6, -6, 0), -PI * 0.5)      # back to the pit's east wall
	await frames(30)
	var cam: Camera3D = rig.camera()
	out("CAM_X_NEAR_WALL", snappedf(cam.global_position.x, 0.01))
	out("CAM_INSIDE_PIT", cam.global_position.x < 17.5)

	# ---- swap spam: 1,3,1,2,3 in five frames -> ends on the sword, cleanly
	place(Vector3(6, -6, 12), PI)
	for s in [1, 3, 1, 2, 3]:
		w.holder.request_slot(s)
		await frames(1)
	await frames(40)
	out("SWAP_END", w.holder.current)
	out("SWAP_IDLE", not w.holder.is_swapping())
	var vis: Array = []
	for id in kit.avatar.weapons:
		if kit.avatar.weapons[id].visible:
			vis.append(id)
	out("SWAP_VISIBLE", ",".join(PackedStringArray(vis)))
	out("BLADE_LIT", w.blade_extent > 0.99)
	w.holder.request("")
	await frames(30)
	out("HOLSTER_BLADE_OFF", w.blade_extent < 0.01 and w.holder.current == "")

	# ---- pistol at a range target
	var t2: Node3D = demo.training_range.targets[1]
	place(Vector3(-6, -6, 12.5), -PI * 0.5)
	rig.set_first_person(true)
	aim_at(t2.global_position + Vector3(0, 1.45, 0))
	w.holder.request("pistol_blaster")
	await frames(30)
	var pistol = w.guns["pistol_blaster"]
	w.press_fire()
	for i in 80:
		aim_at(t2.global_position + Vector3(0, 1.45, 0))
		await frames(1)
	w.release_fire()
	await frames(30)
	out("PISTOL_SHOTS", w.shots)
	out("PISTOL_AMMO_LEFT", pistol.ammo)
	out("TARGET_HITS", t2.hits)
	out("TARGET_DOWN", t2.is_down)
	out("RANGE_SHOTS_COUNTED", WorldState.count("range_shots"))
	out("NO_STREET_FLAG_ON_RANGE", not WorldState.has_flag("shots_in_street"))
	# Reload
	w.press_fire()
	await frames(150)
	w.release_fire()
	pistol.start_reloading()
	await frames(100)
	out("RELOADED", pistol.ammo == int(pistol.config.mag))

	# ---- right-click TOGGLES aim (blaster zoom) on, then off
	place(Vector3(-6, -6, 12.5), -PI * 0.5)
	rig.set_first_person(true)
	w.toggle_alt()
	await frames(60)
	out("AIM_ON", w.aiming)
	out("AIM_ZOOMED", w.rig_node != null and w.rig_node.camera().fov < 75.0)
	w.toggle_alt()
	await frames(60)
	out("AIM_OFF", not w.aiming)

	# ---- sword combo on a target
	var t4: Node3D = demo.training_range.targets[3]
	var hits_before: int = t4.hits
	place(t4.global_position + Vector3(0, 0, -1.25), 0.0)
	rig.set_first_person(false)
	w.holder.request("energy_blade")
	await frames(30)
	w.press_fire()
	w.release_fire()
	var swings_seen := {}
	for i in 110:
		if i == 18 or i == 48:
			w.press_fire()
			w.release_fire()
		if w.combo.mode == SwordCombo.Mode.SWING:
			swings_seen[w.combo.swing_index] = true
		await frames(1)
	out("COMBO_SWINGS", w.combo.swings_started)
	out("COMBO_STAGES", swings_seen.size())
	out("SWORD_HITS", t4.hits - hits_before)

	# ---- deflection: the sparring remote shoots, we time a block
	var rng: TrainingRange = demo.training_range
	var home := TrainingRange._v3(rng.spec.remote.pos)
	place(Vector3(home.x, -6, home.z + 6.0), PI)
	if w.holder.current != "energy_blade":
		w.holder.request("energy_blade")
	await frames(20)
	var blocked_at := -1
	for i in 600:
		var chest: Vector3 = player.global_position + Vector3(0, 1.25, 0)
		rig.rig.yaw = atan2(rng.remote.global_position.x - player.global_position.x, rng.remote.global_position.z - player.global_position.z)
		for b in get_nodes_in_group("bolts"):
			if b.shooter == player or b.get_meta("intercepted", false):
				continue
			var d: float = (chest - b.global_position).length() - 1.5
			if d / maxf(b.speed, 0.1) < 0.08 and w.combo.mode != SwordCombo.Mode.BLOCK:
				w.set_alt(true)
				blocked_at = i
		if blocked_at >= 0 and i - blocked_at > 20:
			w.set_alt(false)
			blocked_at = -1
		if w.deflections >= 3 and rng.remote_hits >= 1:
			break
		await frames(1)
	w.set_alt(false)
	await frames(60)
	out("REMOTE_SHOTS", rng.remote_shots)
	out("DEFLECTIONS", w.deflections)
	out("REMOTE_HITS", rng.remote_hits)
	out("PLAYER_HITS_TAKEN", player.hits_taken)

	# ---- shots in the street are noticed
	var remnant_before := int(WorldState.standing.imperial_remnant)
	place(Vector3(-30, 0, 0), PI * 0.5)
	w.holder.request("pistol_blaster")
	await frames(30)
	w.press_fire()
	await frames(3)
	w.release_fire()
	await frames(10)
	out("STREET_FLAG", WorldState.has_flag("shots_in_street"))
	out("REMNANT_STANDING_DROP", remnant_before - int(WorldState.standing.imperial_remnant))

	out("WORST_FRAME_MS", snappedf(worst_ms, 0.1))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("\n".join(lines))
	quit()
