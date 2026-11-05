class_name BodyAnimator
extends RefCounted
## Procedural animation for the jointed CharacterKit body (M11). Pure math: given
## what the character is doing this frame it returns joint rotations, a pelvis
## height and (for weapons) chest-space hand/weapon targets. No nodes, so the state
## machine and the cycle are unit-tested headless (tests/test_body_animator.gut.gd).
##
## Why procedural and not imported clips: the characters are built from joints by
## CharacterKit (no skinned mesh), and the free CC0 clip libraries ship for a
## humanoid skeleton we do not have. Joint math keeps every character (player,
## cantina owner, troopers later) on one system, and every number is tunable here.
##
## Conventions (CharacterKit): the model faces +Z, its left is +X. Limbs hang along
## local -Y. Positive X rotation on a hip swings the leg BACK; positive on a knee
## bends the shin back; negative on an elbow bends the forearm forward.

enum State { LOCOMOTION, AIRBORNE, LAND }

## Upper body modes. FREE swings the arms; the rest are driven by weapons.
const UPPER_FREE := "free"
const UPPER_AIM := "aim"            ## a blaster: right hand forward, left hand supports
const UPPER_RIFLE := "rifle"
const UPPER_SWORD := "sword"        ## guard / swing / block come from SwordPoses
const UPPER_HOLSTER := "holster"    ## mid weapon swap: weapon_xf comes from the caller

const PELVIS_Y := 0.97
## Issue #133: three gaits. A walk, the run (W held, what used to be the Shift
## sprint) and the Shift sprint. The animation blends by speed, so guards and
## NPCs at their own speeds land somewhere on the same curve.
const WALK_SPEED := 4.0
const RUN_SPEED := 7.0
const SPRINT_SPEED := 10.0
## Metres per full cycle (two steps) at each gait's speed. The walk's step is long
## and unhurried (about 3.8 steps a second) so it no longer reads as a jog.
const WALK_STRIDE := 2.1
const RUN_STRIDE := 3.0
const SPRINT_STRIDE := 4.0

var state := State.LOCOMOTION
var phase := 0.0               ## gait phase, radians
var time := 0.0
var dance_time := 0.0          ## continuous 10-second cantina loop
var perform_time := 0.0        ## issue #261: seconds into a performer's set (ClubMoves)
var land_left := 0.0
var land_time := 0.18
var smoothing := 14.0          ## per second; higher = snappier joints
var pelvis_y := PELVIS_Y
var pelvis_x := 0.0            ## issue #87: side-to-side hip shift (metres, + = model's left)
## Sprint slide (issue #65): 0 = not sliding, 1 = full slide pose. It ramps (on top
## of the joint smoothing) so sprint -> slide -> sprint never pops.
var slide_w := 0.0
var slide_blend_s := 0.14

var _cur: Dictionary = {}      ## joint -> Vector3 degrees (smoothed)
var _last_state := State.LOCOMOTION
var states_seen := {}          ## for tests/traces: every state name entered


## Inputs:
##   speed:       horizontal speed, m/s
##   move_local:  Vector2(x = to the model's left, y = forward), length <= 1
##   grounded:    bool;   vy: vertical velocity
##   crouch / sprint: bool
##   upper:       one of the UPPER_* modes
##   ready:       0..1, how far a gun is raised (1 = aiming, the default; 0 = at rest)
##   aim_pitch:   radians, + is up (aim modes bend the chest toward it)
##   twist:       degrees of chest yaw the caller adds (sword swings)
##   perform:     issue #261: a performer's set ("dj", "drum", "bass"; ClubMoves), at `bpm`
## Returns { joints: {name: Vector3 deg}, pelvis_y: float, pelvis_x: float, state: String,
##   hands / reach: a performer's hands on their instrument (ClubMoves) }
## Issue #540: with `share_out` step returns the same dictionary every call and its
## `joints` is the animator's own (no copy of every joint per step): for a caller
## that reads them at once and changes nothing (NpcBody). Else new ones, as before.
var share_out := false
var _out := {}


func step(dt: float, inp: Dictionary) -> Dictionary:
	time += dt
	var dancing := bool(inp.get("dance", false))
	if dancing:
		dance_time = fposmod(dance_time + dt, DANCE_LOOP_S)
	var performing := str(inp.get("perform", ""))
	if performing != "":
		perform_time += dt
	var grounded: bool = inp.get("grounded", true)
	var vy: float = inp.get("vy", 0.0)
	var speed: float = inp.get("speed", 0.0)
	var crouch: bool = inp.get("crouch", false)

	# ---- state machine
	match state:
		State.LOCOMOTION:
			if not grounded:
				state = State.AIRBORNE
		State.AIRBORNE:
			if grounded:
				state = State.LAND
				land_left = land_time
		State.LAND:
			land_left -= dt
			if not grounded:
				state = State.AIRBORNE
			elif land_left <= 0.0:
				state = State.LOCOMOTION
	states_seen[state_name()] = true
	if state == State.AIRBORNE:
		states_seen["JUMP" if vy > 0.0 else "FALL"] = true

	# ---- gait phase: one full cycle per stride (two steps)
	var stride := stride_for(speed)
	if crouch:
		stride = 0.9
	if state == State.LOCOMOTION and speed > 0.05:
		phase = fmod(phase + TAU * speed / stride * dt, TAU)

	slide_w = move_toward(slide_w, 1.0 if bool(inp.get("slide", false)) and grounded else 0.0, dt / slide_blend_s)
	var target := _target(inp, speed, crouch, vy)
	var k := 1.0 - exp(-smoothing * dt)
	for j in target.joints:
		var v: Vector3 = target.joints[j]
		_cur[j] = (_cur.get(j, v) as Vector3).lerp(v, k)
	pelvis_y = lerpf(pelvis_y, target.pelvis_y, k)
	pelvis_x = lerpf(pelvis_x, target.pelvis_x, k)
	var out := _out if share_out else {}
	out["joints"] = _cur if share_out else _cur.duplicate()
	out["pelvis_y"] = pelvis_y
	out["pelvis_x"] = pelvis_x
	out["state"] = "DANCE" if dancing else ("PERFORM" if performing != "" else state_name())
	out["dance_yaw"] = float(target.get("yaw", 0.0))
	out["hands"] = target.get("hands", {})
	out["reach"] = target.get("reach", {})
	return out


## Issue #133: stride length (one full cycle, metres) for a ground speed.
static func stride_for(speed: float) -> float:
	if speed <= RUN_SPEED:
		return lerpf(WALK_STRIDE, RUN_STRIDE, clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0))
	return lerpf(RUN_STRIDE, SPRINT_STRIDE, clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0))


func state_name() -> String:
	return ["LOCOMOTION", "AIRBORNE", "LAND"][state]


## Every joint the animator owns, so leftovers from a previous pose never stick.
const JOINTS := ["pelvis", "spine", "chest", "neck", "head",
	"l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
	"l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]

## Five playful stage moves of DANCE_SEG_S each, crossfaded over DANCE_BLEND_S, so the
## loop is DANCE_LOOP_S long and closes on its own first pose: hip swirl, a twirl,
## a shimmy and blown kiss, a turn-around bend with a hip shake, and a back-facing
## body roll that spins round to face the audience again.
const DANCE_SEG_S := 4.0
const DANCE_BLEND_S := 0.8
const DANCE_MOVES := 5
const DANCE_LOOP_S := DANCE_SEG_S * DANCE_MOVES


## Move i runs on its own clock: it starts DANCE_BLEND_S before its segment so the
## crossfade out of the previous move already shows it, and every move is tuned to
## begin near upright, facing the audience (or the wall, for the one after the bend).
static func dance_pose(seconds: float) -> Dictionary:
	var t := fposmod(seconds, DANCE_LOOP_S)
	var i := int(t / DANCE_SEG_S) % DANCE_MOVES
	var u := t - float(i) * DANCE_SEG_S
	var cur := _dance_move(i, u + DANCE_BLEND_S)
	var into := u - (DANCE_SEG_S - DANCE_BLEND_S)
	if into <= 0.0:
		return cur
	var nxt := _dance_move((i + 1) % DANCE_MOVES, into)
	var w := _smooth01(into / DANCE_BLEND_S)
	var joints := {}
	for n in JOINTS:
		joints[n] = (cur.joints[n] as Vector3).lerp(nxt.joints[n], w)
	return {
		"joints": joints,
		"pelvis_y": lerpf(cur.pelvis_y, nxt.pelvis_y, w),
		"pelvis_x": lerpf(cur.pelvis_x, nxt.pelvis_x, w),
		"yaw": lerp_angle(cur.yaw, nxt.yaw, w),
	}


static func _dance_move(i: int, s: float) -> Dictionary:
	var j := {}
	for n in JOINTS:
		j[n] = Vector3.ZERO
	var py := PELVIS_Y
	var px := 0.0
	var yaw := 0.0
	match i:
		0:  # hip swirl: slow circles, arms overhead, a cheeky head tilt
			var w := TAU * s / 2.0
			j.pelvis = Vector3(6.0 * cos(w), 12.0 * sin(w + 0.8), 9.0 * sin(w))
			j.spine = Vector3(-3.0 * cos(w), -6.0 * sin(w + 0.8), -5.0 * sin(w))
			j.chest = Vector3(2.0, -8.0 * sin(w + 0.8), -6.0 * sin(w))
			j.head = Vector3(-4.0, 6.0 * sin(w - 0.6), 9.0 * sin(w + 0.9))
			j.l_shoulder = Vector3(-18.0, 0.0, 142.0 + 12.0 * sin(w))
			j.r_shoulder = Vector3(-18.0, 0.0, -142.0 - 12.0 * sin(w + 1.1))
			j.l_elbow = Vector3(-26.0 - 10.0 * sin(w), 0.0, 0.0)
			j.r_elbow = Vector3(-26.0 - 10.0 * sin(w + 1.1), 0.0, 0.0)
			j.l_wrist = Vector3(0.0, 0.0, 14.0 * sin(w * 2.0))
			j.r_wrist = Vector3(0.0, 0.0, -14.0 * sin(w * 2.0))
			j.l_hip = Vector3(-3.0, 0.0, 3.0 + 3.0 * sin(w))
			j.r_hip = Vector3(-3.0, 0.0, -3.0 + 3.0 * sin(w))
			j.l_knee = Vector3(9.0 + 9.0 * maxf(0.0, sin(w)), 0.0, 0.0)
			j.r_knee = Vector3(9.0 + 9.0 * maxf(0.0, -sin(w)), 0.0, 0.0)
			px = 0.05 * sin(w)
			py = PELVIS_Y - 0.02 + 0.015 * cos(w * 2.0)
		1:  # twirl: one hand high, the other on the hip, a full spin and a flourish
			var spin := _smooth01((s - 0.5) / 2.4)
			yaw = TAU * spin
			var bob := sin(TAU * s * 2.0)
			j.pelvis = Vector3(0.0, 5.0 * bob, 4.0 * bob)
			j.chest = Vector3(-3.0, -4.0 * bob, -2.0 * bob)
			j.head = Vector3(-6.0, 0.0, 7.0 * sin(TAU * s / 1.6))
			j.l_shoulder = Vector3(-10.0, 0.0, 155.0 + 8.0 * sin(TAU * s * 1.5))
			j.l_elbow = Vector3(-22.0, 0.0, 0.0)
			j.l_wrist = Vector3(0.0, 0.0, 18.0 * sin(TAU * s * 3.0))
			j.r_shoulder = Vector3(8.0, 0.0, -34.0)
			j.r_elbow = Vector3(-105.0, 0.0, 0.0)
			j.l_hip = Vector3(-4.0, 0.0, 2.0)
			j.r_hip = Vector3(6.0, 0.0, -2.0)
			j.l_knee = Vector3(8.0 + 6.0 * absf(bob), 0.0, 0.0)
			j.r_knee = Vector3(14.0 + 6.0 * absf(bob), 0.0, 0.0)
			j.l_ankle = Vector3(-6.0, 0.0, 0.0)
			j.r_ankle = Vector3(-6.0, 0.0, 0.0)
			py = PELVIS_Y + 0.02 + 0.012 * absf(bob)
		2:  # shimmy: fast shoulders, a beckoning hand and a blown kiss
			var shim := sin(TAU * s * 3.5)
			var kiss := _smooth01((s - 2.2) / 0.5) * (1.0 - _smooth01((s - 3.3) / 0.6))
			var dip := sin(TAU * s * 1.75)
			j.pelvis = Vector3(0.0, -6.0 * dip, 6.0 * dip)
			j.spine = Vector3(2.0, 4.0 * shim * 0.5, 0.0)
			j.chest = Vector3(-2.0, 14.0 * shim, 5.0 * shim)
			j.neck = Vector3(0.0, -4.0 * shim, 0.0)
			j.head = Vector3(-2.0 - 6.0 * kiss, 8.0 * sin(TAU * s / 2.0), -10.0 * kiss + 4.0 * dip)
			j.l_shoulder = Vector3(-38.0 + 6.0 * shim, 0.0, 38.0)
			j.l_elbow = Vector3(-62.0 - 22.0 * sin(TAU * s * 1.5), 0.0, 0.0)
			j.l_wrist = Vector3(0.0, 0.0, 16.0 * sin(TAU * s * 3.0))
			j.r_shoulder = Vector3(-22.0 - 62.0 * kiss, 0.0, -48.0 + 34.0 * kiss - 6.0 * shim)
			j.r_elbow = Vector3(-40.0 - 90.0 * kiss, 0.0, 0.0)
			j.r_wrist = Vector3(0.0, 0.0, -10.0 * kiss)
			j.l_hip = Vector3(-4.0, 0.0, 4.0 + 3.0 * dip)
			j.r_hip = Vector3(-4.0, 0.0, -4.0 + 3.0 * dip)
			j.l_knee = Vector3(12.0 + 10.0 * maxf(0.0, dip), 0.0, 0.0)
			j.r_knee = Vector3(12.0 + 10.0 * maxf(0.0, -dip), 0.0, 0.0)
			px = 0.03 * dip
			py = PELVIS_Y - 0.03 - 0.012 * absf(dip)
		3:  # turn around, bend over and shake it, glancing back at the crowd
			var turn := _smooth01((s - 0.2) / 1.2)
			var fold := _smooth01((s - 1.3) / 0.9)
			var shake := sin(TAU * s * 3.0) * fold
			yaw = PI * turn
			j.pelvis = Vector3(fold * 40.0, 16.0 * shake, 11.0 * shake)
			j.spine = Vector3(fold * 20.0, -8.0 * shake, -4.0 * shake)
			j.chest = Vector3(fold * 24.0, -6.0 * shake, 0.0)
			j.neck = Vector3(-fold * 20.0, 0.0, 0.0)
			j.head = Vector3(-fold * 38.0, 34.0 * fold * sin(TAU * s / 3.2), 6.0 * shake)
			j.l_shoulder = Vector3(-fold * 12.0 - 8.0, 0.0, 14.0 + fold * 6.0)
			j.r_shoulder = Vector3(-fold * 12.0 - 8.0, 0.0, -14.0 - fold * 6.0)
			j.l_elbow = Vector3(-12.0 - fold * 10.0, 0.0, 0.0)
			j.r_elbow = Vector3(-12.0 - fold * 10.0, 0.0, 0.0)
			j.l_hip = Vector3(-fold * 38.0 - 2.0, 0.0, 4.0 + 4.0 * shake)
			j.r_hip = Vector3(-fold * 38.0 - 2.0, 0.0, -4.0 + 4.0 * shake)
			j.l_knee = Vector3(8.0 + fold * 14.0, 0.0, 0.0)
			j.r_knee = Vector3(8.0 + fold * 14.0, 0.0, 0.0)
			j.l_ankle = Vector3(-fold * 6.0, 0.0, 0.0)
			j.r_ankle = Vector3(-fold * 6.0, 0.0, 0.0)
			px = 0.035 * shake
			py = PELVIS_Y - 0.1 * fold
		_:  # back-facing body roll, a hand trailing down a thigh, then round to the front
			var w := TAU * s / 1.6
			var round_up := _smooth01((s - 2.5) / 1.4)
			var open := _smooth01((s - 2.7) / 1.0)
			yaw = PI * (1.0 - round_up)
			j.pelvis = Vector3(16.0 * sin(w + 1.0), 14.0 * sin(w), 5.0 * sin(w + 0.5))
			j.spine = Vector3(14.0 * sin(w + 0.2), -5.0 * sin(w), 0.0)
			j.chest = Vector3(14.0 * sin(w - 0.6), -7.0 * sin(w), 3.0 * sin(w))
			j.neck = Vector3(-8.0 * sin(w - 1.0), 0.0, 0.0)
			j.head = Vector3(-4.0, 46.0 * (1.0 - open) + 6.0 * sin(w), 8.0 * sin(w - 0.8))
			j.l_shoulder = Vector3(lerpf(8.0, -20.0, open), 0.0, lerpf(24.0, 75.0, open))
			j.l_elbow = Vector3(lerpf(-24.0, -20.0, open), 0.0, 0.0)
			j.r_shoulder = Vector3(-14.0, 0.0, lerpf(-150.0, -75.0, open) - 8.0 * sin(w))
			j.r_elbow = Vector3(-28.0, 0.0, 0.0)
			j.r_wrist = Vector3(0.0, 0.0, -12.0 * sin(w * 2.0))
			j.l_hip = Vector3(-6.0 - 8.0 * maxf(0.0, sin(w + 1.0)), 0.0, 4.0)
			j.r_hip = Vector3(-6.0 - 8.0 * maxf(0.0, -sin(w + 1.0)), 0.0, -4.0)
			j.l_knee = Vector3(12.0 + 8.0 * maxf(0.0, sin(w + 1.0)), 0.0, 0.0)
			j.r_knee = Vector3(12.0 + 8.0 * maxf(0.0, -sin(w + 1.0)), 0.0, 0.0)
			px = 0.04 * sin(w)
			py = PELVIS_Y - 0.04 + 0.02 * cos(w * 2.0)
	return { "joints": j, "pelvis_y": py, "pelvis_x": px, "yaw": yaw }


static func _smooth01(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _target(inp: Dictionary, speed: float, crouch: bool, vy: float) -> Dictionary:
	if bool(inp.get("dance", false)):
		return dance_pose(dance_time)
	if str(inp.get("perform", "")) != "":
		return ClubMoves.pose(str(inp.perform), perform_time, float(inp.get("bpm", 110.0)))
	var j := {}
	for n in JOINTS:
		j[n] = Vector3.ZERO
	var py := PELVIS_Y
	var px := 0.0
	var s := sin(phase)
	var c := cos(phase)
	var walk01 := clampf(speed / WALK_SPEED, 0.0, 1.0)
	var run01 := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var dash01 := clampf((speed - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED), 0.0, 1.0)
	var move: Vector2 = inp.get("move_local", Vector2(0, 1))
	if move.length() < 0.01:
		move = Vector2(0, 1)
	move = move.normalized()
	var fwd := move.y          # cos of the move angle in the body frame
	var side := move.x         # + = toward the model's left

	match state:
		State.LOCOMOTION:
			# Issue #133: three gaits on one curve.
			#   walk:   long easy steps, heel first, knees nearly straight, a little
			#           hip sway (issue #87's swagger, toned down) and loose arms.
			#   run:    a light jog; slight lean, the body bounces up between steps
			#           and the arms bend to about 80 degrees.
			#   sprint: a hard forward lean, high knee drive in front, a high kick
			#           behind and arms pumping with the elbows locked near 90.
			var hip_a := 26.0 * walk01 + 18.0 * run01 + 12.0 * dash01
			var drive := (10.0 * run01 + 22.0 * dash01) * maxf(0.0, fwd)
			var knee_a := 40.0 * walk01 + 45.0 * run01 + 30.0 * dash01
			var stance := 5.0 * walk01 + 12.0 * run01
			var strut := walk01 * (1.0 - run01)
			# Legs: swing along the move direction (backwards walking reverses it); the
			# leg in front lifts a little higher as the pace picks up.
			j.l_hip = Vector3(-hip_a * s * fwd - drive * maxf(0.0, s), 0, 14.0 * walk01 * s * side + 2.0)
			j.r_hip = Vector3(hip_a * s * fwd - drive * maxf(0.0, -s), 0, 14.0 * walk01 * s * side - 2.0)
			j.l_knee = Vector3(knee_a * maxf(0.0, c) + stance, 0, 0)
			j.r_knee = Vector3(knee_a * maxf(0.0, -c) + stance, 0, 0)
			j.l_ankle = Vector3(-0.35 * j.l_knee.x + 10.0 * walk01 * s * fwd, 0, 0)
			j.r_ankle = Vector3(-0.35 * j.r_knee.x - 10.0 * walk01 * s * fwd, 0, 0)
			# Hips: a walk is highest over the planted foot and dips between steps; a
			# run is lowest mid-stance (knee taking the load) and rises into the flight.
			py = PELVIS_Y - 0.022 * strut * s * s - 0.035 * run01 * (1.0 - s * s) \
				- 0.02 * run01 - 0.03 * dash01
			px = -0.026 * strut * s
			j.pelvis = Vector3(0, -8.0 * walk01 * s, -4.0 * strut * s)
			j.spine = Vector3(8.0 * run01 + 12.0 * dash01, 0, 2.0 * strut * s)
			j.chest = Vector3(3.0 * walk01 + 4.0 * run01 + 6.0 * dash01, 11.0 * walk01 * s, 1.5 * strut * s)
			j.head = Vector3(-3.0 * walk01 - 6.0 * run01 - 12.0 * dash01, -3.0 * walk01 * s, 2.0 * strut * s)
			# Arms counter-swing the legs: loose from the shoulder on a walk (the
			# forearm swings up a touch on the way forward), bent on the run, pumping
			# hard on the sprint.
			var arm_a := 24.0 * walk01 + 18.0 * run01 + 30.0 * dash01
			var bend := 18.0 * strut
			var elbow := -14.0 - 8.0 * walk01 - 55.0 * run01 - 20.0 * dash01
			var arm_out := 9.0 + 3.0 * strut - 3.0 * dash01
			j.l_shoulder = Vector3(arm_a * s, 4.0 * strut * s, arm_out)
			j.r_shoulder = Vector3(-arm_a * s, 4.0 * strut * s, -arm_out)
			j.l_elbow = Vector3(elbow - bend * maxf(0.0, -s), 0, 0)
			j.r_elbow = Vector3(elbow - bend * maxf(0.0, s), 0, 0)
			j.l_wrist = Vector3(-6.0 * walk01, 0, 0)
			j.r_wrist = Vector3(-6.0 * walk01, 0, 0)
			# Idle: breathe, shift the weight from foot to foot and glance around.
			var idle := 1.0 - walk01
			var sway := sin(time * 0.55)
			j.chest.x += idle * 1.5 * sin(time * 1.7)
			j.l_shoulder.z += idle * 0.8 * sin(time * 1.7)
			j.r_shoulder.z -= idle * 0.8 * sin(time * 1.7)
			px += idle * 0.018 * sway
			j.pelvis.z += idle * 2.5 * sway
			j.chest.z -= idle * 2.0 * sway
			j.l_knee.x += idle * 5.0 * maxf(0.0, -sway)
			j.r_knee.x += idle * 5.0 * maxf(0.0, sway)
			j.head.y += idle * 14.0 * sin(time * 0.31) * sin(time * 0.17)
			j.head.x += idle * 3.0 * sin(time * 0.23)
			if crouch:
				var pose := _crouch(inp, speed, s, c, fwd)
				for n in pose.joints:
					j[n] = pose.joints[n]
				py = pose.pelvis_y
				px = 0.0
		State.AIRBORNE:
			# Tucked on the way up, legs reaching for the ground and arms out on the
			# way down; a running jump splits the legs into a leap.
			var up01 := clampf(vy / 5.0, 0.0, 1.0)
			var down01 := clampf(-vy / 6.0, 0.0, 1.0)
			var leap := clampf(speed / WALK_SPEED, 0.0, 1.0)
			j.l_hip = Vector3(-30.0 - 25.0 * up01 - 25.0 * leap, 0, 5)
			j.r_hip = Vector3(-5.0 - 15.0 * up01 + 30.0 * leap - 10.0 * down01, 0, -5)
			j.l_knee = Vector3(30.0 + 50.0 * up01 - 15.0 * down01, 0, 0)
			j.r_knee = Vector3(25.0 + 30.0 * up01 + 35.0 * leap - 10.0 * down01, 0, 0)
			j.l_ankle = Vector3(-15.0 + 10.0 * down01, 0, 0)
			j.r_ankle = Vector3(10.0 * leap, 0, 0)
			j.l_shoulder = Vector3(-35.0 * up01 + 20.0 * leap, 0, 25.0 + 30.0 * down01)
			j.r_shoulder = Vector3(-35.0 * up01 - 30.0 * leap, 0, -25.0 - 30.0 * down01)
			j.l_elbow = Vector3(-40.0 + 15.0 * down01, 0, 0)
			j.r_elbow = Vector3(-50.0 + 15.0 * down01, 0, 0)
			j.spine = Vector3(6.0 * leap, 0, 0)
			j.chest = Vector3(10.0 * up01 - 4.0 * down01, 0, 0)
			j.head = Vector3(-6.0 + 10.0 * down01, 0, 0)
		State.LAND:
			var dip := clampf(land_left / land_time, 0.0, 1.0)
			j.l_hip = Vector3(-35.0 * dip, 0, 3)
			j.r_hip = Vector3(-30.0 * dip, 0, -3)
			j.l_knee = Vector3(60.0 * dip, 0, 0)
			j.r_knee = Vector3(55.0 * dip, 0, 0)
			j.l_ankle = Vector3(-25.0 * dip, 0, 0)
			j.r_ankle = Vector3(-25.0 * dip, 0, 0)
			j.chest = Vector3(12.0 * dip, 0, 0)
			j.l_shoulder = Vector3(0, 0, 20.0 * dip + 6.0)
			j.r_shoulder = Vector3(0, 0, -20.0 * dip - 6.0)
			py = PELVIS_Y - 0.18 * dip

	# ---- sprint slide: lead leg out straight, the other tucked under, torso leaning
	# back, pelvis near the ground, one arm out for balance.
	if slide_w > 0.0 and state == State.LOCOMOTION:
		var sl := {
			"pelvis": Vector3(0, 0, 0), "spine": Vector3(0, 0, 0),
			"chest": Vector3(-22.0, 0, 0), "neck": Vector3(0, 0, 0), "head": Vector3(14.0, 0, 0),
			"l_hip": Vector3(-82.0, 0, 3), "l_knee": Vector3(6.0, 0, 0), "l_ankle": Vector3(-20.0, 0, 0),
			"r_hip": Vector3(-30.0, 0, -6), "r_knee": Vector3(115.0, 0, 0), "r_ankle": Vector3(-25.0, 0, 0),
			"l_shoulder": Vector3(-30.0, 0, 20.0), "l_elbow": Vector3(-35.0, 0, 0), "l_wrist": Vector3.ZERO,
			"r_shoulder": Vector3(-10.0, 0, -75.0), "r_elbow": Vector3(-10.0, 0, 0), "r_wrist": Vector3.ZERO,
		}
		for n in sl:
			j[n] = (j[n] as Vector3).lerp(sl[n], slide_w)
		py = lerpf(py, PELVIS_Y - 0.5, slide_w)
		px = lerpf(px, 0.0, slide_w)

	# ---- upper body overrides for weapons. Arms are placed by IK afterwards
	# (player_avatar.gd, npc_body.gd), so here we only shape the torso. Issue #87:
	# "ready" is how far the weapon is up (1 = aimed, 0 = resting low), so a body
	# at rest keeps its walk's swagger and only squares up to aim.
	var upper: String = inp.get("upper", UPPER_FREE)
	var ready := clampf(float(inp.get("ready", 1.0)), 0.0, 1.0)
	var pitch_deg := rad_to_deg(float(inp.get("aim_pitch", 0.0)))
	if upper != UPPER_FREE:
		# Stop the walk's shoulder twist so the weapon stays on the aim line.
		# At rest a two-handed carry still damps the twist, or the gun swings about.
		j.pelvis.y *= lerpf(0.7, 0.3, ready)
		j.chest.y *= lerpf(0.35, 0.0, ready)
		j.head.y *= 1.0 - ready
	match upper:
		UPPER_AIM, UPPER_RIFLE:
			j.chest.x = lerpf(j.chest.x * 0.6 + 2.0, -pitch_deg * 0.55 + 4.0, ready)
			j.head.x = lerpf(j.head.x, -pitch_deg * 0.35, ready)
			j.spine.y = (-8.0 if upper == UPPER_AIM else -14.0) * ready
		UPPER_SWORD, UPPER_HOLSTER:
			j.chest.x = j.chest.x * 0.5 - pitch_deg * 0.3 + 6.0
			j.head.x = -pitch_deg * 0.3
	j.chest.y += float(inp.get("twist", 0.0))
	if slide_w > 0.0 and upper != UPPER_FREE:
		j.chest.x -= 14.0 * slide_w  # weapon up: still lean back, the aim pass keeps the hands
	return { "joints": j, "pelvis_y": py, "pelvis_x": px }


## Issue #87: crouched. Still, down on the right knee with the left foot planted
## ahead; moving, a low duck walk (deep knees, short steps, torso forward). Leg
## angles are set so the feet and the knee land on the ground for CharacterKit's
## 0.46 / 0.43 m thigh and shin.
func _crouch(_inp: Dictionary, speed: float, s: float, c: float, fwd: float) -> Dictionary:
	var kneel := {
		"pelvis": Vector3(0, 6, 0), "spine": Vector3(4, 0, 0), "chest": Vector3(6, -4, 0), "head": Vector3(-6, 0, 0),
		"l_hip": Vector3(-86, 0, 8), "l_knee": Vector3(88, 0, 0), "l_ankle": Vector3(-2, 0, 0),
		"r_hip": Vector3(2, 0, -6), "r_knee": Vector3(92, 0, 0), "r_ankle": Vector3(-25, 0, 0),
		"l_shoulder": Vector3(-14, 0, 6), "l_elbow": Vector3(-55, 0, 0), "l_wrist": Vector3.ZERO,
		"r_shoulder": Vector3(4, 0, -10), "r_elbow": Vector3(-20, 0, 0), "r_wrist": Vector3.ZERO,
	}
	var step_a := 18.0 * fwd
	var duck := {
		"pelvis": Vector3(0, -5.0 * s, 0), "spine": Vector3(10, 0, 0), "chest": Vector3(16, 5.0 * s, 0), "head": Vector3(-18, 0, 0),
		"l_hip": Vector3(-58.0 - step_a * s, 0, 8), "l_knee": Vector3(92.0 + 14.0 * maxf(0.0, c), 0, 0),
		"l_ankle": Vector3(-34.0, 0, 0),
		"r_hip": Vector3(-58.0 + step_a * s, 0, -8), "r_knee": Vector3(92.0 + 14.0 * maxf(0.0, -c), 0, 0),
		"r_ankle": Vector3(-34.0, 0, 0),
		"l_shoulder": Vector3(14.0 * s - 10.0, 0, 14), "l_elbow": Vector3(-40, 0, 0), "l_wrist": Vector3.ZERO,
		"r_shoulder": Vector3(-14.0 * s - 10.0, 0, -14), "r_elbow": Vector3(-40, 0, 0), "r_wrist": Vector3.ZERO,
	}
	var m := clampf(speed / 1.2, 0.0, 1.0)
	var j := {}
	for n in kneel:
		j[n] = (kneel[n] as Vector3).lerp(duck[n], m)
	var py := lerpf(PELVIS_Y - 0.44, PELVIS_Y - 0.31 - 0.02 * s * s, m)
	return { "joints": j, "pelvis_y": py }
