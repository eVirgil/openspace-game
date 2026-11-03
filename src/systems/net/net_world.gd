extends Node
## Issue #402: in a LAN game the host's town is the town for everyone. The host's
## game runs its people (the garrison, the townsfolk, the locals, the outposts'
## guards); a guest's game runs none of them and shows the host's instead: where
## each one is, which way they face, walking or running, crouched, aiming, firing,
## hurt and dead. A guest's bolt or blade that lands on one is sent to the host's
## game, which applies it to the real one, so a kill is a kill on every screen.
##
## Lives at /root/NetLink/World (NetLink makes it), so its path is the same in
## every game. Host -> guests: npc_snap (positions, a few times a second; far ones
## less often), npc_fire (a shot, shown as a harmless streak from the copy's rifle)
## and npc_died. Guests -> host: npc_ask (what is id N? the answer is npc_meta, all
## a guest needs to make or find the body) and npc_hit.
##
## A guest's copies are its own town's bodies where they match the host's (same
## node, same soldier), else made from npc_meta; its own bodies the host does not
## have go. The copies keep their looks, animator, ragdoll and health bar; NpcBody
## .net_hit sends their hits here instead of hurting them.
##
## Ids are the host's. A guest asks for what it does not know, so a town reload or
## a late joiner just asks again.

const F_SPRINT := 1
const F_CROUCH := 2
const F_HOSTILE := 4
const F_DRAWN := 8
const F_DEAD := 16

var _ids: Dictionary = {}          ## host: NpcBody instance id -> net id
var _bodies: Dictionary = {}       ## host: net id -> NpcBody;  guest: net id -> its copy
var _shots: Dictionary = {}        ## host: net id -> shots_fired last seen
var _next := 1
var _snap_left := 0.0
var _round := 0
var _meta: Dictionary = {}         ## guest: net id -> npc_meta
var _asked: Dictionary = {}        ## guest: net id -> when it was last asked for
var _scene: Node                   ## guest: the town the copies are in
var _first_snap := -1.0            ## guest: when the first snapshot reached this town
var _claimed: Dictionary = {}      ## guest: its own bodies that copy one of the host's
var snaps_heard := 0               ## tests
var heard_at: Dictionary = {}      ## guest: net id -> where the host's one stood last (tests)
var _heard_t: Dictionary = {}      ## guest: net id -> when
var hits_sent := 0                 ## tests


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _link() -> Node:
	return get_parent()


func _mp() -> MultiplayerAPI:
	return get_tree().get_multiplayer()


func _live() -> bool:
	var l := _link()
	return l != null and l.has_method("_connected") and l._connected() and (_mp().is_server() or bool(l.welcomed_in))


## Whether this town is the host's town shown here (a guest on the host's planet
## when the town was built): it runs no people of its own (TownDemo._npc_brains).
static func shared_town(here: String) -> bool:
	if not NetSession.is_guest():
		return false
	var host: Dictionary = NetSession.link.states.get(1, {})
	return host.is_empty() or str(host.get("planet", here)) == here


func _town() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.get("_player") != null and scene.get("npcs") != null else null


## The host's people in its town: the Remnant and the locals (not the band).
static func people(scene: Node) -> Array:
	var out: Array = []
	for list in [scene.get("npcs"), scene.get("locals")]:
		if list is Array:
			for n in list:
				if n is NpcBody and is_instance_valid(n) and n.is_inside_tree():
					out.append(n)
	return out


func _physics_process(dt: float) -> void:
	if not _live():
		return
	if _mp().is_server():
		_host_tick(dt)
	else:
		_guest_tick()


# ------------------------------------------------------------------ host

func _host_tick(dt: float) -> void:
	var scene := _town()
	if scene == null or _link().roster.size() < 2:
		return
	var all := people(scene)
	for n in all:
		var id := _id_of(n)
		var was := int(_shots.get(id, n.shots_fired))
		if n.shots_fired > was:
			npc_fire.rpc(GameFlow.current_planet_id(), id, n.aim_point)
		_shots[id] = n.shots_fired
	_snap_left -= dt
	if _snap_left > 0.0:
		return
	_snap_left = 1.0 / maxf(1.0, NetSession.n("npc_rate", 10.0))
	_round += 1
	var near := _players_at(scene)
	var far_m := NetSession.n("npc_far_m", 120.0)
	var far_every := maxi(1, int(NetSession.n("npc_far_every", 4)))
	var rows: Array = []
	for n in all:
		if n.dead:
			continue
		if _round % far_every != 0 and not near.any(func(p): return (p as Vector3).distance_to(n.global_position) <= far_m):
			continue
		rows.append(_row(n))
	var chunk := maxi(1, int(NetSession.n("npc_chunk", 14)))
	for i in range(0, rows.size(), chunk):
		npc_snap.rpc(GameFlow.current_planet_id(), rows.slice(i, i + chunk))


## Everyone's feet here: the host's and every guest's on this planet.
func _players_at(scene: Node) -> Array:
	var out: Array = [(scene.get("_player") as Node3D).global_position]
	var here := GameFlow.current_planet_id()
	for id in _link().states:
		var s: Dictionary = _link().states[id]
		if str(s.get("planet", "")) == here:
			out.append(s.pos)
	return out


func _id_of(n: NpcBody) -> int:
	var k := n.get_instance_id()
	if not _ids.has(k):
		_ids[k] = _next
		_bodies[_next] = n
		n.died.connect(_on_died.bind(_next))
		_next += 1
	return int(_ids[k])


## [id, feet, facing, flags, aim (INF at ease), hp]
func _row(n: NpcBody) -> Array:
	var f := 0
	if bool(n.command.sprint):
		f |= F_SPRINT
	if bool(n.command.crouch):
		f |= F_CROUCH
	if n.hostile:
		f |= F_HOSTILE
	if n.drawn:
		f |= F_DRAWN
	return [_id_of(n), n.global_position, n.rotation.y, f, n.aim_point, int(n.health.hp)]


func _on_died(id: int) -> void:
	var n = _bodies.get(id, null)
	if n == null or not is_instance_valid(n) or not _live():
		return
	var killer := 0
	var by = n.last_hit_by
	if by != null and is_instance_valid(by) and by.get("peer_id") != null:
		killer = int(by.peer_id)                # a guest's shot (their body here, RemotePlayer)
	elif by == null and n.has_meta("net_hit_by"):
		killer = int(n.get_meta("net_hit_by"))  # theirs, with no body of theirs here to name
	npc_died.rpc(GameFlow.current_planet_id(), id, n.last_hit_from, n.get("_blade_sweep"), killer)


## Guest -> host: what is this one? (the answer: npc_meta)
@rpc("any_peer", "call_remote", "reliable")
func npc_ask(ids: Array) -> void:
	if not _mp().is_server():
		return
	var out: Array = []
	var scene := _town()
	for id in ids:
		var n = _bodies.get(int(id), null)
		if n == null or not is_instance_valid(n) or scene == null:
			continue
		out.append({ "id": int(id), "key": str(scene.get_path_to(n)), "soldier": n.soldier_id, "post": n.post_id,
			"name": n.display_name, "pos": n.global_position, "yaw": n.rotation.y,
			"home": n.post_pos, "home_yaw": n.post_facing, "dead": n.dead })
	if not out.is_empty():
		npc_meta.rpc_id(_mp().get_remote_sender_id(), out)


## Guest -> host: my bolt or blade landed on your NPC `id` (blade: the sweep, else INF).
@rpc("any_peer", "call_remote", "reliable")
func npc_hit(id: int, amount: float, sweep: Vector3) -> void:
	if not _mp().is_server():
		return
	var n = _bodies.get(id, null)
	if n == null or not is_instance_valid(n) or n.dead:
		return
	var shooter = _link().bodies.get(_mp().get_remote_sender_id(), null)    # their body here
	var dmg := clampf(amount, 0.0, 500.0)
	if sweep != Vector3.INF:
		n._blade_sweep = Vector3(sweep.x, 0.0, sweep.z).normalized()       # a killing cut flings it that way
		if shooter is Node3D:
			n.last_hit_from = (shooter as Node3D).global_position
	n.set_meta("net_hit_by", _mp().get_remote_sender_id())
	n.apply_damage_from(dmg, shooter)
	n._blade_sweep = Vector3.ZERO


# ------------------------------------------------------------------ guest

## Host -> guests: where its people are now.
@rpc("authority", "call_remote", "unreliable_ordered")
func npc_snap(planet: String, rows: Array) -> void:
	var scene := _town()
	if scene == null or planet != GameFlow.current_planet_id() or not bool(scene.get("lan_shared")):
		return
	_enter(scene)
	snaps_heard += 1
	if _first_snap < 0.0:
		_first_snap = Time.get_ticks_msec() / 1000.0
	var want: Array = []
	for r in rows:
		if not (r is Array) or (r as Array).size() < 6:
			continue
		var id := int(r[0])
		var now := Time.get_ticks_msec() / 1000.0
		var vel := Vector3.ZERO           # how fast the host's one walks, from the last two heard
		if heard_at.has(id) and now - float(_heard_t[id]) > 0.03:
			vel = ((r[1] as Vector3) - (heard_at[id] as Vector3)) / (now - float(_heard_t[id]))
			if vel.length() > 12.0:
				vel = Vector3.ZERO              # a jump, not a walk
		heard_at[id] = r[1]
		_heard_t[id] = now
		var n = _copy(id)
		if n == null:
			if not _meta.has(id) and Time.get_ticks_msec() / 1000.0 - float(_asked.get(id, -10.0)) > 2.0:
				_asked[id] = Time.get_ticks_msec() / 1000.0
				want.append(id)
			continue
		_drive(n, r, vel)
	if not want.is_empty():
		npc_ask.rpc_id(1, want)


## A new town: the copies were the old one's.
func _enter(scene: Node) -> void:
	if _scene == scene:
		return
	_scene = scene
	_bodies.clear()
	_claimed.clear()
	_first_snap = -1.0


## Host -> a guest: what it asked about.
@rpc("authority", "call_remote", "reliable")
func npc_meta(list: Array) -> void:
	for m in list:
		if m is Dictionary:
			_meta[int(m.id)] = m
			_asked.erase(int(m.id))


func _copy(id: int) -> NpcBody:
	var n = _bodies.get(id, null)
	if n != null and is_instance_valid(n):
		return n
	if not _meta.has(id) or _scene == null:
		return null
	var m: Dictionary = _meta[id]
	if bool(m.get("dead", false)):
		return null
	# This town's own body at the same spot in the tree, the same soldier, not yet
	# copying another: it is that one. Else one is made from the host's word.
	var own = _scene.get_node_or_null(NodePath(str(m.key)))
	if not (own is NpcBody) or own.dead or own.soldier_id != str(m.soldier) or _claimed.has(own.get_instance_id()):
		own = null
	if own == null and _scene.has_method("make_soldier"):
		own = _scene.make_soldier(str(m.soldier), m.pos, float(m.yaw), str(m.post), "lan:%s" % str(m.key))
		if own != null:
			own.post_pos = m.home
			own.post_facing = float(m.home_yaw)
	if own == null:
		return null
	own.display_name = str(m.get("name", own.display_name))
	_claimed[own.get_instance_id()] = true
	_bodies[id] = own
	_puppet(own)
	return own


## Make a body a copy: its hits go to the host, its shots are pictures.
func _puppet(n: NpcBody) -> void:
	n.net_hit = _on_copy_hit.bind(n)
	if n.weapon_actor != null and not n.has_meta("net_copy"):
		var own_cfg: Callable = n.weapon_actor.configure_bolt
		n.weapon_actor.configure_bolt = func(b):
			if own_cfg.is_valid():
				own_cfg.call(b)
			b.damage = 0.0
			b.splash_damage = 0.0
			b.sweep = false
			b.monitoring = false            # a picture of the host's shot: its hit is the host's to say
			b.collision_mask = 0
			b.ready.connect(func(): b.remove_from_group("bolts"), CONNECT_ONE_SHOT)
	n.set_meta("net_copy", true)


## Where the host's one is: walk there (run if it runs), or jump if far off; face
## and aim as it does.
func _drive(n: NpcBody, r: Array, vel: Vector3) -> void:
	if n.dead:
		return
	var at := r[1] as Vector3
	var yaw := float(r[2])
	var f := int(r[3])
	var off := n.global_position.distance_to(at)
	if off > NetSession.n("npc_snap_m", 6.0):
		n.global_position = at
		n.stop()
	elif off > 0.35 or vel.length() > 0.3:
		# Walk to where it will be in a moment, not where it was: a copy repaths
		# only once its goal has moved on, so aiming at the old spot trails behind.
		n.go_to(at + vel * NetSession.n("npc_lead_s", 0.6), (f & F_SPRINT) != 0)
	elif n.command.go_to != Vector3.INF:
		n.stop()
	n.command.crouch = (f & F_CROUCH) != 0
	n.face_point(n.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 8.0)
	n.hostile = (f & F_HOSTILE) != 0
	n.drawn = (f & F_DRAWN) != 0
	n.aim_point = r[4] as Vector3
	var hp := int(r[5])
	if hp > 0 and hp != int(n.health.hp):
		n.health.hp = mini(hp, int(n.health.max_hp))


## Host -> guests: NPC `id` fired at `aim`: the copy fires a harmless bolt there.
@rpc("authority", "call_remote", "unreliable_ordered")
func npc_fire(planet: String, id: int, aim: Vector3) -> void:
	if planet != GameFlow.current_planet_id() or _mp().is_server():
		return
	var n = _bodies.get(id, null)
	if n == null or not is_instance_valid(n) or n.dead or aim == Vector3.INF:
		return
	n.aim_point = aim
	n.fire_at(aim, 1.0)


## Host -> guests: NPC `id` died there (hit from `from`, a blade's `sweep`); `killer`
## is the guest whose hit it was (their kill marker), 0 if none.
@rpc("authority", "call_remote", "reliable")
func npc_died(planet: String, id: int, from: Vector3, sweep: Vector3, killer: int) -> void:
	if killer == _mp().get_unique_id():
		_marker(true)
	if planet != GameFlow.current_planet_id():
		return
	if _meta.has(id):
		_meta[id]["dead"] = true
	var n = _bodies.get(id, null)
	if n == null or not is_instance_valid(n) or n.dead:
		return
	n.last_hit_from = from
	n._blade_sweep = sweep
	n.health.apply_damage(float(n.health.hp) + 1.0)       # its own death: ragdoll, sound, rifle dropped
	n._blade_sweep = Vector3.ZERO


## A copy was hit here. Only yours are sent (a stray bolt in this game is not one
## in the host's); the marker pops now, the kill's when the host says so.
func _on_copy_hit(amount: float, shooter: Node, sweep: Vector3, n: NpcBody) -> void:
	if not _yours(shooter) or amount <= 0.0 or n.dead:
		return
	n.damage_usec = Time.get_ticks_usec()
	hits_sent += 1
	npc_hit.rpc_id(1, _id_for(n), amount, sweep)


func _id_for(n: NpcBody) -> int:
	for id in _bodies:
		if _bodies[id] == n:
			return int(id)
	return -1


func _yours(shooter: Node) -> bool:
	var scene := get_tree().current_scene
	var p = scene.get("_player") if scene != null else null
	if shooter == null or p == null or not is_instance_valid(shooter):
		return false
	if shooter == p:
		return true
	var v = p.get("vehicle")
	return v != null and is_instance_valid(v) and v.has_method("hull_body") and shooter == v.hull_body()


func _guest_tick() -> void:
	var scene := _town()
	if scene == null or not bool(scene.get("lan_shared")) or _scene != scene or _first_snap < 0.0:
		return
	# Once the host's people are all here, this town's own that copy none of them go.
	if Time.get_ticks_msec() / 1000.0 - _first_snap < NetSession.n("npc_claim_s", 4.0):
		return
	for n in people(scene):
		if not _claimed.has(n.get_instance_id()):
			for list in [scene.get("npcs"), scene.get("locals")]:
				(list as Array).erase(n)
			n.queue_free()


func _marker(kill: bool) -> void:
	var scene := get_tree().current_scene
	var kit = scene.get("player_kit") if scene != null else null
	var w = kit.weapons if kit != null and is_instance_valid(kit) else null
	if w != null and w.feedback != null:
		w.feedback.confirm(kill)
