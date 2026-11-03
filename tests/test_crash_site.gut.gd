extends GutTest
## Issue #148: the crashed starcruiser is a place to ride and fight in. A speeder
## rides up the kicker plate and launches off it (and up the boarding plate into the
## hold); the hold climbs to a level interior deck; ramps and broken railings join it
## to the bridge platform and the upper gallery; every part wears the wreck's metal;
## the Remnant's droids patrol the bridge and the ship; an old cargo droid in the deep
## hold carries a red energy saber that turns your blade red.
## Wreck cleanup: the hold floor is an open speeder ramp; three tiers of decks hang
## off the plating with catwalks, ramps and railings; four assassins on the pad.
## Pure WorldGround queries on the analytic planet, plus a small scene for the droids.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const ID := "starcruiser_wreck"

var _old_current: PlanetSphere
var _sp: PlanetSphere
var g: WorldGround


func before_each() -> void:
	WorldState.reset()
	_old_current = PlanetSphere.current
	_sp = PlanetSphere.new(5000.0)
	_sp.configure_site(Rect2(-200, -200, 400, 400), Rect2(-210, -210, 420, 420), [], 0.0)
	PlanetSphere.current = _sp
	var world: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	var wreck: Array = world.landmarks.filter(func(lm): return str(lm.kind) == "wreck")
	g = WorldGround.new()
	g.setup({ "terrain": { "sphere_radius": 5000.0 }, "landmarks": wreck }, null, null)


func after_each() -> void:
	PlanetSphere.current = _old_current
	WorldState.reset()


func _box(name: String) -> Dictionary:
	for b in g.boxes:
		if str(b.id) == ID + "/" + name:
			return b
	return {}


func _lv(x: float, v: float, w: float) -> Vector3:
	return StarcruiserWreck.site_point(g, Vector3(x, v, w), "level")


func _hull(x: float, y: float, z: float) -> Vector3:
	return StarcruiserWreck.site_point(g, Vector3(x, y, z), "hull")


## A speeder at `at` facing `dir` (along the ground there).
func _speeder(at: Vector3, dir: Vector3) -> HoverModel:
	var m := HoverModel.new(HoverModel.load_config("speeder"), g)
	m.place(at, 0.0)
	var up := g.up_at(m.position)
	var l := PlanetSphere.tilt_to(up).inverse() * (dir - up * dir.dot(up)).normalized()
	m.yaw = atan2(-l.x, -l.z)
	return m


## Walk the line through `points` (world, on the floor) in 0.5 m steps: the floor is
## always there within a step (0.4 m) of the line, nothing is in the way at the
## waist or the head. Returns "" or what went wrong where.
func _walkable(points: Array) -> String:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.5))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var up := g.up_at(p)
			var h := g.height_above(p + up)
			if absf(h - 1.0) > 0.4:
				return "no floor at leg %d step %d (%.2f m under the waist)" % [i, k, h]
			for lift in [1.0, 1.7]:
				var what := g.hit(p + up * lift, 0.35)
				if what != "":
					return "%s in the way at leg %d step %d" % [what, i, k]
	return ""


# ---- the speeder ------------------------------------------------------------------

func test_a_speeder_rides_up_the_kicker_and_launches_off_it() -> void:
	var kicker := _box("speeder_kicker")
	assert_false(kicker.is_empty(), "a bent hull plate stands by the boarding plate")
	var xf := WorldGround.box_xf(kicker)
	var half: Vector3 = ((kicker.max as Vector3) - (kicker.min as Vector3)) * 0.5
	var foot := xf * Vector3(0, half.y, -half.z)
	var lip := xf * Vector3(0, half.y, half.z)
	var dir := (lip - foot).normalized()
	var flat := (dir - g.up_at(foot) * dir.dot(g.up_at(foot))).normalized()
	var m := _speeder(foot - flat * 60.0, flat)
	var launch := {}
	var landed := {}
	var bumps: Array = []
	for i in 60 * 8:
		m.set_command(1.0, 0.0, true)
		for e in m.step(1.0 / 60.0):
			if e.type == "bump":
				bumps.append(e.what)
			if e.type == "launch" and launch.is_empty():
				launch = e
				launch["at"] = m.position
			if e.type == "landed" and not launch.is_empty():
				landed = e
		if not landed.is_empty():
			break
	assert_eq(bumps, [], "nothing on the run-up or the plate stops it")
	assert_false(launch.is_empty(), "it leaves the ground")
	assert_lt((launch.get("at", Vector3.INF) as Vector3).distance_to(lip), 6.0, "off the kicker's lip")
	assert_gt(float(launch.get("vy", 0.0)), 5.0, "carrying the plate's climb up into the air")
	assert_false(landed.is_empty(), "and comes down")
	assert_gt(float(landed.get("air_time", 0.0)), 1.5, "after a real jump")
	assert_true(m.alive() and m.hp == m.max_hp, "unhurt")


func test_a_speeder_rides_up_the_boarding_plate_into_the_hold() -> void:
	var plate := _box("fallen_boarding_plate")
	var xf := WorldGround.box_xf(plate)
	var half: Vector3 = ((plate.max as Vector3) - (plate.min as Vector3)) * 0.5
	var foot := xf * Vector3(0, half.y, -half.z)
	var dir := xf.basis.z.normalized()
	var flat := (dir - g.up_at(foot) * dir.dot(g.up_at(foot))).normalized()
	var m := _speeder(foot - flat * 30.0, flat)
	var entry := StarcruiserWreck.site_point(g, StarcruiserWreck.ENTRY, "hull")
	var bumps: Array = []
	var best := INF
	for i in 60 * 10:
		m.set_command(0.6, 0.0)
		for e in m.step(1.0 / 60.0):
			if e.type == "bump":
				bumps.append(e.what)
		best = minf(best, m.position.distance_to(entry))
		if best < 3.0:
			break                    # on the deck; across it is the far hull
	assert_eq(bumps, [], "the plate and the breach let it through")
	assert_lt(best, 4.0, "it rides up the plate onto the hold's deck")


# ---- the interior -------------------------------------------------------------------

const U := StarcruiserWreck.INTERIOR_V
const M := StarcruiserWreck.MID_V
const L := StarcruiserWreck.LOW_V
const B := StarcruiserWreck.BRIDGE_V


func test_the_interior_floors_are_level() -> void:
	for id in ["starboard_deck", "upper_catwalk", "port_deck_stern", "mid_catwalk", "starboard_ledge",
			"port_ledge", "starboard_balcony", "port_balcony", "bridge_platform"]:
		var b := _box(id)
		assert_false(b.is_empty(), id)
		var xf := WorldGround.box_xf(b)
		var c := xf * (((b.min as Vector3) + (b.max as Vector3)) * 0.5)
		assert_gt(xf.basis.y.normalized().dot(g.up_at(c)), cos(deg_to_rad(4.0)), "%s is level with the horizon, not the hull" % id)


## Wreck cleanup: nothing but the floor within six metres of the hold floor's
## middle, from the breach to the stern bulkhead; the floor runs right up to it.
func test_the_hold_floor_is_an_open_speeder_ramp_to_the_stern() -> void:
	var mine := g.boxes.filter(func(b): return str(b.id).begins_with(ID + "/") and not str(b.id).contains("lower_deck"))
	var x_max := StarcruiserWreck.CLEAR_X - 1.0
	var blocked := {}
	for x in [-x_max, -x_max * 0.5, 0.0, x_max * 0.5, x_max]:
		for z in range(-80, 296, 2):
			for k in [1.0, 2.5, 4.0, 6.0]:
				var p := _hull(x, StarcruiserWreck.DECK_Y + k, z)
				for b in mine:
					if _inside(b, p):
						blocked[str(b.id)] = p
	assert_eq(blocked, {}, "the speeder lane is open")
	assert_eq(_walkable([_hull(0, -24, -30), _hull(0, -24, 295)]), "", "up the floor to the bulkhead")


func test_the_hold_floor_leads_to_the_stern_ramp_and_on_up_to_the_landing_pad() -> void:
	var w := StarcruiserWreck.STERN_RAMP_W
	var head := StarcruiserWreck.floor_v(w)
	var route := [
		_hull(24, -24, 150), _hull(24, -24, 285),               # up the hold floor beside the ramp lane
		_lv(28, head, w - 0.5), _lv(31, head - 0.1, w - 1.0),   # step across onto the ramp's head
		_lv(33, U, 232), _lv(30, U, 228),                       # down along the starboard plating
		_lv(30, U, 188), _lv(30, U, 182), _lv(0, U, 182),       # across the starboard deck to the catwalk
		_lv(0, U, 180), _lv(0, B, 150), _lv(0, B, 132),         # up through the torn dorsal plates
	]
	assert_eq(_walkable(route), "", "hold floor -> stern ramp -> starboard deck -> catwalk -> bridge ramp -> pad")
	assert_lt(head - U, 6.0, "the starboard deck is a short drop below the top of the floor")
	assert_gt(head, U, "and it is lower")
	var top := _lv(0, B, 132)
	assert_gt(_sp.height_above_ground(top), 150.0, "the bridge stands high over the dunes")


func test_a_ramp_joins_the_upper_gallery_to_the_port_decks() -> void:
	var a := deg_to_rad(34.0)
	var g_end := Vector3(-20, -3.3, 235)
	var route := [
		_hull(-20, -3.3, 200),                                  # up the gallery
		_lv(-20, g_end.y * cos(a) + g_end.z * sin(a), -g_end.y * sin(a) + g_end.z * cos(a)),
		_lv(-20, U, 219), _lv(-20, U, 225), _lv(-34, U, 225),   # onto the port deck's stern
		_lv(-34, U, 190), _lv(-34, U, 182), _lv(0, U, 182),     # along the plating to the catwalk
	]
	assert_eq(_walkable(route), "", "gallery -> ramp -> port decks -> upper catwalk")


func test_stairs_and_drops_reach_the_mid_and_low_tiers_on_both_sides() -> void:
	for s in [1.0, -1.0]:
		var route := [
			_lv(23 * s, U, 182), _lv(23 * s, U, 178),           # the stair off the upper catwalk
			_lv(23 * s, M, 154), _lv(23 * s, M, 152),           # onto the mid catwalk
			_lv(33 * s, M, 152), _lv(33 * s, M, 170),           # along the ledge
			_lv(39 * s, M, 174), _lv(39 * s, M, 176),
			_lv(36 * s, L, 200), _lv(34 * s, L, 203),           # and back aft, down to the balcony
		]
		assert_eq(_walkable(route), "", "%s: upper catwalk -> stair -> mid catwalk -> ledge -> drop -> balcony" % ("starboard" if s > 0 else "port"))
	assert_eq(_walkable([_lv(-30, M, 152), _lv(30, M, 152)]), "", "the mid catwalk crosses the hold")
	assert_eq(_walkable([_lv(-34, U, 182), _lv(34, U, 182)]), "", "so does the upper one")


## Wreck cleanup: the decks hang off the plating. Walk out from each toward the
## hull wall: there is deck underfoot all the way until the plating stops your
## feet (below the hull's waist the plating leans out above the deck).
func test_every_hung_deck_meets_the_plating() -> void:
	for d in [
		["starboard_deck", U, 1.0, [188, 200, 214, 230]], ["port_deck_bow", U, -1.0, [188, 194]],
		["port_deck_outer", U, -1.0, [198, 208, 217]], ["port_deck_stern", U, -1.0, [224, 227]],
		["upper_catwalk", U, 1.0, [180, 184]], ["upper_catwalk", U, -1.0, [180, 184]],
		["mid_catwalk", M, 1.0, [151, 153]], ["mid_catwalk", M, -1.0, [151, 153]],
		["starboard_ledge", M, 1.0, [158, 166, 174]], ["port_ledge", M, -1.0, [160, 166, 174]],
		["starboard_balcony", L, 1.0, [201, 205]], ["port_balcony", L, -1.0, [201, 205]],
	]:
		for w in d[3]:
			var v: float = d[1]
			var s: float = d[2]
			var x := 32.0
			var met := ""
			while x < 50.0 and met == "":
				var p := _lv(x * s, v, float(w))
				if g.hit(p + g.up_at(p) * 0.5, 0.5) != "":
					met = "wall"
				elif absf(g.height_above(p + g.up_at(p)) - 1.0) > 0.3:
					met = "falls off at x=%.1f" % (x * s)
				x += 0.25
			assert_eq(met, "wall", "%s at w=%s reaches the plating" % [d[0], w])


func test_three_times_the_decks_ramps_and_railings() -> void:
	var interior := ["starboard_deck", "upper_catwalk", "port_deck_bow", "port_deck_outer", "port_deck_stern",
		"mid_catwalk", "starboard_ledge", "port_ledge", "starboard_balcony", "port_balcony", "bridge_platform"]
	for id in interior:
		assert_eq(str(_box(id).get("kind", "")), "floor", "%s is a floor" % id)
	var ramps := ["stern_ramp", "gallery_ramp", "bridge_ramp", "starboard_stair", "port_stair", "starboard_drop", "port_drop"]
	for id in ramps:
		assert_false(_box(id).is_empty(), id)
	var runs := {}
	for b in g.boxes:
		var id := str(b.id)
		if id.begins_with(ID + "/") and id.contains("_rail") and id.contains("_post_"):
			runs[id.get_slice("_post_", 0)] = true
	assert_gte(interior.size() + 1, 3 * 4, "with the gallery; was the interior deck, landing, bridge platform and gallery")
	assert_gte(ramps.size(), 3 * 2, "was the gallery and bridge ramps")
	assert_gte(runs.size(), 3 * 8, "was eight railing runs")


func test_broken_railings_line_the_open_edges() -> void:
	for run in ["starboard_deck_rail", "mid_catwalk_bow_rail", "upper_catwalk_stern_rail", "bridge_port_rail",
			"starboard_stair_rail_p", "stern_ramp_rail_p"]:
		var panels := g.boxes.filter(func(b): return str(b.id).begins_with(ID + "/" + run + "_") and not str(b.id).contains("_post_"))
		assert_gt(panels.size(), 0, "%s stands" % run)
	assert_false(_box("starboard_deck_rail_0").is_empty())
	assert_true(_box("starboard_deck_rail_3").is_empty(), "with panels knocked out")
	var sagging := _box("starboard_deck_rail_2")
	assert_false(sagging.is_empty())
	var up := g.up_at(WorldGround.box_xf(sagging).origin)
	assert_lt(WorldGround.box_xf(sagging).basis.y.normalized().dot(up), cos(deg_to_rad(10.0)), "and some sagging")
	# A rail stops you walking off the starboard deck's inner edge.
	assert_ne(g.hit(_lv(22, U + 1.0, 190), 0.35), "", "the deck rail is solid")
	# A ramp's rail follows its slope.
	var stair := _box("starboard_stair_rail_p_0")
	assert_false(stair.is_empty())
	assert_lt(absf(WorldGround.box_xf(stair).basis.z.normalized().dot(g.up_at(WorldGround.box_xf(stair).origin))), 0.5)
	assert_gt(absf(WorldGround.box_xf(stair).basis.z.normalized().dot(g.up_at(WorldGround.box_xf(stair).origin))), 0.2, "sloped with the stair")


func test_the_hatch_is_torn_and_the_old_solid_bridge_is_gone() -> void:
	assert_true(_box("plate_%d_1" % StarcruiserWreck.HATCH_SECTION).is_empty())
	assert_true(_box("plate_%d_2" % StarcruiserWreck.HATCH_SECTION).is_empty())
	assert_false(_box("plate_%d_3" % StarcruiserWreck.HATCH_SECTION).is_empty(), "only the dorsal plates")
	assert_false(_box("bridge").is_empty(), "the bridge house stands on the platform")
	assert_false(_box("bridge_strut_-11").is_empty())


func test_every_surface_wears_the_wreck_metal() -> void:
	var mine := g.boxes.filter(func(b): return str(b.id).begins_with(ID + "/"))
	assert_gt(mine.size(), 300)
	for b in mine:
		assert_true(b.has("wreck_finish") and b.has("wreck_frame") and b.has("wreck_level"), str(b.id))
	var scenery := WorldScenery.new()
	scenery.setup(g)
	add_child_autofree(scenery)
	scenery.build_visuals()
	# Wreck cleanup: walkways get their own finish on top: decking, grating, ramp
	# cleats and the bridge platform's landing-pad paint.
	for pair in [["starboard_deck", 5], ["starboard_deck_fill_s3", 5], ["upper_catwalk", 6], ["mid_catwalk", 6],
			["bridge_platform", 8], ["bridge_ramp", 7], ["gallery_ramp", 7], ["stern_ramp", 7],
			["speeder_kicker", 0], ["starboard_deck_rail_0", 3]]:
		var mi := scenery.wreck_part(ID + "/" + str(pair[0]))
		assert_not_null(mi, pair[0])
		if mi != null:
			var mat := mi.material_override as ShaderMaterial
			assert_eq(mat.shader, WorldScenery.WRECK_SHADER, "%s is the ship's metal" % pair[0])
			assert_eq(int(mat.get_shader_parameter("finish")), int(pair[1]), "%s finish" % pair[0])


func _inside(b: Dictionary, p: Vector3) -> bool:
	var l := WorldGround.box_xf(b).affine_inverse() * p
	var mn: Vector3 = b.min
	var mx: Vector3 = b.max
	return l.x > mn.x and l.x < mx.x and l.y > mn.y and l.y < mx.y and l.z > mn.z and l.z < mx.z


# ---- the droids ----------------------------------------------------------------------

func test_every_wreck_route_runs_on_a_floor() -> void:
	var wc: Dictionary = DroidRoster.config().wreck
	for name in wc.routes:
		var r: Dictionary = wc.routes[name]
		var pts: Array = r.points.map(func(p): return StarcruiserWreck.site_point(g, Vector3(p[0], p[1], p[2]), str(r.frame)))
		pts.append(pts[0])
		assert_eq(_walkable(pts), "", "route %s" % name)
	for u in wc.units:
		assert_true(wc.routes.has(str(u.route)), "unit route %s exists" % u.route)
	assert_true(wc.routes.has(str(wc.hauler.route)))
	var pad_units: Array = wc.units.filter(func(u): return str(u.route) in ["bridge", "pad"] and str(u.kind) == "assassin")
	var floaters: Array = wc.units.filter(func(u): return str(u.kind) == "floating")
	assert_eq(pad_units.size(), 4, "four assassin droids hold the landing pad on the bridge platform")
	assert_gte(floaters.size(), 10, "floating droids all over the inside of the ship")
	var routes := {}
	for u in floaters:
		routes[str(u.route)] = true
	assert_gte(routes.size(), 8, "on every tier, not bunched up")


func test_the_remnant_patrols_the_wreck_and_a_cargo_droid_carries_the_saber() -> void:
	WorldState.droids.wrecks_seeded = true
	var root := Node3D.new()
	add_child_autofree(root)
	var scenery := WorldScenery.new()
	scenery.setup(g)
	root.add_child(scenery)
	var p := FakePlayer.new()
	root.add_child(p)
	p.global_position = _hull(30.0, StarcruiserWreck.DECK_Y, -35.0)   # aboard: they idle when nobody is near
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	ctl.ground = g
	root.add_child(ctl)
	await wait_physics_frames(2)
	var mine: Array = ctl.remnant.filter(func(u): return str(u.spec.get("site", "")) == ID)
	assert_eq(mine.size(), (DroidRoster.config().wreck.units as Array).size(), "every wreck unit is out")
	for u in mine:
		assert_eq(u.faction, "imperial_remnant")
		assert_true(ctl.remnant_hostile(u), "they shoot on sight")
		assert_null(ctl._garrison(u), "and call no garrison")
		assert_lt(absf(g.height_above(u.global_position + g.up_at(u.global_position)) - 1.0), 0.3, "standing on a floor")
	var bridge: Array = mine.filter(func(u): return str(u.spec.route) == "bridge")
	var start: Vector3 = bridge[0].global_position
	for i in 90:
		await wait_physics_frames(1)
	assert_gt(bridge[0].global_position.distance_to(start), 1.5, "the bridge droid walks its round")
	assert_lt(absf(g.height_above(bridge[0].global_position + g.up_at(start)) - 1.0), 0.3, "on the platform")
	assert_not_null(ctl.wreck_hauler, "an old cargo droid in the deep hold")
	assert_eq(ctl.wreck_hauler.kind, "cargo")
	assert_eq(ctl.wreck_hauler.faction, "", "nobody's")
	assert_eq(str(DroidRoster.config().wreck.hauler.carries), "wreck_red_saber")
	ctl.withdraw_town_remnant()
	assert_eq(ctl.remnant.filter(func(u): return str(u.spec.get("site", "")) == ID).size(), mine.size(), "they stay after the fleet falls")


# ---- the red saber -------------------------------------------------------------------

func test_the_red_saber_is_a_carried_pickup_that_turns_the_blade_red() -> void:
	var content = CoreScript.new()
	content.load_from()
	var item: Dictionary = content.get_item("red_energy_saber")
	assert_false(item.is_empty())
	var red := Color(str(item.blade_color))
	assert_true(red.r > 0.9 and red.g < 0.3 and red.b < 0.3, "it is red")
	var entry: Array = content.get_pickups("port_town").filter(func(e): return str(e.id) == "wreck_red_saber")
	assert_eq(entry.size(), 1)
	assert_eq(str(entry[0].item), "red_energy_saber")
	assert_true(bool(entry[0].carried), "it rides on its droid, hidden until then")
	var look := ItemKit.new().build("red_saber")
	assert_not_null(look.find_child("Blade", true, false), "it looks like a saber")
	look.free()
	var gear := GearController.new()
	gear.content = content
	assert_eq(gear.blade_color().a, 0.0, "the default blade until you own it")
	WorldState.inventory.pick_up(entry[0])
	assert_eq(gear.blade_color().a, 0.0, "owning it does not override your blue blade")
	assert_true(WorldState.inventory.attach("red_energy_saber", item), "it is activated in the inventory")
	assert_eq(gear.blade_color(), red, "activated, the blade is red")
	assert_eq(gear.blade_hilt(), str(item.hilt))
	WorldState.inventory.detach("red_energy_saber")
	assert_eq(gear.blade_color().a, 0.0, "put away, the blue blade again")
	gear.free()
	var kit := CharacterKit.new(LookMaterials.new())
	var sword := kit.make_energy_sword()
	CharacterKit.recolor_energy_sword(sword, red)
	assert_eq(sword.get_meta("color"), red)
	assert_eq((sword.get_node("Blade/BladeLight") as OmniLight3D).light_color, red)
	assert_eq(((sword.get_node("Blade/Glow") as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("color"), red)
	sword.free()


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
