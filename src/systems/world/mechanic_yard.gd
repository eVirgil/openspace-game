class_name MechanicYard
extends Node3D
## Issue #95: Dorrin Vask's speeder yard, out in the desert about a 30 second
## drive from the back gate (the "mechanic_yard" landmark in
## content/core/worlds/port_desert.json). This node dresses it (garage, bench,
## lift, scrap heap; issue #100: an awning and string lights over his counter, a
## tool bench and pegboard, canisters lying about, cargo droids driving round the
## yard and an unarmed assassin droid minding the garage), stands Dorrin at his
## bench and runs his shop:
##
##   [E] beside him  -- the menu: paint, looks, performance, the Grav Lifter, and
##                      selling the speeder for scrap.
##
## He only works on a speeder of yours parked in his bay (within bay_radius of the
## lift, inside his garage: issue #295 made it wall pieces you can drive into).
## Issue #295: the shop itself is SpeederShop, shared with Skrugs's garage bench in
## free roam; this node is Dorrin, his yard and his [E]. Words, prices and parts:
## content/core/vehicles/speeder_upgrades.json.
##
## The headless test calls talk(), buy(), scrap() and the menu's choose() directly:
## the same code paths as the keys.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const OUTFIT := { "head": "local:darker", "torso": "local:blue", "legs": "local:blue" }

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var gear: GearController              ## for its HUD (prompt, toast) and its focus (E is shared)
var cfg: Dictionary = {}              ## the "mechanic" block
var shop: SpeederShop                 ## issue #295: his menu, parts and scrap (shared with Skrugs)
var menu: DroidMenu                   ## the shop's
var mechanic: Node3D                  ## Dorrin's body
var xf := Transform3D()               ## the yard's frame (on the ball: along the ground's up)
var points: Dictionary = {}
var found := false                    ## the world has the landmark
var in_reach := false
var droids: Array = []                ## issue #100: { look: Node3D, center, rx, rz, speed, a } (cargo droids on their loops)
var guard_droid: Node3D               ## issue #100: the assassin droid with no weapon


func setup(town_demo, world_ground: WorldGround, p_gear: GearController) -> void:
	demo = town_demo
	ground = world_ground
	gear = p_gear
	player = demo._player if demo != null else null
	name = "MechanicYard"


func _ready() -> void:
	cfg = SpeederUpgrades.mechanic()
	shop = SpeederShop.new()
	shop.setup(demo, gear, cfg, func(): return world_point("bay") if found else Vector3.INF)
	add_child(shop)
	menu = shop.menu
	var cc := CoreContent.new()
	cc.load_from()
	var world: Dictionary = demo.world if "world" in demo and not demo.world.is_empty() else cc.world_for_town("port_town")
	var id := str(cfg.get("location", "mechanic_yard"))
	for lm in world.get("landmarks", []):
		if str(lm.get("location", "")) != id:
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		var origin := Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
		var sp := ground.sphere()
		if sp != null:
			origin = sp.surface_at(at.x, at.z)
		xf = Transform3D(PlanetSphere.tilt_to(ground.up_at(origin)) * Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0)))), origin)
		found = true
	if not found:
		return
	var loc: Dictionary = cc.get_location(id)
	for k in loc.get("points", {}):
		points[k] = WorldGround._v3(loc.points[k])
	if demo.use_look:
		_dress(loc)
		_build_droids()
	_build_mechanic()


func npc_name() -> String:
	return str(cfg.get("name", "the mechanic"))


## A point from the location file, in the world, on the sand.
func world_point(id: String) -> Vector3:
	var lp: Vector3 = points.get(id, Vector3.ZERO)
	var p: Vector3 = xf * Vector3(lp.x, 0.0, lp.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


# ------------------------------------------------------------------ the bay

## Your speeder parked in the bay (the nearest one to the lift), or null.
func speeder_in_bay() -> SpeederNode:
	return shop.speeder_in_bay() if shop != null else null


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_drive_droids(dt)
	if not found or player == null or mechanic == null:
		return
	var to := player.global_position - mechanic.global_position
	if to.length() < 12.0:
		var local := xf.basis.inverse() * to
		mechanic.rotation.y = lerp_angle(mechanic.rotation.y, atan2(local.x, local.z), minf(1.0, dt * 4.0))
	_tick_focus()


func _tick_focus() -> void:
	if shop.busy():
		return
	var p := player.global_position
	var at := mechanic.global_position
	in_reach = not player.piloting and Vector2(p.x - at.x, p.z - at.z).length() <= float(cfg.get("reach", 3.4)) \
		and absf(p.y - at.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not in_reach:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(shop.label("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		talk()


# ------------------------------------------------------------------ the shop (SpeederShop)

## [E] beside him: the top menu, or "bring one round" with no speeder in the bay.
func talk() -> void:
	shop.talk()


func top_options() -> Array:
	return shop.top_options()


func group_options(group: String) -> Array:
	return shop.group_options(group)


## Buy part `id` for the speeder in the bay and fit it now (SpeederShop.buy).
func buy(id: String) -> String:
	return shop.buy(id)


## Sell the speeder in the bay for scrap. Returns the credits paid (0 = none there).
func scrap() -> int:
	return shop.scrap()


# ------------------------------------------------------------------ Dorrin

func _build_mechanic() -> void:
	if demo.use_look:
		mechanic = MerchantNPC.new(CharacterKit.new(demo._flat_mats(), 0.0), "local", OUTFIT)
	else:
		mechanic = MerchantNPC.new(null)
	mechanic.name = "Mechanic"
	add_child(mechanic)
	mechanic.global_transform = Transform3D(xf.basis, world_point("mechanic"))
	mechanic.look_at_target = player
	shop.speaker = mechanic


# ------------------------------------------------------------------ the look

## The garage (open toward the town, the lift inside), the bench and the scrap
## heap, in the desert's colours: sun-bleached plaster, rust, oily steel. Issue
## #295: the garage is drawn piece by piece from the same boxes it collides with.
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var plaster := mats.plaster(xf.origin.y, xf.origin.y + 5.0, Color("#7a4a2a"), Color("#cdb48c"))
	var rust := mats.flat(Color("#8e4a26"), 0.85)
	var steel := mats.flat(Color("#4a4c52"), 0.45, 0.6)
	var dark := mats.flat(Color("#2a2622"), 0.9)
	var hazard := mats.flat(Color("#d8a020"), 0.7)
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		var id := str(b.id)
		if id.begins_with("garage_"):
			# Back wall, two side walls and a rusty roof; the side toward the town (+x) stands open.
			_mesh(_box(s), rust if id == "garage_roof" else plaster, c + Vector3(0, s.y * 0.5, 0))
			continue
		match id:
			"bench":
				_mesh(_box(s), steel, c + Vector3(0, s.y * 0.5, 0))
				_mesh(_box(Vector3(s.x + 0.1, 0.06, s.z + 0.1)), rust, c + Vector3(0, s.y + 0.03, 0))
				for i in 3:
					_mesh(_box(Vector3(0.3, 0.25, 0.4)), dark if i % 2 == 0 else hazard, c + Vector3(0, s.y + 0.15, -1.0 + i * 1.0))
			"scrap_heap":
				var rng := RandomNumberGenerator.new()
				rng.seed = 95
				for i in 9:
					var sz := Vector3(rng.randf_range(0.8, 2.2), rng.randf_range(0.4, 1.4), rng.randf_range(0.8, 2.4))
					var m := _mesh(_box(sz), rust if i % 3 else steel,
						c + Vector3(rng.randf_range(-1.6, 1.6), sz.y * 0.4 + (i / 3) * 0.5, rng.randf_range(-1.6, 1.6)))
					m.rotation += Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, TAU), rng.randf_range(-0.3, 0.3))
	_dress_garage(loc, mats, rust, dark)
	_dress_shop(mats, rust, steel, dark, hazard)
	# The lift in the bay: a steel pad with yellow and black edges.
	var bay: Vector3 = points.get("bay", Vector3.ZERO)
	_mesh(_box(Vector3(7.0, 0.12, 4.0)), steel, bay + Vector3(0, 0.06, 0))
	for dz in [-2.05, 2.05]:
		_mesh(_box(Vector3(7.0, 0.14, 0.12)), hazard, bay + Vector3(0, 0.07, dz))


## The garage's dark floor, and a sign over its open door: a hover glow tube in
## the shape of a bar. Sized from its wall pieces.
func _dress_garage(loc: Dictionary, mats: LookMaterials, rust: Material, dark: Material) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for b in loc.get("buildings", []):
		if not str(b.id).begins_with("garage_") or str(b.id) == "garage_roof":
			continue
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		lo = lo.min(c - s * Vector3(0.5, 0, 0.5))
		hi = hi.max(c + s * Vector3(0.5, 1, 0.5))
	if lo.x == INF:
		return
	var mid := (lo + hi) * 0.5
	_mesh(_box(Vector3(hi.x - lo.x - 1.0, 0.05, hi.z - lo.z - 1.0)), dark, Vector3(mid.x, 0.03, mid.z))
	_mesh(_box(Vector3(0.2, 0.9, 4.0)), rust, Vector3(hi.x + 0.3, hi.y - 0.4, mid.z))
	var tube := mats.glow(Color("#7fe0d0"))
	HangingLamp.track_glow(tube, _look())          # issue #458: brighter at dusk
	_mesh(_box(Vector3(0.1, 0.12, 3.4)), tube, Vector3(hi.x + 0.42, hi.y - 0.4, mid.z))


## Issue #100: the shop dressed up. An awning over Dorrin's counter with a string
## of bulbs, a tool bench with a vise and a pegboard of tools, crates, and fuel and
## coolant canisters lying about (some knocked over), all seeded so the yard looks
## the same every visit.
func _dress_shop(mats: LookMaterials, rust: Material, steel: Material, dark: Material, hazard: Material) -> void:
	var cloth := mats.cloth(Color("#a8503a"))
	var stripe := mats.cloth(Color("#e0c890"))
	var bench: Vector3 = Vector3(-1.5, 0, 7)
	# The awning: two poles and a striped canvas over the counter.
	for dz in [-2.2, 2.2]:
		_mesh(_cyl(0.06, 3.1), steel, bench + Vector3(1.6, 1.55, dz))
		_mesh(_cyl(0.06, 3.1), steel, bench + Vector3(-1.4, 1.55, dz))
	for k in 6:
		var m := _mesh(_box(Vector3(3.4, 0.05, 0.8)), cloth if k % 2 == 0 else stripe, bench + Vector3(0.1, 3.05, -2.0 + k * 0.8))
		m.rotation.z = -0.12
	# String lights along the awning's front edge (issue #458: on the lamp clock,
	# never off, like Skrugs's).
	var bulb := mats.glow(Color("#ffd27a"))
	HangingLamp.track_glow(bulb, _look())
	for k in 9:
		var z := -2.2 + k * 0.55
		_mesh(_ball(0.07), bulb, bench + Vector3(1.75, 2.75 - 0.12 * sin(float(k) / 8.0 * PI), z))
	# Parts on his counter, and a lamp hanging from the awning over it (issue
	# #458: a real light, the same lamp as Skrugs's).
	_mesh(_box(Vector3(0.5, 0.35, 0.4)), hazard, bench + Vector3(0.0, 1.2, -1.0))
	HangingLamp.build(self, xf, bench + Vector3(0.3, 2.35, 0.2), mats, _look(), "CounterLamp", 3.2, 6.0, 0.7, 0.5)
	_mesh(_box(Vector3(0.6, 0.08, 0.3)), dark, bench + Vector3(0.1, 1.05, 1.1))
	# The tool bench, a vise and a pegboard of tools behind it.
	var tb := Vector3(-4.6, 0, 9.4)
	_mesh(_box(Vector3(3.2, 0.9, 1.0)), rust, tb + Vector3(0, 0.45, 0))
	_mesh(_box(Vector3(3.3, 0.08, 1.1)), steel, tb + Vector3(0, 0.94, 0))
	_mesh(_box(Vector3(0.3, 0.25, 0.25)), dark, tb + Vector3(1.2, 1.1, 0.2))
	_mesh(_box(Vector3(3.2, 1.6, 0.08)), mats.flat(Color("#5a4632"), 0.9), tb + Vector3(0, 1.9, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	for k in 9:
		var t := _mesh(_box(Vector3(0.06, rng.randf_range(0.3, 0.6), 0.04)), steel if k % 3 else hazard,
			tb + Vector3(-1.3 + k * 0.32, 1.95 + rng.randf_range(-0.3, 0.3), 0.5))
		t.rotation.z = rng.randf_range(-0.4, 0.4)
	# Crates by the garage door (issue #295: beside it, not in it).
	for c in [Vector3(-2.4, 0.45, -5.4), Vector3(-2.2, 1.3, -5.2), Vector3(-1.2, 0.45, -5.6)]:
		_mesh(_box(Vector3(0.9, 0.9, 0.9)), mats.flat(Color("#7a5a36"), 0.9), c)
	# Canisters lying about: fuel red, coolant teal, some on their sides.
	var paints := [mats.flat(Color("#b03a26"), 0.6, 0.2), mats.flat(Color("#3a8a8a"), 0.6, 0.2), hazard, steel]
	for k in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 15.0)
		var at := Vector3(2.0 + cos(a) * r, 0.0, sin(a) * r)
		if (at.x > -3.0 and at.x < 12.0 and absf(at.z) < 3.0) or (at.x < -2.5 and absf(at.z) < 5.5) or Vector2(at.x + 1.5, at.z - 7.0).length() < 2.5:
			continue                 # not on the way into the garage, in it or at the counter
		var tall := rng.randf_range(0.6, 1.0)
		var m := _mesh(_cyl(0.28, tall), paints[k % paints.size()], at + Vector3(0, tall * 0.5, 0))
		if k % 3 == 0:
			m.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0)
			m.position = (xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.28, 0))).origin
		else:
			m.rotation.y = rng.randf() * TAU


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c


func _ball(r: float) -> SphereMesh:
	var b := SphereMesh.new()
	b.radius = r
	b.height = r * 2.0
	b.radial_segments = 8
	b.rings = 4
	return b


# ------------------------------------------------------------------ droids (issue #100)

## Cargo droids driving loops round the yard, and an assassin droid with no
## weapon standing by the garage door. Looks only: nobody owns them.
func _build_droids() -> void:
	var mats: LookMaterials = demo._flat_mats()
	var variants := ["tan", "olive", "blue"]
	var loops := [[Vector3(9, 0, 0), 9.0, 11.0, 2.4], [Vector3(10, 0, -1), 7.0, 13.0, -2.0], [Vector3(10, 0, 1), 9.0, 8.0, 2.9]]
	for i in loops.size():
		var L: Array = loops[i]
		var look := DroidKit.build("cargo", DroidRoster.variant_cfg("cargo", variants[i % variants.size()]), mats,
			DroidRoster.kind_cfg("cargo").get("look", {}))
		look.name = "YardCargo%d" % (i + 1)
		add_child(look)
		DroidKit.set_awake(look, true)
		droids.append({ "look": look, "center": L[0], "rx": float(L[1]), "rz": float(L[2]), "speed": float(L[3]), "a": TAU * i / 3.0 })
	var lc := { "kind": "assassin" }
	guard_droid = DroidKit.build("assassin", DroidRoster.variant_cfg("assassin", "gunmetal"), mats, ShipSalesman.model_look(lc))
	ShipSalesman._disarm(guard_droid)
	guard_droid.name = "YardAssassin"
	add_child(guard_droid)
	DroidKit.set_awake(guard_droid, true)
	DroidKit.play_anim(guard_droid, "idle")
	guard_droid.global_transform = Transform3D(xf.basis * Basis(Vector3.UP, -PI * 0.5), _ground(Vector3(-2.0, 0, 5.6)))     # issue #295: beside the door, not in it
	_drive_droids(0.0)


## A point in the yard's frame, on the ground.
func _ground(local: Vector3) -> Vector3:
	var p: Vector3 = xf * Vector3(local.x, 0.0, local.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


func _drive_droids(dt: float) -> void:
	for d in droids:
		var look: Node3D = d.look
		if not is_instance_valid(look):
			continue
		var rx: float = d.rx
		var rz: float = d.rz
		# Even speed round an ellipse: step the angle by speed over the local radius.
		var a: float = d.a
		var rl := Vector2(rx * sin(a), rz * cos(a)).length()
		a += float(d.speed) * dt / maxf(rl, 0.5)
		d.a = a
		var c: Vector3 = d.center
		var local := c + Vector3(cos(a) * rx, 0, sin(a) * rz)
		var tangent := Vector3(-sin(a) * rx, 0, cos(a) * rz).normalized() * signf(float(d.speed))
		var yaw := atan2(-tangent.x, -tangent.z)
		look.global_transform = Transform3D(xf.basis * Basis(Vector3.UP, yaw), _ground(local))


## The scene's look, for its lamp clock; null in a bare dressing (tests, lookdev).
func _look() -> LookEnvironment:
	return demo.get("look") as LookEnvironment if demo != null else null


## A mesh at a point in the yard's own frame.
func _mesh(mesh: Mesh, mat: Material, local: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf * Transform3D(Basis.IDENTITY, local)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
