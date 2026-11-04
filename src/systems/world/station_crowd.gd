extends Node3D
## Issue #315: the space station's crowd. About 80 people (the config's "crowd"
## block) who walk the walkways, go down the alleys and aisles to stand at a stall,
## a booth or a shack door, look into the open rooms, ride the elevators and cross
## the tunnels between the towers.
##
## They are puppets, the party barge's way (PartyBarge): a kit body (CharacterKit,
## the "station_local" look) moved by script along paths in the station's own frame,
## with a capsule bolts and blades find (CrowdHit), and no physics body, navmesh or
## brain while all is calm. Hurt one and the nearest armed ones are swapped where
## they stand for real locals (NpcBody, the "fighter" profile) run by a Townsfolk of
## the station's own, one a tick; once the alarm is down they are puppets again. The
## dead fall as ragdolls and are back after respawn_s seconds of play.
##
## The render rules (docs/station/STATION_FILL.md) for people:
##   - built one a frame, once the camera first comes within build_within
##   - drawn only within people_m of the camera and show_dy of its height (the floor
##     you are on and the ones just above and below, like the fill)
##   - their joints are not run per person: one walk cycle is sampled once into a
##     table (CYCLE frames) and each walker reads its frame from it
##   - at most anim_budget bodies are posed a frame, nearest first: every frame
##     within anim_near_m, every fourth out to anim_far_m, frozen past that
##   - only those within shadow_m cast a shadow
## Pure paths: every point is in the station's frame (StationHull's), y the floor's.

const BodyAnimatorT := preload("res://src/systems/anim/body_animator.gd")
const LAYER_ENEMIES := 1 << 3
const CYCLE := 24
const UP := Vector3.UP

var station                         ## SpaceStation
var demo                            ## town_demo.gd
var hull: StationHull
var cfg: Dictionary = {}            ## the station config's "crowd" block
var people: Array = []              ## one Dictionary a person (see _add)
var rides := 0                      ## elevator rides finished (traces, tests)
var crossings := 0                  ## tunnels crossed (traces, tests)
var stops := 0                      ## times someone stood at a stall, booth, door or room (traces)
var kills := 0
var posed := 0                      ## bodies posed last frame (review)
var cost_ms := 0.0                  ## this node's own time a frame, smoothed (review)
var built := false

var _rng := RandomNumberGenerator.new()
var _walk: Array = []               ## CYCLE frames of the walk: { joints: { name: Vector3 deg }, pelvis_y }
var _stand: Dictionary = {}
var _queue: Array = []              ## people still to build (look ids)
var _frame := 0
var _folk                           ## Townsfolk running the fighters (made when first provoked)
var _rousing: Array = []
var _calm_t := 0.0
var _cam_local := Vector3.INF


func setup(space_station, town_demo, station_hull: StationHull) -> void:
	station = space_station
	demo = town_demo
	hull = station_hull
	cfg = hull.cfg.get("crowd", {})
	name = "Crowd"
	_rng.seed = int(cfg.get("seed", 315))


func _ready() -> void:
	_sample_cycle()
	var floors: Dictionary = cfg.get("floors", {})
	for fid in floors:
		for k in int(floors[fid]):
			_queue.append(str(fid))


# ------------------------------------------------------------------ the walk cycle

## The walk, sampled once: BodyAnimator stepped at a walking pace until it settles,
## then a frame each CYCLE-th of a stride. Standing is one more frame at rest.
func _sample_cycle() -> void:
	var anim := BodyAnimatorT.new()
	var speed := 1.4
	var inp := { "speed": speed, "move_local": Vector2(0, 1), "grounded": true, "upper": BodyAnimatorT.UPPER_FREE }
	for i in 240:
		anim.step(1.0 / 120.0, inp)
	_walk = []
	_walk.resize(CYCLE)
	var got := 0
	var guard := 0
	while got < CYCLE and guard < 20000:
		var out: Dictionary = anim.step(1.0 / 480.0, inp)
		var k := int(floor(anim.phase / TAU * CYCLE)) % CYCLE
		if _walk[k] == null:
			_walk[k] = { "joints": out.joints, "pelvis_y": float(out.pelvis_y) }
			got += 1
		guard += 1
	for k in CYCLE:
		if _walk[k] == null:
			_walk[k] = _walk[(k + CYCLE - 1) % CYCLE] if _walk[(k + CYCLE - 1) % CYCLE] != null else { "joints": {}, "pelvis_y": BodyAnimatorT.PELVIS_Y }
	var rest := BodyAnimatorT.new()
	var still := { "speed": 0.0, "move_local": Vector2.ZERO, "grounded": true, "upper": BodyAnimatorT.UPPER_FREE }
	var o: Dictionary = {}
	for i in 120:
		o = rest.step(1.0 / 60.0, still)
	_stand = { "joints": o.joints, "pelvis_y": float(o.pelvis_y) }


# ------------------------------------------------------------------ building

func _add(floor_id: String) -> void:
	var t := {}
	var fi := -1
	for tw in hull.towers:
		for i in (tw.floors as Array).size():
			if str(tw.floors[i].id) == floor_id:
				t = tw
				fi = i
	if fi < 0:
		return
	var f: Dictionary = t.floors[fi]
	var looks: Array = cfg.get("looks", ["station_local"])
	var look := str(looks[_rng.randi() % looks.size()])
	var holder := Node3D.new()
	holder.name = "Person_%d" % people.size()
	add_child(holder)
	var body: Node3D
	if demo != null and bool(demo.get("use_look")) and demo.has_method("_kit"):
		body = demo._kit().build(look, "walker")
	else:
		body = Node3D.new()                 # headless: a stand-in that still walks
		body.name = "Stand"
	holder.add_child(body)
	holder.visible = false              # shown once it is near the camera (_process)
	var c: Vector2 = t.c
	var rw := hull.gap_r + 1.5 + _rng.randf() * (hull.walk - 3.0)
	var a := _rng.randf() * TAU
	var sp: Array = cfg.get("speed", [1.1, 1.6])
	var p := { "node": holder, "body": body, "look": look, "tower": t, "fi": fi, "rw": rw,
		"pos": Vector3(c.x + cos(a) * rw, float(f.y), c.y + sin(a) * rw), "yaw": _rng.randf() * TAU,
		"speed": _rng.randf_range(float(sp[0]), float(sp[1])), "phase": _rng.randf() * TAU, "moving": false,
		"legs": [], "hp": float(cfg.get("person_hp", 60)), "dead": false, "back_at": 0.0, "fighter": null,
		"ragdoll": null, "armed": _rng.randf() < float(cfg.get("armed_share", 0.5)), "shown": false, "shadow": true,
		"meshes": body.find_children("*", "GeometryInstance3D", true, false), "home": floor_id, "rest": body.transform }
	p.hit = _hit_for(p)
	people.append(p)
	_place(p)


## Something bolts and blades find: a capsule where the person stands.
func _hit_for(p: Dictionary) -> StaticBody3D:
	var hit := CrowdHit.new()
	hit.crowd = self
	hit.who = p
	hit.name = "Hit_" + str((p.node as Node).name)
	hit.collision_layer = 0
	hit.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	hit.add_child(cs)
	add_child(hit)
	return hit


# ------------------------------------------------------------------ each frame

func _process(dt: float) -> void:
	if station == null or hull == null:
		return
	var t0 := Time.get_ticks_usec()
	_frame_work(dt)
	cost_ms = lerpf(cost_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.05)


func _frame_work(dt: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_cam_local = station.inv * cam.global_position if cam != null else Vector3.INF
	if not built:
		if _cam_local != Vector3.INF and _cam_local.length() > float(cfg.get("build_within", 900.0)):
			return
		if not _queue.is_empty():
			_add(str(_queue.pop_front()))       # one a frame
		else:
			built = true
	_frame += 1
	_tick_fight(dt)
	var due: Array = []
	var show_dy := float(cfg.get("show_dy", 30.0))
	var people_m := float(cfg.get("people_m", 100.0))
	var near := float(cfg.get("anim_near_m", 25.0))
	var far := float(cfg.get("anim_far_m", 60.0))
	var shadow_m := float(cfg.get("shadow_m", 20.0))
	for i in people.size():
		var p: Dictionary = people[i]
		if p.dead:
			_fall(p, dt)
			if WorldState.clock >= float(p.back_at):
				_respawn(p)
			continue
		if p.fighter != null:
			continue
		_step(p, dt)
		var d := (p.pos as Vector3).distance_to(_cam_local) if _cam_local != Vector3.INF else 0.0
		var show := absf((p.pos as Vector3).y - _cam_local.y) <= show_dy and d <= people_m if _cam_local != Vector3.INF else true
		if show != bool(p.shown):
			p.shown = show
			(p.node as Node3D).visible = show
			(p.hit as CrowdHit).collision_layer = LAYER_ENEMIES if show else 0
		if not show:
			continue
		_place(p)
		var cast := d <= shadow_m
		if cast != bool(p.shadow):
			p.shadow = cast
			for m in p.meshes:
				if is_instance_valid(m):
					(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if d <= near or (d <= far and (_frame + i) % 4 == 0):
			due.append([d, p])
	due.sort_custom(func(x, y): return x[0] < y[0])
	posed = mini(due.size(), int(cfg.get("anim_budget", 16)))
	for k in posed:
		_pose(due[k][1])


func _place(p: Dictionary) -> void:
	var n := p.node as Node3D
	n.position = p.pos
	n.rotation = Vector3(0, float(p.yaw), 0)
	(p.hit as Node3D).position = p.pos


## The walk cycle's frame for this person's stride, or standing; then the skin.
func _pose(p: Dictionary) -> void:
	var body: Node3D = p.body
	if not body.has_meta("joints"):
		return
	var fr: Dictionary = _walk[int(float(p.phase) / TAU * CYCLE) % CYCLE] if bool(p.moving) else _stand
	var joints: Dictionary = body.get_meta("joints")
	var jr: Dictionary = fr.joints
	for jn in jr:
		var j = joints.get(jn)
		if j != null:
			(j as Node3D).rotation_degrees = jr[jn]
	if joints.has("pelvis"):
		(joints.pelvis as Node3D).position.y = float(fr.pelvis_y)
	var skins: Array = body.get_meta("skins", [])
	if not skins.is_empty():
		skins[0].sync(body)


# ------------------------------------------------------------------ walking

## One frame of a person: on with what they are doing, or plan what is next.
func _step(p: Dictionary, dt: float) -> void:
	var legs: Array = p.legs
	if legs.is_empty():
		_plan(p)
		return
	var act: Dictionary = legs[0]
	p.moving = false
	match str(act.kind):
		"go":
			if _go(p, act, dt):
				legs.pop_front()
		"wait":
			act.t = float(act.t) - dt
			if act.has("face"):
				p.yaw = lerp_angle(float(p.yaw), float(act.face), minf(1.0, dt * 4.0))
			if float(act.t) <= 0.0:
				legs.pop_front()
		"board":
			_board(p, act, dt)
		"ride":
			_ride(p, act, dt)
		"floor":
			p.tower = act.tower
			p.fi = int(act.fi)
			if bool(act.get("crossed", false)):
				crossings += 1
			legs.pop_front()
		"stood":
			stops += 1
			legs.pop_front()
		_:
			legs.pop_front()


## Along a polyline; true at its end.
func _go(p: Dictionary, act: Dictionary, dt: float) -> bool:
	var pts: Array = act.pts
	var i := int(act.get("i", 0))
	var left := float(p.speed) * (2.0 if bool(act.get("fast", false)) else 1.0) * dt
	var pos: Vector3 = p.pos
	while i < pts.size() and left > 0.0:
		var to: Vector3 = pts[i]
		var dv := to - pos
		var dist := Vector3(dv.x, 0, dv.z).length()
		if dist <= left:
			pos = to
			left -= dist
			i += 1
			continue
		var step := dv * (left / maxf(dist, 0.0001))
		pos += step
		p.yaw = atan2(step.x, step.z)
		left = 0.0
	var moved := pos.distance_to(p.pos)
	p.pos = pos
	act.i = i
	if moved > 0.0001:
		p.moving = true
		p.phase = fposmod(float(p.phase) + TAU * moved / BodyAnimatorT.WALK_STRIDE, TAU)
	return i >= pts.size()


## Waiting by the shaft for the car to stop at this floor, then in.
func _board(p: Dictionary, act: Dictionary, dt: float) -> void:
	var car: Dictionary = station.cars[int(act.car)]
	var c: Vector2 = car.c
	var inside := Vector2((p.pos as Vector3).x - c.x, (p.pos as Vector3).z - c.y).length() <= float(hull.cfg.get("elevator", {}).get("car_radius", 4.5)) - 0.4
	var here := not bool(car.moving) and int(car.i) == int(act.fi)
	if bool(act.get("going", false)):
		if not here and not inside:
			act.going = false                  # it left without them: back to the door
			act.go = { "kind": "go", "pts": [act.wait_at] }
		elif _go(p, act.go, dt):
			p.legs.pop_front()                 # aboard: the ride is next
		return
	if act.has("go") and not _go(p, act.go, dt):
		return
	act.erase("go")
	p.yaw = atan2(c.x - (p.pos as Vector3).x, c.y - (p.pos as Vector3).z)
	if here and float(car.wait) > 1.6:
		act.going = true
		act.go = { "kind": "go", "pts": [act.in_at], "fast": true }


## On the car to floor `to`, then out by that floor's nearest bridge.
func _ride(p: Dictionary, act: Dictionary, _dt: float) -> void:
	var car: Dictionary = station.cars[int(act.car)]
	var pos: Vector3 = p.pos
	pos.y = float(car.at)
	p.pos = pos
	if bool(car.moving) or int(car.i) != int(act.to) or float(car.wait) < 2.0:
		return
	var t: Dictionary = p.tower
	var fi := int(act.to)
	var y := float(t.floors[fi].y)
	var c: Vector2 = t.c
	var a := atan2(pos.z - c.y, pos.x - c.x)
	var b := _nearest(StationHull.bridge_angles(fi), a)
	p.fi = fi
	rides += 1
	p.legs.pop_front()
	p.legs.push_front({ "kind": "go", "pts": [_pt(c, y, hull.shaft_r + 0.7, b), _pt(c, y, float(p.rw), b)], "fast": true })


## What next: stand at a stall or a door, ride an elevator, cross a tunnel, or
## stroll on round the walkway.
func _plan(p: Dictionary) -> void:
	var t: Dictionary = p.tower
	var fi := int(p.fi)
	var f: Dictionary = t.floors[fi]
	var c: Vector2 = t.c
	var y := float(f.y)
	var pos: Vector3 = p.pos
	var a := atan2(pos.z - c.y, pos.x - c.x)
	var rw := float(p.rw)
	var roll := _rng.randf()
	var s_stop := float(cfg.get("stop_share", 0.45))
	var s_lift := float(cfg.get("elevator_share", 0.2))
	var s_tun := float(cfg.get("tunnel_share", 0.15))
	if roll < s_stop:
		if _plan_stop(p, t, f, a):
			return
	elif roll < s_stop + s_lift:
		if _plan_lift(p, t, fi, a):
			return
	elif roll < s_stop + s_lift + s_tun:
		if _plan_tunnel(p, t, f, a):
			return
	var to := a + _rng.randf_range(0.4, 1.6) * (1.0 if _rng.randf() < 0.5 else -1.0)
	p.legs.append({ "kind": "go", "pts": [_pt(c, y, rw, a)] + _arc(c, y, rw, a, to) })
	if _rng.randf() < 0.4:
		p.legs.append({ "kind": "wait", "t": _rng.randf_range(1.0, 3.5) })


## Down a lane to a spot on an aisle (the fill's walking net) or into an open room,
## stand there a while, and back out the same way.
func _plan_stop(p: Dictionary, t: Dictionary, f: Dictionary, a: float) -> bool:
	var c: Vector2 = t.c
	var y := float(f.y)
	var rw := float(p.rw)
	var key := str(t.id) + "/" + str(f.id)
	var fill = station.fill
	var net: Dictionary = fill.nets.get(key, {}) if fill != null else {}
	var path: Array = []
	var face := INF
	if not net.is_empty() and not (net.stops as Array).is_empty():
		var st: Dictionary = net.stops[_rng.randi() % (net.stops as Array).size()]
		var alley := _nearest(net.alleys, float(st.a))
		if alley == INF:
			return false
		path = [_pt(c, y, rw, alley), _pt(c, y, float(st.r), alley)] + _arc(c, y, float(st.r), alley, float(st.a))
		var at := _pt(c, y, float(st.r), float(st.a))
		var fp := _pt(c, y, float(st.face_r), float(st.a))
		face = atan2(fp.x - at.x, fp.z - at.z)
	else:
		var rooms: Array = hull.rooms_of(str(t.id), str(f.id)).filter(func(r): return bool(r.open))
		if rooms.is_empty():
			return false
		var room: Dictionary = rooms[_rng.randi() % rooms.size()]
		var r0 := hull.gap_r + hull.walk
		var deep := float(cfg.get("room_deep", {}).get(str(f.id), 2.0))
		var ra := float(room.a)
		var x := Vector3(cos(ra), 0, sin(ra))
		var z := x.cross(UP)
		var side := _rng.randf_range(1.2, 2.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var o := Vector3(c.x, y, c.y)
		var reach := r0 + _rng.randf_range(1.5, maxf(1.6, deep))
		path = [o + x * (rw), o + x * (r0 - 0.6), o + x * (r0 + 1.0), o + x * (r0 + 1.0) + z * side, o + x * reach + z * side]
		face = atan2(x.x, x.z)
	p.legs.append({ "kind": "go", "pts": [_pt(c, y, rw, a)] + _arc(c, y, rw, a, _angle(c, path[0])) + path })
	var stand_s: Array = cfg.get("stop_s", [4.0, 12.0])
	p.legs.append({ "kind": "stood" })
	p.legs.append({ "kind": "wait", "t": _rng.randf_range(float(stand_s[0]), float(stand_s[1])), "face": face })
	var back := path.duplicate()
	back.reverse()
	p.legs.append({ "kind": "go", "pts": back })
	return true


## To the nearest bridge, wait for the car, ride it to another floor of this tower.
func _plan_lift(p: Dictionary, t: Dictionary, fi: int, a: float) -> bool:
	var ci := -1
	for k in station.cars.size():
		if str(station.cars[k].tower) == str(t.id):
			ci = k
	var floors: Array = t.floors
	if ci < 0 or floors.size() < 2:
		return false
	# Another floor of this tower that has people, by how many live there (so the
	# crowd stays spread the way the config has it).
	var counts: Dictionary = cfg.get("floors", {})
	var allowed: Array = []
	var total := 0.0
	for j in floors.size():
		if j != fi and counts.has(str(floors[j].id)):
			allowed.append(j)
			total += float(counts[str(floors[j].id)])
	if allowed.is_empty():
		return false
	var pick := _rng.randf() * total
	var to: int = allowed[-1]
	for j in allowed:
		pick -= float(counts[str(floors[j].id)])
		if pick <= 0.0:
			to = j
			break
	# Half the time, home (when home is in this tower and they are away from it).
	for j in allowed:
		if str(floors[j].id) == str(p.home) and _rng.randf() < float(cfg.get("home_pull", 0.5)):
			to = j
	var c: Vector2 = t.c
	var y := float(floors[fi].y)
	var rw := float(p.rw)
	var b := _nearest(StationHull.bridge_angles(fi), a)
	var wait_at := _pt(c, y, hull.shaft_r + 0.8, b)
	var in_at := _pt(c, y, _rng.randf_range(0.8, 2.6), b + _rng.randf_range(-0.6, 0.6))
	p.legs.append({ "kind": "go", "pts": [_pt(c, y, rw, a)] + _arc(c, y, rw, a, b) + [_pt(c, y, hull.gap_r + 0.3, b), wait_at] })
	p.legs.append({ "kind": "board", "car": ci, "fi": fi, "wait_at": wait_at, "in_at": in_at })
	p.legs.append({ "kind": "ride", "car": ci, "to": to })
	return true


## Out along a tunnel's lane, through the tunnel to the other tower, in to its
## walkway; that floor is theirs now.
func _plan_tunnel(p: Dictionary, t: Dictionary, f: Dictionary, a: float) -> bool:
	var y := float(f.y)
	var options: Array = []
	for tn in hull.tunnels:
		if str(tn.to) == "bay" or absf(float(tn.y) - y) > 1.0:
			continue
		var other := ""
		if str(tn.from) == str(t.id):
			other = str(tn.to)
		elif str(tn.to) == str(t.id):
			other = str(tn.from)
		else:
			continue
		var ot := hull.tower(other)
		var of := StationHull.floor_at(ot, y)
		if of.is_empty() or not (cfg.get("floors", {}) as Dictionary).has(str(of.id)):
			continue
		options.append([tn, ot, of])
	if options.is_empty():
		return false
	var pick: Array = options[_rng.randi() % options.size()]
	var tn: Dictionary = pick[0]
	var ot: Dictionary = pick[1]
	var of: Dictionary = pick[2]
	var xf: Transform3D = tn.xf
	var lane := _rng.randf_range(-1.4, 1.4)
	var s := xf * Vector3(0, 0, lane)
	var e := xf * Vector3(float(tn.length), 0, lane)
	if str(tn.from) != str(t.id):
		var sw := s
		s = e
		e = sw
	var c: Vector2 = t.c
	var c2: Vector2 = ot.c
	var d := _angle(c, s)
	var d2 := _angle(c2, e)
	var rw := float(p.rw)
	var oi := (ot.floors as Array).find(of)
	p.legs.append({ "kind": "go", "pts": [_pt(c, y, rw, a)] + _arc(c, y, rw, a, d) + [_pt(c, y, float(f.r) - 3.0, d), s, e,
		_pt(c2, y, float(of.r) - 3.0, d2), _pt(c2, y, rw, d2)] })
	p.legs.append({ "kind": "floor", "tower": ot, "fi": oi, "crossed": true })
	return true


# ------------------------------------------------------------------ geometry

static func _pt(c: Vector2, y: float, r: float, a: float) -> Vector3:
	return Vector3(c.x + cos(a) * r, y, c.y + sin(a) * r)


static func _angle(c: Vector2, p: Vector3) -> float:
	return atan2(p.z - c.y, p.x - c.x)


## Points round an arc of radius `r` from angle a0 to a1 the short way, every 2 m.
static func _arc(c: Vector2, y: float, r: float, a0: float, a1: float) -> Array:
	var da := wrapf(a1 - a0, -PI, PI)
	var n := maxi(1, ceili(absf(da) * r / 2.0))
	var out: Array = []
	for k in n:
		out.append(_pt(c, y, r, a0 + da * (k + 1) / n))
	return out


static func _nearest(angles: Array, a: float) -> float:
	var best := INF
	var bd := INF
	for x in angles:
		var d := absf(wrapf(float(x) - a, -PI, PI))
		if d < bd:
			bd = d
			best = float(x)
	return best


# ------------------------------------------------------------------ hurt and fighting back

## Someone was hit by `by` (null: the player). The player (or their droid) hurting
## anyone raises the station's alarm (_provoke). At zero they fall as a ragdoll.
func hurt(p: Dictionary, amount: float, by: Node = null, sweep := Vector3.ZERO) -> void:
	if p.dead or amount <= 0.0:
		return
	var player: Node = demo._player if demo != null else null
	if by == null or DroidController.by_player(by, player):
		_provoke()
	p.hp = float(p.hp) - amount
	if float(p.hp) <= 0.0:
		_kill(p, amount, by, sweep)


func _kill(p: Dictionary, amount := 0.0, by: Node = null, sweep := Vector3.ZERO) -> void:
	p.dead = true
	p.legs = []
	p.back_at = WorldState.clock + float(cfg.get("respawn_s", 180.0))
	(p.hit as CrowdHit).collision_layer = 0
	kills += 1
	var body: Node3D = p.body
	if not body.has_meta("joints") or not body.is_inside_tree():
		return
	var rc := Ragdoll.load_config()
	var at: Vector3 = (p.node as Node3D).global_position
	var from := Vector3.INF
	var fling := Vector3.ZERO
	if sweep != Vector3.ZERO:
		var cut := Vector3(sweep.x, 0.0, sweep.z).normalized()
		from = at - cut
		fling = cut * float(rc.get("blade_fling", 8.0)) + station.frame.basis.y * float(rc.get("blade_fling_up", 5.5))
	elif by is Node3D and is_instance_valid(by):
		from = (by as Node3D).global_position
	var rd := Ragdoll.new(body.get_meta("joints"), rc)
	rd.start(fling, Ragdoll.kick_for(at, from, amount, rc), get_world_3d().direct_space_state, [(p.hit as CrowdHit).get_rid()])
	p.ragdoll = rd


func _fall(p: Dictionary, dt: float) -> void:
	var rd = p.ragdoll
	if rd == null:
		return
	var moving: bool = not (rd as Ragdoll).asleep
	(rd as Ragdoll).step(dt)
	if moving and bool(p.shown):
		var skins: Array = (p.body as Node3D).get_meta("skins", [])
		if not skins.is_empty():
			skins[0].sync(p.body)


func _respawn(p: Dictionary) -> void:
	if p.ragdoll != null:
		(p.ragdoll as Ragdoll).stop()
		p.ragdoll = null
	p.dead = false
	p.hp = float(cfg.get("person_hp", 60))
	var body: Node3D = p.body
	var holder: Node3D = p.node
	body.transform = p.rest
	# Back on their home floor's walkway, standing.
	var key := str(p.home)
	for tw in hull.towers:
		for i in (tw.floors as Array).size():
			if str(tw.floors[i].id) == key:
				p.tower = tw
				p.fi = i
	var c: Vector2 = (p.tower as Dictionary).c
	var a := _rng.randf() * TAU
	p.pos = _pt(c, float(p.tower.floors[int(p.fi)].y), float(p.rw), a)
	p.legs = []
	p.shown = false
	holder.visible = false
	(p.hit as CrowdHit).collision_layer = 0
	_pose(p)


## The alarm: the nearest armed people become real locals where they stand, one a
## tick (_tick_fight), run by the station's own Townsfolk, which counts against your
## standing like the town's. Without the town's brains nobody fights.
func _provoke() -> void:
	if demo == null or not bool(demo.get("npc_brains")) or not demo.has_method("make_npc"):
		return
	if _folk == null:
		_folk = demo.make_townsfolk("StationFolk", [])
	_folk.provoke()
	_calm_t = 0.0
	var player: Node3D = demo._player
	var ppos: Vector3 = station.inv * player.global_position if player != null and is_instance_valid(player) else Vector3.ZERO
	var reach := float(cfg.get("rouse_m", 60.0))
	_rousing = people.filter(func(p): return not p.dead and p.fighter == null and p.armed \
		and (p.pos as Vector3).distance_to(ppos) <= reach and absf((p.pos as Vector3).y - ppos.y) < 8.0)
	_rousing.sort_custom(func(x, y): return (x.pos as Vector3).distance_to(ppos) < (y.pos as Vector3).distance_to(ppos))
	# Real bodies cost: no more than rouse_max fighting at once.
	var fighting := people.filter(func(p): return p.fighter != null).size()
	_rousing = _rousing.slice(0, maxi(0, int(cfg.get("rouse_max", 10)) - fighting))
	if not _rousing.is_empty():
		_rouse(_rousing.pop_front())


func _rouse(p: Dictionary) -> void:
	var soldier: Dictionary = demo._content().get_soldier(str(cfg.get("fighter", "local_resident"))).duplicate(true)
	if soldier.is_empty():
		return
	soldier["archetype"] = p.look
	var here: Vector3 = station.frame * (p.pos as Vector3)
	var f: Vector3 = station.frame.basis * (Basis(UP, float(p.yaw)) * Vector3.BACK)
	var g: NpcBody = demo.make_npc(soldier, here + Vector3(0, 0.05, 0), atan2(-f.x, -f.z), "",
		"npc:%s/crowd_%s" % [station.id, (p.node as Node).name])
	if g == null:
		return
	g.free_walk = true                  # no navmesh aboard: straight across the floor
	g.nav = null
	g.died.connect(_on_fighter_died.bind(p))
	p.fighter = g
	p.legs = []
	(p.node as Node3D).visible = false
	(p.hit as CrowdHit).collision_layer = 0
	_folk.add_member(g)
	if _folk.alarm.active():
		g.perception.awareness = 1.0
		g.perception.noticed = true


func _on_fighter_died(p: Dictionary) -> void:
	p.dead = true
	p.back_at = WorldState.clock + float(cfg.get("respawn_s", 180.0))
	kills += 1


## Back to walking: the fighter goes and the puppet is there again where it stood.
func _settle(p: Dictionary) -> void:
	var g = p.fighter
	p.fighter = null
	if g != null and is_instance_valid(g):
		if not p.dead:
			var at: Vector3 = station.inv * (g as Node3D).global_position
			at.y = float((p.tower as Dictionary).floors[int(p.fi)].y)
			p.pos = at
		_folk.remove_member(g)
		g.queue_free()
	p.shown = false
	if not p.dead:
		p.hp = float(cfg.get("person_hp", 60))


func _tick_fight(dt: float) -> void:
	if _folk == null:
		return
	var calm: bool = not _folk.alarm.active()
	_calm_t = _calm_t + dt if calm else 0.0
	if calm:
		_rousing.clear()
	for i in int(cfg.get("rouse_per_tick", 1)):
		if _rousing.is_empty():
			break
		var r: Dictionary = _rousing.pop_front()
		if not r.dead and r.fighter == null:
			_rouse(r)
	if _calm_t < float(cfg.get("calm_back_s", 20.0)):
		return
	for p in people:
		if p.fighter != null:
			_settle(p)


## What bolts and blades hit: one per person.
class CrowdHit:
	extends StaticBody3D
	var crowd
	var who: Dictionary
	var damage_usec := 0

	func apply_damage(amount: float) -> void:
		damage_usec = Time.get_ticks_usec()
		crowd.hurt(who, amount)

	func apply_damage_from(amount: float, shooter: Node) -> void:
		damage_usec = Time.get_ticks_usec()
		crowd.hurt(who, amount, shooter)

	func apply_blade_hit(amount: float, sweep: Vector3) -> void:
		damage_usec = Time.get_ticks_usec()
		crowd.hurt(who, amount, null, sweep)
