extends GutTest
## Issue #392: the moon rave's droid merchant sells a floating droid and the laser
## rig, sold nowhere else. A rig is dark until E beside the droid turns it on; E
## again turns it off. On or off is saved with the droid. Knocked out it goes
## dark, and it comes back with the droid when it reboots.


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
	var vehicle: Node


func before_each() -> void:
	WorldState.reset()


func _scene() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	root.add_child(ctl)
	return [ctl, p]


## The merchants: the market's (as at the port) and the moon rave's, far apart.
func _sites(ctl: DroidController) -> void:
	var cv: Dictionary = DroidRoster.config().club_vendor
	ctl.vendor_sites.append({ "id": "port_market", "pos": Vector3(-60, 0, 0), "face": Vector3(0, 0, 1), "label": "Droid Merchant" })
	ctl.vendor_sites.append({ "id": str(cv.id), "pos": Vector3(60, 0, 0), "face": Vector3(0, 0, 1), "label": str(cv.label),
		"stock": cv.stock, "sells": str(cv.sells) })


func test_the_rig_is_sold_only_at_the_rave_and_fits_only_floating_droids() -> void:
	assert_eq(DroidRoster.upgrades_for("floating"), ["health", "damage"], "the other merchants' list is as it was")
	assert_eq(DroidRoster.upgrades_for("floating", "rave"), ["lasers"], "the rave's merchant sells the rig")
	assert_eq(DroidRoster.upgrades_for("assassin", "rave"), [], "for floating droids only")
	assert_eq(DroidRoster.upgrades_for("cargo", "rave"), [])
	var s := _scene()
	var ctl: DroidController = s[0]
	_sites(ctl)
	ctl._select_vendor(1)
	assert_eq(ctl.trade_options().map(func(o): return o.id), ["buy:floating"], "floating droids only")
	WorldState.credits = 1000
	assert_eq(ctl.buy("floating"), "bought")
	var uid := int(WorldState.droids.owned[0].uid)
	assert_eq(ctl.upgrade_options().map(func(o): return o.id), ["up:%d:lasers" % uid], "the laser rig, nothing else")
	ctl._select_vendor(0)
	assert_false(ctl.upgrade_options().any(func(o): return str(o.id).ends_with(":lasers")), "not at the market")


func test_e_turns_the_lasers_on_and_off_and_it_is_saved_and_reboots() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	_sites(ctl)
	ctl._select_vendor(1)
	WorldState.credits = 1000
	assert_eq(ctl.buy("floating"), "bought")
	var uid := int(WorldState.droids.owned[0].uid)
	assert_eq(ctl.upgrade(uid, "lasers"), "upgraded")
	assert_eq(WorldState.credits, 1000 - 50 - int(DroidRoster.upgrade_cfg("lasers").prices[0]), "the rig's price, from data")
	var d: Dictionary = WorldState.droids.find(uid)
	assert_eq(str(d.variant), "rave", "it wears the rave droid's colours")
	await wait_physics_frames(3)
	var u = ctl.companions[uid]
	assert_not_null(u.rig, "the rig is on the droid")
	assert_false(u.lasers.visible, "a new rig is dark")
	# Stand beside it, away from both merchants.
	p.global_position = u.global_position + Vector3(0.8, 0, 0)
	ctl.focus = {}
	assert_eq(ctl.interact(), "lasers_on")
	assert_true(u.lasers.visible, "E: lasers on")
	assert_true(DroidRoster.lasers_on(d))
	ctl.focus = {}
	assert_eq(ctl.interact(), "lasers_off")
	assert_false(u.lasers.visible, "E again: off")
	ctl.focus = {}
	assert_eq(ctl.interact(), "lasers_on")
	# Saved with the droid.
	var loaded := DroidRoster.new()
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_true(DroidRoster.lasers_on(loaded.find(uid)), "on survives a save")
	WorldState.droids.set_lasers(uid, false)
	loaded.from_save(JSON.parse_string(JSON.stringify(WorldState.droids.to_save())))
	assert_false(DroidRoster.lasers_on(loaded.find(uid)), "and so does off")
	assert_true(DroidRoster.has_lasers(loaded.find(uid)), "the rig too")
	WorldState.droids.set_lasers(uid, true)
	u.lasers.visible = true
	# Knocked out: dark. Rebooted: on again.
	ctl._hurt_companion(u, 99999.0)
	assert_true(u.dead)
	assert_false(u.rig.visible, "dark while it is knocked out")
	u.down_left = 0.01
	await wait_physics_frames(3)
	var back = ctl.companions[uid]
	assert_ne(back, u, "a new body")
	assert_false(back.dead)
	assert_true(back.rig.visible and back.lasers.visible, "lasers back on when it reboots")
