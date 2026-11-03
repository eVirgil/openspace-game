extends RefCounted
## The sights the hand-gun models lack (issue #65), built from primitives and the
## numbers in hand_weapons.json. All positions are model space (the glb's own
## frame, +Z along the barrel, before the weapon scale), so they are added as
## children of the model node.
##
## Rifle: a scope (tube, ocular and objective bells, two rings on mounts, a rail,
## turrets, thin lens discs and a lit reticle) whose rear end is the `ads.sight`
## point. The tube is open and the bells are the only thing near the eye, so
## looking through it shows the world with the reticle floating in it.
## Issue #229: the rifle model had its own optic, so it showed two. `cut` removes
## that block from the model's mesh, and the scope sits low on a rail in its place,
## in scope_metal.gdshader (anodised, knurled, grooved, worn).
## Pistol: a front post and a pair of rear blades with a notch between them.

const RETICLE_ENERGY := 3.0
const SCOPE_METAL := preload("res://src/systems/look/shaders/scope_metal.gdshader")
const SCOPE_GLASS := preload("res://src/systems/look/shaders/scope_glass.gdshader")
const SCOPE_RETICLE := preload("res://src/systems/look/shaders/scope_reticle.gdshader")
const DARK := preload("res://src/systems/look/shaders/weapon_dark.gdshader")

static var _cut_cache: Dictionary = {}
static var _noise: NoiseTexture2D


static func add_to(model: Node3D, spec: Dictionary) -> void:
	if spec.get("cut") is Dictionary:
		for box in spec.cut.get("boxes", []):
			cut(model, box)
	if spec.get("scope") is Dictionary:
		model.add_child(build_scope(spec.scope))
	if spec.get("sights") is Dictionary:
		model.add_child(build_iron_sights(spec.sights))


static func _v3(a, d := Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


static func _metal(c: Color, rough := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.5
	m.roughness = rough
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A tube along +Z (CylinderMesh is along Y: turn it). r_rear / r_front radii.
static func _tube(parent: Node3D, r_rear: float, r_front: float, length: float, z: float, mat: Material, caps := false) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = r_rear
	c.top_radius = r_front
	c.height = length
	c.radial_segments = 48         # the eyepiece fills the view aimed in: no facets
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return _mesh(parent, c, mat, Vector3(0, 0, z), Vector3(90, 0, 0))


## Drop every triangle of the model's own meshes whose centre lies in the box
## `c.min`..`c.max` (model space; hand_weapons "cut" lists the boxes). The source mesh is untouched (guards and other
## users share it); each cut mesh is built once and cached.
static func cut(model: Node3D, c: Dictionary) -> void:
	var lo := _v3(c.get("min"))
	var box := AABB(lo, _v3(c.get("max")) - lo)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		if m == null:
			continue
		var xf := (mi as Node3D).transform
		var p := mi.get_parent()
		while p != null and p != model:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var key := "%d|%s|%s" % [m.get_instance_id(), box, xf]
		if not _cut_cache.has(key):
			_cut_cache[key] = cut_mesh(m, xf, box)
		(mi as MeshInstance3D).mesh = _cut_cache[key]


## `m` without the triangles whose centre (through `xf`) is inside `box`.
static func cut_mesh(m: ArrayMesh, xf: Transform3D, box: AABB) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arrays := m.surface_get_arrays(si)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var centre := xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
			if not box.has_point(centre):
				keep.append(idx[t])
				keep.append(idx[t + 1])
				keep.append(idx[t + 2])
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(m.surface_get_primitive_type(si), arrays)
		out.surface_set_material(si, m.surface_get_material(si))
	return out


## Aimed in through a scope, show only the tube, lenses and reticle (which shows
## only then): the tube's
## walls are see-through from inside, so the hardware round it (turrets, mounts,
## rail) and the gun below it (receiver, muzzle glow) would show through. Off
## puts them back. A gun without a scope is untouched.
## `barrel_from` (metres from the eye, hand_weapons scope "barrel_from"): the gun
## past it stays, so the barrel runs out under the scope and it does not float.
## That needs the gun's weapon_dark material (its near_clip); others just hide.
static func scope_view(weapon: Node3D, on: bool, barrel_from := 0.0) -> void:
	var scope := weapon.find_child("Scope", true, false) as Node3D
	if scope == null:
		return
	(scope.get_node("Hardware") as Node3D).visible = not on
	# The reticle draws over everything (no depth test), so from the hip it showed
	# through the tube's side: it is only there aimed in.
	(scope.get_node("Reticle") as Node3D).visible = on
	for mi in weapon.find_children("*", "GeometryInstance3D", true, false):
		if scope.is_ancestor_of(mi) or mi.name == "Flash":
			continue
		var g := mi as GeometryInstance3D
		var sm := g.material_override as ShaderMaterial
		if barrel_from > 0.0 and sm != null and sm.shader == DARK:
			g.visible = true
			sm.set_shader_parameter("near_clip", barrel_from if on else 0.0)
		else:
			g.visible = not on


## Aimed in, pin what shows of the scope (tube, bells, rim, lenses, reticle) and
## the barrel running out under it (the gun's weapon_dark meshes, scope_view keeps
## them) to the eye: `cam_from_weapon` is the weapon's transform in the camera's
## space, and each part is drawn at it times its own small transform under the
## weapon, never through world positions (viewmodel_pin.gdshaderinc says why).
## A pinned barrel casts no shadow (its vertices are in the camera's space, not
## the light's). Off (or no scope): drawn the usual way again, shadow back.
static func pin(weapon: Node3D, cam_from_weapon: Transform3D, on: bool) -> void:
	var scope := weapon.find_child("Scope", true, false) as Node3D
	if scope == null:
		return
	for mi in weapon.find_children("*", "GeometryInstance3D", true, false):
		var g := mi as GeometryInstance3D
		var sm := g.material_override as ShaderMaterial
		var barrel := sm != null and sm.shader == DARK
		if not scope.is_ancestor_of(g) and not barrel:
			continue
		if not on:
			g.set_instance_shader_parameter("pin_on", 0.0)
			if g.has_meta("pin_shadow"):
				g.cast_shadow = g.get_meta("pin_shadow")
				g.remove_meta("pin_shadow")
			continue
		var xf := g.transform
		var p := g.get_parent()
		while p != null and p != weapon:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		xf = cam_from_weapon * xf
		var b := xf.basis
		g.set_instance_shader_parameter("pin_x", Vector4(b.x.x, b.y.x, b.z.x, xf.origin.x))
		g.set_instance_shader_parameter("pin_y", Vector4(b.x.y, b.y.y, b.z.y, xf.origin.y))
		g.set_instance_shader_parameter("pin_z", Vector4(b.x.z, b.y.z, b.z.z, xf.origin.z))
		g.set_instance_shader_parameter("pin_on", 1.0)
		if barrel and not g.has_meta("pin_shadow"):
			g.set_meta("pin_shadow", g.cast_shadow)
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _scope_mat(c: Color, rough: float, knurl := 0.0, groove := 0.0, weave := 0.0) -> ShaderMaterial:
	if _noise == null:
		_noise = NoiseTexture2D.new()
		_noise.seamless = true
		_noise.noise = FastNoiseLite.new()
		_noise.noise.frequency = 0.03
	var m := ShaderMaterial.new()
	m.shader = SCOPE_METAL
	m.set_shader_parameter("base", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("knurl", knurl)
	m.set_shader_parameter("groove", groove)
	m.set_shader_parameter("weave", weave)
	m.set_shader_parameter("noise_tex", _noise)
	return m


## A short cylinder along local `axis` ("x", "y" or "z") at `pos`.
static func _knob(parent: Node3D, r: float, h: float, pos: Vector3, axis: String, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 20
	c.rings = 1
	var rot := Vector3.ZERO
	if axis == "x":
		rot = Vector3(0, 0, 90)
	elif axis == "z":
		rot = Vector3(90, 0, 0)
	return _mesh(parent, c, mat, pos, rot)


static func build_scope(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Scope"
	root.position = _v3(s.get("pos"), Vector3(0, 0.24, 0))
	var length := float(s.get("length", 0.24))
	var r := float(s.get("radius", 0.024))
	var r_oc := float(s.get("ocular", 0.029))
	var r_ob := float(s.get("objective", 0.034))
	# Issue #229: the rifle's own blue-grey and twill, so the two read as one kit.
	var body := _scope_mat(Color(0.05, 0.054, 0.062), 0.42, 0.0, 0.0, float(s.get("weave", 0.0)))
	var ring := _scope_mat(Color(0.07, 0.07, 0.075), 0.35)
	var knurled := _scope_mat(Color(0.06, 0.06, 0.065), 0.4, 48.0)
	var grooved := _scope_mat(Color(0.05, 0.05, 0.055), 0.4, 0.0, 9.0)
	var bell := 0.045
	# Main tube between the two bells, then the bells flaring to the ends.
	_tube(root, r, r, length - bell * 2.0 + 0.004, 0.0, body)
	_tube(root, r_oc, r, bell, -length * 0.5 + bell * 0.5, body)
	_tube(root, r, r_ob, bell, length * 0.5 - bell * 0.5, body)
	# Everything outside the tube goes under Hardware: aimed in, the tube's walls
	# are see-through from inside, so it is hidden then (hide_hardware).
	var hw := Node3D.new()
	hw.name = "Hardware"
	root.add_child(hw)
	# The eyepiece's grooved power ring and a knurled focus ring at its very end.
	_tube(hw, r_oc + 0.0012, r_oc + 0.0012, 0.016, -length * 0.5 + 0.026, grooved)
	_tube(hw, r_oc + 0.0008, r_oc + 0.0008, 0.008, -length * 0.5 + 0.006, knurled)
	# Rim at the eyepiece, a ring you can see the world through.
	var rim := TorusMesh.new()
	rim.inner_radius = r_oc - 0.0015
	rim.outer_radius = r_oc + 0.0012
	rim.rings = 64
	rim.ring_segments = 8
	_mesh(root, rim, ring, Vector3(0, 0, -length * 0.5), Vector3(90, 0, 0))
	# Painted bands in the rifle's panel color, lit like its panels: one behind the
	# objective bell, one ahead of the eyepiece's power ring.
	if s.has("accent"):
		var paint := _scope_mat(Color.html(str(s.accent)), 0.5)
		paint.set_shader_parameter("metallic", 0.0)
		paint.set_shader_parameter("glow", float(s.get("accent_glow", 0.6)))
		_tube(hw, r + 0.0008, r + 0.0008, 0.006, length * 0.5 - bell - 0.006, paint)
		_tube(hw, r + 0.0008, r + 0.0008, 0.004, -length * 0.5 + bell + 0.008, paint)
	# Turrets: elevation on top, windage on the shooter's right (-X), the parallax
	# knob on the left; each a body and a knurled cap.
	_knob(hw, r * 0.42, 0.02, Vector3(0, r + 0.008, 0.004), "y", body)
	_knob(hw, r * 0.5, 0.009, Vector3(0, r + 0.019, 0.004), "y", knurled)
	_knob(hw, r * 0.42, 0.02, Vector3(-r - 0.008, 0, 0.004), "x", body)
	_knob(hw, r * 0.5, 0.009, Vector3(-r - 0.019, 0, 0.004), "x", knurled)
	_knob(hw, r * 0.55, 0.014, Vector3(r + 0.006, 0, 0.004), "x", body)
	_knob(hw, r * 0.62, 0.007, Vector3(r + 0.015, 0, 0.004), "x", knurled)
	# Rings clamp the tube; mounts carry them down to a rail on the receiver
	# (`rail_y`, model space: the top of the receiver once the old optic is cut).
	var rail_y := float(s.get("rail_y", -999.0))
	var drop := (root.position.y - rail_y) if rail_y > -999.0 else r + 0.01
	for z in s.get("rings", [-0.065, 0.075]):
		_tube(hw, r * 1.2, r * 1.2, 0.014, float(z), ring)
		var mh := drop - r * 1.05
		var mount := BoxMesh.new()
		mount.size = Vector3(r * 1.3, mh, 0.014)
		_mesh(hw, mount, ring, Vector3(0, -r * 1.05 - mh * 0.5, float(z)))
		_knob(hw, 0.0035, r * 1.5, Vector3(0, -r * 1.12, float(z)), "x", knurled)   # clamp bolt
	# The rail: a base the length of the cut, crossed by the slots of a Picatinny.
	var rail_len := length * 0.85
	var base := BoxMesh.new()
	base.size = Vector3(0.026, 0.006, rail_len)
	_mesh(hw, base, ring, Vector3(0, -drop + 0.003, 0.0))
	var n_slots := int(rail_len / 0.01)
	for i in n_slots:
		var tooth := BoxMesh.new()
		tooth.size = Vector3(0.022, 0.003, 0.0052)
		_mesh(hw, tooth, body, Vector3(0, -drop + 0.0072, -rail_len * 0.5 + 0.005 + i * 0.01))
	# Glass: faint, so the front one reads from outside and neither tints the view.
	var glass := ShaderMaterial.new()
	glass.shader = SCOPE_GLASS
	glass.set_shader_parameter("tint", Color(0.4, 0.7, 0.75, 0.1))
	glass.render_priority = -1
	# The objective's coating: a violet-amber sheen at a glance, clear head on.
	var coated := glass.duplicate() as ShaderMaterial
	coated.set_shader_parameter("tint", Color(0.42, 0.3, 0.62, 0.12))
	coated.set_shader_parameter("rim", 1.0)
	coated.set_shader_parameter("metallic", 0.6)
	for g in [[r_ob - 0.003, length * 0.5 - 0.004, coated], [r_oc - 0.004, -length * 0.5 + 0.02, glass]]:
		var d := CylinderMesh.new()
		d.top_radius = g[0]
		d.bottom_radius = g[0]
		d.height = 0.0015
		d.radial_segments = 20
		var lens := _mesh(root, d, g[2], Vector3(0, 0, g[1]), Vector3(90, 0, 0))
		lens.name = "Lens"
	root.add_child(_reticle(Color.html(str(s.get("reticle", "#ff2a1a"))), r - 0.003))
	return root


## Thin crosshair with an open centre and a dot, lit and unshaded so it reads on
## any background. Sits in the middle of the tube, facing the eye (+Z normal).
static func _reticle(col: Color, reach: float) -> Node3D:
	var n := Node3D.new()
	n.name = "Reticle"
	var m := ShaderMaterial.new()
	m.shader = SCOPE_RETICLE          # unshaded, no depth test: floats over the view
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", RETICLE_ENERGY)
	m.render_priority = 10
	var t := 0.0006
	var gap := 0.003
	var seg := reach - gap
	for sgn in [-1.0, 1.0]:
		var h := BoxMesh.new()
		h.size = Vector3(seg, t, t)
		_mesh(n, h, m, Vector3(sgn * (gap + seg * 0.5), 0, 0))
		var v := BoxMesh.new()
		v.size = Vector3(t, seg, t)
		_mesh(n, v, m, Vector3(0, sgn * (gap + seg * 0.5), 0))
	var dot := BoxMesh.new()
	dot.size = Vector3(t * 1.6, t * 1.6, t)
	_mesh(n, dot, m, Vector3.ZERO)
	return n


static func build_iron_sights(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "IronSights"
	var mat := _metal(Color(0.04, 0.04, 0.045), 0.5)
	if s.get("front") is Dictionary:
		var f: Dictionary = s.front
		var b := BoxMesh.new()
		b.size = _v3(f.get("size"), Vector3(0.0035, 0.016, 0.005))
		_mesh(root, b, mat, _v3(f.get("pos")))
	if s.get("rear") is Dictionary:
		var r: Dictionary = s.rear
		var sz := _v3(r.get("size"), Vector3(0.004, 0.015, 0.006))
		var at := _v3(r.get("pos"))
		var off := float(r.get("gap", 0.007)) * 0.5 + sz.x * 0.5
		for sgn in [-1.0, 1.0]:
			var b := BoxMesh.new()
			b.size = sz
			_mesh(root, b, mat, at + Vector3(sgn * off, 0, 0))
	return root
