class_name FxWarmup
extends Node
## The first blaster shot froze the game for a few seconds: the bolt's glowing
## streak, the muzzle flash, the pop where it lands and their sounds were all
## loaded, built and compiled on that one frame. A town adds this node as it is
## built, and it does that work in pieces, one a frame, before anyone fires:
##
##   1. the explosion and muzzle-flash shaders,
##   2. the impact and ship-gun sounds,
##   3. ExplosionFx's shared meshes, materials, ramps and curves,
##   4. then one of each on screen, far out in front of the camera, so the GPU
##      compiles them for real: a bolt, a muzzle flash, and each kind of explosion.
##
## Once a session (what it built is shared and kept). Headless there is nothing to
## draw, so it stops after the loading.

const BoltScene := preload("res://scenes/entities/bolt.tscn")
const FLASH_SHADER := "res://src/systems/look/shaders/muzzle_flash.gdshader"
## The sounds a shot, a hit or a blast plays through Sound.play.
const SOUNDS := ["ship_laser", "ship_cannon", "ship_missile", "speeder_laser", "droid_shot", "ship_hit", "droid_pop", "vehicle_boom"]
const AHEAD := 300.0       ## metres in front of the camera the shown pieces go
const SHOW_FRAMES := 3     ## frames a shown bolt or flash stays before it is freed

static var done := false
static var _running: FxWarmup
static var _keep: Array = []      ## shaders and materials kept alive, so nothing compiles twice

var _steps: Array[Callable] = []
var _shown: Array = []            ## [node, frames left]


## Adds the warm-up under `parent` (a town), unless one ran this session or is running.
static func start(parent: Node) -> FxWarmup:
	if done or is_instance_valid(_running) or parent == null:
		return null
	_running = FxWarmup.new()
	_running.name = "FxWarmup"
	parent.add_child(_running)
	return _running


func _ready() -> void:
	_steps = [_load_shaders, _load_sounds, _build_explosion_parts]
	if DisplayServer.get_name() != "headless":
		_steps.append_array([_show_bolt, _show_flash, _show_blast.bind("bolt"), _show_blast.bind("small"),
			_show_blast.bind("clash"), _show_blast.bind("big")])


## One step a frame; a step that returns false (no camera yet) is tried again next frame.
func _process(_dt: float) -> void:
	for i in range(_shown.size() - 1, -1, -1):
		_shown[i][1] -= 1
		if _shown[i][1] <= 0:
			if is_instance_valid(_shown[i][0]):
				_shown[i][0].queue_free()
			_shown.remove_at(i)
	if not _steps.is_empty():
		if _steps[0].call():
			_steps.pop_front()
		return
	if _shown.is_empty():
		done = true
		set_process(false)


## Where shown pieces go: AHEAD in front of the camera (INF when there is none yet).
func _ahead() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Vector3.INF
	return cam.global_position - cam.global_transform.basis.z * minf(AHEAD, cam.far * 0.5)


func _load_shaders() -> bool:
	for p in [ExplosionFx.PUFF_SHADER, ExplosionFx.GLOW_SHADER, FLASH_SHADER]:
		_keep.append(load(p))
	return true


func _load_sounds() -> bool:
	Sound.warm(SOUNDS)
	return true


func _build_explosion_parts() -> bool:
	ExplosionFx.warm()
	return true


## One explosion of `kind` (it frees itself). The big one is small: the same
## shaders, without a ship-sized light on the horizon.
func _show_blast(kind: String) -> bool:
	var at := _ahead()
	if at == Vector3.INF:
		return false
	match kind:
		"bolt":
			ExplosionFx.bolt(self, at)
		"small":
			ExplosionFx.small(self, at)
		"clash":
			ExplosionFx.clash(self, at)
		"big":
			ExplosionFx.big(self, at, 0.1)
	return true


## A player's bolt (the glowing streak and its light) that neither moves nor hits.
func _show_bolt() -> bool:
	var at := _ahead()
	if at == Vector3.INF:
		return false
	var b = BoltScene.instantiate()
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.stylize = true
	b.speed = 0.0
	b.damage = 0.0
	add_child(b)
	b.global_position = at
	var streak := b.get_node_or_null("Streak") as MeshInstance3D
	if streak != null:
		_keep.append(streak.material_override)
	_shown.append([b, SHOW_FRAMES])
	return true


## The muzzle flash's quad (PlayerAvatar._make_flash), shown for a few frames.
func _show_flash() -> bool:
	var at := _ahead()
	if at == Vector3.INF:
		return false
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := ShaderMaterial.new()
	m.shader = load(FLASH_SHADER)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	_shown.append([mi, SHOW_FRAMES])
	return true
