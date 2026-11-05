class_name ShipKit
extends RefCounted
## Starfighter looks (M10). Builds the visible ship for a "look" id. Gameplay never
## touches this: the flight model, guns and AI read content/core/ships/*.json; this
## kit reads content/look/ships.json and only decides what the ship looks like.
##
## Two ways to get a design on screen, both data-only:
##   1. A real model: set the look's "scene" to a .tscn or .glb path. The kit
##      instantiates it as-is (forward = -Z, 1 unit = 1 metre). Its "parts" (the
##      same as an upgrade's, see dress) are bolted on every time.
##   2. A stand-in: leave "scene" empty and pick a "frame" ("dart", "blade",
##      "hauler"). Sizes and colours come from the look entry, shapes from here.
##
## Every built ship has the same contract, so the scene code never cares which path
## made it: a root Node3D named after the look, with meta "look_id", an "Engines"
## child holding the engine glows (empty for a model that brings its own), and a
## "Flames" child holding the engine flames, unlit until throttle_flames() opens the
## throttle. A stand-in gets a flame at each glow; a model at each "flames_at"
## nozzle ([x, y, z, radius] in the look, pointing aft along +Z).
##
## Design rules (docs/ART_DIRECTION.md, Ships): silhouette first; the smuggler side
## is warm, worn and asymmetric-friendly; the remnant side is dark plate with oxblood
## trim and amber glass, the same language as the remnant trooper.

const LOOKS_PATH := "res://content/look/ships.json"
const FALLBACK_FRAME := "dart"

var mats: LookMaterials
var looks: Dictionary = {}
var bolts: Dictionary = {}


func _init(materials: LookMaterials = null, looks_override: Dictionary = {}) -> void:
	mats = materials if materials != null else LookMaterials.new()
	var data := looks_override if not looks_override.is_empty() else _read_json(LOOKS_PATH)
	looks = data.get("looks", {})
	bolts = data.get("bolts", {})


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func look_ids() -> Array:
	return looks.keys()


func has_look(look_id: String) -> bool:
	return looks.has(look_id)


## Build the ship for a look id. Unknown ids get the fallback stand-in so a missing
## look is visible in game instead of an invisible ship.
func build(look_id: String) -> Node3D:
	var p: Dictionary = looks.get(look_id, {})
	if p.is_empty():
		push_warning("ShipKit: unknown look id: ", look_id)
	var root := Node3D.new()
	root.name = look_id.to_pascal_case() if look_id != "" else "Ship"
	root.set_meta("look_id", look_id)
	var engines := Node3D.new()
	engines.name = "Engines"
	var flames := Node3D.new()
	flames.name = "Flames"
	flames.set_meta("no_bounds", true)      # left out of the ship's measured size (TownDecor.visual_aabb)
	flames.set_meta("flame_length", float(p.get("flame_length", 6.0)))
	flames.set_meta("palette", EngineFlame.palette(_c(p, "engine", "#8fd8ff")))
	root.add_child(flames)
	var scene_path := str(p.get("scene", ""))
	var model := _load_model(scene_path)
	if model != null:
		model.name = "Model"
		if p.get("darken") is Dictionary:
			darken(model, p.darken, _c(p, "trim", "#6b1e1e"))     # issue #76: the Remnant's dark ships
		if p.get("recolor") is Dictionary:
			recolor(model, p.recolor)                              # the locals' ships: the same paint, a little green
		root.add_child(model)
		root.add_child(engines)
		for n in p.get("flames_at", []):
			_flame(flames, Vector3(float(n[0]), float(n[1]), float(n[2])), float(n[3]))
		if not (p.get("parts", []) as Array).is_empty():
			var parts := Node3D.new()     # always on, unlike the upgrades (dress)
			parts.name = "Parts"
			root.add_child(parts)
			_bolt_on(parts, p.parts)
		throttle_flames(root, 0.0)
		root.set_meta("source", "scene")
		_scale_look(root, p)
		return root
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	root.add_child(engines)
	match str(p.get("frame", FALLBACK_FRAME)):
		"blade":
			_blade(body, engines, p)
		"hauler":
			_hauler(body, engines, p)
		_:
			_dart(body, engines, p)
	throttle_flames(root, 0.0)
	root.set_meta("source", "kit")
	_scale_look(root, p)
	return root


## A look's "scale" (the station's frigate: the freighter's airframe, twice the
## size): every part under the root is scaled about its middle, the root is not,
## so a ship flown or parked (its root's transform set outright) keeps the size.
## Its "length", "span" and "height" are already the scaled ones.
static func _scale_look(root: Node3D, p: Dictionary) -> void:
	var sc := float(p.get("scale", 1.0))
	if is_equal_approx(sc, 1.0):
		return
	root.set_meta("look_scale", sc)
	for c in root.get_children():
		(c as Node3D).scale *= sc


## The look a ship wears for whoever holds the place it stands at: a look's "locals"
## names its locals' paint (interceptor_dark -> interceptor_locals); any other look,
## or the Remnant's, stays as it is.
func look_for(look_id: String, owner: String) -> String:
	if owner == Territory.LOCALS:
		var held := str(looks.get(look_id, {}).get("locals", ""))
		if held != "" and looks.has(held):
			return held
	return look_id


## Swap a built ship's model for look `look_id`'s: the same airframe in another paint
## (an upgraded frigate, ShipUpgrades.look). The root keeps everything else hung on
## it (its hull, its place). A stand-in (no "Model") stays as it is.
func repaint(root: Node3D, look_id: String) -> void:
	var old := root.get_node_or_null("Model")
	if old == null or str(root.get_meta("look_id", "")) == look_id:
		return
	var fresh := build(look_id)
	var model := fresh.get_node_or_null("Model")
	if model != null:
		root.remove_child(old)
		old.queue_free()
		fresh.remove_child(model)
		root.add_child(model)
		root.move_child(model, 0)
		root.set_meta("look_id", look_id)
	fresh.free()


## The upgrades T-89 fitted (ShipUpgrades ids), shown on a built ship: each id in
## the look's "upgrades" is a list of parts bolted onto the model, so they stack.
## Re-dressing replaces the last set; a ship whose look has none stays as built.
## A part: { mesh: "box" (size) | "cyl" (top, bottom, h, open) | "torus" (r, t) |
## "sphere" (r), pos, rot (degrees), mat: "glow" (energy) | "metal" | "plate",
## color, mirror (a copy at -x) }.
func dress(ship: Node3D, fits: Array) -> void:
	var old := ship.get_node_or_null("Upgrades")
	if old != null:
		ship.remove_child(old)
		old.free()
	var ups: Dictionary = looks.get(str(ship.get_meta("look_id", "")), {}).get("upgrades", {})
	var parts: Array = []
	for id in ups:
		if fits.has(id):
			parts.append_array(ups[id])
	if parts.is_empty():
		return
	var root := Node3D.new()
	root.name = "Upgrades"
	root.scale = Vector3.ONE * float(ship.get_meta("look_scale", 1.0))
	ship.add_child(root)
	_bolt_on(root, parts)


## Builds each part (see dress) under `root`.
func _bolt_on(root: Node3D, parts: Array) -> void:
	for part: Dictionary in parts:
		var mesh := _part_mesh(part)
		var col := Color(str(part.get("color", "#8a9099")))
		var mat: Material
		match str(part.get("mat", "metal")):
			"glow":
				mat = _glow(col, float(part.get("energy", 4.0)))
			"plate":
				mat = _plate(col)
			_:
				mat = mats.flat(col, 0.45, 0.55)
		if bool(part.get("open", false)):
			mat = (mat as BaseMaterial3D).duplicate()
			(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		var pos := _v(part.get("pos", [0, 0, 0]))
		var rot := _v(part.get("rot", [0, 0, 0])) * (PI / 180.0)
		var mi := _mi(root, mesh, mat, pos, rot)
		if str(part.get("mat", "")) == "glow":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if bool(part.get("mirror", false)):
			_mi(root, mesh, mat, Vector3(-pos.x, pos.y, pos.z), Vector3(rot.x, -rot.y, -rot.z)).cast_shadow = mi.cast_shadow


func _part_mesh(part: Dictionary) -> Mesh:
	match str(part.get("mesh", "box")):
		"cyl":
			var c := _cyl(float(part.get("top", 0.2)), float(part.get("bottom", 0.2)), float(part.get("h", 0.5)), 20)
			if bool(part.get("open", false)):
				c.cap_top = false
				c.cap_bottom = false
			return c
		"torus":
			var t := TorusMesh.new()
			var r := float(part.get("r", 0.3))
			var w := float(part.get("t", 0.04))
			t.inner_radius = r - w
			t.outer_radius = r + w
			t.rings = 24
			t.ring_segments = 8
			return t
		"sphere":
			return _sphere(float(part.get("r", 0.2)))
	return _box(_v(part.get("size", [0.2, 0.2, 0.2])))


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


## The ship's skin: the material on most of `model`'s surface (by vertex count on
## a model, by size on a stand-in's primitives), which the cockpit's canopy frame
## wears so it matches the outside of the ship.
static func skin(model: Node3D) -> Material:
	if model == null:
		return null
	var count := {}
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var box := mi.mesh.get_aabb().size
			var amount := box.x * box.y + box.y * box.z + box.z * box.x
			if mi.mesh is ArrayMesh:
				amount = float((mi.mesh as ArrayMesh).surface_get_array_len(i))
			count[m] = float(count.get(m, 0.0)) + amount
	var best: Material = null
	for m in count:
		if best == null or count[m] > count[best]:
			best = m
	return best


## Issue #76: a ship model painted dark. Textured parts go through the dark-gun
## shader (PlayerAvatar._darken: grey texels down, painted panels kept); flat-colour
## parts (the interceptor's model) go dark the same way by hand, their bright
## accent colours turned to `accent` (the look's trim: the Remnant's oxblood).
static func darken(model: Node3D, d: Dictionary, accent: Color) -> void:
	var body_mul := float(d.get("body_mul", 0.3))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var textured := false
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			if src.albedo_texture != null:
				textured = true
				continue
			var c := src.albedo_color
			var m := src.duplicate() as BaseMaterial3D
			if c.s > 0.5 and c.v > 0.3:
				m.albedo_color = Color(accent.r, accent.g, accent.b, c.a).lerp(Color(0, 0, 0, c.a), 0.15)
			else:
				m.albedo_color = Color(c.r * body_mul, c.g * body_mul, c.b * body_mul, c.a)
			m.metallic = maxf(m.metallic, 0.45)
			m.roughness = minf(m.roughness, 0.55)
			mi.set_surface_override_material(i, m)
		if textured:
			PlayerAvatar._darken(mi, d)


## A model in a small colour change, no new render. d.swap: { "#from": colour } turns
## each flat material close to `from` into the colour (a hex, or "locals.band": a
## faction colour, town_styles.json "factions"); d.tint multiplies the colour of a
## textured part (a model painted by its texture). Everything else stays.
static func recolor(model: Node3D, d: Dictionary) -> void:
	var swap: Dictionary = d.get("swap", {})
	var tint := Color(str(d.tint)) if d.has("tint") else Color.WHITE
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			if src.albedo_texture != null:
				m.albedo_color = src.albedo_color * tint
			else:
				var hit := false
				for from in swap:
					if _near(src.albedo_color, Color(str(from))):
						var to := str(swap[from])
						var c := LookMaterials.faction_color(to.get_slice(".", 0), to.get_slice(".", 1)) if to.contains(".") else Color(to)
						m.albedo_color = Color(c.r, c.g, c.b, src.albedo_color.a)
						hit = true
						break
				if not hit:
					continue
			mi.set_surface_override_material(i, m)


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.12


func _load_model(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		if path != "":
			push_warning("ShipKit: model not found, using stand-in: ", path)
		return null
	var res = ModelCache.scene(path)
	if res is PackedScene:
		var inst = res.instantiate()
		if inst is Node3D:
			return inst
		if inst != null:
			inst.free()
	push_warning("ShipKit: not a 3D scene, using stand-in: ", path)
	return null


## A bolt or seeker for the projectile field. `style` is "player", "hostile" or
## "missile" (keys of "bolts" in ships.json). The returned pivot's -Z is the
## direction of travel, so the scene can aim it with Basis.looking_at(velocity).
func build_bolt(style: String) -> Node3D:
	var b: Dictionary = bolts.get(style, {})
	var col := Color(str(b.get("color", "#ffffff")))
	var pivot := Node3D.new()
	pivot.name = "Bolt"
	var cyl := CylinderMesh.new()
	var w := float(b.get("width", 0.2))
	cyl.top_radius = w
	cyl.bottom_radius = w
	cyl.height = float(b.get("length", 5.0))
	cyl.radial_segments = 6
	cyl.rings = 1
	var mi := _mi(pivot, cyl, _glow(col, 6.0), Vector3.ZERO, TIP_FORWARD, Vector3.ONE, "Glow")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cockpit's glass catches it going by (CockpitView.gather_lights).
	pivot.add_to_group("glints")
	pivot.set_meta("glint_color", col)
	return pivot


# ------------------------------------------------------------------ materials

func _c(p: Dictionary, key: String, fallback: String) -> Color:
	return Color(str(p.get(key, fallback)))


func _plate(color: Color) -> StandardMaterial3D:
	return mats.flat(color, 0.55, 0.35)


func _glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.4)
	m.metallic = 0.6
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	return m


func _glow(color: Color, energy: float = 4.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ helpers

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE, nname: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if nname != "":
		mi.name = nname
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float, seg: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _prism(size: Vector3) -> PrismMesh:
	var pm := PrismMesh.new()
	pm.size = size
	return pm


## Engine glow disc facing +Z (the exhaust side), and its flame.
func _engine(engines: Node3D, color: Color, pos: Vector3, r: float) -> void:
	var mi := _mi(engines, _cyl(r, r, 0.12, 14), _glow(color, 5.0), pos, Vector3(PI * 0.5, 0, 0))
	mi.name = "Glow%d" % engines.get_child_count()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame(engines.get_parent().get_node("Flames"), pos + Vector3(0, 0, 0.06), r * 0.9)


## A flame out of a nozzle at `pos` (radius `r`), running aft (+Z): the jetpack's
## and the cruiser's flame (EngineFlame) in the ship's colours.
func _flame(flames: Node3D, pos: Vector3, r: float) -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), pos)
	EngineFlame.build(flames, xf, r, r * float(flames.get_meta("flame_length")), flames.get_meta("palette"), 14)


# ------------------------------------------------------------------ throttle flames

const FLAME_IDLE := 0.05      ## throttle below this: engines idle, flames out (the glow stays)
const FLAME_IGNITE := 4.0     ## how fast the flames bloom out of the nozzles (length per second)
const FLAME_CUT := 3.0        ## how fast they die back when the throttle closes
const FLAME_BOOST := 1.35     ## boost burns this much longer


## The engines light when the throttle opens. Eases a built ship's flames toward
## `throttle` (0..1; `boost` burns longer): they bloom out of the nozzles when the
## throttle comes up off idle, die back when it closes, and waver while lit (as the
## jetpack's and the cruiser's do). Call once a frame; `dt` 0 snaps straight there.
static func throttle_flames(ship: Node3D, throttle: float, boost := false, dt := 0.0) -> void:
	var f := ship.get_node_or_null("Flames") as Node3D
	if f == null or f.get_child_count() == 0:
		return
	var want := 0.0 if throttle < FLAME_IDLE else lerpf(0.5, 1.0, clampf(throttle, 0.0, 1.0)) * (FLAME_BOOST if boost else 1.0)
	var lit := float(f.get_meta("lit", 0.0))
	if dt <= 0.0:
		lit = want
	else:
		lit = move_toward(lit, want, dt * (FLAME_IGNITE if want > lit else FLAME_CUT))
	f.set_meta("lit", lit)
	f.visible = lit > 0.01
	if not f.visible:
		return
	var t := Time.get_ticks_msec() * 0.001
	var w0 := lerpf(0.4, 1.0, minf(lit * 1.6, 1.0))      # they open out as they lengthen
	var i := 0
	for fl in f.get_children():
		var k := 1.0 + 0.07 * sin(t * 17.0 + i * 2.1) + 0.04 * sin(t * 43.0 + i * 0.7)
		var w := w0 * (1.0 + 0.025 * sin(t * 29.0 + i * 1.3))
		(fl as Node3D).scale = Vector3(w, maxf(lit * k, 0.001), w)
		i += 1


const ALONG_Z := Vector3(PI * 0.5, 0.0, 0.0)      # cylinder axis -> +/-Z
const TIP_FORWARD := Vector3(-PI * 0.5, 0.0, 0.0)  # cylinder top -> -Z
const FIN := Vector3(0.0, PI * 0.5, 0.0)            # prism profile in the side plane


# ------------------------------------------------------------------ frames

## "dart": the smuggler-side interceptor. Long nose, swept wings with tip guns,
## twin engines, one dorsal fin. Reads as a forward arrow at any range.
func _dart(body: Node3D, engines: Node3D, p: Dictionary) -> void:
	var L := float(p.get("length", 9.0))
	var S := float(p.get("span", 7.6))
	var H := float(p.get("height", 1.6))
	var hull := _plate(_c(p, "hull", "#c9c2b4"))
	var trim := _plate(_c(p, "trim", "#d99a2b"))
	var dark := _plate(_c(p, "dark", "#2a2c33"))
	var eng := _c(p, "engine", "#8fd8ff")
	var r := H * 0.36

	_mi(body, _cyl(r, r * 1.15, L * 0.62), hull, Vector3(0, 0, L * 0.08), ALONG_Z, Vector3.ONE, "Fuselage")
	_mi(body, _cyl(0.0, r, L * 0.32, 12), hull, Vector3(0, 0, -L * 0.39), TIP_FORWARD, Vector3.ONE, "Nose")
	_mi(body, _sphere(r * 0.95), _glass(_c(p, "canopy", "#1f7a78")),
		Vector3(0, r * 0.75, -L * 0.12), Vector3.ZERO, Vector3(0.8, 0.6, 1.9), "Canopy")
	for side in [-1.0, 1.0]:
		var wing := _mi(body, _box(Vector3(S * 0.46, 0.14, L * 0.3)), hull,
			Vector3(side * S * 0.25, -r * 0.2, L * 0.14), Vector3(0, -side * 0.38, 0), Vector3.ONE,
			"Wing" + ("L" if side < 0 else "R"))
		_mi(wing, _box(Vector3(S * 0.18, 0.16, L * 0.05)), trim, Vector3(side * S * 0.08, 0.01, -L * 0.07))
		_mi(body, _cyl(0.12, 0.12, L * 0.42, 8), dark, Vector3(side * S * 0.47, -r * 0.2, -L * 0.02), ALONG_Z)
		_mi(body, _cyl(r * 0.55, r * 0.6, L * 0.34), dark, Vector3(side * r * 1.25, -r * 0.1, L * 0.3), ALONG_Z)
		_engine(engines, eng, Vector3(side * r * 1.25, -r * 0.1, L * 0.475), r * 0.46)
	_mi(body, _prism(Vector3(L * 0.26, H * 0.9, 0.12)), hull, Vector3(0, r + H * 0.4, L * 0.32),
		FIN, Vector3.ONE, "Fin")
	_mi(body, _box(Vector3(r * 0.5, 0.06, L * 0.5)), trim, Vector3(0, r * 1.02, L * 0.05))


## "blade": the remnant fighter. A dark armoured pod with forward-swept, drooping
## blade wings and a tall dorsal spine -- a hunched predator silhouette.
func _blade(body: Node3D, engines: Node3D, p: Dictionary) -> void:
	var L := float(p.get("length", 5.0))
	var S := float(p.get("span", 6.0))
	var H := float(p.get("height", 4.2))
	var hull := _plate(_c(p, "hull", "#3d4147"))
	var trim := _plate(_c(p, "trim", "#6b1e1e"))
	var dark := _plate(_c(p, "dark", "#1e1c1c"))
	var r := L * 0.24

	_mi(body, _sphere(r), hull, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.85, 1.5), "Pod")
	_mi(body, _cyl(r * 0.5, r * 0.62, 0.2, 10), _glass(_c(p, "canopy", "#ffae4a")),
		Vector3(0, r * 0.12, -r * 1.42), ALONG_Z, Vector3.ONE, "Eye")
	_mi(body, _cyl(r * 0.66, r * 0.66, 0.08, 10), trim, Vector3(0, r * 0.12, -r * 1.34), ALONG_Z)
	for side in [-1.0, 1.0]:
		var wing := _mi(body, _box(Vector3(S * 0.46, 0.12, L * 0.42)), hull,
			Vector3(side * S * 0.26, -r * 0.35, -L * 0.04), Vector3(0, side * 0.5, -side * 0.38), Vector3.ONE,
			"Wing" + ("L" if side < 0 else "R"))
		_mi(wing, _box(Vector3(S * 0.46, 0.14, L * 0.06)), trim, Vector3(0, 0.01, -L * 0.2))
		_mi(body, _cyl(0.09, 0.09, L * 0.3, 6), dark, Vector3(side * r * 0.45, -r * 0.55, -L * 0.3), ALONG_Z)
	_mi(body, _prism(Vector3(L * 0.62, H * 0.55, 0.14)), dark, Vector3(0, r * 0.8 + H * 0.2, L * 0.08),
		FIN, Vector3.ONE, "Spine")
	_mi(body, _cyl(r * 0.45, r * 0.55, L * 0.18), dark, Vector3(0, 0, r * 1.45), ALONG_Z)
	_engine(engines, _c(p, "engine", "#ff7a4a"), Vector3(0, 0, r * 1.56), r * 0.38)


## "hauler": the remnant heavy fighter. A wide armoured block with a wedge prow,
## two engine nacelles on stub wings and a third engine on the spine.
func _hauler(body: Node3D, engines: Node3D, p: Dictionary) -> void:
	var L := float(p.get("length", 12.0))
	var S := float(p.get("span", 8.4))
	var H := float(p.get("height", 2.6))
	var hull := _plate(_c(p, "hull", "#4b4f55"))
	var trim := _plate(_c(p, "trim", "#a8844a"))
	var dark := _plate(_c(p, "dark", "#1e1c1c"))
	var eng := _c(p, "engine", "#ff7a4a")

	_mi(body, _box(Vector3(S * 0.42, H, L * 0.62)), hull, Vector3(0, 0, L * 0.06), Vector3.ZERO, Vector3.ONE, "Hull")
	_mi(body, _prism(Vector3(S * 0.42, L * 0.3, H)), hull, Vector3(0, 0, -L * 0.4), TIP_FORWARD,
		Vector3.ONE, "Prow")
	_mi(body, _box(Vector3(S * 0.18, H * 0.3, L * 0.08)), _glass(_c(p, "canopy", "#ffae4a")),
		Vector3(0, H * 0.48, -L * 0.2), Vector3(-0.3, 0, 0), Vector3.ONE, "Bridge")
	_mi(body, _box(Vector3(S * 0.43, H * 0.14, L * 0.04)), trim, Vector3(0, H * 0.2, -L * 0.1))
	for side in [-1.0, 1.0]:
		_mi(body, _box(Vector3(S * 0.22, H * 0.22, L * 0.22)), dark, Vector3(side * S * 0.3, 0, L * 0.12))
		_mi(body, _cyl(H * 0.42, H * 0.46, L * 0.6), hull, Vector3(side * S * 0.42, 0, L * 0.04), ALONG_Z,
			Vector3.ONE, "Nacelle" + ("L" if side < 0 else "R"))
		_mi(body, _cyl(H * 0.47, H * 0.47, L * 0.05), trim, Vector3(side * S * 0.42, 0, -L * 0.18), ALONG_Z)
		_engine(engines, eng, Vector3(side * S * 0.42, 0, L * 0.345), H * 0.34)
	_mi(body, _box(Vector3(S * 0.12, H * 0.5, L * 0.3)), dark, Vector3(0, H * 0.7, L * 0.2))
	_engine(engines, eng, Vector3(0, H * 0.7, L * 0.355), H * 0.2)
