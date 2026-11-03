extends GutTest
## Issue #188: one shared record of events, and word travels. Who was there (the
## card's "hears") knows at once; everyone else once the gossip gets to them
## (gossip_delay). Oda hears everything first. The briefing a character's model
## gets only carries what they have heard.

const FENCE := "res://content/core/npcs/fence_card.json"
const T89 := "res://content/core/npcs/t89_card.json"
const GENERAL := "res://content/core/npcs/general_card.json"
const KILL := "A Remnant gate guard was killed."


func before_each() -> void:
	WorldState.reset()


## The system briefing the brain built for its last turn (no model: canned, but
## the messages are built the same way).
func _briefing(b: NpcBrain) -> String:
	b.begin_visit()
	b.say("Heard anything?")
	var out := ""
	for m in b._messages:
		if str(m.role) == "system" and str(m.content).begins_with("YOUR BRIEFING"):
			out = str(m.content)
	b.end_visit()
	return out


func test_a_kill_at_the_gate_reaches_the_fence_first() -> void:
	WorldState.clock = 10.0
	WorldState.on_guard_killed(-15, false, "gate")
	assert_eq(str(WorldState.events[-1].get("where", "")), "gate")
	WorldState.clock = 25.0                     # a walk to the market
	var fence := NpcBrain.new(null, FENCE)
	var t89 := NpcBrain.new(null, T89)
	assert_string_contains(_briefing(fence), KILL, "the fence hears the gate at once")
	assert_false(_briefing(t89).contains(KILL), "the pit has not heard yet")
	assert_true(NpcBrain.new(null, GENERAL).heard(WorldState.events[-1]), "his men hold the gate")
	assert_true(NpcBrain.new().heard(WorldState.events[-1]), "Oda hears everything first")
	WorldState.clock = 10.0 + t89.gossip_delay()
	assert_string_contains(_briefing(t89), KILL, "then word gets to the pit")


func test_untagged_news_is_gossip_for_everyone_but_oda() -> void:
	WorldState.clock = 5.0
	WorldState.log_event("Killed Old Murk, the beast.")
	WorldState.clock = 6.0
	var fence := NpcBrain.new(null, FENCE)
	assert_false(fence.heard(WorldState.events[-1]))
	assert_true(NpcBrain.new().heard(WorldState.events[-1]))
	WorldState.clock = 5.0 + fence.gossip_delay()
	assert_true(fence.heard(WorldState.events[-1]))


func test_each_place_has_someone_who_hears_it() -> void:
	var t89 := NpcBrain.new(null, T89)
	WorldState.clock = 1.0
	WorldState.log_event("A ship came back into the pit trailing smoke.", "pit")
	assert_true(t89.heard(WorldState.events[-1]))
	assert_false(NpcBrain.new(null, FENCE).heard(WorldState.events[-1]))


func test_where_survives_the_save() -> void:
	WorldState.log_event("Paid off the front gate (10 cr).", "gate")
	var d: Dictionary = WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(d)
	assert_eq(str(WorldState.events[-1].get("where", "")), "gate")
