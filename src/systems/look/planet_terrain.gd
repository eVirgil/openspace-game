class_name PlanetTerrain
extends DesertTerrain
## The desert as a whole ball (issue #77): the same jobs as DesertTerrain (the sand
## you see, the ground you stand on, the town seated at floor level) but on a
## PlanetSphere, so the sand goes all the way round and there is no edge to fall
## off. Same public face, so the town, the ship and the traces use it unchanged.
##
## Three layers of sand, all from the sphere's one height function:
##   near -- 256 m square under the player at 1 m: the collider AND a mesh built
##           from the very same heights, so the dunes you see are the dunes you
##           stand on (no sinking into a crest, no floating over a dip).
##   mid  -- 1 km square under the camera at 4 m, mesh only.
##   far  -- the whole ball, a cube sphere at about 40 m, built once.
## Each layer sinks its own sand a few metres wherever the layer inside it covers
## (instance shader parameters), so a coarse crest never pokes through.
##
## near and mid follow (near: `follow`, the player; mid: the camera) and rebuild on
## a worker thread; the new mesh and collider are swapped in whole on one frame.
## `threaded = false` builds on the calling frame instead (tests).

@export var near_cells := 256
@export var near_step := 1.0
@export var near_recenter := 48.0
@export var mid_cells := 256
@export var mid_step := 4.0
@export var mid_recenter := 160.0
@export var fast_mid_cells := 128          ## flight-only mid mesh: one quarter the vertex work
@export var fast_mid_step := 8.0           ## same ~1 km footprint as 256 cells at 4 m
@export var far_chunks := 4             ## per cube face side
@export var far_cells := 64             ## per chunk side; 4 chunks span each face (issue #93)
@export var hole_sink := 6.0            ## metres an outer layer drops under an inner one
@export var far_limb_margin_degrees := 5.0 ## keep a generous angular buffer at the visible limb
@export var far_limb_relief_padding := 100.0 ## extra radial bound for relief not sampled by far vertices
## The town's own collider: a fixed square round the port, built once, so people,
## droids and dropped things anywhere in and around town always have ground under
## them (the near collider only follows the player). Coarser, and a hair lower, so
## wherever the near one is, its exact heights are the ones you stand on.
@export var town_cells := 256
@export var town_step := 2.0
const TOWN_SINK := 0.05
var town_body: StaticBody3D
var threaded := true

var sphere: PlanetSphere
var near_mesh: MeshInstance3D
var mid_mesh: MeshInstance3D
var far_root: Node3D
var far_chunks_culled := 0          ## current-frame count of safely culled far patches
var _far_instances: Array[MeshInstance3D] = []
var _far_chunk_directions: Array[Vector3] = []
var _far_chunk_angles := PackedFloat32Array()
var _far_surface_bound := 0.0
var _with_mesh := true
var _camera_source: Callable = Callable()   ## () -> Vector3, for the mid ring
## In-flight builds: layer -> { task, center: Vector2 (map), result }.
var _jobs := {}
var _pending_jobs := {}                ## latest requested center/resolution per layer
var _near_map := Vector2.INF            ## map centre of the near layer in place
var _mid_map := Vector2.INF
var _fast_flight_quality := false
var perf_far_build_ms := 0.0
var perf_far_worker_wait_ms := 0.0
var perf_mesh_submit_ms := 0.0
var perf_mesh_submit_count := 0
var perf_mesh_upload_worst_frame_ms := 0.0  ## most near/mid upload time spent in one tick
## Issue #123: finished near/mid meshes wait here (latest per layer) and go up at
## least one a tick, more only while under mesh_upload_budget_ms, so a near and a
## mid landing together never stack into one long frame.
@export var mesh_upload_budget_ms := 2.0
var _ready_meshes := {}


func _init() -> void:
	super._init()
	name = "PlanetTerrain"
	sphere = PlanetSphere.new()
	collider_cells = near_cells
	collider_size = near_cells * near_step
	recenter_distance = near_recenter


func set_radius(r: float) -> void:
	sphere.set_radius(r)
	extent = PI * r


## Issue #99: another kind of ball (the asteroid's AsteroidSphere), before build().
func use_sphere(s: PlanetSphere) -> void:
	sphere = s
	extent = PI * s.radius


## Issue #99: rock instead of sand (moon_rock.gdshader), with these colours.
var rock_look := {}
const ROCK_SHADER := preload("res://src/systems/look/shaders/moon_rock.gdshader")
## A gas ball's cloud tops (GasSphere): the ringed giant's banded look
## (gas_giant.gdshader), { color_a, color_b, bands, ring_normal }.
var gas_look := {}
const GAS_SHADER := preload("res://src/systems/look/shaders/gas_giant.gdshader")


## Issue #272: lava in the rock's low ground (lava_rock.gdshader), when the ball's
## surface has a "lava" block (AsteroidSphere.lava).
const LAVA_SHADER := preload("res://src/systems/look/shaders/lava_rock.gdshader")


## A ball type's surface: its rock colours, and its lava if it has any.
func use_surface(surf: Dictionary) -> void:
	rock_look = surf.get("look", {})


## The ground's material for a ball whose centre is at `center` in this scene:
## sand, moon rock, or lava rock (the lava's level and colours from the sphere).
func _ground_material(center: Vector3) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if not gas_look.is_empty():
		m.shader = GAS_SHADER              # a gas ball's cloud tops: the ringed giant's bands
		for k in gas_look:
			m.set_shader_parameter(k, gas_look[k])
		return m
	var lava_sphere: AsteroidSphere = sphere as AsteroidSphere if sphere is AsteroidSphere and (sphere as AsteroidSphere).has_lava() else null
	m.shader = LAVA_SHADER if lava_sphere != null else (SAND_SHADER if rock_look.is_empty() else ROCK_SHADER)
	for k in rock_look:
		m.set_shader_parameter(k, Color(str(rock_look[k])) if rock_look[k] is String else rock_look[k])
	m.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(512, 3, 0.01))
	m.set_shader_parameter("planet_center", center)
	m.set_shader_parameter("planet_radius", sphere.radius)
	if lava_sphere != null:
		var lv: Dictionary = lava_sphere.lava
		for k in ["glow", "hot"]:
			if lv.has(k):
				m.set_shader_parameter(k, Color(str(lv[k])))
		if lv.has("crust"):
			m.set_shader_parameter("crust_color", Color(str(lv.crust)))
		for k in ["glow_energy", "flow_speed"]:
			if lv.has(k):
				m.set_shader_parameter(k, float(lv[k]))
		m.set_shader_parameter("lava_level", lava_sphere.lava_level())
		m.set_shader_parameter("safe_center", center + Vector3(0, sphere.radius, 0))   # the port, on top of the ball
		m.set_shader_parameter("safe_radius", lava_sphere.lava_keep_clear())
	return m


## The gas look of a planet whose type's surface is gas: its body's colours
## (the planet's own body over its type's), bands and ring plane.
static func gas_look_for(planet: Dictionary) -> Dictionary:
	var body: Dictionary = planet.get("type_cfg", {}).get("body", {}).duplicate()
	body.merge(planet.get("cfg", {}).get("body", {}), true)
	var ring: Dictionary = body.get("ring", {})
	return {
		"color_a": Color(str(body.get("color", "#d9c4b0"))),
		"color_b": Color(str(body.get("dark", "#8a6f68"))),
		"bands": float(body.get("bands", 22.0)),
		"ring_normal": GameFlow.vec(ring.get("normal", [0.25, 0.95, 0.2])).normalized(),
	}


## The ball terrain planet `planet`'s scene builds (a PlanetGen.build dictionary),
## seated on its town and flat sites, not built yet; null when its world is not a
## ball. The scene and a handoff's prewarm (prewarm_far) both make it here, so the
## far mesh one computes is the one the other needs.
static func for_planet(planet: Dictionary) -> PlanetTerrain:
	var world: Dictionary = planet.get("world", {})
	var r := float(world.get("terrain", {}).get("sphere_radius", 0.0))
	if r <= 0.0:
		return null
	var pt := PlanetTerrain.new()
	var surf: Dictionary = planet.get("type_cfg", {}).get("surface", {})
	if str(planet.get("ground", "")) == "ball" and str(surf.get("kind", "")) == "gas":
		# The ringed giant: smooth cloud tops all the way round, the town on a deck above.
		pt.use_sphere(GasSphere.new(r, surf))
		pt.gas_look = gas_look_for(planet)
	elif str(planet.get("ground", "")) == "ball":
		# Issue #99: the asteroid: cratered rock all the way round.
		pt.use_sphere(AsteroidSphere.new(r, surf))
		pt.use_surface(surf)
	else:
		pt.set_radius(r)
	pt.cache_key = "%s/%d" % [str(planet.get("id", "")), int(r)]
	var site := SpaceTravel.site_of(planet.get("town", {}))
	pt.configure_site(site.floor, site.walls, site.sunken, 0.0)
	pt.configure_flat_sites(droid_flat_sites(planet, pt.sphere) + camp_flat_sites(planet, pt.sphere)
		+ outpost_flat_sites(planet, pt.sphere))
	return pt


## Keep the droid relay yards from inheriting dune slopes (the home planet only).
## The height is sampled before registering the pad, so each one stays at the
## terrain's original level.
static func droid_flat_sites(planet: Dictionary, sp: PlanetSphere) -> Array:
	if str(planet.get("id", "")) != PlanetGen.home_id():
		return []
	var sites: Array = []
	for lm in planet.get("world", {}).get("landmarks", []):
		var location_id := str(lm.get("location", ""))
		if not location_id.begins_with("droid_post_"):
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		sites.append({
			"rect": Rect2(at.x - 10.0, at.z - 10.0, 20.0, 20.0),
			"y": sp.elevation(sp.map_dir(at.x, at.z)),
			"blend": 8.0,
		})
	return sites


## Issue #96: level ground under each native pack's camp, so the tents, the fire
## and the people sitting round it stand on the sand you see (not on mounds over a
## dune's slope). Sized from the people's camp block; the pad is the plane square to
## "up" there, through the mean height of the ground across it before levelling.
static func camp_flat_sites(planet: Dictionary, sp: PlanetSphere) -> Array:
	var nat: Dictionary = planet.get("natives", {})
	var cfg: Dictionary = nat.get("people", {}).get("data", {}).get("camp", {})
	if cfg.is_empty():
		return []
	var half := float(cfg.get("ring_m", 9.0)) + float(cfg.get("tent_radius", 3.0)) + float(cfg.get("pad_margin_m", 5.0))
	var sites: Array = []
	for pk in nat.get("packs", []):
		var c = pk.get("camp", null)
		if not (c is Dictionary) or not (c.get("at") is Vector2):
			continue
		var at: Vector2 = c.at
		var sum := 0.0
		for i in 3:
			for j in 3:
				sum += sp.elevation(sp.map_dir(at.x + (i - 1) * half, at.y + (j - 1) * half))
		var mid := sp.center + sp.map_dir(at.x, at.y) * (sp.radius + sum / 9.0)
		sites.append({
			"rect": Rect2(at.x - half, at.y - half, half * 2.0, half * 2.0),
			"y": sum / 9.0,
			"plane_c": mid,
			"plane_u": sp.up_at(mid),
			"blend": float(cfg.get("pad_blend_m", 22.0)),
		})
	return sites


## Issue #309: level ground under each Remnant outpost (the home planet only), so
## its control room's floor is the sand at its doorway, not a metre or four over a
## dune's slope. Sized from the location's buildings plus OUTPOST_PAD_MARGIN; like
## a camp's, the pad is the plane square to "up" there, through the mean height
## of the ground across it before levelling.
const OUTPOST_PAD_MARGIN := 2.5
const OUTPOST_PAD_BLEND := 12.0

static func outpost_flat_sites(planet: Dictionary, sp: PlanetSphere) -> Array:
	if str(planet.get("id", "")) != PlanetGen.home_id():
		return []
	var sites: Array = []
	for lm in planet.get("world", {}).get("landmarks", []):
		var location_id := str(lm.get("location", ""))
		if not (location_id.begins_with("remnant_outpost_") or location_id.begins_with("ranch_")):
			continue
		var loc = ItemKit._read_json("res://content/core/locations/%s.json" % location_id)
		if not (loc is Dictionary) or not bool(loc.get("pad", true)):
			continue             # a ranch village's outpost: the ranch's yard levels it
		var half := 0.0
		for b in loc.get("buildings", []):
			var bs := WorldGround._v3(b.get("size", [0, 0, 0]))
			var bp := WorldGround._v3(b.get("position", [0, 0, 0]))
			half = maxf(half, Vector2(bp.x, bp.z).length() + Vector2(bs.x, bs.z).length() * 0.5)
		if half <= 0.0:
			continue
		# Ranch villages: their walled yard, a set size ("pad_half", "pad_blend").
		half = float(loc.get("pad_half", half + OUTPOST_PAD_MARGIN))
		var blend := float(loc.get("pad_blend", OUTPOST_PAD_BLEND))
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		var sum := 0.0
		for i in 3:
			for j in 3:
				sum += sp.elevation(sp.map_dir(at.x + (i - 1) * half, at.z + (j - 1) * half))
		var mid := sp.center + sp.map_dir(at.x, at.z) * (sp.radius + sum / 9.0)
		sites.append({
			"rect": Rect2(at.x - half, at.z - half, half * 2.0, half * 2.0),
			"y": sum / 9.0,
			"plane_c": mid,
			"plane_u": sp.up_at(mid),
			"blend": blend,
		})
	return sites


# ---------------------------------------------------------------- handoff prewarm

## A no-fade handoff's scene builds its ball's coarse far mesh on its first frame
## (~80 ms for the moon, with the frame waiting on the workers). Flying in, the
## ship is seconds away from that switch: prewarm_far() starts the same chunks on
## worker threads then, and the scene's _build_far takes them instead of making its
## own. Keyed by cache_key (planet and radius); one entry per planet, used once.
var cache_key := ""
static var _prewarmed := {}           ## cache_key -> { terrain, group, cells, results }
## A ball drawn in another planet's sky (SpaceTravel._ball_body): its far chunks are
## kept for the session, since the scene that shows it is built again on the way
## home from it. By cache_key and cells.
var keep_far := false
static var _far_kept := {}


static func prewarm_far(planet: Dictionary) -> bool:
	var pt := for_planet(planet)
	if pt == null:
		return false
	if _prewarmed.has(pt.cache_key):
		pt.free()
		return false
	var cells := mini(pt.far_coarse_cells, pt.far_cells / 4)
	if cells < 2:
		cells = pt.far_cells
	var count := 6 * pt.far_chunks * pt.far_chunks
	var results := []
	results.resize(count)
	var g := WorkerThreadPool.add_group_task(func(k: int): results[k] = pt._far_chunk(k, cells), count, -1, false, "planet far prewarm")
	_prewarmed[pt.cache_key] = { "terrain": pt, "group": g, "cells": cells, "results": results }
	return true


static func is_prewarmed(key: String) -> bool:
	return _prewarmed.has(key)


## The prewarmed chunks for `key` at `cells` (waiting for any still running), or
## [] when there are none. Either way the entry is gone afterwards.
static func _take_prewarmed(key: String, cells: int) -> Array:
	if key == "" or not _prewarmed.has(key):
		return []
	var e: Dictionary = _prewarmed[key]
	_prewarmed.erase(key)
	WorkerThreadPool.wait_for_group_task_completion(int(e.group))
	(e.terrain as PlanetTerrain).free()
	return e.results if int(e.cells) == cells else []


## Drop every prewarm (a scene that never came; tests).
static func clear_prewarmed() -> void:
	for key in _prewarmed.keys():
		_take_prewarmed(key, -1)


func configure_site(floor_rect: Rect2, walls_rect: Rect2, sunken: Array, floor_y: float = 0.0) -> void:
	super.configure_site(floor_rect, walls_rect, sunken, floor_y)
	sphere.configure_site(floor_rect, walls_rect, sunken, floor_y)
	if sphere is AsteroidSphere:
		return                     # its own (short) blend from the station to the rock
	sphere.pad_margin = pad_margin
	sphere.blend = blend
	sphere.dune_offset = dune_offset
	sphere.sink_ramp = sink_ramp


func configure_flat_sites(sites: Array) -> void:
	super.configure_flat_sites(sites)
	sphere.configure_flat_sites(sites)


func height_at(x: float, z: float) -> float:
	return sphere.height_at(x, z, sink_grow)


func ground_at(x: float, z: float) -> float:
	return sphere.height_at(x, z, _collider_grow())


func _collider_grow() -> float:
	return sink_grow + near_step + 1.0


func _cell_step() -> float:
	return near_step


## Where the near layer would be centred for a world position: snapped to whole
## cells in map coordinates, so heights line up between rebuilds. (y = 0: the
## centre is a map position, not a point in the air.)
func snapped_center(pos: Vector3) -> Vector3:
	var m := sphere.world_to_map(pos)
	return Vector3(snappedf(m.x, near_step), 0.0, snappedf(m.y, near_step))


func collider_covers(x: float, z: float, margin: float = 0.0) -> bool:
	var y := height_at(x, z)
	if not is_finite(y):
		return false               # past the rim: no ground on that vertical line
	return _map_covers(sphere.world_to_map(Vector3(x, y, z)), margin)


func _map_covers(m: Vector2, margin: float) -> bool:
	if _near_map == Vector2.INF:
		return false
	var half := collider_size * 0.5 - margin
	return absf(m.x - _near_map.x) <= half and absf(m.y - _near_map.y) <= half


func build(with_mesh: bool = true) -> void:
	_with_mesh = with_mesh
	material = _ground_material(sphere.center)
	collider_body = StaticBody3D.new()
	collider_body.name = "Collider"
	collider_shape = CollisionShape3D.new()
	collider_shape.scale = Vector3(near_step, near_step, near_step)
	collider_body.add_child(collider_shape)
	add_child(collider_body)
	_build_town_collider()
	if with_mesh:
		near_mesh = _layer_mesh("Near")
		mid_mesh = _layer_mesh("Mid")
		# Only the sand round the player casts shadows: coarse dunes further out would
		# shade themselves in blotches the size of shadow-map texels.
		mid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_build_far()
	_apply("near", _compute("near", Vector2(collider_center.x, collider_center.z)))
	if with_mesh:
		_apply("mid", _compute("mid", Vector2.ZERO))


## Issue #99: just the whole ball, coarse, for another planet's sky (a neighbour
## seen from space). `center` is where its centre is in that scene.
## `staged` (issue #121, a handoff): coarser still at first, its full detail
## swapped in by this node's own _process, far_swap_budget_ms a frame.
func build_far_only(center: Vector3, staged: bool = false) -> void:
	if staged:
		refine_in_process = true
	_with_mesh = true
	material = _ground_material(center)      # the ball's own scene's noise (a handoff changes nothing)
	if staged:
		_build_far_staged()
	else:
		_build_far()


# ---------------------------------------------------------------- staged build (issue #121)

## build() for a no-fade handoff, where the ship is already flying and the frame
## must not freeze. Now: the material, an empty near collider, and the whole ball
## as a coarse far mesh (far_coarse_cells per chunk side, about a sixteenth of the
## vertex work), so there is never a hole. On worker threads: the town collider
## (finish_town_collider puts it in) and the full-detail far chunks
## (refine_far_step swaps them into the same MeshInstances, a few a frame). Near
## and mid come from the usual jobs: near where the ship asks (prefetch) or under
## a followed player (snap_to), mid under the camera. Once settled it is the same
## terrain build() makes: far_cells per chunk, the same town collider.
@export var far_coarse_cells := 16      ## at most; never more than a quarter of far_cells
@export var far_swap_budget_ms := 1.0   ## refine_in_process: main-thread ms a frame for swaps
var refine_in_process := false          ## swap the fine far chunks in from _process (no StagedBuild)
var far_detail_cells := 0              ## cells per side of the far chunks in place (0 = none yet)
var far_refined := true                ## false while a staged build's far mesh is still coarse
var far_swaps := 0                     ## fine chunks swapped in by refine_far_step (tests, traces)
var _far_group := -1                   ## the fine far chunks' worker group, while it runs
var _far_fine: Array = []
var _far_fine_max := 0.0
var _town_task := -1
var _town_result: Dictionary = {}
var _live_tasks := {}                  ## near/mid worker task ids not yet waited on


func build_staged(with_mesh: bool = true) -> void:
	_with_mesh = with_mesh
	material = _ground_material(sphere.center)
	collider_body = StaticBody3D.new()
	collider_body.name = "Collider"
	collider_shape = CollisionShape3D.new()
	collider_shape.scale = Vector3(near_step, near_step, near_step)
	collider_body.add_child(collider_shape)
	add_child(collider_body)
	_town_task = WorkerThreadPool.add_task(func(): _town_result = _town_patch(), false, "terrain town")
	if not with_mesh:
		return
	near_mesh = _layer_mesh("Near")
	mid_mesh = _layer_mesh("Mid")
	mid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_far_staged()


## The far ball coarse now, full detail on worker threads (refine_far_step).
func _build_far_staged() -> void:
	var coarse := mini(far_coarse_cells, far_cells / 4)
	if coarse < 2 or (keep_far and _far_kept.has("%s/%d" % [cache_key, far_cells])):
		_build_far()          # (kept: the full detail is already made, nothing to wait for)
		return
	_build_far(coarse)
	far_refined = false
	var count := _far_instances.size()
	_far_fine = []
	_far_fine.resize(count)
	var fine := far_cells
	_far_group = WorkerThreadPool.add_group_task(func(k: int): _far_fine[k] = _far_chunk(k, fine), count, -1, false, "planet far fine")


## Puts the town collider in once its worker is done. True when it is in.
func finish_town_collider() -> bool:
	if town_body != null:
		return true
	if _town_task < 0:
		_build_town_collider()
		return true
	if not WorkerThreadPool.is_task_completed(_town_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_town_task)
	_town_task = -1
	_install_town_collider(_town_result)
	_town_result = {}
	return true


## Swaps finished full-detail far chunks into place, at least one per call and
## more while under `budget_ms` (each is one mesh upload). True once all are in.
## The limb test stays conservative meanwhile: the bound covers the coarse and
## the fine chunks, and each chunk's cone is its own mesh's.
func refine_far_step(budget_ms: float = 2.0) -> bool:
	if far_refined:
		return true
	if _far_group < 0:
		return false
	if not WorkerThreadPool.is_group_task_completed(_far_group):
		return false
	var t0 := Time.get_ticks_usec()
	var count := _far_instances.size()
	while far_swaps < count:
		var k := far_swaps
		var chunk: Dictionary = _far_fine[k]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk.arrays)
		_far_instances[k].mesh = mesh
		_far_chunk_directions[k] = chunk.direction
		_far_chunk_angles[k] = float(chunk.angle)
		_far_fine_max = maxf(_far_fine_max, float(chunk.max_radius))
		_far_surface_bound = maxf(_far_surface_bound, _far_fine_max + maxf(far_limb_relief_padding, 0.0))
		_far_fine[k] = null
		far_swaps += 1
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	if far_swaps < count:
		return false
	WorkerThreadPool.wait_for_group_task_completion(_far_group)
	_far_group = -1
	_far_fine = []
	# All fine now: the same bound build() would have set.
	_far_surface_bound = maxf(_far_fine_max, sphere.radius) + maxf(far_limb_relief_padding, 0.0)
	far_detail_cells = far_cells
	far_refined = true
	return true


## Worker jobs hold this node: never let one outlive it (a scene switched while
## they still ran, as a handoff can within a second of arriving).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		finish_jobs()


## Wait for every worker job still running on this terrain (before freeing it:
## a node a worker is calling into cannot be freed).
func finish_jobs() -> void:
	if _far_group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_far_group)
		_far_group = -1
	if _town_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_town_task)
		_town_task = -1
	for task in _live_tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_live_tasks.clear()


func _build_town_collider() -> void:
	_install_town_collider(_town_patch())


## The town collider's heights (safe on a worker thread: reads the sphere only).
func _town_patch() -> Dictionary:
	var p := sphere.patch(0.0, 0.0, town_cells, town_step, sink_grow + town_step + 1.0)
	var data: PackedFloat32Array = p.heights
	for i in data.size():
		data[i] = (data[i] - TOWN_SINK) / town_step
	p.heights = data
	return p


func _install_town_collider(p: Dictionary) -> void:
	var data: PackedFloat32Array = p.heights
	var shape := HeightMapShape3D.new()
	shape.map_width = town_cells + 1
	shape.map_depth = town_cells + 1
	shape.map_data = data
	town_body = StaticBody3D.new()
	town_body.name = "TownCollider"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(town_step, town_step, town_step)
	town_body.add_child(cs)
	town_body.transform = p.xform
	add_child(town_body)


func _layer_mesh(n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.material_override = material
	add_child(mi)
	return mi


## The mid ring follows whatever this returns (the camera); none = the player.
func follow(node: Node3D) -> void:
	super.follow(node)
	if node == null and (_camera_source.is_valid() or not _jobs.is_empty() or not _pending_jobs.is_empty()
			or not _ready_meshes.is_empty()):
		set_physics_process(true)


func follow_camera(source: Callable) -> void:
	_camera_source = source
	if source.is_valid():
		set_physics_process(true)


func _visual_eye() -> Vector3:
	if _camera_source.is_valid():
		var eye: Vector3 = _camera_source.call()
		return eye
	if _target != null and is_instance_valid(_target):
		return _target.global_position
	return Vector3.ZERO


func _mid_cells_for_quality() -> int:
	return fast_mid_cells if _fast_flight_quality else mid_cells


func _mid_step_for_quality() -> float:
	return fast_mid_step if _fast_flight_quality else mid_step


## Lower only visual mid-terrain resolution during sustained flight; the old mesh
## stays installed until its replacement is complete, so coverage never blanks.
func set_fast_flight_quality(active: bool) -> void:
	if _fast_flight_quality == active:
		return
	_fast_flight_quality = active
	if not _with_mesh or mid_mesh == null:
		return
	var map_pos := sphere.world_to_map(_visual_eye())
	var cells := _mid_cells_for_quality()
	var step := _mid_step_for_quality()
	var center := Vector2(snappedf(map_pos.x, step), snappedf(map_pos.y, step))
	_start("mid", center, cells, step)




func snap_to(pos: Vector3) -> void:
	if collider_shape == null:
		return
	var c := snapped_center(pos)
	var m := Vector2(c.x, c.z)
	if not threaded:
		_apply("near", _compute("near", m))
	else:
		# A teleport (a respawn, a tow home): ground at once, but coarse (4x the
		# cells' size, a sixteenth of the work), then the fine one row by row as usual.
		var coarse := near_cells / 4
		var p := sphere.patch(m.x, m.y, coarse, near_step * 4.0, _collider_grow() + near_step * 3.0)
		p.center = m
		p.cells = coarse
		p.step = near_step * 4.0
		_apply_collider(p)
		_start("near", m)
	_pending = false
	snaps += 1


func is_rebuilding() -> bool:
	return _jobs.has("near") and _jobs.near.stage == "rows"


func prefetch(pos: Vector3) -> void:
	if collider_body == null:
		return
	var c := snapped_center(pos)
	var m := Vector2(c.x, c.z)
	if _near_map != Vector2.INF and m.distance_to(_near_map) < recenter_distance:
		return
	if _jobs.has("near") and m.distance_to(_jobs.near.center) < recenter_distance:
		return
	_start("near", m)
	set_physics_process(true)


func _process(_dt: float) -> void:
	if far_root == null or _far_instances.is_empty() or not is_inside_tree():
		return
	if refine_in_process and not far_refined:
		refine_far_step(far_swap_budget_ms)       # issue #121
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_set_far_visible(true)
		return
	# Mesh vertices and their cached cones are in this terrain's local frame.
	var camera_offset := to_local(camera.global_position) - sphere.center
	far_chunks_culled = 0
	for i in _far_instances.size():
		var visible := far_patch_visible(camera_offset, _far_chunk_directions[i],
			_far_chunk_angles[i], _far_surface_bound, far_limb_margin_degrees)
		if not visible:
			far_chunks_culled += 1
		var mi := _far_instances[i]
		if is_instance_valid(mi) and mi.visible != visible:
			mi.visible = visible


func _set_far_visible(visible: bool) -> void:
	far_chunks_culled = 0
	for mi in _far_instances:
		if is_instance_valid(mi) and mi.visible != visible:
			mi.visible = visible


func _physics_process(_dt: float) -> void:
	if collider_body == null:
		return
	_finish_jobs()
	var following := _target != null and is_instance_valid(_target)
	if following:
		var p := _target.global_position
		var m := sphere.world_to_map(p)
		if not _map_covers(m, 8.0) and not (_jobs.has("near") and _jobs.near.get("snap", false)):
			# Teleported past the edge: rebuild now. A one-off hitch beats a fall.
			snap_to(p)
		elif m.distance_to(_near_map) >= recenter_distance:
			var current_near: Dictionary = _pending_jobs.get("near", _jobs.get("near", {}))
			if current_near.is_empty() or m.distance_to(current_near.center) >= recenter_distance:
				var c := snapped_center(p)
				_start("near", Vector2(c.x, c.z))
	if _with_mesh:
		var eye := _visual_eye()
		var me := sphere.world_to_map(eye)
		if me.distance_to(_mid_map) >= mid_recenter:
			var cells := _mid_cells_for_quality()
			var step := _mid_step_for_quality()
			var center := Vector2(snappedf(me.x, step), snappedf(me.y, step))
			var current_mid: Dictionary = _pending_jobs.get("mid", _jobs.get("mid", _ready_meshes.get("mid", {})))
			var changed := current_mid.is_empty()
			if not changed:
				changed = center.distance_to(current_mid.center) >= mid_recenter
				if int(current_mid.cells) != cells or not is_equal_approx(float(current_mid.step), step):
					changed = true
			if changed:
				_start("mid", center, cells, step)
	if not following and not _camera_source.is_valid() and _jobs.is_empty() and _pending_jobs.is_empty() \
			and _ready_meshes.is_empty():
		set_physics_process(false)


## The collider (near) is built on the main thread, `rows_per_frame` rows each
## physics frame, and swapped in whole on the frame its last row is done: the
## same frame on every run, so traces and tests are repeatable (a swap on
## whichever frame a worker thread happened to finish made them flaky). About
## 1.5 ms a frame; a whole rebuild takes ~2 s, 15 m of a sprint, inside the 80 m
## the old one still covers. Vehicles and ships ride the sphere's own heights, not
## this collider. The meshes (look only) are built on one worker thread: GDScript
## workers only slow each other down, but one runs beside the main thread for free.
@export var rows_per_frame := 2


func _start(layer: String, center: Vector2, cells_override: int = -1, step_override: float = -1.0) -> void:
	var near := layer == "near"
	var cells := cells_override if cells_override > 0 else (near_cells if near else _mid_cells_for_quality())
	var step := step_override if step_override > 0.0 else (near_step if near else _mid_step_for_quality())
	var request := { "center": center, "cells": cells, "step": step }
	if _jobs.has(layer):
		var active: Dictionary = _jobs[layer]
		var same_request: bool = active.center == center and int(active.cells) == cells and is_equal_approx(float(active.step), step)
		if same_request:
			_pending_jobs.erase(layer)
			return
		if int(active.task) >= 0:
			# WorkerThreadPool cannot cancel a task: keep one latest request, never a stale queue.
			_pending_jobs[layer] = request
			set_physics_process(true)
			return
		# Near rows run on the main thread and can be safely replaced before completion.
		_jobs.erase(layer)
	if not threaded:
		_apply(layer, _compute(layer, center, cells, step))
		if near:
			recenters += 1
		return
	var job := { "center": center, "cells": cells, "step": step, "row": 0,
		"heights": PackedFloat32Array(), "verts": PackedVector3Array(), "stage": "rows", "task": -1 }
	if not near:
		# Capture the quality and spacing at request time; a later flight-mode switch
		# cannot reinterpret this worker result.
		job.stage = "mesh"
		job.task = WorkerThreadPool.add_task(func(): job.result = _compute(layer, center, cells, step), false, "terrain " + layer)
		_live_tasks[job.task] = true
	_jobs[layer] = job
	set_physics_process(true)


func _finish_jobs() -> void:
	for layer in _jobs.keys().duplicate():
		if not _jobs.has(layer):
			continue
		var job: Dictionary = _jobs[layer]
		var ts := Time.get_ticks_usec()
		if job.stage == "rows":
			var n := int(job.cells) + 1
			var j1 := mini(int(job.row) + rows_per_frame, n)
			var part := sphere.patch_rows(job.center.x, job.center.y, job.cells, job.step,
				_collider_grow(), job.row, j1)
			var hh: PackedFloat32Array = job.heights
			hh.append_array(part.heights)
			job.heights = hh
			var vv: PackedVector3Array = job.verts
			vv.append_array(part.verts)
			job.verts = vv
			job.row = j1
			if j1 >= n:
				var p := { "xform": sphere.patch_frame(job.center.x, job.center.y), "heights": job.heights,
					"verts": job.verts, "center": job.center, "cells": job.cells, "step": job.step }
				_apply_collider(p)
				recenters += 1
				worst_swap_ms = maxf(worst_swap_ms, (Time.get_ticks_usec() - ts) / 1000.0)
				if _with_mesh:
					job.stage = "mesh"
					job.result = p
					job.task = WorkerThreadPool.add_task(func(): p.arrays = _grid_arrays(p.verts, n), false, "terrain mesh")
					_live_tasks[job.task] = true
				else:
					_jobs.erase(layer)
			worst_step_ms = maxf(worst_step_ms, (Time.get_ticks_usec() - ts) / 1000.0)
		elif int(job.task) >= 0 and WorkerThreadPool.is_task_completed(job.task):
			WorkerThreadPool.wait_for_task_completion(job.task)
			_live_tasks.erase(job.task)
			_jobs.erase(layer)
			if _pending_jobs.has(layer):
				var pending: Dictionary = _pending_jobs[layer]
				_pending_jobs.erase(layer)
				_start(layer, pending.center, int(pending.cells), float(pending.step))
			else:
				_ready_meshes[layer] = job.result   # a newer one replaces an unsent older one
	upload_ready_meshes(mesh_upload_budget_ms)


## Puts finished near/mid meshes in, near first: at least one a call, more while
## under `budget_ms`. True once none are waiting.
func upload_ready_meshes(budget_ms: float) -> bool:
	var t0 := Time.get_ticks_usec()
	for layer in ["near", "mid"]:
		if not _ready_meshes.has(layer):
			continue
		var p: Dictionary = _ready_meshes[layer]
		_ready_meshes.erase(layer)
		_apply_mesh(layer, p)
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	perf_mesh_upload_worst_frame_ms = maxf(perf_mesh_upload_worst_frame_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	return _ready_meshes.is_empty()


## Heights (and, with the look on, the mesh arrays) for a layer centred at map c,
## all at once (the synchronous path: tests, snap_to, the first build).
func _compute(layer: String, c: Vector2, cells_override: int = -1, step_override: float = -1.0) -> Dictionary:
	var near := layer == "near"
	var cells := cells_override if cells_override > 0 else (near_cells if near else _mid_cells_for_quality())
	var step := step_override if step_override > 0.0 else (near_step if near else _mid_step_for_quality())
	var grow := _collider_grow() if near else sink_grow
	var p := sphere.patch(c.x, c.y, cells, step, grow)
	p.center = c
	p.cells = cells
	p.step = step
	if _with_mesh:
		p.arrays = _grid_arrays(p.verts, cells + 1)
	return p


func _apply(layer: String, p: Dictionary) -> void:
	if layer == "near":
		_apply_collider(p)
	_apply_mesh(layer, p)


func _apply_collider(p: Dictionary) -> void:
	var xf: Transform3D = p.xform
	if true:
		var step: float = p.step
		var data: PackedFloat32Array = p.heights
		var scaled := PackedFloat32Array()
		scaled.resize(data.size())
		for i in data.size():
			scaled[i] = data[i] / step
		var shape := HeightMapShape3D.new()
		shape.map_width = int(p.cells) + 1
		shape.map_depth = int(p.cells) + 1
		shape.map_data = scaled
		collider_shape.shape = shape
		collider_shape.scale = Vector3(step, step, step)
		collider_body.global_transform = xf
		collider_center = Vector3(p.center.x, 0.0, p.center.y)
		_near_map = p.center
		_pending = false


func performance_snapshot() -> Dictionary:
	var visible_far := 0
	for chunk in _far_instances:
		if is_instance_valid(chunk) and chunk.visible:
			visible_far += 1
	return {
		"active_terrain_jobs": _jobs.size(),
		"pending_terrain_jobs": _pending_jobs.size(),
		"ready_terrain_meshes": _ready_meshes.size(),
		"far_patch_total": _far_instances.size(),
		"far_patch_visible": visible_far,
		"far_patch_culled": far_chunks_culled,
		"near_patch_visible": near_mesh != null and near_mesh.visible,
		"mid_patch_visible": mid_mesh != null and mid_mesh.visible,
		"far_build_wall_ms": perf_far_build_ms,
		"far_worker_wait_ms": perf_far_worker_wait_ms,
		"main_thread_mesh_submit_ms": perf_mesh_submit_ms,
		"main_thread_mesh_submit_count": perf_mesh_submit_count,
		"main_thread_mesh_upload_worst_frame_ms": perf_mesh_upload_worst_frame_ms
	}


func _apply_mesh(layer: String, p: Dictionary) -> void:
	var xf: Transform3D = p.xform
	if layer == "near":
		if near_mesh != null:
			_set_mesh(near_mesh, p.arrays, xf, int(p.cells) * float(p.step))
			_set_hole(mid_mesh, xf, int(p.cells) * float(p.step) * 0.5)
	elif mid_mesh != null:
		_mid_map = p.center
		_set_mesh(mid_mesh, p.arrays, xf, int(p.cells) * float(p.step))
		if far_root != null:
			for c in far_root.get_children():
				_set_hole(c, xf, int(p.cells) * float(p.step) * 0.5)


func _set_mesh(mi: MeshInstance3D, arrays: Array, xf: Transform3D, size: float) -> void:
	var mesh_started := Time.get_ticks_usec()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-size * 0.5, -200, -size * 0.5), Vector3(size, 400, size))
	mi.mesh = mesh
	mi.global_transform = xf
	_record_mesh_submit(mesh_started)


func _record_mesh_submit(started_usec: int) -> void:
	perf_mesh_submit_ms += (Time.get_ticks_usec() - started_usec) / 1000.0
	perf_mesh_submit_count += 1


## Tell an outer layer where the inner one lies, so it sinks out of the way there.
func _set_hole(mi: GeometryInstance3D, xf: Transform3D, half: float) -> void:
	if mi == null:
		return
	mi.set_instance_shader_parameter("hole_origin", Vector4(xf.origin.x, xf.origin.y, xf.origin.z, half))
	mi.set_instance_shader_parameter("hole_x", xf.basis.x)
	mi.set_instance_shader_parameter("hole_z", xf.basis.z)


## Mesh arrays for a (n x n) grid of points: normals from neighbours, wound to face
## up (clockwise from above = front in Godot).
static func _grid_arrays(verts: PackedVector3Array, n: int) -> Array:
	var norms := PackedVector3Array()
	norms.resize(n * n)
	for j in n:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, n - 1)
		for i in n:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var dx := verts[j * n + i1] - verts[j * n + i0]
			var dz := verts[j1 * n + i] - verts[j0 * n + i]
			norms[j * n + i] = dz.cross(dx).normalized()
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for j in n - 1:
		for i in n - 1:
			var v00 := j * n + i
			var v10 := v00 + 1
			var v01 := v00 + n
			var v11 := v01 + 1
			idx[w] = v00; idx[w + 1] = v10; idx[w + 2] = v01
			idx[w + 3] = v10; idx[w + 4] = v11; idx[w + 5] = v01
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


# ---------------------------------------------------------------- the far ball

## The whole ball: each cube face split into far_chunks^2 meshes, built in
## parallel at load. All chunks share one spacing, so their edges meet exactly.
## 64 cells per chunk cuts the previous far-surface spacing by 25% without adding
## chunks/draw calls or changing the height source or radial curvature.
## Conservative sphere-limb test for a cached far patch. The caller supplies a
## surface radius already inflated by the sampled terrain envelope and relief pad.
## A patch stays visible unless its entire angular cone is beyond that limb plus
## the safety margin; cameras inside the envelope never cull any patch.
static func far_patch_visible(camera_offset: Vector3, patch_direction: Vector3,
		patch_angle: float, surface_bound: float, margin_degrees: float = 5.0) -> bool:
	var distance_squared := camera_offset.length_squared()
	if surface_bound <= 0.0 or distance_squared <= surface_bound * surface_bound:
		return true
	if patch_direction.length_squared() < 0.000001:
		return true
	var distance := sqrt(distance_squared)
	var camera_direction := camera_offset / distance
	var horizon_angle := acos(clampf(surface_bound / distance, 0.0, 1.0))
	var separation := camera_direction.angle_to(patch_direction.normalized())
	var nearest_patch_angle := separation - maxf(patch_angle, 0.0)
	return nearest_patch_angle <= horizon_angle + deg_to_rad(maxf(margin_degrees, 0.0))


## `cells` per chunk side (issue #121: a staged build's coarse first pass); -1 = far_cells.
func _build_far(cells: int = -1) -> void:
	var fc := cells if cells > 0 else far_cells
	var build_started := Time.get_ticks_usec()
	far_root = Node3D.new()
	far_root.name = "Far"
	add_child(far_root)
	_far_instances.clear()
	_far_chunk_directions.clear()
	_far_chunk_angles.clear()
	far_detail_cells = fc
	var count := 6 * far_chunks * far_chunks
	var wait_started := Time.get_ticks_usec()
	var results := _take_prewarmed(cache_key, fc)
	var kept := "%s/%d" % [cache_key, fc]
	if results.size() != count and keep_far:
		results = _far_kept.get(kept, [])
	if results.size() != count:
		results = []
		results.resize(count)
		var g := WorkerThreadPool.add_group_task(func(k: int): results[k] = _far_chunk(k, fc), count, -1, true, "planet far")
		WorkerThreadPool.wait_for_group_task_completion(g)
	if keep_far and cache_key != "":
		_far_kept[kept] = results
	perf_far_worker_wait_ms += (Time.get_ticks_usec() - wait_started) / 1000.0
	var maximum_vertex_radius := sphere.radius
	for k in count:
		var chunk: Dictionary = results[k]
		maximum_vertex_radius = maxf(maximum_vertex_radius, float(chunk.max_radius))
		_far_chunk_directions.append(chunk.direction)
		_far_chunk_angles.append(float(chunk.angle))
		var mi := MeshInstance3D.new()
		mi.name = "Chunk%d" % k
		var mesh_started := Time.get_ticks_usec()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk.arrays)
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_root.add_child(mi)
		_record_mesh_submit(mesh_started)
		_far_instances.append(mi)
	# The sampled far-mesh vertices already include the sphere's dune/crater relief.
	# The additional radial pad is deliberately generous for relief between samples.
	_far_surface_bound = maximum_vertex_radius + maxf(far_limb_relief_padding, 0.0)
	perf_far_build_ms += (Time.get_ticks_usec() - build_started) / 1000.0


const _FACES := [
	[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.LEFT, Vector3.BACK],
	[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
]


func _far_chunk(k: int, cells: int = -1) -> Dictionary:
	var fc := cells if cells > 0 else far_cells
	var per := far_chunks * far_chunks
	var face: Array = _FACES[k / per]
	var ci := (k % per) % far_chunks
	var cj := (k % per) / far_chunks
	# One extra row of points all round, so the normals on a chunk's edge come out
	# the same as its neighbour's (no lighting seam); the border is cut off after.
	var n := fc + 3
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var norm: Vector3 = face[0]
	var ax: Vector3 = face[1]
	var ay: Vector3 = face[2]
	for j in n:
		for i in n:
			# Equal-angle cube mapping keeps the cells near the same size everywhere.
			var a := (float(ci * fc + i - 1) / (far_chunks * fc)) * 2.0 - 1.0
			var b := (float(cj * fc + j - 1) / (far_chunks * fc)) * 2.0 - 1.0
			var dir := (norm + ax * tan(a * PI * 0.25) + ay * tan(b * PI * 0.25)).normalized()
			verts[j * n + i] = sphere.center + dir * (sphere.radius + sphere.elevation(dir, sink_grow))
	var full := _grid_arrays(verts, n)
	var m := n - 2
	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	cv.resize(m * m)
	cn.resize(m * m)
	var fn: PackedVector3Array = full[Mesh.ARRAY_NORMAL]
	for j in m:
		for i in m:
			cv[j * m + i] = verts[(j + 1) * n + i + 1]
			cn[j * m + i] = fn[(j + 1) * n + i + 1]
	var arrays := _grid_arrays(cv, m)
	arrays[Mesh.ARRAY_NORMAL] = cn
	verts = cv
	n = m
	# Face winding differs per face: flip the triangles that came out facing in.
	var mid := verts[(n / 2) * n + n / 2]
	var nm: Vector3 = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[(n / 2) * n + n / 2]
	if nm.dot(mid - sphere.center) < 0.0:
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var s := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = s
		arrays[Mesh.ARRAY_INDEX] = idx
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for q in ns.size():
			ns[q] = -ns[q]
		arrays[Mesh.ARRAY_NORMAL] = ns
	var direction_sum := Vector3.ZERO
	var max_vertex_radius := sphere.radius
	for vertex in verts:
		var radial := vertex - sphere.center
		max_vertex_radius = maxf(max_vertex_radius, radial.length())
		direction_sum += radial.normalized()
	var chunk_direction := direction_sum.normalized()
	var chunk_angle := 0.0
	for vertex in verts:
		var radial := vertex - sphere.center
		chunk_angle = maxf(chunk_angle, chunk_direction.angle_to(radial.normalized()))
	return { "arrays": arrays, "direction": chunk_direction, "angle": chunk_angle, "max_radius": max_vertex_radius }