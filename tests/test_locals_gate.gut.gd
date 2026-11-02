extends GutTest
## The locals hold the front gate when they hold the barracks, and work it like
## the Remnant did: the same checkpoint at the same place, on your standing with
## the locals. In good standing you walk through; below the wave band a guard asks
## for papers; in poor standing it is papers and a search. A fight at the gate is
## a fight with the port, and back. Headless (no look layer); the gate's garrison
## is stepped by hand with its guards seeing you.

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


## `seconds` of the locals' gate with the player just outside it, its guards seeing them.
func _step(g: Garrison, seconds: float) -> void:
	var at := g.gate_pos + Vector3(4.0, 0.0, 0.0)
	for i in maxi(1, int(seconds / DT)):
		g.player.global_position = at
		for guard in g.guards:
			if is_instance_valid(guard) and not guard.dead:
				guard.perception.noticed = true
		g._physics_process(DT)


func _gate(t) -> Garrison:
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS)
	var g: Garrison = t.locals_gate
	assert_not_null(g, "the locals' gate guards have a garrison")
	assert_eq(g.faction, "locals")
	assert_eq(g.guards.size(), 2, "both gate posts")
	for guard in g.guards:
		assert_eq(guard.faction, "locals")
		assert_false(t.townsfolk.brains.has(guard), "the gate runs them, not the townsfolk")
	assert_true(t.garrison == null or t.garrison.guards.is_empty(), "no Remnant on the gate")
	assert_eq(g.gate_pos, t.town.marker_pos("gate"), "the same place")
	return g


func test_the_locals_use_the_remnant_gate_rules() -> void:
	var t = _town()
	var g := _gate(t)
	var cc = preload("res://src/systems/dataload/core_content.gd").new()
	cc.load_from()
	assert_eq(g.checkpoint.cfg, cc.get_soldier("gate_guard").get("checkpoint", {}), "one set of gate rules")


func test_in_good_standing_with_the_locals_you_walk_through() -> void:
	var t = _town()
	var g := _gate(t)
	WorldState.standing.imperial_remnant = -60      # the Remnant's opinion no longer matters here
	WorldState.standing.locals = 50
	_step(g, 8.0)
	assert_false(g.checkpoint.card_open, "no card")
	assert_eq(g.cards_shown, 0)
	assert_false(g.alarm.active())


func test_in_poor_standing_with_the_locals_they_stop_and_search_you() -> void:
	var t = _town()
	var g := _gate(t)
	WorldState.standing.imperial_remnant = 60
	WorldState.standing.locals = -10
	WorldState.credits = 0
	_step(g, 8.0)
	assert_true(g.checkpoint.card_open, "a guard walks up with the card")
	assert_eq(g.checkpoint.band, "search")
	assert_eq(g.cards_shown, 1)
	var before := int(WorldState.standing.get("locals", 0))
	assert_true(g.choose("mouth_off"))
	assert_lt(int(WorldState.standing.get("locals", 0)), before, "the locals' standing moves, not the Remnant's")
	assert_eq(int(WorldState.standing.get("imperial_remnant", 0)), 60)


func test_a_gate_fight_is_a_fight_with_the_port_and_back() -> void:
	var t = _town()
	var g := _gate(t)
	g._raise("attacked")
	assert_true(g.alarm.active())
	assert_true(t.townsfolk.alarm.active(), "the town's locals join the gate's fight")
	g.forgive_player()
	t.townsfolk.forgive_player()
	t.townsfolk._raise("attacked")
	assert_true(g.alarm.active(), "and the gate joins the town's")
