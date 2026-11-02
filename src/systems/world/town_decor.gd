extends Node3D
## Visual dressing for the port town. Reads the same TownLayout data as the
## gameplay layer. Replaced piece by piece by future art passes.
##
## Rules (docs/town/TOWN_PLAN.md addendum, D1 to D6, as changed by art pass 2):
##   - never moves or resizes a box, never edits port_town.json
##   - issue #55: the only collision it adds is the props' (lamp posts, bay posts,
##     fuel pods, pit clutter, and the kit's roof props): one box each, in the
##     kit's "Props" body. The town's boxes, the nav and the routes are untouched.
##   - no character art
##   - look numbers come from LookMaterials constants or time_of_day.json
## Art pass 2: a box with a `look` is drawn by the building kit (town_buildings.gd)
## and its greybox mesh is hidden; market stalls get canopies and wares
## (town_market.gd); alleys get cables and pennants, the main street lamp posts.
## Lamp posts and string lights are glow only: the omni light budget stays as it was.
## `_lamp_at` and `_banner` are copies of the beauty corner helpers, on purpose:
## the beauty corner is the art reference and is not edited.

const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const TownMarket := preload("res://src/systems/world/town_market.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const PitBowl := preload("res://src/systems/world/pit_bowl.gd")
const RingWall := preload("res://src/systems/world/ring_wall.gd")
const StairTower := preload("res://src/systems/world/stair_tower.gd")
const STAIR_LIGHT := Color("#ffbe78")

var mats: LookMaterials
var look: LookEnvironment
var lamps: Array[OmniLight3D] = []
var banners: Array[MeshInstance3D] = []
var parked_ships: Array[Node3D] = []   ## ship models on launch pads (same as flight)
var skipped_kinds := {}       ## kind -> true, for boxes that keep their greybox color
var kit: TownBuildings        ## building variants, shared parts, batching
var market: TownMarket        ## the stalls
var cables: Array[MeshInstance3D] = []
var style: TownStyle          ## issue #45: the planet's town style (null = the port's own look)
var location_id := "port_town"   ## issue #355: whose vendors work the stalls (content/core/vendors "location")
var _rng := RandomNumberGenerator.new()


func dress(town, look_env: LookEnvironment) -> void:
	name = "TownDecor"
	look = look_env
	mats = LookMaterials.new()
	mats.style = style
	_rng.seed = 9001                      # fixed seed: same town every run
	_apply_materials(town)
	kit = TownBuildings.new(mats, look)
	kit.town = town
	_build_buildings(town)
	_dress_cantina(town)
	_light_stair_tower(town)
	_dress_spaceport(town)
	_dress_market(town)
	_add_alley_cables(town)
	_add_street_lamps(town)
	var parts := Node3D.new()
	parts.name = "Buildings"
	add_child(parts)
	kit.flush(parts)
	_add_lamps(town)
	_add_banners(town)
	_park_ships(town)


# ---------------------------------------------------------------- materials

func _box_mesh(id: String) -> MeshInstance3D:
	var body := get_parent().get_node_or_null("Town/" + id)
	if body == null:
		return null
	for c in body.get_children():
		if c is MeshInstance3D:
			return c
	return null


func _inside_bounds(town, b: Dictionary) -> bool:
	var bounds: Dictionary = town.data.get("bounds", {})
	if bounds.is_empty():
		return true
	return float(b.min[0]) >= float(bounds.min[0]) and float(b.max[0]) <= float(bounds.max[0]) \
		and float(b.min[2]) >= float(bounds.min[1]) and float(b.max[2]) <= float(bounds.max[1])


## The material for one box, per the addendum's table. null = keep greybox.
func material_for(town, b: Dictionary) -> Material:
	var id := str(b.id)
	var kind := str(b.kind)
	var zone := str(b.get("zone", ""))
	var min_y := float(b.min[1])
	var h := float(b.max[1]) - min_y
	const BANDS := [LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_MADDER,
		LookMaterials.CLOTH_SAFFRON, LookMaterials.CLOTH_SAND]

	# Ids first: they override their kind's row.
	if id == "pit_floor":
		return mats.hull(-6.0, 6.0)
	if id == "dock_booth":
		return mats.hull(0.0, 1.5)
	match kind:
		"floor":
			if zone == "ground":
				return mats.paving(2.4) if _inside_bounds(town, b) else mats.flat(LookMaterials.CLOTH_SAND)
			if zone == "barracks":                 # issue #237: the drill yard, packed earth
				return mats.flat(Color("#8a7458"), 0.95)
		"wall", "ring":
			if zone == "perimeter":                # issue #393: the wall wears the town's owner
				return mats.faction_plaster(0.0, 5.2, "wall")
			if zone == "spaceport":
				return mats.plaster(-6.0, -1.0, LookMaterials.CLOTH_SAFFRON)
			if zone == "cantina":
				return mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
		"overhead", "roof":
			if zone == "perimeter":              # issue #45: the gate lintel, like its walls
				return mats.faction_plaster(0.0, 5.2, "wall")
			if zone == "cantina":
				return mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
			if zone == "residential_e" or zone == "barracks":
				return mats.hull(-50.0, 1.2)        # rooftop bridges
		"solid":
			if zone == "residential_w" or zone == "residential_e":
				return mats.plaster(0.0, h * 0.35, BANDS[_rng.randi() % BANDS.size()])
			if zone == "market":
				return mats.plaster(0.0, 1.4, LookMaterials.CLOTH_SAFFRON)
			if zone == "barracks" or zone == "perimeter":      # issue #237: the round port's gate towers
				return mats.faction_plaster(0.0, 2.0, "band")
		"ship":
			return mats.hull(-6.0, 4.0)
		"pad":                                       # issue #58: the empty pad's plate
			return mats.pad_metal(minf(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2])) * 0.5, _pad_dust())
		"bowl":
			return mats.plaster(-6.0, -1.0, LookMaterials.CLOTH_SAFFRON)
		"spiral", "lookout":
			return mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
		"cover", "counter", "ramp":
			return mats.hull(min_y, 0.8)
	return null


func _apply_materials(town) -> void:
	for b in town.boxes():
		var mi := _box_mesh(str(b.id))
		if mi == null:
			push_warning("TownDecor: no gameplay node for box " + str(b.id))
			continue
		var m := material_for(town, b)
		if m == null:
			var key := str(b.kind)
			if not skipped_kinds.has(key):
				skipped_kinds[key] = true
				push_warning("TownDecor: no decor material for kind '%s' (keeps greybox)" % key)
			continue
		mi.material_override = m


## How much sand has blown onto the pads: the port's own look is the desert's; a
## styled town with metal walls is a sealed station.
func _pad_dust() -> float:
	if style == null or style.is_identity():
		return 0.45
	return 0.0 if style.metal_walls else 0.25


## A round steel plate on the floor at `at` (its own mesh, not batched: the shader
## lays its rings out from the mesh's centre). Visual only, like the empty pads'.
func _pad_plate(at: Vector3, radius := 6.0, height := 0.03) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 48
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "PadPlate"
	mi.mesh = cm
	mi.material_override = mats.pad_metal(radius, _pad_dust())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at + Vector3(0, height * 0.5, 0)
	add_child(mi)


# ---------------------------------------------------------------- buildings

## Every box with a `look` the kit knows is drawn by the kit; its greybox mesh is
## hidden, its collision stays.
func _build_buildings(town) -> void:
	for b in town.boxes():
		if not b.has("look") or str(b.look) in ["stall", "stall_back"]:
			continue
		if kit.build(b):
			var mi := _box_mesh(str(b.id))
			if mi != null:
				mi.visible = false
		else:
			push_warning("TownDecor: no building look '%s' for %s" % [b.look, b.id])


func _dress_market(town) -> void:
	var stalls: Array = []
	var backs := {}
	for b in town.boxes():
		var look := str(b.get("look", ""))
		if look == "stall" or look == "stall_back":
			if look == "stall":
				stalls.append(b)
			else:
				backs[str(b.id)] = b
			var mi := _box_mesh(str(b.id))
			if mi != null:
				mi.visible = false
	var root := Node3D.new()
	root.name = "Market"
	add_child(root)
	market = TownMarket.new(kit)
	market.dress(root, stalls, backs, _stall_trades(town, stalls))


## Issue #355: the stall each trader works from (the one nearest its marker) ->
## what it shows: its vendor's block in content/look/items.json "stalls". The
## vendors are this location's (content/core/vendors) and the droid merchant
## (droids.json "vendor"), wherever its marker is.
func _stall_trades(town, stalls: Array) -> Dictionary:
	var looks: Dictionary = ItemKit._read_json(ItemKit.LOOKS_PATH).get("stalls", {}).get("vendors", {})
	var vendors: Array = []
	var cc := CoreContent.new()
	if cc.load_from():
		vendors = cc.vendors_in(location_id)
	var droid_vendor: Dictionary = DroidRoster.config().get("vendor", {})
	if not droid_vendor.is_empty():
		vendors.append(droid_vendor)
	var out := {}
	for v in vendors:
		var marker: Dictionary = town.get_marker(str(v.get("marker", "")))
		var look: Dictionary = looks.get(str(v.get("id", "")), {})
		if marker.is_empty() or look.is_empty():
			continue
		var at := _v3(marker.pos)
		var best := ""
		var best_d := 6.0               # metres: a vendor further than this from every counter has no stall
		for b in stalls:
			var mid := (_v3(b.min) + _v3(b.max)) * 0.5
			var d := Vector2(mid.x - at.x, mid.z - at.z).length()
			if d < best_d and not out.has(str(b.id)):
				best_d = d
				best = str(b.id)
		if best != "":
			out[best] = look
	return out


## The cantina hall (art pass 2): a tall room with a stage, so the shell gets
## pilasters and beams inside, a roof parapet and relays outside, and an arched
## portal with a glowing lunette over the door. Positions come from its wall boxes.
func _dress_cantina(town) -> void:
	var body: Dictionary = town.get_box("cantina_body")
	if not body.is_empty():
		_dress_round_cantina(town, body)
		return
	var w: Dictionary = town.get_box("cantina_wall_w")
	var n: Dictionary = town.get_box("cantina_wall_n")
	var s: Dictionary = town.get_box("cantina_wall_s")
	var e: Dictionary = town.get_box("cantina_wall_e_s")
	var lintel: Dictionary = town.get_box("cantina_door_lintel")
	if w.is_empty() or n.is_empty() or s.is_empty() or e.is_empty() or lintel.is_empty():
		return
	var x0 := float(w.max[0])             # inside faces
	var x1 := float(e.min[0])
	var z0 := float(s.max[2])
	var z1 := float(n.min[2])
	var top := float(n.max[1])
	var shell := mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
	var tower: Dictionary = town.get_box("stair_tower")
	kit._xf = Transform3D.IDENTITY
	# Inside: pilasters on the long walls with a lamp each, beams across the ceiling.
	var x := x0 + 3.0
	while x < x1 - 1.5:
		var clear_n := tower.is_empty() or x > float(tower.max[0]) + 0.6 or x < float(tower.min[0]) - 0.6
		for side in [-1.0, 1.0]:
			if side > 0 and not clear_n:
				continue
			var z: float = z1 - 0.25 if side > 0 else z0 + 0.25
			kit.put(kit.box(0.7, top, 0.5), shell, Transform3D(Basis.IDENTITY, Vector3(x, top * 0.5, z)))
			kit.put(kit.box(0.24, 0.5, 0.2), kit.window_glow, Transform3D(Basis.IDENTITY, Vector3(x, 3.2, z - side * 0.33)))
			kit.put(kit.box(0.4, 0.1, 0.36), kit.trim, Transform3D(Basis.IDENTITY, Vector3(x, 2.9, z - side * 0.3)))
		if tower.is_empty() or x > float(tower.max[0]) + 0.3:
			kit.put(kit.box(0.45, 0.5, z1 - z0), kit.trim, Transform3D(Basis.IDENTITY, Vector3(x, top - 0.55, (z0 + z1) * 0.5)))
		x += 4.0
	# Outside: a parapet round the roof, two relays, the portal.
	var ox0 := float(w.min[0])
	var ox1 := float(e.max[0])
	var oz0 := float(s.min[2])
	var oz1 := float(n.max[2])
	var roof_top := top + 0.3
	for side in [-1.0, 1.0]:
		var z: float = oz1 - 0.15 if side > 0 else oz0 + 0.15
		kit.put(kit.box(ox1 - ox0, 0.7, 0.3), shell, Transform3D(Basis.IDENTITY, Vector3((ox0 + ox1) * 0.5, roof_top + 0.35, z)))
		var xx: float = ox1 - 0.15 if side > 0 else ox0 + 0.15
		kit.put(kit.box(0.3, 0.7, oz1 - oz0), shell, Transform3D(Basis.IDENTITY, Vector3(xx, roof_top + 0.35, (oz0 + oz1) * 0.5)))
	kit.antennas(Vector3(x1 - 4.0, roof_top, z0 + 3.0), 5.0, PI * 0.5)
	kit.antennas(Vector3(x1 - 10.0, roof_top, z0 + 2.5), 3.4, PI * 0.5)
	var gz0 := float(lintel.min[2])
	var gz1 := float(lintel.max[2])
	var gy := float(lintel.min[1])
	var gx := ox1 + 0.35
	var half := (gz1 - gz0) * 0.5
	var gc := (gz0 + gz1) * 0.5
	for side in [-1.0, 1.0]:
		kit.put(kit.box(0.8, gy, 0.7), kit.trim, Transform3D(Basis.IDENTITY, Vector3(gx, gy * 0.5, gc + side * (half + 0.35))))
		kit.put(kit.box(0.06, gy * 0.8, 0.08), kit.door_glow, Transform3D(Basis.IDENTITY, Vector3(gx + 0.42, gy * 0.5, gc + side * (half + 0.1))))
	kit.put(kit.box(0.8, 0.3, (half + 0.7) * 2.0), kit.trim, Transform3D(Basis.IDENTITY, Vector3(gx, gy + 0.15, gc)))
	kit.put(kit.arch(half, half + 0.7, 0.8), kit.trim, Transform3D(Basis.IDENTITY, Vector3(gx, gy + 0.3, gc)))
	# The lunette: a glowing half-disc sign over the door.
	kit.put(kit.arch(0.0, half - 0.15, 0.2), kit.door_glow, Transform3D(Basis.IDENTITY, Vector3(gx - 0.1, gy + 0.3, gc)))
	for k in 5:
		var a := PI * (k + 1) / 6.0 - PI * 0.5
		kit.put(kit.box(0.1, half - 0.2, 0.08), kit.trim, Transform3D(Basis(Vector3.RIGHT, a), Vector3(gx + 0.02, gy + 0.3, gc) + Vector3(0, cos(a), sin(a)) * (half - 0.2) * 0.5))


## Issue #237: the club's round body: pilasters with a lamp each round the inside
## and a ring beam under the roof, a parapet round the roof outside, and the same
## arched portal with its glowing lunette over the door.
func _dress_round_cantina(town, body: Dictionary) -> void:
	var info := RingWall.info(body)
	var c: Vector3 = info.c
	var ri: float = info.ri
	var ro: float = info.r
	var top: float = info.y1
	var shell := mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
	kit._xf = Transform3D.IDENTITY
	var n := int(TAU * ri / 4.0)
	for i in n:
		var a := TAU * i / n
		if RingWall.in_gap(info, a) or RingWall.in_gap(info, a + 0.12) or RingWall.in_gap(info, a - 0.12):
			continue
		var d := Vector3(cos(a), 0, sin(a))
		var yaw := Basis(Vector3.UP, -a)
		kit.put(kit.box(0.5, top, 0.7), shell, Transform3D(yaw, c + d * (ri - 0.25) + Vector3(0, top * 0.5, 0)))
		kit.put(kit.box(0.2, 0.5, 0.24), kit.window_glow, Transform3D(yaw, c + d * (ri - 0.58) + Vector3(0, 3.2, 0)))
		kit.put(kit.box(0.36, 0.1, 0.4), kit.trim, Transform3D(yaw, c + d * (ri - 0.55) + Vector3(0, 2.9, 0)))
	kit.put(kit.ring(ri - 0.7, ri - 0.05, top - 0.8, top - 0.3, 64), kit.trim, Transform3D(Basis.IDENTITY, Vector3(c.x, 0, c.z)))
	var roof: Dictionary = town.get_box("cantina_roof")
	var roof_top := float(roof.max[1]) if not roof.is_empty() else top + 0.3
	kit.put(kit.ring(ro - 0.3, ro, roof_top, roof_top + 0.7, 64), shell, Transform3D(Basis.IDENTITY, Vector3(c.x, 0, c.z)))
	kit.antennas(c + Vector3(ro * 0.45, roof_top, -ro * 0.4), 5.0, PI * 0.5)
	kit.antennas(c + Vector3(ro * 0.1, roof_top, -ro * 0.55), 3.4, PI * 0.5)
	# The portal, in the door's own frame (+x out of the room).
	var lintel: Dictionary = town.get_box("cantina_door_lintel")
	var door: Dictionary = {}
	for g in body.get("gaps", []):
		if str(g.get("id", "")) == "door":
			door = g
	if lintel.is_empty() or door.is_empty():
		return
	var da := deg_to_rad(float(door.deg))
	var half := float(door.half)
	var gy := float(lintel.min[1])
	var gx := ro + 0.35
	kit._xf = Transform3D(Basis(Vector3.UP, -da), c)
	for side in [-1.0, 1.0]:
		kit.part(kit.box(0.8, gy, 0.7), kit.trim, Vector3(gx, gy * 0.5, side * (half + 0.35)))
		kit.part(kit.box(0.06, gy * 0.8, 0.08), kit.door_glow, Vector3(gx + 0.42, gy * 0.5, side * (half + 0.1)))
	kit.part(kit.box(0.8, 0.3, (half + 0.7) * 2.0), kit.trim, Vector3(gx, gy + 0.15, 0))
	kit.part(kit.arch(half, half + 0.7, 0.8), kit.trim, Vector3(gx, gy + 0.3, 0))
	kit.part(kit.arch(0.0, half - 0.15, 0.2), kit.door_glow, Vector3(gx - 0.1, gy + 0.3, 0))
	for k in 5:
		var a := PI * (k + 1) / 6.0 - PI * 0.5
		kit.part(kit.box(0.1, half - 0.2, 0.08), kit.trim, Vector3(gx + 0.02, gy + 0.3, 0) + Vector3(0, cos(a), sin(a)) * (half - 0.2) * 0.5, Basis(Vector3.RIGHT, a))
	kit._xf = Transform3D.IDENTITY


## Issue #237: the stair tower lit all the way up: a warm light inside every turn
## of the ramp and one in the lookout, so the climb reads at night and from the
## square (the tower's look adds glowing bands under its ledges outside).
func _light_stair_tower(town) -> void:
	var tower: Dictionary = town.get_box("stair_tower")
	if tower.is_empty():
		return
	var t := StairTower.info(tower)
	var turns := int(float(t.h) / float(t.rise))
	for k in turns:
		var p := StairTower.ramp_point(t, float(t.rc) + 0.4, float(t.th0) + TAU * (k + 0.5)) + Vector3(0, 2.0, 0)
		_stair_light(p, 1.4, 4.5)
	_stair_light(Vector3(t.c.x, t.c.y + float(t.h) + 2.0, t.c.z), 2.0, 8.0)


func _stair_light(p: Vector3, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.name = "StairLight"
	l.light_color = STAIR_LIGHT
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	l.position = p
	add_child(l)


## The round pit (art pass 2): its wall and the street round it, a curb and wall
## lights, a painted ring and light posts at every bay, and clutter (barrels,
## cans, fuel pods, a tool cart) scattered at odd angles. The crate stacks are
## boxes with collision, drawn by the kit (look "crates").
func _dress_spaceport(town) -> void:
	var bowl: Dictionary = {}
	for b in town.boxes():
		if str(b.kind) == "bowl":
			bowl = b
	if bowl.is_empty():
		return
	var mi := _box_mesh(str(bowl.id))
	if mi != null:
		mi.visible = false
	var t := PitBowl.info(bowl, town)
	var parts := PitBowl.parts(bowl, town)
	var c: Vector3 = t.c
	var r: float = t.r
	var y0: float = t.y0
	kit.put(parts.wall, mats.plaster(y0, -1.0, LookMaterials.CLOTH_SAFFRON), Transform3D.IDENTITY)
	kit.put(parts.fill, mats.paving(2.4), Transform3D.IDENTITY)
	# Curb and wall lights, broken where the ramps come out.
	var seg := 48
	for i in seg:
		var a := TAU * i / seg
		var b2 := TAU * (i + 1) / seg
		if PitBowl.in_gap(t, (a + b2) * 0.5) or PitBowl.in_gap(t, a) or PitBowl.in_gap(t, b2):
			continue
		var arc := LookMeshKit.ring_segment(r - 0.05, r + 0.45, 0.0, 0.25, a, b2, 2)
		kit.put(arc, kit.trim, Transform3D(Basis.IDENTITY, c))
		var la := (a + b2) * 0.5
		kit.put(kit.box(0.08, 0.16, 0.5), kit.window_glow, Transform3D(Basis(Vector3.UP, -la), c + Vector3(cos(la), 0, sin(la)) * (r - 0.04) + Vector3(0, -1.0, 0)))
		kit.put(kit.box(0.5, 0.06, 0.18), kit.door_glow, Transform3D(Basis(Vector3.UP, -la), c + Vector3(cos(la), 0, sin(la)) * (r - 0.02) + Vector3(0, y0 + 0.4, 0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	var keep_out: Array = []          ## Rect2s nothing loose may sit on
	for b in town.boxes():
		if str(b.get("zone", "")) != "spaceport":
			continue
		var k := str(b.kind)
		if k == "ship" or k == "pad" or k == "ramp" or k == "cover":
			keep_out.append(Rect2(float(b.min[0]) - 1.2, float(b.min[2]) - 1.2, float(b.max[0]) - float(b.min[0]) + 2.4, float(b.max[2]) - float(b.min[2]) + 2.4))
	var spawn: Vector3 = town.spawn_pos()
	keep_out.append(Rect2(spawn.x - 2.0, spawn.z - 15.0, 4.0, 17.0))   # the walk from the spawn to the ramp
	for m in town.markers_with_role("interact"):                        # issue #58: T-89's spot
		var mp: Vector3 = town.marker_pos(str(m.id))
		keep_out.append(Rect2(mp.x - 1.5, mp.z - 1.5, 3.0, 3.0))
	# Bays: a painted ring under each ship, light posts round it, a fuel pod by the wall.
	# Issue #58: the empty pad (kind "pad") gets the same ring, on top of its plate.
	var paint := mats.flat(Color("#d9a441"), 0.8)
	for b in town.boxes():
		if str(b.kind) != "ship" and str(b.kind) != "pad":
			continue
		var bc := (_v3(b.min) + _v3(b.max)) * 0.5
		var fy := float(b.max[1] if str(b.kind) == "pad" else b.min[1]) + 0.01
		if str(b.kind) == "ship":
			_pad_plate(Vector3(bc.x, float(b.min[1]), bc.z))    # the same steel plate under a parked ship
		kit.put(LookMeshKit.ring_segment(6.0, 6.35, fy, fy + 0.02, 0.0, TAU, 48), paint, Transform3D(Basis.IDENTITY, Vector3(bc.x, 0, bc.z)))
		kit.solid = true
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25 + rng.randf_range(-0.12, 0.12)
			var p := Vector3(bc.x + cos(a) * 6.9, fy, bc.z + sin(a) * 6.9)
			kit.put(kit.cyl(0.06, 0.09, 1.6, 8), kit.metal, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.8, 0)))
			kit.put(kit.ball(0.11, 0.22, false, 8), kit.door_glow, Transform3D(Basis.IDENTITY, p + Vector3(0, 1.66, 0)))
		kit.solid = false
		if str(b.get("zone", "")) != "spaceport":
			continue                  # issue #76: the barracks pad has no pit wall for a fuel pod
		kit.solid = true
		var out := Vector3(bc.x - c.x, 0, bc.z - c.z).normalized()
		var fp := c + out * (r - 2.2) + Vector3(0, y0, 0)
		var yaw := -atan2(out.z, out.x) + PI * 0.5 + rng.randf_range(-0.3, 0.3)
		kit.put(kit.cyl(0.55, 0.55, 2.6, 16), mats.flat(Color("#8a8d90"), 0.4, 0.6), Transform3D(Basis(Vector3.UP, yaw) * TownBuildings.AXIS_X, fp + Vector3(0, 0.75, 0)))
		for s in [-0.8, 0.8]:
			kit.put(kit.box(0.3, 0.3, 1.1), kit.trim, Transform3D(Basis(Vector3.UP, yaw), fp + Vector3(0, 0.15, 0) + Vector3(cos(-yaw), 0, sin(-yaw)) * s))
		kit.solid = false
	# Loose clutter, never lined up: barrels, cans, a cart, coils of hose.
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 2000:
		tries += 1
		var a := rng.randf() * TAU
		var rr := rng.randf_range(7.0, r - 1.0)
		var p := c + Vector3(cos(a) * rr, y0, sin(a) * rr)
		var bad := PitBowl.in_gap(t, a) and rr > 8.0
		for k in keep_out:
			if (k as Rect2).has_point(Vector2(p.x, p.z)):
				bad = true
		if bad:
			continue
		placed += 1
		var yaw := rng.randf() * TAU
		kit.solid = true
		match rng.randi() % 5:
			0, 1:
				var col := Color("#6a5848").lerp(LookMaterials.CLOTH_TEAL, rng.randf() * 0.5)
				kit.put(kit.cyl(0.3, 0.32, 0.9, 12), mats.flat(col, 0.7, 0.3), Transform3D(Basis.IDENTITY, p + Vector3(0, 0.45, 0)))
				if rng.randf() < 0.5:
					var off := Vector3(cos(yaw), 0, sin(yaw)) * 0.66
					kit.put(kit.cyl(0.3, 0.32, 0.9, 12), mats.flat(col.darkened(0.1), 0.7, 0.3), Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, yaw), p + off + Vector3(0, 0.3, 0)))
			2:
				for k in 3 + rng.randi() % 3:
					var q := p + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
					kit.put(kit.cyl(0.1, 0.1, 0.36, 8), mats.flat(Color("#5b6f78"), 0.4, 0.6), Transform3D(Basis.IDENTITY, q + Vector3(0, 0.18, 0)))
			3:
				kit.put(kit.box(1.3, 0.7, 0.7), kit.trim, Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.55, 0)))
				for s in [-0.45, 0.45]:
					kit.put(kit.cyl(0.18, 0.18, 0.08, 10), kit.seam, Transform3D(Basis(Vector3.UP, yaw) * TownBuildings.AXIS_Z, p + Vector3(0, 0.18, 0) + Vector3(cos(-yaw), 0, sin(-yaw)) * s))
			4:
				kit.put(LookMeshKit.ring_segment(0.25, 0.42, 0.0, 0.12, 0.0, TAU, 14), kit.seam, Transform3D(Basis(Vector3.UP, yaw), p))
		kit.solid = false


# ---------------------------------------------------------------- street decor

## Cables strung between neighbouring roofs, some hung with pennants: across the
## hut alleys often, between the towers now and then.
func _add_alley_cables(town) -> void:
	var root := Node3D.new()
	root.name = "Cables"
	add_child(root)
	var cable_mat := mats.flat(Color("#2b2522"), 0.7)
	var pennant := LookMeshKit.cloth(0.34, 0.42, 0.03, 2, 2)
	const PENNANTS := [LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_MADDER, LookMaterials.CLOTH_SAFFRON, LookMaterials.CLOTH_SAND]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for zone in ["residential_w", "residential_e"]:
		var huts: Array = []
		for b in town.boxes():
			if str(b.get("zone", "")) == zone and str(b.kind) == "solid":
				huts.append(b)
		var towers: bool = zone == "residential_e"
		var odds := 0.25 if towers else 0.45
		var reach := 12.0 if towers else 7.0
		for i in huts.size():
			for j in range(i + 1, huts.size()):
				var a: Dictionary = huts[i]
				var b: Dictionary = huts[j]
				var gap := _rect_gap(a, b)
				if gap < 1.0 or gap > reach or rng.randf() > odds:
					continue
				var y := minf(float(a.max[1]), float(b.max[1])) - (rng.randf_range(2.0, 5.0) if towers else 0.25)
				var pa := _edge_toward(a, b, y)
				var pb := _edge_toward(b, a, y + rng.randf_range(-0.3, 0.3))
				var pts := LookMeshKit.catenary(pa, pb, clampf(gap * 0.12, 0.3, 1.4), 12)
				var mi := MeshInstance3D.new()
				mi.mesh = LookMeshKit.tube(pts, 0.03, 4)
				mi.material_override = cable_mat
				root.add_child(mi)
				cables.append(mi)
				if rng.randf() < 0.6:
					var yaw := atan2(-(pb.z - pa.z), pb.x - pa.x)
					for k in range(1, pts.size() - 1):
						var c: Color = PENNANTS[(i + k) % PENNANTS.size()]
						kit.put(pennant, mats.cloth(c), Transform3D(Basis(Vector3.UP, yaw), pts[k]))


func _rect_gap(a: Dictionary, b: Dictionary) -> float:
	var dx := maxf(maxf(float(a.min[0]) - float(b.max[0]), float(b.min[0]) - float(a.max[0])), 0.0)
	var dz := maxf(maxf(float(a.min[2]) - float(b.max[2]), float(b.min[2]) - float(a.max[2])), 0.0)
	return sqrt(dx * dx + dz * dz)


## The point on box a's outline nearest box b's centre, at height y.
func _edge_toward(a: Dictionary, b: Dictionary, y: float) -> Vector3:
	var c := (_v3(b.min) + _v3(b.max)) * 0.5
	var p := Vector3(clampf(c.x, float(a.min[0]), float(a.max[0])), y, clampf(c.z, float(a.min[2]), float(a.max[2])))
	if str(a.get("shape", "")) == "round":
		var ac := (_v3(a.min) + _v3(a.max)) * 0.5
		var r := minf(float(a.max[0]) - float(a.min[0]), float(a.max[2]) - float(a.min[2])) * 0.5
		var d := Vector2(c.x - ac.x, c.z - ac.z).normalized() * (r + 0.1)
		p = Vector3(ac.x + d.x, y, ac.z + d.y)
	return p


## Lamp posts down both sides of the main street. Glowing lanterns only (no
## omni lights), so they light up at dusk with the windows.
func _add_street_lamps(town) -> void:
	var street: Dictionary = {}
	for z in town.zones():
		if str(z.id) == "main_street":
			street = z
	if street.is_empty():
		return
	var x0 := float(street.min[0]) + 4.0
	var x1 := float(street.max[0]) - 14.0
	var post := kit.cyl(0.07, 0.1, 3.6, 8)
	var arm := kit.box(0.06, 0.06, 0.9)
	var lantern := kit.box(0.24, 0.34, 0.24)
	var cap := kit.cyl(0.04, 0.2, 0.14, 8)
	var x := x0
	kit.solid = true
	while x <= x1:
		for s in [-1.0, 1.0]:
			var z: float = (float(street.max[1]) - 0.6) if s > 0 else (float(street.min[1]) + 0.6)
			var base := Vector3(x, 0, z)
			kit.put(post, kit.metal, Transform3D(Basis.IDENTITY, base + Vector3(0, 1.8, 0)))
			kit.put(kit.box(0.4, 0.3, 0.4), kit.trim, Transform3D(Basis.IDENTITY, base + Vector3(0, 0.15, 0)))
			kit.put(arm, kit.metal, Transform3D(Basis.IDENTITY, base + Vector3(0, 3.5, -s * 0.42)))
			kit.put(lantern, kit.window_glow, Transform3D(Basis.IDENTITY, base + Vector3(0, 3.22, -s * 0.8)))
			kit.put(cap, kit.metal, Transform3D(Basis.IDENTITY, base + Vector3(0, 3.46, -s * 0.8)))
		x += 11.0
	kit.solid = false


# ---------------------------------------------------------------- lamps

func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Copied from beauty_corner.gd `_lamp` (renamed). Bulb + omni light, both tracked
## so dusk turns them on.
func _lamp_at(parent: Node3D, pos: Vector3) -> void:
	var bulb := mats.glow(Color("#ffb46a"))
	look.track_glow(bulb)
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = bulb
	mi.position = pos
	parent.add_child(mi)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0.3, 0, 0)
	l.light_color = Color("#ffb46a")
	l.omni_range = 9.0
	l.set_meta("base_energy", 2.2)
	l.shadow_enabled = false
	parent.add_child(l)
	look.track_lamp(l)
	lamps.append(l)


func _add_lamps(town) -> void:
	var root := Node3D.new()
	root.name = "Lamps"
	add_child(root)
	# Cantina: three along the bar, 1 m on the door side, and one at the door.
	var bar: Dictionary = town.get_box("bar_counter")
	if not bar.is_empty():
		var z0 := float(bar.min[2])
		var z1 := float(bar.max[2])
		for i in 3:
			var z := lerpf(z0, z1, (i + 0.5) / 3.0)
			_lamp_at(root, Vector3(float(bar.max[0]) + 1.0, 3.0, z))
	if not town.get_marker("cantina_door").is_empty():
		_lamp_at(root, town.marker_pos("cantina_door") + Vector3(1.0, 2.9, 2.5))
	# Pit: one big light over the pad, set up like the beauty corner's landing bay.
	var pit: Dictionary = town.get_box("pit_floor")
	if not pit.is_empty():
		var c := (_v3(pit.min) + _v3(pit.max)) * 0.5
		var l := OmniLight3D.new()
		l.name = "PitLight"
		l.position = Vector3(c.x, float(pit.max[1]) + 4.0, c.z)
		l.light_color = Color("#ffcf8a")
		l.omni_range = 28.0
		l.set_meta("base_energy", 3.0)
		root.add_child(l)
		look.track_lamp(l)
		lamps.append(l)
	# Gate: one lamp each side.
	if not town.get_marker("gate").is_empty():
		var g: Vector3 = town.marker_pos("gate")
		for side in [-7.0, 7.0]:
			_lamp_at(root, Vector3(g.x, 3.5, g.z + side))


# ---------------------------------------------------------------- banners

## Copied from beauty_corner.gd `_banner`. Hangs a cloth strip from `top`.
func _banner(parent: Node3D, top: Vector3, facing: float, w: float, h: float, color: Color, mat: Material = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = LookMeshKit.cloth(w, h, 0.5)
	m.material_override = mat if mat != null else mats.cloth(color)
	m.position = top
	parent.add_child(m)
	m.rotation.y = -facing + PI * 0.5
	m.set_meta("decor", "banner")
	banners.append(m)
	return m


## Two torn remnant banners on the watchtower: the only cloth in this pass. Issue
## #393: the same torn cloth in the locals' green once they hold the town.
func _add_banners(town) -> void:
	var t: Dictionary = town.get_box("watchtower")
	if t.is_empty():
		return
	var root := Node3D.new()
	root.name = "Banners"
	add_child(root)
	var mn := _v3(t.min)
	var mx := _v3(t.max)
	var y := mx.y - 0.5
	var c := (mn + mx) * 0.5
	var cloth := mats.faction_cloth("band")
	# Toward the gate (+X): full length.
	_banner(root, Vector3(mx.x + 0.05, y, c.z), 0.0, 2.4, 7.0, LookMaterials.REMNANT_OXBLOOD, cloth)
	# Toward main street (-Z): torn short.
	_banner(root, Vector3(c.x, y, mn.z - 0.05), -PI * 0.5, 2.4, 4.0, LookMaterials.REMNANT_OXBLOOD, cloth)


# ---------------------------------------------------------------- parked ships

## The ship you fly, parked on its pad: the exact model the dogfight draws, built
## by the same ShipKit from the same look id (pad encounter -> player ship -> look).
## The box keeps its collision; only its greybox mesh is hidden. The box in
## port_town.json is sized to this model (tests/test_town_decor checks the fit).
func _park_ships(town) -> void:
	var scene_path := "res://scenes/town_demo.tscn"
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var ship_kit := ShipKit.new()
	for p in GameFlow.pads_for_scene(scene_path):
		var box: Dictionary = town.get_box(str(p.get("town_box", "")))
		var enc: Dictionary = content.encounters.get(str(p.get("encounter", "")), {})
		# Issue #45: the one you flew in on; issue #368: else your primary ship (Fleet).
		var ship_id := Fleet.pit_ship(str(enc.get("player", {}).get("ship", "")), content.ships)
		var look_id := str(content.ships.get(ship_id, {}).get("look", ""))
		if box.is_empty() or look_id == "":
			push_warning("TownDecor: pad %s has no ship to park" % str(p.get("id", "")))
			continue
		_park(ship_kit, look_id, "Parked_" + str(p.id), float(p.get("parked_yaw_deg", 0.0)), box, ship_id)
	# Issue #43: the other bays hold the other ships you can fly. Each "ship" box
	# with a `ship` (an id in content/core/ships) gets that ship's look; ShipPilot
	# lets you board any of them.
	for b in town.boxes():
		if str(b.kind) == "ship" and b.has("ship"):
			if str(b.ship) == GameFlow.flown_ship:
				continue                  # issue #45: it is on the pad (you flew it here)
			var look := str(content.ships.get(str(b.ship), {}).get("look", ""))
			if look == "":
				push_warning("TownDecor: bay %s names unknown ship %s" % [str(b.id), str(b.ship)])
				continue
			_park(ship_kit, look, "Parked_" + str(b.id), float(b.get("parked_yaw_deg", 0.0)), b, str(b.ship))


## Issue #58: park a ship bought from T-89 on a pad box (or any box). Returns the
## model, or null when the ship has no look.
func park_ship(ship_id: String, box: Dictionary) -> Node3D:
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var look_id := str(content.ships.get(ship_id, {}).get("look", ""))
	if look_id == "" or box.is_empty():
		return null
	return _park(ShipKit.new(), look_id, "Parked_" + str(box.id), float(box.get("parked_yaw_deg", 0.0)), box, ship_id)


## Belly on the box base, centred on its footprint; the greybox stand-in hidden.
func _park(ship_kit: ShipKit, look_id: String, node_name: String, yaw_deg: float, box: Dictionary, ship_id: String) -> Node3D:
	var ship := ship_kit.build(ShipUpgrades.look(ship_id, look_id))      # in its upgrade's paint
	ship_kit.dress(ship, ShipUpgrades.fitted(ship_id))      # and its upgrade parts
	ship.name = node_name
	ship.set_meta("ship_id", ship_id)
	ship.set_meta("box_id", str(box.id))
	ship.rotation.y = deg_to_rad(yaw_deg)
	add_child(ship)
	var c := (_v3(box.min) + _v3(box.max)) * 0.5
	ship.position = Vector3(c.x, float(box.min[1]), c.z)
	var a := visual_aabb(ship)
	ship.position.y += float(box.min[1]) - a.position.y
	ship.position.x += c.x - a.get_center().x
	ship.position.z += c.z - a.get_center().z
	var mi := _box_mesh(str(box.id)) if str(box.get("kind", "")) == "ship" else null
	if mi != null:
		mi.visible = false     # a pad's plate stays under the ship
	parked_ships.append(ship)
	return ship


## World-space bounds of every mesh under `root`.
static func visual_aabb(root: Node3D) -> AABB:
	var acc := [null]
	_merge_aabb(root, root.global_transform if root.is_inside_tree() else root.transform, acc)
	return acc[0] if acc[0] != null else AABB()


static func _merge_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	for c in n.get_children():
		if c.has_meta("no_bounds"):      # a ship's engine flames (ShipKit), only there under throttle
			continue
		var t := xf
		if c is Node3D:
			t = xf * (c as Node3D).transform
		if c is MeshInstance3D and c.mesh != null:
			var a: AABB = t * c.mesh.get_aabb()
			acc[0] = a if acc[0] == null else acc[0].merge(a)
		_merge_aabb(c, t, acc)
