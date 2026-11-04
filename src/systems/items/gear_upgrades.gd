class_name GearUpgrades
extends RefCounted
## What the market stalls sell from a menu (issues #208, #209): the gear trader's
## one-time upgrades for the pistol, the rifle and the jetpack and his sniper rifle,
## and the fence's quantonium armour once the first bounty is paid. Pure and
## static; what is bought lives in WorldState.gear_fits (saved): [offer id, ...].
##
## Each offer is data in a vendor's "offers" (content/core/vendors/gear_trader.json,
## fence.json; VENDOR_PATHS), tagged here with the vendor's "vendor" id and "seller" label:
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
const TRADER_PATH := "res://content/core/vendors/gear_trader.json"
const VENDOR_PATHS := [TRADER_PATH, FENCE_PATH]   ## the stalls with offers; ids are unique across them

static var _offers: Array = []


## Every stall's offers, each tagged with its "vendor" id and "seller" label.
static func offers() -> Array:
	if _offers.is_empty():
		for path in VENDOR_PATHS:
			var f := FileAccess.open(path, FileAccess.READ)
			var d = JSON.parse_string(f.get_as_text()) if f != null else null
			if not d is Dictionary:
				continue
			for o in d.get("offers", []):
				o["vendor"] = str(d.get("id", ""))
				o["seller"] = str(d.get("label", "")).to_lower()
				_offers.append(o)
	return _offers


## Whether offer `o` is on vendor `vendor`'s stall ("" = any stall).
static func _sold_by(o: Dictionary, vendor: String) -> bool:
	return vendor == "" or str(o.get("vendor", "")) == vendor


static func offer(id: String) -> Dictionary:
	for o in offers():
		if str(o.id) == id:
			return o
	return {}


## Bought for good: off the stall. Never true for an endless offer (an old save may
## still list one in gear_fits).
static func bought(id: String) -> bool:
	return WorldState.gear_fits.has(id) and not bool(offer(id).get("endless", false))


## The offers on vendor `vendor`'s stall now ("" = every stall): not bought yet,
## and their conditions hold.
static func open_offers(vendor: String = "") -> Array:
	return offers().filter(func(o): return _sold_by(o, vendor) and not bought(str(o.id)) \
		and WorldState._conditions_hold(o.get("requires", {}), "stranger"))


## Offers not on sale yet but shown with their "locked" hint: not bought, and
## their conditions do not hold ("" = every stall).
static func locked_offers(vendor: String = "") -> Array:
	return offers().filter(func(o): return _sold_by(o, vendor) and o.has("locked") and not bought(str(o.id)) \
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
	WorldState.log_event("Bought %s from the %s." % [str(o.get("label", id)).to_lower(), str(o.get("seller", "market"))], "market")
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
