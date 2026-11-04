class_name BarracksLook
extends Node3D
## Issue #321: the inside of every walk-in barracks hall (BarracksHall), drawn by
## the town's decor (the look only; the greybox shows the pieces as plain boxes).
##   - the office is the Remnant cruiser's control room: OutpostRoom's consoles,
##     screens, holo table, floor and ceiling lights in the cruiser's finishes,
##     red and blue light, and the planet map (CruiserHolo) over the table, built
##     when the camera comes within holo.show_within,
##   - the corridor, the way in and the locked rooms in the cruiser's bulkheads,
##     a deck underfoot and light bars overhead,
##   - the bunk room: two-high bunks with mattresses, footlockers and lockers,
##   - doors: open frames on the doorways and locked ones (closed, a red light) on
##     the locked rooms, the corridor's ends and the rooms' walls; they go through
##     the building kit, so they batch with the town's,
##   - alarm lights: red lamps inside and over the door outside, pulsing while the
##     town alarm sounds (the Garrison's TownAlarm), off on calm.
## Nothing here collides: the pieces are town boxes (BarracksHall.pieces).

const ROOM_SHADER := preload("res://src/systems/look/shaders/cruiser_metal.gdshader")
const FINISHES := { "console": 7, "screen": 12, "bridge": 9, "wall": 3, "deck": 2, "trim": 1 }   ## RemnantCruiser's
const SHELL := ["back", "end_l", "end_r", "front_l", "front_r", "door_lintel", "roof"]   ## the kit draws these (plaster)

var demo                          ## the town scene (its garrison's alarm, its planet, its camera)
var halls: Array = []             ## per hall: { id, b, holo_at (world), holo, lamps: [OmniLight3D] }
var alarm_on := false             ## for tests and traces
var _mats := {}
var _noise: Texture2D
var _alarm_mat: StandardMaterial3D
var _t := 0.0
var _draw := {}                   ## world.json's draw_distance block, read once


## Draw every walk-in hall in `town`. The kit's parts (bunks, doors) go into the
## kit's next flush, with the town's buildings.
func dress(town, kit, mats: LookMaterials, town_demo = null) -> void:
	name = "BarracksLook"
	demo = town_demo
	_noise = mats.noise
	var spec := BarracksHall.spec()
	var red := Color(str(spec.get("alarm_lights", {}).get("color", "#ff2414")))
	_alarm_mat = StandardMaterial3D.new()          # its own: it pulses
	_alarm_mat.albedo_color = red.darkened(0.6)
	_alarm_mat.emission_enabled = true
	_alarm_mat.emission = red
	_alarm_mat.emission_energy_multiplier = 0.0
	for b in BarracksHall.halls(town.boxes()):
		_dress_hall(town, b, kit, mats)


func _dress_hall(town, b: Dictionary, kit, mats: LookMaterials) -> void:
	var xf := BarracksHall.frame(b)
	var o := BarracksHall.layout(b)
	var parts: Array = []               # { finish, size, xf (world) }
	var add := func(finish: String, size: Vector3, local: Transform3D) -> void:
		parts.append({ "finish": finish, "size": size, "xf": xf * local })
	var ix0: float = o.ix0
	var ix1: float = o.ix1
	var iz: float = o.iz
	var top: float = o.top
	var mid := Vector3((ix0 + ix1) * 0.5, 0, 0)
	# The office: the control room's parts (its own linings are the hall's here).
	for p in OutpostRoom.inside(BarracksHall.office_room(b)):
		var id := str(p.id)
		if id.begins_with("lining"):
			continue
		var c: Vector3 = p.center
		if id == "floor":
			c.y += 0.04                    # over the hall's deck
		add.call(str(p.finish), p.size, Transform3D(p.basis, c))
	# The inside walls and the locked rooms: bulkheads.
	for piece in town.boxes():
		if str(piece.get("part_of", "")) != str(b.id) or str(piece.kind) == "cover":
			continue
		if str(piece.id).trim_prefix(str(b.id) + "_") in SHELL:
			continue
		var mn := BarracksHall._v3(piece.min)
		var mx := BarracksHall._v3(piece.max)
		parts.append({ "finish": "wall", "size": mx - mn, "xf": Transform3D(Basis.IDENTITY, (mn + mx) * 0.5) })
	# Linings on the outer walls' inside faces, a deck underfoot and the ceiling.
	var g: Vector2 = o.gap
	var dz: float = o.dz
	add.call("wall", Vector3(0.04, top, 2.0 * iz), Transform3D(Basis.IDENTITY, Vector3(ix0 + 0.02, top * 0.5, 0)))
	for s: float in [-1.0, 1.0]:
		add.call("wall", Vector3(ix1 - ix0, top, 0.04), Transform3D(Basis.IDENTITY, Vector3(mid.x, top * 0.5, s * (iz - 0.02))))
	var z0 := dz - g.x * 0.5
	var z1 := dz + g.x * 0.5
	add.call("wall", Vector3(0.04, top, z0 + iz), Transform3D(Basis.IDENTITY, Vector3(ix1 - 0.02, top * 0.5, (z0 - iz) * 0.5)))
	add.call("wall", Vector3(0.04, top, iz - z1), Transform3D(Basis.IDENTITY, Vector3(ix1 - 0.02, top * 0.5, (z1 + iz) * 0.5)))
	add.call("wall", Vector3(0.04, top - g.y, g.x), Transform3D(Basis.IDENTITY, Vector3(ix1 - 0.02, (top + g.y) * 0.5, dz)))
	add.call("deck", Vector3(ix1 - ix0, 0.06, 2.0 * iz), Transform3D(Basis.IDENTITY, mid))
	add.call("wall", Vector3(ix1 - ix0, 0.04, 2.0 * iz), Transform3D(Basis.IDENTITY, Vector3(mid.x, top - 0.02, 0)))
	# Light bars down the corridor and over the bunks.
	var cx: float = o.cx
	var k := -iz + 2.5
	while k < iz - 1.0:
		add.call("glow", Vector3(1.2, 0.06, 0.3), Transform3D(Basis.IDENTITY, Vector3(cx, top - 0.06, k)))
		k += 5.0
	var bk: Vector2 = o.bunks
	var bx := ((o.p1 as Vector2).y + ix1) * 0.5
	for t: float in [0.3, 0.7]:
		add.call("glow", Vector3(0.3, 0.06, 1.6), Transform3D(Basis.IDENTITY, Vector3(bx, top - 0.06, lerpf(bk.x, bk.y, t))))
	_meshes(str(b.id), parts)
	# The bunk room's furniture and the doors, through the kit (its next flush).
	kit._xf = xf
	_bunks(b, kit, mats)
	for at in BarracksHall.doors(b):
		kit.door(at, float(BarracksHall.spec().get("locked_doors", {}).get("scale", 1.3)), false, true)
	for dw in BarracksHall.doorways(b):
		if not bool(dw.get("outside", false)):
			kit.door(dw.at, float(dw.scale), true)
	kit._xf = Transform3D.IDENTITY
	# Light: the office's red and blue (as an outpost's), the corridor's and the bunks'.
	var lights: Dictionary = BarracksHall.spec().get("lights", {})
	var oc: Array = lights.get("office", ["#ff3a2a", 1.6, "#4aa8ff", 1.4])
	var hs := BarracksHall.holo_spot(b)
	var off: Vector2 = o.office
	var reach := maxf(float(o.back), off.y - off.x) * 0.7
	_lamp(xf * Vector3(ix0 + 1.3, top - 1.2, (off.x + off.y) * 0.5), Color(str(oc[0])), float(oc[1]), reach)
	_lamp(xf * (hs + Vector3(0, 2.2, 0)), Color(str(oc[2])), float(oc[3]), reach)
	var every := float(lights.get("corridor_every", 9.0))
	var n_cor := maxi(1, int(2.0 * iz / every))
	for i in n_cor:
		var z := -iz + 2.0 * iz * (i + 0.5) / n_cor
		_lamp(xf * Vector3(cx, top - 0.6, z), Color(str(lights.get("corridor", "#dfe8ff"))), float(lights.get("corridor_energy", 1.5)), every * 0.9)
	for t: float in [0.28, 0.72]:
		_lamp(xf * Vector3(bx, 3.2, lerpf(bk.x, bk.y, t)), Color(str(lights.get("bunks", "#ffe8cc"))), float(lights.get("bunks_energy", 1.4)), maxf((bk.y - bk.x) * 0.6, 9.0))
	# The alarm's lamps: in the corridor at both ends, the office, the bunks and over the door outside.
	var lamps: Array = []
	var spots := [Vector3(cx, top - 0.3, -iz + 1.0), Vector3(cx, top - 0.3, iz - 1.0), Vector3(ix0 + 0.3, top - 0.4, (off.x + off.y) * 0.5),
		Vector3(bx, top - 0.3, o.bunk_far - float(o.bunk_side) * 0.6), Vector3(float(o.d) * 0.5 + 0.5, 2.35 * BarracksHall.n("door_scale", 1.6) + 0.9, dz)]
	for at: Vector3 in spots:
		lamps.append(_alarm_lamp(xf * at, xf.basis))
	halls.append({ "id": str(b.id), "b": b, "xf": xf, "holo_at": xf * (hs + Vector3(0, 1.01, 0)), "holo": null, "lamps": lamps })


## Every part of a finish as one mesh (in the world's frame), drawn up close only.
func _meshes(hall_id: String, parts: Array) -> void:
	var groups := {}
	for p in parts:
		var f := str(p.finish)
		if not groups.has(f):
			groups[f] = []
		groups[f].append(p)
	for f in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in groups[f]:
			var bm := BoxMesh.new()
			bm.size = p.size
			st.append_from(bm, 0, p.xf)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [hall_id, f]
		mi.mesh = st.commit()
		mi.material_override = _mat(str(f))
		if f in ["screen", "glow"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_near_only(mi)


## The bunk room: each bunk a post at each corner, two frames and two mattresses
## (and a pillow at the head, against the wall); footlockers and lockers with a lid
## line and a handle.
func _bunks(b: Dictionary, kit, mats: LookMaterials) -> void:
	var frame := mats.painted(Color("#3b3f45"), 0.5, 0.6)
	var cloth := mats.flat(Color("#59604c"), 0.95)
	var pillow := mats.flat(Color("#c9c3b2"), 0.95)
	var steel := mats.painted(Color("#4c5259"), 0.45, 0.55)
	var red := mats.painted(Color("#7a1c18"), 0.5, 0.3)
	var o := BarracksHall.layout(b)
	var head_x := float(o.ix1)                    # the front wall's rows have their heads on it
	for p in BarracksHall.bunk_parts(b):
		var s: Vector3 = p.size
		var c: Vector3 = p.center
		if str(p.finish) == "frame":
			var against_front: bool = c.x + s.x * 0.5 > head_x - 0.05
			for dx: float in [-1.0, 1.0]:
				for dz: float in [-1.0, 1.0]:
					kit.part(kit.box(0.06, s.y, 0.06), frame, Vector3(c.x + dx * (s.x * 0.5 - 0.03), s.y * 0.5, c.z + dz * (s.z * 0.5 - 0.03)))
			for y: float in [0.38, 1.38]:
				kit.part(kit.box(s.x, 0.08, s.z), frame, Vector3(c.x, y, c.z))
				kit.part(kit.box(s.x - 0.1, 0.14, s.z - 0.08), cloth, Vector3(c.x, y + 0.11, c.z))
				var hx := c.x + (s.x * 0.5 - 0.25) * (1.0 if against_front else -1.0)
				kit.part(kit.box(0.32, 0.1, s.z - 0.25), pillow, Vector3(hx, y + 0.23, c.z))
		else:
			kit.part(kit.box(s.x, s.y, s.z), steel, Vector3(c.x, s.y * 0.5, c.z))
			kit.part(kit.box(s.x + 0.02, 0.05, s.z + 0.02), red, Vector3(c.x, s.y * (0.85 if s.y > 1.0 else 0.75), c.z))


func _mat(f: String) -> Material:
	if _mats.has(f):
		return _mats[f]
	var m: Material
	if FINISHES.has(f):
		var sm := ShaderMaterial.new()
		sm.shader = ROOM_SHADER
		sm.set_shader_parameter("finish", FINISHES[f])
		sm.set_shader_parameter("noise_tex", _noise)
		m = sm
	else:                                   # "glow": the light bars
		var g := StandardMaterial3D.new()
		g.albedo_color = Color("#e8f6ff")
		g.emission_enabled = true
		g.emission = Color("#e8f6ff")
		g.emission_energy_multiplier = 3.0
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m = g
	_mats[f] = m
	return m


func _lamp(at: Vector3, col: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = maxf(reach, 4.0)
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at
	_near_only(l)
	return l


## A red lamp for the alarm: a light and its housing, both dark until the alarm.
func _alarm_lamp(at: Vector3, basis: Basis) -> OmniLight3D:
	var cfg: Dictionary = BarracksHall.spec().get("alarm_lights", {})
	var housing := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.18, 0.5)
	housing.mesh = bm
	housing.material_override = _alarm_mat
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(housing)
	housing.global_transform = Transform3D(basis, at)
	var l := OmniLight3D.new()
	l.light_color = Color(str(cfg.get("color", "#ff2414")))
	l.light_energy = 0.0
	l.omni_range = float(cfg.get("range", 10.0))
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	l.global_position = at - basis.x * 0.2
	return l


## The draw distance of an outpost's control room (content/look/world.json room_m).
func _near_only(n: Node3D) -> void:
	if _draw.is_empty():
		_draw = ItemKit._read_json(DrawDistance.LOOK_PATH).get("draw_distance", {})
	var end := float(_draw.get("room_m", 50.0))
	n.set_meta(DrawDistance.BASE, end)
	if n is Light3D:
		var l := n as Light3D
		l.distance_fade_enabled = true
		l.distance_fade_begin = end
		l.distance_fade_length = float(_draw.get("light_fade_m", 20.0))
	elif n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		gi.visibility_range_end = end
		gi.visibility_range_end_margin = end * float(_draw.get("fade_margin", 0.1))


# ------------------------------------------------------------------ live

func _process(dt: float) -> void:
	_t += dt
	_tick_alarm()
	_tick_holo()


## Is the town's alarm sounding? (The Remnant's garrison in town.)
func alarm_sounding() -> bool:
	if demo == null or not is_instance_valid(demo):
		return false
	var g = demo.get("garrison")
	return g != null and is_instance_valid(g) and g.alarm != null and (g.alarm as TownAlarm).active()


func _tick_alarm() -> void:
	var on := alarm_sounding()
	var cfg: Dictionary = BarracksHall.spec().get("alarm_lights", {})
	var pulse := 0.5 + 0.5 * sin(_t * TAU * float(cfg.get("pulse_hz", 1.1)))
	if on != alarm_on:
		alarm_on = on
		for h in halls:
			for l in h.lamps:
				(l as OmniLight3D).visible = on
	if not on:
		_alarm_mat.emission_energy_multiplier = 0.0
		return
	var e := float(cfg.get("energy", 3.0)) * (0.3 + 0.7 * pulse)
	_alarm_mat.emission_energy_multiplier = 1.0 + 4.0 * pulse
	for h in halls:
		for l in h.lamps:
			(l as OmniLight3D).light_energy = e


## The planet map over each office's holo table, built the first time the camera
## is near it and hidden (and stopped) when it is far.
func _tick_holo() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	var spec: Dictionary = BarracksHall.spec().get("holo", {})
	var within := float(spec.get("show_within", 45.0))
	for h in halls:
		var near: bool = cam.global_position.distance_to(h.holo_at) <= within
		if near and h.holo == null:
			h.holo = _make_holo(h)
			if h.holo == null:
				h.holo = false                   # no planet to show: never try again
		if h.holo is CruiserHolo:
			(h.holo as CruiserHolo).visible = near
			(h.holo as CruiserHolo).process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED


func _make_holo(h: Dictionary) -> CruiserHolo:
	if demo == null:
		return null
	var planet: Dictionary = demo.get("planet") if demo.get("planet") is Dictionary else {}
	var world: Dictionary = planet.get("world", {})
	var sp: PlanetSphere = null
	var pilot = demo.get("pilot")
	if pilot != null and pilot.ground != null:
		sp = pilot.ground.sphere()
	if sp == null:
		var r := float(world.get("terrain", {}).get("sphere_radius", 0.0))
		if r <= 0.0:
			return null                      # a flat world: no ball to draw
		sp = PlanetSphere.new(r)
	var spec: Dictionary = (CruiserHull.data().get("holo", {}) as Dictionary).duplicate(true)
	for k in BarracksHall.spec().get("holo", {}):
		spec[k] = BarracksHall.spec().holo[k]
	var lm := CruiserHull.landmark(world)
	var frame := Transform3D(Basis.IDENTITY, sp.center + Vector3(0, sp.radius + 7000.0, 0))
	if lm.is_empty():
		spec["no_cruiser"] = true
	else:
		frame = Transform3D(Basis.IDENTITY, CruiserHull.frame_for(sp, lm).origin)
	var names := { "town": NameHooks.town(world), "cruiser": NameHooks.vessel(CruiserHull.data(), "vessel:" + str(CruiserHull.data().get("id", "remnant_cruiser"))) }
	var moons: Array = []
	var travel = pilot.travel if pilot != null else null
	if travel != null:
		for body in travel.bodies:
			moons.append(body)
			names[str(body.id)] = str(body.name)
	else:
		moons = planet.get("neighbours", [])
		for m in moons:
			names[str(m.get("id", ""))] = str(m.get("name", ""))
	var k := float(spec.get("scale", 0.42))
	var holo := CruiserHolo.new()
	holo.setup(spec, sp, frame, Vector3.ZERO, world, moons, names)
	add_child(holo)
	holo.global_transform = Transform3D(holo.basis.scaled(Vector3.ONE * k), (h.holo_at as Vector3) + Vector3(0, float(spec.get("lift", 1.75)) * k, 0))
	return holo
