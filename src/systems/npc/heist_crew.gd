class_name HeistCrew
extends Node
## Issue #310: who goes with you on a heist (Heist). While one is on:
##   - a crew member: the side's soldier profile (heist_crew_local / _remnant) as
##     a body in no garrison and no townsfolk, so nobody's alarm is theirs and the
##     guards' senses stay on you. They keep a few steps behind you (on the navmesh
##     where there is one, straight over open sand where there is not), catch up
##     when you run, and turn up on your trail when you leave them far behind.
##     They shoot only whoever is fighting you (DroidController.enemies(): a
##     garrison whose alarm is up, someone who shot at you), so sneaking in works
##     with them along. Barks from content/core/story/heist.json; a short AI card
##     (heist_crew_card.json) you can talk to on [E].
##   - an assassin droid lent by DroidController (lend): it follows and fights like
##     one of yours, but is not in your roster.
## Killed (or knocked out), they stay down for the rest of the heist; the heist
## goes on without them. When it ends (paid, downed, called off, flasks lost) the
## crew member walks off and is gone, and the droid goes home.
##
## The headless test drives tick() with its own player node.

var demo                              ## town_demo.gd (or null in a test)
var player: Node3D
var gear: GearController
var body: NpcBody                     ## the crew member, while one is out
var spot: TalkSpot
var host
var fights := 0                       ## shots fired at enemies, for tests and traces
var _run := -1                        ## the heist run the crew is out for
var _leaving := 0.0                   ## > 0: walking off, seconds left before they go
var _leave_to := Vector3.INF
var _burst := 0.0
var _rest := 0.0
var _bark_cd := 0.0
var _foe: Node3D
var _free_walk_left := 0.0
var _fails_seen := 0
var _was_hacked := false


func setup(p_demo, p_player: Node3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear
	name = "HeistCrew"
	if demo != null and demo.get("pilot") != null:
		demo.pilot.woke.connect(_on_woke)


func attach_host(h) -> void:
	host = h


func c(key: String, fallback: float) -> float:
	return float(Heist.crew_cfg().get(key, fallback))


func _bark(kind: String) -> void:
	var lines: Array = Heist.crew_cfg().get("barks", {}).get(kind, [])
	if body != null and is_instance_valid(body) and not body.dead and not lines.is_empty():
		body.say(str(lines[randi() % lines.size()]), 3.0)


func _toast(text: String) -> void:
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 5.0)


## You woke up after being downed: the heist is off.
func _on_woke() -> void:
	if Heist.on_downed():
		_toast(Heist.line("downed"))


func _physics_process(dt: float) -> void:
	tick(dt)


## One frame: the crew follow the heist's state.
func tick(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if Heist.on() and Heist.check_lost():
		_toast(Heist.line("lost"))
	if not Heist.on():
		_dismiss(dt)
		return
	var run := int(WorldState.heist.get("run", 0))
	if run != _run:
		_run = run
		_leaving = 0.0
		_was_hacked = false
	if bool(player.get("piloting")):
		return                          # they wait while you fly; they catch up on landing
	_sync_droid()
	if body == null and not bool(WorldState.heist.get("crew_down", false)):
		_spawn()
	if body != null and is_instance_valid(body) and not body.dead:
		_drive(dt)
		if Heist.hacked() and not _was_hacked:
			_bark("hacked")
	_was_hacked = Heist.hacked()


# ------------------------------------------------------------------ the droid

func _sync_droid() -> void:
	var dc = demo.get("droids") if demo != null else null
	if dc == null:
		return
	if dc.lent_down:
		WorldState.heist["droid_down"] = true
	if bool(WorldState.heist.get("droid_down", false)):
		return
	var side: Dictionary = Heist.crew_cfg().get(Heist.side(), {})
	dc.lend("assassin", str(side.get("droid", "white")))


# ------------------------------------------------------------------ the crew member

func _spawn() -> void:
	if demo == null or not demo.has_method("make_npc"):
		return
	var side: Dictionary = Heist.crew_cfg().get(Heist.side(), {})
	var soldier: Dictionary = demo._content().get_soldier(str(side.get("soldier", "heist_crew_local")))
	if soldier.is_empty():
		return
	var at := _behind(c("follow", 3.0))
	var key := "npc:heist_crew/%d" % _run
	body = demo.make_npc(soldier, at, player.rotation.y, "heist_crew", key)
	if body == null:
		return
	body.set_meta("heist_crew", true)
	body.died.connect(_on_died)
	if str(WorldState.heist.get("crew", "")) == "":
		WorldState.heist["crew"] = body.display_name if body.display_name != "" else "your crew"
		_toast(Heist.line("joined") % Heist.crew_name())
		_bark("start")
	_add_spot()


func _on_died() -> void:
	WorldState.heist["crew_down"] = true
	_toast(Heist.line("crew_down") % Heist.crew_name())
	_drop_spot()


## A point `back` metres behind you, on the sand.
func _behind(back: float) -> Vector3:
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	var at: Vector3 = player.global_position - fwd.normalized() * back
	return at + Vector3(0, 0.3, 0)


## Follow, or fight whoever is fighting you.
func _drive(dt: float) -> void:
	_bark_cd -= dt
	var d := body.global_position.distance_to(player.global_position)
	if d > c("rejoin", 45.0):
		body.global_position = _behind(c("follow", 3.0) + 2.0)      # left far behind: on your trail
		body.stop()
		return
	_walk_mode(dt)
	_foe = _enemy()
	if _foe != null:
		_fight(dt)
		if d > c("catch_up", 9.0):
			body.go_to(_behind(c("follow", 3.0)), true)
		else:
			body.stop()
		return
	body.aim_point = Vector3.INF
	body.hold_fire(dt)
	body.clear_face()
	if d > c("follow", 3.0) + 1.0:
		body.go_to(_behind(c("follow", 3.0)), d > c("catch_up", 9.0))
	elif body.command.go_to != Vector3.INF:
		body.stop()


## The navmesh where it has a path, straight over the sand where it does not
## (the desert between the town and the outposts has none).
func _walk_mode(dt: float) -> void:
	if demo == null:
		return
	if _free_walk_left > 0.0:
		_free_walk_left -= dt
		if _free_walk_left <= 0.0:
			body.nav = demo.nav
			body.free_walk = false
			_fails_seen = body.path_failures
		return
	if body.path_failures > _fails_seen:
		_fails_seen = body.path_failures
		body.nav = null
		body.free_walk = true
		_free_walk_left = 3.0


## The nearest one fighting you, in range with a clear line, or null.
func _enemy() -> Node3D:
	var dc = demo.get("droids") if demo != null else null
	if dc == null:
		return null
	var best: Node3D = null
	var best_d := c("range", 35.0)
	for e in dc.enemies():
		if not is_instance_valid(e) or e == body:
			continue
		var dd: float = body.global_position.distance_to(e.global_position)
		if dd < best_d and _clear(e):
			best = e
			best_d = dd
	return best


func _clear(e: Node3D) -> bool:
	if not body.is_inside_tree():
		return true
	var to := _chest(e)
	var q := PhysicsRayQueryParameters3D.create(body.eye_position(), to)
	q.exclude = [body.get_rid(), player.get_rid()] if player is CollisionObject3D else [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var col: Object = hit.collider
	return col == e or (col is Node and (e.is_ancestor_of(col) or (col as Node).is_ancestor_of(e)))


func _chest(e: Node3D) -> Vector3:
	if e.has_method("center"):
		return e.center()
	if e.has_method("eye_position"):
		return e.eye_position() - Vector3(0, 0.3, 0)
	return e.global_position + Vector3(0, 1.2, 0)


## Bursts at the foe's chest once the rifle is up.
func _fight(dt: float) -> void:
	var at := _chest(_foe)
	body.face_point(at)
	body.aim_point = at
	if _bark_cd <= 0.0:
		_bark("fight")
		_bark_cd = c("bark_s", 7.0)
	if _rest > 0.0:
		_rest -= dt
		body.hold_fire(dt)
		return
	_burst += dt
	if _burst >= c("burst_s", 1.2):
		_burst = 0.0
		_rest = c("rest_s", 0.9)
	if body.carry.on_target():
		if body.fire_at(at, dt):
			fights += 1
	else:
		body.hold_fire(dt)


# ------------------------------------------------------------------ talk

func _add_spot() -> void:
	if host == null or body == null:
		return
	var card := NpcBrain._read(str(Heist.crew_cfg().get("card", "res://content/core/npcs/heist_crew_card.json")))
	card["name"] = Heist.crew_name()
	var brain := NpcBrain.new(null, card)
	brain.extra_brief = _brief
	spot = TalkSpot.new(brain, body, body.global_position)
	spot.radius = 2.2
	spot.face_height = 1.6
	host.add_spot(spot)


func _drop_spot() -> void:
	if host != null and spot != null:
		if host.active == spot:
			host.end_talk()
		host.spots.erase(spot)
	spot = null


## What the crew member knows: whose side, the outpost, who holds it, how many guards.
func _brief() -> Array:
	var id := Heist.target()
	var holder := Territory.owner(id)
	var guards := 0
	var ro = demo.get("outposts") if demo != null else null
	if ro != null:
		var o: Dictionary = ro.outpost(id)
		if not o.is_empty():
			guards = ro.people(o, holder).filter(func(g): return not g.dead).size()
	var mine := "the locals (the port's own people)" if Heist.side() == "locals" else "the Remnant (the old empire's army)"
	var them := "the Remnant" if holder == Territory.REMNANT else "the locals"
	var stage := "the flasks are in hand; now get them home" if Heist.holding() else \
		("the console is hacked; the stash lies in front of it" if Heist.hacked() else "you have not got in yet")
	return ["THE JOB: you work for %s. The target is the control room at %s, held by %s with %d guards there. Status: %s. Your cut is %d%% of the pay." % [
		mine, Story.outpost_label(id), them, guards, stage, roundi(Heist.cut() * 100.0)]]


# ------------------------------------------------------------------ the end

## The heist is over: the crew member walks off and is gone; the droid goes home.
func _dismiss(dt: float) -> void:
	var dc = demo.get("droids") if demo != null else null
	if dc != null and not dc.lent.is_empty():
		dc.give_back()
	if body == null:
		return
	if not is_instance_valid(body):
		body = null
		return
	if _leaving <= 0.0 and not body.dead:
		_drop_spot()
		_leaving = c("leave_s", 8.0)
		if str(WorldState.heist.get("ended", "")) == "paid":
			_bark("paid")
		var away: Vector3 = body.global_position - player.global_position
		away.y = 0.0
		_leave_to = body.global_position + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 40.0
		body.go_to(_leave_to)
		return
	_leaving -= dt
	if _leaving <= 0.0 or body.dead:
		_drop_spot()
		body.queue_free()
		body = null
		_leaving = 0.0


func _process(_dt: float) -> void:
	if spot != null and body != null and is_instance_valid(body):
		spot.stand = body.global_position
