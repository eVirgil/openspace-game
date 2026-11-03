class_name HangingLamp
extends RefCounted
## Issue #458: a hanging lamp for an outpost dressing: a cable, a shade, a glowing
## bulb and a real OmniLight3D, placed in the dressing's own frame. With a
## LookEnvironment the light is tracked like the town's street lamps, but with a
## floor: `day` (0..1) of its energy at the presets that keep lamps off (golden,
## noon), full at dusk and night. Without one (lookdev probes, tests with no look)
## it burns at full. Skrugs's counter and house door and Dorrin's counter hang one
## each; `light` is the bare tracked light (a work light under a roof) and
## `track_glow` puts a bulb string or a sign on the same clock.

const COLOR := Color("#ffb860")        ## the light
const BULB := Color("#ffc070")         ## the bulb's glow
const SHADE := Color("#2b2c30")
const CABLE := Color("#2b2522")


## `parent` gets the meshes and the light; `xf` is the dressing's frame (its
## landmark's origin and yaw); `at` is the bulb, in that frame; the cable rises
## `drop` above the shade to whatever it hangs from.
static func build(parent: Node3D, xf: Transform3D, at: Vector3, mats: LookMaterials, look: LookEnvironment,
		lamp_name: String, energy: float, reach: float, day: float = 0.7, drop: float = 0.3) -> OmniLight3D:
	_part(parent, xf, _cyl(0.01, 0.01, drop), mats.flat(CABLE, 0.7), at + Vector3(0, 0.17 + drop * 0.5, 0))
	_part(parent, xf, _cyl(0.06, 0.2, 0.18), mats.painted(SHADE, 0.5, 0.6), at + Vector3(0, 0.08, 0))
	var glow := mats.glow(BULB)
	var bulb := SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	bulb.radial_segments = 12
	bulb.rings = 6
	_part(parent, xf, bulb, glow, at)
	return light(parent, xf, at - Vector3(0, 0.15, 0), look, lamp_name, energy, reach, day, glow)


## A tracked light alone, at `at` in `xf`'s frame. `glow` is the material it
## lights up (its bulb), put on the same clock.
static func light(parent: Node3D, xf: Transform3D, at: Vector3, look: LookEnvironment, lamp_name: String,
		energy: float, reach: float, day: float = 0.7, glow: StandardMaterial3D = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = lamp_name
	l.light_color = COLOR
	l.omni_range = reach
	l.shadow_enabled = false
	l.set_meta("base_energy", energy)
	l.set_meta("min_level", day)
	parent.add_child(l)
	l.global_transform = xf * Transform3D(Basis.IDENTITY, at)
	if glow != null:
		glow.set_meta("min_level", day)
	if look != null:
		look.track_lamp(l, glow)
	else:
		l.light_energy = energy
		if glow != null:
			glow.emission_energy_multiplier = 0.15 + 3.0
	return l


## A glow material (a bulb string, a sign tube) on the lamps' clock: `day` of
## full by day, full at dusk and night. Without a look, always full.
static func track_glow(m: StandardMaterial3D, look: LookEnvironment, day: float = 0.7) -> void:
	m.set_meta("min_level", day)
	if look != null:
		look.track_glow(m)
	else:
		m.emission_energy_multiplier = 0.15 + 3.0


static func _part(parent: Node3D, xf: Transform3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_transform = xf * Transform3D(Basis.IDENTITY, at)
	return mi


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	return c
