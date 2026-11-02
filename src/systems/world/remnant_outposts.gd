class_name RemnantOutposts
extends Node3D
## The Remnant's desert outposts: three out the front gate (issue #64), near, mid
## and far, and four round the other sides of the town (issue #187: north, south,
## west, southwest), each a little different. Their footprints are world data (landmarks
## in content/core/worlds/port_desert.json, buildings in
## content/core/locations/remnant_outpost_*.json), so ships and speeders already
## collide with them. This node adds, for each one:
##   - the ground: a heightmap collider of the sand round it, so the people there
##     stand on something even when the town's terrain collider (which follows the
##     player) is far away,
##   - the look: one dark, panelled metal building in black and red (the far ones
##     add a comms mast and a lookout), and a cargo ship parked beside it,
##   - issue #76: crates, canisters and drums lying about ("props"), solid, so
##     they are cover,
##   - three troopers (soldiers/outpost_trooper.json) for the town's Garrison, and
##     the routes of its droids: an assassin droid, a floating droid and a cargo
##     droid (DroidController reads droid_specs()),
##   - the bounty target: whoever Oda's contract names (WorldState.bounty_target)
##     stands at the outpost it names, in red. Killing them is
##     WorldState.on_bounty_killed().
## Before the fleet is beaten they are like the town's garrison (standing decides);
## after, they shoot on sight (Story.remnant_hostile, read by the Garrison).
## Dead troopers come back after a few minutes (the town's respawn rule).
##
## Issue #187: an outpost changes hands (Territory). Kill every trooper at one and
## the locals have it: their desert guards (territory.json "outposts" posts) and a
## white assassin droid move in once you are out of sight (or after move_in_s),
## run by the outpost's own Townsfolk. When the Remnant take it back their
## troopers and droids return the same way, once you are swap_dist away. Issue
## #393: the outpost's red band, door frame, lamps and banner turn the locals'
## green with the swap, and back (LookMaterials.repaint, this outpost's group).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const GROUND_HALF := 40.0          ## metres of sand collider either side of the anchor
const GROUND_STEP := 2.0
const WAKE_DIST := 320.0           ## bodies further than this from the player sleep

var demo                           ## town_demo.gd
var ground: WorldGround
var outposts: Array = []           ## { id, label, origin, yaw, cfg }
var guards: Array = []             ## NpcBody at the outposts (also in demo.npcs)
var garrisons: Dictionary = {}     ## outpost id -> its own Garrison (the town builds them)
var folks: Dictionary = {}         ## issue #187: outpost id -> the Townsfolk running the locals there
var held_by: Array = []            ## issue #187: NpcBody, the locals' guards at the outposts (also in demo.locals)
var swaps := 0                     ## issue #187: outposts that changed hands in this scene, for traces
var target: NpcBody                ## the bounty target, while one is out there
var target_run := -1               ## which contract it is
var bounty_kills := 0              ## for tests and traces


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "RemnantOutposts"


## Read the outposts and build them, troopers included. Called by the town before
## its Garrison is set up (the troopers join it).
func build() -> void:
	while not build_step():
		pass


var _cc: CoreContent                ## issue #121: the content a staged build reads from
var _queue: Array = []              ## issue #162: the pieces still to build, in order (Callables)


## Issue #121: build the next piece of an outpost. True once all are built. A
## staged handoff calls this once a frame. Issue #162: a piece is the ground,
## the nav, the look, the ship or one trooper, not a whole outpost (~55 ms).
func build_step() -> bool:
	if _cc == null:
		_cc = CoreContent.new()
		_cc.load_from()
		var world := _cc.world_for_town("port_town")
		for id in Story.OUTPOSTS:
			_queue.append(_build_outpost.bind(str(id), world))
	if _queue.is_empty():
		return true
	(_queue.pop_front() as Callable).call()
	return _queue.is_empty()


func _build_outpost(id: String, world: Dictionary) -> void:
	for lm in world.get("landmarks", []):
		if str(lm.get("location", "")) != id:
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		var loc: Dictionary = _cc.get_location(id)
		var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
		var o := { "id": id, "label": str(loc.get("label", id)), "cfg": loc, "side": Territory.owner(id), "wait": 0.0,
			"origin": Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z), "yaw": yaw }
		# Issue #77: on the home planet's ball the outpost stands along the ground's
		# up there, in the same frame WorldGround gives its buildings.
		var sp := ground.sphere()
		if sp != null:
			o.origin = sp.surface_at(at.x, at.z)
		o.xf = Transform3D(PlanetSphere.tilt_to(ground.up_at(o.origin)) * Basis(Vector3.UP, yaw), o.origin)
		outposts.append(o)
		var parts: Array = [_build_ground.bind(o), _build_nav.bind(o), _build_props.bind(o)]
		if demo.use_look:
			parts.append(_dress.bind(o))
		parts.append(_park_ship.bind(o))
		if o.side == Territory.LOCALS:
			var posts: Dictionary = Territory.cfg().get("outposts", {}).get("posts", {})
			for p in posts:
				parts.append(_add_local.bind(o, str(p), str(posts[p])))
		else:
			for p in TROOPER_POSTS:
				parts.append(_add_guard.bind(o, p))
		_queue = parts + _queue          # this outpost's pieces next, then the others


func outpost(id: String) -> Dictionary:
	for o in outposts:
		if str(o.id) == id:
			return o
	return {}


## A point from an outpost's location file, in the world, on the sand.
func world_point(o: Dictionary, local) -> Vector3:
	var lp: Vector3 = local if local is Vector3 else WorldGround._v3(local)
	var p: Vector3 = (o.xf as Transform3D) * Vector3(lp.x, 0.0, lp.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))   # on the sand, along up
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


func point(o: Dictionary, key: String) -> Vector3:
	return world_point(o, o.cfg.get("points", {}).get(key, [0, 0, 0]))


## The droids each outpost keeps: where they walk. "patrol" (the assassin's) and
## "routes": every point list in the location's points by name (issue #76: the
## floating droid's "floater", the cargo droid's "cargo").
func droid_specs() -> Array:
	var out: Array = []
	for o in outposts:
		var routes := {}
		var pts: Dictionary = o.cfg.get("points", {})
		for k in pts:
			if pts[k] is Array and not (pts[k] as Array).is_empty() and pts[k][0] is Array:
				routes[str(k)] = (pts[k] as Array).map(func(p): return world_point(o, p))
		out.append({ "outpost": o.id, "patrol": routes.get("patrol", []), "routes": routes, "origin": o.origin })
	return out


# ------------------------------------------------------------------ people

const TROOPER_POSTS := ["guard_a", "guard_b", "guard_c"]

func _add_guard(o: Dictionary, key: String) -> NpcBody:
	var here := point(o, key)
	var face: Vector3 = here + (here - (o.origin as Vector3)).normalized()      # looking out, away from the building
	var g: NpcBody = demo.make_soldier("outpost_trooper", here, atan2(face.x - here.x, face.z - here.z),
		"%s/%s" % [o.id, key], "npc:%s/%s" % [o.id, key])
	if g == null:
		return null
	adopt(g, str(o.id))
	guards.append(g)
	return g


## Issue #187: one of the locals' guards on an outpost post, facing out like a trooper.
func _add_local(o: Dictionary, key: String, soldier: String) -> NpcBody:
	var here := point(o, key)
	var face: Vector3 = here + (here - (o.origin as Vector3)).normalized()
	var g: NpcBody = demo.make_soldier(soldier, here, atan2(face.x - here.x, face.z - here.z),
		"%s/%s" % [o.id, key], "npc:%s/locals/%s#%d" % [o.id, key, WorldState.count("outposts_taken")])
	if g == null:
		return null
	adopt(g, str(o.id))
	held_by.append(g)
	return g


## The people standing at outpost `o` for one side, alive or not.
func people(o: Dictionary, side: String) -> Array:
	var list: Array = held_by if side == Territory.LOCALS else guards
	return list.filter(func(g): return is_instance_valid(g) and str(g.get_meta("outpost", "")) == str(o.id))


func _alive_at(o: Dictionary, side: String) -> int:
	return people(o, side).filter(func(g): return not g.dead).size()


## Outposts sleep their people while the player is far; who holds each one is
## checked every frame (three of them: nothing to it).
func _tick_control(dt: float, p: Node3D) -> void:
	for o in outposts:
		var id := str(o.id)
		var want := Territory.owner(id)
		var away: float = p.global_position.distance_to(o.origin) if p != null else INF
		if want == o.side:
			o.wait = 0.0
			if not people(o, o.side).is_empty() and _alive_at(o, o.side) == 0:
				if o.side == Territory.REMNANT:
					Territory.take(id)          # every trooper dead: the locals have it
				else:
					Territory.guards_lost(id)   # the locals' guards dead: the Remnant will be back
			if o.side == Territory.LOCALS and Territory.supply_out() == id and away <= Territory.n("supply_reach", 25.0):
				var pay := Territory.deliver(id)
				_toast(Territory.line("supplied") % [o.label, pay])
			continue
		o.wait = float(o.wait) + dt
		# Change hands out of sight; the locals also walk in while you watch.
		if away > Territory.n("swap_dist", 110.0) or (want == Territory.LOCALS and float(o.wait) >= Territory.n("move_in_s", 30.0)):
			swap(o, want)


## Outpost `o` is `side`'s now: the other side's people and droids go, this side's come.
func swap(o: Dictionary, side: String) -> void:
	var id := str(o.id)
	var p: Node3D = demo._player if demo != null else null
	var seen: bool = p != null and p.global_position.distance_to(o.origin) <= Territory.n("swap_dist", 110.0)
	for g in people(o, o.side):
		if g.dead and seen:
			continue                       # the fallen stay where they fell while you are looking
		_drop(g, id)
	var g0 = garrisons.get(id, null)
	if g0 != null:
		g0.respawns = g0.respawns.filter(func(r): return str(r.get("outpost", "")) != id)
	o.side = side
	o.wait = 0.0
	swaps += 1
	if demo.use_look:
		demo._flat_mats().repaint(side, id)      # issue #393: the band, door frame, lamps and banner
	if side == Territory.LOCALS:
		var posts: Dictionary = Territory.cfg().get("outposts", {}).get("posts", {})
		var mine: Array = []
		for k in posts:
			var g := _add_local(o, str(k), str(posts[k]))
			if g != null:
				mine.append(g)
		var folk = folks.get(id, null)
		if folk == null:
			folks[id] = demo.make_townsfolk("Locals_" + id, mine)
		else:
			for g in mine:
				folk.add_member(g)
		_toast(Territory.line("taken") % o.label)
	else:
		var mine: Array = []
		for k in TROOPER_POSTS:
			var g := _add_guard(o, k)
			if g != null:
				mine.append(g)
		var gar = garrisons.get(id, null)
		if gar == null:
			garrisons[id] = demo.make_outpost_garrison(o, mine)
		else:
			for g in mine:
				gar.add_member(g)
		_toast(Territory.line("retaken") % o.label)
	if demo.droids != null:
		demo.droids.clear_outpost_units(id)
		demo.droids.build_outpost_units(id)


## One body leaves outpost `id` for good.
func _drop(g: NpcBody, id: String) -> void:
	var gar = garrisons.get(id, null)
	if gar != null:
		gar.remove_member(g)
	var folk = folks.get(id, null)
	if folk != null:
		folk.remove_member(g)
	guards.erase(g)
	held_by.erase(g)
	demo.npcs.erase(g)
	demo.locals.erase(g)
	g.queue_free()


func _toast(text: String) -> void:
	if text != "" and demo.gear != null and demo.gear.hud != null:
		demo.gear.hud.toast(text, 5.0)


## Outpost guards use the shared map, which includes a small terrain tile around
## each outpost; they still sleep while the player is far away.
func adopt(g: NpcBody, outpost_id: String) -> void:
	g.nav = demo.nav
	g.set_meta("outpost", outpost_id)


func _physics_process(dt: float) -> void:
	_sync_target()
	var p: Node3D = demo._player if demo != null else null
	if p == null:
		return
	_tick_control(dt, p)
	for g in guards + held_by + ([target] if target != null else []):
		if is_instance_valid(g) and not g.dead:
			var far: bool = g.global_position.distance_to(p.global_position) > WAKE_DIST
			g.process_mode = Node.PROCESS_MODE_DISABLED if far else Node.PROCESS_MODE_INHERIT
	guards = guards.filter(func(g): return is_instance_valid(g))
	held_by = held_by.filter(func(g): return is_instance_valid(g))


## Put the contract's officer at its outpost, or take them away when the contract
## is gone (a story reset).
func _sync_target() -> void:
	var b := WorldState.bounty_target()
	var alive := target != null and is_instance_valid(target) and not target.dead
	if b.is_empty():
		if alive:
			_drop_target()
		return
	if alive and target_run == int(b.run):
		return
	if alive:
		_drop_target()
	var o := outpost(str(b.outpost))
	if not o.is_empty():
		spawn_target(o, b)


func spawn_target(o: Dictionary, b: Dictionary) -> NpcBody:
	var here := point(o, "target")
	var t: NpcBody = demo.make_soldier("bounty_target", here, float(o.yaw) - PI * 0.5, "%s/target" % o.id, str(b.key))
	if t == null:
		return null
	adopt(t, str(o.id))
	t.set_meta("bounty", int(b.run))
	t.died.connect(_on_target_died.bind(t))
	var g = garrisons.get(str(o.id), demo.garrison)
	if g != null:
		g.add_member(t)
	target = t
	target_run = int(b.run)
	return t


func _drop_target() -> void:
	var g = garrisons.get(str(target.get_meta("outpost", "")), demo.garrison)
	if g != null:
		g.remove_member(target)
	demo.npcs.erase(target)
	target.queue_free()
	target = null


func _on_target_died(t: NpcBody) -> void:
	if int(t.get_meta("bounty", -1)) != int(WorldState.bounty.get("run", -2)):
		return
	bounty_kills += 1
	WorldState.on_bounty_killed()
	if demo.gear != null and demo.gear.hud != null:
		demo.gear.hud.toast(str(Story.bounty_cfg().get("killed_toast", "%s is dead.")) % t.display_name, 5.0)


# ------------------------------------------------------------------ ground

## Bake only this outpost's clearing, not the whole planet. Geometry uses the same
## terrain height source as the collision and the outpost's tangent frame for local
## ground-up on the spherical home world.
func _build_nav(o: Dictionary) -> void:
	if demo.nav == null or demo.terrain == null:
		return
	var obstructions: Array = []
	for b in o.cfg.get("buildings", []):
		var size := WorldGround._v3(b.get("size", [1, 1, 1]))
		var pos := WorldGround._v3(b.get("position", [0, 0, 0]))
		var outline := PackedVector3Array([
			Vector3(pos.x - size.x * 0.5, 0.0, pos.z - size.z * 0.5),
			Vector3(pos.x + size.x * 0.5, 0.0, pos.z - size.z * 0.5),
			Vector3(pos.x + size.x * 0.5, 0.0, pos.z + size.z * 0.5),
			Vector3(pos.x - size.x * 0.5, 0.0, pos.z + size.z * 0.5),
		])
		obstructions.append({ "outline": outline, "bottom": pos.y, "height": size.y + 1.0 })
	for pr in props(o):
		var r: float = pr.radius
		var at: Vector3 = pr.at
		obstructions.append({ "outline": PackedVector3Array([at + Vector3(-r, 0, -r), at + Vector3(r, 0, -r),
			at + Vector3(r, 0, r), at + Vector3(-r, 0, r)]), "bottom": 0.0, "height": float(pr.height) + 0.5 })
	demo.nav.add_terrain_region(demo.terrain, o.origin, GROUND_HALF, GROUND_STEP,
		o.xf, obstructions)

## The sand round the outpost as a heightmap, at the terrain's own heights.
func _build_ground(o: Dictionary) -> void:
	var n := int(GROUND_HALF * 2.0 / GROUND_STEP) + 1
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var c: Vector3 = o.origin
	for j in n:
		for i in n:
			var x := c.x - GROUND_HALF + i * GROUND_STEP
			var z := c.z - GROUND_HALF + j * GROUND_STEP
			heights[j * n + i] = ground.terrain.height_at(x, z)
	hm.map_data = heights
	var body := StaticBody3D.new()
	body.name = "Ground_" + str(o.id)
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(GROUND_STEP, 1.0, GROUND_STEP)
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(c.x, 0.0, c.z)


# ------------------------------------------------------------------ the look

## Issue #76: cleaner and more metallic, same footprint. Panelled dark metal walls
## (the hull shader, a little sand at the foot), steel corner posts and ribs, a
## black roof and plinth, a red band and door frame, a lit door, vents, a roof
## unit, red corner lamps and a banner. look.mast: a comms mast on the roof;
## look.tower: a lookout at one corner.
func _dress(o: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var y0: float = (o.origin as Vector3).y
	var wall := mats._shader(LookMaterials.HULL, "outpost_wall_%s" % y0, {
		"sand_y": y0 - 3.5, "panel_size": 1.5, "marking_y": -1000.0,
		"metal": Color("#34373d"), "metal_light": Color("#4a4e55"), "scorch": Color("#2f3238"),
		"sand": Color("#b89468"), "metal_scale": 0.8, "rough_add": 0.05 })
	var black := mats.flat(Color("#141416"), 0.55, 0.4)
	var red := mats.faction_flat("mark", str(o.id), 0.6, 0.2)       # issue #393: this outpost's own
	var steel := mats.flat(Color("#5d6168"), 0.35, 0.75)
	var grille := mats.flat(Color("#0c0c0e"), 0.7, 0.5)
	var lamp := mats.faction_glow("lamp", str(o.id))
	var look: Dictionary = o.cfg.get("look", {})
	for b in o.cfg.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		var hx := s.x * 0.5
		var hz := s.z * 0.5
		# On a slope the walls run down to the lowest sand under them, so no edge floats.
		var skirt := 1.0 + _sink(o, c, hx + 0.2, hz + 0.2)
		_mesh(o, _box(s + Vector3(0, skirt, 0)), wall, c + Vector3(0, (s.y - skirt) * 0.5, 0))
		_mesh(o, _box(Vector3(s.x + 0.6, 0.35, s.z + 0.6)), black, c + Vector3(0, s.y + 0.17, 0))
		_mesh(o, _box(Vector3(s.x + 0.3, 0.5 + skirt - 1.0, s.z + 0.3)), black, c + Vector3(0, 0.1 - (skirt - 1.0) * 0.5, 0))
		_mesh(o, _box(Vector3(s.x + 0.04, 0.3, s.z + 0.04)), red, c + Vector3(0, s.y - 0.6, 0))
		# Corner posts, and steel ribs down the long sides.
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_mesh(o, _box(Vector3(0.34, s.y + 0.1, 0.34)), steel, c + Vector3(hx * sx, s.y * 0.5, hz * sz))
		var ribs := maxi(1, int(s.x / 2.4))
		for i in range(1, ribs):
			var x := -hx + s.x * float(i) / float(ribs)
			for sz in [-1.0, 1.0]:
				_mesh(o, _box(Vector3(0.14, s.y - 0.4, 0.1)), steel, c + Vector3(x, s.y * 0.5, (hz + 0.03) * sz))
		# The door, toward the town: a red frame, a dark door with a seam, a step, a lamp over it.
		_mesh(o, _box(Vector3(0.14, 2.5, 1.8)), red, c + Vector3(hx + 0.02, 1.25, 0))
		_mesh(o, _box(Vector3(0.16, 2.2, 1.4)), black, c + Vector3(hx + 0.06, 1.1, 0))
		_mesh(o, _box(Vector3(0.17, 2.1, 0.03)), steel, c + Vector3(hx + 0.07, 1.1, 0))
		var step := 0.18 + _sink(o, c + Vector3(hx + 0.4, 0, 0), 0.4, 1.0)
		_mesh(o, _box(Vector3(0.8, step, 2.0)), steel, c + Vector3(hx + 0.4, 0.18 - step * 0.5, 0))
		_mesh(o, _box(Vector3(0.22, 0.12, 0.7)), mats.glow(Color("#ffb04a")), c + Vector3(hx + 0.12, 2.75, 0))
		_mesh(o, _box(Vector3(0.05, 2.6, 0.9)), red, c + Vector3(hx + 0.05, s.y - 1.7, hz - 0.9))
		# Vents: two on the back, one on each side.
		for v in [Vector3(-hx - 0.05, 1.4, -hz * 0.45), Vector3(-hx - 0.05, 1.4, hz * 0.45)]:
			_vent(o, c + v, Basis.IDENTITY, grille, steel)
		for sz in [-1.0, 1.0]:
			_vent(o, c + Vector3(-hx * 0.35, 1.9, (hz + 0.05) * sz), Basis(Vector3.UP, PI * 0.5), grille, steel)
		# Red lamps at the front corners of the roof.
		for sz in [-1.0, 1.0]:
			_mesh(o, _box(Vector3(0.18, 0.18, 0.18)), lamp, c + Vector3(hx + 0.1, s.y + 0.45, (hz + 0.1) * sz))
		# A roof unit with a fan and a hatch.
		var ru := c + Vector3(hx * 0.3, s.y + 0.35, -hz * 0.35)
		_mesh(o, _box(Vector3(1.4, 0.6, 1.0)), steel, ru + Vector3(0, 0.3, 0))
		_mesh(o, _cyl(0.38, 0.04), grille, ru + Vector3(0, 0.62, 0))
		_mesh(o, _box(Vector3(0.9, 0.12, 0.9)), black, c + Vector3(-hx * 0.4, s.y + 0.41, hz * 0.3))
		if bool(look.get("mast", false)):
			_mesh(o, _cyl(0.12, 6.0), steel, c + Vector3(-s.x * 0.25, s.y + 3.0, -s.z * 0.25))
			_mesh(o, _box(Vector3(1.6, 0.1, 0.1)), steel, c + Vector3(-s.x * 0.25, s.y + 5.4, -s.z * 0.25))
			_mesh(o, _box(Vector3(0.25, 0.25, 0.25)), lamp, c + Vector3(-s.x * 0.25, s.y + 6.1, -s.z * 0.25))
		else:
			_mesh(o, _cyl(0.04, 1.6), steel, c + Vector3(-hx + 0.5, s.y + 1.1, -hz + 0.5))
		if bool(look.get("tower", false)):
			var t := c + Vector3(-hx - 1.2, 0, hz + 1.2)
			for dx in [-1.0, 1.0]:
				for dz in [-1.0, 1.0]:
					_mesh(o, _box(Vector3(0.25, 7.0, 0.25)), black, t + Vector3(dx, 3.5, dz))
			_mesh(o, _box(Vector3(2.8, 0.25, 2.8)), steel, t + Vector3(0, 7.0, 0))
			_mesh(o, _box(Vector3(2.8, 0.9, 0.12)), red, t + Vector3(0, 7.5, 1.35))
	# The light over the door, so the outpost reads at night.
	var light := OmniLight3D.new()
	light.light_color = Color("#ff9a50")
	light.light_energy = 1.2
	light.omni_range = 7.0
	add_child(light)
	var b0: Dictionary = (o.cfg.get("buildings", []) as Array).front()
	var s0 := WorldGround._v3(b0.get("size", [1, 1, 1]))
	light.global_position = (o.xf as Transform3D) * (WorldGround._v3(b0.get("position", [0, 0, 0])) + Vector3(s0.x * 0.5 + 0.8, 2.6, 0))
	mats.repaint(str(o.side), str(o.id))         # issue #393: painted for whoever holds it now


## How far the sand falls below the outpost's floor (local y = 0) at the corners and
## edge midpoints of a footprint centred at `c` (local), or 0.
func _sink(o: Dictionary, c: Vector3, hx: float, hz: float) -> float:
	var inv := (o.xf as Transform3D).affine_inverse()
	var low := 0.0
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			low = minf(low, (inv * world_point(o, Vector3(c.x + hx * sx, 0, c.z + hz * sz))).y - c.y)
	return -low


## A vent grille facing out of a wall (its basis turns +X to the wall's normal).
func _vent(o: Dictionary, at: Vector3, basis: Basis, grille: Material, frame: Material) -> void:
	_mesh(o, _box(Vector3(0.08, 0.6, 1.0)), frame, at, basis)
	for k in 3:
		_mesh(o, _box(Vector3(0.1, 0.07, 0.86)), grille, at + basis * Vector3(0.0, -0.18 + k * 0.18, 0.0), basis)


# ------------------------------------------------------------------ props (issue #76)

const PROP_SIZE := {                ## kind -> [radius (half width), height]: crate is a box
	"crate": [0.5, 0.9], "canister": [0.28, 1.0], "drum": [0.38, 0.95],
}


## The outpost's crates, canisters and drums ("props" in its location file), each
## { kind, at (local, on the sand), yaw, lying, height, radius }; a stack is one per crate.
func props(o: Dictionary) -> Array:
	var out: Array = []
	for pr in o.cfg.get("props", []):
		var kind := str(pr.get("kind", "crate"))
		var size: Array = PROP_SIZE.get(kind, PROP_SIZE.crate)
		var lp := WorldGround._v3(pr.get("at", [0, 0, 0]))
		var at := (o.xf as Transform3D).affine_inverse() * world_point(o, lp)   # sitting on the sand
		var lying := bool(pr.get("lying", false))
		var yaw := deg_to_rad(float(pr.get("yaw", 0.0)))
		var base := 0.0
		for k in maxi(1, int(pr.get("stack", 1))):
			var shrink := 1.0 - 0.12 * k
			var h := float(size[1]) * shrink
			out.append({ "kind": kind, "at": at, "yaw": yaw + 0.35 * k, "lying": lying, "level": k,
				"radius": float(size[0]) * shrink, "height": h, "base": base })
			base += h
	return out


## The props as solid shapes (always: cover with or without the look), and their
## looks when the town is dressed.
func _build_props(o: Dictionary) -> void:
	var list := props(o)
	if list.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Props_" + str(o.id)
	add_child(body)
	body.global_transform = o.xf
	var mats: LookMaterials = demo._flat_mats() if demo.use_look else null
	for pr in list:
		var xf := _prop_xf(pr)
		var cs := CollisionShape3D.new()
		var r: float = pr.radius
		var h: float = pr.height
		if str(pr.kind) == "crate":
			var bx := BoxShape3D.new()
			bx.size = Vector3(r * 2.0, h, r * 2.0)
			cs.shape = bx
		else:
			var cy := CylinderShape3D.new()
			cy.radius = r
			cy.height = h
			cs.shape = cy
		cs.transform = xf
		body.add_child(cs)
		if mats != null:
			_prop_look(body, pr, xf, mats)


## Where a prop's centre sits, in the outpost's frame: turned by its yaw, a lying
## one tipped onto its side, a stacked one on the one below.
func _prop_xf(pr: Dictionary) -> Transform3D:
	var b := Basis(Vector3.UP, float(pr.yaw))
	var lift: float = float(pr.base) + float(pr.height) * 0.5
	if bool(pr.lying):
		b = b * Basis(Vector3.RIGHT, PI * 0.5)
		lift = float(pr.radius)
	return Transform3D(b, (pr.at as Vector3) + Vector3(0, lift, 0))


func _prop_look(parent: Node3D, pr: Dictionary, xf: Transform3D, mats: LookMaterials) -> void:
	var r: float = pr.radius
	var h: float = pr.height
	var add := func(mesh: Mesh, mat: Material, local: Transform3D) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.transform = xf * local
		parent.add_child(mi)
	match str(pr.kind):
		"crate":
			var body_mat := mats.flat(Color("#3d4046") if int(pr.level) % 2 == 0 else Color("#2a2c30"), 0.5, 0.55)
			var band := mats.flat(Color("#1a1a1c"), 0.6, 0.4)
			add.call(_box(Vector3(r * 2.0, h, r * 2.0)), body_mat, Transform3D.IDENTITY)
			for y in [-h * 0.36, h * 0.36]:
				add.call(_box(Vector3(r * 2.04, 0.08, r * 2.04)), band, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)))
			add.call(_box(Vector3(r * 0.9, h * 0.25, 0.02)), mats.flat(Color("#a81e1a"), 0.7), Transform3D(Basis.IDENTITY, Vector3(0, 0, r + 0.01)))
		"canister":
			var shell := mats.flat(Color("#4f535a"), 0.35, 0.8)
			add.call(_cyl(r, h * 0.82), shell, Transform3D(Basis.IDENTITY, Vector3(0, -h * 0.05, 0)))
			add.call(_cyl(r * 0.55, h * 0.14), mats.flat(Color("#1a1a1c"), 0.5, 0.6), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.42, 0)))
			add.call(_cyl(r * 1.02, 0.1), mats.flat(Color("#c8a02a"), 0.6, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, h * 0.12, 0)))
		"drum":
			add.call(_cyl(r, h), mats.flat(Color("#202226"), 0.55, 0.5), Transform3D.IDENTITY)
			for y in [-h * 0.3, h * 0.3]:
				add.call(_cyl(r * 1.03, 0.06), mats.flat(Color("#8a1a16"), 0.6, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, y, 0)))


## The outpost's ship (the location's "ship"; issue #76: the Remnant's dark
## interceptor or freighter): its model on the sand at the ship point, or a bare
## node in the greybox. The pilot makes it a berth you can fly (its own hull is
## what you bump into); boarding it sets off this outpost's alarm.
func _park_ship(o: Dictionary) -> void:
	var ship_id := str(o.cfg.get("ship", ""))
	var look_id := str(_cc.get_ship(ship_id).get("look", ""))
	if look_id == "":
		return
	var at := point(o, "ship")
	var b: Basis = (o.xf as Transform3D).basis * Basis(Vector3.UP, PI * 0.5)
	var ship: Node3D
	if demo.use_look:
		ship = ShipKit.new().build(look_id)
		add_child(ship)
		# Measured upright at the origin, then stood on the sand in the outpost's frame.
		var a := TownDecor.visual_aabb(ship)
		var lift := Vector3(-a.get_center().x, -a.position.y, -a.get_center().z)
		ship.global_transform = Transform3D(b, at + b * lift)
	else:
		ship = Node3D.new()
		add_child(ship)
		ship.global_transform = Transform3D(b, at + b * Vector3(0, 1.0, 0))
	ship.name = "Ship_" + str(o.id)
	ship.set_meta("ship_id", ship_id)
	ship.set_meta("outpost", str(o.id))
	o["ship"] = ship
	if demo.pilot != null:
		demo.pilot.add_outpost_berth(ship, ship_id, str(o.id))


func _mesh(o: Dictionary, mesh: Mesh, mat: Material, local: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = (o.xf as Transform3D) * Transform3D(basis, local)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c
