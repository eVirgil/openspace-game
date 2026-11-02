extends GutTest
## M9: the port town data and its validator. The positive tests prove the shipped
## town is valid; the negative tests prove each rule actually catches its break.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")
const StairTower := preload("res://src/systems/world/stair_tower.gd")
const CharacterController := preload("res://src/systems/player/character_controller.gd")


## Issue #237: the home port is round now; the tests written for the square port
## keep running against it, as the saved layout port_square.
func _town() -> TownLayout:
	var t := TownLayout.new()
	assert_true(t.load_town("port_town", "port_square"), "port_square loads from content/core")
	return t


func test_home_port_is_round() -> void:
	var t := TownLayout.new()
	assert_true(t.load_town("port_town"), "port_town loads from content/core")
	assert_eq(str(t.data.layout), "port_round", "the home planet builds the round port")
	assert_eq(t.validate(), [], "and it is valid")


## Issue #237: port_town is its planet's saved layout, and either layout loads.
func test_port_town_is_a_saved_layout() -> void:
	var t := TownLayout.new()
	assert_true(t.load_town("port_town"))
	assert_eq(str(t.data.id), "port_town")
	assert_ne(str(t.data.get("layout", "")), "", "built to a named layout")
	var sq := TownLayout.new()
	assert_true(sq.load_town("port_town", "port_square"), "port_square loads by name")
	assert_eq(int(sq.data.size), 50)
	assert_eq(sq.validate(), [], "port_square is valid")
	assert_false(TownLayout.new().load_town("port_town", "no_such_layout"), "an unknown layout is no town")


## Issue #237: the round port. Valid, about twice the floor space, round walled,
## and everything that points at the square port is there too.
func _round() -> TownLayout:
	var t := TownLayout.new()
	assert_true(t.load_town("port_town", "port_round"), "port_round loads by name")
	return t


func test_round_port_validates_clean() -> void:
	var t := _round()
	assert_eq(t.validate(), [], "port_round has no validation errors")
	assert_eq(int(t.data.size), 67)


func test_round_port_keeps_every_marker_and_route() -> void:
	var sq := TownLayout.new()
	sq.load_town("port_town", "port_square")
	var t := _round()
	for m in sq.markers():
		assert_false(t.get_marker(str(m.id)).is_empty(), "port_round has marker " + str(m.id))
	for r in sq.routes():
		assert_false(t.get_route(str(r.id)).is_empty(), "port_round has route " + str(r.id))
	for id in ["bar_counter", "cantina_roof", "cantina_stage", "stair_tower", "pit_bowl", "pit_floor", "gate_lintel", "watchtower", "spare_pad"]:
		assert_false(t.get_box(id).is_empty(), "port_round has box " + id)


## The club cantina (issue #261) moves whole: its band and patrons keep where
## they stand and what they look at, relative to the bar.
func test_round_port_carries_the_club_cantina() -> void:
	var sq := TownLayout.new()
	sq.load_town("port_town", "port_square")
	var t := _round()
	assert_eq(t.data.get("club", {}), sq.data.get("club", {}), "the same club")
	var shift := t.marker_pos("cantina_owner") - sq.marker_pos("cantina_owner")
	for m in sq.markers():
		if not (str(m.id).begins_with("band_") or str(m.id).begins_with("patron_")):
			continue
		# Issue #237 part 4: one the round wall now crowds is pulled in toward the middle.
		var want := sq.marker_pos(str(m.id)) + shift
		var got := t.marker_pos(str(m.id))
		var c: Vector3 = RingWall.info(t.get_box("cantina_body")).c if not t.get_box("cantina_body").is_empty() else got
		var pulled := got.distance_to(want) > 0.01 and Vector2(got.x - c.x, got.z - c.z).length() < Vector2(want.x - c.x, want.z - c.z).length() \
			and got.distance_to(want) < 2.5
		assert_true(got.distance_to(want) < 0.01 or pulled, str(m.id) + " moved with the cantina")
		if m.has("face"):
			var a := Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2])) + shift
			var f: Array = t.get_marker(str(m.id)).face
			assert_almost_eq(Vector3(float(f[0]), float(f[1]), float(f[2])).distance_to(a), 0.0, 0.01, str(m.id) + " looks at the same thing")


## Issue #237 part 4: the club in a round body of the same floor, everything in
## it still inside, the door on the square, the stair tower a turret outside.
func test_round_port_club_has_a_round_body() -> void:
	var sq := TownLayout.new()
	sq.load_town("port_town", "port_square")
	var t := _round()
	var body := t.get_box("cantina_body")
	assert_eq(str(body.get("kind", "")), "ring", "a round body")
	var info := RingWall.info(body)
	var w := sq.get_box("cantina_wall_w")
	var e := sq.get_box("cantina_wall_e_s")
	var n := sq.get_box("cantina_wall_n")
	var s_ := sq.get_box("cantina_wall_s")
	var square := (float(e.min[0]) - float(w.max[0])) * (float(n.min[2]) - float(s_.max[2]))
	assert_almost_eq(PI * float(info.ri) * float(info.ri), square, square * 0.05, "the same floor area")
	assert_eq(str(t.get_box("cantina_roof").get("shape", "")), "round", "a round roof")
	var c: Vector3 = info.c
	for id in ["bar_counter", "cantina_stage", "fixer_table", "cantina_table_1", "cantina_table_2", "cantina_table_3"]:
		var b := t.get_box(id)
		for x in [float(b.min[0]), float(b.max[0])]:
			for z in [float(b.min[2]), float(b.max[2])]:
				assert_lt(Vector2(x - c.x, z - c.z).length(), float(info.ri), id + " is inside the round wall")
	for id in ["bar_front", "cantina_owner", "fixer", "band_dj", "patron_1"]:
		var p := t.marker_pos(id)
		assert_lt(Vector2(p.x - c.x, p.z - c.z).length(), float(info.ri) - 0.6, id + " stands inside")
	# The door faces the square.
	var door_deg := 0.0
	for g in body.gaps:
		if str(g.id) == "door":
			door_deg = float(g.deg)
	var sqz: Dictionary = {}
	for z in t.zones():
		if str(z.id) == "cantina_square":
			sqz = z
	var to_sq := Vector2((float(sqz.min[0]) + float(sqz.max[0])) * 0.5 - c.x, (float(sqz.min[1]) + float(sqz.max[1])) * 0.5 - c.z)
	assert_lt(absf(wrapf(to_sq.angle() - deg_to_rad(door_deg), -PI, PI)), 0.5, "the door opens on the square")
	# The tower stands outside, its door facing the room, the lookout on it.
	var tower := t.get_box("stair_tower")
	var tc := Vector2((float(tower.min[0]) + float(tower.max[0])) * 0.5, (float(tower.min[2]) + float(tower.max[2])) * 0.5)
	var tr := (float(tower.max[0]) - float(tower.min[0])) * 0.5
	assert_gte(tc.distance_to(Vector2(c.x, c.z)) - tr, float(info.r), "the stair tower is outside the wall")
	var to_room := (Vector2(c.x, c.z) - tc).angle()
	assert_lt(absf(wrapf(deg_to_rad(float(tower.door_deg)) - to_room, -PI, PI)), 0.05, "its door faces the room")
	assert_eq(str(t.get_box("lookout").get("stair", "")), "stair_tower", "the lookout is on it")
	# The blade still lies on the lookout floor.
	var cc := CoreContent.new()
	cc.load_from()
	for pk in cc.get_pickups("port_town", "port_round"):
		if str(pk.id) == "tower_blade":
			var at := t.marker_pos(str(pk.marker)) + Vector3(float(pk.offset[0]), float(pk.offset[1]), float(pk.offset[2]))
			# Off the middle (the stairwell and its column), out on the floor.
			var off := Vector2(at.x, at.z).distance_to(tc)
			assert_gt(off, float(tower.core) + 0.5, "the blade is not in the tower's column")
			assert_lt(off, tr, "the blade is over the tower")
			assert_almost_eq(at.y, float(tower.max[1]), 0.05, "on the lookout floor")


## Issue #237: in both ports you can jump out of the lookout's windows: a jump
## clears the sill, the opening fits a standing body at the top of that jump,
## and the lookout box holds the taller room.
func test_lookout_windows_are_tall_enough_to_jump_out() -> void:
	var body := CharacterController.new()
	var peak := 0.6                      # character_controller.gd: velocity.y = sqrt(2 g 0.6)
	assert_lt(StairTower.PARAPET_H + 0.1, peak, "a jump clears the sill")
	assert_gt(StairTower.PARAPET_H, 0.2, "but you don't walk off it")
	assert_lt(peak + body.stand_height, StairTower.ROOM_H, "a body fits the opening at the top of the jump")
	for layout in ["port_square", "port_round"]:
		var t := TownLayout.new()
		t.load_town("port_town", layout)
		var lk := t.get_box("lookout")
		assert_gte(float(lk.max[1]) - float(lk.min[1]), StairTower.ROOM_H + 0.3, layout + ": the lookout box holds the room and its roof")


func test_round_port_is_round_and_twice_the_size() -> void:
	var t := _round()
	var wall := t.get_box("town_wall")
	assert_eq(str(wall.get("kind", "")), "ring", "a round town wall")
	var info := RingWall.info(wall)
	assert_almost_eq(float(info.t), 2.0, 0.01, "as thick as the square wall")
	assert_almost_eq(float(info.y1) - float(info.y0), 6.0, 0.01, "and as tall")
	var inside := PI * float(info.ri) * float(info.ri)
	assert_between(inside / (196.0 * 146.0), 1.9, 2.4, "about twice the square port's floor")
	var bowl := t.get_box("pit_bowl")
	assert_gt(float(bowl.max[0]) - float(bowl.min[0]), 56.0, "a wider bowl than the 56 m pit")
	assert_gte(t.boxes().filter(func(b): return str(b.id).begins_with("surface_pad_")).size(), 8, "pads round the bowl")
	# Two gate towers, each manned, either side of the gate.
	var gate := t.marker_pos("gate")
	for pair in [["watchtower", "trooper_tower"], ["watchtower_s", "trooper_tower_s"]]:
		var b := t.get_box(pair[0])
		assert_false(b.is_empty(), pair[0])
		assert_eq(str(t.get_marker(pair[1]).get("role", "")), "trooper_post", pair[1] + " mans it")
		assert_lt(Vector2(float(b.min[0]) - gate.x, (float(b.min[2]) + float(b.max[2])) * 0.5 - gate.z).length(), 30.0, pair[0] + " by the gate")
	assert_true(sign(float(t.get_box("watchtower").min[2])) != sign(float(t.get_box("watchtower_s").min[2])), "one each side")


## Issue #237 part 3: a market three times today's, with aisles and taller
## stalls and more people in it, and bigger barracks.
func test_round_port_market_is_three_times_and_taller() -> void:
	var sq := TownLayout.new()
	sq.load_town("port_town", "port_square")
	var t := _round()
	var stalls := func(town) -> Array: return town.boxes().filter(func(b): return str(b.get("look", "")) == "stall")
	var sq_stalls: Array = stalls.call(sq)
	var rd_stalls: Array = stalls.call(t)
	assert_gte(rd_stalls.size(), sq_stalls.size() * 3, "three times the stalls")
	var sq_back := float(sq.get_box(str(sq_stalls[0].id) + "_back").max[1])
	for b in rd_stalls:
		var back := t.get_box(str(b.id) + "_back")
		assert_false(back.is_empty(), str(b.id) + " has a back panel")
		assert_gt(float(back.max[1]), sq_back, str(b.id) + " is taller")
		assert_gt(float(b.get("canopy_lift", 0.0)), 0.0, str(b.id) + " has a raised canopy")
	var kit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/planets/town_kit.json"))
	var mk: Dictionary = kit.round.market
	assert_gte((mk.aisles as Array).size(), 3, "at least three aisles")
	assert_gte((mk.cross as Array).size(), 2, "and aisles across them")
	var count := func(town, prefix: String) -> int: return town.markers().filter(func(m): return str(m.id).begins_with(prefix)).size()
	assert_gt(count.call(t, "vendor_"), count.call(sq, "vendor_"), "more merchants")
	assert_gt(count.call(t, "shopper_"), count.call(sq, "shopper_"), "more shoppers")
	for id in ["vendor_1", "vendor_2", "vendor_3", "vendor_4"]:
		assert_eq(str(t.get_marker(id).get("soldier", "")), str(sq.get_marker(id).get("soldier", "")), id + " is the same trader")


func test_round_port_barracks_are_bigger() -> void:
	var sq := TownLayout.new()
	sq.load_town("port_town", "port_square")
	var t := _round()
	var area := func(b: Dictionary) -> float: return (float(b.max[0]) - float(b.min[0])) * (float(b.max[2]) - float(b.min[2]))
	assert_gt(area.call(t.get_box("barracks_hall")), area.call(sq.get_box("barracks_hall")), "a bigger hall")
	for id in ["barracks_block_2", "drill_yard", "barracks_pad", "barracks_bunk", "barracks_upper"]:
		assert_false(t.get_box(id).is_empty(), "the barracks have " + id)
	var zone := func(town) -> float:
		for z in town.zones():
			if str(z.id) == "barracks":
				return (float(z.max[0]) - float(z.min[0])) * (float(z.max[1]) - float(z.min[1]))
		return 0.0
	assert_gt(zone.call(t), zone.call(sq) * 1.8, "about twice the ground")
	var roof := float(t.get_box("barracks_hall").max[1])
	for id in ["trooper_roof_w", "trooper_roof_c", "trooper_roof_e"]:
		assert_almost_eq(t.marker_pos(id).y, roof, 0.01, id + " is on the hall roof")


func test_round_wall_is_open_only_at_its_gates() -> void:
	var t := _round()
	var wall := t.get_box("town_wall")
	var info := RingWall.info(wall)
	var ps := RingWall.pieces(wall)
	for g in wall.gaps:
		var a := deg_to_rad(float(g.deg))
		var p := Vector2(cos(a), sin(a)) * float(info.rm)
		assert_gt(RingWall.distance(wall, p.x, p.y, ps, info), 1.0, "the %s is open" % str(g.id))
	var shut := Vector2(cos(deg_to_rad(90.0)), sin(deg_to_rad(90.0))) * float(info.rm)
	assert_eq(RingWall.distance(wall, shut.x, shut.y, ps, info), 0.0, "the wall is shut between them")


func test_v9_catches_a_marker_in_the_round_wall() -> void:
	var t := _round()
	var copy: Dictionary = t.data.duplicate(true)
	for m in copy.markers:
		if m.id == "resident_e":
			m.pos = [0.0, 0.0, 141.0]
	var t2 := TownLayout.new()
	t2.load_from_dict(copy)
	assert_true(_has_rule(t2.validate(), "V9"), "a marker in the wall breaks V9")


func test_v9_catches_a_route_through_the_round_wall() -> void:
	var t := _round()
	var copy: Dictionary = t.data.duplicate(true)
	copy.routes.append({ "id": "through_wall", "points": [[0, 130], [0, 150]] })
	var t2 := TownLayout.new()
	t2.load_from_dict(copy)
	assert_true(_has_rule(t2.validate(), "V9"), "a route through the wall breaks V9")


## Deep-copy the real town, break one thing, return the validator errors.
func _bad(mutator: Callable) -> Array:
	var t := _town()
	var copy: Dictionary = t.data.duplicate(true)
	mutator.call(copy)
	var t2 := TownLayout.new()
	t2.load_from_dict(copy)
	return t2.validate()


func _has_rule(errs: Array, rule: String) -> bool:
	for e in errs:
		if String(e).begins_with(rule):
			return true
	return false


func idx_of(d: Dictionary, id: String, list: String = "boxes") -> int:
	var arr: Array = d[list]
	for i in arr.size():
		if str(arr[i].id) == id:
			return i
	return -1


func test_town_loads_with_expected_counts() -> void:
	var t := _town()
	assert_eq(t.boxes().size(), 182)   # issue #76: + the barracks landing pad
	assert_eq(t.markers().size(), 42)  # locals: five walkers and four stall keepers; art pass 2: + three patrons at the bar; issue #58: + T-89; + three roof riflemen; issue #261: + the band of three and eight club patrons
	assert_eq(t.routes().size(), 17)   # M15: + patrol loops; locals: + five walkers' loops; art pass 2: + the climb to the lookout; issue #261: + three club strolls
	assert_eq(t.zones().size(), 8)


func test_town_validates_clean() -> void:
	var errs := _town().validate()
	for e in errs:
		gut.p(str(e))
	assert_eq(errs, [], "port_town has no validation errors")


func test_required_markers_exist() -> void:
	var t := _town()
	for id in ["player_spawn", "gate", "back_gap", "cantina_door", "bar_front", "cantina_owner", "fixer"]:
		assert_false(t.get_marker(id).is_empty(), "marker %s exists" % id)


func test_no_gray_homes_on_the_desert_port() -> void:
	var homes: Array = _town().boxes().filter(func(b):
		return str(b.get("id", "")).begins_with("cantina_home_"))
	assert_eq(homes, [], "the gray homes are the station's (#114), not the port's")


func test_npc_markers_match_data_layer() -> void:
	var t := _town()
	var cc := CoreContent.new()
	cc.load_from()
	for m in t.markers_with_role("npc"):
		assert_false(cc.get_npc(str(m.npc)).is_empty(), "npc %s is in the data layer" % m.npc)


func test_spawn_is_on_pit_floor() -> void:
	assert_eq(_town().spawn_pos().y, -6.0)


func test_eight_trooper_posts() -> void:
	assert_eq(_town().markers_with_role("trooper_post").size(), 8)


func test_three_riflemen_on_the_barracks_roof() -> void:
	var t := _town()
	var hall: Dictionary = t.get_box("barracks_hall")
	var on_roof := t.markers_with_role("trooper_post").filter(func(m): return str(m.soldier) == "roof_rifleman")
	assert_eq(on_roof.size(), 3)
	for m in on_roof:
		var p: Vector3 = t.marker_pos(str(m.id))
		assert_almost_eq(p.y, float(hall.max[1]), 0.01, "%s stands on the hall roof" % m.id)
		assert_true(p.x > float(hall.min[0]) and p.x < float(hall.max[0]) and p.z > float(hall.min[2]) and p.z < float(hall.max[2]),
			"%s is inside the roof's edge" % m.id)


func test_route_lengths_match_reference() -> void:
	var t := _town()
	# Art pass 2: round the cantina stage instead of across it, and round the bigger pit.
	assert_almost_eq(t.route_length("gate_to_cantina"), 255.2, 0.1)
	assert_almost_eq(t.route_length("spawn_to_cantina"), 218.2, 0.1)
	assert_almost_eq(t.route_length("backgap_to_cantina"), 150.7, 0.1)


func test_ramp_ne_top_edge_meets_ground() -> void:
	var rt := TownLayout.ramp_transform(_town().get_box("ramp_ne"))
	var b: Basis = rt.basis
	var top: Vector3 = rt.center + b.y * 0.2 + b.x * (rt.size.x / 2.0)
	assert_almost_eq(top.x, 28.0, 0.01)   # art pass 2: the round pit's east ramp
	assert_almost_eq(top.y, 0.0, 0.01)
	assert_almost_eq(top.z, 0.0, 0.01)


func test_ramp_sw_top_edge_meets_ground() -> void:
	var rt := TownLayout.ramp_transform(_town().get_box("ramp_sw"))
	var b: Basis = rt.basis
	var top: Vector3 = rt.center + b.y * 0.2 - b.x * (rt.size.x / 2.0)
	assert_almost_eq(top.x, -28.0, 0.01)   # and its west ramp
	assert_almost_eq(top.y, 0.0, 0.01)
	assert_almost_eq(top.z, 0.0, 0.01)


func test_ramp_angle_is_walkable() -> void:
	var t := _town()
	for id in ["ramp_ne", "ramp_sw"]:
		var rt := TownLayout.ramp_transform(t.get_box(id))
		assert_lt(rad_to_deg(float(rt.angle)), 45.0, "%s is walkable" % id)


func test_catches_overlap() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "shop_2")].min[0] = 45.0)
	assert_true(_has_rule(errs, "V5"), "V5 caught: %s" % str(errs))


func test_catches_outside_zone() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "stall_n1")].min[0] = 30.0)
	assert_true(_has_rule(errs, "V4"), "V4 caught: %s" % str(errs))


func test_catches_blocked_marker() -> void:
	var errs := _bad(func(d): d.markers[idx_of(d, "fixer", "markers")].pos = [-65.0, 0.0, 10.0])
	assert_true(_has_rule(errs, "V6"), "V6 caught: %s" % str(errs))


func test_catches_unsupported_marker() -> void:
	var errs := _bad(func(d): d.markers[idx_of(d, "vendor_1", "markers")].pos[1] = 3.0)
	assert_true(_has_rule(errs, "V7"), "V7 caught: %s" % str(errs))


func test_catches_blocked_route() -> void:
	var errs := _bad(func(d): d.boxes.append({ "id": "junk", "zone": "main_street", "kind": "solid",
		"min": [60.0, 0.0, -2.0], "max": [62.0, 2.0, 2.0] }))
	assert_true(_has_rule(errs, "V8"), "V8 caught: %s" % str(errs))


func test_catches_low_overhead() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "gate_lintel")].min[1] = 1.5)
	assert_true(_has_rule(errs, "V3"), "V3 caught: %s" % str(errs))


func test_catches_duplicate_id() -> void:
	var errs := _bad(func(d): d.markers[idx_of(d, "vendor_2", "markers")].id = "vendor_1")
	assert_true(_has_rule(errs, "V1"), "V1 caught: %s" % str(errs))


func test_chunks_are_port_kind() -> void:
	var chunks: Array = _town().data.chunks
	assert_eq(chunks.size(), 2)
	var centers: Array = []
	for c in chunks:
		assert_eq(str(c.kind), "port")
		centers.append(float(c.center))
	centers.sort()
	assert_eq(centers, [-50.0, 50.0])


## Art pass 2: the residential districts are not a grid any more. Huts on the
## market side, towers (with rooftop bridges) on the barracks side.
func test_neighbourhoods_are_not_a_grid() -> void:
	var t := _town()
	var huts: Array = []
	var towers: Array = []
	var bridges := 0
	for b in t.boxes():
		var look := str(b.get("look", ""))
		if str(b.zone) == "residential_w" and look.begins_with("hut_"):
			huts.append(b)
		elif str(b.zone) == "residential_e" and look.begins_with("tower_"):
			towers.append(b)
		elif str(b.zone) == "residential_e" and look == "bridge":
			bridges += 1
			assert_eq(str(b.kind), "overhead", "%s is walked over, not into" % b.id)
	assert_gt(huts.size(), 30, "plenty of huts by the market")
	assert_gt(towers.size(), 12, "a tower block by the barracks")
	assert_gt(bridges, 4, "with bridges between the roofs")
	# Off-grid: many different row and column starts.
	var xs := {}
	var zs := {}
	for b in huts:
		xs[float(b.min[0])] = true
		zs[float(b.min[2])] = true
	assert_gt(xs.size(), 20, "hut columns do not line up")
	assert_gt(zs.size(), 8, "hut rows do not line up")
	var hut_h := 0.0
	var tower_h := 0.0
	for b in huts:
		hut_h = maxf(hut_h, float(b.max[1]))
	for b in towers:
		tower_h += float(b.max[1]) / towers.size()
	assert_lte(hut_h, 5.0, "huts stay low")
	assert_gt(tower_h, 11.0, "towers stand tall")


func test_every_building_has_a_door_side() -> void:
	for b in _town().boxes():
		if str(b.get("look", "")) in ["", "bridge", "cistern", "stage", "stair_tower", "lookout", "crates", "stall_back"]:
			continue
		assert_true(str(b.get("face", "")) in ["+x", "-x", "+z", "-z"], "%s has a door side" % b.id)
		if str(b.get("shape", "")) == "round":
			assert_almost_eq(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]), 0.01, "%s: round on a square footprint" % b.id)


## Art pass 2: the cantina has a stage in the middle that the walk routes go
## round, and patrons on the bar stools facing the cantina owner.
func test_cantina_stage_and_patrons() -> void:
	var t := _town()
	var stage := t.get_box("cantina_stage")
	assert_false(stage.is_empty(), "the stage exists")
	assert_eq(str(stage.kind), "cover", "you cannot walk through it")
	var roof := t.get_box("cantina_roof")
	assert_gte(float(roof.min[1]), 8.0, "a tall hall")
	# The bar stools (patron_1, _2, ...) face the cantina owner; issue #261's club
	# patrons stand at tables and booths or stroll, facing their own way.
	var patrons := 0
	for m in t.markers():
		var id := str(m.id)
		if id.begins_with("patron_") and id.trim_prefix("patron_").is_valid_int():
			patrons += 1
			var f := Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))
			assert_almost_eq(f.distance_to(t.marker_pos("cantina_owner")), 0.0, 0.5, "%s faces the cantina owner" % m.id)
		elif id.begins_with("patron_"):
			assert_true(m.has("face") or m.has("patrol"), "%s faces somewhere or strolls" % id)
	assert_gte(patrons, 3, "locals at the bar")


## Art pass 2: a round pit with four bays. The player's ship is on the launch
## pad and the spawn is beside it. Issue #58: two bays hold other flyable ships
## (the round freighter among them) and the fourth is an empty pad.
func test_round_pit_with_three_ships_and_an_empty_pad() -> void:
	var t := _town()
	var bowl := t.get_box("pit_bowl")
	assert_eq(str(bowl.kind), "bowl")
	assert_true(bool(bowl.get("hollow", false)), "other boxes sit inside it")
	var ships: Array = []
	for b in t.boxes():
		if str(b.kind) == "ship":
			ships.append(b)
	assert_eq(ships.size(), 3, "three ships in the pit")
	var kinds := {}
	for b in ships:
		if b.has("ship"):
			kinds[str(b.ship)] = true
	assert_eq(kinds.keys().size(), 2, "two other flyable ships, all different (issue #43)")
	assert_true(kinds.has("freighter"), "the round one stays")
	var pad := t.get_box("spare_pad")
	assert_eq(str(pad.get("kind", "")), "pad", "the fourth bay is an empty pad")
	assert_false(pad.has("ship"), "nothing parked on it until you buy a ship")
	ships.append(pad)
	var own := t.get_box("ship")
	var c := Vector3((float(own.min[0]) + float(own.max[0])) * 0.5, -6.0, (float(own.min[2]) + float(own.max[2])) * 0.5)
	assert_lt(t.spawn_pos().distance_to(c), 10.0, "the player spawns by their own ship")
	var r := (float(bowl.max[0]) - float(bowl.min[0])) * 0.5
	for b in ships:
		for x in [float(b.min[0]), float(b.max[0])]:
			for z in [float(b.min[2]), float(b.max[2])]:
				assert_lt(Vector2(x, z).length(), r, "%s fits inside the round wall" % b.id)

