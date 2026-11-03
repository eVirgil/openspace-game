extends RefCounted
## Projectile field (M10). Pure: every bolt and seeker in flight, advanced each frame
## and swept against ship hit spheres. Ship bolts move hundreds of metres a second,
## so a hit is a segment-vs-sphere test over the frame's travel, not a point check;
## that keeps fast bolts from tunnelling through a fighter between frames.
##
## The live scene draws one mesh per entry by its `uid`; the headless trace only
## reads the hits. One implementation, two consumers -- the M2/M5 pattern.

var items: Array = []   ## each: { uid, kind, pos, prev, vel, speed, damage, range_left,
						##         team, owner, homing, turn_rate, target_id, weapon_id,
						##         splash_radius, splash_damage, blast_size, ghost? }
var _next_uid := 1


func add(spawn: Dictionary, owner_id: int, team: String) -> int:
	var uid := _next_uid
	_next_uid += 1
	var pos: Vector3 = spawn.get("origin", Vector3.ZERO)
	var vel: Vector3 = spawn.get("velocity", Vector3.FORWARD)
	items.append({
		"uid": uid,
		"kind": str(spawn.get("kind", "bolt")),
		"weapon_id": str(spawn.get("weapon_id", "")),
		"pos": pos,
		"prev": pos,
		"vel": vel,
		"speed": vel.length(),
		"damage": float(spawn.get("damage", 10.0)),
		"range_left": float(spawn.get("range", 800.0)),
		"team": team,
		"owner": owner_id,
		"homing": bool(spawn.get("homing", false)),
		"turn_rate": float(spawn.get("turn_rate", 0.0)),
		"target_id": int(spawn.get("target_id", -1)),
		"splash_radius": float(spawn.get("splash_radius", 0.0)),
		"splash_damage": float(spawn.get("splash_damage", 0.0)),
		"blast_size": float(spawn.get("blast_size", 0.0)),
	})
	return uid


func count() -> int:
	return items.size()


## Advance every projectile and return the hits this frame.
## `targets` is an Array of { id, team, position, radius, alive }.
## Each hit: { uid, kind, weapon_id, owner, team, target_id, damage, point,
## splash_radius, splash_damage, blast_size }.
func step(dt: float, targets: Array) -> Array:
	var hits: Array = []
	var by_id := {}
	for t in targets:
		by_id[int(t.id)] = t
	var keep: Array = []
	for p in items:
		# Seekers turn toward their target, limited by turn_rate (radians/second).
		if p.homing and by_id.has(p.target_id) and by_id[p.target_id].alive:
			var tpos: Vector3 = by_id[p.target_id].position
			var want: Vector3 = (tpos - p.pos).normalized()
			var cur: Vector3 = (p.vel as Vector3).normalized()
			var ang := cur.angle_to(want)
			if ang > 0.0001:
				var w := minf(1.0, p.turn_rate * dt / ang)
				cur = cur.slerp(want, w).normalized()
			p.vel = cur * p.speed
		p.prev = p.pos
		var step_v: Vector3 = p.vel * dt
		p.pos = p.prev + step_v
		p.range_left -= step_v.length()
		var hit := false
		var ghost: bool = p.get("ghost", false)    # LAN: another game's shot, a picture (NetFight)
		for t in ([] if ghost else targets):
			if not t.alive or str(t.team) == p.team or int(t.id) == p.owner:
				continue
			if segment_hits_sphere(p.prev, p.pos, t.position, float(t.radius)):
				hits.append({
					"uid": p.uid, "kind": p.kind, "weapon_id": p.weapon_id,
					"owner": p.owner, "team": p.team, "target_id": int(t.id),
					"damage": p.damage, "point": closest_point(p.prev, p.pos, t.position),
					"splash_radius": p.splash_radius, "splash_damage": p.splash_damage,
					"blast_size": p.blast_size,
				})
				hit = true
				break
		if not hit and p.range_left > 0.0:
			keep.append(p)
	items = keep
	return hits


static func closest_point(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a
	var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
	return a + ab * t


static func segment_hits_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	return closest_point(a, b, c).distance_squared_to(c) <= r * r
