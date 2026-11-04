extends RefCounted
## Market stalls (town art pass 2). Every counter box with `look: "stall"` gets a
## dressed table, a shade canopy over the vendor's side and wares on top; its back
## panel (`<id>_back`, look "stall_back") gets planks and a shelf of the same
## wares, and carries the back of the canopy. Visual only: posts stand on the
## counter or the panel, canopies are above head height. Issue #237: a stall's
## "canopy_lift" (metres) raises its canopy, for the round port's taller stalls.
##
## No two neighbours match: the canopy shape (slanted, peaked tent, twin parasols),
## its colour, and the wares (pottery, produce, cloth, tech, water, spice) all
## step along the row. `face` is the customer side (the aisle); the vendor stands
## between the counter and the back panel.
##
## Issue #355: planks, canopies and drapes are textured (StallTextures, through
## LookMaterials.wood / canvas / painted). A stall a trader works from (`trades`,
## from TownDecor: the stall nearest the vendor's marker) shows that trade instead:
## "food", "gear", "contraband" or "droids", with the trader's real items (ItemKit
## looks, content/look/items.json "stalls") along the customer's edge.

const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const CANOPIES := ["slant", "peak", "parasol"]
const WARES := ["pottery", "produce", "fabric", "tech", "water", "spice"]
const CLOTHS := [LookMaterials.CLOTH_MADDER, LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_SAFFRON,
	Color("#e6dccb"), Color("#5b3f6e"), Color("#2f5d8a")]
const TERRACOTTA := [Color("#a8603a"), Color("#c27b4a"), Color("#8e4b2e"), Color("#d9b48a"), Color("#2f7f7a")]
const FRUIT := [Color("#e08a2a"), Color("#7aa63a"), Color("#5a2a4a"), Color("#b8322a"), Color("#e2c04a")]
const SPICE := [Color("#b8322a"), Color("#d99a2b"), Color("#7a4a2a"), Color("#e2c04a"), Color("#5f7a3a")]
const CRYSTAL := Color("#7fe0ff")

var kit: TownBuildings        ## shared parts, batching and glows
var mats: LookMaterials
var awnings: Array[MeshInstance3D] = []
var wares := {}               ## stall id -> wares kind (tests, review)
var canopies := {}            ## stall id -> canopy kind
var anchors := {}             ## stall id -> { "front": Vector3, "back": Vector3 } canopy edges (world)
var items := {}               ## issue #355: stall id -> [Node3D] the trader's items on its counter
var _rng := RandomNumberGenerator.new()
var _wood: Material
var _wood_top: Material
var _iron: Material
var _item_kit: ItemKit
var _back_x := 0.0            ## local x of the back panel's near face (negative), this stall
var _panel_top := 0.0         ## its top; 0 when the stall has no back panel
var _face := "+z"             ## this stall's customer side
var _lift := 0.0              ## issue #237: how much higher this stall's canopy is (its box's "canopy_lift")


func _init(building_kit: TownBuildings) -> void:
	kit = building_kit
	mats = kit.mats
	_wood = mats.wood(Color("#6b4a32"), 0.85)
	_wood_top = mats.wood(Color("#8a6444"), 0.8)
	_iron = mats.painted(Color("#4a4440"), 0.55, 0.5)


## `backs`: back panel boxes by id ("<stall id>_back"). `trades`: stall id ->
## { "wares": kind, "items": [look id] } for the stalls traders work from.
func dress(parent: Node3D, stalls: Array, backs: Dictionary = {}, trades: Dictionary = {}) -> void:
	var list := stalls.duplicate()
	list.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for i in list.size():
		_stall(parent, list[i], i, backs.get(str(list[i].id) + "_back", {}), trades.get(str(list[i].id), {}))
	_string_lights(parent, list)


func _stall(parent: Node3D, b: Dictionary, i: int, back: Dictionary, trade: Dictionary = {}) -> void:
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var face := str(b.get("face", "+z"))
	var along_x := face.ends_with("x")
	var yaw: float = { "+x": 0.0, "-x": PI, "+z": -PI * 0.5, "-z": PI * 0.5 }.get(face, 0.0)
	kit._xf = Transform3D(Basis(Vector3.UP, yaw), Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5))
	var size := mx - mn
	var lx := size.x if along_x else size.z       # depth (customer side is +X)
	var lz := size.z if along_x else size.x       # length along the counter
	var h := size.y
	_rng.seed = hash(str(b.id))
	var id := str(b.id)
	_lift = float(b.get("canopy_lift", 0.0))
	_face = face
	# Where the back panel is, in this stall's frame (+X is the aisle).
	_back_x = -lx * 0.5 - 1.7
	_panel_top = 0.0
	if not back.is_empty():
		var bmn := Vector3(float(back.min[0]), float(back.min[1]), float(back.min[2]))
		var bmx := Vector3(float(back.max[0]), float(back.max[1]), float(back.max[2]))
		var local := kit._xf.affine_inverse() * ((bmn + bmx) * 0.5)
		var thick := (bmx.x - bmn.x) if along_x else (bmx.z - bmn.z)
		_back_x = local.x + thick * 0.5
		_panel_top = bmx.y

	# The table: cabinet, a wider top, a dyed drape on the customer side.
	var drape: Color = CLOTHS[(i * 2 + 1) % CLOTHS.size()] if str(b.get("wares", "")) != "rave" else Color("#141418")
	kit.part(kit.box(lx - 0.12, h - 0.1, lz - 0.12), _wood, Vector3(0, (h - 0.1) * 0.5, 0))
	kit.part(kit.box(lx + 0.3, 0.1, lz + 0.25), _wood_top, Vector3(0, h - 0.05, 0))
	kit.part(kit.box(0.03, 0.8, lz - 0.2), mats.canvas(drape), Vector3(lx * 0.5 - 0.03, h - 0.5, 0))

	var kind: String = CANOPIES[(i + i / 3) % CANOPIES.size()]
	var color: Color = CLOTHS[(i * 5 + 2) % CLOTHS.size()]
	if str(b.get("wares", "")) == "rave":
		kind = "neon"                 # issue #392: under the dome there is no sun to keep off
	canopies[id] = kind
	match kind:
		"slant":
			_slant(parent, id, lx, lz, h, color)
		"peak":
			_peak(parent, id, lx, lz, h, color)
		"parasol":
			_parasols(parent, id, lx, lz, h, color, CLOTHS[(i * 5 + 4) % CLOTHS.size()])
		"neon":
			_neon_frame(lz)

	var ware: String = str(trade.get("wares", b.get("wares", WARES[(i * 5) % WARES.size()])))
	if not has_method("_wares_" + ware):
		push_warning("TownMarket: no wares '%s' for %s" % [ware, id])
		ware = WARES[(i * 5) % WARES.size()]
	wares[id] = ware
	_rave_id = id
	call("_wares_" + ware, lx, lz, h)
	if trade.has("items"):
		_items(parent, id, trade.get("items", []), lx, lz, h)
	if _panel_top > 0.0:
		_back_panel(lz, ware, drape)
	# Stock waiting behind the counter, at one end, out of the vendor's way. Issue
	# #355: plank crates with an iron band, and they collide.
	if _rng.randf() < 0.7:
		var z := (lz * 0.5 - 0.35) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var was := kit.solid
		kit.solid = true
		var turn := Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3))
		kit.part(kit.box(0.6, 0.5, 0.6), kit.crate_woods[_rng.randi() % 3], Vector3(-lx * 0.5 - 0.45, 0.25, z), turn)
		kit.solid = was
		kit.part(kit.box(0.64, 0.06, 0.64), kit.crate_band, Vector3(-lx * 0.5 - 0.45, 0.33, z), turn)
		if _rng.randf() < 0.5:
			kit.solid = true
			kit.part(kit.box(0.5, 0.4, 0.5), kit.crate_woods[_rng.randi() % 3], Vector3(-lx * 0.5 - 0.45, 0.7, z), Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)))
			kit.solid = was


# ---------------------------------------------------------------- canopies

func _post(x: float, z: float, y0: float, y1: float) -> void:
	kit.part(kit.cyl(0.045, 0.055, y1 - y0, 6), _iron, Vector3(x, (y0 + y1) * 0.5, z))


## A cloth panel from edge `a` down to edge `b` (both local, mid-width), `w` wide across Z.
func _panel(parent: Node3D, a: Vector3, b: Vector3, w: float, color: Color, bow: float = 0.18) -> MeshInstance3D:
	var d := b - a
	var u := Vector3(0, 0, 1)
	var v := -d.normalized()
	var n := u.cross(v)
	var mi := MeshInstance3D.new()
	mi.mesh = LookMeshKit.cloth(w, d.length(), bow, 6, 4)
	mi.material_override = mats.canvas(color)
	mi.transform = kit._xf * Transform3D(Basis(u, v, n), a)
	mi.set_meta("decor", "awning")
	parent.add_child(mi)
	awnings.append(mi)
	return mi


## A short fringe hanging straight down from a canopy edge.
func _valance(parent: Node3D, top: Vector3, w: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = LookMeshKit.cloth(w, 0.28, 0.02, 6, 1)
	mi.material_override = mats.canvas(color.darkened(0.15))
	mi.transform = kit._xf * Transform3D(Basis(Vector3.UP, -PI * 0.5), top)
	mi.set_meta("decor", "awning")
	parent.add_child(mi)
	awnings.append(mi)


func _anchor(id: String, front: Vector3, back: Vector3) -> void:
	anchors[id] = { "front": kit._xf * front, "back": kit._xf * back, "face": _face }


## One sheet, high over the vendor, sloping down past the customer's side.
func _slant(parent: Node3D, id: String, lx: float, lz: float, h: float, color: Color) -> void:
	var top := maxf(2.95 + _lift, _panel_top + 0.3)
	var back := Vector3(_back_x - 0.25, top, 0)
	var front := Vector3(lx * 0.5 + 0.9, 2.4 + _lift, 0)
	_panel(parent, back, front, lz + 0.8, color)
	_valance(parent, front + Vector3(0, -0.02, 0), lz + 0.8, color)
	var at := func(x: float) -> float: return lerpf(top, 2.4 + _lift, (x - back.x) / (front.x - back.x)) - 0.08
	for s in [-1.0, 1.0]:
		var z: float = s * (lz * 0.5 - 0.06)
		_post(lx * 0.5 - 0.06, z, h, at.call(lx * 0.5 - 0.06))
		if _panel_top > 0.0:
			_post(_back_x - 0.2, z, _panel_top, at.call(_back_x - 0.2))     # on the back panel
		else:
			_post(-lx * 0.5 + 0.06, z, h, at.call(-lx * 0.5 + 0.06))
	_anchor(id, front, back)


## A tent: ridge over the counter's back edge, eaves both sides.
func _peak(parent: Node3D, id: String, lx: float, lz: float, h: float, color: Color) -> void:
	var ridge := Vector3((_back_x - lx * 0.5) * 0.5 if _panel_top > 0.0 else -0.3, 3.3 + _lift, 0)
	var front := Vector3(lx * 0.5 + 0.9, 2.45 + _lift, 0)
	var back := Vector3(_back_x - 0.25, _panel_top + 0.05, 0) if _panel_top > 0.0 else Vector3(-lx * 0.5 - 1.5, 2.45 + _lift, 0)
	_panel(parent, ridge, front, lz + 0.6, color, 0.12)
	_panel(parent, ridge, back, lz + 0.6, color, 0.12)
	_valance(parent, front + Vector3(0, -0.02, 0), lz + 0.6, color)
	for s in [-1.0, 1.0]:
		var z: float = s * (lz * 0.5 - 0.06)
		_post(ridge.x, z, h if ridge.x > -lx * 0.5 else 0.0, 3.22 + _lift)
	kit.part(kit.cyl(0.04, 0.04, lz + 0.6, 6), _iron, ridge + Vector3(0, -0.04, 0), kit.AXIS_Z)
	_anchor(id, front, back)


## Two parasols, one at each end of the counter, in two colours.
func _parasols(parent: Node3D, id: String, lx: float, lz: float, h: float, a: Color, b: Color) -> void:
	for k in 2:
		var z := (lz * 0.25) * (1.0 if k == 0 else -1.0)
		var c := Vector3(-0.3, 2.75 + _lift, z)
		_post(-0.3, z, h, 2.9 + _lift)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 1.75
		cone.height = 0.62
		cone.radial_segments = 10
		cone.rings = 1
		cone.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mats.canvas(a if k == 0 else b)
		mi.transform = kit._xf * Transform3D(Basis.IDENTITY, c)
		mi.set_meta("decor", "awning")
		parent.add_child(mi)
		awnings.append(mi)
		kit.part(kit.ball(0.07, 0.14, false, 8), _iron, c + Vector3(0, 0.34, 0))
	_anchor(id, Vector3(lx * 0.5 + 1.0, 2.45 + _lift, 0), Vector3(-lx * 0.5 - 1.2, 2.45 + _lift, 0))


# ---------------------------------------------------------------- wares

## Even spots along the table top, with a little jitter, between z0 and z1.
func _row(n: int, lz: float, x: float, h: float) -> Array:
	var out: Array = []
	for k in n:
		var t := (k + 0.5) / n
		out.append(Vector3(x + _rng.randf_range(-0.05, 0.05), h, (t - 0.5) * (lz - 0.4) + _rng.randf_range(-0.06, 0.06)))
	return out


func _wares_pottery(_lx: float, lz: float, h: float) -> void:
	for p in _row(6, lz, 0.05, h):
		var r := _rng.randf_range(0.11, 0.2)
		var tall := r * _rng.randf_range(1.8, 2.8)
		var c: Color = TERRACOTTA[_rng.randi() % TERRACOTTA.size()]
		var m := mats.flat(c, 0.75)
		kit.part(kit.ball(r, tall, false, 12), m, p + Vector3(0, tall * 0.5, 0))
		kit.part(kit.cyl(r * 0.45, r * 0.5, 0.08, 10), m, p + Vector3(0, tall + 0.02, 0))
	for p in _row(4, lz, -0.3, h):
		kit.part(kit.cyl(0.12, 0.08, 0.1, 10), mats.flat(TERRACOTTA[_rng.randi() % 3], 0.75), p + Vector3(0, 0.05, 0))


func _wares_produce(_lx: float, lz: float, h: float) -> void:
	var basket := mats.flat(Color("#9a7a4a"), 0.95)
	for p in _row(3, lz, 0.0, h):
		kit.part(kit.cyl(0.32, 0.26, 0.14, 14), basket, p + Vector3(0, 0.07, 0))
		var m := mats.flat(FRUIT[_rng.randi() % FRUIT.size()], 0.6)
		var r := _rng.randf_range(0.06, 0.09)
		for k in 7:
			var a := TAU * k / 7.0
			var off := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.17)
			kit.part(kit.ball(r, r * 2.0, false, 8), m, p + off + Vector3(0, 0.15 + (0.04 if k == 0 else 0.0), 0))


func _wares_fabric(_lx: float, lz: float, h: float) -> void:
	var n := 7
	for k in n:
		var z := (float(k) / (n - 1) - 0.5) * (lz - 0.6)
		var c: Color = CLOTHS[(k + _rng.randi()) % CLOTHS.size()]
		kit.part(kit.cyl(0.11, 0.11, 0.75, 10), mats.cloth(c), Vector3(0, h + 0.11, z), kit.AXIS_X)
		if k < n - 1:
			var c2: Color = CLOTHS[(k + 3) % CLOTHS.size()]
			kit.part(kit.cyl(0.1, 0.1, 0.7, 10), mats.cloth(c2.lightened(0.1)), Vector3(0, h + 0.3, z + (lz - 0.6) / (n - 1) * 0.5), kit.AXIS_X)


func _wares_tech(_lx: float, lz: float, h: float) -> void:
	for p in _row(4, lz, -0.15, h):
		var s := Vector3(_rng.randf_range(0.2, 0.4), _rng.randf_range(0.12, 0.3), _rng.randf_range(0.2, 0.4))
		kit.part(kit.box(snappedf(s.x, 0.05), snappedf(s.y, 0.05), snappedf(s.z, 0.05)), kit.trim, p + Vector3(0, s.y * 0.5, 0), Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)))
	for p in _row(6, lz, 0.25, h):
		kit.part(kit.cyl(0.05, 0.05, 0.22, 8), kit.door_glow, p + Vector3(0, 0.11, 0))
	kit.part(kit.ring(0.1, 0.17, 0.0, 0.06, 14), kit.metal, Vector3(0.1, h, lz * 0.3))
	# A salvaged readout panel, tilted toward the customer.
	kit.part(kit.box(0.05, 0.3, 0.45), kit.door_glow, Vector3(-0.25, h + 0.2, -lz * 0.32), Basis(Vector3.BACK, -0.35))


func _wares_water(_lx: float, lz: float, h: float) -> void:
	var can := mats.flat(Color("#5b6f78"), 0.4, 0.6)
	for row in [-0.15, 0.2]:
		for p in _row(6, lz - 0.9, row, h):
			kit.part(kit.cyl(0.09, 0.1, 0.38, 10), can, p + Vector3(0, 0.19, -0.45))
	kit.part(kit.cyl(0.3, 0.32, 0.55, 14), mats.flat(Color("#3f5a63"), 0.45, 0.5), Vector3(0, h + 0.275, lz * 0.5 - 0.4))
	kit.part(kit.box(0.2, 0.05, 0.05), kit.metal, Vector3(0.38, h + 0.1, lz * 0.5 - 0.4))


func _wares_spice(_lx: float, lz: float, h: float) -> void:
	var sack := mats.cloth(LookMaterials.CLOTH_SAND)
	for p in _row(5, lz - 0.8, 0.0, h):
		var q: Vector3 = p + Vector3(0, 0, -0.4)
		kit.part(kit.ball(0.22, 0.34, false, 12), sack, q + Vector3(0, 0.15, 0))
		kit.part(kit.cyl(0.16, 0.16, 0.04, 12), mats.flat(SPICE[_rng.randi() % SPICE.size()], 1.0), q + Vector3(0, 0.3, 0))
	# A brass balance at the end.
	var brass := mats.flat(Color("#b08a3a"), 0.4, 0.8)
	var z := lz * 0.5 - 0.4
	kit.part(kit.cyl(0.08, 0.1, 0.35, 8), brass, Vector3(0, h + 0.175, z))
	kit.part(kit.box(0.04, 0.03, 0.5), brass, Vector3(0, h + 0.37, z))
	for s in [-0.22, 0.22]:
		kit.part(kit.cyl(0.09, 0.07, 0.03, 10), brass, Vector3(0, h + 0.22, z + s))


# ---------------------------------------------------------------- traders' wares (issue #355)

## The food stall: baskets of fruit at the back, stacks of flatbread and a row of
## clay jars toward the customer (its quartz case, what it buys, is an item).
func _wares_food(_lx: float, lz: float, h: float) -> void:
	var basket := mats.flat(Color("#9a7a4a"), 0.95)
	for p in _row(3, lz, -0.25, h):
		kit.part(kit.cyl(0.26, 0.2, 0.14, 14), basket, p + Vector3(0, 0.07, 0))
		var m := mats.flat(FRUIT[_rng.randi() % FRUIT.size()], 0.6)
		for k in 6:
			var a := TAU * k / 6.0
			var off := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.13)
			kit.part(kit.ball(0.07, 0.14, false, 8), m, p + off + Vector3(0, 0.15 + (0.04 if k == 0 else 0.0), 0))
	var bread := mats.flat(Color("#c99a5a"), 0.95)
	for k in 2:
		var p := Vector3(0.2, h, -lz * 0.3 + k * 0.36)
		for n in 4:
			kit.part(kit.cyl(0.16, 0.16, 0.03, 12), bread, p + Vector3(_rng.randf_range(-0.02, 0.02), 0.015 + n * 0.032, 0))
	for p in _row(3, lz * 0.35, 0.25, h):
		var c := mats.flat(TERRACOTTA[_rng.randi() % 3], 0.75)
		kit.part(kit.ball(0.1, 0.22, false, 10), c, p + Vector3(0, 0.11, lz * 0.3))


## The gear trader: a coil of rope, a dark helmet and a rack of charged cells at
## the back; the jetpack and the cases it trades in are items.
func _wares_gear(_lx: float, lz: float, h: float) -> void:
	var rope := mats.flat(Color("#9a8460"), 0.95)
	for k in 3:
		kit.part(kit.ring(0.1, 0.17, 0.0, 0.05, 14), rope, Vector3(-0.3, h + k * 0.05, -lz * 0.5 + 0.45))
	kit.part(kit.ball(0.17, 0.26, true, 12), mats.painted(Color("#3a3c40"), 0.45, 0.5), Vector3(-0.3, h, lz * 0.5 - 0.4))
	kit.part(kit.box(0.2, 0.06, 0.7), _iron, Vector3(-0.32, h + 0.03, 0))
	for k in 5:
		kit.part(kit.cyl(0.04, 0.04, 0.2, 8), kit.door_glow, Vector3(-0.32, h + 0.16, -0.28 + k * 0.14))


## The fence: a tarp thrown half over a crate, a few loose crystals and a locked
## strongbox; the contraband he pays for is items.
func _wares_contraband(_lx: float, lz: float, h: float) -> void:
	var z := -lz * 0.5 + 0.5
	kit.part(kit.box(0.6, 0.35, 0.6), kit.trim, Vector3(-0.25, h + 0.175, z))
	kit.part(kit.box(0.66, 0.03, 0.4), mats.canvas(Color("#5f5a48")), Vector3(-0.25, h + 0.365, z + 0.12), Basis(Vector3.RIGHT, 0.1))
	var crystal := mats.glow(CRYSTAL)
	crystal.emission_energy_multiplier = 0.6
	for k in 4:
		var p := Vector3(-0.3 + _rng.randf_range(-0.05, 0.05), h, lz * 0.5 - 0.35 - k * 0.12)
		kit.part(kit.cyl(0.0, 0.035, 0.12 + k * 0.02, 5), crystal, p + Vector3(0, 0.06 + k * 0.01, 0), Basis(Vector3.BACK, _rng.randf_range(-0.4, 0.4)))
	kit.part(kit.box(0.35, 0.22, 0.25), mats.painted(Color("#2f3a34"), 0.5, 0.55), Vector3(-0.32, h + 0.11, 0.0))


## The droid merchant: droid heads with one lit eye each, arm segments and a servo
## ring at the back; a power cell case is an item.
func _wares_droids(_lx: float, lz: float, h: float) -> void:
	var shell := mats.painted(Color("#8a8278"), 0.5, 0.55)
	var dark := mats.painted(Color("#2e3034"), 0.5, 0.5)
	var eye := mats.glow(Color("#ff5a3a"))
	eye.emission_energy_multiplier = 1.2
	for p in _row(3, lz * 0.55, -0.3, h):
		var q: Vector3 = p + Vector3(0, 0, -lz * 0.2)
		kit.part(kit.ball(0.15, 0.26, false, 12), shell, q + Vector3(0, 0.13, 0))
		kit.part(kit.ball(0.04, 0.04, false, 8), eye, q + Vector3(0.13, 0.17, 0))
		kit.part(kit.cyl(0.08, 0.1, 0.05, 10), dark, q + Vector3(0, 0.02, 0))
	for k in 2:
		var z := lz * 0.5 - 0.45 - k * 0.3
		kit.part(kit.cyl(0.035, 0.035, 0.45, 8), shell, Vector3(-0.3, h + 0.04, z), kit.AXIS_X)
		kit.part(kit.ball(0.05, 0.1, false, 8), dark, Vector3(-0.08, h + 0.05, z))
	kit.part(kit.ring(0.06, 0.12, 0.0, 0.05, 14), dark, Vector3(0.0, h, lz * 0.5 - 0.3))


# ---------------------------------------------------------------- the rave's stalls (issue #392)

const RAVE_GOODS := ["beads", "glow", "shirts", "vials", "snacks", "signs"]
## Two kinds of goods a stall, never the same two as the stall before it.
const RAVE_MIXES := [["beads", "glow"], ["shirts", "vials"], ["snacks", "signs"], ["glow", "shirts"],
	["vials", "beads"], ["signs", "snacks"]]
const NEON := [Color("#ff2bd6"), Color("#2bd9ff"), Color("#7aff5a"), Color("#ffe14a"), Color("#a05bff")]
var rave_goods := {}          ## stall id -> [goods] (tests, review)
var _rave_n := 0
var _rave_id := ""


## The moon rave's stalls: no canopy, a neon tube along the counter's front edge,
## and two of the rave's goods on the table (RAVE_MIXES, a different pair each
## stall): bead strands, glow sticks, band shirts on a rail, jars and vials,
## snack bowls, little neon signs.
func _wares_rave(lx: float, lz: float, h: float) -> void:
	var mix: Array = RAVE_MIXES[_rave_n % RAVE_MIXES.size()]
	_rave_n += 1
	rave_goods[_rave_id] = mix
	var tube := _neon_mat(NEON[_rave_n % NEON.size()])
	kit.part(kit.box(0.03, 0.03, lz + 0.2), tube, Vector3(lx * 0.5 + 0.14, h - 0.08, 0))
	kit.part(kit.box(0.03, 0.03, lz + 0.2), tube, Vector3(lx * 0.5 + 0.14, 0.12, 0))
	for k in mix.size():
		var z0 := -lz * 0.5 + 0.25 + k * lz * 0.5
		call("_rave_" + str(mix[k]), z0, z0 + lz * 0.5 - 0.5, h)


## Issue #392: a rave stall's "canopy": a neon tube round the top of its back
## panel (or a frame on posts where it has none), in this stall's colour.
func _neon_frame(lz: float) -> void:
	var m := _neon_mat(NEON[(_rave_n + 3) % NEON.size()])
	var x := _back_x + 0.03
	var top := _panel_top if _panel_top > 0.0 else 2.4
	if _panel_top <= 0.0:
		for z in [-lz * 0.5, lz * 0.5]:
			_post(x, z, 0.0, top)
	kit.part(kit.box(0.03, 0.03, lz), m, Vector3(x, top - 0.05, 0))
	for z in [-lz * 0.5 + 0.02, lz * 0.5 - 0.02]:
		kit.part(kit.box(0.03, top - 0.3, 0.03), m, Vector3(x, (top - 0.05 + 0.25) * 0.5, z))


func _neon_mat(c: Color) -> StandardMaterial3D:
	var m := mats.glow(c)
	m.emission_energy_multiplier = 2.5
	return m


func _rave_beads(z0: float, z1: float, h: float) -> void:
	# Strands looped over a rod on two posts, more piled on the table.
	kit.part(kit.cyl(0.015, 0.015, 0.5, 6), _iron, Vector3(-0.2, h + 0.25, z0 + 0.05))
	kit.part(kit.cyl(0.015, 0.015, 0.5, 6), _iron, Vector3(-0.2, h + 0.25, z1 - 0.05))
	kit.part(kit.cyl(0.012, 0.012, z1 - z0, 6), _iron, Vector3(-0.2, h + 0.5, (z0 + z1) * 0.5), kit.AXIS_Z)
	var n := int((z1 - z0) / 0.12)
	for k in n:
		var c: Color = NEON[(k + _rave_n) % NEON.size()]
		var m := mats.flat(c, 0.25, 0.3)
		var z := z0 + 0.06 + k * (z1 - z0 - 0.12) / maxf(n - 1, 1)
		kit.part(kit.ring(0.11, 0.125, 0.0, 0.02, 14), m, Vector3(-0.2, h + 0.39, z), Basis(Vector3.BACK, PI * 0.5))
	for k in 4:
		var m := mats.flat(NEON[(k * 2 + _rave_n) % NEON.size()], 0.25, 0.3)
		kit.part(kit.ring(0.06, 0.08, 0.0, 0.025, 12), m, Vector3(0.2, h, lerpf(z0, z1, (k + 0.5) / 4.0)))


func _rave_glow(z0: float, z1: float, h: float) -> void:
	# Glow sticks standing in three cups, a bundle lying in front.
	for k in 3:
		var z := lerpf(z0, z1, (k + 0.5) / 3.0)
		kit.part(kit.cyl(0.08, 0.07, 0.14, 12), kit.trim, Vector3(-0.15, h + 0.07, z))
		for j in 6:
			var a := TAU * j / 6.0
			var tilt := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.18)
			kit.part(kit.cyl(0.008, 0.008, 0.3, 6), _neon_mat(NEON[(j + k) % NEON.size()]),
				Vector3(-0.15 + cos(a) * 0.04, h + 0.18, z + sin(a) * 0.04), tilt)
	for j in 5:
		kit.part(kit.cyl(0.008, 0.008, 0.28, 6), _neon_mat(NEON[j % NEON.size()]),
			Vector3(0.22, h + 0.01 + (j % 2) * 0.016, lerpf(z0, z1, 0.2 + j * 0.15)), kit.AXIS_X)


func _rave_shirts(z0: float, z1: float, h: float) -> void:
	# Band shirts on hangers along a rail standing on the table.
	for z in [z0 + 0.05, z1 - 0.05]:
		kit.part(kit.cyl(0.015, 0.015, 1.0, 6), _iron, Vector3(-0.1, h + 0.5, z))
	kit.part(kit.cyl(0.012, 0.012, z1 - z0, 6), _iron, Vector3(-0.1, h + 0.98, (z0 + z1) * 0.5), kit.AXIS_Z)
	var n := maxi(3, int((z1 - z0) / 0.16))
	for k in n:
		var z := lerpf(z0 + 0.15, z1 - 0.15, float(k) / maxf(n - 1, 1))
		var c: Color = [Color("#141418"), Color("#2a1038"), Color("#0e2a30"), Color("#3a0e1e")][k % 4]
		kit.part(kit.box(0.42, 0.5, 0.03), mats.cloth(c), Vector3(-0.1, h + 0.66, z), Basis(Vector3.UP, PI * 0.5))
		kit.part(kit.box(0.2, 0.14, 0.032), _neon_mat(NEON[(k + _rave_n) % NEON.size()]), Vector3(-0.1, h + 0.72, z), Basis(Vector3.UP, PI * 0.5))


func _rave_vials(z0: float, z1: float, h: float) -> void:
	# A tray of little jars and vials, each with a glowing drop inside.
	kit.part(kit.box(0.5, 0.03, z1 - z0), kit.trim, Vector3(0.0, h + 0.015, (z0 + z1) * 0.5))
	var rows := 3
	var cols := maxi(3, int((z1 - z0) / 0.12))
	for r in rows:
		for k in cols:
			var p := Vector3(-0.16 + r * 0.16, h + 0.03, lerpf(z0 + 0.08, z1 - 0.08, float(k) / maxf(cols - 1, 1)))
			var tall := 0.07 + float((r + k) % 3) * 0.035
			var glass := mats.flat(Color(0.8, 0.9, 1.0), 0.05, 0.2)
			kit.part(kit.cyl(0.028, 0.03, tall, 8), glass, p + Vector3(0, tall * 0.5, 0))
			kit.part(kit.cyl(0.022, 0.022, tall * 0.55, 8), _neon_mat(NEON[(r * 2 + k) % NEON.size()]), p + Vector3(0, tall * 0.3, 0))
			kit.part(kit.cyl(0.02, 0.02, 0.02, 8), mats.flat(Color("#1a1a1e"), 0.6), p + Vector3(0, tall + 0.01, 0))


func _rave_snacks(z0: float, z1: float, h: float) -> void:
	# Bowls of bright snacks.
	var n := maxi(2, int((z1 - z0) / 0.4))
	for k in n:
		var p := Vector3(-0.05 + (k % 2) * 0.15, h, lerpf(z0 + 0.2, z1 - 0.2, float(k) / maxf(n - 1, 1)))
		kit.part(kit.cyl(0.18, 0.12, 0.1, 14), mats.painted(Color("#26262a"), 0.4, 0.6), p + Vector3(0, 0.05, 0))
		var m := mats.flat(NEON[(k + _rave_n + 2) % NEON.size()].lerp(Color.WHITE, 0.2), 0.7)
		for j in 7:
			var a := TAU * j / 7.0
			var off := Vector3(cos(a), 0, sin(a)) * (0.0 if j == 0 else 0.09)
			kit.part(kit.ball(0.04, 0.06, false, 6), m, p + off + Vector3(0, 0.11 + (0.02 if j == 0 else 0.0), 0))


func _rave_signs(z0: float, z1: float, h: float) -> void:
	# Little neon signs on stands: a ring, a zigzag and a star of tubes.
	var n := 3
	for k in n:
		var z := lerpf(z0 + 0.2, z1 - 0.2, float(k) / (n - 1))
		var m := _neon_mat(NEON[(k + _rave_n + 1) % NEON.size()])
		kit.part(kit.box(0.04, 0.4, 0.04), _iron, Vector3(-0.2, h + 0.2, z))
		kit.part(kit.box(0.06, 0.02, 0.36), kit.trim, Vector3(-0.2, h + 0.01, z))
		var c := Vector3(-0.2, h + 0.58, z)
		match k % 3:
			0:
				kit.part(kit.ring(0.14, 0.16, -0.01, 0.01, 18), m, c, Basis(Vector3.BACK, PI * 0.5))
			1:
				for j in 4:
					var a := Vector3(0, (j % 2) * 0.2 - 0.1, -0.18 + j * 0.12)
					var b := Vector3(0, ((j + 1) % 2) * 0.2 - 0.1, -0.18 + (j + 1) * 0.12)
					var d := b - a
					kit.part(kit.box(0.02, 0.02, d.length()), m, c + (a + b) * 0.5, Basis.looking_at(d, Vector3.RIGHT))
			_:
				for j in 3:
					kit.part(kit.box(0.02, 0.32, 0.02), m, c, Basis(Vector3.RIGHT, PI * j / 3.0))


## The trader's own items (ItemKit looks) along the customer's edge of the counter,
## a case's latch (or the jetpack's front) to the aisle, each sitting on the top.
## Real nodes, not batched: an item can be a model.
func _items(parent: Node3D, id: String, looks: Array, lx: float, lz: float, h: float) -> void:
	if _item_kit == null:
		_item_kit = ItemKit.new(mats)
	var built: Array = []
	var widths: Array = []
	var total := 0.0
	for l in looks:
		var look_id := str(l)
		if not _item_kit.has_look(look_id):
			push_warning("TownMarket: no item look '%s' for %s" % [look_id, id])
			continue
		var node := _item_kit.build(look_id)
		# Cases lie with their latch (-Z) to the aisle, so their width runs along the
		# counter; the jetpack stands with its front (+Z) to the aisle.
		var turn := Basis(Vector3.UP, -PI * 0.5 if str(_item_kit.look(look_id).get("frame", "")) == "case" else PI * 0.5)
		var box := ItemKit.bounds(node, Transform3D(turn, Vector3.ZERO))
		if total + box.size.z > lz - 0.3:
			node.free()
			continue
		node.transform = Transform3D(turn, Vector3(0, -box.position.y, 0))
		node.set_meta("decor", "stall_item")
		built.append([node, box])
		widths.append(box.size.z)
		total += box.size.z
	if built.is_empty():
		return
	var gap := (lz - 0.3 - total) / built.size()
	var z := -(lz - 0.3) * 0.5 + gap * 0.5
	var out: Array = []
	for k in built.size():
		var node: Node3D = built[k][0]
		var box: AABB = built[k][1]
		var x := lx * 0.5 - 0.12 - (box.position.x + box.size.x)    # its front edge just in from the counter's
		var local := Transform3D(node.transform.basis, Vector3(x, h, z - box.position.z) + node.transform.origin)
		node.transform = kit._xf * local
		parent.add_child(node)
		out.append(node)
		z += widths[k] + gap
	items[id] = out


# ---------------------------------------------------------------- lights

## Strings of bulbs across the aisle, from each stall to the one facing it.
func _string_lights(parent: Node3D, _stalls: Array) -> void:
	var cable := mats.flat(Color("#2b2522"), 0.7)
	var bulb := kit.ball(0.06, 0.12, false, 6)
	var ids := anchors.keys()
	ids.sort()
	for a_id in ids:
		var a: Dictionary = anchors[a_id]
		var best := ""
		var best_d := INF
		for b_id in ids:
			if b_id <= a_id:
				continue          # each pair once
			var b: Dictionary = anchors[b_id]
			var d: float = (a.front as Vector3).distance_to(b.front)
			# Facing each other across the aisle, lined up along the counters.
			var fa := str(a.get("face", "+z"))
			var across_z := fa.ends_with("z")
			var lateral := absf((a.front as Vector3).x - (b.front as Vector3).x) if across_z \
				else absf((a.front as Vector3).z - (b.front as Vector3).z)
			if d < best_d and str(b.get("face", "")) == ("-" if fa.begins_with("+") else "+") + fa.substr(1) and lateral < 1.0:
				best_d = d
				best = b_id
		if best == "" or best_d > 16.0:
			continue
		var p0: Vector3 = a.front + Vector3(0, -0.05, 0)
		var p1: Vector3 = anchors[best].front + Vector3(0, -0.05, 0)
		var pts := LookMeshKit.catenary(p0, p1, 0.6, 16)
		var mi := MeshInstance3D.new()
		mi.mesh = LookMeshKit.tube(pts, 0.015, 4)
		mi.material_override = cable
		parent.add_child(mi)
		for k in range(1, pts.size() - 1):
			kit.put(bulb, kit.window_glow, Transform3D(Basis.IDENTITY, pts[k] + Vector3(0, -0.08, 0)))


## The back panel: planks, a cross rail, and a shelf of the stall's wares at
## eye height on the vendor's side, with a strip of the drape's cloth along the top.
func _back_panel(lz: float, ware: String, drape: Color) -> void:
	var x := _back_x - 0.2
	var top := _panel_top
	for k in 5:
		var z := -lz * 0.5 + (k + 0.5) * lz / 5.0
		kit.part(kit.box(0.42, top, lz / 5.0 - 0.04), _wood if k % 2 == 0 else _wood_top, Vector3(x, top * 0.5, z))
	kit.part(kit.box(0.46, 0.12, lz + 0.1), kit.trim, Vector3(x, top - 0.3, 0))
	kit.part(kit.box(0.04, 0.35, lz - 0.2), mats.cloth(drape), Vector3(_back_x + 0.03, top - 0.6, 0))
	var sy := 1.55
	kit.part(kit.box(0.34, 0.05, lz - 0.5), _wood_top, Vector3(_back_x + 0.17, sy, 0))
	for k in 6:
		var z := -lz * 0.5 + 0.55 + k * (lz - 1.1) / 5.0
		var p := Vector3(_back_x + 0.17, sy + 0.025, z)
		match ware:
			"pottery":
				kit.part(kit.ball(0.09, 0.22, false, 10), mats.flat(TERRACOTTA[k % TERRACOTTA.size()], 0.75), p + Vector3(0, 0.11, 0))
			"produce":
				kit.part(kit.ball(0.08, 0.16, false, 8), mats.flat(FRUIT[k % FRUIT.size()], 0.6), p + Vector3(0, 0.08, 0))
			"fabric":
				kit.part(kit.box(0.25, 0.12, 0.3), mats.cloth(CLOTHS[k % CLOTHS.size()]), p + Vector3(0, 0.06, 0))
			"tech":
				kit.part(kit.cyl(0.05, 0.05, 0.2, 8), kit.door_glow, p + Vector3(0, 0.1, 0))
			"water":
				kit.part(kit.cyl(0.08, 0.09, 0.3, 10), mats.flat(Color("#5b6f78"), 0.4, 0.6), p + Vector3(0, 0.15, 0))
			"food":
				kit.part(kit.cyl(0.13, 0.13, 0.03, 12), mats.flat(Color("#c99a5a"), 0.95), p + Vector3(0, 0.015, 0))
				kit.part(kit.ball(0.07, 0.14, false, 8), mats.flat(FRUIT[k % FRUIT.size()], 0.6), p + Vector3(0, 0.1, 0))
			"gear", "contraband":
				kit.part(kit.box(0.26, 0.16, 0.3), kit.trim, p + Vector3(0, 0.08, 0))
			"droids":
				kit.part(kit.ball(0.09, 0.16, false, 10), mats.painted(Color("#8a8278"), 0.5, 0.55), p + Vector3(0, 0.08, 0))
			"rave":
				kit.part(kit.cyl(0.05, 0.05, 0.18, 8), _neon_mat(NEON[(k + _rave_n) % NEON.size()]), p + Vector3(0, 0.09, 0))
			_:
				kit.part(kit.cyl(0.07, 0.08, 0.16, 10), mats.flat(SPICE[k % SPICE.size()], 0.9), p + Vector3(0, 0.08, 0))

