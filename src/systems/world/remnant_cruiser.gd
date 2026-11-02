class_name RemnantCruiser
extends Node3D
## Issue #193: the Remnant's star cruiser, in orbit over the home planet far to the
## east: past the curve from the port, plain to see from space. It is part of the
## home planet's map (a landmark of its world, like the wreck), not a planet of its
## own: the fight on the way up, the flight across and the landing in its bay are
## one sky, with nothing loaded or faded on the way. Its shapes are CruiserHull's
## (already solid to ships and to feet, through WorldGround and WorldScenery); this
## node adds, in the town scene:
##   - the look: the hull, decks and bridge merged into a few meshes on one shader
##     (cruiser_metal), glass, light strips, a beacon on every mast, the engines'
##     glow, the bay's energy shield (solid to people, open to ships) and the
##     lights inside,
##   - the ships on the bay's pads: two interceptors (flyable: taking one sounds the
##     alarm), a frigate, and the empty pad Z sets you down on (ShipPilot.dock),
##   - the crew: troopers and sentries in the bay, the corridor and its rooms and the
##     ramp shaft, an honour guard on the bridge, and the general at the great window,
##     plus the Remnant droids, all built a body a frame once your ship comes within
##     wake_distance, on a navmesh baked from the cruiser's own decks, run by a
##     garrison of their own that shoots on sight,
##   - the general's death: the cruiser is taken (WorldState.on_cruiser_taken): the
##     locals' purse, the port's love, and the end of Oda's story. From then on
##     nobody is aboard; anyone left alive is gone the next time you come back
##     (issue #303: but the dark master, DarkMasterPost, waits in the bay),
##   - the label naming it in the sky while you fly, and a pull back aboard if you
##     fall out of it.
## Everything else is data: content/core/cruiser/remnant_cruiser.json.

const SHADER := preload("res://src/systems/look/shaders/cruiser_metal.gdshader")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const FINISHES := { "hull": 0, "trim": 1, "deck": 2, "wall": 3, "grate": 4, "ramp": 5, "cargo": 6,
	"console": 7, "rail": 8, "bridge": 9, "pad": 10, "beacon": 11, "screen": 12 }
const NAV_BOUNDS := AABB(Vector3(-52, -20, -152), Vector3(118, 100, 484))

var demo                               ## town_demo.gd
var ground: WorldGround
var cfg: Dictionary = {}
var id := "remnant_cruiser"
var frame := Transform3D.IDENTITY      ## the cruiser's own frame in the world
var inv := Transform3D.IDENTITY
var vessel_name := ""
var garrison: Garrison
var crew: Array = []                   ## NpcBody aboard (the general too)
var general: NpcBody
var units: Array = []                  ## the Remnant droids aboard (DroidUnit)
var ships: Array = []                  ## { pad, node, berth (or -1) }
var woke := false                      ## the crew has been (or is being) built
var nav_ready := false
var taken_here := false                ## the general died in this scene
var falls := 0                         ## times you were pulled back aboard (traces, tests)

var _queue: Array = []                 ## crew still to build (Callables), a body a frame
var _hull: Node3D                      ## the look, in the cruiser's frame
var _inside: Node3D                    ## its interior lights (off from far away)
var _layer: CanvasLayer
var _label: Label
var _was_aboard := false
var _stairs_reached := false           ## the fleet chapter's "infiltrate" step was reported
var _last_aboard := Vector3.INF
var _mats: Dictionary = {}
var _flames: Array = []                ## the engines' flame nodes (Node3D), to flicker
var holo: CruiserHolo                  ## the bridge's planet map, built the first time you are near it

static var _meshes: Dictionary = {}    ## finish -> ArrayMesh, built once a session


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	cfg = CruiserHull.data()
	id = str(cfg.get("id", id))
	frame = CruiserHull.frame(ground, id)
	inv = frame.affine_inverse()
	name = "RemnantCruiser"
	vessel_name = NameHooks.vessel(cfg, "vessel:" + id)


func _ready() -> void:
	_hull = Node3D.new()
	_hull.name = "Hull"
	add_child(_hull)
	_hull.transform = frame
	if demo.use_look:
		_build_look()
	_build_shield()
	_park_ships()
	_bake_nav()
	_build_label()


# ------------------------------------------------------------------ queries

func to_local_point(p: Vector3) -> Vector3:
	return inv * p


func to_world(local: Vector3) -> Vector3:
	return frame * local


## Somewhere in its walkable interior.
func aboard(p: Vector3) -> bool:
	return CruiserHull.aboard(inv * p)


func taken() -> bool:
	return Story.cruiser_taken()


func label() -> String:
	var l := str(cfg.get("label", "cruiser"))
	return "%s %s" % [l, vessel_name] if vessel_name != "" else l


## How far `p` is from the cruiser's middle (metres).
func distance(p: Vector3) -> float:
	return p.distance_to(frame.origin)


## Close enough for Z to dock you.
func can_dock(p: Vector3) -> bool:
	return distance(p) <= float(cfg.get("dock", {}).get("radius", 3200.0)) and not aboard(p)


## The world points the docking autopilot flies through from `p` (CruiserHull.dock_path).
func dock_path(p: Vector3) -> Array:
	return CruiserHull.dock_path(inv * p).map(func(l): return frame * (l as Vector3))


## The dock pad's heading (a yaw about world up: the cruiser is level with the port).
func dock_yaw() -> float:
	var pd := CruiserHull.dock_pad()
	return (frame.basis * Basis(Vector3.UP, float(pd.get("yaw", 0.0)))).get_euler().y


func dock_cfg() -> Dictionary:
	return cfg.get("dock", {})


func line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, ""))


func escort_id() -> String:
	return str(cfg.get("escort", ""))


## Where the objective arrow points: the bay from outside, the general once aboard;
## or `part` by name: "bay" (the dock pad), "stairs" (the foot of the ramp stack),
## "general" (him alive, else his place on the bridge).
func objective_point(from: Vector3, part: String = "") -> Vector3:
	var alive := general != null and is_instance_valid(general) and not general.dead
	match part:
		"bay":
			return frame * (CruiserHull.dock_pad().get("at", Vector3.ZERO) as Vector3)
		"stairs":
			return frame * CruiserHull.stairs_foot()
		"general":
			return general.global_position if alive else frame * WorldGround._v3(cfg.get("general", {}).get("at", [0, 58, 219]))
	if alive and aboard(from):
		return general.global_position
	if aboard(from):
		return frame * WorldGround._v3(cfg.get("general", {}).get("at", [0, 58, 219]))
	return frame * (CruiserHull.dock_pad().get("at", Vector3.ZERO) as Vector3)


# ------------------------------------------------------------------ frame

func _physics_process(_dt: float) -> void:
	var p: Node3D = demo._player if demo != null else null
	if p == null or not is_instance_valid(p):
		return
	var at: Vector3 = p.global_position
	var near := distance(at) <= float(cfg.get("wake_distance", 2600.0))
	if _inside != null:
		_inside.visible = distance(at) < 3000.0
	if near and not woke and not taken():
		_wake()
	if not _queue.is_empty():
		(_queue.pop_front() as Callable).call()
	if taken() and not near and not crew.is_empty():
		_abandon()                     # the survivors took the pods while you were away
	var sleep := float(cfg.get("sleep_distance", 460.0))
	var now := Time.get_ticks_usec()
	for g in crew:
		if not is_instance_valid(g):
			continue
		# Awake while dying or just hit (a shot from your ship far off), so they fall
		# or answer it; asleep they are still solid to bolts (_enlist).
		var awake: bool = g.dead or g.global_position.distance_to(at) <= sleep or now - g.damage_usec < 5000000
		g.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
	crew = crew.filter(func(g): return is_instance_valid(g))
	_fall_guard(p)
	_steps(p)
	if demo.look != null:
		demo.look.set_shadow_cap(float(cfg.get("aboard_shadow_distance", 0.0)) if aboard(at) else 0.0)


func _exit_tree() -> void:
	if demo != null and demo.look != null:
		demo.look.set_shadow_cap(0.0)


## The fleet chapter's steps (Story "steps"): on foot aboard is "landed", once; in
## the ramp shaft is "infiltrated", once a session (the story ignores repeats).
func _steps(p: Node3D) -> void:
	if p.get("piloting") == true or _stairs_reached:
		return
	var local := inv * p.global_position
	if CruiserHull.aboard(local) and CruiserHull.at_stairs(local):
		_stairs_reached = true
		Story.event("cruiser_infiltrated")


## Fallen out of the cruiser (through the bay's mouth, off the hull): back aboard
## by the dock pad.
func _fall_guard(p: Node3D) -> void:
	if p.get("piloting") == true:
		_was_aboard = false
		return
	var here := aboard(p.global_position)
	if here:
		if not _was_aboard:
			Story.event("cruiser_landed")      # on foot aboard: the fleet chapter's first step
		_was_aboard = true
		_last_aboard = p.global_position
		return
	if not _was_aboard:
		return
	if distance(p.global_position) > 1000.0:
		_was_aboard = false            # moved away (woken in the pit, towed home), not fallen
		return
	var local := inv * p.global_position
	if local.y > CruiserHull.DECK_Y - 12.0 and CruiserHull.GRAVITY_BOX.has_point(local):
		return
	var pd := CruiserHull.dock_pad()
	var back := frame * ((pd.get("at", Vector3.ZERO) as Vector3) + Vector3(-16, 0.1, 0))
	p.global_position = back
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	falls += 1
	_toast(line("fell"), 3.0)


# ------------------------------------------------------------------ the crew

## Your ship is close: the crew comes aboard, a body a frame (the bay first).
func _wake() -> void:
	woke = true
	if not demo.has_method("make_soldier"):
		return
	var i := 0
	for c in cfg.get("crew", []):
		_queue.append(_add_crew.bind(c, i))
		i += 1
	if not cfg.get("general", {}).is_empty():
		_queue.append(_add_general)
	_queue.append(_add_droids)


func _add_crew(c: Dictionary, i: int) -> NpcBody:
	var here := frame * WorldGround._v3(c.get("at", [0, 0, 0]))
	var face := frame.basis * WorldGround._v3(c.get("face", [0, 0, -1]))
	var g: NpcBody = demo.make_soldier(str(c.get("soldier", "cruiser_trooper")), here + Vector3(0, 0.05, 0),
		atan2(face.x, face.z), "%s/crew_%d" % [id, i], "npc:%s/crew_%d" % [id, i], self)
	if g == null:
		return null
	_enlist(g)
	var route: Array = c.get("route", [])
	if route.size() >= 2 and garrison != null and garrison.brains.has(g):
		garrison.brains[g].patrol_points = route.map(func(r): return frame * WorldGround._v3(r))
	return g


func _add_general() -> void:
	var c: Dictionary = cfg.get("general", {})
	var here := frame * WorldGround._v3(c.get("at", [0, 58, 219]))
	var face := frame.basis * WorldGround._v3(c.get("face", [0, 0, -1]))
	general = demo.make_soldier(str(c.get("soldier", "cruiser_general")), here + Vector3(0, 0.05, 0),
		atan2(face.x, face.z), "%s/general" % id, "npc:%s/general" % id, self)
	if general == null:
		return
	_enlist(general)
	general.died.connect(_on_general_died)


## A body joins the cruiser's garrison (made by the first one aboard).
func _enlist(g: NpcBody) -> void:
	g.set_meta("cruiser", id)
	# Asleep (far from you) a body's process is off, which by default takes it out
	# of physics too: bolts would pass through a trooper you can see.
	g.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	g.nav = demo.nav
	crew.append(g)
	if garrison == null:
		if not demo.npc_brains:
			return
		garrison = demo._make_garrison("Garrison_" + id, [g], false,
			frame * Vector3(0, CruiserHull.DECK_Y, (CruiserHull.BAY_Z.x + CruiserHull.BAY_Z.y) * 0.5))
		garrison.always_hostile = not DarkPact.joined()     # issue #303: his crew is yours on the oath
		var outposts = demo.outposts
		if outposts != null:
			outposts.garrisons[id] = garrison      # a ship taken from its bay sounds its alarm
	else:
		garrison.add_member(g)


## The Remnant droids aboard (DroidController), on routes in the cruiser's frame.
func _add_droids() -> void:
	var dc = demo.droids
	if dc == null:
		return
	for d in cfg.get("droids", []):
		var spec: Dictionary = (d as Dictionary).duplicate(true)
		spec["patrol"] = (spec.get("route", []) as Array).map(func(r): return frame * WorldGround._v3(r))
		spec.erase("route")
		spec["site"] = id
		spec["hostile"] = true
		spec["respawn"] = false
		if garrison != null:
			spec["garrison"] = garrison
		var u = dc.spawn_site_unit(spec)
		if u != null:
			units.append(u)


## The general is dead: the cruiser is taken.
func _on_general_died() -> void:
	if taken():
		return
	taken_here = true
	var who := general.display_name if general != null and general.display_name != "" else "The general"
	var pay := WorldState.on_cruiser_taken(who, cfg.get("reward", {}), line("event_taken"))
	_toast(line("general_dead") % who, 6.0)
	if pay > 0:
		_toast(line("taken") % pay, 6.0)
	# The fight in its sky ends with him: landing in the bay only took you out of it.
	if demo.pilot != null and demo.pilot.fight != null:
		demo.pilot.end_fight("general")
		_toast(line("escort_gone"), 6.0)
	Sound.battle()


## Taken, and you are away: whoever was left aboard is gone.
func _abandon() -> void:
	for g in crew:
		if not is_instance_valid(g):
			continue
		if garrison != null:
			garrison.remove_member(g)
		demo.npcs.erase(g)
		g.queue_free()
	crew.clear()
	general = null
	for u in units:
		if is_instance_valid(u) and demo.droids != null:
			demo.droids.remove_site_unit(u)
	units.clear()


# ------------------------------------------------------------------ the navmesh

func _bake_nav() -> void:
	if demo.nav == null:
		return
	var boxes := CruiserHull.parts().filter(func(p): return bool(p.get("nav", false)))
	demo.nav.add_faces_region(TownNav.oriented_box_faces(boxes), frame, NAV_BOUNDS,
		func(_r): nav_ready = true)


# ------------------------------------------------------------------ ships on the pads

func _park_ships() -> void:
	var cc = demo._content()
	var root := Node3D.new()
	root.name = "ParkedShips"
	add_child(root)
	for pd in CruiserHull.pads():
		var ship_id := str(pd.ship)
		if ship_id == "":
			continue
		var look_id := str(cc.get_ship(ship_id).get("look", ""))
		var ship: Node3D
		if demo.use_look and look_id != "":
			ship = (demo.pilot.kit if demo.pilot != null and demo.pilot.kit != null else ShipKit.new(demo._flat_mats())).build(look_id)
		else:
			ship = Node3D.new()
		var s := float(pd.scale)
		var a := TownDecor.visual_aabb(ship) if demo.use_look else AABB(Vector3(-4, -1, -4), Vector3(8, 3, 8))
		root.add_child(ship)
		var b := (frame.basis * Basis(Vector3.UP, float(pd.yaw))).scaled(Vector3.ONE * s)
		var lift := Vector3(-a.get_center().x, -a.position.y + 0.1, -a.get_center().z)
		ship.global_transform = Transform3D(b, frame * (pd.at as Vector3) + b * lift)
		ship.name = "Ship_" + str(pd.id)
		ship.set_meta("ship_id", ship_id)
		var entry := { "pad": pd.id, "node": ship, "berth": -1 }
		if bool(pd.flyable) and demo.pilot != null:
			entry.berth = demo.pilot.add_outpost_berth(ship, ship_id, id)
			demo.pilot.berths[entry.berth]["where"] = label()
		else:
			_solid_ship(root, ship, a, s, str(pd.id))
		ships.append(entry)


## A ship that only stands there (the frigate): solid to feet and to ships. The
## body is not under the (scaled) model: a box its size, in its place.
func _solid_ship(root: Node3D, ship: Node3D, a: AABB, s: float, pad_id: String) -> void:
	var xf := ship.global_transform * Transform3D(Basis.IDENTITY, a.get_center())
	xf = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var half := a.size * s * 0.5
	var body := StaticBody3D.new()
	body.name = "Hull_" + pad_id
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = half * 2.0
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	body.global_transform = xf
	ground.add_box("%s/ship_%s" % [id, pad_id], "solid", -half, half, "", false, xf)


# ------------------------------------------------------------------ the bay's shield

## Across the bay's mouth: you cannot walk out into space, a ship flies straight
## through, and so do bolts both ways (your ship's guns into the bay, theirs out).
func _build_shield() -> void:
	var z := CruiserHull.BAY_Z
	var size := Vector3(0.4, 28.0, z.y - z.x)
	var at := Vector3(CruiserHull.BAY_X.y + 0.5, 0.0, (z.x + z.y) * 0.5)
	var body := StaticBody3D.new()
	body.name = "BayShield"
	body.set_meta("bolts_pass", true)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size + Vector3(1.6, 0, 0)
	cs.shape = shape
	body.add_child(cs)
	_hull.add_child(body)
	body.position = at
	if not demo.use_look:
		return
	var mi := MeshInstance3D.new()
	mi.name = "ShieldLook"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = LookMaterials.energy_shield(size, Vector3(0, 3, 6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hull.add_child(mi)
	mi.position = at


# ------------------------------------------------------------------ the look

func _build_look() -> void:
	var noise: Texture2D = demo._flat_mats().noise
	for f in FINISHES:
		if f == "pad":
			continue
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("finish", FINISHES[f])
		m.set_shader_parameter("noise_tex", noise)
		_mats[f] = m
	_mats["glass"] = _glass()
	_mats["glow"] = _emissive(Color("#e8f6ff"), 3.0)
	_mats["reactor"] = _emissive(Color("#9fdcff"), 6.0)
	var groups := {}
	for p in CruiserHull.parts():
		var f := str(p.finish)
		if f == "hidden":
			continue                       # solid only (the bells' boxes): drawn round
		if f == "pad":
			_pad(p, noise)
			continue
		if not groups.has(f):
			groups[f] = []
		groups[f].append(p)
	for f in groups:
		var mi := MeshInstance3D.new()
		mi.name = "Cruiser_" + str(f)
		mi.mesh = _merged(str(f), groups[f])
		mi.material_override = _mats.get(f, _mats["hull"])
		if f in ["glass", "glow", "screen", "reactor", "beacon"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 50.0
		_hull.add_child(mi)
	_engines()
	_globes()
	_lights()


## Every part of a finish as one mesh in the cruiser's frame (made once a session).
static func _merged(finish: String, list: Array) -> ArrayMesh:
	if _meshes.has(finish):
		return _meshes[finish]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in list:
		var bm := BoxMesh.new()
		bm.size = p.size
		st.append_from(bm, 0, p.xf)
	var mesh := st.commit()
	_meshes[finish] = mesh
	return mesh


func _pad(p: Dictionary, noise: Texture2D) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("finish", FINISHES.pad)
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("plate_half", (p.size as Vector3) * 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Cruiser_" + str(p.id)
	var bm := BoxMesh.new()
	bm.size = p.size
	mi.mesh = bm
	mi.material_override = m
	mi.transform = p.xf
	_hull.add_child(mi)


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.62, 0.75, 0.16)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.9
	m.roughness = 0.04
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## The engines on the stern (CruiserHull.engines; their housings are hull parts).
## Each bell flares from a throat deep in its housing out to its mouth: plated
## outside with a rim and stiffening rings, a liner inside glowing blue toward a
## white-hot throat, and its flame out of the mouth.
func _engines() -> void:
	var trim: Material = _mats["trim"]
	var liner := _emissive(Color("#1a4f9c"), 1.6)
	liner.cull_mode = BaseMaterial3D.CULL_DISABLED
	var throat := _emissive(Color("#eefaff"), 9.0)
	var ring_glow := _emissive(Color("#4aa8ff"), 2.4)
	var aft := Basis(Vector3.RIGHT, PI * 0.5)         # a cylinder's +y turned aft (+z)
	for e in CruiserHull.engines():
		var c: Vector3 = e.at                        # the mouth
		var r := float(e.radius)
		var aux := bool(e.aux)
		var length := CruiserHull.BELL_LENGTH * (0.5 if aux else 1.0)
		var tr := r * 0.55                           # the throat
		var mid := c - Vector3(0, 0, length * 0.5)
		_mesh(_cyl(r, tr, length, 40, false), trim, Transform3D(aft, mid))
		_mesh(_cyl(r * 0.94, tr * 0.92, length, 40, false), liner, Transform3D(aft, mid))
		_mesh(_cyl(tr * 0.92, tr * 0.92, 0.3, 32), throat, Transform3D(aft, c - Vector3(0, 0, length - 0.4)))
		# The rim round the mouth, and rings round the bell (the last one glowing).
		_mesh(_ring(r, r * 0.1), trim, Transform3D(aft, c))
		for k in 3:
			var d := length * (0.22 + k * 0.2)
			var rr := lerpf(r, tr, d / length) + 0.15
			_mesh(_ring(rr, r * (0.05 if k < 2 else 0.035)), trim if k < 2 else ring_glow, Transform3D(aft, c - Vector3(0, 0, d)))
		_flame(c, r * 0.95, r * (5.0 if aux else 6.5))
		var light := OmniLight3D.new()
		light.light_color = Color("#7cc4ff")
		light.light_energy = 2.5 if aux else 4.0
		light.omni_range = r * 8.0
		_hull.add_child(light)
		light.position = c + Vector3(0, 0, r * 1.5)


## A flame out of a bell's mouth at `at`, aft: the jetpack's flame grown to the
## cruiser's size and burning blue (EngineFlame, which the ships' engines share).
## `nr` is its radius at the mouth, `fh` its length; _flicker() makes it waver.
func _flame(at: Vector3, nr: float, fh: float) -> void:
	_flames.append(EngineFlame.build(_hull, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at), nr, fh, EngineFlame.ION))


## The flames waver, each out of step with the others (as the jetpack's do).
func _flicker() -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in _flames.size():
		var k := 1.0 + 0.07 * sin(t * 17.0 + i * 2.1) + 0.04 * sin(t * 43.0 + i * 0.7)
		var w := 1.0 + 0.025 * sin(t * 29.0 + i * 1.3)
		(_flames[i] as Node3D).scale = Vector3(w, k, w)


static func _cyl(top: float, bottom: float, h: float, seg: int, caps := true) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


## A ring of radius `r` (to its tube's middle), `tube` thick, round its own y.
static func _ring(r: float, tube: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - tube
	t.outer_radius = r + tube
	t.rings = 48
	t.ring_segments = 8
	return t


## The sensor globes on the tower's roof, in the hull's own grey.
func _globes() -> void:
	for g in CruiserHull.globes():
		var sphere := SphereMesh.new()
		sphere.radius = float(g.radius)
		sphere.height = float(g.radius) * 2.0
		sphere.radial_segments = 32
		sphere.rings = 16
		var mi := _mesh(sphere, _mats["hull"], Transform3D(Basis.IDENTITY, g.at))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _mesh(mesh: Mesh, mat: Material, xf: Transform3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	(parent if parent != null else _hull).add_child(mi)
	return mi


## The lights inside: floods in the bay, lamps down the corridor and in its rooms,
## up the shaft (and the reactor's blue through its grille), and over the bridge.
func _lights() -> void:
	_inside = Node3D.new()
	_inside.name = "InteriorLights"
	_hull.add_child(_inside)
	var d := CruiserHull.DECK_Y
	var list: Array = []
	for x: float in [-20.0, 24.0]:
		for z: float in [-120.0, -64.0, -8.0]:
			list.append([Vector3(x, CruiserHull.BAY_TOP - 6.0, z), "#e4edff", 11.0, 80.0])
	for x: float in [-24.0, 20.0]:
		for z: float in [-128.0, -92.0, -56.0, -20.0, 14.0]:
			list.append([Vector3(x, d + 12.0, z), "#dbe7ff", 5.0, 40.0])     # low fill over the pads
	for z in [-110.0, -40.0, 10.0]:
		list.append([Vector3(-38.0, d + 8.0, z), "#ffcf9a", 3.5, 32.0])      # warm fill along the cargo
	for i in 16:
		list.append([Vector3(0, CruiserHull.HALL_TOP - 1.5, 36.0 + i * 15.0), "#cfe6ff", 3.5, 20.0])
	for z: float in [116.0, 128.0]:
		list.append([Vector3(16, CruiserHull.HALL_TOP - 1.5, z), "#ffd9a8", 5.0, 20.0])
	for z: float in [182.0, 194.0]:
		list.append([Vector3(-16, CruiserHull.HALL_TOP - 1.5, z), "#ffd9a8", 5.0, 20.0])
	for i in CruiserHull.FLIGHTS:
		list.append([Vector3(0, d + 6.0 + i * CruiserHull.FLIGHT_RISE, 298), "#c3dbff", 6.0, 36.0])
	for x: float in [-18.0, 18.0]:
		for y in [d + 14.0, d + 38.0, d + 62.0]:
			list.append([Vector3(x, y, 298), "#c3dbff", 4.0, 30.0])         # fill on the landings
	list.append([Vector3(0, 12, 318), "#7fc8ff", 5.0, 42.0])
	for z: float in [226.0, 242.0, 258.0]:
		list.append([Vector3(0, CruiserHull.BRIDGE_TOP - 2.0, z), "#dce8ff", 3.5, 30.0])
	for x: float in [-16.0, 16.0]:
		for z: float in [228.0, 256.0]:
			list.append([Vector3(x, CruiserHull.BRIDGE_TOP - 2.0, z), "#dce8ff", 2.5, 26.0])
	for x: float in [-18.0, 18.0]:
		list.append([Vector3(x, CruiserHull.PIT_Y + 2.0, 242), "#38c8ff", 2.0, 16.0])
	for l in list:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = Color(str(l[1]))
		o.light_energy = float(l[2])
		o.omni_range = float(l[3])
		o.omni_attenuation = 0.8
		_inside.add_child(o)


# ------------------------------------------------------------------ the label and toasts

func _build_label() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("#ffb08a"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	_layer.add_child(_label)


func _process(_dt: float) -> void:
	_flicker()
	_holo_near()
	if _label == null:
		return
	var pilot = demo.pilot
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var flying: bool = pilot != null and pilot.piloting and pilot.atmo.state in [AtmoFlight.State.FLYING, AtmoFlight.State.LIFTOFF]
	var at: Vector3 = frame.origin
	if cam == null or not flying or cam.is_position_behind(at) or aboard(pilot.atmo.position()):
		_label.visible = false
		return
	var d := distance(pilot.atmo.position())
	var text := line("label") % label()
	if can_dock(pilot.atmo.position()):
		text = line("dock_hint") % [text, d / 1000.0]
	else:
		text += "  %.1f km" % (d / 1000.0)
	_label.text = text
	_label.position = cam.unproject_position(at) + Vector2(14, -10)
	_label.visible = true


## The holo table's map: built the first time you come within holo.show_within of
## it, shown only then (it spins every frame).
func _holo_near() -> void:
	var spec: Dictionary = cfg.get("holo", {})
	if not demo.use_look or spec.is_empty() or demo._player == null or not is_instance_valid(demo._player):
		return
	var table := CruiserHull.holo_table()
	var near: bool = (inv * (demo._player.global_position as Vector3)).distance_to(table) <= float(spec.get("show_within", 400.0))
	if near and holo == null:
		var names := { "town": NameHooks.town(ground.world), "cruiser": vessel_name }
		var moons: Array = []
		var travel = demo.pilot.travel if demo.pilot != null else null
		if travel != null:
			for b in travel.bodies:
				moons.append(b)
				names[str(b.id)] = str(b.name)
		elif "planet" in demo:
			moons = demo.planet.get("neighbours", [])
		holo = CruiserHolo.new()
		holo.setup(spec, ground.sphere(), frame, table + Vector3(0, float(spec.get("lift", 1.75)), 0), ground.world, moons, names)
		_hull.add_child(holo)
	if holo != null:
		holo.visible = near
		holo.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


func _toast(text: String, secs: float) -> void:
	if text == "":
		return
	if demo.gear != null and demo.gear.hud != null:
		demo.gear.hud.toast(text, secs)
	elif demo.pilot != null:
		demo.pilot.hud.toast(text, secs)
