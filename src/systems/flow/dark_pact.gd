class_name DarkPact
extends RefCounted
## Issue #303: the dark master's offer, and the oath that splits the ending. Pure
## and static, like Story; its state is flags in WorldState (saved with the world):
##
##   dark_offered     he made his offer (once a save; missing him counts too)
##   dark_pact        you swore his oath: the Remnant are on your side
##   dark_refused     you said no: he fights you
##   dark_oath_broken you went back to Oda while the oath was open
##   dark_master_dead:<where>  he died there ("cruiser", "barracks")
##   town_retaken     the Remnant hold the town's barracks again (Territory)
##
## Story mode: after the general dies he waits in the cruiser's bay
## (DarkMasterPost). Join, and your Remnant standing jumps to friendly and the
## "dark_oath" quest opens: clear the barracks' local guards. Their deaths hand
## the town back to the Remnant (Territory.barracks_guard_died), raise your
## standing with them to 100 and end the debrief with the dark end card. Telling Oda first breaks the oath. Refuse, and
## he fights you with his red blade.
## Free roam (freeplay saves): no offer; he is an enemy on the cruiser once the
## general is dead, and on the barracks roof too while the Remnant hold the planet.
##
## Friendly with the Remnant in free play, you take their ships without an alarm
## (borrowed, not stolen), and droid prices follow whose side you are on.
##
## Numbers and lines: content/core/npcs/dark_master.json.

const PATH := "res://content/core/npcs/dark_master.json"
const QUEST := "dark_oath"

static var _cfg: Dictionary = {}
static var town_label := ""            ## the town's name for "{town}" in lines (the town scene sets it)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


static func n(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func line(key: String) -> String:
	return fill(str(cfg().get("lines", {}).get(key, "")))


## "{town}" in a line is the town's name.
static func fill(text: String) -> String:
	return text.replace("{town}", town_label if town_label != "" else "the port")


static func offered() -> bool:
	return WorldState.has_flag("dark_offered")


static func joined() -> bool:
	return WorldState.has_flag("dark_pact")


static func refused() -> bool:
	return WorldState.has_flag("dark_refused")


static func oath_open() -> bool:
	return Quests.state(QUEST) == "open"


static func town_retaken() -> bool:
	return WorldState.has_flag(Territory.RETAKEN)


static func dead_at(where: String) -> bool:
	return WorldState.has_flag("dark_master_dead:" + where)


static func _standing() -> int:
	return int(WorldState.standing.get("imperial_remnant", 0))


## Move Remnant standing to `to` (up only, or down only).
static func _standing_at_least(to: int, why: String) -> void:
	if _standing() < to:
		WorldState.change_standing("imperial_remnant", to - _standing(), why)


static func _standing_at_most(to: int, why: String) -> void:
	if _standing() > to:
		WorldState.change_standing("imperial_remnant", to - _standing(), why)


# ------------------------------------------------------------------ the offer (story mode)

## He makes his offer: aboard the cruiser, the general dead, not made before.
static func offer_due() -> bool:
	return WorldState.story_mode() and Story.cruiser_taken() and not offered() and not dead_at("cruiser")


## Yes: the Remnant are yours, and the oath is open. False if it was too late.
static func join() -> bool:
	if offered():
		return false
	WorldState.set_flag("dark_offered")
	WorldState.set_flag("dark_pact")
	_standing_at_least(int(cfg().get("standing", {}).get("join", 25)), "Someone swore the dark master's oath.")
	Story.event("dark_pact")                 # the quest (Quests: unlocked_by)
	WorldState.checkpoint("dark_pact")
	return true


## No: he fights.
static func refuse() -> bool:
	if offered():
		return false
	WorldState.set_flag("dark_offered")
	WorldState.set_flag("dark_refused")
	WorldState.log_event("Someone refused the dark master.")
	WorldState.checkpoint("dark_refused")
	return true


## You left the cruiser without meeting him: the offer is gone.
static func missed() -> void:
	if offered() or not WorldState.story_mode():
		return
	WorldState.set_flag("dark_offered")
	WorldState.set_flag("dark_missed")


## Oda tells the debrief. With the oath open, that breaks it; an offer never
## heard is gone (you came home without meeting him).
static func on_debrief() -> void:
	if joined() and oath_open():
		break_oath()
	missed()


static func break_oath() -> void:
	Quests.fail(QUEST)
	WorldState.set_flag("dark_pact", false)
	WorldState.set_flag("dark_oath_broken")
	_standing_at_most(int(cfg().get("standing", {}).get("broken", -40)), "Someone broke the dark master's oath.")
	WorldState.checkpoint("dark_oath_broken")


## The barracks are the Remnant's again (Territory.retake_town). On the oath,
## that is the oath done: your Remnant standing jumps to its top (the troopers
## who come back must not shoot you for the locals you just cut down) and the
## debrief ends with the dark card.
static func on_town_retaken() -> void:
	if not joined():
		return
	_standing_at_least(int(cfg().get("standing", {}).get("retaken", 100)), "The Remnant took the barracks back.")
	if oath_open():
		Story.event("town_guards_cleared")


## He died at `where`. Killed while you are sworn to him (on the barracks roof),
## the Remnant turn on you and the oath is over.
static func on_killed(where: String) -> void:
	if dead_at(where):
		return
	WorldState.set_flag("dark_master_dead:" + where)
	if joined():
		WorldState.set_flag("dark_pact", false)
		_standing_at_most(int(cfg().get("standing", {}).get("killed", -40)), "Someone killed the dark master.")
	else:
		WorldState.log_event("The dark master was killed.")
	WorldState.checkpoint("dark_master_dead")


# ------------------------------------------------------------------ where he stands

## On the cruiser: after the general's death, until he dies there. In story
## mode only to make his offer or to fight (refused, or the oath broken); once
## you joined him he is gone from it (he waits for the moon).
static func on_cruiser() -> bool:
	if not Story.cruiser_taken() or dead_at("cruiser"):
		return false
	if not WorldState.story_mode():
		return true
	if WorldState.has_flag("dark_missed"):
		return false
	return not offered() or refused() or WorldState.has_flag("dark_oath_broken")


## On the barracks roof, facing the gate, while the Remnant hold the planet: on
## the oath in story mode, always in free roam.
static func on_roof() -> bool:
	if dead_at("barracks") or not Story.cruiser_taken() or not Territory.remnant_planet():
		return false
	return joined() or not WorldState.story_mode()


## He is at `where` to fight you on sight (else he only fights back).
static func hostile_at(where: String) -> bool:
	if not WorldState.story_mode():
		return true
	if where == "cruiser":
		return refused() or WorldState.has_flag("dark_oath_broken")
	return not joined()


# ------------------------------------------------------------------ friends of the Remnant (free play)

## The Remnant count you a friend: they do not shoot on sight and your standing
## is friendly or better.
static func remnant_friend() -> bool:
	return not Story.remnant_hostile() and _standing() >= int(n("friend_standing", 15.0))


## Their ships are yours to borrow (no alarm, no chase), in free play.
static func borrow_ok() -> bool:
	return Story.chapter() == "free" and remnant_friend()


## What a borrowed ship costs in Remnant standing.
static func borrow_cost() -> int:
	return int(n("borrow_standing", -2.0))


## A droid's price at a vendor: the desert droid posts deal cheaply with friends
## of the Remnant, the port's market with friends of the locals. Never under what
## the merchant pays back for it (no buy-and-sell profit).
static func droid_price(kind: String, at_post: bool) -> int:
	var base := DroidRoster.price(kind)
	var faction := "imperial_remnant" if at_post else "locals"
	if at_post and not remnant_friend():
		return base
	var friendly := int(n("friend_standing", 15.0))
	if int(WorldState.standing.get(faction, 0)) < friendly:
		return base
	var cut := int(round(base * n("droid_discount", 0.8)))
	return maxi(cut, DroidRoster.resale(kind))
