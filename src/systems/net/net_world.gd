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
## The planet's beast (the centipede) the same way: beast_snap, beast_hit and
## beast_died; a guest's own is the copy (PlanetBeast.net_copy), or goes when the
## host's planet has none.
##
## And the planet's natives (NativesDirector): the packs' members ride npc_snap with
## the town's people (npc_meta names one by its pack and slot, and the guest's copy
## is its own member there, never a new body), their moves (a swing, a throw, a
## wave) by npc_act. The camps by camp_snap (each pack's mood and which tents are
## down; camp_hit sends a guest's shot on a tent, native_provoke a pack that saw a
## guest steal), the animals by pig_snap, pig_hit and pig_died.
## The droids the same way (droid_snap, droid_fire, droid_ask / droid_meta,
## droid_hit, droid_died, droid_gone): the Remnant's and the locals' patrol droids,
## the wreck's crew and the haulers. A guest's town builds none of them
## (DroidController.net_copy) and makes each from the host's description. The
## moon rave's laser droid: rave_snap (where it is on its loop), rave_hit and
## rave_down. And every player's own droids walk in the others' games as pictures
## that follow that player (pal_snap and pal_fire, from every game to every other).
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
var _acts: Dictionary = {}         ## host: net id -> acts last seen
var _natives_built := -1.0         ## guest: when this town's natives were all built


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


## The planet's natives here (NativesDirector), or null.
static func natives(scene: Node) -> Node:
	var d = scene.get("natives") if scene != null else null
	return d if d != null and is_instance_valid(d) else null


## The packs' members here.
static func pack_members(scene: Node) -> Array:
	var d := natives(scene)
	if d == null:
		return []
	return (d.members() as Array).filter(func(n): return (n as NpcBody).is_inside_tree())


func _physics_process(dt: float) -> void:
	if not _live():
		return
	if _mp().is_server():
		_host_tick(dt)
	else:
		_guest_tick()
		_drive_droids(dt)
	_pals_tick(dt)


# ------------------------------------------------------------------ host

func _host_tick(dt: float) -> void:
	var scene := _town()
	if scene == null or _link().roster.size() < 2:
		return
	var all := people(scene) + pack_members(scene)
	for n in all:
		var id := _id_of(n)
		var was := int(_shots.get(id, n.shots_fired))
		if n.shots_fired > was:
			npc_fire.rpc(GameFlow.current_planet_id(), id, n.aim_point)
		_shots[id] = n.shots_fired
		if n.acts > int(_acts.get(id, n.acts)) and not n.dead:
			npc_act.rpc(GameFlow.current_planet_id(), id, n.action)
		_acts[id] = n.acts
	var ctl = scene.get("droids")
	_droid_shots(ctl)
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
	_send_beast(scene)
	_send_natives(scene, near, far_m, _round % far_every == 0)
	_send_droids(ctl, near, far_m, far_every)
	if _round % far_every == 0:
		_send_raves(scene)


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
	var d := natives(scene)
	for id in ids:
		var n = _bodies.get(int(id), null)
		if n == null or not is_instance_valid(n) or scene == null:
			continue
		var m := { "id": int(id), "key": str(scene.get_path_to(n)), "soldier": n.soldier_id, "post": n.post_id,
			"name": n.display_name, "pos": n.global_position, "yaw": n.rotation.y,
			"home": n.post_pos, "home_yaw": n.post_facing, "dead": n.dead }
		var key: Array = d.net_key(n) if d != null and n.free_walk else []
		if not key.is_empty():
			m["pack"] = str(key[0])          # one of a pack: the guest's own member at this slot
			m["slot"] = int(key[1])
		out.append(m)
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


# ------------------------------------------------------------------ the beast

const BEAST_NONE := 0
const BEAST_ALIVE := 1
const BEAST_DEAD := 2
var _beast_hooked: Object = null
var _beast_by := 0                 ## host: the guest whose hit landed on it last (0 = none)


func _send_beast(scene: Node) -> void:
	var b = scene.get("beast")
	if b == null or not is_instance_valid(b):
		beast_snap.rpc(GameFlow.current_planet_id(), BEAST_NONE, Vector3.ZERO, Vector3.ZERO, false, 0.0)
		return
	if b != _beast_hooked:
		_beast_hooked = b
		b.slain.connect(func(): if _live(): beast_died.rpc(GameFlow.current_planet_id(), _beast_by))
	beast_snap.rpc(GameFlow.current_planet_id(), BEAST_DEAD if b.dead else BEAST_ALIVE, b._head_ground, b.heading, b.chasing, b.hp)


## Guest -> host: my bolt or blade landed on the beast.
@rpc("any_peer", "call_remote", "reliable")
func beast_hit(amount: float) -> void:
	var scene := _town()
	var b = scene.get("beast") if scene != null else null
	if not _mp().is_server() or b == null or not is_instance_valid(b) or b.dead:
		return
	_beast_by = _mp().get_remote_sender_id()
	b._hurt(clampf(amount, 0.0, 500.0), false)       # it hurts; it chases nobody for it here
	_beast_by = 0 if not b.dead else _beast_by


## Host -> guests: where the beast is (or that there is none, or it is dead).
@rpc("authority", "call_remote", "unreliable_ordered")
func beast_snap(planet: String, state: int, at: Vector3, head: Vector3, chase: bool, hp: float) -> void:
	var scene := _town()
	if scene == null or planet != GameFlow.current_planet_id() or not bool(scene.get("lan_shared")):
		return
	var b = scene.get("beast")
	if b == null or not is_instance_valid(b):
		return                          # this game has none (killed in the guest's own save)
	if state == BEAST_NONE:
		scene.set("beast", null)        # the host's planet has none: nor does this town
		b.queue_free()
		return
	if not b.net_copy:
		b.net_copy = true
		b.net_hit = func(amount): beast_hit.rpc_id(1, amount)
	if state == BEAST_DEAD:
		b.net_die()
		return
	b.net_hear(at, head, chase, hp)


## Host -> guests: the beast died; `killer` is the guest whose hit it was (0: not a guest's).
@rpc("authority", "call_remote", "reliable")
func beast_died(planet: String, killer: int) -> void:
	if killer == _mp().get_unique_id():
		_marker(true)
	var scene := _town()
	var b = scene.get("beast") if scene != null and planet == GameFlow.current_planet_id() else null
	if b != null and is_instance_valid(b) and b.net_copy:
		b.net_die()


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
	_natives_built = -1.0
	_dunits.clear()
	_dheard.clear()


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
	if m.has("pack"):
		return _native_copy(id, m)
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


## One of a pack: this game's own member at the same slot of the same pack (the
## packs are built the same in every game); none made when it is not here.
func _native_copy(id: int, m: Dictionary) -> NpcBody:
	var d := natives(_scene)
	var own = d.net_member(str(m.pack), int(m.slot)) if d != null else null
	if own == null or own.dead or _claimed.has(own.get_instance_id()):
		return null
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
	var d := natives(_scene) if n.free_walk else null
	if d != null and d.net_slide(n, at):
		return                          # far off: slid along the ground, as the host's
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


## Host -> guests: NPC `id` played `move` (a swing, a throw, a gesture).
@rpc("authority", "call_remote", "reliable")
func npc_act(planet: String, id: int, move: String) -> void:
	if planet != GameFlow.current_planet_id() or _mp().is_server():
		return
	var n = _bodies.get(id, null)
	if n != null and is_instance_valid(n) and not n.dead and move != "":
		n.act(move)


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
	if shooter == p or DroidController.by_player(shooter, p):
		return true                     # you, or one of your droids
	var v = p.get("vehicle")
	return v != null and is_instance_valid(v) and v.has_method("hull_body") and shooter == v.hull_body()


func _guest_tick() -> void:
	var scene := _town()
	if scene == null or not bool(scene.get("lan_shared")):
		return
	_hook_natives(scene)
	if _scene != scene or _first_snap < 0.0:
		return
	# Once the host's people are all here, this town's own that copy none of them go.
	var now := Time.get_ticks_msec() / 1000.0
	var claim_s := NetSession.n("npc_claim_s", 4.0)
	if now - _first_snap < claim_s:
		return
	for n in people(scene):
		if not _claimed.has(n.get_instance_id()):
			for list in [scene.get("npcs"), scene.get("locals")]:
				(list as Array).erase(n)
			n.queue_free()
	# The same for the packs, once this town has built all of its own.
	var d := natives(scene)
	if d == null or not d.is_built():
		_natives_built = -1.0
		return
	if _natives_built < 0.0:
		_natives_built = now
	if now - _natives_built < claim_s:
		return
	for n in pack_members(scene):
		if not _claimed.has(n.get_instance_id()):
			d.net_drop(n)


func _marker(kill: bool) -> void:
	var scene := get_tree().current_scene
	var kit = scene.get("player_kit") if scene != null else null
	var w = kit.weapons if kit != null and is_instance_valid(kit) else null
	if w != null and w.feedback != null:
		w.feedback.confirm(kill)


# ------------------------------------------------------------------ the natives' camps and animals

var _pig_by := 0                   ## host: the guest whose hit landed on an animal just now


## Each pack's mood and its camp's tents (every far round), and the animals.
func _send_natives(scene: Node, near: Array, far_m: float, far_round: bool) -> void:
	var d := natives(scene)
	if d == null:
		return
	var here := GameFlow.current_planet_id()
	if far_round:
		var camps: Array = []
		for p in d.packs:
			if p is Dictionary and p.has("rec"):
				var c = p.get("camp")
				camps.append([str(p.id), str(p.state), d.is_friendly(p), (c as NativeCamp).down_mask() if c != null else 0])
		if not camps.is_empty():
			camp_snap.rpc(here, camps)
	var rows: Array = []
	for i in d.pigs.size():
		var pig = d.pigs[i]
		if not is_instance_valid(pig):
			continue
		if not pig.has_meta("net_hooked"):
			pig.set_meta("net_hooked", true)
			pig.killed.connect(func(_p): if _live(): pig_died.rpc(GameFlow.current_planet_id(), i, _pig_by))
		if not far_round and (pig.dead or not near.any(func(q): return (q as Vector3).distance_to(pig.global_position) <= far_m)):
			continue
		rows.append([i, pig.global_position, pig.fleeing(), pig.dead])
	var chunk := maxi(1, int(NetSession.n("npc_chunk", 14)))
	for i in range(0, rows.size(), chunk):
		pig_snap.rpc(here, rows.slice(i, i + chunk))


## Hooks a guest's natives to the host's: a pack this game sees you rob, or a tent
## you shoot, is the host's.
func _hook_natives(scene: Node) -> void:
	var d := natives(scene)
	if d == null:
		return
	if not d.net_provoke.is_valid():
		d.net_provoke = func(pack_id: String): native_provoke.rpc_id(1, pack_id)
	for c in d.camps:
		if is_instance_valid(c) and not (c as NativeCamp).net_hit.is_valid():
			var pack_id := str((c as NativeCamp).id)
			c.net_hit = func(i: int, amount: float, shooter: Node):
				if _yours(shooter) and amount > 0.0:
					hits_sent += 1
					camp_hit.rpc_id(1, pack_id, i, amount)


func _guest_natives(planet: String) -> Node:
	var scene := _town()
	if scene == null or planet != GameFlow.current_planet_id() or not bool(scene.get("lan_shared")):
		return null
	return natives(scene)


## Host -> guests: each pack: [id, state, friendly, tents down (bit i: tent i)].
@rpc("authority", "call_remote", "unreliable_ordered")
func camp_snap(planet: String, rows: Array) -> void:
	var d := _guest_natives(planet)
	if d == null:
		return
	for r in rows:
		if not (r is Array) or (r as Array).size() < 4:
			continue
		var p: Dictionary = d.pack(str(r[0]))
		if p.is_empty():
			continue
		p.state = str(r[1])
		p["net_friendly"] = bool(r[2])
		var c = p.get("camp")
		if c != null and is_instance_valid(c):
			(c as NativeCamp).net_down(int(r[3]))


## Host -> guests: the animals: [index, where, running, dead].
@rpc("authority", "call_remote", "unreliable_ordered")
func pig_snap(planet: String, rows: Array) -> void:
	var d := _guest_natives(planet)
	if d == null:
		return
	for r in rows:
		if not (r is Array) or (r as Array).size() < 4 or int(r[0]) < 0 or int(r[0]) >= d.pigs.size():
			continue
		var pig = d.pigs[int(r[0])]
		if not is_instance_valid(pig):
			continue
		if not (pig as SandPig).net_hit.is_valid():
			pig.net_hit = _on_pig_hit.bind(int(r[0]))
		if bool(r[3]):
			pig.net_die(false)
		else:
			pig.net_hear(r[1] as Vector3, bool(r[2]))


## Host -> guests: animal `i` died; `killer` is the guest whose hit it was.
@rpc("authority", "call_remote", "reliable")
func pig_died(planet: String, i: int, killer: int) -> void:
	var mine := killer == _mp().get_unique_id()
	if mine:
		_marker(true)
	var d := _guest_natives(planet)
	if d != null and i >= 0 and i < d.pigs.size() and is_instance_valid(d.pigs[i]):
		d.pigs[i].net_die(mine)


## A guest's copy of animal `i` was hit (only yours are sent).
func _on_pig_hit(amount: float, shooter: Node, i: int) -> void:
	if not _yours(shooter) or amount <= 0.0:
		return
	hits_sent += 1
	pig_hit.rpc_id(1, i, amount)


## Guest -> host: my bolt or blade landed on animal `i`.
@rpc("any_peer", "call_remote", "reliable")
func pig_hit(i: int, amount: float) -> void:
	var d := natives(_town())
	if not _mp().is_server() or d == null or i < 0 or i >= d.pigs.size():
		return
	var pig = d.pigs[i]
	if not is_instance_valid(pig) or pig.dead:
		return
	_pig_by = _mp().get_remote_sender_id()
	pig.apply_damage_from(clampf(amount, 0.0, 500.0), _link().bodies.get(_pig_by, null))   # it bolts from their body
	_pig_by = 0


## Guest -> host: my shot landed on tent `i` of pack `pack_id`'s camp.
@rpc("any_peer", "call_remote", "reliable")
func camp_hit(pack_id: String, i: int, amount: float) -> void:
	var d := natives(_town())
	if not _mp().is_server() or d == null:
		return
	var c = d.pack(pack_id).get("camp")
	if c != null and is_instance_valid(c) and i >= 0 and i < (c as NativeCamp).tents.size():
		(c as NativeCamp)._on_tent_hit(i, clampf(amount, 0.0, 500.0), _link().bodies.get(_mp().get_remote_sender_id(), null))


## Guest -> host: pack `pack_id` saw me rob it (or tear at its tents): it turns.
@rpc("any_peer", "call_remote", "reliable")
func native_provoke(pack_id: String) -> void:
	var d := natives(_town())
	if not _mp().is_server() or d == null:
		return
	var p: Dictionary = d.pack(pack_id)
	if not p.is_empty():
		d._provoke(p)


# ------------------------------------------------------------------ droids

const D_PROVOKED := 1
var _dids: Dictionary = {}         ## host: DroidUnit instance id -> net id
var _dunits: Dictionary = {}       ## host: net id -> DroidUnit;  guest: net id -> its copy
var _dshots: Dictionary = {}       ## host: net id -> shots last seen
var _dnext := 1
var _droids_hooked: Object = null  ## host: the DroidController whose deaths are sent
var _droid_by := 0                 ## host: the guest whose hit is landing now (0 = none)
var _dmeta: Dictionary = {}        ## guest: net id -> droid_meta
var _dasked: Dictionary = {}       ## guest: net id -> when it was last asked for
var _dheard: Dictionary = {}       ## guest: net id -> { at, yaw, vel, fight, t }


## The host's droids that are the town's (not yours, not the wrecks in the sand).
static func town_droids(ctl) -> Array:
	var out: Array = []
	if ctl == null or not is_instance_valid(ctl):
		return out
	for u in ctl.remnant + [ctl.hauler, ctl.wreck_hauler]:
		if u != null and is_instance_valid(u) and u.is_inside_tree():
			out.append(u)
	return out


func _droid_id(u) -> int:
	var k: int = u.get_instance_id()
	if not _dids.has(k):
		_dids[k] = _dnext
		_dunits[_dnext] = u
		u.tree_exiting.connect(_on_droid_gone.bind(k, _dnext), CONNECT_ONE_SHOT)
		_dnext += 1
	return int(_dids[k])


func _on_droid_gone(k: int, id: int) -> void:
	_dids.erase(k)
	_dunits.erase(id)
	_dshots.erase(id)
	if _live():
		droid_gone.rpc(id)


func _droid_shots(ctl) -> void:
	for u in town_droids(ctl):
		var id := _droid_id(u)
		if u.shots > int(_dshots.get(id, u.shots)):
			droid_fire.rpc(GameFlow.current_planet_id(), id, u.last_aim)
		_dshots[id] = u.shots


## [id, feet, heading, flags, hp]; far ones only every far_every-th time, as the people.
func _send_droids(ctl, near: Array, far_m: float, far_every: int) -> void:
	if ctl == null or not is_instance_valid(ctl):
		return
	if ctl != _droids_hooked:
		_droids_hooked = ctl
		ctl.unit_down.connect(func(u, sweep):
			if _live():
				droid_died.rpc(_droid_id(u), sweep, _droid_by))
	var rows: Array = []
	for u in town_droids(ctl):
		if u.dead:
			continue
		if _round % far_every != 0 and not near.any(func(p): return (p as Vector3).distance_to(u.global_position) <= far_m):
			continue
		rows.append([_droid_id(u), u.global_position, u.yaw, D_PROVOKED if u.provoked else 0, u.hp])
	var chunk := maxi(1, int(NetSession.n("npc_chunk", 14)))
	for i in range(0, rows.size(), chunk):
		droid_snap.rpc(GameFlow.current_planet_id(), rows.slice(i, i + chunk))


## Guest -> host: what is droid N? (the answer: droid_meta)
@rpc("any_peer", "call_remote", "reliable")
func droid_ask(ids: Array) -> void:
	if not _mp().is_server():
		return
	var out: Array = []
	for id in ids:
		var u = _dunits.get(int(id), null)
		if u == null or not is_instance_valid(u):
			continue
		var ctl = u.ctl
		out.append({ "id": int(id), "kind": u.kind, "variant": u.variant, "faction": u.faction,
			"hp": u.hp, "max_hp": u.max_hp, "gun": u.gun, "outpost": str(u.spec.get("outpost", "")),
			"site": str(u.spec.get("site", "")),
			"hauler": "pit" if u == ctl.hauler else ("wreck" if u == ctl.wreck_hauler else ""),
			"pos": u.global_position, "yaw": u.yaw, "dead": u.dead })
	if not out.is_empty():
		droid_meta.rpc_id(_mp().get_remote_sender_id(), out)


## Guest -> host: my bolt or blade landed on your droid `id` (blade: the sweep, else INF).
@rpc("any_peer", "call_remote", "reliable")
func droid_hit(id: int, amount: float, sweep: Vector3) -> void:
	if not _mp().is_server():
		return
	var u = _dunits.get(id, null)
	if u == null or not is_instance_valid(u) or u.dead:
		return
	var shooter = _link().bodies.get(_mp().get_remote_sender_id(), null)    # their body here
	_droid_by = _mp().get_remote_sender_id()
	u.ctl.on_unit_hit(u, clampf(amount, 0.0, 500.0), shooter, Vector3.ZERO if sweep == Vector3.INF else sweep)
	_droid_by = 0


## Host -> guests: where its droids are now.
@rpc("authority", "call_remote", "unreliable_ordered")
func droid_snap(planet: String, rows: Array) -> void:
	var scene := _town()
	if scene == null or planet != GameFlow.current_planet_id() or not bool(scene.get("lan_shared")):
		return
	_enter(scene)
	var ctl = _guest_droids(scene)
	if ctl == null:
		return
	var want: Array = []
	var now := Time.get_ticks_msec() / 1000.0
	for r in rows:
		if not (r is Array) or (r as Array).size() < 5:
			continue
		var id := int(r[0])
		var h: Dictionary = _dheard.get(id, {})
		var vel := Vector3.ZERO           # how fast the host's one goes, from the last two heard
		if not h.is_empty() and now - float(h.t) > 0.03:
			vel = ((r[1] as Vector3) - (h.at as Vector3)) / (now - float(h.t))
			if vel.length() > 12.0:
				vel = Vector3.ZERO              # a jump, not a walk
		_dheard[id] = { "at": r[1], "yaw": float(r[2]), "vel": vel, "fight": (int(r[3]) & D_PROVOKED) != 0, "t": now }
		var u = _dcopy(id, ctl)
		if u == null:
			if not _dmeta.has(id) and now - float(_dasked.get(id, -10.0)) > 2.0:
				_dasked[id] = now
				want.append(id)
			continue
		u.provoked = (int(r[3]) & D_PROVOKED) != 0     # in a fight: your droids answer it
		u.hp = float(r[4])
	if not want.is_empty():
		droid_ask.rpc_id(1, want)


## This town's DroidController, if it is one that runs no droids of its own.
func _guest_droids(scene: Node):
	var ctl = scene.get("droids")
	if ctl == null or not is_instance_valid(ctl) or not ctl.net_copy:
		return null
	if not ctl.net_hit.is_valid():
		ctl.net_hit = _on_droid_copy_hit
	return ctl


## Host -> a guest: the droids it asked about.
@rpc("authority", "call_remote", "reliable")
func droid_meta(list: Array) -> void:
	for m in list:
		if m is Dictionary:
			_dmeta[int(m.id)] = m
			_dasked.erase(int(m.id))


func _dcopy(id: int, ctl):
	var u = _dunits.get(id, null)
	if u != null and is_instance_valid(u):
		return u
	if not _dmeta.has(id) or bool(_dmeta[id].get("dead", false)):
		return null
	u = ctl.net_unit(_dmeta[id])
	u.set_meta("net_id", id)
	_dunits[id] = u
	return u


## Every frame: each copy closes on where the host's one is by now.
func _drive_droids(dt: float) -> void:
	for id in _dunits:
		var u = _dunits[id]
		if u == null or not is_instance_valid(u) or u.dead or not _dheard.has(id):
			continue
		var h: Dictionary = _dheard[id]
		_glide(u, h, dt, bool(h.fight))


## Move droid `u` toward `h` (at, yaw, vel, t): run on at its speed a moment past
## the last word, smoothed, and jump when it is droid_snap_m off. Its legs, wheels
## or hover go with it.
func _glide(u, h: Dictionary, dt: float, fighting: bool) -> void:
	var since := clampf(Time.get_ticks_msec() / 1000.0 - float(h.t), 0.0, 0.25)
	var vel := h.vel as Vector3
	var to := (h.at as Vector3) + vel * since
	if u.global_position.distance_to(to) > NetSession.n("droid_snap_m", 6.0):
		u.global_position = to
	else:
		u.global_position = u.global_position.lerp(to, 1.0 - exp(-NetSession.n("droid_smooth", 10.0) * dt))
	u.yaw = lerp_angle(u.yaw, float(h.yaw), 1.0 - exp(-NetSession.n("droid_smooth", 10.0) * dt))
	u.ctl._orient(u)
	var speed := vel.length()
	u.walk(dt, speed > 0.3, speed, fighting and speed <= 0.3)


## Host -> guests: droid `id` fired at `aim`: the copy fires a harmless bolt there.
@rpc("authority", "call_remote", "unreliable_ordered")
func droid_fire(planet: String, id: int, aim: Vector3) -> void:
	if planet != GameFlow.current_planet_id() or _mp().is_server() or aim == Vector3.INF:
		return
	var u = _dunits.get(id, null)
	if u == null or not is_instance_valid(u) or u.dead:
		return
	u.ctl.net_fire(u, aim, u.gun)


## Host -> guests: droid `id` died (a blade's `sweep`, ZERO for a bolt, INF: it
## ran off); `killer` is the guest whose hit it was (their kill marker), 0 if none.
@rpc("authority", "call_remote", "reliable")
func droid_died(id: int, sweep: Vector3, killer: int) -> void:
	if killer == _mp().get_unique_id():
		_marker(true)
	if _dmeta.has(id):
		_dmeta[id]["dead"] = true
	var u = _dunits.get(id, null)
	if u != null and is_instance_valid(u):
		u.ctl.net_down(u, sweep)


## Host -> guests: droid `id` is gone (it came back as a new one, its outpost
## changed hands, the cruiser's crew left).
@rpc("authority", "call_remote", "reliable")
func droid_gone(id: int) -> void:
	_dmeta.erase(id)
	_dheard.erase(id)
	var u = _dunits.get(id, null)
	_dunits.erase(id)
	if u == null or not is_instance_valid(u):
		return
	var ctl = u.ctl
	ctl.remnant.erase(u)
	if ctl.hauler == u:
		ctl.hauler = null
	if ctl.wreck_hauler == u:
		ctl.wreck_hauler = null
	u.queue_free()


## A copy was hit here (DroidController.net_hit). Only yours are sent: your bolt,
## your droid's, or your blade (a cut, `sweep`, is only ever the player's).
func _on_droid_copy_hit(u, amount: float, shooter: Node, sweep: Vector3) -> void:
	if u.faction == "" or amount <= 0.0 or not (_yours(shooter) or sweep != Vector3.ZERO):
		return                          # a hauler shrugs it off, as the host's does
	hits_sent += 1
	droid_hit.rpc_id(1, int(u.get_meta("net_id")), amount, sweep if sweep != Vector3.ZERO else Vector3.INF)


# ------------------------------------------------------------------ the rave's laser droid

var _rave_by := 0                  ## host: the guest whose hit is landing now


## [path from the town, where it is on its loop, alive]
func _send_raves(scene: Node) -> void:
	var rows: Array = []
	for r in get_tree().get_nodes_in_group("rave_droids"):
		if not (r is RaveDroid) or not scene.is_ancestor_of(r):
			continue
		var key := str(scene.get_path_to(r))
		if not r.has_meta("net_hooked"):
			r.set_meta("net_hooked", true)
			r.shot_down.connect(func(): if _live(): rave_down.rpc(GameFlow.current_planet_id(), key, _rave_by))
		rows.append([key, r.t, r.alive])
	if not rows.is_empty():
		rave_snap.rpc(GameFlow.current_planet_id(), rows)


## Host -> guests: where the laser droids are on their loops.
@rpc("authority", "call_remote", "unreliable_ordered")
func rave_snap(planet: String, rows: Array) -> void:
	var scene := _town()
	if scene == null or planet != GameFlow.current_planet_id() or not bool(scene.get("lan_shared")):
		return
	for row in rows:
		var r = _rave(scene, row[0]) if row is Array and (row as Array).size() >= 3 else null
		if r == null:
			continue
		if not bool(row[2]):
			r.shoot_down()
		elif absf(r.t - float(row[1])) > NetSession.n("rave_sync_s", 0.4):
			r.t = float(row[1])


## This town's laser droid at `key`, made a copy of the host's.
func _rave(scene: Node, key) -> RaveDroid:
	var r = scene.get_node_or_null(NodePath(str(key)))
	if not (r is RaveDroid):
		return null
	if not r.net_copy:
		r.net_copy = true
		r.net_hit = func(amount: float, shooter: Node):
			if amount > 0.0 and _yours(shooter):
				rave_hit.rpc_id(1, str(key), amount)
	return r


## Guest -> host: my bolt or blade landed on the laser droid at `key`.
@rpc("any_peer", "call_remote", "reliable")
func rave_hit(key: String, amount: float) -> void:
	var scene := _town()
	var r = scene.get_node_or_null(NodePath(key)) if scene != null and _mp().is_server() else null
	if not (r is RaveDroid) or not r.alive:
		return
	_rave_by = _mp().get_remote_sender_id()
	r.hit(clampf(amount, 0.0, 500.0), _link().bodies.get(_rave_by, null))
	_rave_by = 0


## Host -> guests: the laser droid at `key` was shot down; `killer`: the guest whose shot it was.
@rpc("authority", "call_remote", "reliable")
func rave_down(planet: String, key: String, killer: int) -> void:
	if killer == _mp().get_unique_id():
		_marker(true)
	var scene := _town()
	if scene == null or planet != GameFlow.current_planet_id() or not bool(scene.get("lan_shared")):
		return
	var r = _rave(scene, key)
	if r != null:
		r.shoot_down()


# ------------------------------------------------------------------ everyone's own droids

const P_DEAD := 1
const P_FIGHT := 2
var _pal_left := 0.0
var _pal_shots: Dictionary = {}    ## your droid's uid -> shots last seen
var _pals: Dictionary = {}         ## "peer:uid" -> { u, peer, dead, at, yaw, vel, fight, t }: theirs, here


## Send where your droids are (and their shots); move the others' pictures here.
func _pals_tick(dt: float) -> void:
	if _link().roster.size() < 2:
		return
	var scene := _town()
	var ctl = scene.get("droids") if scene != null else null
	if ctl != null and not is_instance_valid(ctl):
		ctl = null
	var here := GameFlow.current_planet_id()
	if ctl != null:
		for uid in ctl.companions:
			var u = ctl.companions[uid]
			if not is_instance_valid(u):
				continue
			if u.shots > int(_pal_shots.get(uid, u.shots)):
				pal_fire.rpc(here, int(uid), u.last_aim)
			_pal_shots[uid] = u.shots
	_pal_left -= dt
	if _pal_left <= 0.0:
		_pal_left = 1.0 / maxf(1.0, NetSession.n("pal_rate", 10.0))
		var rows: Array = []
		if ctl != null:
			for uid in ctl.companions:
				var u = ctl.companions[uid]
				if is_instance_valid(u) and u.is_inside_tree():
					rows.append([int(uid), u.kind, u.variant, u.global_position, u.yaw,
						(P_DEAD if u.dead else 0) | (P_FIGHT if u.target != null else 0)])
		pal_snap.rpc(here if ctl != null else "", rows)
	var now := Time.get_ticks_msec() / 1000.0
	for key in _pals.keys():
		var p: Dictionary = _pals[key]
		if not is_instance_valid(p.u) or p.u.get_parent() != ctl or not _link().roster.has(p.peer) \
				or now - float(p.t) > NetSession.n("pal_timeout_s", 3.0):
			_drop_pal(key)
		elif not bool(p.dead):
			_glide(p.u, p, dt, bool(p.fight))


func _drop_pal(key: String) -> void:
	var p = _pals.get(key, null)
	_pals.erase(key)
	if p != null and is_instance_valid(p.u):
		p.u.queue_free()


## Every player -> every other (the host relays): where my droids are. All of them
## each time, so one missing is one gone (sold, or waiting while I fly).
## [uid, kind, variant, feet, heading, flags]
@rpc("any_peer", "call_remote", "unreliable_ordered")
func pal_snap(planet: String, rows: Array) -> void:
	var from := _mp().get_remote_sender_id()
	if not _link().roster.has(from):
		return
	var scene := _town()
	var ctl = scene.get("droids") if scene != null else null
	var seen := {}
	if ctl != null and is_instance_valid(ctl) and planet == GameFlow.current_planet_id():
		var now := Time.get_ticks_msec() / 1000.0
		for r in rows:
			if not (r is Array) or (r as Array).size() < 6:
				continue
			var key := "%d:%d" % [from, int(r[0])]
			var dead := (int(r[5]) & P_DEAD) != 0
			seen[key] = true
			var p = _pals.get(key, null)
			if p != null and (not is_instance_valid(p.u) or p.u.get_parent() != ctl or (bool(p.dead) and not dead)):
				_drop_pal(key)              # a new town, or it rebooted (a new body there too)
				p = null
			if p == null:
				var u = ctl.net_picture(str(r[1]), str(r[2]))
				u.global_position = r[3]
				u.yaw = float(r[4])
				ctl._orient(u)
				p = { "u": u, "peer": from, "dead": false, "at": r[3], "t": now }
				_pals[key] = p
			var vel := Vector3.ZERO
			if now - float(p.t) > 0.03:
				vel = ((r[3] as Vector3) - (p.at as Vector3)) / (now - float(p.t))
				if vel.length() > 12.0:
					vel = Vector3.ZERO
			p.at = r[3]
			p.yaw = float(r[4])
			p.vel = vel
			p.fight = (int(r[5]) & P_FIGHT) != 0
			p.t = now
			if dead and not bool(p.dead):
				p.dead = true
				ctl.net_down(p.u, Vector3.ZERO)      # knocked out: down it goes, here too
	for key in _pals.keys():
		if int(_pals[key].peer) == from and not seen.has(key):
			_drop_pal(key)


## Every player -> every other: my droid `uid` fired at `aim` (a harmless bolt here).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func pal_fire(planet: String, uid: int, aim: Vector3) -> void:
	var p = _pals.get("%d:%d" % [_mp().get_remote_sender_id(), uid], null)
	if p == null or planet != GameFlow.current_planet_id() or aim == Vector3.INF or not is_instance_valid(p.u) or bool(p.dead):
		return
	p.u.ctl.net_fire(p.u, aim, DroidRoster.kind_cfg(p.u.kind).get("gun", {}))
