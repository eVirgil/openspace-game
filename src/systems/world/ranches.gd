class_name Ranches
extends Node3D
## Ranch villages: three set pieces far out on the home planet, each a Remnant
## outpost with a few houses round it. Every place is two landmarks at one spot
## in content/core/worlds/port_desert.json:
##   - remnant_outpost_<name>: the outpost itself, built by RemnantOutposts like
##     every other (troopers, control room, ship, droids) and one of
##     Story.OUTPOSTS, so it counts toward driving the Remnant off. Its
##     "after_cruiser" keeps it theirs until the cruiser has fallen
##     (Territory.locked). Its map pin says "Village".
##   - ranch_<name> (location kind "ranch"): the houses (one tall), the walled
##     yard with its gate toward the port, four merchant stands and a fire. Its
##     buildings are solid boxes in the ship's ground already (WorldGround); this
##     node only dresses them and stands the people in them.
##
## The people are the locals': armed ranchers (soldiers/ranch_local.json) hanging
## about the fire and the gate, and a keeper behind each stand, all run by the
## ranch's own Townsfolk (their own alarm: a fight out here never reaches the
## port). The stands sell what the port's do: the gear trader, the food stall and
## the fence are the port's vendors (content/core/vendors, same stock and prices)
## added to the gear's list at the stand, and the droid stand is one more droid
## merchant (DroidController.vendor_sites). No speeders. A stand shuts while its
## keeper is dead or the ranch is up in arms.
##
## Render rules: everything here is drawn to DRAW_M (the wreck field's and the
## barge's 1500 m) and no further, so a ranch 3.5 km out draws nothing until you
## are on your way to it. People sleep past WAKE_DIST, like the outposts'.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownMarket := preload("res://src/systems/world/town_market.gd")
const WAKE_DIST := 320.0           ## bodies further than this from the player sleep
const DRAW_M := 1500.0             ## nothing here is drawn further than this
const DRAW_FADE := 150.0
const KEEPER_BACK := 1.3           ## metres behind a stand's counter its keeper stands
const SHOP_FRONT := 1.4            ## ... and in front, where a customer stands

## The town's building kit with plain plaster: its shader's dirt and painted
## band go by world height, which means nothing on the far side of the ball.
class RanchKit extends "res://src/systems/world/town_buildings.gd":
	func _init(m: LookMaterials, l: LookEnvironment) -> void:
		super(m, l)

	func _plaster(b: Dictionary, _band_y: float) -> Material:
		var i := absi(hash(str(b.id)))
		return mats.plaster(-1.0e7, -1.0e7, BANDS[i % BANDS.size()], TINTS[(i / 7) % TINTS.size()])


var demo                           ## town_demo.gd
var ground: WorldGround
var ranches: Array = []            ## { id, label, cfg, xf, origin, root }
var people: Array = []             ## NpcBody: the ranchers and the keepers (also in demo.locals)
var droid_sites: Array = []        ## the droid stands, as DroidController.vendor_sites
var vendors: Array = []            ## the other stands, as GearController.vendors ({ cfg, pos }); handed over once
var _vendors_given := 0
var folks: Dictionary = {}         ## ranch id -> its Townsfolk
var _cc: CoreContent
var _queue: Array = []             ## the pieces still to build, in order (Callables)
var _started := false


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "Ranches"


## Build every ranch now (a staged handoff calls build_step once a frame instead).
func build() -> void:
	while not build_step():
		pass


## Build the next piece: one ranch's look, its stands' trade, or one person.
## True once all are built.
func build_step() -> bool:
	if not _started:
		_started = true
		_cc = CoreContent.new()
		_cc.load_from()
		for lm in _cc.world_for_town("port_town").get("landmarks", []):
			var loc := _cc.get_location(str(lm.get("location", "")))
			if str(loc.get("kind", "")) == "ranch":
				_queue.append(_place.bind(lm, loc))
	if _queue.is_empty():
		return true
	(_queue.pop_front() as Callable).call()
	return _queue.is_empty()


func _place(lm: Dictionary, loc: Dictionary) -> void:
	var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
	var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
	var origin := Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
	var basis := Basis(Vector3.UP, yaw)
	var sp := ground.sphere()
	if sp != null:
		origin = sp.surface_at(at.x, at.z)
		basis = PlanetSphere.tilt_to(ground.up_at(origin)) * basis
	var root := Node3D.new()
	root.name = str(loc.get("id", "Ranch")).to_pascal_case()
	add_child(root)
	var r := { "id": str(loc.get("id", "")), "label": str(loc.get("label", "")), "cfg": loc,
		"xf": Transform3D(basis, origin), "origin": origin, "root": root }
	root.global_transform = r.xf
	ranches.append(r)
	var parts: Array = []
	if demo.use_look:
		parts.append(_dress.bind(r))
	var stalls: Dictionary = loc.get("stalls", {})
	for sid in stalls:
		parts.append(_add_keeper.bind(r, str(sid)))
	var spots: Array = loc.get("points", {}).get("locals", [])
	for i in spots.size():
		parts.append(_add_rancher.bind(r, i))
	_queue = parts + _queue           # this ranch's pieces next, then the others


# ------------------------------------------------------------------ people

## One of the ranch's armed locals at its spot, facing the fire (or the yard).
func _add_rancher(r: Dictionary, i: int) -> NpcBody:
	var pts: Dictionary = r.cfg.get("points", {})
	var here := world_point(r, pts.locals[i])
	var look_at := world_point(r, pts.get("fire", [0, 0, 0]))
	if here.distance_to(look_at) > 12.0:
		look_at = r.origin
	var post := "%s/local_%d" % [r.id, i]
	return _person(r, str(r.cfg.get("local", "ranch_local")), here, look_at, post)


## The keeper behind stand `sid`, facing the customer's side. Its stand's trade
## goes in with it: the port's vendor at the counter, or a droid merchant.
func _add_keeper(r: Dictionary, sid: String) -> NpcBody:
	var s: Dictionary = r.cfg.get("stalls", {}).get(sid, {})
	var b := building(r, sid)
	if b.is_empty():
		return null
	var c := WorldGround._v3(b.get("position", [0, 0, 0]))
	var f := _face_dir(str(b.get("face", "+z")))
	var counter := world_point(r, c)
	var here := world_point(r, c - f * KEEPER_BACK)
	var front := world_point(r, c + f * SHOP_FRONT)
	var post := "%s/%s" % [r.id, sid]
	var g := _person(r, str(s.get("keeper", "local_merchant")), here, front, post)
	if bool(s.get("droid", false)):
		var up := ground.up_at(here)
		var face := front - here
		face = (face - up * face.dot(up)).normalized()
		droid_sites.append({ "id": post, "label": str(s.get("label", "Droid merchant")), "pos": counter,
			"face": face, "open": vendor_open.bind(post) })
	else:
		var v := _cc.get_vendor(str(s.get("vendor", "")))
		if not v.is_empty():
			v = v.duplicate(true)
			v["marker"] = post            # the keeper's post: shut while they are dead (vendor_open)
			vendors.append({ "cfg": v, "pos": counter })
	return g


func _person(r: Dictionary, soldier: String, here: Vector3, face: Vector3, post: String) -> NpcBody:
	var g: NpcBody = demo.make_soldier(soldier, here, atan2(face.x - here.x, face.z - here.z), post, "npc:" + post)
	if g == null:
		return null
	g.set_meta("ranch", str(r.id))
	people.append(g)
	return g


## The ranches' own directors, once everyone stands (the town's _npc_brains), and
## the stands' open/shut rule round the gear's.
func start_brains() -> void:
	for r in ranches:
		var mine: Array = people.filter(func(g): return is_instance_valid(g) and str(g.get_meta("ranch", "")) == str(r.id))
		if not mine.is_empty():
			folks[str(r.id)] = demo.make_townsfolk("Ranch_" + str(r.id), mine)
	_give_vendors()
	var gear = demo.get("gear")
	if gear == null:
		return
	var town_open: Callable = gear.vendor_open
	var town_line: Callable = gear.closed_line
	gear.vendor_open = func(marker: String) -> bool:
		if _folk_for(marker) != null:
			return vendor_open(marker)
		return not town_open.is_valid() or bool(town_open.call(marker))
	gear.closed_line = func(marker: String) -> String:
		var f = _folk_for(marker)
		if f != null:
			return f.closed_line(marker)
		return str(town_line.call(marker)) if town_line.is_valid() else ""


## True while the stand at `post` will trade: its keeper is alive and the ranch
## is not up in arms (Townsfolk.vendor_open). Before the brains start, open.
func vendor_open(post: String) -> bool:
	var f = _folk_for(post)
	return f == null or bool(f.vendor_open(post))


func _folk_for(post: String):
	return folks.get(post.get_slice("/", 0), null) if post.contains("/") else null


func _physics_process(_dt: float) -> void:
	_give_vendors()
	var p: Node3D = demo._player if demo != null else null
	if p == null:
		return
	for g in people:
		if is_instance_valid(g) and not g.dead:
			var far: bool = g.global_position.distance_to(p.global_position) > WAKE_DIST
			g.process_mode = Node.PROCESS_MODE_DISABLED if far else Node.PROCESS_MODE_INHERIT
	people = people.filter(func(g): return is_instance_valid(g))


# ------------------------------------------------------------------ places

## The stands built so far go on the gear's vendor list (it may come up after them).
func _give_vendors() -> void:
	var gear = demo.get("gear") if demo != null else null
	if gear == null or _vendors_given >= vendors.size():
		return
	for i in range(_vendors_given, vendors.size()):
		gear.vendors.append(vendors[i])
	_vendors_given = vendors.size()


func ranch(id: String) -> Dictionary:
	for r in ranches:
		if str(r.id) == id:
			return r
	return {}


func building(r: Dictionary, id: String) -> Dictionary:
	for b in r.cfg.get("buildings", []):
		if str(b.get("id", "")) == id:
			return b
	return {}


## A point in a ranch's frame, in the world, on the sand.
func world_point(r: Dictionary, local) -> Vector3:
	var lp: Vector3 = local if local is Vector3 else WorldGround._v3(local)
	var p: Vector3 = (r.xf as Transform3D) * Vector3(lp.x, 0.0, lp.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


static func _face_dir(face: String) -> Vector3:
	return { "+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+z": Vector3.BACK, "-z": Vector3.FORWARD }.get(face, Vector3.BACK)


# ------------------------------------------------------------------ the look

## The houses in the town's building kit, the walls and gate in plaster, the
## stands in the town's market kit (each showing its trader's wares), and the
## fire with crates to sit on. All drawn to DRAW_M.
func _dress(r: Dictionary) -> void:
	var d = demo.get("decor")
	var mats: LookMaterials = d.mats if d != null and d.get("mats") != null else demo._flat_mats()
	var kit := RanchKit.new(mats, demo.look)
	var market := TownMarket.new(kit)
	var looks: Dictionary = ItemKit._read_json(ItemKit.LOOKS_PATH).get("stalls", {}).get("vendors", {})
	var stall_cfg: Dictionary = r.cfg.get("stalls", {})
	var wall := mats.plaster(-1.0e7, -1.0e7, LookMaterials.CLOTH_SAND, Color("#d6c09c"))
	var cap := mats.plaster(-1.0e7, -1.0e7, LookMaterials.CLOTH_SAND, Color("#b89a72"))
	var banner := mats.canvas(LookMaterials.CLOTH_TEAL)
	var stalls: Array = []
	var trades := {}
	for b in r.cfg.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		var box := { "id": "%s_%s" % [r.id, b.id], "face": str(b.get("face", "+x")), "look": str(b.get("look", "")),
			"min": [c.x - s.x * 0.5, c.y, c.z - s.z * 0.5], "max": [c.x + s.x * 0.5, c.y + s.y, c.z + s.z * 0.5] }
		match str(b.get("look", "")):
			"wall":
				kit._xf = Transform3D.IDENTITY
				kit.part(kit.box(s.x, s.y + 0.6, s.z), wall, c + Vector3(0, (s.y - 0.6) * 0.5, 0))   # its foot a little under the sand
				kit.part(kit.box(s.x + 0.25, 0.22, s.z + 0.25), cap, c + Vector3(0, s.y + 0.11, 0))
			"gate":
				kit._xf = Transform3D.IDENTITY
				kit.part(kit.box(s.x, s.y + 0.6, s.z), wall, c + Vector3(0, (s.y - 0.6) * 0.5, 0))
				kit.part(kit.box(s.x + 0.4, 0.35, s.z + 0.4), cap, c + Vector3(0, s.y + 0.17, 0))
				kit.part(kit.box(0.05, 2.4, s.z * 0.7), banner, c + Vector3(s.x * 0.5 + 0.04, s.y - 1.7, 0))
				kit.part(kit.box(0.25, 0.25, 0.25), kit.door_glow, c + Vector3(0, s.y + 0.48, 0))
			"stall":
				stalls.append(box)
				var sc: Dictionary = stall_cfg.get(str(b.id), {})
				var trade: Dictionary = looks.get("droid_merchant" if bool(sc.get("droid", false)) else str(sc.get("vendor", "")), {})
				if not trade.is_empty():
					trades[box.id] = trade
			_:
				kit.build(box)
	market.dress(r.root, stalls, {}, trades)
	_fire(r, kit, mats)
	kit.flush(r.root)
	_draw_range(r.root)


## A ring of stones with embers in it, and crates round it to sit on.
func _fire(r: Dictionary, kit, mats: LookMaterials) -> void:
	var pts: Dictionary = r.cfg.get("points", {})
	if not pts.has("fire"):
		return
	var at := WorldGround._v3(pts.fire)
	kit._xf = Transform3D.IDENTITY
	var stone := mats.flat(Color("#6f655b"), 0.95)
	var ember := mats.glow(Color("#ff7a2a"))
	ember.emission_energy_multiplier = 2.5
	kit.part(kit.ring(0.7, 1.05, -0.1, 0.35), stone, at)
	kit.part(kit.cyl(0.65, 0.65, 0.12, 12), ember, at + Vector3(0, 0.08, 0))
	var was: bool = kit.solid
	kit.solid = true
	for i in 4:
		var a := TAU * (float(i) + 0.35) / 4.0
		var p := at + Vector3(cos(a), 0, sin(a)) * 2.6
		kit.part(kit.box(0.7, 0.45, 0.6), kit.crate_woods[i % kit.crate_woods.size()], p + Vector3(0, 0.22, 0),
			Basis(Vector3.UP, a + 0.4))
	kit.solid = was
	var light := OmniLight3D.new()
	light.name = "Fire"
	light.light_color = Color("#ff9a4a")
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 120.0
	light.distance_fade_length = 30.0
	light.position = at + Vector3(0, 1.0, 0)
	r.root.add_child(light)


## Every mesh under `root` stops at DRAW_M (fading over DRAW_FADE): DrawDistance
## leaves a mesh with its own range alone, and a house would otherwise draw at
## any distance.
func _draw_range(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end <= 0.0:
			gi.visibility_range_end = DRAW_M
			gi.visibility_range_end_margin = DRAW_FADE
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
