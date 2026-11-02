extends GutTest
## The standing toast (StandingNews, StandingToast): "Remnant standing +10" with
## the change green for up and red for down, over a gauge. Faction standing
## only; what one character thinks of you (Oda's trust) is not news here.


func before_each() -> void:
	WorldState.reset()
	StandingNews.clear()


func test_a_standing_change_is_news() -> void:
	var was := int(WorldState.standing.imperial_remnant)
	WorldState.change_standing("imperial_remnant", 10)
	assert_eq(StandingNews.queue.size(), 1)
	assert_eq(StandingNews.queue[0].from, was)
	assert_eq(StandingNews.queue[0].to, was + 10)


func test_no_move_is_no_news() -> void:
	WorldState.standing.locals = 100
	WorldState.change_standing("locals", 5)         # already at the limit
	WorldState.change_standing("smuggler", 0)
	assert_true(StandingNews.queue.is_empty())


func test_the_limit_clamps_the_news() -> void:
	WorldState.standing.locals = 97
	WorldState.change_standing("locals", 10)
	assert_eq(StandingNews.queue[0].to - StandingNews.queue[0].from, 3)


func test_two_changes_to_one_faction_waiting_are_one() -> void:
	var was := int(WorldState.standing.locals)
	WorldState.change_standing("locals", 4)
	WorldState.change_standing("locals", -1)
	assert_eq(StandingNews.queue.size(), 1)
	assert_eq(StandingNews.queue[0].from, was)
	assert_eq(StandingNews.queue[0].to, was + 3)


func test_reset_clears_the_news() -> void:
	WorldState.change_standing("locals", 4)
	WorldState.reset()
	assert_true(StandingNews.queue.is_empty())


func test_a_load_and_the_dev_panel_are_not_news() -> void:
	WorldState.standing["locals"] = 50
	assert_true(StandingNews.queue.is_empty())


func test_a_characters_trust_is_not_standing_news() -> void:
	var rel := Relationship.new()
	rel.trust = 40
	assert_true(StandingNews.queue.is_empty())


func test_names_come_from_the_story_data() -> void:
	assert_eq(StandingNews.faction_name("imperial_remnant"), "Remnant")
	assert_eq(StandingNews.faction_name("dune_nomads"), "Dune Nomads", "no entry: made from the id")


func test_the_toast_reads_name_and_change_and_colours_it() -> void:
	var t := StandingToast.new()
	add_child_autofree(t)
	WorldState.change_standing("imperial_remnant", 10)
	t._process(0.01)
	var up: StandingToast.Row = t.rows.imperial_remnant
	assert_eq(up.title.text, "Remnant standing")
	assert_eq(up.amount.text, "+10")
	assert_eq(up.change_color(), StandingToast.GREEN)
	WorldState.change_standing("locals", -4)
	t._process(0.01)
	var down: StandingToast.Row = t.rows.locals
	assert_eq(down.amount.text, "-4")
	assert_eq(down.change_color(), StandingToast.RED)
	assert_eq(t.rows.size(), 2, "one row for each faction, together")


func test_the_marker_sweeps_and_the_row_clears() -> void:
	var t := StandingToast.new()
	add_child_autofree(t)
	t.show_change("smuggler", 20, 30)
	var r: StandingToast.Row = t.rows.smuggler
	assert_eq(r.shown, 20.0)
	t._process(StandingToast.SWEEP * 0.5)
	assert_between(r.shown, 20.1, 29.9)
	t._process(StandingToast.SWEEP)
	assert_eq(r.shown, 30.0)
	t._process(StandingToast.IN + StandingToast.HOLD + StandingToast.OUT)
	assert_true(t.rows.is_empty())


func test_a_second_change_adds_to_the_row_up() -> void:
	var t := StandingToast.new()
	add_child_autofree(t)
	t.show_change("locals", 5, 9)
	t._process(StandingToast.HOLD)
	t.show_change("locals", 9, 7)
	var r: StandingToast.Row = t.rows.locals
	assert_eq(r.amount.text, "+2", "from where the row began")
	t._process(StandingToast.HOLD)
	assert_false(t.rows.is_empty(), "held again")
