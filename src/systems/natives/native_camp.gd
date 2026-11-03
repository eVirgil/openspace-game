class_name NativeCamp
extends Node3D
## Issue #96: a desert pack's camp. A ring of hide tents round a firepit that is
## always lit, built where the pack's data puts it (a stop on its route). Each tent
## is a full room: walls with a doorway facing the fire, a roof, a rug, a rock
## table and rock seats, a bedroll and a chest of loot. The walls are solid.
##
## Shoot a tent and it takes damage; enough and it falls in (the rock furniture and
## the chest stay). Every tent down and the camp is wrecked: it is rebuilt a few
## in-game hours later (NativesDirector, WorldState.native_camp). What the tents'
## chests hold, who sees you take it, and resting are the director's.
##
## Built from the people's "camp" block (content/core/species/*.json) and the
## pack's own "camp" (the planet's natives data).

signal tent_hit(shooter: Node, amount: float)
signal wrecked

var id := ""
var cfg: Dictionary = {}
var director                          ## NativesDirector: the ground, the materials
var center := Vector3.ZERO            ## the firepit, on the ground
var up := Vector3.UP
var tents: Array = []                 ## see _tent
var fires: Array = []                 ## { root, light, flames: [MeshInstance3D] }
var spots: Array = []                 ## where members stand round the fire (world)
var is_wrecked := false
## Issue #402: a LAN guest's copy of the host's camp. Hits on its tents go here,
## (tent, amount, shooter), instead of tearing them: the host's game says which fall.
var net_hit: Callable
var lit_near := 140.0                 ## lights and flicker only this close to the player
var _near := false
var _near_t := 0.0
var _t := 0.0


func setup(camp_id: String, camp_cfg: Dictionary, p_director, at: Vector3) -> void:
	id = camp_id
	name = "Camp_" + camp_id
	cfg = camp_cfg
	director = p_director
	center = pick_site(at)
	up = director.up_at(center)


## The flattest ground within site_search_m of `at` for the fire and the ring of
## tents (dunes would cut through them), off any rock. A few hundred ground
## queries, once.
func pick_site(at: Vector3) -> Vector3:
	# Close in first (the planet levels the ground at `at`, so off a rock there is
	# usually right there), then the whole search.
	var close := _best_site(at, 9.0, 3.0)
	if _unevenness(close) < 0.3:
		return close
	return _best_site(at, float(cfg.get("site_search_m", 45.0)), 9.0)


func _best_site(at: Vector3, search: float, step: float) -> Vector3:
	var u: Vector3 = director.up_at(at)
	var side := NativeSteer._side(u)
	var fwd := side.cross(u).normalized()
	var best := at
	var best_score := INF
	var n := int(search / step)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var c: Vector3 = at + side * (i * step) + fwd * (j * step)
			if c.distance_to(at) > search:
				continue
			if director.steer != null and director.steer.blocked(c, u):
				continue
			var score := _unevenness(director._on_ground(c)) + c.distance_to(at) * 0.01
			if score < best_score:
				best_score = score
				best = c
	return director._on_ground(best)


## How far apart (up and down) the ground is under the fire and the tents' floors.
func _unevenness(c: Vector3) -> float:
	var u: Vector3 = director.up_at(c)
	var side := NativeSteer._side(u)
	var fwd := side.cross(u).normalized()
	var ring := float(cfg.get("ring_m", 9.0))
	var r := float(cfg.get("tent_radius", 3.0))
	var lo := 0.0
	var hi := 0.0
	for k in 12:
		var a := TAU * float(k) / 12.0
		for d: float in [ring - r, ring, ring + r]:
			var h: float = (director._on_ground(c + (side * cos(a) + fwd * sin(a)) * d) - c).dot(u)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Everything, at once (a few dozen meshes and shapes; no bodies).
func build() -> void:
	var mats: LookMaterials = director.demo._flat_mats() if director.demo != null and director.demo.use_look else null
	var n := clampi(int(cfg.get("tents", 3)), 1, 6)
	var ring := float(cfg.get("ring_m", 9.0))
	var side := NativeSteer._side(up)
	var fwd := side.cross(up).normalized()
	var a0 := float(cfg.get("yaw_deg", 0.0)) * PI / 180.0
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var at := center + (side * cos(a) + fwd * sin(a)) * ring
		if director.steer != null:
			at = director.steer.clear_spot(at, up)
		var fl := _floor_at(director._on_ground(at))
		tents.append(_tent(i, fl.at, float(fl.depth), mats))
	fires.append(_firepit(center, mats))
	_props(mats)
	# Packs walk round the tents and what lies between them.
	if director.steer != null:
		for t in tents:
			director.steer.add((t.xf as Transform3D).origin, float(t.r) + 0.3)
		for i in n:
			var a := a0 + TAU * (float(i) + 0.5) / float(n)
			director.steer.add(center + (side * cos(a) + fwd * sin(a)) * ring * 0.95, 1.3)
	var k := maxi(int(cfg.get("spots", 14)), 1)
	for i in k:
		var a := TAU * (float(i) + 0.5) / float(k)
		var r := 2.6 + float(i % 2) * 1.2
		spots.append(director._on_ground(center + (side * cos(a) + fwd * sin(a)) * r))


## A tent's floor: { at, depth }. Level with the highest ground under it (up to
## half a metre over the middle), so no sand shows through inside; `depth` is how
## far down its earth platform and walls reach to meet the lowest ground.
func _floor_at(at: Vector3) -> Dictionary:
	var u: Vector3 = director.up_at(at)
	var side := NativeSteer._side(u)
	var fwd := side.cross(u).normalized()
	var r := float(cfg.get("tent_radius", 3.0))
	var sum := 0.0
	var lo := 0.0
	var hi := 0.0
	for k in 12:
		var a := TAU * float(k) / 12.0
		for d: float in [r * 0.5, r]:
			var h: float = (director._on_ground(at + (side * cos(a) + fwd * sin(a)) * d) - at).dot(u)
			sum += h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var floor_h := minf(hi, sum / 24.0 + 0.5) + 0.03
	return { "at": at + u * floor_h, "depth": floor_h - lo + 0.12 }


## The frame of something standing at `at` on the ground, its +Z turned to face `look`.
func _frame(at: Vector3, look: Vector3) -> Transform3D:
	var u: Vector3 = director.up_at(at)
	var tilt := PlanetSphere.tilt_to(u)
	var l := tilt.inverse() * (look - at)
	var yaw := atan2(l.x, l.z) if Vector2(l.x, l.z).length() > 0.01 else 0.0
	return Transform3D(tilt * Basis(Vector3.UP, yaw), at)


# ------------------------------------------------------------------ tents

class TentBody extends StaticBody3D:
	var camp
	var index := 0

	func apply_damage_from(amount: float, shooter: Node) -> void:
		camp._on_tent_hit(index, amount, shooter)

	func apply_damage(amount: float) -> void:
		apply_damage_from(amount, null)


## One tent: { index, xf, body, upright, heap, walls: [CollisionShape3D], hp, down,
## inside: Vector3 (its middle, on the floor), bed, box (chest, world), lid }.
func _tent(i: int, at: Vector3, depth: float, mats: LookMaterials) -> Dictionary:
	var xf := _frame(at, center)            # the doorway (+Z) faces the fire
	var r := float(cfg.get("tent_radius", 3.0))
	var wall_h := float(cfg.get("wall_h", 1.95))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + i * 7919
	var root := Node3D.new()
	root.name = "Tent_%d" % i
	add_child(root)
	root.global_transform = xf
	var body := TentBody.new()
	body.name = "Body"
	body.camp = self
	body.index = i
	root.add_child(body)
	var upright := Node3D.new()
	upright.name = "Upright"
	root.add_child(upright)
	var t := { "index": i, "xf": xf, "root": root, "body": body, "upright": upright, "walls": [],
		"hp": float(cfg.get("tent_hp", 90.0)), "down": false, "r": r }
	var hide_col := Color(str(cfg.get("hide", "#a88a64")))
	var rug_col := Color(str(cfg.get("rug", "#8c3a26")))
	var accent := Color(str(cfg.get("rug_accent", "#d9a441")))
	var segs := 14
	var hide: Material = null
	var roof_hide: Material = null
	var dark: Material = null
	var rock: Material = null
	var wood: Material = null
	var rope: Material = null
	if mats != null:
		hide = CampTextures.hide(hide_col)
		# The roof's one UV wrap holds every panel: a seam per panel.
		var rh := (hide as StandardMaterial3D).duplicate() as StandardMaterial3D
		rh.uv1_scale = Vector3(segs, 1.0, 1.0)
		roof_hide = rh
		dark = CampTextures.hide(hide_col.darkened(0.35))
		rock = CampTextures.rock(Color(str(cfg.get("rock", "#6e6258"))))
		wood = CampTextures.wood(Color("#6a4a2c"))
		rope = mats.flat(Color("#8a7454"), 1.0)
	# The floor: a low platform of packed earth, its sides sloped so you walk up
	# onto it at the doorway, reaching down to the lowest ground under the tent.
	var plat := CylinderMesh.new()
	plat.top_radius = r - 0.05
	plat.bottom_radius = r + depth * 1.6
	plat.height = depth
	plat.radial_segments = 28
	plat.rings = 1
	var earth: Material = CampTextures.earth(Color(str(cfg.get("earth", "#c89c6c")))) if mats != null else null
	_mesh(root, plat, earth, Transform3D(Basis.IDENTITY, Vector3(0, -depth * 0.5, 0)))
	_shape(body, plat.create_convex_shape(), Transform3D(Basis.IDENTITY, Vector3(0, -depth * 0.5, 0)))
	# Walls: hide panels round a circle, the ones at the front left out (the
	# doorway). One quad each (its seams at its edges), a solid box to bump into.
	var skirt := maxf(float(cfg.get("skirt_m", 0.8)), depth)
	var door := deg_to_rad(float(cfg.get("door_deg", 34.0)))
	var chord := 2.0 * r * sin(PI / segs) + 0.04
	for s in segs:
		var a := TAU * (float(s) + 0.5) / segs
		if absf(wrapf(a, -PI, PI)) < door:
			continue
		# Down into the sand by `skirt`, so a slope never shows a gap under it.
		var pos := Vector3(r * sin(a), (wall_h - skirt) * 0.5, r * cos(a))
		var b := Basis(Vector3.UP, a)
		var q := QuadMesh.new()
		q.size = Vector2(chord, wall_h + skirt)
		_mesh(upright, q, hide, Transform3D(b, pos))
		var cs := _shape(body, _box_shape(Vector3(chord, wall_h + skirt, 0.3)), Transform3D(b, pos))
		(t.walls as Array).append(cs)
		# A painted band of the rug's colours round the top of the wall, outside.
		if mats != null:
			var band := QuadMesh.new()
			band.size = Vector2(chord, 0.22)
			_mesh(upright, band, mats.cloth(accent.darkened(0.15) if s % 2 == 0 else rug_col),
				Transform3D(b, Vector3((r + 0.012) * sin(a), wall_h - 0.32, (r + 0.012) * cos(a))))
		# Wall posts at every other joint, and a guy rope out to a stake.
		var aj := TAU * float(s) / segs
		if s % 2 == 0 and absf(wrapf(aj, -PI, PI)) > door:
			var post := Vector3((r - 0.04) * sin(aj), 0, (r - 0.04) * cos(aj))
			_mesh(upright, _cyl(0.045, wall_h + 0.1), wood, Transform3D(Basis.IDENTITY, post + Vector3(0, (wall_h + 0.1) * 0.5, 0)))
			if s % 4 == 0:
				var top := Vector3((r + 0.05) * sin(aj), wall_h + 0.02, (r + 0.05) * cos(aj))
				var stake := Vector3((r + 1.3) * sin(aj), 0.0, (r + 1.3) * cos(aj))
				_line(upright, top, stake, 0.012, rope)
				_mesh(upright, _cyl(0.035, 0.3), wood, Transform3D(Basis.IDENTITY, stake + Vector3(0, 0.1, 0)))
	# Flaps tied back either side of the doorway, and the door frame.
	for sgn: float in [-1.0, 1.0]:
		var a := sgn * door
		var b := Basis(Vector3.UP, a + sgn * 0.9)
		var fq := QuadMesh.new()
		fq.size = Vector2(0.9, wall_h * 0.92)
		_mesh(upright, fq, dark, Transform3D(b, Vector3((r + 0.25) * sin(a), wall_h * 0.46, (r + 0.25) * cos(a))))
		_mesh(upright, _cyl(0.05, wall_h + 0.15), wood, Transform3D(Basis.IDENTITY, Vector3(r * sin(a), (wall_h + 0.15) * 0.5, r * cos(a))))
		_line(upright, Vector3((r + 0.3) * sin(a), wall_h * 0.55, (r + 0.3) * cos(a)),
			Vector3((r + 0.15) * sin(a + sgn * 0.18), wall_h * 0.55, (r + 0.15) * cos(a + sgn * 0.18)), 0.015, rope)
	_line(upright, Vector3(-r * sin(door), wall_h + 0.08, r * cos(door)), Vector3(r * sin(door), wall_h + 0.08, r * cos(door)), 0.05, wood)
	# The roof: a low cone to a centre pole, open underneath, with ribs over it, a
	# rim where it meets the wall and a cap at the top.
	var roof_h := float(cfg.get("roof_h", 1.5))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = r + 0.3
	cone.height = roof_h
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = segs
	_mesh(upright, cone, roof_hide, Transform3D(Basis.IDENTITY, Vector3(0, wall_h + roof_h * 0.5 - 0.05, 0)))
	var apex := Vector3(0, wall_h + roof_h - 0.02, 0)
	for k in segs / 2:
		var a := TAU * (float(k) * 2.0) / segs
		var foot := Vector3((r + 0.32) * sin(a), wall_h - 0.06, (r + 0.32) * cos(a))
		var out := (foot - apex).cross(Vector3(cos(a), 0, -sin(a))).normalized() * 0.05
		_line(upright, apex + out, foot + out, 0.035, wood)
	var rim := CylinderMesh.new()
	rim.top_radius = r + 0.3
	rim.bottom_radius = r + 0.34
	rim.height = 0.14
	rim.radial_segments = segs
	rim.cap_top = false
	rim.cap_bottom = false
	_mesh(upright, rim, dark, Transform3D(Basis.IDENTITY, Vector3(0, wall_h - 0.1, 0)))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.08
	cap.bottom_radius = 0.42
	cap.height = 0.3
	cap.radial_segments = 8
	_mesh(upright, cap, dark, Transform3D(Basis.IDENTITY, apex + Vector3(0, 0.02, 0)))
	_mesh(upright, _cyl(0.06, wall_h + roof_h + 0.3), wood, Transform3D(Basis.IDENTITY, Vector3(0, (wall_h + roof_h + 0.3) * 0.5, 0)))
	_shape(body, _cyl_shape(0.1, wall_h + roof_h), Transform3D(Basis.IDENTITY, Vector3(0, (wall_h + roof_h) * 0.5, 0)))
	# Streamers off the top of the pole, in the rug's colours.
	if mats != null:
		for k in 2:
			var sq := QuadMesh.new()
			sq.size = Vector2(0.12, 0.7)
			var sb := Basis(Vector3.UP, k * 1.9 + rng.randf()) * Basis(Vector3.FORWARD, 0.5 + k * 0.3)
			_mesh(upright, sq, mats.cloth(accent if k == 0 else rug_col), Transform3D(sb, apex + Vector3(0.12, 0.05, 0)))
	# The heap it falls into (hidden until then): the roof flat on the ground.
	var heap := Node3D.new()
	heap.name = "Heap"
	heap.visible = false
	root.add_child(heap)
	var flat := cone.duplicate() as CylinderMesh
	flat.height = 0.35
	flat.top_radius = 0.6
	_mesh(heap, flat, roof_hide, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.3, 0.2, -0.2)))
	var heap_q := QuadMesh.new()
	heap_q.size = Vector2(2.2, 1.6)
	_mesh(heap, heap_q, dark, Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-1.2, 0.08, 1.1)))
	_mesh(heap, _cyl(0.06, 3.2), wood, Transform3D(Basis(Vector3.FORWARD, 1.45), Vector3(0, 0.12, 0.4)))
	_mesh(heap, _cyl(0.045, 2.0), wood, Transform3D(Basis(Vector3.UP, 1.1) * Basis(Vector3.FORWARD, 1.5), Vector3(-0.6, 0.1, -0.9)))
	t["heap"] = heap
	# Inside: a woven rug, a rock table with rock seats and cushions, a bedroll, the
	# chest, pots and a canister or two, a lamp hanging from the pole.
	if mats != null:
		var rq := PlaneMesh.new()
		rq.size = Vector2(r * 1.3, r * 1.15)
		_mesh(root, rq, CampTextures.rug(rug_col, accent), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.025, -0.2)))
	var table := Vector3(0.0, 0.0, -1.1)
	_mesh(root, _rock_mesh(0.32, 0.5, rng), rock, Transform3D(Basis.IDENTITY, table + Vector3(0, 0.25, 0)))
	_mesh(root, _box(Vector3(1.2, 0.14, 0.75)), rock, Transform3D(Basis(Vector3.UP, 0.08), table + Vector3(0, 0.57, 0)))
	_shape(body, _box_shape(Vector3(1.2, 0.64, 0.75)), Transform3D(Basis.IDENTITY, table + Vector3(0, 0.32, 0)))
	for seat: Vector3 in [Vector3(-1.0, 0, -1.0), Vector3(1.0, 0, -1.2), Vector3(0.2, 0, -2.0)]:
		_mesh(root, _rock_mesh(0.27, 0.44, rng), rock, Transform3D(Basis(Vector3.UP, seat.x), seat + Vector3(0, 0.22, 0)))
		_shape(body, _cyl_shape(0.27, 0.44), Transform3D(Basis.IDENTITY, seat + Vector3(0, 0.22, 0)))
		if mats != null:
			var cush := _cyl(0.24, 0.07)
			cush.radial_segments = 10
			_mesh(root, cush, mats.cloth(accent.darkened(0.25)), Transform3D(Basis.IDENTITY, seat + Vector3(0, 0.475, 0)))
	# On the table: a bowl and a pot.
	var clay: Material = CampTextures.clay(Color("#c47e50")) if mats != null else null
	_pot(root, table + Vector3(-0.3, 0.64, 0.1), 0.13, clay)
	var bowl := SphereMesh.new()
	bowl.radius = 0.14
	bowl.height = 0.12
	bowl.is_hemisphere = true
	bowl.radial_segments = 10
	bowl.rings = 3
	_mesh(root, bowl, clay, Transform3D(Basis(Vector3.RIGHT, PI), table + Vector3(0.3, 0.76, -0.1)))
	var bed := Vector3(-1.75, 0.0, 0.5)
	if mats != null:
		_mesh(root, _box(Vector3(0.85, 0.12, 1.9)), CampTextures.hide(hide_col.lightened(0.2)), Transform3D(Basis(Vector3.UP, 0.25), bed + Vector3(0, 0.06, 0)))
		_mesh(root, _box(Vector3(0.6, 0.14, 0.32)), mats.cloth(rug_col.darkened(0.2)), Transform3D(Basis(Vector3.UP, 0.25), bed + Vector3(0.18, 0.14, -0.75)))
		_mesh(root, _box(Vector3(0.8, 0.05, 0.7)), CampTextures.rug(accent.darkened(0.4), rug_col), Transform3D(Basis(Vector3.UP, 0.25), bed + Vector3(-0.02, 0.14, 0.45)))
	var chest := Vector3(1.75, 0.0, 0.1)
	var cb := Basis(Vector3.UP, -PI * 0.5)      # its front faces the middle of the tent
	_mesh(root, _box(Vector3(0.85, 0.5, 0.52)), wood, Transform3D(cb, chest + Vector3(0, 0.25, 0)))
	_shape(body, _box_shape(Vector3(0.85, 0.5, 0.52)), Transform3D(cb, chest + Vector3(0, 0.25, 0)))
	# Its iron bands.
	var iron: Material = CampTextures.canister(Color("#3a3634"), Color("#3a3634")) if mats != null else null
	for bx: float in [-0.3, 0.3]:
		_mesh(root, _box(Vector3(0.06, 0.52, 0.54)), iron, Transform3D(cb, chest + cb * Vector3(bx, 0.25, 0)))
	var hinge := Node3D.new()
	hinge.name = "Lid"
	root.add_child(hinge)
	hinge.transform = Transform3D(cb, chest + cb * Vector3(0, 0.5, -0.26))
	_mesh(hinge, _box(Vector3(0.88, 0.08, 0.54)), wood, Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0.27)))
	for bx: float in [-0.3, 0.3]:
		_mesh(hinge, _box(Vector3(0.06, 0.1, 0.56)), iron, Transform3D(Basis.IDENTITY, Vector3(bx, 0.04, 0.27)))
	t["lid"] = hinge
	# Beside the chest: a canister and a water jar.
	_canister(root, Transform3D(Basis.IDENTITY, chest + Vector3(0.1, 0, 0.85)), 0.2, 0.62, rng, mats)
	_pot(root, chest + Vector3(-0.05, 0, -0.75), 0.24, clay)
	t["inside"] = xf * Vector3(0, 0, -0.3)
	t["bed"] = xf * bed
	t["box"] = xf * (chest + Vector3(0, 0.4, 0))
	# A lamp hanging from the pole, lit only near the player.
	var lamp_at := Vector3(0.0, wall_h + 0.05, 0.12)
	_line(root, Vector3(0, wall_h + 0.5, 0.05), lamp_at + Vector3(0, 0.12, 0), 0.008, rope)
	if mats != null:
		var lantern := _cyl(0.07, 0.16)
		_mesh(root, lantern, iron, Transform3D(Basis.IDENTITY, lamp_at + Vector3(0, 0.1, 0)))
		var glass := _cyl(0.055, 0.12)
		var gm := mats.glow(Color(1.0, 0.7, 0.35))
		gm.emission_energy_multiplier = 2.0
		_mesh(root, glass, gm, Transform3D(Basis.IDENTITY, lamp_at - Vector3(0, 0.02, 0)))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 1.4
	lamp.omni_range = r + 1.8
	lamp.shadow_enabled = false
	lamp.position = lamp_at
	lamp.visible = false
	root.add_child(lamp)
	t["lamp"] = lamp
	return t


## Open or shut tent `i`'s chest lid (open = emptied).
func set_lid(i: int, open: bool) -> void:
	var lid: Node3D = tents[i].lid
	lid.rotation.x = -1.9 if open else 0.0


## Which tent the point is inside (in from its wall), or -1.
func tent_at(p: Vector3, margin: float = 0.4) -> int:
	for t in tents:
		var l: Vector3 = (t.xf as Transform3D).affine_inverse() * p
		if Vector2(l.x, l.z).length() < float(t.r) - margin and l.y > -1.0 and l.y < 3.0:
			return int(t.index)
	return -1


## The tent whose chest `p` is within `reach` of, or -1.
func chest_near(p: Vector3, reach: float = 1.6) -> int:
	for t in tents:
		if (t.box as Vector3).distance_to(p) <= reach:
			return int(t.index)
	return -1


func _on_tent_hit(i: int, amount: float, shooter: Node) -> void:
	var t: Dictionary = tents[i]
	tent_hit.emit(shooter, amount)
	if net_hit.is_valid():
		net_hit.call(i, amount, shooter)
		return
	if bool(t.down):
		return
	t.hp = float(t.hp) - amount
	if float(t.hp) <= 0.0:
		knock_down(i)


## Tent `i` falls in: the walls and roof become a heap, the walls stop being walls.
func knock_down(i: int) -> void:
	var t: Dictionary = tents[i]
	if bool(t.down):
		return
	t.down = true
	(t.upright as Node3D).visible = false
	(t.heap as Node3D).visible = true
	for cs in t.walls:
		(cs as CollisionShape3D).disabled = true
	if tents.all(func(x): return bool(x.down)) and not is_wrecked:
		is_wrecked = true
		wrecked.emit()


## Wrecked from the start (a save from inside the hours it takes to come back).
func show_wrecked() -> void:
	for t in tents:
		knock_down(int(t.index))


## Which tents are down: bit i for tent i (issue #402: what a LAN host sends).
func down_mask() -> int:
	var mask := 0
	for t in tents:
		if bool(t.down):
			mask |= 1 << int(t.index)
	return mask


## Issue #402: a guest's copy takes the host's word on which tents are down (all
## up again is the camp put back).
func net_down(mask: int) -> void:
	if mask == 0:
		if down_mask() != 0:
			rebuild()
		return
	for t in tents:
		if mask & (1 << int(t.index)) and not bool(t.down):
			knock_down(int(t.index))


## Back up: every tent standing and whole again.
func rebuild() -> void:
	is_wrecked = false
	for t in tents:
		t.down = false
		t.hp = float(cfg.get("tent_hp", 90.0))
		(t.upright as Node3D).visible = true
		(t.heap as Node3D).visible = false
		for cs in t.walls:
			(cs as CollisionShape3D).disabled = false


# ------------------------------------------------------------------ fire

func _firepit(at: Vector3, mats: LookMaterials) -> Dictionary:
	var root := Node3D.new()
	root.name = "Firepit"
	add_child(root)
	root.global_transform = _frame(at, at + NativeSteer._side(up))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 31
	var rock: Material = CampTextures.rock(Color("#5a524a")) if mats != null else null
	var wood: Material = CampTextures.wood(Color("#4a3220")) if mats != null else null
	var char_m: Material = CampTextures.earth(Color("#2a2420")) if mats != null else null
	# Ash and char under it, then a ring of stones, each set on the ground itself.
	var ash := CylinderMesh.new()
	ash.top_radius = 0.7
	ash.bottom_radius = 0.78
	ash.height = 0.04
	ash.radial_segments = 14
	_mesh(root, ash, char_m, Transform3D(Basis.IDENTITY, _ground_local(root, Vector3.ZERO) + Vector3(0, 0.01, 0)))
	var stones := 11
	for s in stones:
		var a := TAU * float(s) / stones + rng.randf_range(-0.1, 0.1)
		var at_l := _ground_local(root, Vector3(0.82 * sin(a), 0, 0.82 * cos(a)))
		var st := SphereMesh.new()
		st.radius = rng.randf_range(0.17, 0.24)
		st.height = st.radius * rng.randf_range(1.1, 1.5)
		st.radial_segments = 7
		st.rings = 3
		_mesh(root, st, rock, Transform3D(Basis(Vector3.UP, a), at_l + Vector3(0, st.height * 0.3, 0)))
	for k in 4:
		_mesh(root, _cyl(0.06, 1.0), wood, Transform3D(Basis(Vector3.UP, k * 0.8) * Basis(Vector3.RIGHT, 1.3), _ground_local(root, Vector3.ZERO) + Vector3(0, 0.14, 0)))
	# A spit across it on two forked sticks, a pot hung from it.
	for sgn: float in [-1.0, 1.0]:
		var foot := _ground_local(root, Vector3(1.05 * sgn, 0, 0))
		_line(root, foot, foot + Vector3(-0.05 * sgn, 1.25, 0), 0.03, wood)
		_line(root, foot + Vector3(-0.05 * sgn, 1.05, 0), foot + Vector3(0.08 * sgn, 1.32, 0.05), 0.02, wood)
	var bar_y := _ground_local(root, Vector3.ZERO).y + 1.22
	_line(root, Vector3(-1.25, bar_y, 0), Vector3(1.25, bar_y, 0), 0.025, wood)
	_line(root, Vector3(0.1, bar_y, 0), Vector3(0.1, bar_y - 0.45, 0), 0.006, wood)
	_pot(root, Vector3(0.1, bar_y - 0.72, 0), 0.17, CampTextures.canister(Color("#2e2a28"), Color("#2e2a28")) if mats != null else null)
	var flames: Array = []
	var fy := _ground_local(root, Vector3.ZERO).y
	if mats != null:
		for k in 3:
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.26 - k * 0.06
			c.height = 0.7 + k * 0.15
			c.radial_segments = 6
			c.rings = 1
			var col := Color("#ff7a1a") if k == 0 else (Color("#ffb03a") if k == 1 else Color("#ffe08a"))
			var fm := mats.glow(col)
			fm.emission_energy_multiplier = 3.0
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_color = col
			var f := _mesh(root, c, fm, Transform3D(Basis.IDENTITY, Vector3(0.05 * (k - 1), fy + 0.2 + c.height * 0.5, 0.04 * k)))
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flames.append(f)
		# Embers: a glowing bed in the middle.
		var em := mats.glow(Color("#ff5a10"))
		em.emission_energy_multiplier = 2.0
		var bed := CylinderMesh.new()
		bed.top_radius = 0.38
		bed.bottom_radius = 0.45
		bed.height = 0.05
		bed.radial_segments = 10
		_mesh(root, bed, em, Transform3D(Basis.IDENTITY, Vector3(0, fy + 0.05, 0))).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.28)
	light.light_energy = float(cfg.get("fire_energy", 1.8))
	light.omni_range = float(cfg.get("fire_range", 10.0))
	light.shadow_enabled = false
	light.position = Vector3(0, fy + 0.9, 0)
	light.visible = false
	root.add_child(light)
	return { "root": root, "light": light, "flames": flames }


## What a camp has lying about outside, between the tents: stacks of scavenged
## canisters, a woodpile, a drying rack hung with hides, water jars, spears leant on
## a tent, and a ring of stones round the edge. The bigger things are solid.
func _props(mats: LookMaterials) -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)
	root.global_transform = _frame(center, center + NativeSteer._side(up))
	var body := StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 101
	var wood: Material = CampTextures.wood(Color("#9a7048")) if mats != null else null
	var rock: Material = CampTextures.rock(Color(str(cfg.get("rock", "#6e6258"))).lightened(0.35)) if mats != null else null
	var clay: Material = CampTextures.clay(Color("#c47e50")) if mats != null else null
	var hide_col := Color(str(cfg.get("hide", "#a88a64")))
	var ring := float(cfg.get("ring_m", 9.0))
	var r := float(cfg.get("tent_radius", 3.0))
	var n := clampi(int(cfg.get("tents", 3)), 1, 6)
	var a0 := float(cfg.get("yaw_deg", 0.0)) * PI / 180.0
	# Between each pair of tents, in turn: canisters, the woodpile, the rack.
	for i in n:
		var a := a0 + TAU * (float(i) + 0.5) / float(n)
		var dir := _ring_dir(a)
		var at := dir * (ring * 0.95)
		var face := Basis(Vector3.UP, atan2(dir.x, dir.z))
		match i % 3:
			0:
				# A stack of canisters, one on its side.
				for k in 4:
					var off := face * Vector3(-0.8 + k * 0.5 + rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.2, 0.2))
					_canister(root, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _ground_local(root, at + off)), 0.26, rng.randf_range(0.75, 0.95), rng, mats)
				var lie := _ground_local(root, at + face * Vector3(0.1, 0, 0.75))
				_canister(root, Transform3D(face * Basis(Vector3.FORWARD, PI * 0.5), lie + Vector3(0, 0.26, 0)), 0.26, 0.9, rng, mats)
				_shape(body, _box_shape(Vector3(2.2, 0.9, 1.5)), Transform3D(face, _ground_local(root, at) + Vector3(0, 0.45, 0.25)))
				_canister(root, Transform3D(Basis.IDENTITY, _ground_local(root, at + face * Vector3(-0.5, 0, 0.1)) + Vector3(0, 0.9, 0)), 0.22, 0.6, rng, mats)
			1:
				# The woodpile.
				for k in 9:
					var row := k / 4
					var col := float(k % 4) - 1.5 + row * 0.5
					var l := Transform3D(face * Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)),
						_ground_local(root, at) + face * Vector3(0, 0.12 + row * 0.2, col * 0.22))
					_mesh(root, _cyl(rng.randf_range(0.08, 0.11), rng.randf_range(1.2, 1.6)), wood, l)
				_shape(body, _box_shape(Vector3(1.6, 0.6, 1.0)), Transform3D(face, _ground_local(root, at) + Vector3(0, 0.3, 0)))
				for k in 3:
					_pot(root, _ground_local(root, at + face * Vector3(1.1 + k * 0.45, 0, 0.4)), rng.randf_range(0.18, 0.26), clay)
			2:
				# A drying rack hung with hides.
				for sgn: float in [-1.0, 1.0]:
					var foot := _ground_local(root, at + face * Vector3(1.1 * sgn, 0, 0))
					_line(root, foot, foot + Vector3(0, 1.7, 0), 0.04, wood)
				var top := _ground_local(root, at) + Vector3(0, 1.65, 0)
				_line(root, top - face * Vector3(1.2, 0, 0), top + face * Vector3(1.2, 0, 0), 0.03, wood)
				for k in 3:
					var hq := QuadMesh.new()
					hq.size = Vector2(0.6, rng.randf_range(0.9, 1.2))
					var hc := hide_col.darkened(rng.randf_range(0.0, 0.3)).lerp(Color("#c8b490"), rng.randf() * 0.4)
					_mesh(root, hq, CampTextures.hide(hc) if mats != null else null,
						Transform3D(face * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)), top + face * Vector3(-0.7 + k * 0.7, -hq.size.y * 0.5, 0)))
				_shape(body, _box_shape(Vector3(2.3, 1.7, 0.2)), Transform3D(face, _ground_local(root, at) + Vector3(0, 0.85, 0)))
	# Spears leant on each tent's side.
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var tent := _ring_dir(a) * ring
		var foot := _ground_local(root, _ring_dir(a + 0.45) * ring)
		var lean := (tent - foot).slide(Vector3.UP).normalized() * 0.85
		for k in 2:
			var o := lean.cross(Vector3.UP).normalized() * (k * 0.3)
			_line(root, foot + o, foot + o + lean + Vector3(0, 2.0, 0), 0.022, wood)
			var tip := SphereMesh.new()
			tip.radius = 0.04
			tip.height = 0.28
			tip.radial_segments = 4
			tip.rings = 2
			var dir2 := (lean + Vector3(0, 2.0, 0)).normalized()
			var tb := Basis(Quaternion(Vector3.UP, dir2))
			_mesh(root, tip, rock, Transform3D(tb, foot + o + lean + Vector3(0, 2.0, 0) + dir2 * 0.1))
	# A ring of stones round the camp's edge, and a few logs to sit on by the fire.
	var edge := ring + r + 2.0
	for k in 22:
		var a := TAU * float(k) / 22.0 + rng.randf_range(-0.05, 0.05)
		var st := SphereMesh.new()
		st.radius = rng.randf_range(0.15, 0.3)
		st.height = st.radius * rng.randf_range(1.0, 1.4)
		st.radial_segments = 6
		st.rings = 3
		var p := _ground_local(root, _ring_dir(a) * edge)
		_mesh(root, st, rock, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, st.height * 0.25, 0)))
	for k in 3:
		var a := TAU * (float(k) + 0.25) / 3.0
		var d := _ring_dir(a)
		var p := _ground_local(root, d * 4.4)
		var lb := Basis(Vector3.UP, atan2(d.x, d.z)) * Basis(Vector3.FORWARD, PI * 0.5)
		_mesh(root, _cyl(0.17, 1.5), wood, Transform3D(lb, p + Vector3(0, 0.15, 0)))


## Lights on and the fire flickering only near the player (checked twice a second).
func tick(dt: float, ppos: Vector3) -> void:
	_t += dt
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = 0.5
		var near := ppos != Vector3.INF and ppos.distance_to(center) < lit_near
		if near != _near:
			_near = near
			for f in fires:
				(f.light as OmniLight3D).visible = near
			for t in tents:
				(t.lamp as OmniLight3D).visible = near
	if not _near:
		return
	for f in fires:
		var k := 0
		for fl in f.flames:
			var s := 1.0 + 0.16 * sin(_t * (9.0 + k * 3.7) + k) + 0.08 * sin(_t * 23.0 + k * 2.0)
			(fl as Node3D).scale = Vector3(1.0, s, 1.0)
			k += 1
		(f.light as OmniLight3D).light_energy = float(cfg.get("fire_energy", 1.8)) * (0.85 + 0.15 * sin(_t * 11.0))


func lights_on() -> bool:
	return _near


# ------------------------------------------------------------------ bits

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # thin hide: no striping inside
	mi.transform = xf
	parent.add_child(mi)
	return mi


func _shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	return cs


## Round the ring at angle `a` in the frame _frame(center, center + side) gives
## (build() lays the tents out with side * cos(a) + fwd * sin(a)).
static func _ring_dir(a: float) -> Vector3:
	return Vector3(-sin(a), 0.0, cos(a))


## Ground under a point in `root`'s frame (x, z), in that frame.
func _ground_local(root: Node3D, l: Vector3) -> Vector3:
	var w := root.global_transform * Vector3(l.x, 0.0, l.z)
	var g: Vector3 = director._on_ground(w) if director != null else w
	return root.global_transform.affine_inverse() * g


## A thin rod from `a` to `b` (a pole, a rope, a spear).
func _line(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var c := _cyl(radius, d.length())
	c.radial_segments = 5
	var basis := Basis(Quaternion(Vector3.UP, d.normalized())) if d.length() > 0.001 else Basis.IDENTITY
	return _mesh(parent, c, mat, Transform3D(basis, (a + b) * 0.5))


## A rough-cut rock: an eight-sided slab, a little out of round.
func _rock_mesh(radius: float, height: float, rng: RandomNumberGenerator) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius * rng.randf_range(0.82, 0.95)
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 7
	c.rings = 1
	return c


## A clay pot standing at `at` (its foot): a round belly and a neck.
func _pot(parent: Node3D, at: Vector3, radius: float, mat: Material) -> void:
	var belly := SphereMesh.new()
	belly.radius = radius
	belly.height = radius * 1.7
	belly.radial_segments = 10
	belly.rings = 5
	_mesh(parent, belly, mat, Transform3D(Basis.IDENTITY, at + Vector3(0, radius * 0.85, 0)))
	var neck := CylinderMesh.new()
	neck.top_radius = radius * 0.5
	neck.bottom_radius = radius * 0.4
	neck.height = radius * 0.45
	neck.radial_segments = 10
	neck.rings = 1
	_mesh(parent, neck, mat, Transform3D(Basis.IDENTITY, at + Vector3(0, radius * 1.8, 0)))


const CAN_PAINT := [["#4f7a72", "#c9a23a"], ["#8a3a2a", "#d8cfc0"], ["#5e6a3e", "#1e1e1e"], ["#b8913a", "#3a3a3a"]]

## A scavenged canister: a painted drum with rolled rims and a cap. `xf` puts its
## foot (its axis is its +Y).
func _canister(parent: Node3D, xf: Transform3D, radius: float, height: float, rng: RandomNumberGenerator, mats: LookMaterials) -> void:
	var paint: Array = CAN_PAINT[rng.randi() % CAN_PAINT.size()]
	var m: Material = CampTextures.canister(Color(str(paint[0])), Color(str(paint[1]))) if mats != null else null
	var drum := CylinderMesh.new()
	drum.top_radius = radius
	drum.bottom_radius = radius
	drum.height = height
	drum.radial_segments = 12
	drum.rings = 1
	var mi := _mesh(parent, drum, m, xf * Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0)))
	mi.visibility_range_end = 220.0
	var metal: Material = CampTextures.canister(Color("#4a4846"), Color("#4a4846")) if mats != null else null
	for y: float in [0.02, height - 0.02]:
		var rim := _cyl(radius + 0.015, 0.035)
		rim.radial_segments = 12
		_mesh(parent, rim, metal, xf * Transform3D(Basis.IDENTITY, Vector3(0, y, 0))).visibility_range_end = 120.0
	var cap := _cyl(radius * 0.22, 0.06)
	_mesh(parent, cap, metal, xf * Transform3D(Basis.IDENTITY, Vector3(radius * 0.5, height + 0.03, 0))).visibility_range_end = 120.0


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


static func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c
