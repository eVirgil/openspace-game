class_name GearUpgrades
extends RefCounted
## What the fence sells besides buying contraband (issues #208, #209): one-time
## upgrades for the pistol, the rifle and the jetpack, and quantonium armour once
## the first bounty is paid. Pure and static; what is bought lives in
## WorldState.gear_fits (saved): [offer id, ...].
##
## Each offer is data in content/core/vendors/fence.json "offers":
##   { id, label, price, target, mult: { "<path>": factor } }  an upgrade: factors
##       on paths in the target's data (a weapon file, or the jetpack item's
##       "jetpack.fuel"), put on by apply() where that data is used,
##   { id, label, price, item, requires }  an item, sold once (requires: WorldState's
##       conditions, e.g. a bounty paid). "endless": true = he never runs out: on
##       sale whenever its conditions hold, bought and sold back as often as you like
##       (the quantonium armour, like the nomads' stock).
## An offer with a "locked" hint shows on the menu before its conditions hold
## (locked_offers), so the player knows it is there and what opens it.

const FENCE_PATH := "res://content/core/vendors/fence.json"

static var _offers: Array = []


static func offers() -> Array:
	if _offers.is_empty():
		var f := FileAccess.open(FENCE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_offers = d.get("offers", []) if d is Dictionary else []
	return _offers


static func offer(id: String) -> Dictionary:
	for o in offers():
		if str(o.id) == id:
			return o
	return {}


## Bought for good: off the stall. Never true for an endless offer (an old save may
## still list one in gear_fits).
static func bought(id: String) -> bool:
	return WorldState.gear_fits.has(id) and not bool(offer(id).get("endless", false))


## The offers on the stall now: not bought yet, and their conditions hold.
static func open_offers() -> Array:
	return offers().filter(func(o): return not bought(str(o.id)) \
		and WorldState._conditions_hold(o.get("requires", {}), "stranger"))


## Offers not on sale yet but shown with their "locked" hint: not bought, and
## their conditions do not hold.
static func locked_offers() -> Array:
	return offers().filter(func(o): return o.has("locked") and not bought(str(o.id)) \
		and not WorldState._conditions_hold(o.get("requires", {}), "stranger"))


## Pay for an offer: an upgrade goes on, an item goes in your pockets. Returns
## "bought", "cant_afford", "full" (no backpack slot for the item) or "" (not on offer).
static func buy(id: String) -> String:
	var o := offer(id)
	if o.is_empty() or not open_offers().has(o):
		return ""
	if WorldState.credits < int(o.get("price", 0)):
		return "cant_afford"
	if o.has("item") and not WorldState.inventory.room_for(str(o.item)):
		return "full"
	WorldState.credits -= int(o.get("price", 0))
	if not bool(o.get("endless", false)):
		WorldState.gear_fits.append(id)
	if o.has("item"):
		WorldState.inventory.add(str(o.item))
	WorldState.log_event("Bought %s from the fence." % str(o.get("label", id)).to_lower(), "market")
	return "bought"


## A copy of `cfg` (the data of `target`: a weapon id, or an item id) with every
## upgrade bought for it on.
static func apply(cfg: Dictionary, target: String) -> Dictionary:
	var out := cfg
	for o in offers():
		if str(o.get("target", "")) != target or not bought(str(o.id)):
			continue
		if out == cfg:
			out = cfg.duplicate(true)
		var mult: Dictionary = o.get("mult", {})
		for path in mult:
			var keys := str(path).split(".")
			var d: Dictionary = out
			for k in keys.slice(0, keys.size() - 1):
				d = d.get(k, {})
			var last := keys[keys.size() - 1]
			if d.has(last):
				d[last] = float(d[last]) * float(mult[path])
	return out


## "Pistol: hair trigger, ..." for the log and F1 ("" with none).
static func owned_line() -> String:
	var names: Array = offers().filter(func(o): return o.has("target") and bought(str(o.id))) \
		.map(func(o): return str(o.label))
	return ", ".join(PackedStringArray(names))
