class_name DroidRoster
extends RefCounted
## Companion droids (issue #51). Pure and headless-testable: which droids the
## player runs (up to max_owned), what each cargo droid carries, which broken
## droids are lying out in the desert, and the range remote's taming streak.
##
## It never touches nodes. Money comes back as numbers; the caller (DroidController)
## moves the credits in WorldState. Kinds, variants and prices come from
## content/core/droids/droids.json.
##
## Lives in WorldState.droids, so it survives town -> flight -> town and is saved
## with the rest of the world. A droid's cargo is NOT in WorldState.inventory:
## that is the point. The gate searches the inventory, never the droid.
##
## Upgrades: the droid merchant fits each droid with more health, a bigger hold
## (a cargo droid starts with cargo_slots kinds of item) or a harder-hitting gun
## (droids.json "upgrades"). Levels live on the droid ("up") and go with it.
## A droid of yours wears its kind's base_variant until its first upgrade, then
## the shiny upgraded_variant (look_variant).

const DATA := "res://content/core/droids/droids.json"

static var _cfg: Dictionary = {}

var owned: Array = []       ## [{ uid, kind, variant, cargo: { item id -> count }, up: { upgrade -> level }, lasers_on? }]
var wrecks: Array = []      ## [{ uid, kind, variant, pos: [x, y, z] }]
var wrecks_seeded := false  ## the home ball's starting field is generated once and saved
var streak := 0             ## range remote bolts blocked in a row
var next_uid := 1


static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_cfg = d
	return _cfg


static func kind_cfg(kind: String) -> Dictionary:
	return (config().get("kinds", {}) as Dictionary).get(kind, {})


static func variant_cfg(kind: String, variant: String) -> Dictionary:
	var vs: Dictionary = kind_cfg(kind).get("variants", {})
	if vs.has(variant):
		return vs[variant]
	return vs.values()[0] if not vs.is_empty() else {}


static func label(kind: String) -> String:
	return str(kind_cfg(kind).get("label", kind))


static func price(kind: String) -> int:
	return int(kind_cfg(kind).get("price", 0))


static func resale(kind: String) -> int:
	return int(kind_cfg(kind).get("resale", 0))


static func max_owned() -> int:
	return int(config().get("max_owned", 3))


## A random look for a droid the player gets (never the Remnant's colours).
static func pick_variant(kind: String, rng: RandomNumberGenerator) -> String:
	var vs: Array = (config().get("player_variants", {}) as Dictionary).get(kind, [])
	if vs.is_empty():
		vs = (kind_cfg(kind).get("variants", {}) as Dictionary).keys()
	return str(vs[rng.randi() % vs.size()]) if not vs.is_empty() else ""


## How droid `d` of yours looks: its kind's base_variant, or once it has any
## upgrade, the upgraded_variant. Falls back to its own variant.
## Issue #392: an upgrade with its own look (the laser rig's "variant") wins.
static func look_variant(d: Dictionary) -> String:
	var kc := kind_cfg(str(d.get("kind", "")))
	var upgraded := false
	for key in (d.get("up", {}) as Dictionary):
		if int(d.up[key]) > 0 and upgrade_cfg(str(key)).has("variant"):
			return str(upgrade_cfg(str(key)).variant)
		upgraded = upgraded or int(d.up[key]) > 0
	return str(kc.get("upgraded_variant" if upgraded else "base_variant", d.get("variant", "")))


# ---- owning -------------------------------------------------------------------

func is_full() -> bool:
	return owned.size() >= max_owned()


func find(uid: int) -> Dictionary:
	for d in owned:
		if int(d.uid) == uid:
			return d
	return {}


## Take on a droid. Returns its entry, or {} when the roster is full or the kind
## is unknown.
func add(kind: String, variant: String) -> Dictionary:
	if is_full() or kind_cfg(kind).is_empty():
		return {}
	var d := { "uid": next_uid, "kind": kind, "variant": variant, "cargo": {}, "up": {} }
	d.variant = look_variant(d)          # yours start in the kind's base look
	next_uid += 1
	owned.append(d)
	return d


## Let a droid go. Its cargo goes with it. Returns false if it was not ours.
func remove(uid: int) -> bool:
	var d := find(uid)
	if d.is_empty():
		return false
	owned.erase(d)
	return true


# ---- trade ----------------------------------------------------------------------

## Buy a droid of `kind` with `credits` available. Returns { cost, droid }, or
## { error: "full" | "cant_afford" | "unknown" }.
## `cost`: what this stall asks (issue #303: friends pay less), -1 = the list price.
func buy(kind: String, variant: String, credits: int, cost: int = -1) -> Dictionary:
	if kind_cfg(kind).is_empty():
		return { "error": "unknown" }
	if is_full():
		return { "error": "full" }
	var pay := price(kind) if cost < 0 else cost
	if pay > credits:
		return { "error": "cant_afford" }
	return { "cost": pay, "droid": add(kind, variant) }


## Sell a droid back to the merchant. Returns the credits paid, or -1.
func sell(uid: int) -> int:
	var d := find(uid)
	if d.is_empty():
		return -1
	remove(uid)
	return resale(str(d.kind))


# ---- upgrades ---------------------------------------------------------------------

static func upgrade_cfg(key: String) -> Dictionary:
	return (config().get("upgrades", {}) as Dictionary).get(key, {})


static func upgrade_label(key: String) -> String:
	return str(upgrade_cfg(key).get("label", key))


static func upgrade_max(key: String) -> int:
	return (upgrade_cfg(key).get("prices", []) as Array).size()


## The upgrades a kind can take: health for all, cargo for a droid that carries,
## damage for one with a gun. `at` (issue #392): a merchant that sells its own
## ("sold_at", the moon rave's laser rig) offers only those; every other merchant
## ("") offers the rest.
static func upgrades_for(kind: String, at := "") -> Array:
	var out: Array = []
	for key in (config().get("upgrades", {}) as Dictionary):
		if str(key) != "note" and str(upgrade_cfg(str(key)).get("sold_at", "")) == at and fits(kind, str(key)):
			out.append(key)
	return out


## Whether a droid of `kind` can take upgrade `key` at all, wherever it is sold.
static func fits(kind: String, key: String) -> bool:
	var kc := kind_cfg(kind)
	var uc := upgrade_cfg(key)
	if uc.is_empty() or key == "note":
		return false
	if uc.has("kinds"):
		return (uc.kinds as Array).has(kind)
	match key:
		"cargo":
			return bool(kc.get("carries", false))
		"damage":
			return kc.has("gun")
	return true


## Capped at the levels on sale: a save from when there were more has them all.
static func level(d: Dictionary, key: String) -> int:
	return mini(int((d.get("up", {}) as Dictionary).get(key, 0)), upgrade_max(key))


## What the next level of `key` costs this droid, or -1 (maxed, or not for its kind).
static func upgrade_price(d: Dictionary, key: String) -> int:
	if not fits(str(d.get("kind", "")), key):
		return -1
	var prices: Array = upgrade_cfg(key).get("prices", [])
	var lv := level(d, key)
	return int(prices[lv]) if lv < prices.size() else -1


## Hit points: its kind's "hp", plus "per_level" of that for each health level.
static func health(d: Dictionary) -> float:
	var base := float(kind_cfg(str(d.get("kind", ""))).get("hp", 60.0))
	return base * (1.0 + float(upgrade_cfg("health").get("per_level", 0.5)) * level(d, "health"))


## Its gun's damage, times this.
static func damage_mult(d: Dictionary) -> float:
	return 1.0 + float(upgrade_cfg("damage").get("per_level", 0.35)) * level(d, "damage")


## How many kinds of item its hold takes (0 for a droid that does not carry).
static func cargo_slots(d: Dictionary) -> int:
	var kc := kind_cfg(str(d.get("kind", "")))
	if not bool(kc.get("carries", false)):
		return 0
	return int(kc.get("cargo_slots", 2)) + int(upgrade_cfg("cargo").get("per_level", 2)) * level(d, "cargo")


## Pay for the next level of `key` on droid `uid` with `credits` available.
## Returns { cost, level }, or { error: "unknown" | "maxed" | "cant_afford" }.
func upgrade(uid: int, key: String, credits: int) -> Dictionary:
	var d := find(uid)
	if d.is_empty() or not fits(str(d.kind), key):
		return { "error": "unknown" }
	var cost := upgrade_price(d, key)
	if cost < 0:
		return { "error": "maxed" }
	if cost > credits:
		return { "error": "cant_afford" }
	if not d.has("up"):
		d["up"] = {}
	d.up[key] = level(d, key) + 1
	d.variant = look_variant(d)          # any upgrade: the shiny look
	if key == "lasers":
		d["lasers_on"] = false           # issue #392: a new rig is dark until E beside it
	return { "cost": cost, "level": int(d.up[key]) }


# ---- the laser rig (issue #392) ---------------------------------------------------------

## Droid `d` wears the laser rig.
static func has_lasers(d: Dictionary) -> bool:
	return level(d, "lasers") > 0


## Its lasers are on (E beside it; a new rig is dark).
static func lasers_on(d: Dictionary) -> bool:
	return has_lasers(d) and bool(d.get("lasers_on", false))


## Turn droid `uid`'s lasers on or off. Returns the new state (false with no rig).
func set_lasers(uid: int, on: bool) -> bool:
	var d := find(uid)
	if d.is_empty() or not has_lasers(d):
		return false
	d["lasers_on"] = on
	return on


# ---- cargo ----------------------------------------------------------------------

## Room in droid `d`'s hold for `item_id`: it stacks, or a slot is free.
static func hold_has_room(d: Dictionary, item_id: String) -> bool:
	var cargo: Dictionary = d.get("cargo", {})
	return cargo.has(item_id) or cargo.size() < cargo_slots(d)


## Move n of an item from the player's pockets into a cargo droid. Worn gear comes
## off first. Returns false if the droid cannot carry, its hold has no slot for
## another kind, or the pockets are short.
func stash(uid: int, inv: Inventory, item_id: String, n: int = 1) -> bool:
	var d := find(uid)
	if d.is_empty() or not bool(kind_cfg(str(d.kind)).get("carries", false)):
		return false
	if not hold_has_room(d, item_id):
		return false
	if not inv.remove(item_id, n):
		return false
	d.cargo[item_id] = int(d.cargo.get(item_id, 0)) + n
	return true


## What a cargo droid holds back into the pockets, as much as the backpack has
## room for (the rest stays in the hold). Returns how many items moved.
func unload(uid: int, inv: Inventory) -> int:
	var d := find(uid)
	if d.is_empty():
		return 0
	var moved := 0
	for id in d.cargo.keys():
		if not inv.room_for(str(id)):
			continue
		inv.add(str(id), int(d.cargo[id]))
		moved += int(d.cargo[id])
		d.cargo.erase(id)
	return moved


## Everything in droid `uid`'s hold would fit in the backpack.
func cargo_fits(uid: int, inv: Inventory) -> bool:
	return inv.room_for_all(find(uid).get("cargo", {}))


## Every item every droid is carrying: item id -> count.
func all_cargo() -> Dictionary:
	var out := {}
	for d in owned:
		for id in d.cargo:
			out[id] = int(out.get(id, 0)) + int(d.cargo[id])
	return out


# ---- taming ---------------------------------------------------------------------

## A range remote bolt was blocked or deflected. Returns true when that makes the
## streak (taming.streak in a row).
func on_remote_blocked() -> bool:
	streak += 1
	return streak >= int(config().get("taming", {}).get("streak", 5))


func on_remote_hit_player() -> void:
	streak = 0


# ---- wrecks ---------------------------------------------------------------------

func has_wreck_of(kind: String) -> bool:
	for w in wrecks:
		if str(w.kind) == kind:
			return true
	return false


func find_wreck(uid: int) -> Dictionary:
	for w in wrecks:
		if int(w.uid) == uid:
			return w
	return {}


## Maybe strand one more broken droid in the desert. Flat worlds keep the old ring
## around `center`; on the ball, map coordinates cover the whole sphere and
## `surface` returns the actual ground point. `clear` rejects landmarks, and
## sphere_center/radius make spacing geodesic instead of map-plane distance.
func roll_wreck(rng: RandomNumberGenerator, center: Vector3, ground: Callable = Callable(), force := false,
		surface: Callable = Callable(), sphere_center := Vector3.ZERO, sphere_radius := 0.0,
		spot_clear: Callable = Callable()) -> Dictionary:
	var wc: Dictionary = config().get("wrecks", {})
	var on_ball := sphere_radius > 0.0 and surface.is_valid()
	var max_out := int(wc.get("ball_max_out", 12)) if on_ball else int(wc.get("max_out", 3))
	if wrecks.size() >= max_out:
		return {}
	if not force and rng.randf() >= float(wc.get("chance", 0.4)):
		return {}
	var kinds: Array = []
	for k in (config().get("kinds", {}) as Dictionary):
		if on_ball or not has_wreck_of(str(k)):
			kinds.append(str(k))
	if kinds.is_empty():
		return {}
	var kind: String = kinds[rng.randi() % kinds.size()]
	var sep := float(wc.get("ball_min_separation", 500.0)) if on_ball else float(wc.get("min_separation", 180.0))
	for _try in (120 if on_ball else 24):
		var a := rng.randf() * TAU
		var p: Vector3
		if on_ball:
			# Uniform area over the sphere outside a generous keep-out around the port.
			var min_angle := float(wc.get("ball_min_radius", 900.0)) / sphere_radius
			var max_angle := PI - min_angle
			var theta := acos(rng.randf_range(cos(max_angle), cos(min_angle)))
			var map_radius := theta * sphere_radius
			var x := center.x + cos(a) * map_radius
			var z := center.z + sin(a) * map_radius
			p = surface.call(x, z)
		else:
			var r := rng.randf_range(float(wc.get("min_radius", 160.0)), float(wc.get("max_radius", 520.0)))
			p = center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var clear := true
		for w in wrecks:
			var old := Vector3(float(w.pos[0]), float(w.pos[1]), float(w.pos[2]))
			var apart: float
			if on_ball:
				var d1 := (p - sphere_center).normalized()
				var d2 := (old - sphere_center).normalized()
				apart = acos(clampf(d1.dot(d2), -1.0, 1.0)) * sphere_radius
			else:
				apart = Vector2(p.x - old.x, p.z - old.z).length()
			if apart < sep:
				clear = false
				break
		if not clear:
			continue
		if on_ball and spot_clear.is_valid() and not bool(spot_clear.call(p)):
			continue
		if not on_ball and ground.is_valid():
			p.y = float(ground.call(p.x, p.z))
		var w := { "uid": next_uid, "kind": kind, "variant": pick_variant(kind, rng), "pos": [p.x, p.y, p.z] }
		next_uid += 1
		wrecks.append(w)
		return w
	return {}


## Issue #76: a wreck at a given spot (an outpost's cargo droid that ran off and
## broke down out there), whatever the random field holds.
func add_wreck(kind: String, variant: String, at: Vector3) -> Dictionary:
	var w := { "uid": next_uid, "kind": kind, "variant": variant, "pos": [at.x, at.y, at.z] }
	next_uid += 1
	wrecks.append(w)
	return w


## A fixed wreck resets and joins the roster. Returns the new droid, or {} when
## the roster is full (the wreck stays where it is).
func fix_wreck(uid: int) -> Dictionary:
	var w := find_wreck(uid)
	if w.is_empty() or is_full():
		return {}
	wrecks.erase(w)
	return add(str(w.kind), str(w.variant))


# ---- save -----------------------------------------------------------------------

func to_save() -> Dictionary:
	return { "owned": owned.duplicate(true), "wrecks": wrecks.duplicate(true), "wrecks_seeded": wrecks_seeded,
		"streak": streak, "next_uid": next_uid }


func from_save(d: Dictionary) -> void:
	owned = []
	for o in d.get("owned", []):
		if not kind_cfg(str(o.get("kind", ""))).is_empty() and owned.size() < max_owned():
			var up := {}
			for key in (o.get("up", {}) as Dictionary):
				up[str(key)] = int(o.up[key])
			var mine := { "uid": int(o.uid), "kind": str(o.kind), "variant": str(o.get("variant", "")),
				"cargo": (o.get("cargo", {}) as Dictionary).duplicate(), "up": up }
			if o.has("lasers_on"):
				mine["lasers_on"] = bool(o.lasers_on)
			mine.variant = look_variant(mine)    # older saves: the random look becomes the base one
			owned.append(mine)
	wrecks = []
	for w in d.get("wrecks", []):
		wrecks.append({ "uid": int(w.uid), "kind": str(w.kind), "variant": str(w.get("variant", "")),
			"pos": (w.get("pos", [0, 0, 0]) as Array).duplicate() })
	streak = int(d.get("streak", 0))
	wrecks_seeded = bool(d.get("wrecks_seeded", false))
	next_uid = int(d.get("next_uid", 1))
	for o in owned + wrecks:
		next_uid = maxi(next_uid, int(o.uid) + 1)
