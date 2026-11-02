extends RefCounted
## Cinematic view (V's third view). Pure, like the camera rig and the chase
## camera: a camera that cuts to a new spot near its subject every `shot_time`
## seconds and, between cuts, hangs there, turning to keep the subject framed and
## drifting after it on a slack lead, so the subject walks (or flies) out ahead of
## it. On foot the rig node owns one, in ships and speeders the chase camera does;
## `scale` sizes the shots to the subject. The owner hands it a ray check
## (`blocked`) so a shot never sits behind a wall, and a shot that loses sight of
## the subject cuts early.

## Each shot: [bearing off the subject's forward (deg), distance, height], the
## last two in units of `scale`. Front quarters, sides, a low trailing shot, a high
## wide one. A cut never picks the shot already on screen.
const SHOTS := [
	[35.0, 1.6, 0.35], [-40.0, 1.9, 0.1], [90.0, 1.4, 0.25], [-95.0, 2.2, 0.6],
	[150.0, 1.7, 0.05], [-160.0, 2.4, 1.3], [0.0, 2.6, 0.5], [120.0, 2.8, 1.8],
]

var shot_time := 4.0       ## seconds a shot holds before the next cut
var scale := 3.5           ## metres per shot unit
var lead := 0.8            ## how fast the camera drifts after the subject (1/s)
var aim_ease := 5.0        ## how fast it turns to keep the subject framed (1/s)
var lose_range := 4.5      ## cut early once the subject is this many units away
var max_lag := 1.5         ## units a fast subject may pull ahead of the camera: it follows harder to keep up
## func(from: Vector3, to: Vector3) -> Vector3: how far along from -> to the view
## is clear (to itself when nothing is in the way). Invalid: nothing ever is.
var blocked := Callable()
var xform := Transform3D.IDENTITY
var shot := -1             ## index into SHOTS of the shot on screen
var cuts := 0

var _left := 0.0
var _offset := Vector3()   ## camera - subject, held in world space for the shot
var _pos := Vector3()
var _look := Vector3()
var _hidden := 0.0         ## seconds the subject has been out of sight
var _speed := 0.0          ## the subject's speed, smoothed (m/s)
var _last := Vector3()
var _seen := false
var _timed := false       ## _speed has a first measurement to smooth from
var _rng := RandomNumberGenerator.new()


## The next update cuts to a fresh shot.
func reset() -> void:
	_left = 0.0
	_seen = false
	_timed = false


## Where the camera is this frame. `forward` is the subject's heading (any
## length, any tilt), `up` the ground's up.
func update(dt: float, subject: Vector3, forward: Vector3, up: Vector3 = Vector3.UP) -> Transform3D:
	_left -= dt
	if _seen and dt > 0.0:
		var v := subject.distance_to(_last) / dt
		_speed = lerpf(_speed, v, 1.0 - exp(-8.0 * dt)) if _timed else v
		_timed = true
	_last = subject
	_seen = true
	if _left <= 0.0 or _hidden > 0.5 or _pos.distance_to(subject) > lose_range * scale:
		_cut(subject, forward, up)
	else:
		# A slow subject is trailed on a slack lead; a fast one (a ship, a speeder)
		# would outrun that and cut the shot every second, so the lead tightens
		# until it falls no more than `max_lag` units behind.
		var follow := maxf(lead, _speed / (max_lag * scale))
		_pos = _pos.lerp(subject + _offset, 1.0 - exp(-follow * dt))
		_look = _look.lerp(subject, 1.0 - exp(-maxf(aim_ease, follow * 8.0) * dt))
		if blocked.is_valid():
			var clear: Vector3 = blocked.call(subject, _pos)
			_hidden = _hidden + dt if clear.distance_to(_pos) > 0.3 else 0.0
	var b := _facing(_look - _pos, up)
	xform = Transform3D(b if b != Basis() else xform.basis, _pos)
	return xform


func _cut(subject: Vector3, forward: Vector3, up: Vector3) -> void:
	var fwd := forward - up * forward.dot(up)
	if fwd.length() < 0.001:
		fwd = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	fwd = fwd.normalized()
	# From a random shot on, the first with a clear view; failing that, the one
	# with the most room, pulled in front of whatever is in the way.
	var start := _rng.randi_range(0, SHOTS.size() - 1)
	var pick := -1
	var at := Vector3()
	var room := -1.0
	for k in SHOTS.size():
		var i := (start + k) % SHOTS.size()
		if i == shot:
			continue
		var s: Array = SHOTS[i]
		var want: Vector3 = subject + (fwd.rotated(up, deg_to_rad(s[0])) * s[1] + up * s[2]) * scale
		var got: Vector3 = blocked.call(subject, want) if blocked.is_valid() else want
		if got.distance_to(want) < 0.05:
			pick = i
			at = want
			break
		if subject.distance_to(got) > room:
			room = subject.distance_to(got)
			pick = i
			at = got
	shot = pick
	_offset = at - subject
	_pos = at
	_look = subject
	_left = shot_time
	_hidden = 0.0
	cuts += 1


## A basis looking along `dir`, standing on `up`. Basis() when there is no such
## basis (no direction, or straight up or down).
static func _facing(dir: Vector3, up: Vector3) -> Basis:
	if dir.length() < 0.01 or dir.normalized().cross(up).length() < 0.01:
		return Basis()
	return Basis.looking_at(dir, up)
