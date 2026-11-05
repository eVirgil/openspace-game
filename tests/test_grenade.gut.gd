extends GutTest
## Issue #372: the thrown grenade. The arc preview and the thrown body land in the
## same place; it bounces off a wall, bursts at the fuse or at once on a droid; the
## blast kills a trooper, a droid and a speeder in its radius and leaves one outside
## it alone, and hurts the player who threw it; one grenade throws once; every gear
## trader and fence sells them at one price and never runs out.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const PlayerBody := preload("res://src/systems/player/character_body.gd")

var cfg: Dictionary
var content


func before_each() -> void:
	WorldState.reset()
	cfg = CharacterKit._read_json(Grenade.CFG_PATH)
	content = CoreScript.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


## A ray against the plane y = 0 (the ground) and, when `wall_x` is finite, the wall x = wall_x.
static func _planes(wall_x := INF) -> Callable:
	return func(a: Vector3, b: Vector3) -> Dictionary:
		var best := {}
		var best_t := 2.0
		if a.y > 0.0 and b.y <= 0.0:
			var t := a.y / (a.y - b.y)
			best = { "position": a.lerp(b, t), "normal": Vector3.UP, "collider": null }
			best_t = t
		if is_finite(wall_x) and a.x < wall_x and b.x >= wall_x:
			var t := (wall_x - a.x) / (b.x - a.x)
			if t < best_t:
				best = { "position": a.lerp(b, t), "normal": Vector3.LEFT, "collider": null }
		return best


func _thrown(at: Vector3, v: Vector3, hit: Callable) -> Grenade:
	var g := Grenade.new()
	g.setup(cfg, at, v)
	g.hit = hit
	g.up_at = func(_p): return Vector3.UP
	autofree(g)
	return g


# ---- the arc ------------------------------------------------------------------

func test_preview_and_throw_land_in_the_same_place() -> void:
	var dt := 1.0 / 60.0
	var at := Vector3(0, 1.55, 0)
	var v := GrenadeArc.launch_velocity(Vector3(0, -0.1, -1), Vector3.UP, float(cfg.throw_speed), float(cfg.lift_deg))
	var path := GrenadeArc.trace(at, v, float(cfg.gravity), func(_p): return Vector3.UP, _planes(), 6.0, dt)
	assert_true(path.landed, "the preview reaches the ground")
	var g := _thrown(at, v, _planes())
	for i in 600:
		g.tick(dt)
		if g.first_contact != Vector3.INF:
			break
	assert_almost_eq((g.first_contact as Vector3).distance_to(path.at), 0.0, 0.001, "the grenade lands where the dots end")
	assert_gt((path.at as Vector3).length(), 8.0, "a throw carries some way")


# ---- bounce and fuse ----------------------------------------------------------

func test_it_bounces_back_off_a_wall() -> void:
	var g := _thrown(Vector3(0, 1.5, 0), Vector3(12, 2, 0), _planes(3.0))
	for i in 60:
		g.tick(1.0 / 60.0)
		if g.bounces > 0:
			break
	assert_eq(g.bounces, 1, "it hit the wall")
	assert_lt(g.velocity.x, 0.0, "and comes back off it")
	assert_lt(absf(g.velocity.x), 12.0 * 0.5, "slower than it went in")
	assert_false(g.done, "a wall does not set it off")


func test_it_bursts_when_the_fuse_runs_out() -> void:
	var g := _thrown(Vector3(0, 1000, 0), Vector3.ZERO, func(_a, _b): return {})
	var bursts := []
	g.burst.connect(func(at, _hurt): bursts.append(at))
	var t := 0.0
	while not g.done and t < 10.0:
		g.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_eq(bursts.size(), 1, "it went off once")
	assert_almost_eq(t, float(cfg.fuse_s), 1.0 / 30.0, "at the fuse time")


func test_it_bursts_at_once_on_a_droid() -> void:
	var droid := StaticBody3D.new()
	autofree(droid)
	var hit := func(a: Vector3, b: Vector3) -> Dictionary:
		return { "position": a.lerp(b, 0.5), "normal": Vector3.UP, "collider": droid } if b.x >= 2.0 else {}
	var g := _thrown(Vector3(0, 1.5, 0), Vector3(10, 0, 0), hit)
	g.is_target = func(c): return c == droid
	var ticks := 0
	while not g.done and ticks < 60:
		g.tick(1.0 / 60.0)
		ticks += 1
	assert_true(g.done, "touching the droid set it off")
	assert_lt(ticks * (1.0 / 60.0), 0.5, "long before the fuse")


# ---- the blast ----------------------------------------------------------------

func _trooper(at: Vector3) -> NpcBody:
	var n := NpcBody.new()
	n.setup(content.get_soldier("gate_guard"), at, 0.0, null)
	add_child_autofree(n)
	return n


func test_the_blast_wrecks_what_is_close_and_spares_what_is_not() -> void:
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
	var near := _trooper(Vector3(2, 0, 0))
	var far := _trooper(Vector3(float(cfg.blast_radius) + 6.0, 0, 0))
	var you: CharacterBody3D = PlayerBody.new()
	root.add_child(you)
	you.global_position = Vector3(-2, 0, 1)
	var speeder := SpeederNode.new()
	speeder.setup(null, null, {}, false)
	root.add_child(speeder)
	speeder.global_position = Vector3(0, 0.6, -3)
	var ctl := DroidController.new()
	ctl.setup(null, you, null)
	root.add_child(ctl)
	await wait_physics_frames(3)
	assert_gt(ctl.remnant.size(), 0, "a Remnant droid to blow up")
	var droid = ctl.remnant[0]
	droid.global_position = Vector3(0, 0, 2)
	await wait_physics_frames(2)
	var hp_before: int = you.health.hp
	var hurt := Blast.damage(root.get_world_3d().direct_space_state, Vector3(0, 0.3, 0), cfg, you, you)
	assert_true(near.dead, "the trooper beside it is dead")
	assert_false(far.dead, "the one outside the radius is not")
	assert_eq(far.hits_taken, 0, "and was not touched")
	assert_true(droid.dead, "the droid went up")
	assert_false(speeder.model.alive(), "the speeder is destroyed")
	assert_eq(hp_before - int(you.health.hp), int(cfg.player_damage), "the thrower takes the player's damage")
	assert_true(hurt.has(near) and hurt.has(speeder), "it reports what it hurt")


func test_a_blast_kill_flings_harder_than_a_bolt() -> void:
	var rc := Ragdoll.load_config()
	var fling := Ragdoll.blast_fling(Vector3(1, 0, 0), Vector3.ZERO, float(cfg.blast_radius), Vector3.UP, rc)
	assert_gt(fling.x, 0.0, "away from the burst")
	assert_gt(fling.y, 0.0, "and off its feet")
	assert_gt(fling.length(), float(rc.get("kick_max", 4.5)), "harder than the hardest bolt kick")
	var edge := Ragdoll.blast_fling(Vector3(6, 0, 0), Vector3.ZERO, float(cfg.blast_radius), Vector3.UP, rc)
	assert_lt(edge.length(), fling.length(), "softer at the edge")


# ---- LAN ----------------------------------------------------------------------

class FakeRemote extends StaticBody3D:
	var peer_id := 7
	var took := 0.0
	func apply_damage_from(amount: float, _shooter: Node) -> void:
		took += amount
	func apply_damage(_amount: float) -> void:
		pass


func test_another_players_grenade_is_only_a_picture() -> void:
	var g := _thrown(Vector3(0, 1.5, 0), Vector3(4, 3, 0), _planes())
	g.picture = true
	g.is_target = func(_c): return true      # even what would set a real one off
	var bursts := []
	g.burst.connect(func(at, _h): bursts.append(at))
	var t := 0.0
	while not g.done and t < 10.0:
		g.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_eq(bursts.size(), 0, "it never goes off by itself: the thrower's game says where")
	assert_gt(t, float(cfg.fuse_s), "it lingers past the fuse waiting for word")


func test_a_grenade_hurts_another_player_like_it_hurts_you() -> void:
	var other := FakeRemote.new()
	autofree(other)
	assert_true(Blast.hit(other, Vector3.ZERO, cfg, null, null))
	assert_eq(other.took, float(cfg.player_damage), "the player's damage, not a trooper's")


# ---- the throw's pose -----------------------------------------------------------

func test_the_arm_winds_back_then_swings_over_and_lets_go() -> void:
	var sp := ThrowPose.spec(CharacterKit._read_json("res://content/look/hand_weapons.json"))
	var wound := ThrowPose.right_hand(sp, -1.0)
	assert_lt(wound.z, 0.0, "held, the hand is behind the shoulder")
	assert_gt(wound.y, 0.18, "and above it")
	var mid := ThrowPose.right_hand(sp, float(sp.swing_s) * 0.45)
	assert_gt(mid.y, wound.y - 0.1, "it comes over the top")
	var end := ThrowPose.right_hand(sp, float(sp.swing_s))
	assert_gt(end.z, 0.2, "and finishes out in front")
	assert_true(ThrowPose.in_hand(sp, 0.0), "the grenade is in the hand as the swing starts")
	assert_false(ThrowPose.in_hand(sp, ThrowPose.release_delay(sp) + 0.01), "and gone at the release")
	assert_eq(ThrowPose.weight(sp, 0.0, float(sp.swing_s) * 0.5), 1.0, "the swing owns the arm")
	assert_almost_eq(ThrowPose.weight(sp, 0.0, float(sp.swing_s) + float(sp.blend_s) + 0.001), 0.0, 0.001, "and gives it back after")


# ---- supply -------------------------------------------------------------------

func test_one_grenade_throws_once() -> void:
	var w := PlayerWeapons.new()
	w.grenade_cfg = cfg
	add_child_autofree(w)
	WorldState.inventory.add("grenade", 1)
	assert_eq(w.grenades(), 1)
	assert_not_null(w.throw_grenade(Vector3.ZERO, Vector3.FORWARD), "the first throw goes")
	assert_eq(w.grenades(), 0, "none left")
	assert_null(w.throw_grenade(Vector3.ZERO, Vector3.FORWARD), "the second press does nothing")
	assert_eq(w.grenades_thrown, 1)


func test_grenades_are_saved_with_the_world() -> void:
	WorldState.inventory.add("grenade", 3)
	var inv := Inventory.new()
	inv.from_save(WorldState.inventory.to_save())
	assert_eq(inv.count("grenade"), 3)


func test_every_gear_trader_and_fence_sells_them_for_ever() -> void:
	var item: Dictionary = content.get_item("grenade")
	var sellers := 0
	var price := -1
	for vid in content.vendors:
		var v: Dictionary = content.get_vendor(vid)
		var buys: Array = v.get("buys", [])
		if not (buys.has("gear") or buys.has("contraband")):
			continue
		sellers += 1
		assert_true(Inventory.sells_endlessly("grenade", v), "%s never runs out of grenades" % vid)
		var p := Inventory.buy_price(item, v)
		if price < 0:
			price = p
		assert_eq(p, price, "%s sells them at the one price" % vid)
	assert_eq(price, 40)
	assert_gte(sellers, 4, "the port's gear trader and fence, the moon's and the lava moon's fences")
	var moon: Dictionary = content.get_vendor("station_fence")
	var inv := Inventory.new()
	for i in 3:
		assert_eq(inv.buy("grenade", item, moon, 1000), 40)
	assert_true(inv.vendor_stock(moon).has("grenade"), "still in stock after three")
	assert_eq(inv.count("grenade"), 3)


func test_a_dead_trooper_can_leave_one() -> void:
	var cfg_drop: Dictionary = cfg.get("drop", {})
	assert_true((cfg_drop.get("factions", []) as Array).has("imperial_remnant"))
	assert_gt(float(cfg_drop.get("chance", 0.0)), 0.0)
	var inv := Inventory.new()
	assert_true(inv.pick_up({ "id": "grenade_drop_1", "item": "grenade", "loose": true }))
	assert_eq(inv.count("grenade"), 1)
	assert_false(inv.is_taken("grenade_drop_1"), "a trooper's drop is not kept in the save")
