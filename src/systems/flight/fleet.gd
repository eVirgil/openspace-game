class_name Fleet
extends RefCounted
## The ships you own (issue #368). Pure and static, like ShipUpgrades; what is
## true lives in WorldState (saved):
##   - "wreck": the wreck T-89 rebuilt (WorldState.SHIP_REBUILT + wreck_ship),
##   - "t89":   the ship he sold you (WorldState.hangar),
##   - "kept_N": a stolen ship Skrugs cleaned up for you (WorldState.kept_ships).
##   - "free":  a free roam game's own interceptor, the pit pad's ship, yours from
##              the start (WorldState.FREE_SHIP; its ship id is the story data's
##              "free_roam_ship"), so Call brings it in free roam too.
## Each is known by that key. One is the primary (WorldState.primary_ship): it waits
## on the pit pad wherever you wake (ShipPilot.woke_in_pit) and it is the one Call
## brings to you (ShipPilot.call_ship). The others stay where you last left them,
## planet and spot (WorldState.ship_spots), across saves.
##
## A primary shot to pieces is not lost: it is back on the pad the next time you
## wake (or load), and T-89's repair fee comes out of your credits (repair()).

const WRECK := "wreck"
const T89 := "t89"
const FREE := "free"
const WRECKED := "primary_wrecked"         ## the flag: the primary was shot to pieces, not yet repaired


## Every ship you own, in order: [{ key, ship }].
static func owned() -> Array:
	var out: Array = []
	if WorldState.has_flag(WorldState.FREE_SHIP) and not WorldState.story_mode() and free_ship() != "":
		out.append({ "key": FREE, "ship": free_ship() })
	if WorldState.has_flag(WorldState.SHIP_REBUILT) and WorldState.wreck_ship != "":
		out.append({ "key": WRECK, "ship": WorldState.wreck_ship })
	if WorldState.hangar != "":
		out.append({ "key": T89, "ship": WorldState.hangar })
	for k in WorldState.kept_ships:
		out.append({ "key": str(k.get("key", "")), "ship": str(k.get("ship", "")) })
	return out


## The ship id of a free roam game's own interceptor.
static func free_ship() -> String:
	return str(Story.data().get("free_roam_ship", ""))


static func owns(key: String) -> bool:
	return key != "" and owned().any(func(e): return str(e.key) == key)


## The ship id behind `key` ("" = not one of yours).
static func ship_of(key: String) -> String:
	for e in owned():
		if str(e.key) == key:
			return str(e.ship)
	return ""


## The primary's key, "" when you own nothing. The first ship you get becomes it on
## its own, and so does the next one when it goes.
static func primary() -> String:
	if not owns(WorldState.primary_ship):
		var all := owned()
		WorldState.primary_ship = str(all[0].key) if not all.is_empty() else ""
	return WorldState.primary_ship


static func set_primary(key: String) -> bool:
	if not owns(key):
		return false
	WorldState.primary_ship = key
	return true


## Whether the primary waits on the pit pad. Not in a story save before T-89 rebuilt
## the wreck: the pad is the wreck's until then (issue #206).
static func goes_to_pit() -> bool:
	return primary() != "" and not (WorldState.story_mode() and not WorldState.has_flag(WorldState.SHIP_REBUILT))


## The ship on the pit pad when the town is built: the one you flew in on, else the
## primary (when it goes there), else the pad's own (`pad_ship`).
static func pit_ship(pad_ship: String, ships: Dictionary) -> String:
	if GameFlow.flown_ship != "" and ships.has(GameFlow.flown_ship):
		return GameFlow.flown_ship
	if goes_to_pit() and ships.has(ship_of(primary())):
		return ship_of(primary())
	return pad_ship


## Its key ("" = the pad's own, nobody's).
static func pit_key() -> String:
	if GameFlow.flown_ship != "":
		return GameFlow.flown_key if owns(GameFlow.flown_key) else ""
	return primary() if goes_to_pit() else ""


## A stolen ship is yours now (Skrugs cleaned it up). Returns its key.
static func keep(ship_id: String) -> String:
	var n := int(WorldState.counters.get("ships_kept", 0)) + 1
	WorldState.counters["ships_kept"] = n
	var key := "kept_%d" % n
	WorldState.kept_ships.append({ "key": key, "ship": ship_id })
	primary()
	return key


## `key` is gone for good: sold, or shot to pieces when it was not the primary.
static func lose(key: String) -> void:
	match key:
		FREE:
			WorldState.set_flag(WorldState.FREE_SHIP, false)
			WorldState.set_flag(WorldState.FREE_SHIP_GONE)
		WRECK:
			WorldState.wreck_ship = ""
		T89:
			WorldState.hangar = ""
		_:
			WorldState.kept_ships = WorldState.kept_ships.filter(func(k): return str(k.get("key", "")) != key)
	WorldState.ship_spots.erase(key)
	if WorldState.primary_ship == key:
		WorldState.primary_ship = ""
		primary()


# ------------------------------------------------------------------ where they are

## Where `key` was last left: { planet, pos: [x, y, z], rot: [x, y, z, w] }, or {}.
static func spot(key: String) -> Dictionary:
	return WorldState.ship_spots.get(key, {})


static func remember(key: String, xf: Transform3D) -> void:
	if not owns(key):
		return
	var q := xf.basis.orthonormalized().get_rotation_quaternion()
	WorldState.ship_spots[key] = { "planet": GameFlow.current_planet_id(),
		"pos": [xf.origin.x, xf.origin.y, xf.origin.z], "rot": [q.x, q.y, q.z, q.w] }


## A spot's transform (the ship's own, as it stood).
static func spot_xf(s: Dictionary) -> Transform3D:
	var p = s.get("pos", [0, 0, 0])
	var r = s.get("rot", [0, 0, 0, 1])
	var q := Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()
	return Transform3D(Basis(q), Vector3(float(p[0]), float(p[1]), float(p[2])))


# ------------------------------------------------------------------ repairs

## T-89's fee for patching the primary up: repair_rate times its list price.
static func repair_fee(ship_id: String) -> int:
	var c := ShipSalesman.config()
	return int(round(ShipSalesman.list_price(ship_id) * float(c.get("repair_rate", 0.2))))


## The primary was shot to pieces and is back: the fee is paid (what you have, if
## that is less). Returns what was taken, -1 when nothing needed repairing.
static func repair() -> int:
	if not WorldState.has_flag(WRECKED):
		return -1
	WorldState.set_flag(WRECKED, false)
	var fee := mini(repair_fee(ship_of(primary())), maxi(WorldState.credits, 0))
	WorldState.credits -= fee
	WorldState.log_event("T-89 patched up a ship that was shot to pieces.")
	return fee


# ------------------------------------------------------------------ the ledger

## One row per ship for the inventory: { key, ship, label, fits, planet, primary, wrecked }.
static func rows() -> Array:
	var out: Array = []
	var p := primary()
	for e in owned():
		var key := str(e.key)
		var sid := str(e.ship)
		var fits: Array = ShipUpgrades.fitted(sid).map(func(id): return ShipUpgrades.label(id).to_lower())
		out.append({ "key": key, "ship": sid, "label": ShipUpgrades.ship_label(sid),
			"fits": ", ".join(PackedStringArray(fits)), "planet": str(spot(key).get("planet", "")),
			"primary": key == p, "wrecked": key == p and WorldState.has_flag(WRECKED) })
	return out
