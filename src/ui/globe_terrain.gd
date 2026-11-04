class_name GlobeTerrain
extends RefCounted
## The ground under the F11 Map page's globe (GlobeView): the ball's own heights
## (PlanetSphere.elevation, the one function the sand you walk on comes from, so
## the asteroid's craters too) baked once a planet into a small texture, which
## globe_ground.gdshader lights and lays faintly under the globe's grid. Mesas
## (DesertLandforms.mesa_spots) are pressed in as rock the height they stand.
## On the lava moon (AsteroidSphere.has_lava) the "rock" is the lava instead: the
## open ground under its level, as AsteroidSphere.in_lava has it, which the
## planet's terrain look (GlobeMap.terrain_look) paints molten.
##
## The texture is latitude/longitude round the map frame's own axis (GlobeMap.dir:
## the port at +Y, the top row): u = atan2(x, z) / TAU + 0.5, v = 0.5 - lat / PI.
## R and G are the ground's slope east and north (0.5 = level, 0 and 1 = SLOPE
## down or up), B the height (0 = the lowest ground on the ball, 1 the highest),
## A rock. The shader lights the slopes from the screen's top left, so the light
## stays put however the globe is turned.
##
## Baked on worker threads, a row a task; `poll` (the globe's _process) moves it on
## and finishes it on the main thread, and the globe draws bare until `texture` is
## ready. One bake a planet a session (`for_sphere`). Size: content/look/map.json
## "terrain".

const SLOPE := 0.6                      ## the steepest slope the texture holds (rise over run)
const LAVA_SOFT := 3.0                  ## m: the lava's shore on the map, from dry to molten
const LAVA_FADE := 250.0                ## m along the ground past the dry ground round the port before the lava shows full

static var _kept := {}                  ## key -> GlobeTerrain

var texture: ImageTexture = null        ## null until the bake is done
var size := Vector2i(1024, 512)

var _sphere: PlanetSphere
var _rocks: Array = []                  ## [{ dir: Vector3, angle: float, height: float }]
var _heights: Array = []                ## per row: PackedFloat32Array, metres
var _cover: Array = []                  ## per row: PackedFloat32Array, rock 0..1
var _texels: Array = []                 ## per row: PackedByteArray, RGBA8
var _range: Array = []                  ## per row: Vector2(lowest, highest) height
var _group := -1
var _stage := 0                         ## 0 heights, 1 texels, 2 done
var _lo := 0.0
var _hi := 1.0
var _lava := -INF                       ## the lava's level (m above the bare ball), -INF = none
var _lava_clear := 0.0                  ## no lava this near the port (m along the ground)


## The bake for this planet (`key`): the one already made or under way, else a new
## one started. `mesas`: DesertLandforms.mesa_spots ({ map, radius, height } each).
static func for_sphere(key: String, sphere: PlanetSphere, mesas: Array = []) -> GlobeTerrain:
	if _kept.has(key):
		return _kept[key]
	var t := GlobeTerrain.new()
	var px: Array = GlobeMap.look().get("terrain", {}).get("size", [1024, 512])
	t.size = Vector2i(int(px[0]), int(px[1]))
	t._sphere = sphere
	if sphere is AsteroidSphere and (sphere as AsteroidSphere).has_lava():
		var a := sphere as AsteroidSphere
		t._lava = a.lava_level()          # worked out here, once, not on the workers
		t._lava_clear = a.lava_keep_clear() + AsteroidSphere.LAVA_MARGIN
	for m in mesas:
		var at: Vector2 = m.map
		t._rocks.append({ "dir": sphere.map_dir(at.x, at.y), "angle": float(m.radius) / sphere.radius, "height": float(m.height) })
	t._heights.resize(t.size.y)
	t._cover.resize(t.size.y)
	t._texels.resize(t.size.y)
	t._range.resize(t.size.y)
	t._group = WorkerThreadPool.add_group_task(t._height_row, t.size.y, -1, false, "globe terrain heights")
	_kept[key] = t
	return t


## Moves every bake still under way on (one for a map you have since left too: its
## worker group has to be waited on). The globe calls it each frame while any is.
static func poll_all() -> void:
	for t: GlobeTerrain in _kept.values():
		t.poll()


## Waits out every bake still under way: the globe leaving the tree (the game
## quitting, the scene going) must not leave worker tasks running GDScript behind
## it, or the engine's shutdown waits on them for ever. At most about a second.
static func finish_all() -> void:
	for t: GlobeTerrain in _kept.values():
		while not t.poll(true):
			pass


## Any bake still under way.
static func busy() -> bool:
	for t: GlobeTerrain in _kept.values():
		if t._stage < 2:
			return true
	return false


## Moves the bake on when its worker tasks are done (`block`: waits for them).
## True once the texture is ready.
func poll(block := false) -> bool:
	if _stage >= 2:
		return true
	if not block and not WorkerThreadPool.is_group_task_completed(_group):
		return false
	WorkerThreadPool.wait_for_group_task_completion(_group)
	if _stage == 0:
		_lo = INF
		_hi = -INF
		for r: Vector2 in _range:
			_lo = minf(_lo, r.x)
			_hi = maxf(_hi, r.y)
		_hi = maxf(_hi, _lo + 1.0)
		_stage = 1
		_group = WorkerThreadPool.add_group_task(_texel_row, size.y, -1, false, "globe terrain texels")
		return false
	var bytes := PackedByteArray()
	for row: PackedByteArray in _texels:
		bytes.append_array(row)
	var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	texture = ImageTexture.create_from_image(img)
	_heights = []
	_cover = []
	_texels = []
	_range = []
	_sphere = null
	_stage = 2
	return true


## The unit direction at texel (i, j)'s centre, in the map frame.
func texel_dir(i: float, j: float) -> Vector3:
	var lon := (i + 0.5) / size.x * TAU - PI
	var lat := PI * 0.5 - (j + 0.5) / size.y * PI
	return Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))


## Row j's heights (metres above the bare ball, mesas standing on them) and rock.
func _height_row(j: int) -> void:
	var row := PackedFloat32Array()
	var cover := PackedFloat32Array()
	row.resize(size.x)
	cover.resize(size.x)
	var lat := PI * 0.5 - (j + 0.5) / size.y * PI
	var lo := INF
	var hi := -INF
	var near: Array = []
	for r in _rocks:
		if absf(asin(clampf((r.dir as Vector3).y, -1.0, 1.0)) - lat) < float(r.angle) * 1.2:
			near.append(r)
	for i in size.x:
		var d := texel_dir(i, j)
		var h := _sphere.elevation(d)
		var c := 0.0
		for r in near:
			var a := d.angle_to(r.dir)
			var ang := float(r.angle)
			if a < ang * 1.15:
				h += float(r.height) * smoothstep(ang, ang * 0.8, a)
				c = maxf(c, smoothstep(ang * 1.15, ang * 0.85, a))
		if _lava > -INF:
			# soft at its shore and faded in past the port's dry ground: the rows
			# bunch up toward the port (the texture's pole), and a hard edge there
			# draws as streaks
			var from := _sphere.dir_map(d).length() - _lava_clear
			c = maxf(c, clampf((_lava - h) / LAVA_SOFT + 0.5, 0.0, 1.0) * clampf(from / LAVA_FADE, 0.0, 1.0))
		row[i] = h
		cover[i] = c
		lo = minf(lo, h)
		hi = maxf(hi, h)
	_heights[j] = row
	_cover[j] = cover
	_range[j] = Vector2(lo, hi)


## Row j's texels: its slopes from the neighbours' heights, its height, its rock.
func _texel_row(j: int) -> void:
	var up: PackedFloat32Array = _heights[maxi(j - 1, 0)]
	var row: PackedFloat32Array = _heights[j]
	var down: PackedFloat32Array = _heights[mini(j + 1, size.y - 1)]
	var cover: PackedFloat32Array = _cover[j] if _lava == -INF else _lava_blur(j)
	var lat := PI * 0.5 - (j + 0.5) / size.y * PI
	var dy := PI / size.y * _sphere.radius * float(mini(j + 1, size.y - 1) - maxi(j - 1, 0))
	var dx := maxf(TAU / size.x * _sphere.radius * cos(lat), 0.01) * 2.0
	var out := PackedByteArray()
	out.resize(size.x * 4)
	for i in size.x:
		var east := (row[(i + 1) % size.x] - row[(i - 1 + size.x) % size.x]) / dx
		var north := (up[i] - down[i]) / dy
		out[i * 4] = _byte(0.5 + 0.5 * east / SLOPE)
		out[i * 4 + 1] = _byte(0.5 + 0.5 * north / SLOPE)
		out[i * 4 + 2] = _byte((row[i] - _lo) / (_hi - _lo))
		out[i * 4 + 3] = _byte(cover[i])
	_texels[j] = out


## Row j's lava, blurred over a texel's height round it in every direction: the
## rows are a fixed distance apart but the columns close up toward the port (the
## pole), where unblurred the lava's speckle would draw as rays out from it.
func _lava_blur(j: int) -> PackedFloat32Array:
	var lat := PI * 0.5 - (j + 0.5) / size.y * PI
	var k := clampi(int(round(1.0 / maxf(cos(lat), 0.0001))), 1, size.x / 4)   # columns a row's height spans
	var out := PackedFloat32Array()
	out.resize(size.x)
	var rows := 0
	for jj in range(maxi(j - 1, 0), mini(j + 2, size.y)):
		var src: PackedFloat32Array = _cover[jj]
		var pre := PackedFloat32Array()        # running sums, so each window is two reads
		pre.resize(size.x + 1)
		for i in size.x:
			pre[i + 1] = pre[i] + src[i]
		var total := pre[size.x]
		for i in size.x:
			var a := i - k
			var b := i + k + 1
			var sum := pre[mini(b, size.x)] - pre[maxi(a, 0)]
			if a < 0:
				sum += total - pre[size.x + a]
			if b > size.x:
				sum += pre[b - size.x]
			out[i] += sum / float(2 * k + 1)
		rows += 1
	for i in size.x:
		out[i] /= float(rows)
	return out


static func _byte(f: float) -> int:
	return int(round(clampf(f, 0.0, 1.0) * 255.0))
