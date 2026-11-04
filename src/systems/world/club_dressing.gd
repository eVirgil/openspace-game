class_name ClubDressing
extends Node3D
## Issue #261: the cantina dressed as a club, from the town data's "club" block:
##
##   "club": { "style": "jazz", "bpm": 100 }
##
## Every marker with a "prop" gets that instrument in front of it (ClubProps:
## "dj_desk", "drum_kit", "upright_bass"), built in the performer's own space so
## their hands land on it. Then the room for the style:
##
##   jazz  the desert port: a chill, low-lit jazz club. Wood plank floor with a
##         checker floor round the stage, panelled walls under velvet drapes,
##         leather booths with candlelit tables, round tables over the cantina's
##         own, warm and blue stage spots through the haze, a neon sign over the
##         door and an upright piano and a saxophone on a stand by the stage.
##   rave  the moon: the whole dome is the club (no building). A round stage
##         with a laser droid hovering over it (shoot it and the lasers stop),
##         moving heads behind it, a hologram wall behind the DJ, rave speaker
##         stacks with strobes on top, an LED dance floor that
##         ripples on the beat, neon rings round the dome wall, a mirror ball
##         and a lit canopy over the bar. The dome's own lights are turned down
##         (AsteroidWorld.club_dim).
##
## Visual only (no collision): the town's boxes are what block. Positions come
## from the cantina's wall, stage, table and counter boxes.

const RingWall := preload("res://src/systems/world/ring_wall.gd")

var props: ClubProps
var cfg: Dictionary = {}
var inner := Rect2()          ## the cantina's floor inside its walls (x, z)
var ceiling := 5.0
var stage_c := Vector3.ZERO   ## the stage's centre on its top
var stage_r := 0.0
var round_c := Vector3.ZERO   ## issue #237: a round room (a "cantina_body" ring): its centre
var round_r := 0.0            ## and inside radius; 0 for the square room


func dress(town, scene: Node) -> void:
	name = "ClubDressing"
	cfg = town.data.get("club", {})
	if cfg.is_empty():
		return
	props = ClubProps.new(str(cfg.get("style", "jazz")), float(cfg.get("bpm", 100.0)))
	add_child(props)
	_measure(town)
	for m in town.markers():
		if m.has("prop"):
			_instrument(town, m)
	match props.style:
		"jazz":
			_jazz(town, scene)
		"rave":
			_rave(town, scene)


## The room's floor, ceiling and stage from the town's boxes.
func _measure(town) -> void:
	var w: Dictionary = town.get_box("cantina_wall_w")
	var e: Dictionary = town.get_box("cantina_wall_e_s")
	var n: Dictionary = town.get_box("cantina_wall_n")
	var s: Dictionary = town.get_box("cantina_wall_s")
	if not (w.is_empty() or e.is_empty() or n.is_empty() or s.is_empty()):
		inner = Rect2(float(w.max[0]), float(s.max[2]), float(e.min[0]) - float(w.max[0]), float(n.min[2]) - float(s.max[2]))
	var body: Dictionary = town.get_box("cantina_body")
	if not body.is_empty():
		var info := RingWall.info(body)
		round_c = info.c
		round_r = float(info.ri)
		inner = Rect2(round_c.x - round_r, round_c.z - round_r, round_r * 2.0, round_r * 2.0)
	var roof: Dictionary = town.get_box("cantina_roof")
	if not roof.is_empty():
		ceiling = float(roof.min[1])
	var st: Dictionary = town.get_box("cantina_stage")
	if not st.is_empty():
		stage_c = Vector3((float(st.min[0]) + float(st.max[0])) * 0.5, float(st.max[1]), (float(st.min[2]) + float(st.max[2])) * 0.5)
		stage_r = (float(st.max[0]) - float(st.min[0])) * 0.5


## The instrument for the performer at marker `m`, facing where they face.
func _instrument(town, m: Dictionary) -> void:
	var here: Vector3 = town.marker_pos(str(m.id))
	var yaw := 0.0
	if m.has("face"):
		yaw = atan2(float(m.face[0]) - here.x, float(m.face[2]) - here.z)
	var at := Transform3D(Basis(Vector3.UP, yaw), here)
	match str(m.prop):
		"dj_desk":
			props.dj_desk(at)
		"drum_kit":
			props.drum_kit(at)
		"upright_bass":
			props.upright_bass(at)


## Hide a box's greybox mesh (its collision stays) where the club draws its own.
func _hide_box(scene: Node, id: String) -> void:
	var body := scene.get_node_or_null("Town/" + id) if scene != null else null
	if body == null:
		return
	for c in body.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false


func _slab(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	return props._box(props, size, pos, mat)


# ------------------------------------------------------------------ jazz

func _jazz(town, scene: Node) -> void:
	if inner.size == Vector2.ZERO:
		return
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var mid := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	# The floor: dark planks wall to wall, a checker floor round the stage.
	if round_r > 0.0:
		props._cyl(props, round_r - 0.02, 0.012, Vector3(round_c.x, 0.006, round_c.z), ClubTextures.wood(Color("#4a2c1a"), 0.16))
	else:
		_slab(Vector3(x1 - x0, 0.012, z1 - z0), Vector3(mid.x, 0.006, mid.z), ClubTextures.wood(Color("#4a2c1a"), 0.16))
	if stage_r > 0.0:
		var side := stage_r * 2.0 + 4.0
		_slab(Vector3(side, 0.014, side), Vector3(stage_c.x, 0.008, stage_c.z), ClubTextures.checker(Color("#151312"), Color("#d6c8a8"), 0.55))
		_slab(Vector3(side + 0.12, 0.016, 0.06), Vector3(stage_c.x, 0.008, stage_c.z - side * 0.5), ClubTextures.brushed(Color("#b08e50"), 0.9))
		_slab(Vector3(side + 0.12, 0.016, 0.06), Vector3(stage_c.x, 0.008, stage_c.z + side * 0.5), ClubTextures.brushed(Color("#b08e50"), 0.9))
		_slab(Vector3(0.06, 0.016, side), Vector3(stage_c.x - side * 0.5, 0.008, stage_c.z), ClubTextures.brushed(Color("#b08e50"), 0.9))
		_slab(Vector3(0.06, 0.016, side), Vector3(stage_c.x + side * 0.5, 0.008, stage_c.z), ClubTextures.brushed(Color("#b08e50"), 0.9))
		# The stage's own top in planks, a velvet skirt round its rim.
		props._cyl(props, stage_r - 0.13, 0.012, stage_c + Vector3(0, 0.007, 0), ClubTextures.wood(Color("#6a4024"), 0.12, 0.4))
	_walls(town)
	_booths(town)
	_tables(town, scene)
	_stage_lights()
	for side in [-1.0, 1.0]:      # speaker stacks either side of the band, on the floor
		var at := stage_c + Vector3(-stage_r - 0.9, -stage_c.y, side * (stage_r - 0.4))
		props.speaker(Transform3D(Basis(Vector3.UP, PI * 0.5 - side * 0.5), at), Vector3(0.8, 1.5, 0.6))
		props.speaker(Transform3D(Basis(Vector3.UP, PI * 0.5 - side * 0.5), at + Vector3(0, 1.5, 0)), Vector3(0.7, 0.7, 0.55))
	_sign(town)
	_piano_and_sax(town)


## Panelled wainscot to 1.3 m on every wall it fits (not the door, the back bar or
## the stair tower), velvet drapes above it between the hall's pilasters.
func _walls(town) -> void:
	if round_r > 0.0:
		_round_walls(town)
		return
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var panel := ClubTextures.panels(Color("#3e2414"), 1.1)
	var rail := ClubTextures.brushed(Color("#b08e50"), 0.9)
	var velvet := ClubTextures.velvet(Color("#5a1420"))
	var door_lo := -2.0
	var door_hi := 2.0
	var lintel: Dictionary = town.get_box("cantina_door_lintel")
	if not lintel.is_empty():
		door_lo = float(lintel.min[2])
		door_hi = float(lintel.max[2])
	var tower: Dictionary = town.get_box("stair_tower")
	var tower_x := float(tower.max[0]) + 0.3 if not tower.is_empty() else x0
	var tower_z := float(tower.min[2]) - 0.3 if not tower.is_empty() else z1
	var counter: Dictionary = town.get_box("bar_counter")
	# Runs along each wall: [from, to] on that wall's axis.
	var runs := [
		["s", x0, x1], ["n", tower_x, x1],
		["e", z0, door_lo], ["e", door_hi, z1],
		["w", z0, (float(counter.min[2]) - 1.2) if not counter.is_empty() else z1],
	]
	for r in runs:
		var a := float(r[1])
		var b := float(r[2])
		if b - a < 0.5:
			continue
		var c := (a + b) * 0.5
		var len := b - a
		match str(r[0]):
			"s":
				_slab(Vector3(len, 1.3, 0.05), Vector3(c, 0.65, z0 + 0.025), panel)
				_slab(Vector3(len, 0.05, 0.09), Vector3(c, 1.32, z0 + 0.045), rail)
			"n":
				_slab(Vector3(len, 1.3, 0.05), Vector3(c, 0.65, z1 - 0.025), panel)
				_slab(Vector3(len, 0.05, 0.09), Vector3(c, 1.32, z1 - 0.045), rail)
			"e":
				_slab(Vector3(0.05, 1.3, len), Vector3(x1 - 0.025, 0.65, c), panel)
				_slab(Vector3(0.09, 0.05, len), Vector3(x1 - 0.045, 1.32, c), rail)
			"w":
				_slab(Vector3(0.05, 1.3, len), Vector3(x0 + 0.025, 0.65, c), panel)
				_slab(Vector3(0.09, 0.05, len), Vector3(x0 + 0.045, 1.32, c), rail)
	# Drapes between TownDecor's pilasters (every 4 m from 3 m in) on the long walls.
	var x := x0 + 5.0
	while x < x1 - 2.5:
		for side in [-1.0, 1.0]:
			if side > 0 and x < tower_x + 1.4:
				continue
			var z: float = z1 - 0.06 if side > 0 else z0 + 0.06
			var h := minf(4.2, ceiling - 3.0)
			_slab(Vector3(2.9, h, 0.06), Vector3(x, 1.45 + h * 0.5, z), velvet)
			for k in 6:              # folds
				_slab(Vector3(0.12, h, 0.05), Vector3(x - 1.25 + k * 0.5, 1.45 + h * 0.5, z - side * 0.05), velvet)
			_slab(Vector3(3.0, 0.08, 0.12), Vector3(x, 1.45 + h + 0.04, z - side * 0.04), rail)
		x += 4.0


## Issue #237: the round room's walls: the same wainscot and drapes, in straight
## runs round the curve, clear of its gaps (the door, the tower) and the back bar.
func _round_walls(town) -> void:
	var panel := ClubTextures.panels(Color("#3e2414"), 1.1)
	var rail := ClubTextures.brushed(Color("#b08e50"), 0.9)
	var velvet := ClubTextures.velvet(Color("#5a1420"))
	var keep_out := _round_keep_out(town)
	var run := 2.4
	var n := int(TAU * round_r / run)
	for i in n:
		var a := TAU * (i + 0.5) / n
		if _round_blocked(keep_out, a, run * 0.5 / round_r):
			continue
		var at := _on_wall(a, 0.03)
		_slab_at(Vector3(run, 1.3, 0.05), at, 0.65, panel)
		_slab_at(Vector3(run, 0.05, 0.09), _on_wall(a, 0.05), 1.32, rail)
		if i % 2 == 0:
			var h := minf(4.2, ceiling - 3.0)
			_slab_at(Vector3(run * 0.9, h, 0.06), _on_wall(a, 0.07), 1.45 + h * 0.5, velvet)
			_slab_at(Vector3(run, 0.08, 0.12), _on_wall(a, 0.09), 1.45 + h + 0.04, rail)


## Angle ranges [centre, half] (radians, round the room's centre) kept clear of
## wall dressing: the ring's gaps and the back bar behind the counter.
func _round_keep_out(town) -> Array:
	var out: Array = []
	var info := RingWall.info(town.get_box("cantina_body"))
	for g in info.gaps:
		out.append([float(g[0]), float(g[1]) + 0.12])
	var counter: Dictionary = town.get_box("bar_counter")
	if not counter.is_empty():
		var cz := (float(counter.min[2]) + float(counter.max[2])) * 0.5 - round_c.z
		var half := (float(counter.max[2]) - float(counter.min[2])) * 0.5 + 1.2
		out.append([atan2(cz, -sqrt(maxf(round_r * round_r - cz * cz, 0.0))), asin(clampf(half / round_r, 0.0, 1.0))])
	return out


func _round_blocked(keep_out: Array, a: float, half: float) -> bool:
	for k in keep_out:
		if absf(wrapf(a - float(k[0]), -PI, PI)) < float(k[1]) + half:
			return true
	return false


## A point on the inside of the round wall at angle `a`, `off` metres in from it,
## with the yaw that faces it into the room (local +z inward, x along the wall).
func _on_wall(a: float, off: float) -> Transform3D:
	var d := Vector3(cos(a), 0, sin(a))
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), round_c + d * (round_r - off))


func _slab_at(size: Vector3, at: Transform3D, y: float, mat: Material) -> void:
	var mi := _slab(size, Vector3.ZERO, mat)
	mi.transform = Transform3D(at.basis, at.origin + Vector3(0, y, 0))


## Leather booths along the side walls, each with a candlelit table.
func _booths(town) -> void:
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var tower: Dictionary = town.get_box("stair_tower")
	var west_n := float(tower.max[0]) + 0.6 if not tower.is_empty() else x0 + 1.0
	var spots := [
		[Vector3(x0 + 12.5, 0, z0 + 0.05), 0.0, 3.4], [Vector3(x1 - 2.5, 0, z0 + 0.05), 0.0, 3.0],
		[Vector3(west_n + 2.0, 0, z1 - 0.05), PI, 3.4], [Vector3(x1 - 4.0, 0, z1 - 0.05), PI, 3.4],
	]
	for s in spots:
		var p: Vector3 = s[0]
		var yaw: float = s[1]
		var len: float = s[2]
		if round_r > 0.0:
			# Issue #237: the same spot, on the curved wall, facing into the room.
			var at := _on_wall(atan2(p.z - round_c.z, p.x - round_c.x), 0.05 + len * len / (8.0 * round_r))
			p = at.origin
			yaw = at.basis.get_euler().y
		props.booth(Transform3D(Basis(Vector3.UP, yaw), p), len, Color("#5a1e1a"))
		var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
		props.cocktail_table(p + fwd * 1.15, 0.38, 0.72)


## A round table over each of the cantina's own (their greybox hidden; the box still
## blocks), with a candle and drinks.
func _tables(town, scene: Node) -> void:
	for b in town.boxes():
		var id := str(b.id)
		if not id.begins_with("cantina_table") and id != "fixer_table":
			continue
		var c := Vector3((float(b.min[0]) + float(b.max[0])) * 0.5, 0, (float(b.min[2]) + float(b.max[2])) * 0.5)
		var r := minf(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2])) * 0.5
		props.cocktail_table(c, r, float(b.max[1]))
		_hide_box(scene, id)


## Warm spots on the band from the ceiling, a cool blue wash from behind, and a
## slow-turning mirror ball over the floor.
func _stage_lights() -> void:
	if stage_r <= 0.0:
		return
	var y := ceiling - 0.6
	var c := stage_c + Vector3(0, 1.2, 0)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		props.spot(stage_c + Vector3(cos(a) * (stage_r + 3.0), y, sin(a) * (stage_r + 3.0)), c, Color("#ffb468"), 9.0)
	for i in 2:
		var a := PI + (i - 0.5) * 1.4
		props.spot(stage_c + Vector3(cos(a) * (stage_r + 1.5), y, sin(a) * (stage_r + 1.5)), stage_c + Vector3(0, 0.6, 0), Color("#3a6aff"), 6.0, 12.0)
	props.mirror_ball(stage_c + Vector3(0, ceiling - 1.6 - stage_c.y, 0), ceiling, 0.32)


## A neon sign high on the back wall facing the door: a cocktail glass and a
## crescent moon over a wavy underline.
func _sign(town) -> void:
	var counter: Dictionary = town.get_box("bar_counter")
	var x := inner.position.x + 0.12
	var zc := (inner.position.y + inner.end.y) * 0.5
	var y := 5.6 if ceiling > 7.0 else ceiling - 1.4
	if not counter.is_empty():
		zc = (float(counter.min[2]) + float(counter.max[2])) * 0.5
	if round_r > 0.0:          # issue #237: on the curved back wall, its widest point clear of it
		x = round_c.x - sqrt(maxf(round_r * round_r - pow(absf(zc - round_c.z) + 1.4, 2.0), 0.0)) + 0.12
	var pink := Color("#ff4aa0")
	var teal := Color("#3fe8d8")
	var amber := Color("#ffb040")
	# The glass: a V on a stem, an olive on a pick.
	var g := PackedVector3Array([
		Vector3(x, y + 1.0, zc - 0.9), Vector3(x, y + 0.2, zc - 0.4), Vector3(x, y + 1.0, zc + 0.1),
	])
	props.neon(g, pink, true)
	props.neon(PackedVector3Array([Vector3(x, y + 0.2, zc - 0.4), Vector3(x, y - 0.4, zc - 0.4)]), pink)
	props.neon(PackedVector3Array([Vector3(x, y - 0.4, zc - 0.75), Vector3(x, y - 0.4, zc - 0.05)]), pink)
	props.neon(PackedVector3Array([Vector3(x, y + 0.75, zc - 0.65), Vector3(x, y + 1.15, zc - 0.2)]), amber)
	# The crescent moon.
	var moon := PackedVector3Array()
	for k in 13:
		var a := lerpf(-2.2, 2.2, k / 12.0)
		moon.append(Vector3(x, y + 0.6 + sin(a) * 0.55, zc + 1.0 + cos(a) * 0.55))
	for k in 13:
		var a := lerpf(2.2, -2.2, k / 12.0)
		moon.append(Vector3(x, y + 0.6 + sin(a) * 0.4, zc + 1.18 + cos(a) * 0.38))
	props.neon(moon, teal, true)
	var wave := PackedVector3Array()
	for k in 17:
		var u := k / 16.0
		wave.append(Vector3(x, y - 0.75 + 0.08 * sin(u * TAU * 2.0), zc - 1.0 + u * 2.6))
	props.neon(wave, amber)


## An upright piano against the north wall by the stage and a saxophone resting
## on its stand at the stage's edge: nobody plays them tonight.
func _piano_and_sax(_town) -> void:
	if stage_r <= 0.0:
		return
	var z1 := inner.end.y
	if round_r > 0.0:          # issue #237: against the curved north wall
		var dx := stage_c.x - 4.6 - round_c.x
		z1 = round_c.z + sqrt(maxf(round_r * round_r - pow(absf(dx) + 0.8, 2.0), 0.0)) - 0.2
	var root := props._group("Piano", Transform3D(Basis(Vector3.UP, PI), Vector3(stage_c.x - 4.6, 0, z1 - 0.4)))
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color("#0e0b0a")
	lacquer.roughness = 0.12
	lacquer.clearcoat_enabled = true
	lacquer.clearcoat = 1.0
	props._box(root, Vector3(1.5, 1.25, 0.55), Vector3(0, 0.625, -0.05), lacquer)
	props._box(root, Vector3(1.52, 0.06, 0.6), Vector3(0, 1.28, -0.05), lacquer)
	props._box(root, Vector3(1.4, 0.06, 0.3), Vector3(0, 0.74, 0.32), lacquer)
	props._box(root, Vector3(1.3, 0.025, 0.16), Vector3(0, 0.78, 0.34), props._flat(Color("#f2ece0"), 0.3))
	for k in 36:
		if k % 7 in [2, 6]:
			continue
		props._box(root, Vector3(0.016, 0.02, 0.09), Vector3(-0.63 + k * 0.036, 0.8, 0.31), props._flat(Color("#0a0a0a"), 0.3))
	for side in [-1.0, 1.0]:
		props._box(root, Vector3(0.08, 0.74, 0.08), Vector3(side * 0.66, 0.37, 0.4), lacquer)
	props._box(root, Vector3(0.8, 0.06, 0.36), Vector3(0, 0.5, 0.85), ClubTextures.leather(Color("#2a1410"), 0.12))
	for sx in [-0.35, 0.35]:
		for sz in [0.7, 1.0]:
			props._box(root, Vector3(0.04, 0.48, 0.04), Vector3(sx, 0.24, sz), lacquer)
	props.candle(root, Vector3(0.5, 1.31, -0.05))
	# The saxophone on its stand: a brass body down to the bend and up to the bell.
	var sax := props._group("Sax", Transform3D(Basis(Vector3.UP, 0.6), stage_c + Vector3(stage_r * 0.62, 0, -stage_r * 0.55)))
	var brass := ClubTextures.brushed(Color("#c9a048"), 0.95)
	brass.roughness = 0.22
	var path := [Vector3(0.0, 0.95, -0.02), Vector3(0.0, 0.82, 0.0), Vector3(0.0, 0.35, 0.02), Vector3(0.03, 0.22, 0.06),
		Vector3(0.06, 0.22, 0.13), Vector3(0.07, 0.34, 0.16), Vector3(0.07, 0.5, 0.18)]
	for k in path.size() - 1:
		var r := lerpf(0.018, 0.05, float(k) / (path.size() - 1))
		props._rod(sax, path[k], path[k + 1], r, brass)
	props._cone(sax, 0.09, 0.05, 0.12, Vector3(0.07, 0.56, 0.18), brass)
	props._rod(sax, Vector3(0.0, 0.95, -0.02), Vector3(0.0, 1.02, -0.1), 0.01, props._flat(Color("#141414"), 0.4))
	for k in 6:
		props._cyl(sax, 0.012, 0.01, Vector3(0.0, 0.42 + k * 0.07, 0.04), props._flat(Color("#e8dcc0"), 0.4), Vector3(90, 0, 0))
	var stand := props._flat(Color("#1a1a1a"), 0.5, 0.6)
	props._rod(sax, Vector3(0.0, 0.0, 0.0), Vector3(0.02, 0.3, 0.06), 0.012, stand)
	for k in 3:
		var a := TAU * k / 3.0
		props._rod(sax, Vector3(0.0, 0.02, 0.0), Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.22), 0.01, stand)


# ------------------------------------------------------------------ rave

func _rave(town, scene: Node) -> void:
	if stage_r <= 0.0:
		return
	_hide_box(scene, "cantina_stage")
	var st: Dictionary = town.data.get("station", {})
	var centre := Vector3.ZERO
	var radius := 36.0
	var wall_h := 6.0
	var dome_h := 30.0
	if not st.is_empty():
		centre = Vector3(float(st.center[0]), 0.0, float(st.center[2]))
		radius = float(st.radius)
		wall_h = float(st.wall_height)
		dome_h = float(st.dome_height)
	var k: Dictionary = TownGen.new().kit.get("club_dome", {})
	var fmin := Vector2(centre.x, centre.z) + TownGen._v2(k.get("floor", {}).get("min", [0, 0]))
	var fmax := Vector2(centre.x, centre.z) + TownGen._v2(k.get("floor", {}).get("max", [0, 0]))
	var floor_mid := Vector3((fmin.x + fmax.x) * 0.5, 0.0, (fmin.y + fmax.y) * 0.5)
	# The stage faces the dance floor: `fwd` from the stage toward it, `side` across.
	var fwd := Vector3(floor_mid.x - stage_c.x, 0.0, floor_mid.z - stage_c.z).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var face := Basis(Vector3.UP, atan2(fwd.x, fwd.z))
	_rave_stage(fwd, side)
	_rave_rig(fwd, side, face, floor_mid)
	_rave_floor(fmin, fmax)
	_rave_speakers(fwd, side, face)
	_rave_walls(centre, radius, wall_h)
	_rave_bar(town)
	var ceil_at := func(p: Vector3) -> float:
		var d := Vector2(p.x - centre.x, p.z - centre.z).length()
		return wall_h + sqrt(maxf(0.0, 1.0 - pow(d / radius, 2.0))) * dome_h
	props.mirror_ball(floor_mid + Vector3(0, 9.0, 0), ceil_at.call(floor_mid), 0.6)
	_rave_lounge(town, scene)


## The stage: a black deck with a diamond-plate top, a lit rim that cycles through
## the colours, and steps down to the floor at the front.
func _rave_stage(fwd: Vector3, _side: Vector3) -> void:
	var h := stage_c.y
	var base := stage_c - Vector3(0, h, 0)
	props._cyl(props, stage_r, h - 0.04, base + Vector3(0, (h - 0.04) * 0.5, 0), ClubTextures.brushed(Color("#141418"), 0.6))
	props._cyl(props, stage_r - 0.04, 0.04, base + Vector3(0, h - 0.02, 0), ClubTextures.plate(Color("#3a3c42")))
	for y in [h - 0.06, 0.12]:
		var rim := ClubTextures.glow(Color("#ff2bd6"), 4.0)
		var t := TorusMesh.new()
		t.inner_radius = stage_r - 0.02
		t.outer_radius = stage_r + 0.03
		t.ring_segments = 12
		t.rings = 48
		props._put(props, t, base + Vector3(0, y, 0), rim)
		props.cycles.append([rim, 0.12, 0.0 if y > 0.5 else 0.5])
		props.pulses.append([rim, 2.0, 7.0, 1.0, 0.0])
	for i in 3:     # steps
		var d := stage_r + 0.25 + i * 0.35
		var sh := h - (i + 1) * h / 4.0
		var step := props._box(props, Vector3(2.4, sh, 0.36), base + fwd * d + Vector3(0, sh * 0.5, 0), ClubTextures.plate(Color("#3a3c42")))
		step.rotation.y = atan2(fwd.x, fwd.z)


## Over and behind the stage, with no truss: the laser droid (RaveDroid) hovering
## over the DJ with a fan of lasers under it, moving heads on the floor behind the
## stage throwing beams up over the crowd, and a hologram wall floating over its
## emitter behind the DJ. The strobes stand on the speaker stacks.
func _rave_rig(fwd: Vector3, side: Vector3, face: Basis, floor_mid: Vector3) -> void:
	var ground := stage_c - Vector3(0, stage_c.y, 0)
	var back := ground - fwd * (stage_r + 0.4)
	var span := stage_r + 1.4
	# Moving heads in a row on the floor behind the stage, sweeping beams over the crowd.
	var hues := [Color("#ff2bd6"), Color("#2bd9ff"), Color("#ffffff"), Color("#7aff5a"), Color("#ff2bd6"), Color("#2bd9ff")]
	for i in 6:
		var u := lerpf(-span + 0.8, span - 0.8, i / 5.0)
		var at: Vector3 = back + fwd * 0.5 + side * u + Vector3(0, 0.15, 0)
		var aim := floor_mid + side * (u * 1.3) + fwd * randf_range(-3.0, 3.0) + Vector3(0, randf_range(6.0, 9.0), 0)
		var l := props.spot(at, aim, hues[i], 14.0, 22.0)
		props.lights.append([l, 4.0, 16.0, 1.0, i * 0.25])
	# The laser droid: a fan of beams under it, out over the crowd.
	var droid := RaveDroid.new()
	droid.home = ground + fwd * 0.5 + Vector3(0, 6.6, 0)
	droid.fwd = fwd
	droid.side = side
	var deck := stage_c
	var deck_r := stage_r
	droid.floor_at = func(p: Vector3) -> float:
		return deck.y if Vector2(p.x - deck.x, p.z - deck.z).length() < deck_r else 0.0
	props.add_child(droid)
	for i in 18:      # two tiers: one dipping to the floor, one flat over the heads
		var a := lerpf(-0.75, 0.75, (i % 9) / 8.0)
		var dir := (face * Vector3(sin(a), -0.32 if i < 9 else -0.13, cos(a))).normalized()
		var beam := Node3D.new()
		droid.lasers.add_child(beam)
		beam.basis = Basis.looking_at(dir, Vector3.UP)
		var col: Color = [Color("#3aff4a"), Color("#ff2a3a"), Color("#2bd9ff")][i % 3]
		var core := props._cyl(beam, 0.01, 34.0, Vector3(0, 0, -17.0), ClubTextures.glow(col, 7.0), Vector3(90, 0, 0))
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var halo := props._cyl(beam, 0.04, 34.0, Vector3(0, 0, -17.0), ClubTextures.beam(col, 0.2), Vector3(90, 0, 0))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.fades.append([halo.material_override, 0.05, 0.3, 0.5, i * 0.11])
		props.sweeps.append([beam, beam.basis, Vector3.UP, 18.0, 3.2, i * 0.07])
	var lens := ClubTextures.glow(Color("#3aff4a"), 6.0)
	props._sphere(droid.lasers, 0.09, Vector3.ZERO, lens)
	props.cycles.append([lens, 0.2, 0.0])
	_rave_hologram(back, side, face, span)


## The hologram wall behind the DJ: a grid of see-through panels of light whose
## colours roll across it like the old LED wall's, flickering, with faint scan lines
## and a bright band climbing it, over a glowing emitter on the floor. No frame.
func _rave_hologram(back: Vector3, side: Vector3, face: Basis, span: float) -> void:
	var width := span * 2.0 - 0.8
	var y0 := 1.0
	var height := 4.6
	var emitter := ClubTextures.glow(Color("#2bd9ff"), 5.0)
	var strip := props._box(props, Vector3(width, 0.06, 0.18), back + Vector3(0, 0.03, 0), emitter)
	strip.basis = face
	props.cycles.append([emitter, 0.1, 0.0])
	props.pulses.append([emitter, 2.0, 7.0, 1.0, 0.0])
	var rise := ClubTextures.beam(Color("#2bd9ff"), 0.05)    # the light rising off the emitter
	var sheet := props._box(props, Vector3(width, y0, 0.01), back + Vector3(0, y0 * 0.5, 0), rise)
	sheet.basis = face
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.cycles.append([rise, 0.1, 0.0])
	var cols := 14
	var rows := 6
	var pw := width / cols
	var ph := height / rows
	for cx in cols:
		for cy in rows:
			var m := ClubTextures.beam(Color.from_hsv(0.0, 0.85, 1.0), 0.3)
			var p: Vector3 = back + side * ((cx - (cols - 1) * 0.5) * pw) + Vector3(0, y0 + (cy + 0.5) * ph, 0)
			var tile := props._box(props, Vector3(pw - 0.09, ph - 0.09, 0.01), p, m)
			tile.basis = face
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props.cycles.append([m, 0.1, cx * 0.035 + cy * 0.06])
			props.fades.append([m, 0.05, 0.3, 1.0, absf(cx - (cols - 1) * 0.5) * 0.06])
	var lines := ClubTextures.beam(Color("#bff4ff"), 0.08)
	var n := int(height / 0.16)
	for k in n:
		var line := props._box(props, Vector3(width, 0.012, 0.012), back + Vector3(0, y0 + (k + 0.5) * height / n, 0) + face.z * 0.01, lines)
		line.basis = face
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var band_mat := ClubTextures.beam(Color("#e8fbff"), 0.35)
	var band := props._box(props, Vector3(width, 0.12, 0.02), back, band_mat)
	band.basis = face
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.scans.append([band, back + Vector3(0, y0, 0) + face.z * 0.02, back + Vector3(0, y0 + height, 0) + face.z * 0.02, 2.4, 0.0])
	var wash := OmniLight3D.new()    # its colour on the DJ and the deck
	wash.omni_range = 9.0
	wash.light_energy = 1.2
	wash.shadow_enabled = false
	wash.position = back + face.z * 1.5 + Vector3(0, y0 + height * 0.5, 0)
	props.add_child(wash)
	props.cycles.append([wash, 0.1, 0.2])


## The LED dance floor: square tiles in a black grid, each cycling through the
## colours a little behind its neighbour and flashing on the beat in rings out
## from the middle.
func _rave_floor(fmin: Vector2, fmax: Vector2) -> void:
	var mid := (fmin + fmax) * 0.5
	props._box(props, Vector3(fmax.x - fmin.x + 0.4, 0.03, fmax.y - fmin.y + 0.4), Vector3(mid.x, 0.015, mid.y), ClubTextures.brushed(Color("#0c0c0e"), 0.6))
	var x := fmin.x + 0.5
	while x < fmax.x:
		var z := fmin.y + 0.5
		while z < fmax.y:
			var m := ClubTextures.glow(Color.from_hsv(0.0, 0.8, 1.0), 1.0)
			m.albedo_color = Color("#101012")
			m.roughness = 0.15
			props._box(props, Vector3(0.92, 0.035, 0.92), Vector3(x, 0.02, z), m)
			var d := Vector2(x, z).distance_to(mid)
			props.cycles.append([m, 0.06, (x + z) * 0.03])
			props.pulses.append([m, 0.25, 2.6, 1.0, -d * 0.09])
			z += 1.0
		x += 1.0


## Stacks of rave speakers either side of the stage, facing the floor, a strobe
## on each.
func _rave_speakers(fwd: Vector3, side: Vector3, face: Basis) -> void:
	for s in [-1.0, 1.0]:
		var foot: Vector3 = stage_c - Vector3(0, stage_c.y, 0) + side * s * (stage_r + 2.6) + fwd * 0.6
		var yaw := Basis(Vector3.UP, -s * 0.25) * face
		props.speaker(Transform3D(yaw, foot), Vector3(1.4, 1.2, 1.0))
		props.speaker(Transform3D(yaw, foot + Vector3(0, 1.2, 0)), Vector3(1.4, 1.2, 1.0))
		props.speaker(Transform3D(yaw, foot + Vector3(0, 2.4, 0)), Vector3(1.0, 0.9, 0.8))
		var strobe := ClubTextures.glow(Color("#ffffff"), 1.0)     # a strobe on top
		var bar := props._box(props, Vector3(0.5, 0.18, 0.12), foot + Vector3(0, 3.42, 0), strobe)
		bar.basis = yaw
		props.pulses.append([strobe, 0.0, 30.0, 2.0, 0.0])
		var flash := OmniLight3D.new()
		flash.light_color = Color("#e8f0ff")
		flash.omni_range = 18.0
		flash.shadow_enabled = false
		flash.position = foot + Vector3(0, 3.6, 0) + yaw.z * 0.4
		props.add_child(flash)
		props.lights.append([flash, 0.0, 6.0, 2.0, 0.0])


## Neon rings round the inside of the dome wall, cyan low and magenta high, the
## colours rolling round.
func _rave_walls(centre: Vector3, radius: float, wall_h: float) -> void:
	for ring in [[2.4, Color("#2bd9ff")], [wall_h - 0.6, Color("#ff2bd6")]]:
		var pts := _circle(centre + Vector3(0, float(ring[0]), 0), radius - 0.45, 96)
		var glow := ClubTextures.glow(ring[1], 4.0)
		for i in pts.size():
			props._rod(props, pts[i], pts[(i + 1) % pts.size()], 0.035, glow)
		props.pulses.append([glow, 1.5, 5.0, 1.0, 0.0 if float(ring[0]) < 3.0 else 0.5])


## A canopy over the bar for its lamps to hang from, edged in neon: over the
## counter and the owner's side of it (issue #392: it grows with the counter, and
## follows it wherever the owner stands), posts at the owner's corners.
func _rave_bar(town) -> void:
	var counter: Dictionary = town.get_box("bar_counter")
	if counter.is_empty():
		return
	var r := Rect2(float(counter.min[0]), float(counter.min[2]), float(counter.max[0]) - float(counter.min[0]),
		float(counter.max[2]) - float(counter.min[2])).grow(1.0)
	var owner: Vector3 = town.marker_pos("cantina_owner") if not town.get_marker("cantina_owner").is_empty() else Vector3.INF
	var back := Vector2.ZERO          # the owner's side of the counter, as a direction
	if owner != Vector3.INF:
		var mid := r.get_center()
		var d := Vector2(owner.x - mid.x, owner.z - mid.y)
		back = Vector2(signf(d.x), 0.0) if absf(d.x) / r.size.x > absf(d.y) / r.size.y else Vector2(0.0, signf(d.y))
		r = r.expand(Vector2(owner.x, owner.z) + back * 1.0)
	var c := Vector3(r.get_center().x, 4.3, r.get_center().y)
	props._box(props, Vector3(r.size.x, 0.2, r.size.y), c, ClubTextures.brushed(Color("#1a1a1e"), 0.6))
	var steel := ClubTextures.brushed(Color("#b8b8bc"))
	var across := Vector2(-back.y, back.x)
	var half := Vector2(r.size.x, r.size.y) * 0.5 - Vector2(0.2, 0.2)
	var post_at := Vector2(c.x, c.z) + Vector2(back.x * half.x, back.y * half.y)
	for s in [-1.0, 1.0]:
		var p: Vector2 = post_at + across * s * (absf(across.x) * half.x + absf(across.y) * half.y) * 0.9
		props._rod(props, Vector3(p.x, 0, p.y), Vector3(p.x, 4.2, p.y), 0.06, steel)
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var edge := PackedVector3Array([Vector3(x1, 4.18, z0), Vector3(x1, 4.18, z1), Vector3(x0, 4.18, z1), Vector3(x0, 4.18, z0)])
	props.neon(edge, Color("#2bd9ff"), true, 0.025, 5.0)
	# Lamps hanging over the counter, cycling slowly through the colours.
	var n := maxi(2, int(float(counter.max[0]) - float(counter.min[0])) / 3)
	var long_x := float(counter.max[0]) - float(counter.min[0]) >= float(counter.max[2]) - float(counter.min[2])
	for i in n:
		var u := (i + 0.5) / n
		var p := Vector3(lerpf(float(counter.min[0]), float(counter.max[0]), u), 3.0, (float(counter.min[2]) + float(counter.max[2])) * 0.5) if long_x \
			else Vector3((float(counter.min[0]) + float(counter.max[0])) * 0.5, 3.0, lerpf(float(counter.min[2]), float(counter.max[2]), u))
		props._rod(props, p, Vector3(p.x, 4.2, p.z), 0.008, steel)
		var shade := ClubTextures.glow(Color("#ff2bd6"), 3.0)
		props._cone(props, 0.06, 0.2, 0.22, p - Vector3(0, 0.11, 0), shade)
		props.cycles.append([shade, 0.04, float(i) / n])
		var l := OmniLight3D.new()
		l.omni_range = 3.5
		l.light_energy = 0.9
		l.shadow_enabled = false
		l.position = p - Vector3(0, 0.4, 0)
		props.add_child(l)
		props.cycles.append([l, 0.04, float(i) / n])


## Issue #392: the lounge round the bar (TownGen's lounge boxes, their greybox
## hidden): the port club's leather booths in black and purple leather with a
## neon line along the back, a low table in front of each, and high cocktail
## tables, each with a neon ring and a glow under its top.
func _rave_lounge(town, scene: Node) -> void:
	var k := 0
	for b in town.boxes():
		var id := str(b.id)
		if not id.begins_with("lounge_"):
			continue
		_hide_box(scene, id)
		var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
		var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
		var hue := Color.from_hsv(fposmod(0.83 + k * 0.29, 1.0), 0.85, 1.0)
		k += 1
		if id.begins_with("lounge_booth_") and not id.begins_with("lounge_booth_table_"):
			var face := str(b.get("face", "-z"))
			var dir: Vector3 = { "+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+z": Vector3.BACK, "-z": Vector3.FORWARD }.get(face, Vector3.FORWARD)
			var back: Array = b.get("back", [(mn.x + mx.x) * 0.5, (mn.z + mx.z) * 0.5])
			var at := Vector3(float(back[0]), 0, float(back[1]))
			var length := (mx.x - mn.x) if absf(dir.z) > 0.5 else (mx.z - mn.z)
			props.booth(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), at), length, Color("#2a1038"))
			var side := dir.cross(Vector3.UP)
			props.neon(PackedVector3Array([at + side * length * 0.5 + Vector3(0, 1.22, 0.0) + dir * 0.08,
				at - side * length * 0.5 + Vector3(0, 1.22, 0.0) + dir * 0.08]), hue, false, 0.014, 4.0)
			continue
		var c := Vector3((mn.x + mx.x) * 0.5, 0, (mn.z + mx.z) * 0.5)
		var r := minf(mx.x - mn.x, mx.z - mn.z) * 0.5
		props.cocktail_table(c, r - 0.02, mx.y, false)
		props.neon(_circle(c + Vector3(0, mx.y - 0.06, 0), r - 0.04, 18), hue, true, 0.012, 4.0)
		var glow := ClubTextures.glow(hue, 2.5)
		props._cyl(props, r * 0.8, 0.01, c + Vector3(0, mx.y - 0.075, 0), glow)
		props.pulses.append([glow, 1.0, 3.5, 2.0, k * 0.17])
		var under := OmniLight3D.new()
		under.light_color = hue
		under.light_energy = 0.6
		under.omni_range = 1.6
		under.shadow_enabled = false
		under.position = c + Vector3(0, mx.y - 0.25, 0)
		props.add_child(under)


static func _circle(c: Vector3, r: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
	return out
