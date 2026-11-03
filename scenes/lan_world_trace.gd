extends SceneTree
## Issue #402 trace (headless, loopback): one town for two players, across two real
## processes, each with a town built. scripts/test_lan_world.sh starts both:
##   - the guest's town runs no people of its own: every one is a copy of one of
##     the host's (as many copies as the host has people), each within 2.5 m of
##     where the host's last stood, plus 0.6 s of its walk (it follows behind),
##   - the guest shoots the nearest Remnant trooper copy until the host's dies: it
##     is dead in both games, and the guest's game hears the kill was theirs,
##   - the beast (the centipede): the guest's is a copy whose head is within 3 m
##     of the host's; the guest shoots it until the host's dies, and it is dead in
##     both games.
##
## Run: godot --headless --path . -s res://scenes/lan_world_trace.gd -- host|guest <port>

var role := ""
var port := 24992
var session
var link
var town
var fails := PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	port = int(args[1]) if args.size() > 1 else port
	_run.call_deferred()


func say(s: String) -> void:
	print("LAN_WORLD %s: %s" % [role, s])


func _wait(secs: float, until: Callable = Callable()) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < end:
		await physics_frame
		if until.is_valid() and until.call():
			return true
	return until.is_valid() and until.call()


func _build_town() -> void:
	town = load("res://scenes/town_demo.gd").new()
	town.set("use_look", false)
	root.add_child(town)
	current_scene = town
	await _wait(6.0, func(): return town.get("garrison") != null)
	await _wait(1.0)


func _run() -> void:
	await process_frame
	session = load("res://src/systems/net/net_session.gd")
	session.root = OS.get_user_data_dir() + "/lan_world_trace_"
	session._cfg = session.cfg().duplicate(true)
	session._cfg["port"] = port
	session._cfg["connect_timeout"] = 8.0
	if role == "host":
		await _build_town()
		if session.host(self, "Host") != OK:
			say("FAIL could not host")
			quit(1)
			return
		link = session.link
		await _host()
	else:
		await _wait(1.0)
		if session.join(self, "127.0.0.1", "Guest") != OK:
			say("FAIL could not join")
			quit(1)
			return
		link = session.link
		link.arrive_on_welcome = false
		if not await _wait(30.0, func(): return link.welcomed_in):
			fails.append("never let in")
			await _done()
			return
		await _build_town()
		await _guest()
	await _done()


func _done() -> void:
	for f in fails:
		say("FAIL " + f)
	say("PASS" if fails.is_empty() else "FAILED")
	session.leave()
	await process_frame
	quit(0 if fails.is_empty() else 1)


func _host() -> void:
	var people: Array = load("res://src/systems/net/net_world.gd").people(town)
	say("host's town: %d people" % people.size())
	if not await _wait(60.0, func(): return link.roster.size() > 1):
		fails.append("the guest never joined")
		return
	var dead_at_start := people.filter(func(n): return n.dead).size()
	# The guest kills one: wait for a death here, from the guest's hit.
	var killed := await _wait(60.0, func(): return people.any(func(n): return is_instance_valid(n) and n.dead and n.has_meta("net_hit_by")))
	if not killed:
		fails.append("no trooper here died of the guest's shots (%d dead at start)" % dead_at_start)
	else:
		say("a trooper died here of the guest's shots")
	var b = town.get("beast")
	if b != null and is_instance_valid(b):
		if await _wait(30.0, func(): return b.dead):
			say("the beast died here of the guest's shots")
		else:
			fails.append("the beast here never died")
	await _wait(3.0)


func _guest() -> void:
	var world = link.get_node("World")
	if not await _wait(15.0, func(): return world.snaps_heard > 3):
		fails.append("no snapshots of the host's town")
		return
	await _wait(load("res://src/systems/net/net_session.gd").n("npc_claim_s", 4.0) + 2.0)
	var people: Array = world.people(town)
	var copies: Array = world._bodies.values().filter(func(n): return is_instance_valid(n))
	say("town shared: %s; %d people here, %d of them copies; snapshots %d; meta %d; asked %d" % [town.lan_shared, people.size(), copies.size(), world.snaps_heard, world._meta.size(), world._asked.size()])
	if not town.lan_shared:
		fails.append("the guest's town was not built as the host's")
	if town.get("townsfolk") != null:
		fails.append("the guest's town runs its own townsfolk")
	if people.size() != copies.size() or copies.is_empty():
		fails.append("people here (%d) are not all copies (%d)" % [people.size(), copies.size()])
	var off := 0
	for id in world._bodies:
		var n = world._bodies[id]
		if is_instance_valid(n) and world.heard_at.has(id) and (n.global_position as Vector3).distance_to(world.heard_at[id]) > 2.5 + n.velocity.length() * 0.6:
			off += 1
			say("  off: %s %.1f m (here %s, host %s, going %s, path ok %s)" % [n.name, (n.global_position as Vector3).distance_to(world.heard_at[id]), str(n.global_position.snapped(Vector3.ONE * 0.1)), str((world.heard_at[id] as Vector3).snapped(Vector3.ONE * 0.1)), str(n.command.go_to != Vector3.INF), n.last_path_ok])
	say("%d of %d copies not where the host's stood" % [off, copies.size()])
	if off > 0:
		fails.append("%d copies are not where the host's are" % off)
	# Shoot the nearest Remnant copy (as a bolt from the guest's player would).
	var me: Vector3 = town._player.global_position
	var target = null
	for n in copies:
		if not n.dead and n.faction == "imperial_remnant" and (target == null or n.global_position.distance_to(me) < target.global_position.distance_to(me)):
			target = n
	if target == null:
		fails.append("no Remnant copy to shoot")
		return
	say("shooting %s" % target.name)
	var hp0 := int(target.health.hp)
	while not target.dead and await _wait(0.3) == false:
		if target.dead:
			break
		target.apply_damage_from(25.0, town._player)
		if world.hits_sent > 40:
			break
	await _wait(3.0, func(): return target.dead)
	say("hits sent %d; the copy dead: %s (hp was %d)" % [world.hits_sent, target.dead, hp0])
	if not target.dead:
		fails.append("the copy never died")
	if int(target.health.hp) == hp0 and not target.dead:
		fails.append("the copy took no damage from the host's word")
	await _beast_guest(world)


func _beast_guest(world) -> void:
	var b = town.get("beast")
	if b == null or not is_instance_valid(b):
		say("no beast in this town (none on the planet, or slain in this save): skipped")
		return
	if not await _wait(5.0, func(): return b.net_copy):
		fails.append("the beast here is not a copy of the host's")
		return
	await _wait(1.0)
	var host_at: Vector3 = b._net_at
	var off: float = (b._head_ground as Vector3).distance_to(host_at)
	say("beast: a copy, head %.1f m from the host's (hp %.0f)" % [off, b.hp])
	if off > 3.0 + b._net_vel.length() * 0.6:
		fails.append("the beast's head is %.1f m from the host's" % off)
	for i in 6:
		if b.dead:
			break
		b.apply_damage_from(500.0, town._player)
		await _wait(0.5)
	await _wait(3.0, func(): return b.dead)
	say("beast dead here: %s" % b.dead)
	if not b.dead:
		fails.append("the beast never died")
