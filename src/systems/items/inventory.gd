class_name Inventory
extends RefCounted
## The player's gear (M13). Pure and headless-testable: what the player owns, what
## is attached in each body slot, which pickups in the world are already taken, and
## what each vendor holds after the player has traded with them.
##
## It never touches money or nodes. Prices come back as numbers; the caller
## (GearController) moves the credits in WorldState and updates the world. Item,
## vendor and pickup facts come from content/core (items/, vendors/, pickups/), so a
## new item is a JSON file, not code.
##
## Lives in WorldState.inventory, so it survives town -> flight -> town and is saved
## with the rest of the world.
##
## The backpack: what you carry fills a few slots (content/core/flow/gear.json
## "backpack"). The pistol always holds the first; every other kind you own takes
## one (a stack is one slot), except what is activated (worn: the jetpack on your
## back, the armour on), which rides on the body instead. Owning more than fits
## is possible (a story gift), but the ways you pick things up ask room_for first.

const GEAR_PATH := "res://content/core/flow/gear.json"

static var _pack_cfg: Dictionary = {}

var owned: Dictionary = {}      ## item id -> count
var attached: Dictionary = {}   ## slot -> item id ("back" -> "jetpack")
var taken: Dictionary = {}      ## pickup id -> true
var stock: Dictionary = {}      ## vendor id -> Array of item ids (once traded with)


# ---- owning -------------------------------------------------------------------

func count(id: String) -> int:
	return int(owned.get(id, 0))


func has(id: String) -> bool:
	return count(id) > 0


func add(id: String, n: int = 1) -> void:
	owned[id] = count(id) + n


## Remove n of an item. Returns false (and changes nothing) when there are fewer.
## Removing the last one also takes it off the body.
func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	owned[id] = count(id) - n
	if owned[id] <= 0:
		owned.erase(id)
		detach(id)
	return true


func item_ids() -> Array:
	var ids := owned.keys()
	ids.sort()
	return ids


# ---- the backpack ------------------------------------------------------------------

static func backpack_cfg() -> Dictionary:
	if _pack_cfg.is_empty():
		var f := FileAccess.open(GEAR_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_pack_cfg = d.get("backpack", {}) if d is Dictionary else {}
	return _pack_cfg


static func backpack_slots() -> int:
	return int(backpack_cfg().get("slots", 5))


## What always holds the first slots (the pistol), by label.
static func fixed_slots() -> Array:
	return backpack_cfg().get("fixed", ["Pistol"])


## "Your backpack is full (5 of 5 slots)."
static func full_line() -> String:
	return str(backpack_cfg().get("full", "Your backpack is full (%d of %d slots).")) % [backpack_slots(), backpack_slots()]


## The kinds in the backpack, in order: everything owned that is not activated.
func packed_ids() -> Array:
	return item_ids().filter(func(id): return not is_attached(str(id)))


func slots_used() -> int:
	return fixed_slots().size() + packed_ids().size()


func slots_free() -> int:
	return maxi(0, backpack_slots() - slots_used())


## Room for one more `id`: it stacks on what you have, a slot is free, or (given
## its item data) it goes straight onto a free body slot (the caller wears it).
func room_for(id: String, item_cfg: Dictionary = {}) -> bool:
	if has(id) or slots_free() > 0:
		return true
	var slot := str(item_cfg.get("slot", ""))
	return slot != "" and in_slot(slot) == ""


## Room for all of `items` (item id -> count) at once.
func room_for_all(items: Dictionary) -> bool:
	var new_kinds := 0
	for id in items:
		if not has(str(id)) and int(items[id]) > 0:
			new_kinds += 1
	return new_kinds <= slots_free()


## Room for `id` once `paid` x `paid_id` has gone (a trade: the last of what you
## pay with frees its slot).
func room_after_paying(id: String, paid_id: String, paid: int) -> bool:
	return room_for(id) or (paid_id != id and count(paid_id) == paid)


# ---- attaching ------------------------------------------------------------------

## Put an owned item in its body slot (from the item's "slot"). Whatever was in that
## slot comes off. Returns false for items you do not own or that have no slot.
func attach(id: String, item_cfg: Dictionary) -> bool:
	var slot := str(item_cfg.get("slot", ""))
	if slot == "" or not has(id):
		return false
	attached[slot] = id
	return true


## Take an item off the body. It stays owned. Returns false if it was not attached.
func detach(id: String) -> bool:
	for slot in attached.keys():
		if attached[slot] == id:
			attached.erase(slot)
			return true
	return false


func is_attached(id: String) -> bool:
	return attached.values().has(id)


func in_slot(slot: String) -> String:
	return str(attached.get(slot, ""))


# ---- pickups --------------------------------------------------------------------

func is_taken(pickup_id: String) -> bool:
	return taken.has(pickup_id)


## Take a pickup placed in the world. Returns false if it was already taken.
func pick_up(pickup: Dictionary) -> bool:
	var pid := str(pickup.get("id", ""))
	if pid == "" or is_taken(pid):
		return false
	taken[pid] = true
	add(str(pickup.get("item", "")), maxi(1, int(pickup.get("count", 1))))
	return true


# ---- trade ----------------------------------------------------------------------

## What a vendor has for sale: its data stock until the player trades with it, then
## whatever trading left there. A vendor with "resells": false (the fences, which pay
## more than they would ask) never sells on what it bought. What it has in
## "endless_stock" (the gear trader's jetpacks) is always there, whatever trading did.
func vendor_stock(vendor_cfg: Dictionary) -> Array:
	var vid := str(vendor_cfg.get("id", ""))
	var s: Array
	if stock.has(vid) and bool(vendor_cfg.get("resells", true)):
		s = (stock[vid] as Array).duplicate()
	else:
		s = (vendor_cfg.get("stock", []) as Array).duplicate()
	for id in vendor_cfg.get("endless_stock", []):
		if not s.has(id):
			s.append(id)
	return s


## The vendor never runs out of `id`: the whole stall is "endless" (the food stall,
## issue #96) or `id` is in its "endless_stock".
static func sells_endlessly(id: String, vendor_cfg: Dictionary) -> bool:
	return bool(vendor_cfg.get("endless", false)) or (vendor_cfg.get("endless_stock", []) as Array).has(id)


## Credits a vendor pays for an item, or -1 if it does not buy that kind. "*" in
## "buys" = any kind at all (the fences), the kinds it does not name at "any_rate".
static func sell_price(item_cfg: Dictionary, vendor_cfg: Dictionary) -> int:
	var kinds: Array = vendor_cfg.get("buys", [])
	var rate := float(vendor_cfg.get("buy_rate", 0.5))
	if not kinds.has(str(item_cfg.get("kind", ""))):
		if not kinds.has("*"):
			return -1
		rate = float(vendor_cfg.get("any_rate", rate))
	if bool(item_cfg.get("contraband", false)):
		rate *= Territory.fence_mult()     # issue #187: the locals' outposts open the fence's routes
	return int(round(float(item_cfg.get("value", 0)) * rate))


## Credits a vendor asks for an item: its own price for it ("prices": { item id:
## credits }) if it names one, else the item's value at its sell_rate.
static func buy_price(item_cfg: Dictionary, vendor_cfg: Dictionary) -> int:
	var own = vendor_cfg.get("prices", {}).get(str(item_cfg.get("id", "")), null)
	if own != null:
		return int(own)
	return int(round(float(item_cfg.get("value", 0)) * float(vendor_cfg.get("sell_rate", 1.0))))


## Sell one of an item. Returns the credits earned, or -1 when you do not own it or
## the vendor does not buy it. The vendor stocks what it bought (unless "resells": false).
func sell(id: String, item_cfg: Dictionary, vendor_cfg: Dictionary) -> int:
	var price := sell_price(item_cfg, vendor_cfg)
	if price < 0 or not has(id):
		return -1
	remove(id)
	if bool(vendor_cfg.get("resells", true)) and not sells_endlessly(id, vendor_cfg):
		var s := vendor_stock(vendor_cfg)
		s.append(id)
		stock[str(vendor_cfg.get("id", ""))] = s
	return price


## Buy one of an item with `credits` available. Returns the cost, or -1 when the
## vendor does not have it or you cannot afford it.
func buy(id: String, item_cfg: Dictionary, vendor_cfg: Dictionary, credits: int) -> int:
	var s := vendor_stock(vendor_cfg)
	var cost := buy_price(item_cfg, vendor_cfg)
	if not s.has(id) or cost > credits:
		return -1
	if not sells_endlessly(id, vendor_cfg):     # issue #96: the food stall never runs out
		s.erase(id)
		stock[str(vendor_cfg.get("id", ""))] = s
	add(id)
	return cost


# ---- save -------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"owned": owned.duplicate(),
		"attached": attached.duplicate(),
		"taken": taken.keys(),
		"stock": stock.duplicate(true),
	}


func from_save(d: Dictionary) -> void:
	owned = {}
	for k in (d.get("owned", {}) as Dictionary):
		var n := int(d.owned[k])
		if n > 0:
			owned[str(k)] = n
	attached = {}
	for slot in (d.get("attached", {}) as Dictionary):
		var id := str(d.attached[slot])
		if has(id):                      # never wear something you do not own
			attached[str(slot)] = id
	taken = {}
	for pid in d.get("taken", []):
		taken[str(pid)] = true
	stock = {}
	var st: Dictionary = d.get("stock", {})
	for vid in st:
		stock[str(vid)] = (st[vid] as Array).duplicate()
