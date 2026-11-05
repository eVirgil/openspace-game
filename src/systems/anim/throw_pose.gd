class_name ThrowPose
extends RefCounted
## Issue #372: the overarm throw, kept pure so it is testable headless. The hands
## are points in the character's chest space (metres: +X the left, +Y up, +Z ahead;
## the right shoulder is at (-0.22, 0.18, 0)) that the avatar reaches with its arm IK.
##
## Holding the throw key the right hand winds back behind the shoulder with the
## grenade in it and the left hand points ahead at the target. Letting go swings
## the right hand up over the shoulder, forward through the release and down into
## the follow-through over `swing_s`; the grenade leaves the hand at `release_at`
## of the swing. Then the arms blend back to whatever they were doing over `blend_s`.
##
## spec: content/look/hand_weapons.json "throw".

const DEFAULTS := {
	"wind": [-0.26, 0.36, -0.32],
	"over": [-0.22, 0.50, 0.06],
	"release": [-0.12, 0.30, 0.50],
	"follow": [0.04, -0.10, 0.36],
	"left": [0.10, 0.10, 0.50],
	"swing_s": 0.32,
	"release_at": 0.4,
	"blend_s": 0.15,
}


## The throw block with missing keys filled in.
static func spec(look: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var t = look.get("throw", {})
	if t is Dictionary:
		out.merge(t, true)
	return out


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


## Where the right hand is `s` seconds into the swing (s < 0: wound up, holding).
static func right_hand(sp: Dictionary, s: float) -> Vector3:
	if s < 0.0:
		return _v(sp.wind)
	var u := clampf(s / maxf(0.01, float(sp.swing_s)), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var keys := [_v(sp.wind), _v(sp.over), _v(sp.release), _v(sp.follow)]
	# Three legs, the middle one (over the shoulder to the release) the fastest.
	var cuts := [0.0, 0.3, float(sp.release_at) + 0.15, 1.0]
	for i in 3:
		if e <= float(cuts[i + 1]) or i == 2:
			var k := clampf((e - float(cuts[i])) / maxf(0.001, float(cuts[i + 1]) - float(cuts[i])), 0.0, 1.0)
			return (keys[i] as Vector3).lerp(keys[i + 1], k)
	return _v(sp.follow)


static func left_hand(sp: Dictionary) -> Vector3:
	return _v(sp.left)


## How much the throw owns the arms (0..1): eased in while holding (`held_s` since
## the key went down), full through the swing, eased out after it. `s` is seconds
## since letting go (< 0: still holding).
static func weight(sp: Dictionary, held_s: float, s: float) -> float:
	var b := maxf(0.01, float(sp.blend_s))
	if s < 0.0:
		return clampf(held_s / b, 0.0, 1.0)
	var over := s - float(sp.swing_s)
	if over <= 0.0:
		return 1.0
	return clampf(1.0 - over / b, 0.0, 1.0)


## Whether the grenade is still in the hand `s` seconds into the swing.
static func in_hand(sp: Dictionary, s: float) -> bool:
	return s < float(sp.swing_s) * float(sp.release_at)


## Seconds from letting go to the grenade leaving the hand.
static func release_delay(sp: Dictionary) -> float:
	return float(sp.swing_s) * float(sp.release_at)


## Whether the throw is over (blended out).
static func done(sp: Dictionary, s: float) -> bool:
	return s >= float(sp.swing_s) + float(sp.blend_s)
