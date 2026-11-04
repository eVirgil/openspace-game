class_name AsteroidSphere
extends PlanetSphere
## The asteroid as a real ball (issue #99), the same kind of ball as the home
## planet (PlanetSphere, issue #77): the town sits on a flat plateau on top, the
## ground follows the ball all the way round, "up" turns with it, and one height
## function feeds the rock you see, the collider you stand on and the ships'
## ground. Only the open ground differs: grey rock instead of dunes, pocked with
## craters of three sizes (a fixed, seeded set spread over the whole ball, so they
## wrap it with no seam) on a rough, slow swell.
##
## Settings: the asteroid type's "surface" in content/core/planets/types.json.

var craters: Array = []        ## per layer: { cell: float, grid: { Vector3i: [[x, y, z, r], ...] }, depth, reach }
var bumps := 1.2
var swell := 6.0
## Issue #272: the surface's "lava" block ({} = no lava): the low ground under
## lava_level() is molten, except within keep_clear metres of the port.
var lava: Dictionary = {}
var _lava_level := NAN

const LAVA_SAMPLES := 1500     ## directions over the whole ball, for the lava level
const LAVA_MARGIN := 20.0      ## metres past keep_clear before the lava is full (the shader's fade)


func _init(r: float = 1500.0, surface: Dictionary = {}) -> void:
	super._init(r)
	_swell.seed = 99
	_small.seed = 199
	flat_radius = float(surface.get("flat_radius", 130.0))
	up_blend = float(surface.get("up_blend", 160.0))
	bumps = float(surface.get("bumps", bumps))
	swell = float(surface.get("swell", swell))
	var lv = surface.get("lava", {})
	lava = lv if lv is Dictionary else {}
	_scatter(surface.get("craters", []))


## Seat the town: as PlanetSphere, with the asteroid's own (much shorter) blend
## from the station's floors to open rock. Outside the walls the hallway's and
## the pit ring's decks are slabs laid on the rock, so the rock sits DECK_CLEAR
## under them (level with them it showed through). The pit's dip ends under its
## deck ring: the near mesh widens it 4 m past the pit floor (the collider's
## grow), and with 1 m of ramp it stays inside the 6 m ring instead of opening a
## trench along the ring's outer edge.
const DECK_CLEAR := 0.12


func configure_site(floor_rect: Rect2, walls_rect: Rect2, sunken: Array, floor_y: float = 0.0) -> void:
	super.configure_site(floor_rect, walls_rect, sunken, floor_y - DECK_CLEAR)
	pad_margin = 10.0
	blend = 70.0
	dune_offset = 1.5
	sink_ramp = 1.0
	_lava_level = NAN


# ---------------------------------------------------------------- lava (issue #272)

func has_lava() -> bool:
	return not lava.is_empty()


## No lava this close to the port (metres along the ground): the station, its
## hallway and the landing pit stand on dry rock.
func lava_keep_clear() -> float:
	return float(lava.get("keep_clear", flat_radius))


## The height (metres above the bare ball) the lava fills up to: the open ground
## below it is lava.cover of the whole ball's open ground, measured once over a
## fixed spread of directions, so it follows the rock whatever its numbers are.
func lava_level() -> float:
	if not has_lava():
		return -INF
	if not is_nan(_lava_level):
		return _lava_level
	var hs := PackedFloat32Array()
	var golden := PI * (3.0 - sqrt(5.0))
	var open_from := flat_radius + up_blend
	for i in LAVA_SAMPLES:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(LAVA_SAMPLES)
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var a := golden * float(i)
		var dir := Vector3(cos(a) * ring, y, sin(a) * ring)
		if dir_map(dir).length() < open_from:
			continue
		hs.append(elevation(dir))
	hs.sort()
	var cover := clampf(float(lava.get("cover", 0.35)), 0.0, 1.0)
	_lava_level = hs[clampi(int(hs.size() * cover), 0, hs.size() - 1)] if hs.size() > 0 else 0.0
	return _lava_level


## Is a world point (the planet's own scene) touching the lava: at or below its
## level, where the lava is full (past keep_clear and the fade after it)?
func in_lava(p: Vector3, margin: float = 0.05) -> bool:
	if not has_lava():
		return false
	if world_to_map(p).length() < lava_keep_clear() + LAVA_MARGIN:
		return false
	return (p - center).length() - radius <= lava_level() + margin


## Every crater, once: `count` of them per layer at random spots on the ball,
## filed in a 3D grid: each crater in every cell its reach touches, so a point
## asks one cell per layer (the near collider asks a lot).
func _scatter(layers: Array) -> void:
	craters = []
	for L in layers:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(L.get("seed", 1))
		var rr: Array = L.get("radius", [10.0, 20.0])
		var reach := float(rr[1]) * 1.6
		var cell := maxf(reach * 2.0, 1.0)
		var grid := {}
		for i in int(L.get("count", 100)):
			var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			var c := d * radius
			var r := lerpf(float(rr[0]), float(rr[1]), pow(rng.randf(), 1.6))
			var e := r * 1.6
			for ix in range(floori((c.x - e) / cell), floori((c.x + e) / cell) + 1):
				for iy in range(floori((c.y - e) / cell), floori((c.y + e) / cell) + 1):
					for iz in range(floori((c.z - e) / cell), floori((c.z + e) / cell) + 1):
						var k := Vector3i(ix, iy, iz)
						if not grid.has(k):
							grid[k] = []
						(grid[k] as Array).append([c.x, c.y, c.z, r])
		craters.append({ "cell": cell, "grid": grid, "depth": float(L.get("depth", 0.22)), "reach": reach })


## The open rock at a point on the bare ball (metres above it).
func _dunes(p: Vector3) -> float:
	var h := 0.0
	for L in craters:
		h += _crater_layer(p, L)
	h += _swell.get_noise_3d(p.x * 0.004, p.y * 0.004, p.z * 0.004) * swell
	h += _small.get_noise_3d(p.x * 0.035, p.y * 0.035, p.z * 0.035) * bumps
	return h


## Sum of one layer's craters round p: a bowl with a raised rim each.
func _crater_layer(p: Vector3, L: Dictionary) -> float:
	var cell: float = L.cell
	var list = (L.grid as Dictionary).get(Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell)))
	if list == null:
		return 0.0
	var depth_k: float = L.depth
	var h := 0.0
	for c in list:
		var r: float = c[3]
		var dx: float = p.x - c[0]
		var dy: float = p.y - c[1]
		var dz: float = p.z - c[2]
		var d2 := dx * dx + dy * dy + dz * dz
		if d2 >= r * r * 2.56:
			continue
		var d := sqrt(d2) / r
		var depth := r * depth_k
		if d < 1.0:
			h += depth * (d * d - 1.0) + depth * 0.3 * d * d * d * d
		else:
			var t := 1.0 - (d - 1.0) / 0.6
			h += depth * 0.3 * t * t
	return h
