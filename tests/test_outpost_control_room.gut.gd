extends GutTest
## Issue #309: every Remnant outpost is a control room you can walk into (walls, a
## roof and a doorway on the old footprint), and its console, held for 5 seconds
## during a heist, drops a stash of 15 flasks of refined quantonium.

const CONTENT := preload("res://src/systems/dataload/core_content.gd")


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func _in_any(pieces: Array, p: Vector3) -> bool:
	for b in pieces:
		var s := WorldGround._v3(b.size)
		var c := WorldGround._v3(b.position) + Vector3(0, s.y * 0.5, 0)
		if AABB(c - s * 0.5, s).has_point(p):
			return true
	return false


func test_every_outpost_is_a_walk_in_room_on_the_same_footprint() -> void:
	var cc = CONTENT.new()
	cc.load_from()
	for id in Story.OUTPOSTS:
		var loc: Dictionary = cc.get_location(str(id))
		var b: Dictionary = loc.buildings[0]
		var s := WorldGround._v3(b.size)
		assert_true(OutpostRoom.is_room(b), "%s is a control room" % id)
		var pieces := WorldGround.pieces(loc)
		var box := AABB()
		for k in pieces.size():
			var ps := WorldGround._v3(pieces[k].size)
			var pb := AABB(WorldGround._v3(pieces[k].position) - Vector3(ps.x, 0, ps.z) * 0.5, ps)
			box = pb if k == 0 else box.merge(pb)
		assert_almost_eq(box.size, s, Vector3.ONE * 0.01, "%s keeps its footprint (ships still hit it)" % id)
		assert_false(_in_any(pieces, Vector3(s.x * 0.5 - 0.15, 1.2, 0)), "%s: the doorway is open" % id)
		assert_false(_in_any(pieces, Vector3(0, 1.2, 0)), "%s: the room is hollow" % id)
		assert_true(_in_any(pieces, Vector3(-s.x * 0.5 + 0.1, 1.2, 0)), "%s: the back wall is solid" % id)
		assert_true(_in_any(pieces, Vector3(0, s.y - 0.1, 0)), "%s has a roof" % id)
		assert_true(OutpostRoom.contains(b, WorldGround._v3(loc.points.guard_c)), "%s: guard_c stands inside" % id)
		var stand := OutpostRoom.stand(b)
		assert_true(OutpostRoom.contains(b, stand), "%s: the hack spot is inside" % id)
		for part in OutpostRoom.inside(b):
			if bool(part.solid):
				var ps: Vector3 = part.size
				assert_false(AABB((part.center as Vector3) - ps * 0.5, ps).has_point(stand + Vector3(0, 0.5, 0)),
					"%s: nothing solid stands on the hack spot (%s)" % [id, part.id])


func _room() -> RemnantOutposts:
	var ro := RemnantOutposts.new()
	autofree(ro)
	var b := { "id": "block", "size": [10, 5.5, 7], "position": [0, 0, 0], "room": {} }
	ro.outposts = [{ "id": "remnant_outpost_mid", "label": "the broken ridge outpost", "xf": Transform3D.IDENTITY,
		"room": { "b": b, "lift": 0.0, "stand": OutpostRoom.stand(b) } }]
	return ro


func test_hold_five_seconds_drops_fifteen_flasks() -> void:
	var ro := _room()
	var at := ro.console_point(ro.outposts[0])
	assert_eq(ro.hack_step(0.1, true, at), "locked", "no heist on: the console is locked")
	WorldState.heist = { "run": 1, "outpost": "remnant_outpost_mid" }
	assert_eq(ro.hack_step(0.1, false, at), "ready")
	var state := ""
	for i in 49:
		state = ro.hack_step(0.1, true, at)
	assert_eq(state, "hacking", "4.9 s in: still hacking")
	assert_true(Heist.stash_entry().is_empty(), "nothing yet")
	assert_eq(ro.hack_step(0.11, true, at), "done", "5 s: done")
	var e := Heist.stash_entry()
	assert_eq(int(e.get("count", 0)), 15, "15 flasks")
	assert_eq(str(e.get("item", "")), "refined_quantonium")
	assert_eq(ro.hack_step(0.1, true, at), "wiped", "nothing left on it")
	WorldState.inventory.pick_up(e)
	assert_eq(WorldState.inventory.count("refined_quantonium"), 15, "picked up like a drop")
	assert_true(WorldState.carrying_contraband(), "contraband: the gate's search finds it")
	assert_true(Heist.stash_entry().is_empty(), "taken")


func test_letting_go_or_stepping_away_resets() -> void:
	var ro := _room()
	var at := ro.console_point(ro.outposts[0])
	WorldState.heist = { "run": 1, "outpost": "remnant_outpost_mid" }
	for i in 30:
		ro.hack_step(0.1, true, at)
	assert_almost_eq(ro.hacking, 3.0, 0.01)
	assert_eq(ro.hack_step(0.1, false, at), "ready", "let go at 3 s")
	assert_eq(ro.hacking, 0.0, "the bar resets")
	assert_true(Heist.stash_entry().is_empty(), "nothing drops")
	for i in 30:
		ro.hack_step(0.1, true, at)
	assert_eq(ro.hack_step(0.1, true, at + Vector3(4, 0, 0)), "", "stepped away")
	assert_eq(ro.hacking, 0.0)
	assert_false(Heist.hacked())
