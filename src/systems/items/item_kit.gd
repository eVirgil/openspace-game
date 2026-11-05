class_name ItemKit
extends RefCounted
## Item looks (M13). Builds the visible item for a "look" id: the same model is
## worn on the body and lies in the world as a pickup. Gameplay never touches this:
## the inventory and the jetpack read content/core/items/*.json; this kit reads
## content/look/items.json and only decides what the item looks like.
##
## Two ways to get a design on screen, both data-only (the ShipKit pattern):
##   1. A real model: set the look's "scene" to a .tscn or .glb path (the wearer's
##      back is -Z, 1 unit = 1 metre). The kit mounts it as-is.
##   2. A stand-in: leave "scene" empty and pick a "frame" ("twin_tank"). Sizes and
##      colours come from the look entry, shapes from here.
##
## Every built item has the same contract: a root Node3D named after the look, meta
## "look_id" and "source" ("scene" or "kit"), and a "Flames" child holding the
## thrust flames (hidden until set_flames()). A model can bring its own "Flames".

const LOOKS_PATH := "res://content/look/items.json"
const FALLBACK_FRAME := "twin_tank"

var mats: LookMaterials
var looks: Dictionary = {}
var pickup_style: Dictionary = {}


func _init(materials: LookMaterials = null, looks_override: Dictionary = {}) -> void:
	mats = materials if materials != null else LookMaterials.new()
	var data := looks_override if not looks_override.is_empty() else _read_json(LOOKS_PATH)
	looks = data.get("looks", {})
	pickup_style = data.get("pickup", {})


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func has_look(look_id: String) -> bool:
	return looks.has(look_id)


func look(look_id: String) -> Dictionary:
	return looks.get(look_id, {})


## Where a worn item sits on the chest joint.
func on_back_transform(look_id: String) -> Transform3D:
	var b: Dictionary = look(look_id).get("on_back", {})
	var p: Array = b.get("pos", [0, 0, -0.2])
	var r: Array = b.get("rot", [0, 0, 0])
	var basis := Basis.from_euler(Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2]))))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## Build the item for a look id. Unknown ids get the fallback stand-in so a missing
## look is visible in game instead of invisible.
func build(look_id: String) -> Node3D:
	var p := look(look_id)
	if p.is_empty():
		push_warning("ItemKit: unknown look id: ", look_id)
	var root := Node3D.new()
	root.name = look_id.to_pascal_case() if look_id != "" else "Item"
	root.set_meta("look_id", look_id)
	var model := _load_model(str(p.get("scene", "")))
	if model != null:
		model.name = "Model"
		root.add_child(model)
		# Issue #25: a "case" model is a 1 m cube stretched to the look's size, tinted
		# toward its shell colour, with the stand-in's glowing status strip low on the latch side (-Z).
		if str(p.get("frame", "")) == "case":
			var size := Vector3(float(p.get("width", 0.5)), float(p.get("height", 0.3)), float(p.get("depth", 0.34)))
			model.scale = size
			_mi(root, _box(Vector3(size.x * 0.5, 0.02, 0.01)), _glow(_c(p, "glow", "#59d6ff"), 2.5),
				Vector3(0, size.y * 0.22, -size.z * 0.5 - 0.004), Vector3.ZERO, "Status")
		# "model_scale" [x, y, z] squeezes a model along its own axes (a flatter jetpack).
		elif p.has("model_scale"):
			var s: Array = p.model_scale
			model.scale = Vector3(float(s[0]), float(s[1]), float(s[2]))
		if p.has("tint"):
			_tint(model, _c(p, "shell", "#ffffff"), float(p.tint))
		if model.get_node_or_null("Flames") == null:
			var f := Node3D.new()
			f.name = "Flames"
			root.add_child(f)
			# Issue #25: a model without its own flames gets the kit's at each nozzle.
			for at in p.get("flames_at", []):
				_flame(f, Vector3(float(at[0]), float(at[1]), float(at[2])), float(p.get("tank_radius", 0.085)),
					float(p.get("height", 0.52)), p)
		root.set_meta("source", "scene")
		set_flames(root, false)
		return root
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var flames := Node3D.new()
	flames.name = "Flames"
	root.add_child(flames)
	match str(p.get("frame", FALLBACK_FRAME)):
		"case":
			_case(body, p)
		"saber":
			_saber(body, p)
		"grenade":
			_grenade(body, p)
		_:
			_twin_tank(body, flames, p)
	root.set_meta("source", "kit")
	set_flames(root, false)
	return root


## Issue #355: bounds of every visible mesh of a built item, with the item itself
## at `xf` (it need not be in the tree), e.g. to set it down on a counter.
static func bounds(item: Node, xf: Transform3D = Transform3D.IDENTITY) -> AABB:
	var acc := [null]
	_merge_bounds(item, xf, acc)
	return acc[0] if acc[0] != null else AABB(Vector3(-0.2, 0, -0.2), Vector3(0.4, 0.3, 0.4))


static func _merge_bounds(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var a: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children():
		if c is Node3D and (c as Node3D).visible:      # not the hidden flames
			_merge_bounds(c, xf * (c as Node3D).transform, acc)


## Show or hide the thrust flames; `power` 0..1 scales their length.
static func set_flames(item: Node3D, on: bool, power: float = 1.0) -> void:
	var f := item.get_node_or_null("Flames")
	if f == null:
		f = item.find_child("Flames", true, false)
	if f == null:
		return
	f.visible = on
	if on:
		(f as Node3D).scale = Vector3(1.0, clampf(power, 0.2, 1.4), 1.0)
		# A flicker: each flame's length wavers a little, out of step with the other.
		var t := Time.get_ticks_msec() * 0.001
		var i := 0
		for fl in f.get_children():
			if fl is Node3D:
				var k := 1.0 + 0.09 * sin(t * 37.0 + i * 2.1) + 0.05 * sin(t * 91.0 + i * 0.7)
				(fl as Node3D).scale = Vector3(1.0, k, 1.0)
			i += 1


func _load_model(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		if path != "":
			push_warning("ItemKit: model not found, using stand-in: ", path)
		return null
	var res = ModelCache.scene(path)
	if res is PackedScene:
		var inst = res.instantiate()
		if inst is Node3D:
			return inst
		if inst != null:
			inst.free()
	push_warning("ItemKit: not a 3D scene, using stand-in: ", path)
	return null


# ------------------------------------------------------------------ helpers

func _c(p: Dictionary, key: String, fallback: String) -> Color:
	return Color(str(p.get(key, fallback)))


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		nname: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if nname != "":
		mi.name = nname
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, seg: int = 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ frames

## "case": a squat carry case with corner guards and a glowing status strip
## (cargo: power cells, crates). Sits on its base at y = 0.
func _case(body: Node3D, p: Dictionary) -> void:
	var size := Vector3(float(p.get("width", 0.5)), float(p.get("height", 0.3)), float(p.get("depth", 0.34)))
	var shell := StandardMaterial3D.new()
	shell.albedo_color = _c(p, "shell", "#3c4a52")
	shell.roughness = 0.6
	shell.metallic = 0.3
	var trim := StandardMaterial3D.new()
	trim.albedo_color = _c(p, "trim", "#8c8478")
	trim.metallic = 0.6
	_mi(body, _box(size), shell, Vector3(0, size.y * 0.5, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mi(body, _box(Vector3(0.05, size.y + 0.02, 0.05)), trim,
				Vector3(sx * (size.x * 0.5 - 0.02), size.y * 0.5, sz * (size.z * 0.5 - 0.02)))
	_mi(body, _box(Vector3(size.x * 0.6, 0.025, 0.01)), _glow(_c(p, "glow", "#59d6ff"), 2.5),
		Vector3(0, size.y * 0.62, size.z * 0.5 + 0.006), Vector3.ZERO, "Status")
	_mi(body, _box(Vector3(size.x * 0.4, 0.03, 0.06)), trim, Vector3(0, size.y + 0.015, 0), Vector3.ZERO, "Handle")


## "grenade" (issue #372): a palm-sized canister standing on its end, a glowing
## band round its waist and a trigger cap on top. `radius` and `height` in metres.
func _grenade(body: Node3D, p: Dictionary) -> void:
	var r := float(p.get("radius", 0.045))
	var h := float(p.get("height", 0.12))
	var shell := StandardMaterial3D.new()
	shell.albedo_color = _c(p, "shell", "#5a5f58")
	shell.roughness = 0.45
	shell.metallic = 0.55
	var trim := StandardMaterial3D.new()
	trim.albedo_color = _c(p, "trim", "#2a2c2a")
	trim.metallic = 0.7
	trim.roughness = 0.35
	_mi(body, _cyl(r, r, h), shell, Vector3(0, h * 0.5, 0), Vector3.ZERO, "Shell")
	_mi(body, _cyl(r * 1.06, r * 1.06, h * 0.16), _glow(_c(p, "glow", "#ff8a2a"), 3.0), Vector3(0, h * 0.5, 0), Vector3.ZERO, "Band")
	_mi(body, _cyl(r * 0.55, r * 0.7, h * 0.18), trim, Vector3(0, h + h * 0.09, 0), Vector3.ZERO, "Cap")
	_mi(body, _cyl(r * 1.02, r * 1.02, h * 0.08), trim, Vector3(0, h * 0.04, 0), Vector3.ZERO, "Foot")


## "saber" (issue #148): a hilt with its blade lit, lying flat (along +X) so it
## reads as a sword from across a room. "hilt_model" is the hilt .glb (0.28 m
## along +Y, emitter up); without it the hilt is built from parts.
func _saber(body: Node3D, p: Dictionary) -> void:
	var length := float(p.get("length", 0.9))
	var flat := Vector3(0, 0, -PI * 0.5)   # radians, as _mi takes them: +Y turned to +X
	var blade := _c(p, "blade", "#ff2a2a")
	var model := _load_model(str(p.get("hilt_model", "")))
	if model != null:
		model.name = "Hilt"
		model.position = Vector3(-0.13, 0.05, 0)
		model.rotation = flat
		body.add_child(model)
	else:
		var hilt := StandardMaterial3D.new()
		hilt.albedo_color = _c(p, "hilt", "#2a2826")
		hilt.metallic = 0.6
		var trim := StandardMaterial3D.new()
		trim.albedo_color = _c(p, "trim", "#b08e50")
		trim.metallic = 0.7
		_mi(body, _cyl(0.02, 0.022, 0.26), hilt, Vector3(-0.13, 0.05, 0), flat, "Hilt")
		_mi(body, _sphere(0.03), trim, Vector3(-0.27, 0.05, 0), Vector3.ZERO, "Pommel")
		for i in 3:
			_mi(body, _cyl(0.024, 0.024, 0.015), trim, Vector3(-0.2 + i * 0.05, 0.05, 0), flat, "Grip%d" % i)
		_mi(body, _cyl(0.026, 0.02, 0.04), trim, Vector3(0.02, 0.05, 0), flat, "Emitter")
	_mi(body, _cyl(0.011, 0.013, length), _glow(blade.lerp(Color.WHITE, 0.6), 5.0),
		Vector3(length * 0.5 + 0.015, 0.05, 0), flat, "Blade")
	_mi(body, _cyl(0.016, 0.018, length * 1.03), _glow(blade, 2.0),
		Vector3(length * 0.5 + 0.015, 0.05, 0), flat, "BladeGlow")


## "twin_tank": two upright fuel tanks on a back plate with straps, a trim band,
## and a downward nozzle under each tank. Flames hang below the nozzles. The back
## plate is at z = 0 (against the wearer), the tanks sit behind it (-Z).
func _twin_tank(body: Node3D, flames: Node3D, p: Dictionary) -> void:
	var h := float(p.get("height", 0.52))
	var r := float(p.get("tank_radius", 0.085))
	var spread := float(p.get("spread", 0.2))
	var metal := mats.flat(_c(p, "metal", "#8c8478"), 0.45, 0.55)
	var trim := mats.flat(_c(p, "trim", "#d99a2b"), 0.6, 0.2)
	var dark := mats.flat(_c(p, "dark", "#2a2622"), 0.8, 0.2)
	var strap := mats.flat(_c(p, "strap", "#5a3a24"), 0.9, 0.0)
	var nozzle := mats.flat(_c(p, "nozzle", "#3a3632"), 0.5, 0.6)

	_mi(body, _box(Vector3(spread * 1.6, h * 0.9, 0.04)), dark, Vector3(0, 0, -0.02), Vector3.ZERO, "Plate")
	for side in [-1.0, 1.0]:
		var x: float = side * spread * 0.5
		var z := -0.04 - r
		_mi(body, _cyl(r, r, h * 0.8), metal, Vector3(x, 0, z), Vector3.ZERO, "Tank" + ("L" if side > 0 else "R"))
		_mi(body, _sphere(r), metal, Vector3(x, h * 0.4, z))
		_mi(body, _cyl(r * 1.04, r * 1.04, h * 0.08), trim, Vector3(x, h * 0.18, z))
		_mi(body, _cyl(r * 0.55, r * 0.8, h * 0.14), nozzle, Vector3(x, -h * 0.47, z), Vector3.ZERO, "Nozzle")
		_flame(flames, Vector3(x, -h * 0.54, z), r, h, p)
		# Harness straps rising off the top of the plate toward the shoulders.
		_mi(body, _box(Vector3(0.045, 0.02, 0.16)), strap, Vector3(side * spread * 0.45, h * 0.45, 0.06),
			Vector3(-0.35, 0, 0))
	_mi(body, _box(Vector3(spread * 1.2, 0.05, 0.08)), trim, Vector3(0, h * 0.3, -0.06), Vector3.ZERO, "Bar")
	_mi(body, _box(Vector3(spread * 1.7, 0.06, 0.05)), strap, Vector3(0, -h * 0.38, -0.01), Vector3.ZERO, "Belt")


## Flames from a nozzle at `at`, raked back away from the wearer (-Z) by
## "flame_rake". Length is "flame_metres" if set, else `h` * "flame_length"; the
## radius at the nozzle is "nozzle_radius" if set, else `r`. Layered and additive:
## a white-hot mouth and core, a yellow-orange body, a faint red plume, shock
## diamonds down the middle, and a small light on the legs. Every mesh is a direct
## child of the flame node (the worn-view check in GearController relies on it).
func _flame(flames: Node3D, at: Vector3, r: float, h: float, p: Dictionary) -> void:
	var fl := Node3D.new()
	fl.name = "Flame"
	fl.position = at
	fl.rotation.x = float(p.get("flame_rake", 0.35))
	flames.add_child(fl)
	var fh := float(p.get("flame_metres", h * float(p.get("flame_length", 1.3))))
	var nr := float(p.get("nozzle_radius", r))
	var hot := _c(p, "flame_core", "#ffd9a0")
	var body := _c(p, "flame", "#ff8a2a")
	var tail := _c(p, "flame_tail", "#ff3a14")
	var parts: Array = [
		_mi(fl, _cyl(nr * 0.95, nr * 0.95, 0.006, 16), _plume(hot.lerp(Color.WHITE, 0.5), 6.0, 1.0),
			Vector3(0, -0.003, 0), Vector3.ZERO, "Mouth"),
		_mi(fl, _cyl(nr * 0.55, 0.0, fh * 0.4, 12), _plume(hot.lerp(Color.WHITE, 0.3), 5.0, 0.9),
			Vector3(0, -fh * 0.2, 0), Vector3.ZERO, "Core"),
		_mi(fl, _cyl(nr * 0.85, nr * 0.1, fh * 0.75, 14), _plume(hot.lerp(body, 0.5), 3.0, 0.6),
			Vector3(0, -fh * 0.375, 0), Vector3.ZERO, "Body"),
		_mi(fl, _cyl(nr * 1.05, 0.0, fh, 14), _plume(body, 2.2, 0.45),
			Vector3(0, -fh * 0.5, 0), Vector3.ZERO, "Outer"),
		_mi(fl, _cyl(nr * 1.4, nr * 0.3, fh * 0.85, 14), _plume(tail, 1.4, 0.16),
			Vector3(0, -fh * 0.5, 0), Vector3.ZERO, "Plume"),
	]
	for i in 3:
		var d := _mi(fl, _sphere(nr * (0.32 - i * 0.07)), _plume(hot.lerp(Color.WHITE, 0.6), 6.0, 0.8),
			Vector3(0, -fh * (0.22 + i * 0.18), 0), Vector3.ZERO, "Diamond%d" % i)
		d.scale = Vector3(1.0, 1.8, 1.0)
		parts.append(d)
	for m in parts:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = body
	light.light_energy = 1.2
	light.omni_range = maxf(fh * 4.0, 0.6)
	light.position = Vector3(0, -fh * 0.4, 0)
	fl.add_child(light)


## An unshaded, additive flame layer: `alpha` sets how much it adds.
func _plume(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := _glow(color, energy)
	m.albedo_color.a = alpha
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Multiply a model's colour toward `color` (k 0 = as made, 1 = fully), per instance.
static func _tint(model: Node, color: Color, k: float) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = Color.WHITE.lerp(color, k)
			mi.set_surface_override_material(s, m)
