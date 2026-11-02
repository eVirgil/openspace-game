extends GutTest
## The locals work their checkpoints like the Remnant did: the front gate and the
## barracks yard when they hold the barracks, and the ring round each outpost they
## hold. The same rules in the same places, on your standing with the locals. In
## good standing you walk through; below the wave band a guard asks for papers; in
## poor standing it is papers and a search. A fight at the barracks is a fight with
## the port, and back. Headless (no look layer); each garrison is stepped by hand
## with its guards seeing you.

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	WorldState.time_of_day = "golden"
	WorldState.set_flag("remnant_fleet_beaten")     # the locals hold the barracks


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = true
	add_child_autofree(t)
	return t


## `seconds` of garrison `g` with the player held at `at`, everyone in `who` seeing them.
func _step(g: Garrison, who: Array, seconds: float, at: Vector3) -> void:
	for i in maxi(1, int(seconds / DT)):
		g.player.global_position = at
		for guard in who:
			if is_instance_valid(guard) and not guard.dead:
				guard.perception.noticed = true
		g._physics_process(DT)


func _zone(g: Garrison, id: String) -> Dictionary:
	for z in g.zones:
		if str(z.spec.get("id", "")) == id:
			return z
	return {}


func _barracks(t) -> Garrison:
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS)
	var g: Garrison = t.locals_garrison
	assert_not_null(g, "the locals' barracks guards have a garrison")
	assert_eq(g.faction, "locals")
	assert_eq(g.members.size(), Territory.barracks_posts().size(), "every barracks post")
	assert_eq(g.guards.size(), 2, "two of them on the gate")
	for guard in g.members:
		assert_eq(guard.faction, "locals")
		assert_false(t.townsfolk.brains.has(guard), "the garrison runs them, not the townsfolk")
	assert_true(t.garrison == null or t.garrison.guards.is_empty(), "no Remnant on the gate")
	assert_eq(g.gate_pos, t.town.marker_pos("gate"), "the same place")
	return g


func _at_gate(g: Garrison) -> Vector3:
	return g.gate_pos + Vector3(4.0, 0.0, 0.0)


## A spot in the barracks yard: in front of the hall, between the yard walls.
func _in_yard(z: Dictionary) -> Vector3:
	var lo: Array = z.spec.min
	var hi: Array = z.spec.max
	return Vector3(lerpf(float(lo[0]), float(hi[0]), 0.4), 0.0, float(lo[1]) + 6.0)


func test_the_locals_use_the_remnant_gate_rules() -> void:
	var t = _town()
	var g := _barracks(t)
	var cc = preload("res://src/systems/dataload/core_content.gd").new()
	cc.load_from()
	assert_eq(g.checkpoint.cfg, cc.get_soldier("gate_guard").get("checkpoint", {}), "one set of gate rules")


func test_in_good_standing_with_the_locals_you_walk_through() -> void:
	var t = _town()
	var g := _barracks(t)
	WorldState.standing.imperial_remnant = -60      # the Remnant's opinion no longer matters here
	WorldState.standing.locals = 50
	_step(g, g.guards, 8.0, _at_gate(g))
	assert_false(g.checkpoint.card_open, "no card")
	assert_eq(g.cards_shown, 0)
	assert_false(g.alarm.active())


func test_in_poor_standing_with_the_locals_the_gate_stops_and_searches_you() -> void:
	var t = _town()
	var g := _barracks(t)
	WorldState.standing.imperial_remnant = 60
	WorldState.standing.locals = -10
	WorldState.credits = 0
	_step(g, g.guards, 8.0, _at_gate(g))
	assert_true(g.checkpoint.card_open, "a guard walks up with the card")
	assert_eq(g.checkpoint.band, "search")
	assert_eq(g.cards_shown, 1)
	var before := int(WorldState.standing.get("locals", 0))
	assert_true(g.choose("mouth_off"))
	assert_lt(int(WorldState.standing.get("locals", 0)), before, "the locals' standing moves, not the Remnant's")
	assert_eq(int(WorldState.standing.get("imperial_remnant", 0)), 60)


func test_the_barracks_yard_stops_you_too() -> void:
	var t = _town()
	var g := _barracks(t)
	var z := _zone(g, "barracks")
	assert_false(z.is_empty(), "the barracks yard is a checkpoint zone")
	assert_gt(z.guards.size(), 0, "with the locals' yard guards on it")
	WorldState.standing.locals = -10
	_step(g, z.guards, 8.0, _in_yard(z))
	assert_true((z.checkpoint as Checkpoint).card_open, "a yard guard walks up with the card")
	assert_eq((z.checkpoint as Checkpoint).band, "search")


func test_an_outpost_the_locals_hold_stops_you_too() -> void:
	var id := str(Story.OUTPOSTS[0])
	Territory.take(id)
	var t = _town()
	var o: Dictionary = {}
	for each in t.outposts.outposts:
		if str(each.id) == id:
			o = each
	assert_false(o.is_empty())
	var og = t.outposts.folks.get(id)
	assert_true(og is Garrison, "the locals there have a garrison")
	assert_eq(og.faction, "locals")
	var z := _zone(og, id)
	assert_false(z.is_empty(), "the outpost's ring is a checkpoint zone")
	assert_gt(z.guards.size(), 0, "with the locals' guards on it")
	var at: Vector3 = (o.origin as Vector3) + Vector3(12.0, 0.0, 0.0)
	WorldState.standing.locals = -10
	_step(og, z.guards, 8.0, at)
	assert_true((z.checkpoint as Checkpoint).card_open, "poor standing: the card opens out there")
	assert_eq((z.checkpoint as Checkpoint).band, "search")
	assert_false(t.townsfolk.alarm.active(), "an outpost's fight is its own")


func test_a_barracks_fight_is_a_fight_with_the_port_and_back() -> void:
	var t = _town()
	var g := _barracks(t)
	g._raise("attacked")
	assert_true(g.alarm.active())
	assert_true(t.townsfolk.alarm.active(), "the town's locals join the barracks' fight")
	g.forgive_player()
	t.townsfolk.forgive_player()
	t.townsfolk._raise("attacked")
	assert_true(g.alarm.active(), "and the barracks join the town's")
