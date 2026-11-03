extends GutTest
## Issue #295: Skrugs's yard behind the cantina (round port) and his post outside
## the square port's back gate, the back gate a speeder fits through, garages you
## can drive into (his and Dorrin's), his bench in free roam, and him buying ships.

const TownDemo := preload("res://scenes/town_demo.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")
const DT := 1.0 / 60.0

var content
var speeder: Dictionary


func before_each() -> void:
	WorldState.reset()
	content = CoreScript.new()
	content.load_from()
	speeder = HoverModel.load_config("speeder")


func after_each() -> void:
	WorldState.reset()


func _landmark(world: Dictionary, id: String) -> Dictionary:
	for lm in world.get("landmarks", []):
		if str(lm.get("id", "")) == id:
			return lm
	return {}


func _ground(layout: String) -> WorldGround:
	var town = TownLayout.new()
	town.load_town("port_town", layout)
	var g := WorldGround.new()
	g.setup(content.world_for_town("port_town", layout), town, content)
	return g


## A landmark's frame on the ground, as WorldGround and MechanicYard place it.
func _site(g: WorldGround, lm: Dictionary) -> Transform3D:
	var at := WorldGround._v3(lm.at)
	var sp := g.sphere()
	var base := sp.surface_at(at.x, at.z) if sp != null else Vector3(at.x, g.terrain.height_at(at.x, at.z), at.z)
	var up := g.up_at(base)
	return Transform3D(PlanetSphere.tilt_to(up) * Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0)))), base)


func _on_ground(g: WorldGround, p: Vector3) -> Vector3:
	var sp := g.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	return Vector3(p.x, g.terrain.height_at(p.x, p.z), p.z)


## The world footprint [min, max] (x, z) of every box of a landmark.
func _footprints(g: WorldGround, id: String) -> Array:
	var out: Array = []
	for b in g.boxes:
		if not str(b.id).begins_with(id + "/"):
			continue
		var xf := WorldGround.box_xf(b)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in 8:
			var c := Vector3(b.max.x if i & 1 else b.min.x, b.max.y if i & 2 else b.min.y, b.max.z if i & 4 else b.min.z)
			var w: Vector3 = xf * c
			lo = lo.min(w)
			hi = hi.max(w)
		out.append({ "id": str(b.id), "min": lo, "max": hi })
	return out


## A speeder on `g` at `at`, nose toward `dir` (flat, world).
func _speeder(g: WorldGround, at: Vector3, dir: Vector3) -> HoverModel:
	var m := HoverModel.new(speeder, g)
	m.place(at, 0.0)
	var l: Vector3 = PlanetSphere.tilt_to(g.up_at(at)).inverse() * dir
	m.place(at, atan2(-l.x, -l.z))
	return m


## Drive through `points` in turn (steering at each), at `throttle`. Returns the
## events and stops at the last point.
func _drive(m: HoverModel, points: Array, throttle: float, max_s: float) -> Array:
	var ev: Array = []
	var k := 0
	for i in int(max_s * 60.0):
		if k >= points.size():
			break
		var to: Vector3 = points[k]
		var want := to - m.position
		want -= m.up() * want.dot(m.up())
		if want.length() < 3.0:
			k += 1
			continue
		var cross := m.forward().cross(want.normalized()).dot(m.up())
		m.set_command(throttle, clampf(-cross * 3.0, -1.0, 1.0))
		ev.append_array(m.step(DT))
	return ev


## Steer onto the line out from the town's middle along `dir` (aiming `ahead` metres
## further along it, as a driver lines up on a gate) until `to_r` from the middle.
func _follow_line(m: HoverModel, dir: Vector3, to_r: float, throttle: float, max_s: float, ahead: float = 7.0) -> Array:
	var ev: Array = []
	for i in int(max_s * 60.0):
		var along := Vector3(m.position.x, 0, m.position.z).dot(dir)
		if along >= to_r:
			break
		var want := dir * (along + ahead) - Vector3(m.position.x, 0, m.position.z)
		var cross := m.forward().cross(want.normalized()).dot(m.up())
		m.set_command(throttle, clampf(-cross * 3.0, -1.0, 1.0))
		ev.append_array(m.step(DT))
	return ev


func _bumps(ev: Array) -> Array:
	return ev.filter(func(e): return str(e.type) == "bump").map(func(e): return str(e.what))


# ---- where he is, per layout ---------------------------------------------------------------

func test_his_post_moves_with_the_town_layout() -> void:
	var round := _landmark(content.world_for_town("port_town", "port_round"), "skrugs_post")
	var square := _landmark(content.world_for_town("port_town", "port_square"), "skrugs_post")
	assert_eq(str(round.location), "skrugs_post_round")
	assert_eq(str(square.location), "skrugs_post")
	assert_eq(Array(square.at).map(func(v): return int(v)), [-135, 0, -60], "the square port's spot before #237")
	assert_false(round.has("layouts"), "resolved: one landmark, one place")
	var home := _landmark(content.world_for_town("port_town"), "skrugs_post")
	assert_eq(str(home.location), "skrugs_post_round", "the home planet is built to the round port")
	var gen: Dictionary = PlanetGen.make(content.planets["port_desert"], content)
	assert_eq(str(_landmark(gen.world, "skrugs_post").location), "skrugs_post_round", "PlanetGen resolves it too")


func test_the_round_yard_is_inside_the_wall_behind_the_cantina_and_clear_of_the_town() -> void:
	var g := _ground("port_round")
	var town = TownLayout.new()
	town.load_town("port_town", "port_round")
	var cantina: Dictionary = town.get_box("cantina_body")
	var cc := (WorldGround._v3(cantina.min) + WorldGround._v3(cantina.max)) * 0.5
	var cr := (float(cantina.max[0]) - float(cantina.min[0])) * 0.5
	var mine := _footprints(g, "skrugs_post")
	assert_eq(mine.size(), 8, "house, stall, pad, four garage pieces, bench")
	for f in mine:
		for c in [Vector2(f.min.x, f.min.z), Vector2(f.max.x, f.min.z), Vector2(f.min.x, f.max.z), Vector2(f.max.x, f.max.z)]:
			assert_lt(c.length(), 139.5, "%s inside the wall" % f.id)
			assert_gt(c.distance_to(Vector2(cc.x, cc.z)), cr, "%s clear of the cantina" % f.id)
			assert_lt(c.x, cc.x - cr + 1.0, "%s behind the cantina" % f.id)
	for b in town.boxes():
		if str(b.kind) in ["floor", "ring", "pad"]:
			continue
		for f in mine:
			var hit: bool = float(b.min[0]) < f.max.x and f.min.x < float(b.max[0]) and float(b.min[2]) < f.max.z \
				and f.min.z < float(b.max[2]) and float(b.min[1]) < f.max.y and f.min.y < float(b.max[1])
			assert_false(hit, "%s overlaps the town's %s" % [f.id, b.id])


func test_the_square_post_is_outside_its_back_gate() -> void:
	var town = TownLayout.new()
	town.load_town("port_town", "port_square")
	var gap: Vector3 = town.marker_pos("back_gap")
	for f in _footprints(_ground("port_square"), "skrugs_post"):
		assert_lt(f.max.x, gap.x - 1.0, "%s outside the wall" % f.id)


func test_the_ramp_is_its_own_landmark_out_past_the_gate() -> void:
	var g := _ground("port_round")
	var ramp := g.boxes.filter(func(b): return str(b.id) == "skrugs_ramp/ramp")
	assert_eq(ramp.size(), 1)
	assert_eq(str(ramp[0].rise), "-z")
	var c: Vector3 = WorldGround.box_xf(ramp[0]) * ((ramp[0].min + ramp[0].max) * 0.5)
	assert_gt(Vector2(c.x, c.z).length(), 160.0, "out in the sand")
	assert_true(g.boxes.filter(func(b): return str(b.id).begins_with("skrugs_post/") and str(b.get("rise", "")) != "").is_empty(),
		"no ramp in the yard")


# ---- the back gate -------------------------------------------------------------------------

## 2D distance between two wall pieces' footprints (corner to edge, both ways).
func _piece_gap(a: Dictionary, b: Dictionary) -> float:
	var ca := _corners(a)
	var cb := _corners(b)
	var best := INF
	for pair in [[ca, cb], [cb, ca]]:
		for p in pair[0]:
			for i in 4:
				best = minf(best, Geometry2D.get_closest_point_to_segment(p, pair[1][i], pair[1][(i + 1) % 4]).distance_to(p))
	return best


func _corners(p: Dictionary) -> Array:
	var bx: Basis = p.basis
	var h: Vector3 = p.size * 0.5
	var out: Array = []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var w: Vector3 = p.center + bx.x * h.x * s.x + bx.z * h.z * s.y
		out.append(Vector2(w.x, w.z))
	return out


func test_the_back_gate_fits_a_speeder_and_no_more() -> void:
	var town = TownLayout.new()
	town.load_town("port_town", "port_round")
	var wall: Dictionary = town.get_box("town_wall")
	var gate := deg_to_rad(-166.0)
	var pieces := RingWall.pieces(wall)
	pieces.sort_custom(func(a, b): return absf(wrapf(atan2(a.center.z, a.center.x) - gate, -PI, PI)) \
		< absf(wrapf(atan2(b.center.z, b.center.x) - gate, -PI, PI)))
	var gap := _piece_gap(pieces[0], pieces[1])
	var r := float(speeder.body_radius)
	assert_gt(gap, 2.0 * r + 0.6, "a speeder (%.1f m) fits with room to spare (%.2f m)" % [2.0 * r, gap])
	assert_lt(gap, 2.0 * r + 2.0, "just wide enough, nothing bigger (%.2f m)" % gap)
	var bg: Vector3 = town.marker_pos("back_gap")
	assert_almost_eq(rad_to_deg(atan2(bg.z, bg.x)), -166.0, 0.5, "the back_gap marker still in the gate")


func test_a_speeder_drives_out_of_the_back_gate() -> void:
	var g := _ground("port_round")
	var d := Vector3(cos(deg_to_rad(-166.0)), 0, sin(deg_to_rad(-166.0)))
	var m := _speeder(g, _on_ground(g, d * 120.0), d)
	var ev := _drive(m, [_on_ground(g, d * 175.0)], 0.8, 8.0)
	assert_eq(_bumps(ev), [], "nothing scraped")
	assert_gt(Vector2(m.position.x, m.position.z).length(), 165.0, "out past the wall")


func test_a_bought_speeder_drives_out_of_his_garage_and_through_the_gate() -> void:
	var g := _ground("port_round")
	var world: Dictionary = content.world_for_town("port_town", "port_round")
	var xf := _site(g, _landmark(world, "skrugs_post"))
	var loc: Dictionary = content.get_location("skrugs_post_round")
	var bay := _on_ground(g, xf * WorldGround._v3(loc.points.bay))
	var out_door := _on_ground(g, xf * (WorldGround._v3(loc.points.bay) + Vector3(8, 0, 0)))
	var d := Vector3(cos(deg_to_rad(-166.0)), 0, sin(deg_to_rad(-166.0)))
	var m := _speeder(g, bay, xf.basis.x)
	# A careful driver: out of the door, turn onto the lane's line and straight
	# through. The gate is only just wide enough, so not at full speed.
	var ev := _drive(m, [out_door], 0.3, 6.0)
	ev.append_array(_follow_line(m, d, 175.0, 0.3, 15.0, 6.0))
	assert_eq(_bumps(ev), [], "out of the garage, down the lane and through the gate without scraping")
	assert_gt(Vector2(m.position.x, m.position.z).length(), 165.0, "in the desert")


# ---- garages you can drive into ------------------------------------------------------------

func _garage_case(layout: String, landmark: String, loc_id: String) -> Dictionary:
	var g := _ground(layout)
	var world: Dictionary = content.world_for_town("port_town", layout)
	var lm := _landmark(world, landmark)
	if loc_id == "":
		loc_id = str(lm.location)
	return { "g": g, "xf": _site(g, lm), "loc": content.get_location(loc_id) }


func _drives_in(c: Dictionary, bay_local: Vector3) -> void:
	var g: WorldGround = c.g
	var xf: Transform3D = c.xf
	var start := _on_ground(g, xf * (bay_local + Vector3(18, 0, 0)))
	var bay := _on_ground(g, xf * bay_local)
	var m := _speeder(g, start, -xf.basis.x)
	var ev := _drive(m, [bay], 0.5, 6.0)
	assert_eq(_bumps(ev), [], "straight in through the open side")
	assert_lt(m.position.distance_to(bay), 3.5, "it ends up in the bay")
	# Into the back wall from inside: the walls still block.
	ev = _drive(m, [_on_ground(g, xf * (bay_local - Vector3(14, 0, 0)))], 0.6, 3.0)
	assert_false(_bumps(ev).is_empty(), "the back wall blocks from inside")
	# A side wall from outside: no way in.
	var side := _on_ground(g, xf * (bay_local + Vector3(0, 0, 16)))
	var m2 := _speeder(g, side, -xf.basis.z)
	ev = _drive(m2, [bay], 0.6, 4.0)
	assert_false(_bumps(ev).is_empty(), "a side wall blocks from outside")
	assert_gt(m2.position.distance_to(bay), 3.0, "and it stays out")


func test_dorrins_garage_can_be_driven_into() -> void:
	var c := _garage_case("port_round", "mechanic_yard", "mechanic_yard")
	_drives_in(c, WorldGround._v3(c.loc.points.bay))


func test_skrugs_garages_can_be_driven_into() -> void:
	for layout in ["port_round", "port_square"]:
		var c := _garage_case(layout, "skrugs_post", "")
		_drives_in(c, WorldGround._v3(c.loc.points.bay))


func test_garage_roofs_stand_on_their_walls() -> void:
	var g := _ground("port_round")
	var roofs := g.boxes.filter(func(b): return str(b.id).ends_with("/garage_roof"))
	assert_eq(roofs.size(), 2, "Skrugs's and Dorrin's")
	for b in roofs:
		assert_gte(float(b.min.y), 3.5, "%s: clear height inside" % b.id)


# ---- the town: bench, shop, ships ----------------------------------------------------------

func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func test_free_roam_bench_is_dorrins_menu_on_the_speeder_in_his_garage() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var t = _town()
	var post: SpeederPost = t.speeder_post
	assert_not_null(post.shop, "free roam: his bench works")
	WorldState.credits = 1000
	post.buy()
	assert_not_null(post.shop.speeder_in_bay(), "a bought speeder waits in his bay")
	post.shop.talk()
	var ids: Array = post.shop.menu.options.map(func(o): return str(o.id))
	for want in ["group:paint", "group:looks", "group:performance", "buy:grav_lifter", "scrap"]:
		assert_has(ids, want)
	assert_eq(post.shop.buy("engine_1"), "bought")
	assert_eq(WorldState.speeder_fits[0].parts, ["engine_1"], "fitted and saved")
	assert_almost_eq(float(post.shop.speeder_in_bay().cfg.max_speed), float(speeder.max_speed) * 1.12, 0.01)
	assert_eq(WorldState.credits, 750, "Dorrin's prices")


func test_story_has_no_bench_menu_and_dorrin_still_works() -> void:
	WorldState.new_game(WorldState.STORY)
	var t = _town()
	assert_null(t.speeder_post.shop, "story: Dorrin is the only mechanic")
	var y: MechanicYard = t.mechanic
	WorldState.credits = 1000
	t.speeder_post.buy()
	var s: SpeederNode = t.speeder_post.speeders[-1]
	s.place(y.world_point("bay"), 0.0)
	assert_eq(y.buy("thrusters_1"), "bought")


func test_the_brief_says_where_he_is_and_what_his_garage_does() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var t = _town()
	var lines := "\n".join(PackedStringArray(t.speeder_post.brief()))
	assert_string_contains(lines, "behind the cantina")
	assert_string_contains(lines, "garage bench")


## A ship parked by his post: a stand-in model on a new berth.
func _berth_at(t, at: Vector3, id: String, outpost: String = "") -> int:
	var v := Node3D.new()
	t.add_child(v)
	v.global_position = at
	if outpost != "":
		return t.pilot.add_outpost_berth(v, id, outpost)
	return t.pilot.add_berth(v, id, "test_box_" + id)


func test_he_buys_a_stolen_outpost_ship_for_more_than_list() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	var i := _berth_at(t, post.world_point("ship_sell"), "remnant_fighter", "test_outpost")
	assert_true(post.ship_offer().is_empty(), "not stolen yet: not his to buy")
	t.pilot.berths[i].stolen = true
	var o := post.ship_offer()
	assert_eq(int(o.berth), i)
	var want := int(round(ShipSalesman.list_price("remnant_fighter") * 1.25))
	assert_eq(int(o.price), want, "stolen_rate times the list price")
	assert_gt(int(o.price), ShipSalesman.resale_price("remnant_fighter"), "more than any honest sale")
	WorldState.credits = 10
	assert_eq(post.buy_ship(), want)
	assert_eq(WorldState.credits, 10 + want)
	assert_true(bool(t.pilot.berths[i].destroyed), "gone for good")
	assert_false(bool(t.pilot.berths[i].stolen), "the chase ends with it")
	assert_false(t.pilot.flying_stolen())
	assert_true(WorldState.events.any(func(e): return str(e).contains("sold a Remnant ship to Skrugs") \
		or (e is Dictionary and str(e.get("text", "")).contains("sold a Remnant ship to Skrugs"))), "logged")
	assert_true(post.ship_offer().is_empty(), "nothing left to buy")


func test_he_buys_your_bought_ship_at_resale() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.hangar = "courier"
	WorldState.ship_fits["courier"] = ["hull"]
	t.salesman.park_owned()
	assert_true(post.ship_offer().is_empty(), "on T-89's pad, far from Skrugs")
	t.salesman.bought_ship.global_position = post.world_point("ship_sell") + Vector3(4, 0, 0)
	var o := post.ship_offer()
	assert_eq(str(o.kind), "owned")
	assert_eq(int(o.price), t.salesman.resale("courier"), "T-89's buy-back price")
	WorldState.credits = 0
	post.buy_ship()
	assert_eq(WorldState.credits, t.salesman.resale("courier"))
	assert_eq(WorldState.hangar, "", "the pad is free")
	assert_false(WorldState.ship_fits.has("courier"), "its upgrades went with it")


func test_never_the_pit_ship_or_free_port_ships() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	var here := post.world_point("ship_sell")
	t.pilot.berths[0].visual.global_position = here
	_berth_at(t, here + Vector3(3, 0, 0), "courier")
	assert_true(post.ship_offer().is_empty(), "berth 0 and free keys are never his")


func test_nothing_sold_without_the_click() -> void:
	var t = _town()
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	var post: SpeederPost = t.speeder_post
	post.attach_host(t.bar)
	var i := _berth_at(t, post.world_point("ship_sell"), "remnant_fighter", "test_outpost")
	t.pilot.berths[i].stolen = true
	WorldState.credits = 0
	t.bar.start_talk(post.spot)
	var o := post.ship_offer()
	post.spot.brain.ship_buy_offered.emit({ "id": o.id, "name": o.name, "price": o.price })
	assert_true(t.bar.panel.job_open(), "the card is up")
	assert_eq(WorldState.credits, 0, "nothing yet")
	t.bar.panel.answer_card(false)
	assert_false(bool(t.pilot.berths[i].destroyed), "said no: still yours")
	post.spot.brain.ship_buy_offered.emit({ "id": o.id, "name": o.name, "price": o.price })
	t.bar.panel.answer_card(true)
	assert_eq(WorldState.credits, int(o.price), "the click sells")
	assert_true(bool(t.pilot.berths[i].destroyed))
	assert_eq(post.spot.brain.rel.mood, "warm")
	t.bar.end_talk()


func test_he_buys_a_stolen_ship_within_100_m_of_his_stall() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	var stall := post.world_point("merchant")
	var out := (post.world_point("ship_sell") - stall)
	out.y = 0.0
	out = out.normalized()
	var near := _berth_at(t, stall + out * 95.0, "remnant_fighter", "test_outpost")
	t.pilot.berths[near].stolen = true
	assert_eq(int(post.ship_offer().get("berth", -1)), near, "95 m from his stall: his to buy")
	t.pilot.berths[near].visual.global_position = stall + out * 105.0
	assert_true(post.ship_offer().is_empty(), "105 m: too far")


func test_he_offers_a_stolen_ship_the_moment_you_talk() -> void:
	var t = _town()
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	var post: SpeederPost = t.speeder_post
	post.attach_host(t.bar)
	var i := _berth_at(t, post.world_point("ship_sell"), "remnant_fighter", "test_outpost")
	t.pilot.berths[i].stolen = true
	WorldState.credits = 0
	t.bar.start_talk(post.spot)
	var o := post.ship_offer()
	assert_true(t.bar.panel.job_open(), "the card is up before a word is said")
	var said := str(JSON.parse_string(str(post.spot.brain.history[-1].content)).say)
	assert_string_contains(said, str(o.price), "he opens with his price")
	t.bar.panel.answer_card(true)
	assert_eq(WorldState.credits, int(o.price), "the click sells")
	assert_true(bool(t.pilot.berths[i].destroyed), "and the ship is gone")
	t.bar.end_talk()
	# Nothing stolen in reach: he greets as usual, no card.
	t.bar.start_talk(post.spot)
	assert_false(t.bar.panel.job_open(), "no ship, no card")
	t.bar.end_talk()


func test_his_stall_is_by_his_garage_and_the_back_gate() -> void:
	var g := _ground("port_round")
	var town = TownLayout.new()
	town.load_town("port_town", "port_round")
	var gate := Vector2.ZERO
	for m in town.markers():
		if str(m.id) == "back_gap":
			gate = Vector2(float(m.pos[0]), float(m.pos[2]))
	var at := {}
	for f in _footprints(g, "skrugs_post"):
		at[str(f.id).get_slice("/", 1)] = Vector2((f.min.x + f.max.x) * 0.5, (f.min.z + f.max.z) * 0.5)
	assert_lt(at.stall.distance_to(gate), 15.0, "a short walk in from the back gate")
	assert_lt(at.stall.distance_to(gate), at.house.distance_to(gate), "in front of his house, not behind it")
	assert_lt(at.stall.distance_to(at.garage_side_a), 11.0, "beside his garage")


func test_his_card_offers_only_the_ship_the_game_says() -> void:
	var b := NpcBrain.new(null, SpeederPost.CARD_PATH)
	assert_string_contains(str(b.builder.rules_message().content), "offer_ship_buy")
	var c := b.canned_reply("Want to buy my ship?")
	assert_true((c.actions as Array).is_empty(), "no ship by his post: land it first")
	b.ship_offer = func(): return { "id": "ship:3", "name": "Remnant Fighter", "price": 1875, "stolen": true }
	c = b.canned_reply("Want to buy my ship?")
	assert_eq(str(c.actions[0].type), "offer_ship_buy")
	var ids := { "ship_buy": b.ship_offer.call(), "allowed": b.builder.actions() }
	var v := ActionValidator.validate([{ "type": "offer_ship_buy", "id": "ship:3", "price": 1 }], ids, {})
	assert_eq(int(v.kept[0].price), 1875, "the game's price, never the model's")
	v = ActionValidator.validate([{ "type": "offer_ship_buy", "id": "ship:0" }], ids, {})
	assert_true(v.kept.is_empty(), "not the ship by his post")


# ---- the look ------------------------------------------------------------------------------

class FakeDemo extends Node:
	var use_look := true
	var look: LookEnvironment          # issue #458: his lamps track it when there is one
	func _flat_mats() -> LookMaterials:
		return LookMaterials.new()


## Only the look: no town, no Skrugs, no speeders (Godot 4 does not call the
## parent's _ready for it).
class BarePost extends SpeederPost:
	func _ready() -> void:
		pass


func test_no_price_board() -> void:
	var demo := FakeDemo.new()
	add_child_autofree(demo)
	var post := BarePost.new()
	post.demo = demo
	add_child_autofree(post)
	for loc_id in ["skrugs_post", "skrugs_post_round"]:
		post._dress(content.get_location(loc_id))
	var boards := post.get_children().filter(func(n): return n is MeshInstance3D and n.mesh is BoxMesh \
		and (n.mesh as BoxMesh).size.is_equal_approx(Vector3(0.06, 0.7, 1.2)))
	assert_eq(boards.size(), 0, "no price board in either town")
	assert_gt(post.get_children().size(), 10, "the rest is dressed")


# ---- issue #458: his lamps and his workbench -----------------------------------------------

## The post dressed with a look to track its lamps (as town_demo gives it), for a
## layout. Origin and yaw stay zero, so positions read in the post's own frame.
func _lit_post(loc_id: String) -> Array:
	var demo := FakeDemo.new()
	demo.look = LookEnvironment.new()
	demo.add_child(demo.look)
	add_child_autofree(demo)
	var post := BarePost.new()
	post.demo = demo
	var loc: Dictionary = content.get_location(loc_id)
	for k in loc.get("points", {}):
		post.points[k] = WorldGround._v3(loc.points[k])
	add_child_autofree(post)
	post._dress(loc)
	return [post, demo.look, loc]


func _lamps_of(post: Node) -> Array:
	return post.get_children().filter(func(n): return n is OmniLight3D)


func test_four_lamps_on_by_day_and_brighter_at_dusk() -> void:
	for loc_id in ["skrugs_post", "skrugs_post_round"]:
		var r := _lit_post(loc_id)
		var post: SpeederPost = r[0]
		var look: LookEnvironment = r[1]
		var lamps := _lamps_of(post)
		var names: Array = lamps.map(func(l): return str(l.name))
		names.sort()
		assert_eq(names, ["BenchLamp", "DoorLamp", "GarageLight", "StallLamp"], "%s: the counter, the garage, the house door and the bench" % loc_id)
		for l in lamps:
			assert_true(look._lamps.has(l), "%s: %s is on the look's lamp clock" % [loc_id, l.name])
			assert_false(l.shadow_enabled, "%s: %s casts no shadow (cheap)" % [loc_id, l.name])
		look.apply("noon")
		var day := {}
		for l in lamps:
			assert_true(l.visible and l.light_energy > 0.0, "%s: %s stays on at noon" % [loc_id, l.name])
			day[l.name] = l.light_energy
		look.apply("dusk")
		for l in lamps:
			assert_gt(l.light_energy, float(day[l.name]), "%s: %s is brighter at dusk" % [loc_id, l.name])


func test_his_bench_has_a_pegboard_behind_it() -> void:
	for loc_id in ["skrugs_post", "skrugs_post_round"]:
		var r := _lit_post(loc_id)
		var post: SpeederPost = r[0]
		var loc: Dictionary = r[2]
		var boards: Array = post.get_children().filter(func(n): return str(n.get_meta("decor", "")) == "workbench")
		assert_eq(boards.size(), 1, "%s: one pegboard" % loc_id)
		var tools: Array = post.get_children().filter(func(n): return str(n.get_meta("decor", "")) == "tool")
		assert_gt(tools.size(), 3, "%s: tools on it" % loc_id)
		var bench: Dictionary = loc.buildings.filter(func(b): return str(b.id) == "bench")[0]
		var c := WorldGround._v3(bench.position)
		var stand: Vector3 = post.points["bench"] - c
		var board: Vector3 = (boards[0] as Node3D).position - c
		stand.y = 0.0
		board.y = 0.0
		assert_lt(board.dot(stand), 0.0, "%s: the pegboard stands on the far side from where the player stands" % loc_id)
		assert_lt(board.length(), 2.0, "%s: ... right behind the bench" % loc_id)


func test_the_look_off_has_no_lamps_and_no_pegboard() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	var t = _town()
	var post: SpeederPost = t.speeder_post
	assert_not_null(post, "the post is built")
	assert_eq(_lamps_of(post).size(), 0, "look off: no lamps")
	assert_eq(post.get_children().filter(func(n): return n.has_meta("decor")).size(), 0, "look off: no dressing")
	assert_not_null(post.shop, "free roam: his bench still works")
