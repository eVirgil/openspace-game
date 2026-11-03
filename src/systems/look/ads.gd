extends RefCounted
## Aim down sights maths (issue #65), kept pure so it is testable headless.
##
## The ADS pose is solved from the camera, not hand tuned: a fixed chest-space
## offset cannot keep a sight on the screen centre because in first person the
## chest follows the camera pitch at a different rate. So while aimed the weapon is
## put where the camera is: pointing along its forward axis, with the sight point
## on the centre line, `relief` metres in front of the eye. Anything on that line
## (rear notch, front post, scope reticle) lands on the crosshair.

const DEFAULTS := { "sight": [0.0, 0.1, 0.0], "relief": 0.25, "mag": 1.0, "blend_s": 0.15 }


## The `ads` block of a gun in hand_weapons.json, missing keys filled in.
static func spec(look: Dictionary, id: String) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var g = look.get(id, {})
	if g is Dictionary and g.get("ads") is Dictionary:
		out.merge(g.ads, true)
	return out


static func has_ads(look: Dictionary, id: String) -> bool:
	var g = look.get(id, {})
	return g is Dictionary and g.get("ads") is Dictionary


## `step`: which of the gun's "zoom_steps" (the sniper rifle: a second right-click
## zooms in further); a gun without them has the one `mag`.
static func magnification(look: Dictionary, id: String, step := 0) -> float:
	var steps = spec(look, id).get("zoom_steps")
	if steps is Array and not steps.is_empty():
		return maxf(1.0, float(steps[clampi(step, 0, steps.size() - 1)]))
	return maxf(1.0, float(spec(look, id).mag))


## How many zoom steps a gun has (1 for most).
static func zoom_steps(look: Dictionary, id: String) -> int:
	var steps = spec(look, id).get("zoom_steps")
	return steps.size() if steps is Array and not steps.is_empty() else 1


## What to hand CameraRigNode.set_zoom: fov = base_fov * zoom = base_fov / mag.
static func zoom(look: Dictionary, id: String, step := 0) -> float:
	return 1.0 / magnification(look, id, step)


## Zoomed past a gun's first step, the eye backs off the scope by this much so the
## eyepiece and reticle keep their size on screen (the view inside zooms, the scope
## does not). `fov_deg` is the camera's fov now, `base_fov` its unzoomed one.
## Never below 1: nothing changes at or under the first step.
static func relief_scale(look: Dictionary, id: String, base_fov: float, fov_deg: float) -> float:
	var first := deg_to_rad(base_fov / magnification(look, id, 0))
	return maxf(1.0, tan(first * 0.5) / tan(deg_to_rad(maxf(1.0, fov_deg)) * 0.5))


static func sight_point(look: Dictionary, id: String) -> Vector3:
	var a = spec(look, id).sight
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## World transform of the weapon (model space, +Z along the barrel) that puts
## `sight` (model space) on the camera's centre line, `relief` in front of the eye,
## with the barrel along the camera's forward axis (-Z of the camera).
static func weapon_global(cam: Transform3D, sight: Vector3, relief: float) -> Transform3D:
	var b := cam.basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(b, cam.origin - cam.basis.orthonormalized().z * relief - b * sight)


## The same pose in the camera's own space: weapon_global with the camera at the
## origin. Small numbers only, so it holds to the micron however far out the
## camera is (GunSights.pin draws the scope at it).
static func weapon_local(sight: Vector3, relief: float) -> Transform3D:
	return weapon_global(Transform3D.IDENTITY, sight, relief)


## How far (metres) the sight point is off the camera's centre line; 0 when aligned.
static func centre_error(cam: Transform3D, weapon: Transform3D, sight: Vector3) -> float:
	var local := cam.affine_inverse() * (weapon * sight)
	return Vector2(local.x, local.y).length()
