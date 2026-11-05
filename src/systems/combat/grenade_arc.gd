class_name GrenadeArc
extends RefCounted
## Issue #372: the grenade's flight, kept pure so the dotted preview and the thrown
## grenade use one function and the grenade lands where the dots end.
##
## A step is semi-implicit Euler at a fixed dt under the planet's own gravity
## (`up_at`: the ground's up at a point, straight up on a flat world). The preview
## traces steps until the first thing it would touch; the grenade runs the same
## steps one physics tick at a time and bounces where it touches.

const DT := 1.0 / 60.0


## The throw: `aim` (where the camera looks) lifted by `lift_deg` toward `up`, at `speed`.
static func launch_velocity(aim: Vector3, up: Vector3, speed: float, lift_deg: float) -> Vector3:
	var d := aim.normalized()
	var side := d.cross(up)
	if side.length() > 0.001:
		d = d.rotated(side.normalized(), deg_to_rad(lift_deg))
	return d.normalized() * speed


## One step: velocity under gravity first, then position. Returns [pos, vel].
static func step(pos: Vector3, vel: Vector3, up: Vector3, gravity: float, dt: float) -> Array:
	var v := vel - up.normalized() * gravity * dt
	return [pos + v * dt, v]


## Off a surface with normal `n`: the part into it comes back at `bounce`, the part
## along it keeps `slide` of its speed.
static func bounce(vel: Vector3, n: Vector3, bounce_k: float, slide: float) -> Vector3:
	var nn := n.normalized()
	var into := vel.dot(nn)
	if into >= 0.0:
		return vel
	var normal := nn * into
	var along := vel - normal
	return along * slide - normal * bounce_k


## The path from `from` at `vel`, `dt` a step, out to `max_s` seconds. `hit` is
## (a: Vector3, b: Vector3) -> Dictionary (a ray from a to b: { position, normal, ... },
## {} for nothing); `up_at` is (p) -> Vector3. Returns { points, landed, at, normal, hit }:
## points every step up to where it lands (or the last step), `landed` whether it touched.
static func trace(from: Vector3, vel: Vector3, gravity: float, up_at: Callable, hit: Callable,
		max_s := 6.0, dt := DT) -> Dictionary:
	var pts: Array = [from]
	var p := from
	var v := vel
	var t := 0.0
	while t < max_s:
		var up: Vector3 = up_at.call(p) if up_at.is_valid() else Vector3.UP
		var s := step(p, v, up, gravity, dt)
		var q: Vector3 = s[0]
		var h: Dictionary = hit.call(p, q) if hit.is_valid() else {}
		if not h.is_empty():
			pts.append(h.position)
			return { "points": pts, "landed": true, "at": h.position, "normal": h.get("normal", up), "hit": h }
		p = q
		v = s[1]
		pts.append(p)
		t += dt
	return { "points": pts, "landed": false, "at": p, "normal": Vector3.UP, "hit": {} }
