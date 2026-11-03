extends Node
## LAN: one space fight. The host's game runs the fight over its planet (the
## raiders, the Remnant's interceptor, the cruiser's escort: its SpaceFight, AI and
## all); a guest who climbs out while it is running joins it instead of starting
## their own (ShipPilot.start_fight): their SpaceFight flies only their own ship,
## and every other ship in it is a copy of one of the host's, AI off, put where the
## host's is (a little ahead, from its speed). A guest's bolt or seeker that lands
## on a copy is sent to the host's game and lands on the real one, so a kill is a
## kill on every screen (the kill marker is the shooter's), the waves come when the
## host's do, and the last wave down pays everyone in the fight. Each player's own
## ship shows to the others as their RemoteShip (NetLink.ship_state).
##
## For now the host's fighters only go for the host: a guest is in nobody's sights,
## and the host's bolts are pictures in a guest's game.
##
## Friendly fire (lan.json "friendly_fire"): your own bolts (not seekers) that cross
## another player's ship (their RemoteShip, within its radius) stop there and the
## hit goes to their game (NetLink.send_ship_hit), in a shared fight or not.
##
## Lives at /root/NetLink/Fight (NetLink makes it). Host -> guests: fight_snap (the
## ships, fight_rate times a second), fight_kill, fight_over. Guests -> host:
## fight_hit. Everyone -> everyone in the fight: fight_shots (bolts and seekers
## fired, shown as harmless ones). SpaceFight calls before_step and after_step
## around each step of its director.

const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var _snap: Dictionary = {}       ## guest: the host's fight as last heard { planet, encounter, waves, t, rows: { id: row } }
var _pending: Array = []         ## guest: the host's kills and its fight's end, for the next step
var _ghosts: Array = []          ## the others' shots, for the next step
var _snap_left := 0.0
var hits_sent := 0               ## tests
var ship_hits_sent := 0          ## your bolts on the other players' ships (tests)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _link() -> Node:
	return get_parent()


func _mp() -> MultiplayerAPI:
	return get_tree().get_multiplayer()


func _live() -> bool:
	var l := _link()
	return l != null and l.has_method("_connected") and l._connected() and (_mp().is_server() or bool(l.welcomed_in)) \
		and l.roster.size() >= 2


## The town's fight now, or null.
func _fight():
	var scene := get_tree().current_scene
	var pilot = scene.get("pilot") if scene != null else null
	if pilot == null or not is_instance_valid(pilot):
		return null
	var f = pilot.get("fight")
	return f if f != null and is_instance_valid(f) else null


## Guest: the host's fight over this planet, if it is going on now ({ encounter }),
## else {}. ShipPilot joins it instead of starting the pad's own.
func joinable() -> Dictionary:
	if not NetSession.is_guest() or _snap.is_empty() or str(_snap.planet) != GameFlow.current_planet_id():
		return {}
	if Time.get_ticks_msec() / 1000.0 - float(_snap.t) > NetSession.n("fight_stale_s", 2.0):
		return {}
	return { "encounter": str(_snap.encounter) }


## Before the director steps: the others' shots go in, and (a guest's copy of the
## host's fight) its ships go where the host's are. Returns the host's news for this
## step (kills, a new wave, the end), as the director's own events.
func before_step(fight, dt: float) -> Array:
	var out: Array = []
	if not _live():
		_ghosts.clear()
		return out
	if _shared(fight):
		for g in _ghosts:
			_add_ghost(fight, g)
	_ghosts.clear()
	if fight.net_copy:
		out = _guest_news(fight)
		_sync_copies(fight, dt)
	return out


## After it steps: the host sends its fight; a guest its hits on the copies; both
## the shots they fired.
func after_step(fight, events: Array) -> void:
	if not _live():
		return
	_hit_players(fight)
	if not _shared(fight):
		return
	var df = fight.df
	var here := GameFlow.current_planet_id()
	if _mp().is_server():
		for e in events:
			if str(e.type) == "kill":
				var peer := 1 if int(e.get("by", -1)) == df.player_id else int(e.get("peer", 0))
				fight_kill.rpc(here, int(e.id), e.point, peer, str(e.get("who", "")))
		_snap_left -= get_physics_process_delta_time()
		if _snap_left <= 0.0:
			_snap_left = 1.0 / maxf(1.0, NetSession.n("fight_rate", 15.0))
			fight_snap.rpc([here, fight.encounter_id, int(df.stats.waves)], _rows(df))
	else:
		var hits: Array = []
		for e in events:
			if str(e.type) == "hit" and bool(e.get("net", false)):
				var v: Dictionary = df.get_ship(int(e.id))
				hits.append([int(v.get("net_id", -1)), float(e.damage), str(e.kind), e.point])
		if not hits.is_empty():
			hits_sent += hits.size()
			fight_hit.rpc_id(1, hits)
	var shots := _new_shots(fight)
	if not shots.is_empty():
		fight_shots.rpc(here, shots)


## The host's fight ended (ShipPilot.end_fight): the guests' copies of it end too,
## paid if every wave went down.
func host_over(fight, outcome: String) -> void:
	if _live() and _mp().is_server():
		fight_over.rpc(GameFlow.current_planet_id(), outcome, fight.encounter_id)


## The fight the others' shots belong in: the host's own, or a guest's copy of it.
func _shared(fight) -> bool:
	return fight != null and fight.df != null and (fight.net_copy or _mp().is_server())


## Guest: up in space with no fight while the host's is on: join it.
func _physics_process(_dt: float) -> void:
	if get_tree().paused or joinable().is_empty() or _fight() != null:
		return
	var scene := get_tree().current_scene
	var pilot = scene.get("pilot") if scene != null else null
	if pilot != null and is_instance_valid(pilot) and pilot.has_method("join_net_fight"):
		pilot.join_net_fight()


# ------------------------------------------------------------------ host

## Every ship in the host's fight but the host's own (that is its RemoteShip):
## [id, ship id, team, where, rotation, speed, who].
func _rows(df) -> Array:
	var rows: Array = []
	for s in df.ships:
		if not s.alive or s.id == df.player_id:
			continue
		rows.append([int(s.id), str(s.ship_id), str(s.team), s.flight.position,
			s.flight.basis.orthonormalized().get_rotation_quaternion(), float(s.flight.speed), Dogfight.who(s)])
	return rows


## Guest -> host: my shots landed on these of your ships: [[id, amount, kind, point], ...].
@rpc("any_peer", "call_remote", "reliable")
func fight_hit(rows: Array) -> void:
	var id := _mp().get_remote_sender_id()
	var f = _fight()
	if not _mp().is_server() or not _link().roster.has(id) or f == null or f.df == null:
		return
	for r in rows:
		if r is Array and r.size() >= 4:
			f.df.net_damage(int(r[0]), clampf(float(r[1]), 0.0, 500.0), str(r[2]), r[3] as Vector3, id)


# ------------------------------------------------------------------ guest

## Host -> guests: its fight now. [planet, encounter, waves so far], rows (_rows).
@rpc("authority", "call_remote", "unreliable_ordered")
func fight_snap(head: Array, rows: Array) -> void:
	if head.size() < 3:
		return
	var by_id := {}
	for r in rows:
		if r is Array and r.size() >= 7:
			by_id[int(r[0])] = r
	var now := Time.get_ticks_msec() / 1000.0
	var seen: Dictionary = _snap.get("seen", {}) if str(_snap.get("encounter", "")) == str(head[1]) else {}
	for id in by_id:
		seen[id] = now
	_snap = { "planet": str(head[0]), "encounter": str(head[1]), "waves": int(head[2]), "t": now,
		"rows": by_id, "seen": seen }


## Host -> guests: one of its fight's ships went down, shot by player `peer` (0: one
## of the fight's own).
@rpc("authority", "call_remote", "reliable")
func fight_kill(planet: String, id: int, point: Vector3, peer: int, who: String) -> void:
	var f = _fight()
	if f != null and f.net_copy and planet == GameFlow.current_planet_id():
		_pending.append({ "type": "kill", "net_id": id, "point": point, "peer": peer, "who": who })


## Host -> guests: its fight is over ("complete": every wave down).
@rpc("authority", "call_remote", "reliable")
func fight_over(planet: String, outcome: String, encounter: String) -> void:
	if str(_snap.get("encounter", "")) == encounter:
		_snap = {}
	var f = _fight()
	if f != null and f.net_copy and planet == GameFlow.current_planet_id():
		_pending.append({ "type": "over", "outcome": outcome })


## The host's news as this fight's events: kills (yours with your marker), a new
## wave, and the end (`complete` pays, as winning your own does; anything else is
## `net_over`). No word from the host for fight_stale_s is the end too.
func _guest_news(fight) -> Array:
	var df = fight.df
	var out: Array = []
	for p in _pending:
		if p.type == "over":
			out.append({ "type": "complete", "payout": fight.payout() } if p.outcome == "complete" else { "type": "net_over" })
			continue
		var s: Dictionary = df.get_ship(int(fight.net_ids.get(int(p.net_id), -1)))
		if s.is_empty() or not s.alive:
			continue
		s.alive = false
		out.append({ "type": "kill", "id": s.id, "ship_id": s.ship_id, "team": s.team, "point": p.point,
			"who": p.who, "by": df.player_id if int(p.peer) == _mp().get_unique_id() else -1 })
	_pending.clear()
	if _snap.is_empty() or Time.get_ticks_msec() / 1000.0 - float(_snap.t) > NetSession.n("fight_stale_s", 2.0):
		if not out.any(func(e): return e.type == "complete" or e.type == "net_over"):
			out.append({ "type": "net_over" })
		return out
	if int(_snap.waves) > int(df.stats.waves):
		df.stats.waves = int(_snap.waves)
		out.append({ "type": "wave", "index": int(_snap.waves), "count": 0 })
	return out


## Every ship in the host's fight as a copy here, where the host's is: a new one
## made, one gone quiet for fight_stale_s put away.
func _sync_copies(fight, dt: float) -> void:
	var df = fight.df
	var now := Time.get_ticks_msec() / 1000.0
	var since := clampf(now - float(_snap.get("t", now)), 0.0, NetSession.n("fight_lead_max_s", 0.3))
	var rows: Dictionary = _snap.get("rows", {})
	var seen: Dictionary = _snap.get("seen", {})
	for hid in fight.net_ids.keys():
		var s: Dictionary = df.get_ship(int(fight.net_ids[hid]))
		if not s.is_empty() and s.alive and now - float(seen.get(hid, 0.0)) > NetSession.n("fight_stale_s", 2.0):
			s.alive = false
	var k := 1.0 - exp(-NetSession.n("fight_smooth_rate", 10.0) * dt)
	for hid in rows:
		var r: Array = rows[hid]
		var rot := (r[4] as Quaternion).normalized()
		var to: Vector3 = (r[3] as Vector3) + Basis(rot) * Vector3.FORWARD * float(r[5]) * since
		var s: Dictionary = df.get_ship(int(fight.net_ids.get(hid, -1)))
		if s.is_empty():
			var lid: int = df.spawn_ship(str(r[1]), str(r[2]), to, Basis(rot) * Vector3.FORWARD)
			s = df.get_ship(lid)
			if s.is_empty():
				continue
			s.net = true
			s.net_id = int(hid)
			s.brain = null
			s.pilot_name = str(r[6])
			s.callsign = ""
			fight.net_ids[hid] = lid
			s.flight.position = to
			s.flight.basis = Basis(rot)
		if not s.alive:
			continue
		var f = s.flight
		if f.position.distance_to(to) > maxf(NetSession.n("fight_snap_m", 60.0), float(r[5]) * 0.5):
			f.position = to
			f.basis = Basis(rot)
		else:
			f.position = f.position.lerp(to, k)
			f.basis = Basis(f.basis.orthonormalized().get_rotation_quaternion().slerp(rot, k))
		f.speed = float(r[5])


# ------------------------------------------------------------------ shots

## Friendly fire: this step's bolts of yours that crossed another player's ship.
## Seekers never count.
func _hit_players(fight) -> void:
	var df = fight.df
	var targets: Array = []
	for rs in _link().ship_bodies.values():
		if is_instance_valid(rs) and rs.hittable():
			targets.append(rs)
	if targets.is_empty():
		return
	var keep: Array = []
	for p in df.projectiles.items:
		var hit = null
		if int(p.owner) == df.player_id and str(p.kind) != "missile" and not p.get("ghost", false):
			for rs in targets:
				if df.projectiles.segment_hits_sphere(p.prev, p.pos, rs.global_position, rs.radius()):
					hit = rs
					break
		if hit == null:
			keep.append(p)
			continue
		ship_hits_sent += 1
		_link().send_ship_hit(int(hit.peer_id), float(p.damage))
	df.projectiles.items = keep


## This game's shots since the last ones sent: the host's whole fight's, a guest's
## own. [kind, team, from, velocity, range, turn rate, target (the host's id, -1: none)]
func _new_shots(fight) -> Array:
	var df = fight.df
	var rows: Array = []
	var top: int = fight.net_sent
	var back := {}
	if fight.net_copy:
		for hid in fight.net_ids:
			back[int(fight.net_ids[hid])] = int(hid)
	for p in df.projectiles.items:
		if int(p.uid) <= fight.net_sent:
			continue
		top = maxi(top, int(p.uid))
		if p.get("ghost", false) or (fight.net_copy and int(p.owner) != df.player_id):
			continue
		var tgt := int(p.target_id) if p.homing else -1
		if fight.net_copy:
			tgt = int(back.get(tgt, -1))
		rows.append([str(p.kind), str(p.team), p.pos, p.vel, float(p.range_left), float(p.turn_rate), tgt])
	fight.net_sent = top
	return rows


## Everyone in the fight -> everyone else: shots I fired, to be shown.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func fight_shots(planet: String, rows: Array) -> void:
	if planet != GameFlow.current_planet_id() or not _shared(_fight()):
		return
	for r in rows:
		if r is Array and r.size() >= 7:
			_ghosts.append(r)


## One of the others' shots in this fight: it flies as theirs did (a seeker after
## the same ship, when that ship is here) and hits nothing.
func _add_ghost(fight, r: Array) -> void:
	var df = fight.df
	var tgt := int(r[6])
	if fight.net_copy:
		tgt = int(fight.net_ids.get(tgt, -1))
	var homing: bool = str(r[0]) == "missile" and not df.get_ship(tgt).is_empty()
	df.projectiles.add({ "kind": str(r[0]), "origin": r[2] as Vector3, "velocity": r[3] as Vector3,
		"damage": 0.0, "range": float(r[4]), "homing": homing, "turn_rate": float(r[5]),
		"target_id": tgt }, -1, str(r[1]))
	df.projectiles.items.back()["ghost"] = true
