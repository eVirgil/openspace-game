extends Node3D
## Camera rig node (M1). Owns a live Camera3D and drives it every frame from the
## pure camera_rig math. Toggling FPV<->TPV only recomputes the camera position
## for the SAME yaw/pitch, so aim is preserved.
##
## M11 adds, all on the node side (the pure rig and its tests are unchanged):
## - an over-the-shoulder third person view that never clips through walls (a ray
##   from the head to the camera pulls the camera in front of whatever it hits);
## - a 0.2 s glide between views (position only: the look direction, which is the
##   aim, still switches instantly);
## - recoil kick, screen shake, FOV zoom, and a cinematic override the bar's
##   two-shot uses while the player talks.
##
## V's third view, cinematic (CinematicShots), is node side too: the camera cuts
## to a new spot near the player every few seconds and trails them between cuts.
## The guns still aim along the third person view (aim_transform), which is where
## the mouse points; going into or out of it is a cut, not a glide.

const CameraRig := preload("res://src/systems/camera/camera_rig.gd")
const CinematicShots := preload("res://src/systems/camera/cinematic_shots.gd")

signal view_changed(first_person: bool)

@export var mouse_sensitivity := 0.0025
@export var toggle_action := "toggle_view"
@export var shoulder := 0.55          ## third person shoulder offset (m)
@export var tpv_distance := 3.2
@export var collide := true
@export var glide_time := 0.2
@export var base_fov := 75.0
@export var cine_fov := 55.0          ## the cinematic view's lens
var rig := CameraRig.new()
var cine := CinematicShots.new()
var _camera: Camera3D
var _player: Node3D
var input_enabled := true             ## false while a dialogue owns the mouse
var look_blocked := false            ## the weapon wheel is open: the mouse points at slots, not the view

var _glide_from := Transform3D()
var _glide_left := 0.0
var _shake := 0.0
var _kick := 0.0                      ## pending recoil pitch (rad), applied over a few frames
var _zoom := 1.0
var _zoom_target := 1.0
var _override := false
var _override_xf := Transform3D()
var _override_fov := -1.0
var _override_blend := 0.0
var _last_xf := Transform3D()
var _slide_roll := 0.0                ## current camera roll from a slide (rad)
var _aim_xf := Transform3D()          ## the third person view the guns aim along, in cinematic


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = base_fov
	add_child(_camera)
	_camera.make_current()
	rig.tpv_shoulder = shoulder
	rig.tpv_distance = tpv_distance
	cine.blocked = _resolve_collision


func set_player(player: Node3D) -> void:
	_player = player


func camera() -> Camera3D:
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and not look_blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			or event is InputEventMouseMotion and not look_blocked and DisplayServer.get_name() == "headless":
		rig.add_yaw(-event.relative.x * mouse_sensitivity * _zoom)
		rig.add_pitch(-event.relative.y * mouse_sensitivity * _zoom)
	if event.is_action_pressed(toggle_action):
		toggle_view()


## V: first person -> third person -> cinematic -> first person.
func toggle_view() -> void:
	set_view((rig.mode + 1) % CameraRig.Mode.size())


func set_view(m: int) -> void:
	if rig.mode == m:
		return
	var was_cine := rig.is_cinematic()
	rig.set_mode(m)
	# First <-> third person glides; into or out of cinematic is a cut.
	_glide_from = _last_xf
	_glide_left = glide_time if _last_xf != Transform3D() and not was_cine and not rig.is_cinematic() else 0.0
	cine.reset()
	view_changed.emit(rig.is_first_person())
	print_verbose("CameraRig: view -> ", ["FPV", "TPV", "CINE"][rig.mode])


func set_first_person(on: bool) -> void:
	if rig.is_first_person() != on:
		set_view(CameraRig.Mode.FPV if on else CameraRig.Mode.TPV)


func is_cinematic() -> bool:
	return rig.is_cinematic()


## The view the guns aim along: the camera's, except in cinematic, where the shot
## is off somewhere else and the aim is still the third person view's.
func aim_transform() -> Transform3D:
	return _aim_xf if rig.is_cinematic() and _aim_xf != Transform3D() else _camera.global_transform


## Recoil: pitch the view up by `degrees`, spread over a few frames.
func kick(degrees: float) -> void:
	_kick += deg_to_rad(degrees)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 1 = normal, < 1 zooms in (aiming down the sights).
func set_zoom(z: float) -> void:
	_zoom_target = z


## Hand the camera to a fixed shot (the bar's two-shot). null-like: call clear.
func set_override(xf: Transform3D, fov: float = -1.0) -> void:
	_override = true
	_override_xf = xf
	_override_fov = fov


## The override at once, no blend in from the on-foot view: a no-fade handoff's
## new scene must show the very view the last scene ended on, from its first frame.
func snap_override(xf: Transform3D, fov: float = -1.0) -> void:
	set_override(xf, fov)
	_override_blend = 1.0
	if _camera.is_inside_tree():
		_camera.global_transform = xf
	if fov > 0.0:
		_camera.fov = fov
	_camera.make_current()


func clear_override() -> void:
	_override = false


func is_overridden() -> bool:
	return _override or _override_blend > 0.001


func _process(delta: float) -> void:
	if _player == null:
		return
	# Absolute, not relative. rotate_y() re-added the yaw every frame and spun
	# the player forever after any mouse movement. The body reads -rotation.y
	# as its movement yaw, which lines up with the rig's look direction.
	_player.rotation.y = rig.yaw
	if not _camera.is_inside_tree():
		return
	if _kick > 0.0:
		var k := minf(_kick, _kick * 25.0 * delta + 0.0005)
		rig.add_pitch(k)
		_kick -= k
	# M15: the eye drops with a crouch (the capsule shrinks too), so you cannot
	# peek over cover your body is hiding behind.
	var crouched: bool = _player.get("crouched_shape") == true
	# Slide: lower still, eased in and out by progress, plus a small roll (issue #65).
	var sliding: bool = _player.get("sliding") == true
	var eye_to := 1.0 if crouched else 1.6
	if sliding:
		eye_to = 0.85
	rig.fpv_offset.y = move_toward(rig.fpv_offset.y, eye_to, delta * (6.0 if sliding else 4.0))
	rig.tpv_height = move_toward(rig.tpv_height, (1.25 if crouched else 1.8), delta * 4.0)
	_slide_roll = lerpf(_slide_roll, deg_to_rad(3.5) if sliding else 0.0, 1.0 - exp(-10.0 * delta))
	# Follow the player's render-smoothed origin (between the last two physics ticks),
	# not the 60 Hz stepped global_position. Plain Node3D players have no such method.
	var p: Vector3 = _player.call("render_origin") if _player.has_method("render_origin") else _player.global_position
	var xf: Transform3D = rig.camera_transform(p)
	# Issue #77: on the home planet the view stands on the ground's up, not world up.
	var tilt: Basis = _player.get("tilt") if _player.get("tilt") is Basis else Basis.IDENTITY
	var pivot: Vector3 = rig.tpv_pivot(p)
	if tilt != Basis.IDENTITY:
		xf = Transform3D(tilt, p) * Transform3D(Basis.IDENTITY, -p) * xf
		pivot = p + tilt * (pivot - p)
	if not rig.is_first_person() and collide:
		xf.origin = _resolve_collision(pivot, xf.origin)
	_aim_xf = xf
	if rig.is_cinematic():
		var up: Vector3 = tilt.y
		xf = cine.update(delta, p + up * 1.2, xf.basis.z * -1.0, up)
	elif _glide_left > 0.0:
		_glide_left = maxf(0.0, _glide_left - delta)
		var f := 1.0 - _glide_left / glide_time
		f = f * f * (3.0 - 2.0 * f)
		xf.origin = _glide_from.origin.lerp(xf.origin, f)
	if _shake > 0.0:
		xf.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.05
		_shake = maxf(0.0, _shake - delta * 4.0)
	_last_xf = xf
	_override_blend = move_toward(_override_blend, 1.0 if _override else 0.0, delta * 2.5)
	if _override_blend > 0.0:
		var b := _override_blend * _override_blend * (3.0 - 2.0 * _override_blend)
		xf = xf.interpolate_with(_override_xf, b)
	if absf(_slide_roll) > 0.0005 and not rig.is_cinematic():
		xf.basis = xf.basis * Basis(Vector3(0, 0, 1), _slide_roll)
	_camera.global_transform = xf
	_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-12.0 * delta))
	var fov := cine_fov if rig.is_cinematic() else base_fov * _zoom
	if _override_blend > 0.0 and _override_fov > 0.0:
		fov = lerpf(fov, _override_fov, _override_blend)
	_camera.fov = fov


## Pull the camera in front of whatever lies between the head and it.
func _resolve_collision(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return to
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to
	var dir := (to - from).normalized()
	var p: Vector3 = hit.position - dir * 0.25
	if from.distance_to(p) < 0.3:
		p = from - dir * 0.0
	return p
