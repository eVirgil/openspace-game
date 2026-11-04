class_name AtmoFighter
extends Node3D
## The Remnant's interceptor in the port's sky (issue #76). It stands on the
## barracks pad (the town box with a "remnant_ship") and hunts you in the air:
##   - it takes off when you fly a ship stolen from an outpost, or when you are
##     wanted (the garrison's alarm is up or your Remnant standing is hostile) and
##     are `launch_distance` past the edge of the town; once the fleet is beaten
##     it never comes after you again (issue #180),
##   - it flies with the same AtmoFlight as your ship (the ground, the air thinning,
##     crashing) and fights with the same parts as the space dogfights: the
##     FighterBrain pilot (pursue, attack, break, extend) from a pilot profile, the
##     ship's ShipLoadout guns firing real bolts (ShipPilot.ship_bolt), its
##     ShipDefense shield and hull behind a ShipHull your bolts hit,
##   - on top of the space pilot it keeps off the ground (`floor_agl` now and
##     `look_ahead_s` ahead) and under the edge of space (`ceiling_margin`),
##   - with nothing to chase for `give_up_s` (you landed, climbed into space, are
##     not wanted any more) it flies home and lands on its pad,
##   - shot down, it blows up and a new one stands on the pad `respawn_s` later;
##     if it shoots you down you both start again in town (you in the pit, it on
##     its pad),
##   - standing on its pad it is a ship you can take, like an outpost's (a pilot
##     berth): taking it sounds the barracks alarm, you fly that one away, and a
##     new one lands on the pad `replace_s` later (once the pad is clear) to come
##     after you; another ship's guns or your hand weapons can shoot it to pieces
##     there (a new one `respawn_s` later).
## Numbers: the ship's "scramble" block (content/core/ships/remnant_interceptor.json)
## and its pilot (content/core/pilots/remnant_hunter.json).
##
## Tests and traces drive it through the same step() the frame calls.

const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const ShipDefense := preload("res://src/systems/flight/ship_defense.gd")
const ShipLoadout := preload("res://src/systems/flight/ship_loadout.gd")
const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const MissileLock := preload("res://src/systems/flight/missile_lock.gd")

enum Mode { PARKED, LAUNCHING, HUNTING, RETURNING, DOWN }

const BARRACKS := "barracks"      ## its berth's "outpost" (ShipPilot: taking it is stealing)

signal launched
signal shot_down
signal landed_home

var demo                          ## the town scene (town_demo.gd)
var pilot: ShipPilot              ## the player's flying
var content
var ship_id := ""
var cfg: Dictionary = {}          ## the ship's data
var sc: Dictionary = {}           ## its "scramble" block
var atmo: AtmoFlight
var brain
var guns                          ## ShipLoadout
var defense                       ## ShipDefense
var hull: ShipHull
var visual: Node3D
var pad_box: Dictionary = {}
var home := Vector3.ZERO
var home_yaw := 0.0
var mode := Mode.PARKED
var respawn_left := -1.0
var idle_left := 0.0              ## seconds left with nothing to chase before it goes home
var reset_pending := false        ## it shot you down: back to the pad once you are towed
var berth := -1                   ## its pilot berth while it stands on the pad (yours to take), or -1

## For traces and tests.
var launches := 0
var kills_of_player := 0
var times_shot_down := 0
var shots := 0
var lock = MissileLock.new()      ## its seekers' lock on your ship (the cockpit's seeker warning reads it)
var seekers := 0                  ## seekers it has launched at you (traces, tests)
var _seeker_gap := 0.0            ## seconds before it may launch another
var times_taken := 0
var times_wrecked := 0
var log_events: Array = []

var _was_crashed := false


func setup(town_demo, box: Dictionary, ship_pilot: ShipPilot) -> void:
	demo = town_demo
	pilot = ship_pilot
	pad_box = box
	name = "RemnantInterceptor"


func _ready() -> void:
	content = CoreContent.new()
	content.load_from()
	ship_id = str(pad_box.get("remnant_ship", "remnant_interceptor"))
	cfg = content.get_ship(ship_id)
	sc = cfg.get("scramble", {})
	atmo = AtmoFlight.new()
	atmo.setup(cfg, pilot.ground)
	brain = FighterBrain.new(content.get_pilot(str(cfg.get("pilot", "veteran"))), atmo.flight, 76)
	var mn := WorldGround._v3(pad_box.min)
	var mx := WorldGround._v3(pad_box.max)
	home = Vector3((mn.x + mx.x) * 0.5, mx.y, (mn.z + mx.z) * 0.5)
	home_yaw = deg_to_rad(float(pad_box.get("parked_yaw_deg", 0.0)))
	_build_visual()
	_reset_home()


func _build_visual() -> void:
	var look_id := str(cfg.get("look", ""))
	if demo.use_look and look_id != "":
		var kit := ShipKit.new(demo._flat_mats())
		visual = kit.build(kit.look_for(look_id, Territory.owner(Territory.BARRACKS)))
	else:
		visual = Node3D.new()
	visual.name = "Ship"
	add_child(visual)
	var acc := [null]
	TownDecor._merge_aabb(visual, Transform3D.IDENTITY, acc)
	var size := Vector3(9.0, 2.5, 8.0)
	var center := Vector3.ZERO
	if acc[0] != null:
		var a: AABB = acc[0]
		atmo.clearance = maxf(0.3, -a.position.y)
		size = a.size
		center = a.get_center()
	hull = ShipHull.new()
	hull.name = "ShipHull"
	if acc[0] == null or not hull.fit(visual):
		hull.fit_box(size, center)
	visual.add_child(hull)
	hull.on_damage = _on_hit


## The barracks changed hands: the interceptor on its pad takes the holder's paint
## (the locals': the same model, a little green).
func repaint(owner: String) -> void:
	var look_id := str(cfg.get("look", ""))
	if visual != null and look_id != "" and demo.use_look:
		var kit := ShipKit.new(demo._flat_mats())
		kit.repaint(visual, kit.look_for(look_id, owner))


func p(key: String, fallback: float) -> float:
	return float(sc.get(key, fallback))


func mode_label() -> String:
	return Mode.keys()[mode]


func flying() -> bool:
	return mode == Mode.LAUNCHING or mode == Mode.HUNTING or mode == Mode.RETURNING


func position() -> Vector3:
	return atmo.position()


func velocity() -> Vector3:
	return atmo.flight.velocity() if atmo.state == AtmoFlight.State.FLYING else Vector3.ZERO


# ------------------------------------------------------------------ who it hunts

## Your ship, while it is in the air down here (not out in a space fight).
func target_up() -> bool:
	return pilot != null and pilot.piloting and (pilot.fight == null or pilot.fight.sheltered) \
		and pilot.atmo.state in [AtmoFlight.State.LIFTOFF, AtmoFlight.State.FLYING, AtmoFlight.State.LANDING]


## The Remnant wants you: a stolen ship, the garrison's alarm or a hostile standing.
## Issue #180: once the fleet is beaten the Remnant is defeated and it stops
## chasing (one already up gives up and flies home).
func wanted() -> bool:
	if Story.remnant_hostile():
		return false
	if pilot != null and pilot.flying_stolen():
		return true
	var g = demo.garrison if "garrison" in demo else null
	if g == null:
		return false
	return g.alarm.active() or g.checkpoint.base_band(int(WorldState.standing.get("imperial_remnant", 0))) == "hostile"


## Should it take off now?
func should_scramble() -> bool:
	if not target_up() or not wanted():
		return false
	if pilot.flying_stolen():
		return true
	return not TownNav.in_town(demo.town, pilot.atmo.position(), p("launch_distance", 300.0))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	step(dt)


func step(dt: float) -> void:
	_watch_player()
	match mode:
		Mode.PARKED:
			if _taken():
				_hand_over()
			elif _wrecked():
				_wrecked_on_pad()
			elif should_scramble():
				scramble()
		Mode.LAUNCHING:
			atmo.set_command(0.0, 0.0, 0.0, 0.0, false)
			_events(atmo.step(dt))
			if atmo.state == AtmoFlight.State.FLYING:
				mode = Mode.HUNTING
				idle_left = p("give_up_s", 10.0)
		Mode.HUNTING:
			_hunt(dt)
		Mode.RETURNING:
			_return(dt)
		Mode.DOWN:
			respawn_left -= dt
			if respawn_left <= 0.0 and _pad_clear():
				_reset_home()
	defense.step(dt)
	_sync_visual()


func scramble() -> bool:
	if mode != Mode.PARKED or not atmo.takeoff():
		return false
	_withdraw_berth()
	_set_solid(true)
	mode = Mode.LAUNCHING
	launches += 1
	launched.emit()
	_toast(GameFlow.label("interceptor_up"))
	return true


## It shot you down: once you are towed (in town again), it is back on its pad.
func _watch_player() -> void:
	if pilot == null:
		return
	var crashed: bool = pilot.piloting and pilot.atmo.state == AtmoFlight.State.CRASHED
	if crashed and not _was_crashed and flying():
		var last: Dictionary = pilot.log_events.back() if not pilot.log_events.is_empty() else {}
		if str(last.get("what", "")) == "shot_down":
			kills_of_player += 1
		reset_pending = true         # down while it was up: you both start again in town
	_was_crashed = crashed
	if reset_pending and not crashed and pilot.crash_left < 0.0:
		reset_pending = false
		if mode != Mode.DOWN:
			_reset_home()


func _hunt(dt: float) -> void:
	var up := target_up()
	if up and wanted():
		idle_left = p("give_up_s", 10.0)
	else:
		idle_left -= dt
		if idle_left <= 0.0:
			mode = Mode.RETURNING
			_toast(GameFlow.label("interceptor_home"))
			return
	var b = brain
	b.has_target = up
	if up:
		b.target_pos = pilot.atmo.position()
		b.target_vel = pilot.atmo.flight.velocity()
	b.arena_center = b.target_pos if up else home + atmo.up() * p("return_altitude", 90.0)
	b.arena_radius = 100000.0
	var pc: Dictionary = guns.group_config("primary")
	b.bolt_speed = float(pc.get("bolt_speed", 300.0))
	b.weapon_range = float(pc.get("range", 900.0))
	# Its seekers lock on your ship as yours do on it: held in the cone and range for
	# lock_time, and it launches one (then every seeker_gap_s at most).
	_seeker_gap = maxf(0.0, _seeker_gap - dt)
	if up:
		lock.update(dt, 1, atmo.flight.forward(), pilot.atmo.position() - atmo.position())
	else:
		lock.reset()
	b.has_missiles = guns.has_group("secondary") and p("seekers", 1.0) > 0.0
	b.missile_locked = lock.is_locked()
	b.update(dt)
	var cmd: Dictionary = b.command.duplicate()
	var fire: bool = b.fire_primary and up
	var seeker: bool = b.fire_secondary and up and _seeker_gap <= 0.0
	if _keep_clear(cmd):
		fire = false
		seeker = false
	atmo.set_command(cmd.pitch, cmd.yaw, cmd.roll, cmd.throttle, cmd.boost)
	_events(atmo.step(dt))
	_fire(dt, fire, seeker)


## The space pilot does not know about the ground. Pull up when it is low now or
## will be soon, and level out under the edge of space. Rewrites `cmd`; true when
## it took over (no shooting while it does).
func _keep_clear(cmd: Dictionary) -> bool:
	var f = atmo.flight
	var up := atmo.up()
	var ahead: Vector3 = f.position + f.velocity() * p("look_ahead_s", 2.5)
	var floor_h := p("floor_agl", 45.0)
	var low := atmo.agl() < floor_h or pilot.ground.height_above(ahead - up * atmo.clearance) < floor_h * 0.6
	var high := atmo.altitude() > atmo.space_altitude - p("ceiling_margin", 900.0)
	if not low and not high:
		return false
	var fwd: Vector3 = f.forward()
	var flat := (fwd - up * fwd.dot(up))
	if flat.length() < 0.05:
		flat = f.basis.y - up * f.basis.y.dot(up)
	var aim: Vector3 = f.position + flat.normalized() * 100.0 + up * (90.0 if low else -60.0)
	steer(cmd, aim)
	cmd.throttle = 1.0
	return true


## The brain's steering toward a world point, into `cmd`.
func steer(cmd: Dictionary, point: Vector3) -> void:
	brain._steer_to(point, float(cmd.get("throttle", 1.0)), bool(cmd.get("boost", false)))
	for k in ["pitch", "yaw", "roll"]:
		cmd[k] = brain.command[k]


## Home: across at return_altitude, then straight down onto the pad.
func _return(dt: float) -> void:
	if atmo.state == AtmoFlight.State.LANDING:
		_events(atmo.step(dt))
		return
	if target_up() and wanted():
		mode = Mode.HUNTING
		idle_left = p("give_up_s", 10.0)
		return
	var up := atmo.up()
	var over := home + up * (p("return_altitude", 90.0) + atmo.clearance)
	var to := over - atmo.position()
	var flat := to - up * to.dot(up)
	var cmd := { "throttle": clampf(flat.length() / 300.0, 0.25, 1.0), "boost": false, "pitch": 0.0, "yaw": 0.0, "roll": 0.0 }
	if flat.length() < p("land_from", 60.0):
		atmo.state = AtmoFlight.State.LANDING    # straight down onto the pad, wherever it is
		_events(atmo.step(dt))
		return
	if not _keep_clear(cmd):
		steer(cmd, over)
	atmo.set_command(cmd.pitch, cmd.yaw, cmd.roll, cmd.throttle, false)
	_events(atmo.step(dt))


func _events(events: Array) -> void:
	for e in events:
		log_events.append(e)
		match str(e.type):
			"crashed":
				_go_down(e.at, false)
			"landed":
				if mode == Mode.RETURNING:
					_reset_home()
					landed_home.emit()


func _fire(dt: float, trigger: bool, seeker := false) -> void:
	var v: Vector3 = atmo.flight.velocity()
	var volley := false
	for s in guns.fire(dt, atmo.transform(), v, trigger, seeker, 1 if seeker else -1):
		if str(s.kind) == "missile":
			_launch_seeker(s)
			continue
		if str(s.kind) != "bolt":
			continue
		var b := ShipPilot.ship_bolt(s, hull, content, pilot.ground, Color(str(sc.get("bolt_color", "#ff3020"))))
		demo.add_child(b)
		b.global_position = s.origin
		shots += 1
		volley = true
	if volley:
		Sound.play("ship_cannon", atmo.position())


## One seeker at your ship: a ship bolt that turns after your hull (ShipPilot's own
## seekers, the other way round), and goes up where it lands, splash and all.
func _launch_seeker(s: Dictionary) -> void:
	var b := ShipPilot.ship_bolt(s, hull, content, pilot.ground, Color(str(sc.get("bolt_color", "#ff3020"))))
	b.streak_length = 1.6
	b.streak_radius = 0.15
	b.seek = pilot.hull
	b.turn_rate = float(s.get("turn_rate", 0.0))
	b.blast_size = float(s.get("blast_size", 0.0))
	demo.add_child(b)
	b.global_position = s.origin
	seekers += 1
	_seeker_gap = p("seeker_gap_s", 10.0)
	lock.reset()
	Sound.play("ship_missile", s.origin)


## What it has on your ship now: `locks` (1 while its seekers hold you) and
## `missiles` (its seekers in the air turning after your hull). The cockpit's seeker
## warning (SeekerWarning) goes off on either, with the space fight on or off.
func seekers_on_player() -> Dictionary:
	var out := { "locks": 0, "missiles": 0 }
	if pilot == null or pilot.hull == null or not is_inside_tree():
		return out
	if mode == Mode.HUNTING and target_up() and lock.is_locked():
		out.locks = 1
	for b in get_tree().get_nodes_in_group("bolts"):
		if is_instance_valid(b) and "seek" in b and b.seek == pilot.hull:
			out.missiles += 1
	return out


# ------------------------------------------------------------------ damage

## A bolt hit it. The Remnant's own (troopers, droids) do not count; parked it
## shrugs it off too (the pad's ship is not a target until it flies).
func _on_hit(amount: float, shooter: Node) -> void:
	if not flying():
		return
	if shooter != null and "faction" in shooter and str(shooter.get("faction")) == str(cfg.get("faction", "")):
		return
	if shooter == hull:
		return
	defense.apply_damage(amount)
	hull.took_damage()                  # issue #181: a hit marker for whoever shot it
	if brain != null:
		brain.notify_hit()
	if not defense.is_alive():
		_go_down(atmo.position(), true)


func _go_down(at: Vector3, shot: bool) -> void:
	if mode == Mode.DOWN:
		return
	atmo._crash(at, "shot_down" if shot else "ground")
	mode = Mode.DOWN
	hull.dead = true
	respawn_left = p("respawn_s", 120.0)
	visual.visible = false
	_set_solid(false)
	if pilot != null:
		pilot._crash_fx(at)
	Sound.play("vehicle_boom", at)
	if shot:
		times_shot_down += 1
		WorldState.change_standing("imperial_remnant", int(sc.get("kill_standing", -10)), "A Remnant interceptor was shot down.")
		WorldState.log_event("A Remnant interceptor was shot down over the desert.")
		_toast(GameFlow.label("interceptor_down"))
	shot_down.emit()


## On the pad, patched up, waiting.
func _reset_home() -> void:
	atmo.reached_space = false
	atmo.park(home, home_yaw)
	defense = ShipDefense.new(cfg)
	guns = ShipLoadout.new(cfg, content)
	lock.configure(guns.group_config("secondary"))
	lock.reset()
	_seeker_gap = 0.0
	mode = Mode.PARKED
	hull.dead = false
	respawn_left = -1.0
	visual.visible = true
	_sync_visual()
	_offer_berth()
	_set_solid(berth < 0)                # a berth's hull stands in for its own


func _set_solid(on: bool) -> void:
	hull.collision_layer = 1 if on else 0


# ------------------------------------------------------------------ on its pad

## On its pad it is a ship you can take or shoot to pieces: a pilot berth, like an
## outpost's (ShipPilot.add_outpost_berth), whose hull you bump into and shoot,
## from a ship or on foot ("foot_target", ShipPilot._parked_target). Taking it
## sounds the town garrison's alarm ("town_alarm", ShipPilot._steal).
func _offer_berth() -> void:
	if pilot == null:
		return
	if berth < 0:
		berth = pilot.add_outpost_berth(visual, ship_id, BARRACKS)
		pilot.berths[berth]["where"] = GameFlow.label("barracks_where")
		pilot.berths[berth]["town_alarm"] = true
		pilot.berths[berth]["foot_target"] = true
	var b: Dictionary = pilot.berths[berth]
	b.clearance = atmo.clearance
	b.destroyed = false
	b.erase("defense")                   # patched up with the rest of it
	_berth_solid(b, true)


## Taking off after you: not a berth while it flies (marked destroyed, so nobody
## boards it; its own hull takes the hits in the air).
func _withdraw_berth() -> void:
	if berth >= 0:
		var b: Dictionary = pilot.berths[berth]
		b.destroyed = true
		_berth_solid(b, false)


func _berth_solid(b: Dictionary, on: bool) -> void:
	var h: ShipHull = b.hull
	if h != null and is_instance_valid(h):
		h.dead = not on
		h.collision_layer = 1 if on else 0
		h.collision_mask = 1 if on else 0


## You climbed into it on its pad.
func _taken() -> bool:
	return berth >= 0 and pilot.piloting and pilot.berth == berth


## Shot to pieces on its pad, by a ship or on foot (ShipPilot._hit_parked).
func _wrecked() -> bool:
	return berth >= 0 and bool(pilot.berths[berth].get("destroyed", false))


## You took it: that model is the pilot's now (it flies off as your stolen ship),
## and a new one lands on the pad `replace_s` later, once the pad is clear, to
## come after you as for any stolen ship.
func _hand_over() -> void:
	var taken := visual
	hull.queue_free()
	taken.reparent(demo)
	berth = -1
	times_taken += 1
	_build_visual()
	mode = Mode.DOWN
	respawn_left = p("replace_s", 8.0)
	hull.dead = true
	visual.visible = false
	_set_solid(false)


## Shot to pieces on its pad: the Remnant notice, and a new one stands there
## `respawn_s` later.
func _wrecked_on_pad() -> void:
	mode = Mode.DOWN
	hull.dead = true
	respawn_left = p("respawn_s", 120.0)
	visual.visible = false
	_set_solid(false)
	times_wrecked += 1
	WorldState.change_standing("imperial_remnant", int(sc.get("kill_standing", -10)), "A Remnant interceptor was shot to pieces on its pad.")
	shot_down.emit()


## Nothing on the pad for a new one to land on: your ship, or you on foot.
func _pad_clear() -> bool:
	if pilot == null:
		return true
	var r := p("pad_clear", 30.0)
	if pilot.atmo.position().distance_to(home) < r:
		return false
	var you = demo._player if "_player" in demo else null
	return pilot.piloting or you == null or you.global_position.distance_to(home) >= r


func _sync_visual() -> void:
	if visual != null:
		visual.global_transform = atmo.transform()
		var up := atmo.state == AtmoFlight.State.FLYING
		ShipKit.throttle_flames(visual, atmo.flight.throttle if up else 0.0, atmo.flight.boosting,
			get_physics_process_delta_time())


func _toast(text: String) -> void:
	if text != "" and pilot != null and pilot.piloting and pilot.hud != null:
		pilot.hud.toast(text, 3.5)


# ------------------------------------------------------------------ the HUD

## What the pilot's HUD draws for it: where it is, where to aim (the lead), how
## hurt it is. Empty while it is not in the air.
func hud_target() -> Dictionary:
	if not flying() or mode == Mode.LAUNCHING or pilot == null:
		return {}
	var me := pilot.atmo
	var pc: Dictionary = pilot.guns.group_config("primary") if pilot.guns != null else {}
	var lead: Dictionary = LeadSolver.intercept(me.position(), me.flight.velocity(), atmo.position(), velocity(),
		float(pc.get("bolt_speed", 300.0)))
	return { "pos": atmo.position(), "lead": lead.point, "lead_ok": bool(lead.valid),
		"label": str(cfg.get("label", "")), "dist": me.position().distance_to(atmo.position()),
		"hull": float(defense.hull_hp()) / maxf(1.0, float(defense.hull_max())) }
