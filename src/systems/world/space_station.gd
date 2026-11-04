class_name SpaceStation
extends Node3D
## A space station in this planet's sky (StationHull: its shape; one config file
## per station in content/core/stations/). Its boxes are already in the ship's
## ground and the walkers' colliders (the "station" landmark put them there); this
## node adds what moves and what you see:
##   - the look: every part merged by finish, the cruiser's metal, glass, glow
##   - the energy shield across the bay's mouth (ships and bolts through, not you),
##     the shields in the tunnels' roofs and round the gaps between floors (you
##     through, not the air)
##   - an elevator in each tower: a platform riding its shaft floor to floor, and the
##     shaft's doors, open only where it has stopped
##   - Z docking: the same calls the cruiser answers (can_dock, dock_path, dock_yaw,
##     dock_cfg, line), so ShipPilot flies you into its bay the same way
##   - the label naming it in the sky while you fly, interior lights, and a pull back
##     aboard if you fall out
##   - open to the air where the planet's air is breathable (no harmful_surface:
##     the ringed giant): the bay's shield lets you walk out, you roam outside on
##     the jetpack, and you are pulled back only if you drop toward a gas ball's
##     clouds (open_air)
## Nothing here is about one planet: SpaceStation is built for every "station"
## landmark of the world it is in (town_demo._build_stations).

const SHADER := preload("res://src/systems/look/shaders/cruiser_metal.gdshader")
const FINISHES := { "hull": 0, "trim": 1, "deck": 2, "wall": 3, "grate": 4, "rail": 8, "pad": 10, "beacon": 11 }

var demo                               ## town_demo.gd
var ground: WorldGround
var hull: StationHull
var cfg: Dictionary = {}
var landmark: Dictionary = {}
var id := ""
var frame := Transform3D.IDENTITY
var inv := Transform3D.IDENTITY
var vessel_name := ""
var cars: Array = []                   ## per tower: { tower, c, stops, body, at, i, dir, wait, moving, doors: [[floor, CollisionShape3D, Node3D]] }
var falls := 0                         ## times you were pulled back aboard (traces, tests)
var rides := 0                         ## elevator stops reached with you aboard the car (traces)
var open_air := false                  ## the planet's air is breathable: you may go outside (setup)

var _root: Node3D
var _inside: Node3D
var _layer: CanvasLayer
var _label: Label
var _was_aboard := false
var _shadow_capped := false

static var _meshes: Dictionary = {}    ## "<station>/<finish>" -> ArrayMesh, built once a session


func setup(town_demo, world_ground: WorldGround, lm: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	landmark = lm
	hull = StationHull.for_id(str(lm.get("station", "")))
	cfg = hull.cfg if hull != null else {}
	id = str(lm.get("id", hull.id if hull != null else "station"))
	frame = StationHull.frame(ground, id)
	inv = frame.affine_inverse()
	name = "SpaceStation_" + id
	vessel_name = NameHooks.vessel(cfg, "station:" + id)
	var pl = demo.get("planet") if demo != null else null
	open_air = pl is Dictionary and not (pl as Dictionary).is_empty() and HarmfulSurface.config(pl).is_empty()


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Frame"
	add_child(_root)
	_root.transform = frame
	if hull == null:
		return
	if demo != null and demo.use_look:
		_build_look()
		_lights()
	_build_shield()
	_build_hatches()
	_build_tubes()
	_build_elevators()
	_build_label()


# ------------------------------------------------------------------ queries

func to_world(local: Vector3) -> Vector3:
	return frame * local


func aboard(p: Vector3) -> bool:
	return hull != null and hull.aboard(inv * p)


func label() -> String:
	var l := str(cfg.get("label", "station"))
	return str(cfg.get("name_fmt", "%s")) % vessel_name if vessel_name != "" else l


func distance(p: Vector3) -> float:
	return p.distance_to(frame.origin)


func can_dock(p: Vector3) -> bool:
	return hull != null and distance(p) <= float(dock_cfg().get("radius", 2500.0)) and not aboard(p)


func dock_path(p: Vector3) -> Array:
	return hull.dock_path(inv * p).map(func(l): return frame * (l as Vector3))


## The dock pad's heading (a yaw about world up: the station is level).
func dock_yaw() -> float:
	return (frame.basis * Basis(Vector3.UP, float(hull.dock_pad().get("yaw", 0.0)))).get_euler().y


func dock_cfg() -> Dictionary:
	return cfg.get("dock", {})


func line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, ""))


## The dock pad, in the world.
func dock_point() -> Vector3:
	return frame * (hull.dock_pad().get("at", Vector3.ZERO) as Vector3)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if hull == null:
		return
	var p: Node3D = demo._player if demo != null and "_player" in demo else null
	var at := inv * p.global_position if p != null and is_instance_valid(p) else Vector3.INF
	for car in cars:
		_step_car(car, dt, at)
	if p == null or not is_instance_valid(p):
		return
	if _inside != null:
		_inside.visible = distance(p.global_position) < float(cfg.get("lights_within", 3000.0))
	_fall_guard(p)
	var here := hull.aboard(at)
	if demo.look != null and here != _shadow_capped:
		_shadow_capped = here
		demo.look.set_shadow_cap(float(cfg.get("aboard_shadow_distance", 0.0)) if here else 0.0)


func _exit_tree() -> void:
	if _shadow_capped and demo != null and demo.look != null:
		demo.look.set_shadow_cap(0.0)


## Fallen out of the station (off a tunnel's roof, out past the shield): back
## aboard beside the dock pad. In open air going outside is fine: over a gas ball
## (WorldGround.lethal_below) you are pulled back only once you drop the station's
## outside.drop_below metres under its lowest floor, toward the clouds; over solid
## ground, never (you land).
func _fall_guard(p: Node3D) -> void:
	if p.get("piloting") == true:
		_was_aboard = false
		return
	if open_air:
		if ground == null or ground.lethal_below == -INF or aboard(p.global_position):
			return
		var drop := float(cfg.get("outside", {}).get("drop_below", 40.0))
		if (inv * p.global_position).y >= hull.bottom_y() - drop or distance(p.global_position) > 3000.0:
			return
		_pull_back(p, line("fell_clouds"))
		return
	if aboard(p.global_position):
		_was_aboard = true
		return
	if _was_aboard and hull.on_roof(inv * p.global_position):
		return                         # out on a tunnel's roof walk, through its hatch
	if not _was_aboard:
		return
	if distance(p.global_position) > 1000.0:
		_was_aboard = false            # moved away (woken in the pit, towed home), not fallen
		return
	_pull_back(p, line("fell"))


func _pull_back(p: Node3D, text: String) -> void:
	p.global_position = frame * hull.spawn_point()
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	falls += 1
	_toast(text, 3.0)


# ------------------------------------------------------------------ the elevators

## A platform in each tower's shaft (an AnimatableBody3D, so whoever stands on it
## rides it with their normal movement), and the shaft's doors on every floor.
func _build_elevators() -> void:
	var el: Dictionary = cfg.get("elevator", {})
	var r := float(el.get("car_radius", 4.5))
	for e in hull.elevators():
		var c: Vector2 = e.c
		var body := AnimatableBody3D.new()
		body.name = "Elevator_" + str(e.tower)
		body.sync_to_physics = true
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = 0.5
		cs.shape = shape
		cs.position = Vector3(0, -0.25, 0)
		body.add_child(cs)
		_root.add_child(body)
		var y0: float = e.stops[0]
		body.position = Vector3(c.x, y0, c.y)
		if demo != null and demo.use_look:
			_dress_car(body, r)
		var car := { "tower": str(e.tower), "c": c, "stops": e.stops, "body": body, "at": y0, "i": 0, "dir": 1,
			"wait": float(el.get("wait", 3.5)), "moving": false, "target": 0, "doors": [], "rider": false }
		for d in hull.doors:
			if str(d.tower) != str(e.tower):
				continue
			var db := StaticBody3D.new()
			db.name = "ShaftDoor_%s_%d" % [str(e.tower), int(d.floor)]
			var dcs := CollisionShape3D.new()
			var ds := BoxShape3D.new()
			ds.size = d.size
			dcs.shape = ds
			db.add_child(dcs)
			_root.add_child(db)
			db.transform = d.xf
			var look: Node3D = null
			if demo != null and demo.use_look:
				look = _mesh_box(d.size, _door_mat(), d.xf)
			car.doors.append([int(d.floor), dcs, look])
		cars.append(car)
		_set_doors(car)


## One frame of a car: wait at its stop (its doors open), then move on to the next
## stop: on along its way with you aboard, to your floor when you stand by its
## shaft elsewhere, else on round its floors.
func _step_car(car: Dictionary, dt: float, player: Vector3) -> void:
	var el: Dictionary = cfg.get("elevator", {})
	var stops: Array = car.stops
	var c: Vector2 = car.c
	var body: AnimatableBody3D = car.body
	var on_car := Vector2(player.x - c.x, player.z - c.y).length() <= float(el.get("car_radius", 4.5)) + 0.3 \
		and absf(player.y - float(car.at)) < 2.5
	var n := stops.size()
	if bool(car.moving):
		var ty := float(stops[int(car.target)])
		car.at = move_toward(float(car.at), ty, float(el.get("speed", 4.0)) * dt)
		body.position = Vector3(c.x, float(car.at), c.y)
		if absf(float(car.at) - ty) < 0.001:
			car.moving = false
			car.i = int(car.target)
			car.wait = float(el.get("wait", 3.5))
			if on_car:
				rides += 1
			_set_doors(car)
		return
	car.wait = float(car.wait) - dt
	if float(car.wait) > 0.0:
		return
	var next := -1
	if on_car:
		if int(car.i) + int(car.dir) < 0 or int(car.i) + int(car.dir) >= n:
			car.dir = -int(car.dir)
		next = int(car.i) + int(car.dir)
	else:
		var called := _called_floor(car, player)
		if called == int(car.i):
			car.wait = 0.5             # you are at its door: it waits for you
			return
		if called >= 0:
			next = called
			car.dir = 1 if called > int(car.i) else -1
		else:
			if int(car.i) + int(car.dir) < 0 or int(car.i) + int(car.dir) >= n:
				car.dir = -int(car.dir)
			next = int(car.i) + int(car.dir)
	car.target = clampi(next, 0, n - 1)
	car.moving = true
	_set_doors(car)


## The floor whose bridges (or the gap round the shaft) you stand on in this car's
## tower, or -1.
func _called_floor(car: Dictionary, player: Vector3) -> int:
	if player == Vector3.INF:
		return -1
	var c: Vector2 = car.c
	if Vector2(player.x - c.x, player.z - c.y).length() > hull.gap_r + 2.0:
		return -1
	var stops: Array = car.stops
	for k in stops.size():
		if player.y >= float(stops[k]) - 0.5 and player.y <= float(stops[k]) + 3.0:
			return k
	return -1


## Open the doors of the floor the car has stopped at; close the rest.
func _set_doors(car: Dictionary) -> void:
	for d in car.doors:
		var open: bool = not bool(car.moving) and int(d[0]) == int(car.i)
		(d[1] as CollisionShape3D).set_deferred("disabled", open)
		if d[2] != null:
			(d[2] as Node3D).visible = not open


func _dress_car(body: AnimatableBody3D, r: float) -> void:
	var deck := CylinderMesh.new()
	deck.top_radius = r
	deck.bottom_radius = r
	deck.height = 0.5
	deck.radial_segments = 32
	_mesh(deck, _mat("grate"), Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0)), body)
	var rim := TorusMesh.new()
	rim.inner_radius = r - 0.12
	rim.outer_radius = r + 0.05
	rim.rings = 40
	rim.ring_segments = 6
	_mesh(rim, _glow(Color("#7fd4ff"), 3.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), body)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5           # between the bridges, out of the way
		var post := BoxMesh.new()
		post.size = Vector3(0.18, 3.4, 0.18)
		_mesh(post, _mat("trim"), Transform3D(Basis.IDENTITY, Vector3(cos(a) * (r - 0.3), 1.7, sin(a) * (r - 0.3))), body)
	var crown := TorusMesh.new()
	crown.inner_radius = r - 0.4
	crown.outer_radius = r - 0.2
	crown.rings = 40
	crown.ring_segments = 6
	_mesh(crown, _mat("trim"), Transform3D(Basis.IDENTITY, Vector3(0, 3.4, 0)), body)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#cfeaff")
	lamp.light_energy = 2.0
	lamp.omni_range = 9.0
	lamp.position = Vector3(0, 3.0, 0)
	body.add_child(lamp)


# ------------------------------------------------------------------ the shield

## Across the bay's mouth: you cannot walk out into space, a ship flies straight
## through, and so do bolts both ways. In open air (breathable) it only keeps the
## weather out: you walk through it too.
func _build_shield() -> void:
	var sh := hull.shield()
	if sh.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "BayShield"
	body.set_meta("bolts_pass", true)
	for pc in ([] if open_air else sh.pieces):
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = (pc.size as Vector3) + Vector3(1.6, 0, 0)
		cs.shape = shape
		cs.transform = pc.xf
		body.add_child(cs)
	_root.add_child(body)
	if demo == null or not demo.use_look:
		return
	var mi := MeshInstance3D.new()
	mi.name = "ShieldLook"
	mi.mesh = _curved_shield(sh)
	mi.material_override = LookMaterials.energy_shield(sh.size, Vector3(0, 3, 6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	mi.transform = sh.xf


## The shields in the tunnels' roofs: no collider (you jump up through one onto
## the roof walk, and drop back in), only the look.
func _build_hatches() -> void:
	if demo == null or not demo.use_look:
		return
	for hc in hull.hatches:
		var mi := MeshInstance3D.new()
		mi.name = "Hatch_" + str(hc.tunnel)
		var bm := BoxMesh.new()
		bm.size = hc.size
		mi.mesh = bm
		mi.material_override = LookMaterials.energy_shield(hc.size, Vector3(0.8, 0, 0.8), Vector3.RIGHT)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
		mi.transform = hc.xf


## The shields round the gaps between floors (StationHull.tubes): no collider (jump
## the railing, jetpack up and step out through one onto the floor's roof), only
## the look: an open cylinder, its rims where it meets the ceiling and the floor
## above.
func _build_tubes() -> void:
	if demo == null or not demo.use_look:
		return
	for tb in hull.tubes:
		var h := float(tb.y1) - float(tb.y0)
		var r := float(tb.r)
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 48
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.name = "GapShield_%s_%d" % [str(tb.tower), int(tb.floor)]
		mi.mesh = cm
		mi.material_override = LookMaterials.energy_shield(Vector3(r * 2.0, h, r * 2.0), Vector3(0, 0.6, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c: Vector2 = tb.c
		mi.position = Vector3(c.x, (float(tb.y0) + float(tb.y1)) * 0.5, c.y)
		_root.add_child(mi)


## The shield's curve as a mesh in its own frame (StationHull.shield): the wall's arc
## across the mouth, full height, so the shader's rims sit on its top, bottom and ends.
static func _curved_shield(sh: Dictionary) -> ArrayMesh:
	var r := float(sh.r)
	var half := float(sh.half)
	var size: Vector3 = sh.size
	var mid := r * (1.0 + cos(half)) * 0.5
	var hy := size.y * 0.5
	var n := 32
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var t0 := -half + 2.0 * half * k / n
		var t1 := -half + 2.0 * half * (k + 1) / n
		var a0 := Vector3(r * cos(t0) - mid, -hy, r * sin(t0))
		var a1 := Vector3(r * cos(t1) - mid, -hy, r * sin(t1))
		var b0 := a0 + Vector3(0, 2.0 * hy, 0)
		var b1 := a1 + Vector3(0, 2.0 * hy, 0)
		var n0 := Vector3(cos(t0), 0, sin(t0))
		var n1 := Vector3(cos(t1), 0, sin(t1))
		for v in [[a0, n0, 0.0], [b0, n0, 1.0], [b1, n1, 1.0], [a0, n0, 0.0], [b1, n1, 1.0], [a1, n1, 0.0]]:
			st.set_normal(v[1])
			st.set_uv(Vector2(float(k) / n, v[2]))
			st.add_vertex(v[0])
	return st.commit()


# ------------------------------------------------------------------ the look

var _mats: Dictionary = {}


func _build_look() -> void:
	var groups := {}
	for p in hull.parts:
		var f := str(p.finish)
		if f == "pad":
			_pad(p)
			continue
		if not groups.has(f):
			groups[f] = []
		groups[f].append(p)
	for f in groups:
		var mi := MeshInstance3D.new()
		mi.name = "Station_" + str(f)
		mi.mesh = _merged(hull.id + "/" + str(f), groups[f])
		mi.material_override = _mat(str(f))
		if f in ["glass", "glass_floor", "glow", "beacon"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 50.0
		_root.add_child(mi)


func _mat(finish: String) -> Material:
	if _mats.has(finish):
		return _mats[finish]
	var m: Material
	match finish:
		"glass":
			m = RemnantCruiser._glass()
		"glass_floor":
			var g := RemnantCruiser._glass()
			g.albedo_color = Color(0.5, 0.7, 0.85, 0.28)
			g.roughness = 0.12
			m = g
		"glow":
			m = _glow(Color("#9fdcff"), 3.0)
		"beacon":
			m = _glow(Color("#ff5a3a"), 6.0)
		_:
			var sm := ShaderMaterial.new()
			sm.shader = SHADER
			sm.set_shader_parameter("finish", FINISHES.get(finish, 0))
			var noise = demo._flat_mats().noise if demo != null and demo.has_method("_flat_mats") else null
			if noise != null:
				sm.set_shader_parameter("noise_tex", noise)
			m = sm
	_mats[finish] = m
	return m


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	return RemnantCruiser._emissive(c, energy)


func _door_mat() -> Material:
	if not _mats.has("door"):
		var g := RemnantCruiser._glass()
		g.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
		g.emission_enabled = true
		g.emission = Color("#5fc8ff")
		g.emission_energy_multiplier = 0.6
		_mats["door"] = g
	return _mats["door"]


static func _merged(key: String, list: Array) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in list:
		var bm := BoxMesh.new()
		bm.size = p.size
		st.append_from(bm, 0, p.xf)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


func _pad(p: Dictionary) -> void:
	var m := _mat("pad").duplicate() as ShaderMaterial
	m.set_shader_parameter("plate_half", (p.size as Vector3) * 0.5)
	var mi := _mesh_box(p.size, m, p.xf)
	mi.name = "Station_" + str(p.id)


func _mesh_box(size: Vector3, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh(bm, mat, xf)


func _mesh(mesh: Mesh, mat: Material, xf: Transform3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	(parent if parent != null else _root).add_child(mi)
	return mi


## Lamps round every floor and over its gap, along the tunnels and over the bay's
## deck; off from far away.
func _lights() -> void:
	_inside = Node3D.new()
	_inside.name = "InteriorLights"
	_root.add_child(_inside)
	var list: Array = []
	for t in hull.towers:
		var c: Vector2 = t.c
		for f in t.floors:
			var y := float(f.y)
			var r := float(f.r)
			var rr := hull.gap_r + hull.walk + (r - hull.gap_r - hull.walk) * 0.5
			var n := 6 if r > 50.0 else 5
			for k in n:
				var a := TAU * (k + 0.25) / n
				list.append([Vector3(c.x + cos(a) * rr, y + hull.floor_h - 2.5, c.y + sin(a) * rr), "#ffe2b8", 4.0, r * 0.7])
			list.append([Vector3(c.x, y + hull.floor_h - 1.5, c.y), "#cfeaff", 3.0, 22.0])
	for tn in hull.tunnels:
		var l := float(tn.length)
		var x := 6.0
		while x < l:
			list.append([(tn.xf as Transform3D) * Vector3(x, hull.tunnel_h - 0.8, 0), "#dbe9ff", 2.0, 12.0])
			x += 16.0
	if not hull.bay.is_empty():
		var bx: Transform3D = hull.bay.xf
		var r := float(hull.bay.r)
		list.append([bx * Vector3(0, float(hull.bay.height) - 4.0, 0), "#e4edff", 9.0, 60.0])
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			list.append([bx * Vector3(cos(a) * r * 0.55, float(hull.bay.height) - 4.0, sin(a) * r * 0.55), "#e4edff", 7.0, 50.0])
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
	_label.add_theme_color_override("font_color", Color("#9fe8ff"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	_layer.add_child(_label)


func _process(_dt: float) -> void:
	if _label == null or demo == null:
		return
	var pilot = demo.get("pilot")
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


func _toast(text: String, secs: float) -> void:
	if text == "" or demo == null:
		return
	var gear = demo.get("gear")
	if gear != null and gear.hud != null:
		gear.hud.toast(text, secs)
