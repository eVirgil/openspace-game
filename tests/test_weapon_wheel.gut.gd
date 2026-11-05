extends GutTest
## Issue #410: the Tab weapon wheel. The pure part (WeaponWheel) on its own, then
## PlayerWeapons driven through real action events: hold Tab, point, let go.

const PlayerBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")

var w: WeaponWheel


func before_each() -> void:
	WorldState.reset()
	w = WeaponWheel.new(["pistol_blaster", "rifle_blaster", "energy_blade"])


func after_each() -> void:
	WorldState.reset()


func _open(wheel: WeaponWheel) -> void:
	wheel.press()
	assert_true(wheel.tick(0.25), "held past the threshold, it opens")


# ---- the pure wheel ---------------------------------------------------------------

func test_eight_directions_pick_eight_slots_clockwise_from_the_top() -> void:
	var dirs := [Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
			Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1)]
	for i in 8:
		assert_eq(WeaponWheel.slot_at(dirs[i].normalized(), 0.3), i, "direction %d" % i)
		assert_eq(WeaponWheel.slot_at(WeaponWheel.slot_dir(i), 0.3), i)


func test_inside_the_dead_zone_is_the_middle() -> void:
	assert_eq(WeaponWheel.slot_at(Vector2(0.1, -0.1), 0.3), -1)
	assert_eq(WeaponWheel.slot_at(Vector2.ZERO, 0.3), -1)


func test_slots_pad_to_eight() -> void:
	assert_eq(w.slots.size(), 8)
	assert_eq(w.id_at(2), "energy_blade")
	assert_eq(w.id_at(3), "")


func test_a_tap_is_not_a_wheel() -> void:
	w.press()
	assert_false(w.tick(0.1))
	assert_false(w.is_open)
	assert_true(w.is_held(), "still down, so the release is a tap")
	assert_eq(w.release(), "")


func test_holding_opens_it_in_the_middle_with_nothing_picked() -> void:
	_open(w)
	assert_true(w.is_open)
	assert_eq(w.highlighted(), -1)
	assert_eq(w.release(), "", "letting go in the middle keeps what you have")
	assert_false(w.is_open)


func test_keys_pick_a_slot_and_letting_go_returns_it() -> void:
	_open(w)
	w.push_keys(Vector2(1, 0))
	assert_eq(w.highlighted(), 2)
	assert_eq(w.release(), "energy_blade")


func test_a_diagonal_key_pair_picks_the_corner() -> void:
	_open(w)
	w.push_keys(Vector2(1, -1))
	assert_eq(w.highlighted(), 1)
	assert_eq(w.choice(), "rifle_blaster")


func test_the_choice_stays_when_the_key_goes_up() -> void:
	_open(w)
	w.push_keys(Vector2(0, -1))
	w.push_keys(Vector2.ZERO)
	assert_eq(w.choice(), "pistol_blaster")


func test_mouse_moves_the_pointer_and_back_to_the_middle_clears_it() -> void:
	_open(w)
	w.move_mouse(Vector2(0, -120))
	assert_eq(w.choice(), "pistol_blaster")
	w.move_mouse(Vector2(0, 120))
	assert_eq(w.highlighted(), -1)
	assert_eq(w.choice(), "")


func test_the_pointer_stops_at_the_rim() -> void:
	_open(w)
	w.move_mouse(Vector2(5000, 0))
	assert_almost_eq(w.pointer.length(), 1.0, 0.001)
	assert_eq(w.choice(), "energy_blade")


func test_mouse_does_nothing_while_closed() -> void:
	w.move_mouse(Vector2(100, 0))
	assert_eq(w.pointer, Vector2.ZERO)


func test_an_empty_slot_can_not_be_picked_with_the_mouse() -> void:
	_open(w)
	w.move_mouse(Vector2(0, 140))
	assert_eq(w.highlighted(), 4)
	assert_false(w.selectable(4))
	assert_eq(w.release(), "", "the mouse may rest on a dimmed slot; letting go there does nothing")


func test_a_key_at_an_empty_slot_jumps_to_the_nearest_weapon() -> void:
	_open(w)
	w.push_keys(Vector2(0, 1))
	assert_eq(w.highlighted(), 2, "down is empty: the sword is two steps away, the pistol four")
	assert_eq(w.choice(), "energy_blade")
	w.push_keys(Vector2(-1, 0))
	assert_eq(w.highlighted(), 0, "left is empty: the pistol is two steps away, the sword four")
	assert_eq(w.release(), "pistol_blaster")


func test_a_key_tie_goes_to_the_lower_slot() -> void:
	assert_eq(w.nearest_selectable(5), 0, "slot 6 is three steps from the sword and three from the pistol")


func test_a_weapon_the_player_may_not_draw_is_skipped_by_the_keys() -> void:
	w.can_draw = func(id): return id == "pistol_blaster"
	_open(w)
	w.push_keys(Vector2(1, 0))
	assert_eq(w.choice(), "pistol_blaster", "the sword is dimmed, so right lands on the pistol")
	w.push_keys(Vector2(0, 1))
	assert_eq(w.choice(), "pistol_blaster")


func test_keys_with_no_weapon_to_land_on_pick_nothing() -> void:
	w.can_draw = func(_id): return false
	_open(w)
	w.push_keys(Vector2(1, 0))
	assert_eq(w.choice(), "")


func test_cancel_closes_without_a_pick() -> void:
	_open(w)
	w.push_keys(Vector2(1, 0))
	w.cancel()
	assert_false(w.is_open)
	assert_false(w.is_held())
	assert_eq(w.release(), "")


# ---- PlayerWeapons ----------------------------------------------------------------

func _kit() -> Array:
	var p := PlayerBody.new()
	add_child_autofree(p)
	var bolts := Node3D.new()
	add_child_autofree(bolts)
	var rig := CameraRigNode.new()
	add_child_autofree(rig)
	var kit := PlayerKit.attach(p, rig, bolts, LookMaterials.new())
	return [kit.weapons, p, rig]


func _tab(pw: PlayerWeapons, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = "weapon_cycle"
	ev.pressed = down
	pw._unhandled_input(ev)


func _frames(pw: PlayerWeapons, secs: float) -> void:
	var t := 0.0
	while t < secs:
		pw._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0


func _point(pw: PlayerWeapons, dir: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.relative = dir * pw.wheel.mouse_pixels
	pw._unhandled_input(mm)


func test_the_wheel_slots_are_the_number_keys() -> void:
	var pw: PlayerWeapons = _kit()[0]
	assert_eq(pw.wheel.id_at(0), "pistol_blaster")
	assert_eq(pw.wheel.id_at(1), "rifle_blaster")
	assert_eq(pw.wheel.id_at(2), "sniper_rifle")
	for i in [3, 4, 5, 6]:
		assert_eq(pw.wheel.id_at(i), "", "4 to 7 are free for guns to come")
	assert_eq(pw.wheel.id_at(7), "energy_blade", "the sword is key 8, the last slot")
	assert_almost_eq(pw.wheel.hold_time, 0.2, 0.0001, "read from hand_weapons.json")


func test_hold_tab_point_up_left_let_go_draws_the_sword() -> void:
	var pw: PlayerWeapons = _kit()[0]
	_tab(pw, true)
	_frames(pw, 0.3)
	assert_true(pw.wheel.is_open)
	_point(pw, Vector2(-1, -1).normalized())
	_tab(pw, false)
	_frames(pw, 0.6)
	assert_false(pw.wheel.is_open)
	assert_eq(pw.holder.current, "energy_blade")
	assert_true(pw.holder.is_ready())


func test_a_tap_still_cycles_to_the_next_weapon() -> void:
	var pw: PlayerWeapons = _kit()[0]
	_tab(pw, true)
	_frames(pw, 0.05)
	_tab(pw, false)
	_frames(pw, 0.4)
	assert_false(pw.wheel.is_open)
	assert_eq(pw.holder.current, "pistol_blaster")


func test_letting_go_on_the_weapon_in_hand_keeps_it_out() -> void:
	var pw: PlayerWeapons = _kit()[0]
	pw.holder.request("pistol_blaster")
	_frames(pw, 0.5)
	_tab(pw, true)
	_frames(pw, 0.3)
	_point(pw, Vector2(0, -1))
	_tab(pw, false)
	_frames(pw, 0.5)
	assert_eq(pw.holder.current, "pistol_blaster", "the number key would holster; the wheel does not")


func test_letting_go_in_the_middle_changes_nothing() -> void:
	var pw: PlayerWeapons = _kit()[0]
	pw.holder.request("rifle_blaster")
	_frames(pw, 0.5)
	_tab(pw, true)
	_frames(pw, 0.3)
	_tab(pw, false)
	_frames(pw, 0.5)
	assert_eq(pw.holder.current, "rifle_blaster")


func test_the_wheel_takes_walking_and_fire_and_gives_them_back() -> void:
	var kit := _kit()
	var pw: PlayerWeapons = kit[0]
	var p = kit[1]
	pw.holder.request("pistol_blaster")
	_frames(pw, 0.5)
	_tab(pw, true)
	_frames(pw, 0.3)
	assert_true(p.move_blocked, "WASD points at slots, nobody walks")
	assert_true(kit[2].look_blocked, "the mouse points at slots, the view holds still")
	var fire := InputEventAction.new()
	fire.action = "fire"
	fire.pressed = true
	pw._unhandled_input(fire)
	assert_false(pw._fire_held, "no firing while choosing")
	_tab(pw, false)
	assert_false(p.move_blocked)
	assert_false(kit[2].look_blocked)


func test_the_world_is_not_paused_while_it_is_open() -> void:
	var pw: PlayerWeapons = _kit()[0]
	_tab(pw, true)
	_frames(pw, 0.3)
	assert_true(pw.wheel.is_open)
	assert_false(get_tree().paused)
	pw.holder.request("rifle_blaster")
	_frames(pw, 0.5)
	assert_eq(pw.holder.current, "rifle_blaster", "the swap machine keeps running under the wheel")


func test_turning_weapons_off_closes_it_without_a_pick() -> void:
	var kit := _kit()
	var pw: PlayerWeapons = kit[0]
	var p = kit[1]
	_tab(pw, true)
	_frames(pw, 0.3)
	_point(pw, Vector2(1, 0))
	pw.set_enabled(false)
	assert_false(pw.wheel.is_open)
	assert_false(p.move_blocked)
	pw.set_enabled(true)
	_tab(pw, false)
	_frames(pw, 0.5)
	assert_eq(pw.holder.current, "", "no pick came out of it")


func test_going_down_closes_it() -> void:
	var kit := _kit()
	var pw: PlayerWeapons = kit[0]
	var p = kit[1]
	_tab(pw, true)
	_frames(pw, 0.3)
	p.is_downed = true
	_frames(pw, 0.1)
	assert_false(pw.wheel.is_open)
	assert_false(p.move_blocked)
