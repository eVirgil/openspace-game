class_name Townsfolk
extends Node
## The port's own people: the director for every NpcBody whose soldier profile is
## in the "locals" faction, the way Garrison runs the Remnant troopers. Same pieces
## (GuardBrain per body, a TownAlarm for the lot), different rules:
##
##   calm      residents and shoppers walk their loops (marker "patrol" routes);
##             merchants and the fence mind their stall and look around
##   alarm     raised when the player hurts or kills any local. Every local in town
##             fights: walkers take cover and close in on their leash, merchants
##             (profile combat.hold_ground) duck behind the counter and shoot over
##             it, never leaving the stall. Everyone's pistol (profile "sidearm")
##             comes out when the alarm goes up and is put away after
##   after     calm again when the player flees or is downed. After fleeing the
##             locals remember the face for memory_s and start again on sight;
##             once the player wakes in the pit they forget it (forgive_player)
##
## Their own alarm, not the garrison's: shooting a local does not call the Remnant,
## and a gate fight does not turn the market on you. While the locals are up in
## arms (or the stall keeper is dead) a vendor will not trade (vendor_open).
##
## Who does what comes from the profile's "role": "local" (walks a loop),
## "merchant" (holds a stall). Numbers: content/core/soldiers/local_*.json and
## the town's "locals" block; barks: content/core/dialogue/locals_lines.json.
##
## The locals' guards on the barracks posts (while they hold it) are not run
## here: they work the front gate and the barracks yard in a garrison of their own
## (Garrison, on the locals' side), and so do the locals at each outpost they hold.
## The barracks' alarm and this one go up together (alarm_up, join_alarm), so a
## fight at the gate is a fight with the port and back.
##
## They know the planet's beast (PlanetBeast): calm, a local you walk close by now
## and then says something about it, by name (its "lore" in the planet's file).

const LINES_PATH := "res://content/core/dialogue/locals_lines.json"

var demo
var town
## Fights here count against the locals' standing (and fleeing one is
## remembered). Off for the party barge's crowd: its fights touch no one's.
var standing := true
var player: CharacterBody3D
var members: Array = []           ## every local NpcBody
var brains: Dictionary = {}       ## NpcBody -> GuardBrain
var alarm: TownAlarm
var cfg: Dictionary = {}          ## the town's "locals" block
var lines: Dictionary = {}
var claimed: Dictionary = {}      ## NpcBody -> Vector3 its cover spot

## Numbers the traces read.
var barks_said: Array = []
var beast_said: Array = []        ## what the locals have said about the beast (traces)
var alarm_t := -1.0               ## game seconds when the alarm last went up
var kills := 0

var _rng := RandomNumberGenerator.new()
var _attacked := false
var unfound: Array = []         ## issue #307: bodies of silent sword kills nobody has found yet
var silent_kills := 0           ## (traces)
var _clock := 0.0
var _last_key := ""
var _last_key_t := -100.0
var _beast_cfg: Dictionary = {}   ## PlanetBeast.config of this planet ({} if it has no beast)
var _beast_next := 0.0            ## game seconds before a local may talk of the beast again

## The alarm went up here (any cause): the locals' barracks join it (Garrison.join_alarm).
signal alarm_up(at: Vector3)


## `all` = every local NpcBody in town.
func setup(town_demo, all: Array) -> void:
	demo = town_demo
	town = demo.town
	player = demo._player
	members = all
	_rng.seed = 11
	cfg = town.data.get("locals", {}) if town.data is Dictionary else {}
	alarm = TownAlarm.new(cfg.get("alarm", {}))
	lines = CharacterKit._read_json(LINES_PATH).get("lines", {})
	_beast_cfg = PlanetBeast.config(demo.get("planet") if demo.get("planet") is Dictionary else {})
	_beast_next = float(_beast_cfg.get("locals_say_first_s", 6.0))
	for g in members:
		if (not g.has_meta("outpost") or not is_same(members, demo.locals)) and not on_barracks(g):
			_adopt(g)              # (issue #187: the town's leaves the outposts' locals to theirs)
	if player != null and player.has_signal("downed"):
		player.downed.connect(_on_player_downed)


## A local guard on a barracks post: the locals' barracks garrison runs it, not this.
static func on_barracks(g: NpcBody) -> bool:
	return g.has_meta("barracks_locals")


func _adopt(g: NpcBody) -> void:
	var b := GuardBrain.new(g.profile, 211 + brains.size() * 37)
	var m: Dictionary = town.get_marker(g.post_id)
	var pts: Array = town.route_points_3d(str(m.get("patrol", ""))) if m.has("patrol") else []
	b.patrol_points = pts if pts.size() >= 2 else [g.post_pos]
	b.set_post_facing(g.post_facing)
	brains[g] = b
	g.died.connect(_on_local_died.bind(g))
	g.hit_by.connect(_on_local_hit.bind(g))


## Issue #187: a local joins after setup (the locals' guards moving into the
## barracks or an outpost), and leaves (the Remnant take the outpost back).
func add_member(g: NpcBody) -> void:
	if g == null or brains.has(g) or on_barracks(g):
		return
	if not members.has(g):
		members.append(g)
	_adopt(g)


func remove_member(g: NpcBody) -> void:
	members.erase(g)
	brains.erase(g)
	claimed.erase(g)


func _physics_process(dt: float) -> void:
	if alarm == null or player == null:
		return
	_clock += dt
	var alive := _alive()
	var ppos := _player_pos()
	var seen := false
	var noticed := false
	var nearest := INF
	for g in alive:
		seen = seen or g.perception.visible
		noticed = noticed or g.perception.noticed
		if ppos != Vector3.INF:
			nearest = minf(nearest, g.global_position.distance_to(ppos))
	# A face they remember starts it again.
	if not alarm.active() and alarm.remembers() and noticed and ppos != Vector3.INF:
		_raise("remembered")
	if not alarm.active():
		_find_bodies(alive)
	if _attacked:
		_raise("attacked")
	_attacked = false
	alarm.update(dt, { "seen": seen, "player_pos": ppos, "nearest_dist": nearest, "alive": alive.size() })
	_handle(alarm.drain())
	for g in alive:
		var b: GuardBrain = brains[g]
		g.drawn = alarm.active() or not g.sidearm   # pistols out while the port is up in arms (a guard's rifle always is)
		if alarm.active():
			b.engage()
			b.alarm_pos = alarm.last_known
		else:
			b.alarm_pos = Vector3.INF
		_run_brain(g, dt, ppos)
	if not alarm.active():
		_beast_talk(alive, ppos)


func _run_brain(g: NpcBody, dt: float, ppos: Vector3) -> void:
	var b: GuardBrain = brains[g]
	g.brief(b, ppos, player.velocity if ppos != Vector3.INF else Vector3.ZERO)
	b.update(dt)
	if b.want_cover:
		b.want_cover = false
		b.cover = _pick_cover(g, b)
	g.carry_out(b, dt)
	if b.bark != "":
		_say(g, b.bark)


func _raise(why: String) -> void:
	if not alarm.raise(why, _player_pos()):
		return
	_handle(alarm.drain())
	if why != "remembered" and standing:
		WorldState.change_standing("locals", int(cfg.get("alarm", {}).get("raise_standing", -10)),
			"Someone opened fire on the port's own people.")


## The locals' barracks went up in arms: the port fights too. No standing here;
## the barracks already took it.
func join_alarm(at: Vector3) -> void:
	if alarm != null and alarm.raise("joined", at):
		_handle(alarm.drain())


func _handle(events: Array) -> void:
	for e in events:
		match str(e.type):
			"alarm":
				alarm_t = _clock
				for g in _alive():
					g.perception.awareness = 1.0
					g.perception.noticed = true
				_say(_lead(_alive()), "alarm")
				alarm_up.emit(alarm.last_known)
			"standing":
				if standing:
					WorldState.change_standing("locals", int(e.delta), "Someone shot up the port's locals and got away.")
			"flag":
				if standing:
					WorldState.set_flag("fled_locals_fight")
			"calm":
				for g in _alive():
					var b: GuardBrain = brains[g]
					if str(e.why) == "downed":
						b.stand_down()
					else:
						b.calm()
				claimed.clear()


## True when the stall at `marker` is open for trade: its keeper (the local posted
## there, if any) is alive and the locals are not fighting. A stall with nobody
## posted at it is always open.
func vendor_open(marker: String) -> bool:
	for g in members:
		if g.post_id == marker:
			return not g.dead and not alarm.active()
	return true


## What a closed stall's keeper says ("" if none is posted there, or they are
## dead). The same line every frame: the prompt asks each frame.
func closed_line(marker: String) -> String:
	var list: Array = lines.get("shop_closed", [])
	for g in members:
		if g.post_id == marker and not g.dead and not list.is_empty():
			return str(list[absi(hash(marker)) % list.size()])
	return ""


# ------------------------------------------------------------------ cover

## A free cover spot within the profile's cover_search_radius (none for a merchant:
## radius 0). Spots come from the garrison's grid when the town has one; without it
## the locals fight in the open. Same "returning our own spot means none" rule.
func _pick_cover(g: NpcBody, b: GuardBrain) -> Vector3:
	var c: Dictionary = g.profile.get("combat", {})
	var reach := float(c.get("cover_search_radius", 0.0))
	var garrison = demo.get("garrison")
	if reach <= 0.0 or garrison == null:
		return Vector3.INF
	var threat: Vector3 = b.target_pos if b.visible else b.last_seen
	if threat == Vector3.INF:
		threat = b.alarm_pos
	if threat == Vector3.INF:
		return Vector3.INF
	var taken: Array = []
	for other in claimed:
		if other != g and not other.dead:
			taken.append(claimed[other])
	var mine: Array = []
	for sp in garrison.spots_near(g.global_position, reach):
		var p: Vector3 = sp.pos
		if Vector2(p.x - g.global_position.x, p.z - g.global_position.z).length() <= reach:
			mine.append(sp)
	var i := CoverPicker.pick(g.global_position, threat, mine, taken,
		float(c.get("cover_min_threat_dist", 5.0)), float(c.get("cover_max_threat_dist", 30.0)))
	if i < 0:
		claimed.erase(g)
		return Vector3.INF
	var at: Vector3 = mine[i].pos
	if claimed.has(g) and (claimed[g] as Vector3).distance_to(at) < 1.2 and g.global_position.distance_to(at) < 1.5:
		claimed.erase(g)
		return Vector3.INF
	claimed[g] = at
	return at


# ------------------------------------------------------------------ events

## The player hurt someone this director speaks for who is not one of its bodies
## (a dancer on the party barge): the alarm goes up next tick, as if a member was hit.
func provoke() -> void:
	_attacked = true


func _on_local_hit(shooter: Node, _amount: float, g: NpcBody) -> void:
	if DroidController.by_player(shooter, player) and SilentKill.unaware_cut(g):
		_check_cut.call_deferred(g)            # issue #307: silent if the cut killed them unseen
		return
	brains[g].notify_hit()
	if DroidController.by_player(shooter, player):
		_attacked = true


## Issue #307: an unaware local was cut. Dead and unseen: nobody knows.
func _check_cut(g: NpcBody) -> void:
	if is_instance_valid(g) and g.dead and not SilentKill.witnessed(g, _alive()):
		return
	_attacked = true
	if is_instance_valid(g) and brains.has(g):
		brains[g].notify_hit()


## Issue #307: a local who walks within sight of a silent kill finds the body.
func _find_bodies(alive: Array) -> void:
	if unfound.is_empty():
		return
	unfound = unfound.filter(func(b): return is_instance_valid(b))
	var f := SilentKill.finder(alive, unfound)
	if f.is_empty():
		return
	unfound.erase(f[1])
	_say(f[0], "found_body" if lines.has("found_body") else "man_down")
	_attacked = true


func _on_local_died(g: NpcBody) -> void:
	kills += 1
	claimed.erase(g)
	var left0 := _alive()
	if SilentKill.unaware_cut(g) and not SilentKill.witnessed(g, left0):
		if standing:                         # issue #307: the standing hit still lands, quietly
			WorldState.change_standing("locals", int(cfg.get("alarm", {}).get("killed_standing", -8)),
				"A local was killed in the street.")
		silent_kills += 1
		unfound.append(g)
		return
	if DroidController.by_player(g.last_hit_by, player):
		if standing:
			WorldState.change_standing("locals", int(cfg.get("alarm", {}).get("killed_standing", -8)),
				"A local was killed in the street.")
		_attacked = true
	var left := _alive()
	if not left.is_empty():
		_say(_nearest(left, g.global_position), "man_down")


func _on_player_downed() -> void:
	if alarm.active():
		_say(_lead(_alive()), "downed")
	alarm.stand_down()
	_handle(alarm.drain())


## The player died and woke in the pit (Garrison._wake_in_pit): like the guards,
## the locals forget the fight and the face, whatever happened while the player
## was out (a stray bolt landing then would have raised the alarm again).
func forgive_player() -> void:
	alarm.stand_down()
	_handle(alarm.drain())
	_attacked = false
	claimed.clear()
	for g in _alive():
		g.perception = Perception.new(g.profile.get("perception", {}))
		var b: GuardBrain = brains.get(g)
		if b != null and b.state != GuardBrain.State.PATROL and b.state != GuardBrain.State.RETURN:
			b.stand_down()


# ------------------------------------------------------------------ helpers

func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player) or player.get("piloting") == true or player.get("is_downed") == true:
		return Vector3.INF
	return player.global_position


## (Only those it runs: the town's members list is the scene's own locals, which
## also holds the locals at the outposts, each run by its outpost's Townsfolk.)
func _alive() -> Array:
	var out: Array = []
	for g in members:
		if is_instance_valid(g) and not g.dead and brains.has(g):
			out.append(g)
	return out


func _lead(among: Array) -> NpcBody:
	if among.is_empty() or player == null:
		return null
	return _nearest(among, player.global_position)


func _nearest(among: Array, at: Vector3) -> NpcBody:
	var best: NpcBody = null
	var bd := INF
	for g in among:
		var d: float = g.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = g
	return best


## Calm, a local the player walks close by now and then talks of the beast.
func _beast_talk(alive: Array, ppos: Vector3) -> void:
	if _beast_cfg.is_empty() or ppos == Vector3.INF or _clock < _beast_next:
		return
	var g := _nearest(alive, ppos)
	if g == null or g.global_position.distance_to(ppos) > float(_beast_cfg.get("locals_say_m", 4.0)):
		return
	var said := PlanetBeast.lore(demo.planet)
	if said.is_empty():
		return
	var text := str(said[_rng.randi() % said.size()])
	_beast_next = _clock + float(_beast_cfg.get("locals_say_every_s", 30.0))
	beast_said.append(text)
	g.say(text, 4.0, false)


func _say(g: NpcBody, key: String) -> void:
	var list: Array = lines.get(key, [])
	if g == null or list.is_empty():
		return
	if key == _last_key and _clock - _last_key_t < 1.5:
		return
	_last_key = key
	_last_key_t = _clock
	barks_said.append(key)
	var shout_keys: Array = NpcBody.sound_cfg().get("shout_keys", [])
	g.say(str(list[_rng.randi() % list.size()]), 2.6, shout_keys.has(key))
