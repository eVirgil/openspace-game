class_name ClubProps
extends Node3D
## Issue #261: the clubs' props, shared by both: the band's instruments (a DJ desk
## with glowing buttons and two glowing decks, a techno drum kit, an upright
## bass), the room (round tables with candles, leather booths, speaker stacks,
## stage spots with a beam of haze, neon tubes, a mirror ball) and what moves on
## the beat (the platters spin, buttons and cones pulse, lights sweep). Built from
## simple shapes like the bottles, in the ClubTextures surfaces, with no collision:
## the town data's boxes already block where something stands.
##
## An instrument is built in its performer's own space (feet at the origin, +Z the
## way they face, +X their left) from ClubMoves' numbers, so the hands NpcBody
## puts on it land on it. `at` is the performer's transform in the scene.
##
## Everything that moves stops when the club goes quiet (Sound.club_live false,
## a band member killed): the decks stop turning and the lights stop pulsing.

var bpm := 100.0
var style := "jazz"           ## "jazz" (warm wood and brass) or "rave" (black metal, LEDs)
var t := 0.0
var spins: Array = []         ## [Node3D, radians a second]
var pulses: Array = []        ## [StandardMaterial3D, low, high, beats a pulse, phase]
var sweeps: Array = []        ## [Node3D, Basis rest, Vector3 axis, degrees, seconds a sweep, phase]
var throbs: Array = []        ## [Node3D, scale amplitude, phase] (speaker cones)
var lights: Array = []        ## [Light3D, low, high, beats a pulse, phase]
var beam_alpha := 0.018       ## how thick the haze is in a spot's beam
var cycles: Array = []        ## [material or Light3D, hue turns a second, hue offset]: colours that cycle
var fades: Array = []         ## [StandardMaterial3D, low alpha, high alpha, beats a pulse, phase] (holograms)
var pops: Array = []          ## [Node3D, swell, beats a pulse, phase]: grows on the hit, settles back
var scans: Array = []         ## [Node3D, Vector3 from, Vector3 to, seconds a pass, phase]: glides from one to the other, again and again
var live_fn := Callable()     ## #269 cleanup: optional () -> bool, the barge's own "is the party on" (else Sound.club_live)


func _init(p_style := "jazz", p_bpm := 100.0) -> void:
	name = "ClubProps"
	style = p_style
	bpm = p_bpm


func _process(dt: float) -> void:
	if not _live():
		return
	t += dt
	var beat := t * bpm / 60.0
	for s in spins:
		(s[0] as Node3D).rotate_object_local(Vector3.UP, float(s[1]) * dt)
	for p in pulses:
		var k := _pulse(beat / float(p[3]) + float(p[4]))
		(p[0] as StandardMaterial3D).emission_energy_multiplier = lerpf(float(p[1]), float(p[2]), k)
	for l in lights:
		var k := _pulse(beat / float(l[3]) + float(l[4]))
		(l[0] as Light3D).light_energy = lerpf(float(l[1]), float(l[2]), k)
	for w in sweeps:
		var a := deg_to_rad(float(w[3])) * sin(TAU * (t / float(w[4]) + float(w[5])))
		(w[0] as Node3D).basis = (w[1] as Basis) * Basis(w[2], a)
	for f in fades:
		var m := f[0] as StandardMaterial3D
		var k := _pulse(beat / float(f[3]) + float(f[4]))
		m.albedo_color.a = lerpf(float(f[1]), float(f[2]), k) * (0.92 + 0.08 * sin(t * 47.0 + float(f[4]) * 9.0))
	for o in pops:
		(o[0] as Node3D).scale = Vector3.ONE * (1.0 + float(o[1]) * _pulse(beat / float(o[2]) + float(o[3])))
	for c in scans:
		(c[0] as Node3D).position = (c[1] as Vector3).lerp(c[2], fposmod(t / float(c[3]) + float(c[4]), 1.0))
	for c in cycles:
		var col := Color.from_hsv(fposmod(t * float(c[1]) + float(c[2]), 1.0), 0.85, 1.0)
		if c[0] is Light3D:
			(c[0] as Light3D).light_color = col
		else:
			var m := c[0] as StandardMaterial3D
			if m.emission_enabled:
				m.emission = col
			m.albedo_color = Color(col.r, col.g, col.b, m.albedo_color.a)
	for c in throbs:
		var k := 1.0 + float(c[1]) * _pulse(beat + float(c[2]))
		(c[0] as Node3D).scale = Vector3(1.0, k, 1.0)


func _live() -> bool:
	if live_fn.is_valid():
		return bool(live_fn.call())
	return Sound.lib().club_live


## A sharp rise on the beat that falls away before the next (0..1).
static func _pulse(beats: float) -> float:
	return pow(1.0 - fposmod(beats, 1.0), 3.0)


# ------------------------------------------------------------------ instruments

## The DJ's desk (#104: glowing buttons and two glowing circles), in front of the
## DJ standing at `at`.
func dj_desk(at: Transform3D) -> Node3D:
	var root := _group("DjDesk", at)
	var jazz := style == "jazz"
	var body_mat: Material = ClubTextures.wood(Color("#4a2a18"), 0.12) if jazz else ClubTextures.brushed(Color("#1a1a1e"), 0.6)
	var top_mat: Material = ClubTextures.brushed(Color("#3a3a3e") if jazz else Color("#26262a"), 0.7)
	var trim: Material = ClubTextures.brushed(Color("#b08e50"), 0.9) if jazz else ClubTextures.glow(Color("#ff2bd6"), 2.5)
	var y := ClubMoves.DJ_TOP
	var z := ClubMoves.DJ_Z + 0.06
	var w := ClubMoves.DJ_DECK_X * 2.0 + 0.5
	_box(root, Vector3(w, y - 0.04, 0.6), Vector3(0, (y - 0.04) * 0.5, z), body_mat)
	_box(root, Vector3(w + 0.06, 0.04, 0.66), Vector3(0, y - 0.02, z), top_mat)
	_box(root, Vector3(w + 0.08, 0.03, 0.03), Vector3(0, y - 0.02, z + 0.34), trim)
	_box(root, Vector3(w + 0.08, 0.03, 0.03), Vector3(0, y - 0.02, z - 0.34), trim)
	# The audience side: a lit panel and a strip of LEDs that run with the beat.
	var face := ClubTextures.glow(Color("#c8601c") if jazz else Color("#1a8cff"), 0.5)
	face.albedo_color = Color("#1a0c06") if jazz else Color("#040c18")
	_box(root, Vector3(w - 0.2, 0.36, 0.02), Vector3(0, y * 0.55, z + 0.31), face)
	pulses.append([face, 0.15, 0.9, 1.0, 0.0])
	var n := 12
	for i in n:
		var led := ClubTextures.glow(Color.from_hsv(float(i) / n, 0.7, 1.0), 1.0)
		_box(root, Vector3(0.05, 0.05, 0.02), Vector3(-w * 0.4 + w * 0.8 * i / (n - 1), y * 0.85, z + 0.31), led)
		pulses.append([led, 0.2, 3.5, 2.0, float(i) / n])
	# Two decks, each a glowing ring round a spinning record.
	for side in [-1.0, 1.0]:
		var c := Vector3(side * ClubMoves.DJ_DECK_X, y, ClubMoves.DJ_Z)
		_box(root, Vector3(0.36, 0.03, 0.34), c + Vector3(0, 0.015, 0), ClubTextures.brushed(Color("#2a2a2e"), 0.7))
		var ring := ClubTextures.glow(Color("#3fe8ff") if side > 0 else Color("#ff6a2b"), 3.0)
		_cyl(root, 0.155, 0.012, c + Vector3(0, 0.034, 0), ring)
		pulses.append([ring, 1.6, 4.5, 1.0, 0.5 if side > 0 else 0.0])
		var platter := Node3D.new()
		platter.position = c + Vector3(0, 0.042, 0)
		root.add_child(platter)
		_cyl(platter, 0.142, 0.008, Vector3.ZERO, _flat(Color("#0c0c0e"), 0.25))
		_cyl(platter, 0.045, 0.01, Vector3.ZERO, _flat(Color("#c9a058") if side > 0 else Color("#a8322a"), 0.6))
		_box(platter, Vector3(0.012, 0.012, 0.09), Vector3(0.0, 0.006, 0.08), _flat(Color("#e8dcc0"), 0.6))
		spins.append([platter, 3.5])
		_cyl(root, 0.012, 0.06, c + Vector3(-0.15 * side, 0.06, -0.12), _flat(Color("#c0c0c4"), 0.3, 0.9))
		var arm := _box(root, Vector3(0.015, 0.012, 0.2), c + Vector3(-0.12 * side, 0.08, -0.04), _flat(Color("#c0c0c4"), 0.3, 0.9))
		arm.rotation.y = 0.35 * side
	# The mixer between them: faders, knobs and a grid of glowing buttons.
	var mx := Vector3(0, y, ClubMoves.DJ_Z - 0.04)
	_box(root, Vector3(0.24, 0.05, 0.32), mx + Vector3(0, 0.025, 0), _flat(Color("#141416"), 0.5, 0.3))
	for i in 4:
		_box(root, Vector3(0.012, 0.012, 0.09), mx + Vector3(-0.08 + i * 0.053, 0.055, -0.08), _flat(Color("#2a2a2a"), 0.6))
		_box(root, Vector3(0.03, 0.02, 0.016), mx + Vector3(-0.08 + i * 0.053, 0.066, -0.08 + 0.02 * (i % 3)), _flat(Color("#e8e8ea"), 0.4))
		for k in 3:
			_cyl(root, 0.012, 0.018, mx + Vector3(-0.08 + i * 0.053, 0.06, 0.0 + k * 0.045), _flat(Color("#d8d8dc"), 0.4, 0.4))
	var palette := [Color("#ff3a8c"), Color("#3fe8ff"), Color("#ffcc33"), Color("#7aff5a")]
	for gx in 4:
		for gz in 2:
			var b := ClubTextures.glow(palette[(gx + gz) % palette.size()], 2.0)
			_box(root, Vector3(0.03, 0.012, 0.03), mx + Vector3(-0.08 + gx * 0.053, 0.056, 0.1 + gz * 0.04), b)
			pulses.append([b, 0.4, 4.0, 1.0 if gz == 0 else 0.5, float(gx) * 0.25])
	# A laptop on the right wing, its screen lit.
	var lap := _group("Laptop", Transform3D(Basis(Vector3.UP, 0.3), Vector3(-ClubMoves.DJ_DECK_X - 0.12, y, ClubMoves.DJ_Z + 0.16)), root)
	_box(lap, Vector3(0.3, 0.015, 0.21), Vector3(0, 0.008, 0), _flat(Color("#9a9ca0"), 0.35, 0.8))
	var screen := _box(lap, Vector3(0.3, 0.2, 0.01), Vector3(0, 0.11, 0.1), ClubTextures.glow(Color("#6ab0ff"), 1.4))
	screen.rotation.x = -0.25
	return root


## The techno drum kit in front of the drummer standing at `at`, all hologram:
## a projector puck on the floor throws up a cone of light, and in it float three
## hexagonal pads (the snare in the middle, a tom either side), two cymbal discs
## up high and a kick panel low down. Each is a see-through glowing fill inside a
## bright outline; on its hit it flares and swells, then fades back.
func drum_kit(at: Transform3D) -> Node3D:
	var root := _group("DrumKit", at)
	var z := ClubMoves.DRUM_Z
	var hues := [Color("#3fe8ff"), Color("#ff3a8c"), Color("#ffb040")] if style == "jazz" else [Color("#2bd9ff"), Color("#ff2bd6"), Color("#7aff5a")]
	# The projector: a black puck with a lit ring, and its cone of light.
	_cyl(root, 0.26, 0.06, Vector3(0, 0.03, z + 0.05), _flat(Color("#0e0e10"), 0.3, 0.5))
	var ring := ClubTextures.glow(hues[0], 3.0)
	var rm := TorusMesh.new()
	rm.inner_radius = 0.22
	rm.outer_radius = 0.24
	_put(root, rm, Vector3(0, 0.062, z + 0.05), ring)
	pulses.append([ring, 1.5, 5.0, 1.0, 0.0])
	var cone_m := CylinderMesh.new()
	cone_m.top_radius = 0.62
	cone_m.bottom_radius = 0.2
	cone_m.height = ClubMoves.DRUM_CYM_Y
	cone_m.cap_top = false
	cone_m.cap_bottom = false
	cone_m.radial_segments = 24
	var cone_mat := ClubTextures.beam(hues[0], 0.05)
	_put(root, cone_m, Vector3(0, 0.06 + ClubMoves.DRUM_CYM_Y * 0.5, z + 0.05), cone_mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fades.append([cone_mat, 0.03, 0.09, 1.0, 0.0])
	# The pads, tilted toward the drummer.
	var pads := [[Vector3(0, ClubMoves.DRUM_PAD_Y, z), 0.17, hues[0], 0.0, 6], [Vector3(ClubMoves.DRUM_TOM_X, ClubMoves.DRUM_TOM_Y, z + 0.06), 0.14, hues[1], 0.0, 6],
		[Vector3(-ClubMoves.DRUM_TOM_X, ClubMoves.DRUM_TOM_Y, z + 0.06), 0.14, hues[1], 0.5, 6],
		[Vector3(-ClubMoves.DRUM_CYM_X, ClubMoves.DRUM_CYM_Y, z + 0.1), 0.2, hues[2], 0.0, 24], [Vector3(ClubMoves.DRUM_CYM_X, ClubMoves.DRUM_CYM_Y, z + 0.1), 0.18, hues[2], 0.5, 24]]
	for p in pads:
		var c: Vector3 = p[0]
		var tilt := -22.0 if int(p[4]) == 6 else -14.0
		_holo_pad(root, c, float(p[1]), p[2], float(p[3]), int(p[4]), tilt, 0.5 if int(p[4]) == 24 else 1.0)
	# The kick: an upright panel low in front, flaring on every beat.
	_holo_pad(root, Vector3(0.0, 0.3, z + 0.18), 0.16, hues[0], 0.0, 6, -90.0, 1.0)
	return root


## One hologram pad on `parent` at `c`: a see-through glowing fill (`sides` sides,
## 6 a hex, more a disc) inside a bright outline and a fainter inner one, tilted
## `tilt` degrees toward the drummer. It flares and swells once every `beats`
## beats, `phase` of a beat late.
func _holo_pad(parent: Node3D, c: Vector3, r: float, hue: Color, phase: float, sides: int, tilt: float, beats: float) -> void:
	var pad := Node3D.new()
	pad.position = c
	pad.rotation_degrees.x = tilt
	parent.add_child(pad)
	var fill := ClubTextures.beam(hue, 0.18)
	var fm := CylinderMesh.new()
	fm.top_radius = r
	fm.bottom_radius = r
	fm.height = 0.008
	fm.radial_segments = sides
	_put(pad, fm, Vector3.ZERO, fill).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fades.append([fill, 0.1, 0.55, beats, phase])
	var edge := ClubTextures.glow(hue, 4.0)
	pulses.append([edge, 2.0, 9.0, beats, phase])
	for ring_r in [r, r * 0.55]:
		var ring := edge if ring_r == r else ClubTextures.glow(hue, 2.0)
		if ring_r != r:
			pulses.append([ring, 0.6, 5.0, beats, phase])
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			_rod(pad, Vector3(cos(a0) * ring_r, 0, sin(a0) * ring_r), Vector3(cos(a1) * ring_r, 0, sin(a1) * ring_r), 0.005 if ring_r == r else 0.003, ring)
	pops.append([pad, 0.12, beats, phase])


## Two drumsticks, one in each of a drummer's hands (`joints` of their body).
static func sticks(joints: Dictionary) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#d8b888")
	wood.roughness = 0.5
	for side in ["l", "r"]:
		var wrist := joints.get(side + "_wrist") as Node3D
		if wrist == null:
			continue
		var stick := MeshInstance3D.new()
		stick.name = "Stick"
		var m := CylinderMesh.new()
		m.top_radius = 0.007
		m.bottom_radius = 0.011
		m.height = ClubMoves.STICK
		m.radial_segments = 8
		stick.mesh = m
		stick.material_override = wood
		wrist.add_child(stick)
		# Gripped in the fist, running on past the knuckles and dipping down toward
		# the pads (the wrist's -Y runs along the hand, -Z is down when it is level).
		var dir := Vector3(0.0, -0.8, -0.6)
		stick.position = Vector3(0.0, -0.09, 0.0) + dir * ClubMoves.STICK * 0.4
		stick.rotation_degrees = Vector3(rad_to_deg(atan2(0.6, 0.8)), 0.0, 0.0)


## The upright bass, standing in front of the player at `at`, its strings facing
## out (ClubMoves.bass_axis). Its strings are lasers.
func upright_bass(at: Transform3D) -> Node3D:
	var root := _group("UprightBass", at)
	var axis := Node3D.new()
	axis.name = "Axis"
	axis.position = Vector3(ClubMoves.BASS_X, 0, ClubMoves.BASS_Z)
	axis.rotation_degrees.x = -ClubMoves.BASS_TILT
	root.add_child(axis)
	var varnish := StandardMaterial3D.new()     # gloss black lacquer
	varnish.albedo_color = Color("#0c0c0e")
	varnish.roughness = 0.18
	varnish.metallic = 0.2
	varnish.clearcoat_enabled = true
	varnish.clearcoat = 1.0
	var dark := _flat(Color("#120c08"), 0.4)
	_cyl(axis, 0.01, 0.16, Vector3(0, 0.08, 0), ClubTextures.brushed(Color("#a0a0a4")))
	# The body: the bass's outline (wide lower bout, pinched waist, narrower
	# upper bout, sloped shoulders) as a slab with bevelled edges.
	_put(axis, _bass_body(0.24), Vector3.ZERO, varnish)
	# The front: a black fingerboard up the neck, f-holes, bridge and four strings.
	_box(axis, Vector3(0.06, 0.66, 0.05), Vector3(0, 1.38, 0.02), varnish)
	_box(axis, Vector3(0.05, 0.84, 0.015), Vector3(0, 1.22, 0.06), dark)
	for side in [-1.0, 1.0]:
		var f := _box(axis, Vector3(0.012, 0.16, 0.01), Vector3(side * 0.1, 0.62, 0.125), dark)
		f.rotation.z = side * 0.15
	_box(axis, Vector3(0.12, 0.07, 0.012), Vector3(0, 0.56, 0.13), _flat(Color("#2a2a2e"), 0.4, 0.6))
	_box(axis, Vector3(0.09, 0.2, 0.012), Vector3(0, 0.34, 0.125), dark)
	# Laser strings: four beams from the tailpiece to the nut, each with a soft
	# halo, flaring as they are played and cycling through the colours; a lit
	# emitter at each end.
	var laser := Color("#ff2a3a")
	for k in 4:
		var x := -0.024 + k * 0.016
		var a := Vector3(x, 0.34, 0.138)
		var b := Vector3(x, 1.64, 0.072)
		var core := ClubTextures.glow(laser.lightened(0.5), 6.0)
		_rod(axis, a, b, 0.0022, core)
		var halo := _rod(axis, a, b, 0.009, ClubTextures.beam(laser, 0.35))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pulses.append([core, 4.0, 14.0, 0.5, float(k) * 0.25])
		cycles.append([core, 0.08, float(k) * 0.06])
		cycles.append([halo.material_override, 0.08, float(k) * 0.06])
	var emitter := ClubTextures.glow(laser, 4.0)
	cycles.append([emitter, 0.08, 0.0])
	_box(axis, Vector3(0.08, 0.025, 0.02), Vector3(0, 0.34, 0.14), emitter)
	_box(axis, Vector3(0.07, 0.02, 0.02), Vector3(0, 1.64, 0.075), emitter)
	var glow := OmniLight3D.new()
	glow.light_color = laser
	glow.light_energy = 0.6
	glow.omni_range = 1.6
	glow.shadow_enabled = false
	glow.position = Vector3(0, 1.0, 0.2)
	axis.add_child(glow)
	cycles.append([glow, 0.08, 0.1])
	# The scroll and pegs at the top.
	_box(axis, Vector3(0.05, 0.14, 0.06), Vector3(0, ClubMoves.BASS_HEIGHT - 0.1, 0.0), varnish)
	_sphere(axis, 0.04, Vector3(0, ClubMoves.BASS_HEIGHT - 0.02, 0.02), varnish)
	for k in 4:
		_cyl(axis, 0.008, 0.12, Vector3(0, ClubMoves.BASS_HEIGHT - 0.16 + k * 0.03, 0.0), ClubTextures.brushed(Color("#c9a058")), Vector3(0, 0, 90))
	return root


## The bass's body: its outline, half-width by height up the axis, extruded
## `depth` deep (front at +Z), the front and back each a bevel's width in from
## the ribs so the edges round off.
static func _bass_body(depth: float) -> ArrayMesh:
	var keys := [[0.07, 0.0], [0.1, 0.2], [0.2, 0.29], [0.42, 0.34], [0.6, 0.29], [0.72, 0.2],
		[0.8, 0.21], [0.95, 0.25], [1.07, 0.18], [1.14, 0.07], [1.16, 0.0]]
	var rows: Array = []        ## [h, half-width]
	for k in keys.size() - 1:
		for s in 6:
			var u := float(s) / 6.0
			var a: Array = keys[k]
			var b: Array = keys[k + 1]
			var uu := u * u * (3.0 - 2.0 * u)
			rows.append([lerpf(a[0], b[0], u), lerpf(a[1], b[1], uu)])
	rows.append(keys.back())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := depth * 0.5
	var bevel := 0.035
	# Each row is a ring of 8 points: front face corners in by the bevel, the rib
	# at full width, the back face in by the bevel (left and right).
	var ring := func(h: float, w: float) -> Array:
		var wi := maxf(0.0, w - bevel)
		return [Vector3(-wi, h, half), Vector3(-w, h, half - bevel), Vector3(-w, h, -half + bevel), Vector3(-wi, h, -half),
			Vector3(wi, h, -half), Vector3(w, h, -half + bevel), Vector3(w, h, half - bevel), Vector3(wi, h, half)]
	for r in rows.size() - 1:
		var a: Array = ring.call(float(rows[r][0]), float(rows[r][1]))
		var b: Array = ring.call(float(rows[r + 1][0]), float(rows[r + 1][1]))
		for i in 8:
			var j := (i + 1) % 8
			st.add_vertex(a[i]); st.add_vertex(b[i]); st.add_vertex(b[j])
			st.add_vertex(a[i]); st.add_vertex(b[j]); st.add_vertex(a[j])
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ the room

## A round table: a dark top, a brass pedestal, a candle and two glasses.
func cocktail_table(pos: Vector3, r := 0.42, h := 0.78, candle := true) -> Node3D:
	var root := _group("ClubTable", Transform3D(Basis.IDENTITY, pos))
	_cyl(root, r, 0.04, Vector3(0, h - 0.02, 0), ClubTextures.wood(Color("#2e1a10"), 0.1, 0.35))
	_cyl(root, r + 0.01, 0.015, Vector3(0, h - 0.045, 0), ClubTextures.brushed(Color("#b08e50"), 0.9))
	_cyl(root, 0.035, h - 0.06, Vector3(0, (h - 0.06) * 0.5, 0), ClubTextures.brushed(Color("#b08e50"), 0.9))
	_cyl(root, r * 0.55, 0.03, Vector3(0, 0.015, 0), ClubTextures.brushed(Color("#2a2420"), 0.8))
	if candle:
		self.candle(root, Vector3(0, h, 0))
	for k in 2:
		var a := 1.2 + k * 2.4
		_glass(root, Vector3(cos(a) * r * 0.55, h, sin(a) * r * 0.55), [Color("#c98a3a"), Color("#3f8f8a")][k])
	return root


## A candle in a red glass on `parent` at `at`, with a small flickering light.
func candle(parent: Node3D, at: Vector3) -> void:
	var cup := StandardMaterial3D.new()
	cup.albedo_color = Color(0.7, 0.12, 0.1, 0.55)
	cup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cup.emission_enabled = true
	cup.emission = Color("#ff6a2b")
	cup.emission_energy_multiplier = 1.4
	cup.roughness = 0.1
	_cyl(parent, 0.04, 0.08, at + Vector3(0, 0.04, 0), cup)
	var flame := ClubTextures.glow(Color("#ffb060"), 6.0)
	_sphere(parent, 0.012, at + Vector3(0, 0.085, 0), flame).scale = Vector3(1, 1.8, 1)
	var l := OmniLight3D.new()
	l.light_color = Color("#ff9a4a")
	l.light_energy = 0.5
	l.omni_range = 2.2
	l.shadow_enabled = false
	l.position = at + Vector3(0, 0.15, 0)
	parent.add_child(l)
	lights.append([l, 0.4, 0.6, 0.37, randf()])


## A leather booth along a wall: a tufted back and seat on a wooden plinth,
## `length` metres long, its back on the wall. `at` faces into the room (+Z).
func booth(at: Transform3D, length: float, tint := Color("#5a1e1a")) -> Node3D:
	var root := _group("Booth", at)
	var leather := ClubTextures.leather(tint)
	_box(root, Vector3(length, 0.28, 0.62), Vector3(0, 0.14, 0.31), ClubTextures.wood(Color("#2e1a10"), 0.12))
	_box(root, Vector3(length, 0.16, 0.58), Vector3(0, 0.36, 0.33), leather)
	_box(root, Vector3(length, 0.72, 0.16), Vector3(0, 0.8, 0.08), leather)
	_box(root, Vector3(length + 0.04, 0.05, 0.2), Vector3(0, 1.18, 0.08), ClubTextures.brushed(Color("#b08e50"), 0.9))
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.08, 0.7, 0.62), Vector3(side * (length * 0.5 + 0.04), 0.35, 0.31), ClubTextures.wood(Color("#2e1a10"), 0.12))
	return root


## A speaker cabinet `size` (w, h, d), its grille facing +Z of `at`, two cones that
## throb on the beat.
func speaker(at: Transform3D, size := Vector3(0.7, 1.2, 0.6)) -> Node3D:
	var root := _group("Speaker", at)
	var case_mat: Material = ClubTextures.wood(Color("#1e1612"), 0.2) if style == "jazz" else ClubTextures.brushed(Color("#18181a"), 0.4)
	_box(root, size, Vector3(0, size.y * 0.5, 0), case_mat)
	_box(root, Vector3(size.x - 0.06, size.y - 0.06, 0.02), Vector3(0, size.y * 0.5, size.z * 0.5), ClubTextures.grille())
	var cones := [[size.x * 0.36, size.y * 0.32], [size.x * 0.2, size.y * 0.75]]
	for c in cones:
		var holder := Node3D.new()
		holder.position = Vector3(0, float(c[1]), size.z * 0.5 + 0.012)
		holder.rotation_degrees.x = 90.0
		root.add_child(holder)
		_cyl(holder, float(c[0]) + 0.02, 0.01, Vector3.ZERO, ClubTextures.brushed(Color("#4a4a4e"), 0.8))
		var cone := Node3D.new()
		holder.add_child(cone)
		_cone(cone, float(c[0]) * 0.25, float(c[0]), 0.03, Vector3(0, 0.02, 0), _flat(Color("#141414"), 0.7))
		_cyl(cone, float(c[0]) * 0.22, 0.02, Vector3(0, 0.04, 0), _flat(Color("#2a2a2c"), 0.4))
		throbs.append([cone, 1.4, 0.0])
	if style == "rave":
		var edge := ClubTextures.glow(Color("#2bd9ff"), 2.0)
		_box(root, Vector3(size.x, 0.02, 0.02), Vector3(0, size.y - 0.01, size.z * 0.5 + 0.01), edge)
		pulses.append([edge, 0.5, 4.0, 1.0, 0.0])
	return root


## A stage spot hung at `from`, aimed at `to`: a can, a spot light, and a soft
## cone of light through the haze. `sweep` degrees it swings back and forth.
func spot(from: Vector3, to: Vector3, color: Color, energy := 6.0, sweep := 0.0, beam := true) -> SpotLight3D:
	var pivot := Node3D.new()
	pivot.name = "Spot"
	add_child(pivot)
	pivot.transform = Transform3D(Basis.looking_at(to - from, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.FORWARD), from)
	var can := _cyl(pivot, 0.12, 0.3, Vector3(0, 0, 0.0), ClubTextures.brushed(Color("#1a1a1c"), 0.6), Vector3(90, 0, 0))
	can.name = "Can"
	_cyl(pivot, 0.1, 0.01, Vector3(0, 0, -0.155), ClubTextures.glow(color, 4.0), Vector3(90, 0, 0))
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	var reach := from.distance_to(to)
	l.spot_range = reach * 1.6
	l.spot_angle = 18.0
	l.spot_attenuation = 0.6
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 2.0
	pivot.add_child(l)
	if beam:
		var length := reach * 0.95
		var cone := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.08
		m.bottom_radius = tan(deg_to_rad(l.spot_angle)) * length
		m.height = length
		m.radial_segments = 20
		m.cap_top = false
		m.cap_bottom = false
		cone.mesh = m
		cone.material_override = ClubTextures.beam(color, beam_alpha)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.rotation_degrees.x = 90.0
		cone.position = Vector3(0, 0, -length * 0.5)
		pivot.add_child(cone)
	if sweep > 0.0:
		sweeps.append([pivot, pivot.basis, Vector3.UP, sweep, randf_range(5.0, 8.0), randf()])
	return l


## A neon tube along `points` (a loop if `closed`), glowing `color`, with a light
## at its middle so it colours the wall behind it.
func neon(points: PackedVector3Array, color: Color, closed := false, radius := 0.022, energy := 5.0) -> void:
	var glow := ClubTextures.glow(color, energy)
	var n := points.size() if closed else points.size() - 1
	var mid := Vector3.ZERO
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		_rod(self, a, b, radius, glow)
		mid += a
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.shadow_enabled = false
	l.position = mid / maxf(1.0, n)
	add_child(l)


## A mirror ball hung from `ceiling` at `pos`, turning slowly, with a few specks of
## light thrown round the room.
## Issue #392: a laser droid's fan of beams, built into `parent` (its emitter
## hangs at parent's origin; +Z of `face` is straight ahead), sweeping and
## fading on this props' clock: the stage's droid (ClubDressing) and a floating
## droid of yours with the laser rig (DroidController). `o` (all optional):
## beams (per two tiers), tiers [tilt, tilt] (below level, the first dips more),
## spread (radians either side), length (m), sweep_deg, sweep_s, colors.
func laser_fan(parent: Node3D, face: Basis, o: Dictionary = {}) -> void:
	var n := int(o.get("beams", 18))
	var per := maxi(1, n / 2)
	var tiers: Array = o.get("tiers", [-0.32, -0.13])
	var spread := float(o.get("spread", 0.75))
	var length := float(o.get("length", 34.0))
	var cols: Array = o.get("colors", ["#3aff4a", "#ff2a3a", "#2bd9ff"])
	for i in n:
		var a := lerpf(-spread, spread, (i % per) / float(maxi(per - 1, 1)))
		var tilt := float(tiers[0] if i < per else tiers[mini(1, tiers.size() - 1)])
		var dir := (face * Vector3(sin(a), tilt, cos(a))).normalized()
		var beam := Node3D.new()
		parent.add_child(beam)
		beam.basis = Basis.looking_at(dir, Vector3.UP)
		var col := Color(str(cols[i % cols.size()]))
		var core := _cyl(beam, 0.01, length, Vector3(0, 0, -length * 0.5), ClubTextures.glow(col, 7.0), Vector3(90, 0, 0))
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var halo := _cyl(beam, 0.04, length, Vector3(0, 0, -length * 0.5), ClubTextures.beam(col, 0.2), Vector3(90, 0, 0))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fades.append([halo.material_override, 0.05, 0.3, 0.5, i * 0.11])
		sweeps.append([beam, beam.basis, Vector3.UP, float(o.get("sweep_deg", 18.0)), float(o.get("sweep_s", 3.2)), i * 0.07])
	var lens := ClubTextures.glow(Color(str(cols[0])), 6.0)
	_sphere(parent, 0.09, Vector3.ZERO, lens)
	cycles.append([lens, 0.2, 0.0])


func mirror_ball(pos: Vector3, ceiling: float, r := 0.35) -> void:
	_rod(self, pos + Vector3(0, r, 0), Vector3(pos.x, ceiling, pos.z), 0.01, _flat(Color("#808084"), 0.4, 0.8))
	var ball := Node3D.new()
	ball.position = pos
	add_child(ball)
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color("#d0d4dc")
	mirror.metallic = 1.0
	mirror.roughness = 0.05
	_sphere(ball, r, Vector3.ZERO, mirror)
	var facets := 18
	for k in facets:
		var a := TAU * k / facets
		for rk in 4:
			var e := -0.9 + rk * 0.6
			var d := Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e))
			var tile := _box(ball, Vector3(0.06, 0.06, 0.005), d * (r + 0.002), mirror)
			tile.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)
	spins.append([ball, 0.4])


# ------------------------------------------------------------------ shapes

func _group(n: String, at: Transform3D, parent: Node3D = null) -> Node3D:
	var g := Node3D.new()
	g.name = n
	g.transform = at
	(parent if parent != null else self).add_child(g)
	return g


func _flat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _put(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _put(parent, b, pos, mat)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	return _cone(parent, r, r, h, pos, mat, rot)


func _cone(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 20
	return _put(parent, c, pos, mat, rot)


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	return _put(parent, s, pos, mat)


## A rod from `a` to `b`.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := _cyl(parent, r, a.distance_to(b), (a + b) * 0.5, mat)
	var d := (b - a).normalized()
	if absf(d.dot(Vector3.UP)) < 0.999:
		var x := Vector3.UP.cross(d).normalized()
		mi.basis = Basis(x, d, x.cross(d))
	return mi


func _glass(parent: Node3D, at: Vector3, drink: Color) -> void:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.9, 0.95, 1.0, 0.25)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.roughness = 0.05
	_cone(parent, 0.035, 0.028, 0.1, at + Vector3(0, 0.05, 0), g)
	var d := StandardMaterial3D.new()
	d.albedo_color = Color(drink.r, drink.g, drink.b, 0.8)
	d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	d.emission_enabled = true
	d.emission = drink
	d.emission_energy_multiplier = 0.4
	_cone(parent, 0.03, 0.026, 0.055, at + Vector3(0, 0.03, 0), d)
