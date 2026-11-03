class_name WreckLook
extends RefCounted
## Issue #206: a story save's ship is a wreck until T-89 rebuilds it, and it
## looks it. No new model: every mesh under the ship gets a grime overlay (a
## multiply pass, triplanar, from a noise texture: duller colours and patchy dirt
## and soot), and a few scorch marks are projected onto the hull (Decals with a
## soft, ragged burn texture). remove() takes it all off again.
##
## Numbers: content/look/ships.json "wreck".

const LOOK_PATH := "res://content/look/ships.json"
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const META := "wreck_look_overlays"      ## MeshInstance3D -> its own material_overlay, to put back

static var _grime: StandardMaterial3D
static var _scorch: Texture2D


static func cfg() -> Dictionary:
	var f := FileAccess.open(LOOK_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d.get("wreck", {}) if d is Dictionary else {}


static func is_on(ship: Node3D) -> bool:
	return ship != null and ship.has_meta(META)


## Make `ship` (its model, or whatever stands in for it) look wrecked. Safe to call twice.
static func apply(ship: Node3D) -> void:
	if ship == null or is_on(ship):
		return
	var c := cfg()
	var kept := {}
	for mi in ship.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with("Flames") or (mi as MeshInstance3D).mesh == null:
			continue
		kept[mi] = (mi as MeshInstance3D).material_overlay
		(mi as MeshInstance3D).material_overlay = grime(c)
	ship.set_meta(META, kept)
	var box := _bounds(ship)
	if box.size == Vector3.ZERO:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("seed", 89))
	var marks: Array = c.get("scorch", [])
	for i in marks.size():
		var m: Dictionary = marks[i]
		var at: Array = m.get("at", [0.5, 0.5])      # across the hull's top, 0..1 in x and z
		var d := Decal.new()
		d.name = "WreckScorch%d" % i
		var r := float(m.get("size", 0.25)) * maxf(box.size.x, box.size.z)
		d.size = Vector3(r, box.size.y * 0.6, r)     # the hull's upper half only, never the sand under it
		d.texture_albedo = scorch()
		d.modulate = Color(str(c.get("scorch_color", "#1c1612")))
		d.albedo_mix = float(c.get("scorch_mix", 0.9))
		d.upper_fade = 0.05
		d.lower_fade = 0.05
		ship.add_child(d)
		d.position = Vector3(lerpf(box.position.x, box.end.x, float(at[0])), box.position.y + box.size.y * 0.75,
			lerpf(box.position.z, box.end.z, float(at[1])))
		d.rotation.y = rng.randf_range(0.0, TAU)


## Take the wreck's look off (rebuilt): the overlays they had, no scorch marks.
static func remove(ship: Node3D) -> void:
	if not is_on(ship):
		return
	var kept: Dictionary = ship.get_meta(META)
	for mi in kept:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = kept[mi]
	ship.remove_meta(META)
	for d in ship.get_children():
		if d is Decal and String(d.name).begins_with("WreckScorch"):
			ship.remove_child(d)
			d.queue_free()


## The grime pass: multiplies what is under it by a dusty, patchy brown-grey.
static func grime(c: Dictionary = {}) -> StandardMaterial3D:
	if _grime != null:
		return _grime
	var n := FastNoiseLite.new()
	n.seed = int(c.get("seed", 89))
	n.frequency = float(c.get("grime_frequency", 0.035))
	n.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(str(c.get("grime_dark", "#9a8874"))))     # soot and old oil
	ramp.set_color(1, Color(str(c.get("grime_light", "#e2d6c2"))))    # sun-bleached dust
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	var s := float(c.get("grime_scale", 0.18))
	m.uv1_scale = Vector3(s, s, s)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_grime = m
	return m


## A burn mark: dark in the middle, ragged at the edge, see-through outside.
static func scorch() -> Texture2D:
	if _scorch != null:
		return _scorch
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.95))
	g.add_point(0.45, Color(0.05, 0.035, 0.02, 0.75))
	g.set_color(g.get_point_count() - 1, Color(0.1, 0.08, 0.06, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.95, 0.5)
	t.width = 128
	t.height = 128
	_scorch = t
	return t


## The ship's meshes' box, in the ship's own frame.
static func _bounds(ship: Node3D) -> AABB:
	var acc := [null]
	TownDecor._merge_aabb(ship, Transform3D.IDENTITY, acc)
	return acc[0] if acc[0] != null else AABB()
