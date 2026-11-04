class_name CantinaDressing
extends Node3D
## Visual dressing for the cantina (M12): a back bar with shelves and bottles, the
## framed card deck, taps on the counter, stools, and warm hanging lamps. Visual
## only: no collision, so the M9 walk routes and validation are untouched.
## Issue #55: the room was too dark (six small lamps in a 31 x 27 m hall), so the
## hanging lamps reach further and a soft warm fill hangs under the roof. Indoor
## lights: on day and night, not driven by the time of day. Every
## position is derived from the bar_counter and cantina wall boxes in the town data.
##
## Issue #47: every drink the player pays for, the Cantina Owner sets a bottle on
## the counter (CantinaOwnerNPC.serve), each a different colour from the last.
## They line up along the counter; after SERVED_MAX the oldest goes.

const SERVED_COLORS := ["#c98a3a", "#3f8f8a", "#7a2a26", "#e0b040", "#6b6f78", "#5f9a4e", "#8a4fa0", "#d8c49a"]
const SERVED_MAX := 12
const SERVED_GAP := 0.2

const RingWall := preload("res://src/systems/world/ring_wall.gd")

var mats: LookMaterials
const LAMP_ENERGY := 3.2
const FILL_ENERGY := 1.1

var fills: Array[OmniLight3D] = []   ## issue #55: the room's fill lights
var served: Array = []               ## bottles on the counter, oldest first
var served_count := 0                ## every bottle ever set down (picks the next slot)
var _colors_given := 0
var counter_min := Vector3.ZERO
var counter_max := Vector3.ZERO
var shelf_x := 0.0
var serve_z := 0.0                   ## where she stands along the counter; the row starts beside her


## Issue #392: the bar's own frame. Everything here is built with the customers
## on +x and the owner on -x, the counter running along z; a counter whose
## "front" is another way ("-z": the moon rave's long bar) is the same bar turned,
## pivoting on its middle. "+x" (or none: every other cantina) is the scene's own frame.
static func bar_frame(counter: Dictionary) -> Transform3D:
	var front := str(counter.get("front", "+x"))
	if front == "+x" or counter.is_empty():
		return Transform3D.IDENTITY
	var yaw: float = { "-x": PI, "+z": -PI * 0.5, "-z": PI * 0.5 }.get(front, 0.0)
	var c := Vector3((float(counter.min[0]) + float(counter.max[0])) * 0.5, 0.0, (float(counter.min[2]) + float(counter.max[2])) * 0.5)
	return Transform3D(Basis(Vector3.UP, yaw), c)


## The counter's corners in its bar frame (min, max).
static func local_counter(counter: Dictionary) -> Array:
	var inv := bar_frame(counter).affine_inverse()
	var a: Vector3 = inv * Vector3(float(counter.min[0]), float(counter.min[1]), float(counter.min[2]))
	var b: Vector3 = inv * Vector3(float(counter.max[0]), float(counter.max[1]), float(counter.max[2]))
	return [a.min(b), a.max(b)]


func dress(town, materials: LookMaterials) -> void:
	name = "CantinaDressing"
	mats = materials
	var counter: Dictionary = town.get_box("bar_counter")
	var wall_w: Dictionary = town.get_box("cantina_wall_w")
	if counter.is_empty():
		return
	transform = bar_frame(counter)
	var lc := local_counter(counter)
	var cmin: Vector3 = lc[0]
	var cmax: Vector3 = lc[1]
	# Issue #261: with no building (the moon's dome rave) the back bar stands on
	# its own behind her, on a panel of its own.
	var back_x := float(wall_w.max[0]) + 0.05 if not wall_w.is_empty() else cmin.x - 3.4
	# Issue #237: in a round room the back bar stands against the curve behind her.
	var body: Dictionary = town.get_box("cantina_body")
	if not body.is_empty():
		var info := RingWall.info(body)
		var dz := 6.5 + absf((cmin.z + cmax.z) * 0.5 - float(info.c.z))
		back_x = float(info.c.x) - sqrt(maxf(float(info.ri) * float(info.ri) - dz * dz, 0.0)) + 0.05
	counter_min = cmin
	counter_max = cmax
	shelf_x = back_x + 0.2
	var wood := mats.flat(Color("#5a3a24"), 0.7)
	var dark_wood := mats.flat(Color("#3a2618"), 0.75)
	var brass := mats.flat(Color("#b08e50"), 0.35, 0.8)
	var top := mats.flat(Color("#2e2620"), 0.35, 0.2)
	# Counter top slab and a brass foot rail on the customer side.
	_box(Vector3((cmin.x + cmax.x) * 0.5, cmax.y + 0.03, 0.0), Vector3(cmax.x - cmin.x + 0.2, 0.06, cmax.z - cmin.z + 0.2), top)
	_cyl(Vector3(cmax.x + 0.25, 0.2, 0.0), 0.03, cmax.z - cmin.z, brass, Vector3(90, 0, 0))
	# Back bar: three shelves of bottles against the west wall.
	var shelf_z := 6.5
	for i in 3:
		var y := 1.2 + i * 0.55
		_box(Vector3(back_x + 0.2, y, 0.0), Vector3(0.4, 0.05, shelf_z * 2.0), dark_wood)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11 + i
		var z := -shelf_z + 0.25
		while z < shelf_z - 0.2:
			var h := rng.randf_range(0.22, 0.38)
			var col: Color = [Color("#7fb07a"), Color("#c98a3a"), Color("#6a2a24"), Color("#c9b896"), Color("#4a6a8a"), Color("#e0a050")][rng.randi() % 6]
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(col.r, col.g, col.b, 0.75)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.15
			glass.emission_enabled = true
			glass.emission = col
			glass.emission_energy_multiplier = 0.25
			_cyl(Vector3(back_x + 0.2 + rng.randf_range(-0.08, 0.08), y + 0.025 + h * 0.5, z), rng.randf_range(0.035, 0.055), h, glass)
			_cyl(Vector3(back_x + 0.2, y + 0.025 + h + 0.05, z), 0.015, 0.1, glass)
			z += rng.randf_range(0.14, 0.3)
	# Back bar cabinet under the shelves.
	_box(Vector3(back_x + 0.35, 0.5, 0.0), Vector3(0.7, 1.0, shelf_z * 2.0), wood)
	if wall_w.is_empty():
		_box(Vector3(back_x - 0.08, 1.9, 0.0), Vector3(0.16, 3.8, shelf_z * 2.0 + 0.6), dark_wood)       # its own back panel (the rave's, and the round room's curve behind it)
	# The framed card deck: her famous cursed deck.
	_box(Vector3(back_x + 0.03, 2.95, 0.0), Vector3(0.04, 0.5, 0.8), brass)
	_box(Vector3(back_x + 0.06, 2.95, 0.0), Vector3(0.02, 0.42, 0.72), mats.flat(Color("#1c1816"), 0.9))
	for k in 4:
		_box(Vector3(back_x + 0.075, 2.95 + (k % 2) * 0.06 - 0.03, -0.24 + k * 0.16), Vector3(0.01, 0.16, 0.11), mats.flat(Color("#e8dcc0"), 0.8))
	# Taps on the counter.
	for z in [-1.5, -1.1, -0.7]:
		_cyl(Vector3(cmin.x + 0.4, cmax.y + 0.2, z), 0.025, 0.34, brass)
		_box(Vector3(cmin.x + 0.4, cmax.y + 0.4, z), Vector3(0.05, 0.1, 0.03), dark_wood)
	# Stools on the customer side (no collision); along a long bar, all the way along it.
	var stools: Array = [-3.6, -2.4, -1.2, 1.2, 2.4, 3.6, 4.8, -4.8]
	if cmax.z - cmin.z > 10.6:
		stools = []
		var sz := cmin.z + 0.6
		while sz < cmax.z - 0.5:
			stools.append(sz)
			sz += 1.2
	for z in stools:
		var sx := cmax.x + 0.75
		_cyl(Vector3(sx, 0.38, z), 0.03, 0.76, brass)
		_cyl(Vector3(sx, 0.78, z), 0.2, 0.07, mats.flat(Color("#6a2a24"), 0.8))
	# Warm hanging lamps over the counter and the room, on cords from the ceiling.
	var roof: Dictionary = town.get_box("cantina_roof")
	var ceiling := float(roof.min[1]) if not roof.is_empty() else 4.2     # issue #261: the rave's canopy over the bar
	# Issue #261: a club can turn the house lights down ("club": { "dim" }).
	var dim := float(town.data.get("club", {}).get("dim", 1.0))
	var lamp_glow := mats.glow(Color("#ffb060"))
	lamp_glow.emission_energy_multiplier = 3.0
	var lamps := [Vector3(cmin.x + 0.5, 3.3, -4.0), Vector3(cmin.x + 0.5, 3.3, 0.0), Vector3(cmin.x + 0.5, 3.3, 3.5)]
	for id in ["cantina_table_1", "cantina_table_2", "cantina_table_3"]:
		var t: Dictionary = town.get_box(id)
		if not t.is_empty():
			lamps.append(transform.affine_inverse() * Vector3((float(t.min[0]) + float(t.max[0])) * 0.5, 3.6, (float(t.min[2]) + float(t.max[2])) * 0.5))
	for p in lamps:
		_cyl(Vector3(p.x, (p.y + ceiling) * 0.5, p.z), 0.008, ceiling - p.y, brass)
		_cyl(p, 0.22, 0.18, mats.flat(Color("#2a2420"), 0.6, 0.5))
		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		bulb.mesh = s
		bulb.material_override = lamp_glow
		bulb.position = p + Vector3(0, -0.1, 0)
		add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Color("#ffb070")
		l.light_energy = LAMP_ENERGY * dim
		l.omni_range = 10.0
		l.omni_attenuation = 1.0
		l.shadow_enabled = false
		l.position = p + Vector3(0, -0.25, 0)
		add_child(l)
	_add_fill(town, back_x, ceiling, dim)


## Soft warm light from under the roof over the four quarters of the room, so the
## corners and tables read without lifting the bar's pools of light.
func _add_fill(town, west_x: float, ceiling: float, dim := 1.0) -> void:
	var east: Dictionary = town.get_box("cantina_wall_e_s")
	var north: Dictionary = town.get_box("cantina_wall_n")
	var south: Dictionary = town.get_box("cantina_wall_s")
	var x0 := west_x
	var x1 := 0.0
	var z0 := 0.0
	var z1 := 0.0
	var body: Dictionary = town.get_box("cantina_body")
	if not body.is_empty():
		# Issue #237: the round room's quarters are those of the square inside it.
		var info := RingWall.info(body)
		var h := float(info.ri) * 0.75
		x0 = float(info.c.x) - h
		x1 = float(info.c.x) + h
		z0 = float(info.c.z) - h
		z1 = float(info.c.z) + h
	elif east.is_empty() or north.is_empty() or south.is_empty():
		return
	else:
		x1 = float(east.min[0])
		z0 = float(south.max[2])
		z1 = float(north.min[2])
	for fx in [0.25, 0.75]:
		for fz in [0.25, 0.75]:
			var l := OmniLight3D.new()
			l.name = "CantinaFill"
			l.light_color = Color("#ffc890")
			l.light_energy = FILL_ENERGY * dim
			l.omni_range = maxf(x1 - x0, z1 - z0) * 0.6
			l.omni_attenuation = 0.8
			l.shadow_enabled = false
			l.position = Vector3(lerpf(x0, x1, fx), ceiling - 1.5, lerpf(z0, z1, fz))
			add_child(l)
			fills.append(l)


# ------------------------------------------------------------------ served bottles

## The colour for the next bottle she fetches: round the palette, so two in a row
## never match (even when two drinks are ordered back to back).
func take_color() -> Color:
	var c := Color(SERVED_COLORS[_colors_given % SERVED_COLORS.size()])
	_colors_given += 1
	return c


## A bottle (body and neck), origin at its base, in `color`.
func make_bottle(color: Color) -> Node3D:
	return bottle_mesh(color)


## The same bottle for anyone (issue #261: the club crowd holds one).
static func bottle_mesh(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "ServedBottle"
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(color.r, color.g, color.b, 0.82)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.12
	glass.emission_enabled = true
	glass.emission = color
	glass.emission_energy_multiplier = 0.35
	for part in [[0.05, 0.24, 0.12], [0.017, 0.09, 0.285]]:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = part[0]
		c.bottom_radius = part[0]
		c.height = part[1]
		c.radial_segments = 10
		m.mesh = c
		m.material_override = glass
		m.position = Vector3(0, part[2], 0)
		root.add_child(m)
	root.set_meta("color", color)
	return root


## Where bottle number `i` stands: on her side of the counter top, in a row
## starting just beside her (the taps are on her other side), within reach.
## In the scene's space (counter_min / max and serve_z are in the bar's frame).
func slot(i: int) -> Vector3:
	var z := serve_z + 0.25 + (i % SERVED_MAX) * SERVED_GAP
	var local := Vector3(counter_min.x + 0.45, counter_max.y + 0.06, minf(z, counter_max.z - 0.2))
	return global_transform * local if is_inside_tree() else transform * local


## Issue #392: she stands at `at` (the scene's space): the next bottles go beside her.
func serve_at(at: Vector3) -> void:
	serve_z = (transform.affine_inverse() * at).z


## Put `bottle` down on the next free spot; the oldest goes once the row is full.
## Returns where it stands.
func set_down(bottle: Node3D) -> Vector3:
	if served.size() >= SERVED_MAX:
		var old: Node3D = served.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var at := slot(served_count)
	if bottle.get_parent() != self:
		if bottle.get_parent() != null:
			bottle.get_parent().remove_child(bottle)
		add_child(bottle)
	bottle.global_position = at
	bottle.rotation = Vector3.ZERO
	served.append(bottle)
	served_count += 1
	return at


func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _cyl(pos: Vector3, r: float, h: float, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	m.mesh = c
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)
	return m
