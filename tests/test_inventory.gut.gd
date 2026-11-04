extends GutTest
## M13: the inventory and trade rules, and the gear data. Owning, attaching to a
## slot, picking up once, selling at the vendor's rate, buying back from what it
## holds, saving with the world, and every reference between items, vendors,
## pickups, looks and town markers resolving. The last test adds a new item and
## vendor from JSON alone and trades with them.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const Jetpack := preload("res://src/systems/player/jetpack.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")

var content
var jet: Dictionary
var trader: Dictionary


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()
	jet = content.get_item("jetpack")
	trader = content.get_vendor("gear_trader")


# ---- data -------------------------------------------------------------------

func test_gear_content_loads_by_id() -> void:
	assert_eq(jet.get("id"), "jetpack")
	assert_eq(jet.get("slot"), "back", "the jetpack is worn on the back")
	assert_true(jet.has("jetpack"), "it carries jetpack tuning")
	assert_eq(trader.get("id"), "gear_trader")
	assert_eq(content.get_pickups("port_town").size(), 3, "the pit jetpack, (M15) the cache outside the gate and (#148) the wreck's red saber")
	assert_eq(content.vendors_in("port_town").size(), 2, "the gear trader and (M15) the fence")


func test_every_gear_reference_resolves() -> void:
	var looks: Dictionary = ItemKit.new().looks
	var town = TownLayout.new()
	assert_true(town.load_town("port_town"))
	for id in content.items:
		var it: Dictionary = content.get_item(id)
		assert_true(looks.has(str(it.get("look", id))), "%s look exists in items.json" % id)
		assert_gt(int(it.get("value", 0)), 0, "%s has a value" % id)
	for vid in content.vendors:
		var v: Dictionary = content.get_vendor(vid)
		assert_false(town.get_marker(str(v.marker)).is_empty(), "%s stands at a real marker" % vid)
	for loc in content.pickups:
		for p in content.get_pickups(loc):
			assert_false(content.get_item(str(p.item)).is_empty(), "%s item resolves" % p.id)
			assert_false(town.get_marker(str(p.marker)).is_empty(), "%s marker resolves" % p.id)


func test_gear_files_match_manifest() -> void:
	for cat in ["items", "vendors", "pickups"]:
		for id in content.manifest.get(cat, []):
			assert_true(FileAccess.file_exists("res://content/core/%s/%s.json" % [cat, id]),
				"%s file exists: %s" % [cat, id])


# ---- owning and attaching -----------------------------------------------------

func test_add_remove_and_counts() -> void:
	var inv := Inventory.new()
	assert_false(inv.has("jetpack"))
	inv.add("jetpack")
	assert_eq(inv.count("jetpack"), 1)
	assert_false(inv.remove("jetpack", 2), "cannot remove more than you have")
	assert_true(inv.remove("jetpack"))
	assert_false(inv.has("jetpack"))


func test_attach_needs_ownership_and_a_slot() -> void:
	var inv := Inventory.new()
	assert_false(inv.attach("jetpack", jet), "cannot wear what you do not own")
	inv.add("jetpack")
	assert_true(inv.attach("jetpack", jet))
	assert_eq(inv.in_slot("back"), "jetpack")
	assert_true(inv.is_attached("jetpack"))
	assert_false(inv.attach("jetpack", { "id": "jetpack" }), "an item with no slot cannot be worn")


func test_detach_keeps_the_item() -> void:
	var inv := Inventory.new()
	inv.add("jetpack")
	inv.attach("jetpack", jet)
	assert_true(inv.detach("jetpack"))
	assert_eq(inv.in_slot("back"), "")
	assert_true(inv.has("jetpack"), "taking it off does not drop it")
	assert_false(inv.detach("jetpack"), "already off")


func test_removing_the_last_one_takes_it_off() -> void:
	var inv := Inventory.new()
	inv.add("jetpack")
	inv.attach("jetpack", jet)
	inv.remove("jetpack")
	assert_eq(inv.in_slot("back"), "", "nothing left to wear")


# ---- pickups ------------------------------------------------------------------

func test_a_pickup_is_taken_once() -> void:
	var inv := Inventory.new()
	var p: Dictionary = content.get_pickups("port_town")[0]
	assert_true(inv.pick_up(p))
	assert_true(inv.has("jetpack"))
	assert_true(inv.is_taken(str(p.id)))
	assert_false(inv.pick_up(p), "the same pickup cannot be taken twice")
	assert_eq(inv.count("jetpack"), 1)


# ---- trade --------------------------------------------------------------------

func test_prices_come_from_value_and_rates() -> void:
	assert_eq(Inventory.sell_price(jet, trader), int(round(float(jet.value) * float(trader.buy_rate))))
	assert_eq(Inventory.buy_price(jet, trader), int(round(float(jet.value) * float(trader.sell_rate))))
	assert_eq(Inventory.sell_price({ "kind": "food", "value": 10 }, trader), -1, "the trader only buys gear")


func test_the_fences_buy_anything_you_have() -> void:
	for vid in ["fence", "station_fence"]:
		var fence: Dictionary = content.get_vendor(vid)
		for id in content.items:
			var it: Dictionary = content.get_item(str(id))
			assert_gte(Inventory.sell_price(it, fence), 0, "%s buys %s" % [vid, id])
		assert_eq(Inventory.sell_price(jet, fence), int(round(float(jet.value) * float(fence.any_rate))), "gear at any_rate")
		assert_lte(Inventory.sell_price(jet, fence), Inventory.sell_price(jet, trader), "no better than the gear trader")
		var cells: Dictionary = content.get_item("unmarked_cells")
		assert_gt(Inventory.sell_price(cells, fence), int(cells.value), "contraband still at its own, better rate")
	assert_eq(Inventory.sell_price({ "kind": "food", "value": 10 }, trader), -1, "other stalls still buy only their kinds")


## The trade rules on a gear stall without the gear trader's endless jetpacks.
func _plain_trader() -> Dictionary:
	var v := trader.duplicate(true)
	v.erase("endless_stock")
	return v


func test_sell_pays_and_stocks_the_vendor() -> void:
	var stall := _plain_trader()
	var inv := Inventory.new()
	inv.add("jetpack")
	inv.attach("jetpack", jet)
	var price := inv.sell("jetpack", jet, stall)
	assert_eq(price, Inventory.sell_price(jet, stall))
	assert_false(inv.has("jetpack"))
	assert_eq(inv.in_slot("back"), "", "selling the worn pack takes it off")
	assert_eq(inv.vendor_stock(stall), ["jetpack"], "the stall now holds it")
	assert_eq(inv.sell("jetpack", jet, stall), -1, "nothing left to sell")


func test_buy_back_needs_stock_and_credits() -> void:
	var stall := _plain_trader()
	var inv := Inventory.new()
	assert_eq(inv.buy("jetpack", jet, stall, 999), -1, "the stall starts with nothing to sell")
	inv.add("jetpack")
	inv.sell("jetpack", jet, stall)
	var cost := Inventory.buy_price(jet, stall)
	assert_eq(inv.buy("jetpack", jet, stall, cost - 1), -1, "cannot afford it")
	assert_eq(inv.buy("jetpack", jet, stall, cost), cost)
	assert_true(inv.has("jetpack"))
	assert_eq(inv.vendor_stock(stall), [], "it left the stall")


func test_gear_trader_always_sells_jetpacks() -> void:
	var inv := Inventory.new()
	assert_eq(inv.vendor_stock(trader), ["jetpack"], "a fresh game: the trader has jetpacks")
	var cost := Inventory.buy_price(jet, trader)
	assert_eq(cost, int(jet.value), "at the jetpack's value")
	assert_eq(inv.buy("jetpack", jet, trader, cost - 1), -1, "cannot afford it")
	assert_eq(inv.buy("jetpack", jet, trader, cost * 3), cost)
	assert_eq(inv.buy("jetpack", jet, trader, cost * 3), cost, "never runs out")
	assert_eq(inv.count("jetpack"), 2)
	assert_eq(inv.vendor_stock(trader), ["jetpack"], "still on the stall")
	assert_eq(inv.sell("jetpack", jet, trader), Inventory.sell_price(jet, trader), "it still buys them back")
	assert_eq(inv.vendor_stock(trader), ["jetpack"], "a sold jetpack does not pile up")


func test_old_saves_see_the_trader_jetpacks() -> void:
	var inv := Inventory.new()
	inv.from_save({ "stock": { "gear_trader": ["red_energy_saber"] } })
	var s := inv.vendor_stock(trader)
	assert_true(s.has("red_energy_saber"), "what was sold to it before stays")
	assert_true(s.has("jetpack"), "and the jetpacks are there too")
	assert_eq(inv.to_save().stock.gear_trader, ["red_energy_saber"], "the save is untouched")


# ---- save ---------------------------------------------------------------------

func test_inventory_save_round_trip() -> void:
	var inv := Inventory.new()
	inv.pick_up(content.get_pickups("port_town")[0])
	inv.attach("jetpack", jet)
	var other := Inventory.new()
	other.from_save(JSON.parse_string(JSON.stringify(inv.to_save())))
	assert_true(other.has("jetpack"))
	assert_eq(other.in_slot("back"), "jetpack")
	assert_true(other.is_taken("pit_jetpack"))


func test_a_save_cannot_wear_what_it_does_not_own() -> void:
	var inv := Inventory.new()
	inv.from_save({ "owned": {}, "attached": { "back": "jetpack" } })
	assert_eq(inv.in_slot("back"), "")


func test_world_state_saves_the_inventory() -> void:
	WorldState.reset()
	WorldState.inventory.add("jetpack")
	WorldState.inventory.attach("jetpack", jet)
	var saved := JSON.stringify(WorldState.to_save())
	WorldState.reset()
	assert_false(WorldState.inventory.has("jetpack"), "reset clears it")
	WorldState.from_save(JSON.parse_string(saved))
	assert_eq(WorldState.inventory.in_slot("back"), "jetpack", "the world save carries the gear")
	WorldState.from_save({})
	assert_false(WorldState.inventory.has("jetpack"), "an old save without gear loads empty")
	WorldState.reset()


# ---- extensibility --------------------------------------------------------------

func _write(path: String, data) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func test_a_new_item_and_vendor_need_only_data() -> void:
	var root := "user://m13_new_content"
	_write(root + "/manifest.json", { "items": ["rocket_pack"], "vendors": ["scrap_dealer"],
		"pickups": ["test_town"] })
	_write(root + "/items/rocket_pack.json", { "id": "rocket_pack", "label": "Rocket Pack",
		"kind": "gear", "slot": "back", "value": 300, "look": "jetpack",
		"jetpack": { "fuel": 4.0, "thrust": 50.0, "max_rise": 14.0 } })
	_write(root + "/vendors/scrap_dealer.json", { "id": "scrap_dealer", "location": "test_town",
		"marker": "x", "buys": ["gear"], "buy_rate": 0.25, "sell_rate": 2.0, "stock": ["rocket_pack"] })
	_write(root + "/pickups/test_town.json", { "id": "test_town", "pickups": [
		{ "id": "crate_pack", "item": "rocket_pack", "marker": "x" } ] })
	var c = CoreScript.new()
	assert_true(c.load_from(root))
	var item: Dictionary = c.get_item("rocket_pack")
	var v: Dictionary = c.get_vendor("scrap_dealer")
	var inv := Inventory.new()
	assert_eq(inv.buy("rocket_pack", item, v, 600), 600, "the dealer sells its data stock at 2x")
	assert_true(inv.attach("rocket_pack", item))
	var j = Jetpack.new(item.jetpack)
	assert_eq(j.fuel_max(), 4.0, "the new pack flies on its own numbers")
	assert_eq(inv.sell("rocket_pack", item, v), 75, "and sells back at 0.25x")
	assert_true(inv.pick_up(c.get_pickups("test_town")[0]), "and can lie in the world")
