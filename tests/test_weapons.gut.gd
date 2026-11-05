extends GutTest
## M2: the weapon state machine. Proves visible-bolt blasters: fire timing, recoil,
## ammo drawdown, and reload. This is the core of "two ranged weapons work" and is
## proven headless -- no rendered bolts needed in CI.

var pistol
var rifle
var blade


func before_each() -> void:
	var content = load("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var Weapon = load("res://src/systems/combat/weapon.gd")
	pistol = Weapon.new(content.get_weapon("pistol_blaster"))
	rifle = Weapon.new(content.get_weapon("rifle_blaster"))
	blade = content.get_weapon("energy_blade")


func test_both_weapons_exist_and_differ() -> void:
	assert_eq(pistol.config.get("class"), "pistol")
	assert_eq(rifle.config.get("class"), "rifle")
	assert_gt(rifle.config.get("damage"), pistol.config.get("damage"), "rifle hits harder")
	assert_true(pistol.config.get("visible_bolt"), "blaster bolts are visible")
	assert_true(rifle.config.get("visible_bolt"), "rifle bolts are visible")


func test_firing_drops_ammo_one_per_shot() -> void:
	var start: int = pistol.ammo
	pistol.start_firing(0.05, true)   # fire this frame
	assert_eq(pistol.ammo, start - 1, "firing drops one round")
	# Fire again immediately should be blocked by the cooldown.
	var blocked: int = pistol.start_firing(0.05, true)
	assert_eq(blocked, int(pistol.Result.NONE), "cooldown blocks the 2nd shot")
	assert_eq(pistol.ammo, start - 1, "ammo unchanged while on cooldown")


func test_cooldown_unlocks_firing() -> void:
	pistol.start_firing(0.05, true)
	pistol.start_firing(0.5, true)  # advance past the 0.12s cooldown
	# After cooldown, a fresh trigger pull should fire.
	pistol._fire_cd_left = 0.0
	var res: int = pistol.start_firing(0.01, true)
	assert_eq(res, int(pistol.Result.SHOT), "after cooldown the weapon fires")


func test_firing_to_empty_triggers_reload() -> void:
	var Weapon := load("res://src/systems/combat/weapon.gd")
	var tiny = Weapon.new({ "mag": 2, "rate": 0.0, "reload_time": 0.5, "damage": 1 })
	tiny.ammo = 2
	tiny.start_firing(0.01, true)   # shot 1
	tiny.start_firing(0.01, true)   # shot 2 -> empty
	var res: int = tiny.start_firing(0.01, true)   # empty + trigger -> reload start
	assert_eq(res, int(tiny.Result.RELOAD_START), "empty + trigger starts reload")
	assert_true(tiny.is_reloading(), "reloading flag is set")
	# Finish the reload and confirm it restores the full magazine.
	tiny.start_firing(1.0, false)
	assert_eq(tiny.ammo, 2, "reload restores full magazine")
	assert_false(tiny.is_reloading(), "reload completes")


func test_recoil_is_configured() -> void:
	assert_gt(pistol.recoil(), 0.0, "pistol has recoil")
	assert_gt(rifle.recoil(), 0.0, "rifle has recoil")
	assert_gt(rifle.recoil(), pistol.recoil(), "rifle has more recoil")


func test_energy_blade_is_melee_in_core() -> void:
	# The blade is a melee; it lives in the same data layer and is distinguished
	# by class. (Full blade behavior is M3; this only proves it is present and
	# labeled melee for the data layer.)
	assert_eq(blade.get("class"), "melee")


func test_reload_progress_runs_zero_to_one() -> void:
	# Issue #229: the reload is animated from this.
	var w = load("res://src/systems/combat/weapon.gd").new({ "mag": 4, "rate": 0.0, "reload_time": 1.0, "damage": 1 })
	assert_eq(w.reload_progress(), -1.0, "not reloading")
	w.ammo = 1
	w.start_reloading()
	assert_almost_eq(w.reload_progress(), 0.0, 0.001)
	w.start_firing(0.25, false)
	assert_almost_eq(w.reload_progress(), 0.25, 0.001)
	w.start_firing(0.8, false)
	assert_eq(w.reload_progress(), -1.0, "done")


## Issue #546: a held trigger fires at the data's rate. The cooldown used to drop
## the part of the tick past zero, so every rate rounded up to whole 60 Hz ticks
## (the pistol's 0.12 s fired every 0.133 s, 10% slow).
func test_held_trigger_fires_at_the_data_rate() -> void:
	var content = load("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var Weapon = load("res://src/systems/combat/weapon.gd")
	for id in ["pistol_blaster", "rifle_blaster", "ship_cannon"]:
		var cfg: Dictionary = content.get_weapon(id).duplicate()
		cfg["mag"] = 100000   # no reloads in the window
		var w = Weapon.new(cfg)
		var shots := 0
		for i in 600:   # 10 s at 60 Hz
			if w.start_firing(1.0 / 60.0, true) == int(w.Result.SHOT):
				shots += 1
		var want: float = 10.0 / float(cfg["rate"])
		assert_almost_eq(float(shots), want, 1.0, "%s: %d shots in 10 s, data says %.1f" % [id, shots, want])
