class_name PlatformWorld
extends Node3D
## A town on a platform (issue #45): water, lava and gas worlds, and asteroid
## stations. Built from the town's own data and the planet type's "surface":
##
##   - the deck: the town's floors, closed underneath by a hull (a keel you can see
##     from the air), so nothing falls through the bottom of the town
##   - a glass enclosure rising from the perimeter walls, open above (ships lift
##     out of it), solid to people and to ships
##   - an energy shield across the open gate: translucent, glowing, and walkable
##     (no collision): the gate stays open
##   - what lies below: a sea, a lava lake, cloud decks of gas, or the asteroid's
##     own rock with debris drifting round it
##   - falling off the deck kills you: a fade, the type's line ("You went over the
##     edge and into the lava."), and you wake by the landing bay, as when the
##     garrison drags you to the pit
##
## Colliders are built in the greybox too (the traces walk and fall with real
## physics); dress() adds the looks.

signal fell                            ## the player went over the edge and was put back

const ENCLOSURE_HEIGHT := 24.0
const FALL_FADE_Y := -25.0             ## below the deck: the screen starts to go
const FALL_DEAD_Y := -60.0             ## and here you are dead

var demo
var planet: Dictionary
var surface: Dictionary = {}
var deck := Rect2()                    ## xz: every floor of the town (inside + apron)
var bounds := Rect2()                  ## xz: the walls
var gate := { "x": 0.0, "z0": 0.0, "z1": 0.0, "h": 5.0 }
var glass_boxes: Array = []            ## { id, min, max } (WorldGround boxes too)
var enclosure_height := ENCLOSURE_HEIGHT
var depth := 160.0                     ## metres from the deck down to the surface
var falls := 0                         ## times the player went over (traces, tests)
var fall_text := ""
var shield: MeshInstance3D
var _falling := false
var _fade: ColorRect
var _fade_t := 0.0


func setup(town_scene, p: Dictionary) -> void:
	demo = town_scene
	planet = p
	var tcfg: Dictionary = p.get("type_cfg", {})
	surface = tcfg.get("surface", {})
	depth = float(surface.get("depth", 160.0))
	enclosure_height = float(tcfg.get("enclosure_height", ENCLOSURE_HEIGHT))
	fall_text = str(tcfg.get("fall_text", ""))
	_measure(demo.town)


func _measure(town) -> void:
	var first := true
	for b in town.boxes():
		if str(b.kind) != "floor":
			continue
		var r := _rect(b)
		deck = r if first else deck.merge(r)
		first = false
	var bd: Dictionary = town.data.get("bounds", {})
	if not bd.is_empty():
		bounds = Rect2(float(bd.min[0]), float(bd.min[1]), float(bd.max[0]) - float(bd.min[0]), float(bd.max[1]) - float(bd.min[1]))
	var lintel: Dictionary = town.get_box("gate_lintel")
	if not lintel.is_empty():
		gate = { "x": float(lintel.max[0]), "x0": float(lintel.min[0]), "z0": float(lintel.min[2]), "z1": float(lintel.max[2]),
			"h": float(lintel.min[1]) }


func _ready() -> void:
	name = "Platform"
	_build_glass_colliders()
	_build_underside_collider()


# ------------------------------------------------------------------ gameplay

## Glass panels on every perimeter wall, up to the enclosure height; over the gate
## the glass starts above the lintel, so the opening below stays open.
func _build_glass_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "Glass"
	add_child(body)
	glass_boxes = []
	for b in demo.town.boxes():
		if str(b.get("zone", "")) != "perimeter":
			continue
		var top := float(b.max[1])
		if top >= enclosure_height:
			continue
		var mn := Vector3(float(b.min[0]), top, float(b.min[2]))
		var mx := Vector3(float(b.max[0]), enclosure_height, float(b.max[2]))
		var id := "glass_" + str(b.id)
		glass_boxes.append({ "id": id, "min": mn, "max": mx })
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mx - mn
		cs.shape = shape
		cs.position = (mn + mx) * 0.5
		body.add_child(cs)


## The hull under the deck: a slab the full size of the deck.
func _build_underside_collider() -> void:
	var body := StaticBody3D.new()
	body.name = "Underside"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(deck.size.x, 5.5, deck.size.y)
	cs.shape = shape
	cs.position = Vector3(deck.get_center().x, -0.5 - 2.75, deck.get_center().y)
	body.add_child(cs)
	add_child(body)


## Where the ground is under (x, z) for the fall guard: the deck's own top on the
## deck, far below it everywhere else (the guard leaves the edge to this node).
func ground_at(x: float, z: float) -> float:
	if deck.has_point(Vector2(x, z)):
		return 0.0
	return -depth - 1000.0


## The glass, as WorldGround boxes (ships bump into it), and for an asteroid its
## rock as a column under the deck.
func add_to_ground(ground: WorldGround) -> void:
	for g in glass_boxes:
		ground.add_box(str(g.id), "wall", g.min, g.max)
	if str(surface.get("kind", "")) == "rock":
		var r := float(surface.get("radius", 260.0))
		var c := deck.get_center()
		ground.columns.append({ "id": "asteroid_rock", "kind": "rock", "center": Vector3(c.x, -depth - r * 1.4, c.y),
			"radius": r, "top": -12.0 })


func _physics_process(dt: float) -> void:
	var p: Node3D = demo._player if demo != null else null
	if p == null or not is_instance_valid(p) or bool(p.get("piloting")):
		return
	var y := p.global_position.y
	if _falling:
		_fade_t += dt
		_set_fade(clampf(_fade_t / 0.8, 0.0, 1.0))
		if y < FALL_DEAD_Y or _fade_t > 2.5:
			_respawn(p)
		return
	if y < FALL_FADE_Y:
		_falling = true
		_fade_t = 0.0


## Back by the landing bay, on your feet. Nothing is taken: the edge did this.
func _respawn(p: Node3D) -> void:
	_falling = false
	falls += 1
	var at: Vector3 = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
	p.global_position = at
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
		if "controller" in p and p.controller != null:
			p.controller.velocity = Vector3.ZERO
			p.controller.body_pos = at
	WorldState.bump("falls")
	if fall_text != "":
		WorldState.log_event(fall_text)
	var pl = demo.get("pilot") if demo != null else null
	if pl != null and is_instance_valid(pl):
		pl.woke_in_pit()                 # issue #368: your primary ship is on the pad
	var tw := create_tween()
	tw.tween_method(_set_fade, 1.0, 0.0, 0.8)
	if demo.pads.size() > 0 and demo.pads[0].has_method("toast"):
		demo.pads[0].toast((fall_text + "  " if fall_text != "" else "") + GameFlow.label("fall_wake"), 4.0)
	fell.emit()


func _set_fade(a: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		_fade = ColorRect.new()
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_fade)
	_fade.color = Color(0, 0, 0, a)


func is_falling() -> bool:
	return _falling


# ------------------------------------------------------------------ looks

## The keel, the glass, the shield and what lies below. `env` drives the glows.
func dress(env: LookEnvironment, mats: LookMaterials) -> void:
	_dress_keel(mats)
	_dress_glass(mats)
	_dress_shield(env)
	match str(surface.get("kind", "")):
		"water":
			_sea(false)
		"lava":
			_sea(true, env)
		"gas":
			if str(planet.get("ground", "")) != "ball":
				_clouds()               # a gas ball's own ball is the clouds (PlanetTerrain); its ring is the town scene's
		"rock":
			_asteroid(mats)


func _dress_keel(mats: LookMaterials) -> void:
	var c := deck.get_center()
	var slab := MeshInstance3D.new()
	slab.name = "Deck"
	var bm := BoxMesh.new()
	bm.size = Vector3(deck.size.x, 5.5, deck.size.y)
	slab.mesh = bm
	slab.position = Vector3(c.x, -0.5 - 2.75, c.y)
	slab.material_override = mats.hull(-50.0, 6.0)
	add_child(slab)
	# A tapered keel under it: the platform reads as a built thing from the air.
	var keel := MeshInstance3D.new()
	keel.name = "Keel"
	var cyl := CylinderMesh.new()
	var r := maxf(deck.size.x, deck.size.y) * 0.5
	cyl.top_radius = r * 0.62
	cyl.bottom_radius = r * 0.08
	cyl.height = r * 0.55
	cyl.radial_segments = 8
	keel.mesh = cyl
	keel.scale = Vector3(deck.size.x / maxf(deck.size.y, 1.0), 1.0, 1.0)
	keel.position = Vector3(c.x, -6.0 - cyl.height * 0.5, c.y)
	keel.material_override = mats.hull(-50.0, 8.0)
	add_child(keel)
	# Lights round the deck edge.
	var glow := mats.glow(Color("#7fe0ff"))
	glow.emission_energy_multiplier = 1.4
	for i in 4:
		var e := MeshInstance3D.new()
		var b := BoxMesh.new()
		var along_x := i < 2
		b.size = Vector3(deck.size.x, 0.25, 0.3) if along_x else Vector3(0.3, 0.25, deck.size.y)
		e.mesh = b
		e.material_override = glow
		var z := deck.position.y if i == 0 else deck.end.y
		var x := deck.position.x if i == 2 else deck.end.x
		e.position = Vector3(c.x, -1.2, z) if along_x else Vector3(x, -1.2, c.y)
		add_child(e)


func _dress_glass(mats: LookMaterials) -> void:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.72, 0.88, 0.96, 0.14)
	glass.metallic = 0.3
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := mats.hull(-50.0, 3.0)
	var root := Node3D.new()
	root.name = "GlassLook"
	add_child(root)
	for g in glass_boxes:
		var mn: Vector3 = g.min
		var mx: Vector3 = g.max
		var pane := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = mx - mn
		pane.mesh = bm
		pane.material_override = glass
		pane.position = (mn + mx) * 0.5
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pane)
		# Mullions every 8 m and a rail along the top.
		var along_x := (mx.x - mn.x) > (mx.z - mn.z)
		var length := (mx.x - mn.x) if along_x else (mx.z - mn.z)
		var n := maxi(1, int(length / 8.0))
		for k in n + 1:
			var t := float(k) / float(n)
			var m := MeshInstance3D.new()
			var mb := BoxMesh.new()
			mb.size = Vector3(0.3, mx.y - mn.y, 0.3)
			m.mesh = mb
			m.material_override = frame
			var px := lerpf(mn.x, mx.x, t) if along_x else (mn.x + mx.x) * 0.5
			var pz := (mn.z + mx.z) * 0.5 if along_x else lerpf(mn.z, mx.z, t)
			m.position = Vector3(px, (mn.y + mx.y) * 0.5, pz)
			root.add_child(m)
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(mx.x - mn.x + 0.4, 0.4, mx.z - mn.z + 0.4)
		rail.mesh = rb
		rail.material_override = frame
		rail.position = Vector3((mn.x + mx.x) * 0.5, mx.y, (mn.z + mx.z) * 0.5)
		root.add_child(rail)


## The gate's shield: glowing glass you walk straight through.
func _dress_shield(env: LookEnvironment) -> void:
	if not gate.has("x0"):
		return
	shield = MeshInstance3D.new()
	shield.name = "GateShield"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, float(gate.h), float(gate.z1) - float(gate.z0))
	shield.mesh = bm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.35, 0.85, 1.0, 0.22)
	m.emission_enabled = true
	m.emission = Color("#5fe0ff")
	m.emission_energy_multiplier = 1.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield.material_override = m
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.position = Vector3((float(gate.x0) + float(gate.x)) * 0.5, float(gate.h) * 0.5, (float(gate.z0) + float(gate.z1)) * 0.5)
	add_child(shield)


func _process(dt: float) -> void:
	if shield != null:
		var m := shield.material_override as StandardMaterial3D
		var t := Time.get_ticks_msec() / 1000.0
		m.albedo_color.a = 0.18 + 0.07 * sin(t * 2.2)


func _sea(lava: bool, env: LookEnvironment = null) -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Lava" if lava else "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60000, 60000)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	sea.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(str(surface.get("color", "#1d4f6e")))
	m.roughness = float(surface.get("roughness", 0.1))
	m.metallic = float(surface.get("metallic", 0.2))
	m.albedo_texture = LookEnvironment.make_noise_texture(256, 11, 0.03)
	m.uv1_scale = Vector3(400, 400, 1)
	if lava:
		m.emission_enabled = true
		m.emission = Color(str(surface.get("glow", "#ff5a14")))
		m.emission_energy_multiplier = float(surface.get("emission", 2.0))
		m.emission_texture = m.albedo_texture
		var light := OmniLight3D.new()
		light.light_color = Color(str(surface.get("glow", "#ff5a14")))
		light.omni_range = depth * 1.6
		light.light_energy = 1.6
		light.position = Vector3(deck.get_center().x, -depth * 0.6, deck.get_center().y)
		add_child(light)
	sea.material_override = m
	sea.position = Vector3(deck.get_center().x, -depth, deck.get_center().y)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _clouds() -> void:
	var layers := int(surface.get("layers", 4))
	var top := Color(str(surface.get("color", "#d8a8c8")))
	var deep := Color(str(surface.get("deep", "#8a5a98")))
	for i in layers:
		var t := float(i) / maxf(layers - 1, 1)
		var c := MeshInstance3D.new()
		c.name = "Cloud%d" % i
		var pm := PlaneMesh.new()
		pm.size = Vector2(50000, 50000)
		c.mesh = pm
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = top.lerp(deep, t)
		m.albedo_color.a = 0.55 if i < layers - 1 else 1.0
		m.albedo_texture = LookEnvironment.make_noise_texture(256, 21 + i, 0.02)
		m.uv1_scale = Vector3(120 + i * 40, 120 + i * 40, 1)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 1.0
		c.material_override = m
		c.position = Vector3(deck.get_center().x, -depth * (0.55 + 0.45 * t), deck.get_center().y)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)


## The asteroid itself: one big lumpy rock the station is bolted onto, and
## debris drifting round it.
func _asteroid(mats: LookMaterials) -> void:
	var r := float(surface.get("radius", 260.0))
	var rock := mats.rock(-depth - r, 0.06)
	rock.set_shader_parameter("rock_a", Color(str(surface.get("color", "#5a5a5e"))))
	rock.set_shader_parameter("rock_b", Color(str(surface.get("color", "#5a5a5e"))).lightened(0.15))
	rock.set_shader_parameter("rock_dark", Color(str(surface.get("deep", "#2e2e32"))))
	rock.set_shader_parameter("dust", Color(str(surface.get("color", "#5a5a5e"))).lightened(0.3))
	var noise := FastNoiseLite.new()
	noise.seed = 45
	noise.frequency = 1.2 / r
	noise.fractal_octaves = 4
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 1.5
	sphere.radial_segments = 48
	sphere.rings = 24
	var body := MeshInstance3D.new()
	body.name = "Asteroid"
	body.mesh = LookMeshKit.rock(sphere, noise, 0.32, 0.0, 4.5, 0.4)
	body.material_override = rock
	var c := deck.get_center()
	body.position = Vector3(c.x, -depth - r * 0.62, c.y)
	add_child(body)
	# Debris: a MultiMesh of small rocks round the big one.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4545
	var n := int(surface.get("debris", 40))
	var small := SphereMesh.new()
	small.radius = 1.0
	small.height = 1.6
	small.radial_segments = 10
	small.rings = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	noise.frequency = 1.4
	mm.mesh = LookMeshKit.rock(small, noise, 0.35, 0.0, 2.0, 0.4)
	mm.instance_count = n
	for i in n:
		var a := rng.randf() * TAU
		var dist := r * rng.randf_range(1.3, 3.2)
		var y := -depth + rng.randf_range(-r * 0.8, r * 0.6)
		var s := rng.randf_range(2.0, 14.0)
		var basis := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(c.x + cos(a) * dist, y, c.y + sin(a) * dist)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Debris"
	mmi.multimesh = mm
	mmi.material_override = rock
	add_child(mmi)


static func _rect(b: Dictionary) -> Rect2:
	return Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
