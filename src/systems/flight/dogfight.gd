extends RefCounted
## Dogfight director (M10). Pure and headless-testable, like the M5 mission: it owns
## every ship in a space encounter (flight model, shield + hull, guns, seeker lock,
## and an AI pilot for everyone but a human player), the projectiles in flight, and
## the wave schedule, and it steps them all with one call.
##
## The encounter itself is data (content/core/encounters/*.json): which ship the
## player flies, wingmen, and enemy waves by ship id. Ships, guns and pilot
## personalities are data too, so a new fight is JSON only.
##
## Consumers:
##   scenes/m10_dogfight_trace.gd        -- headless, the player flown by the AI
##   scenes/flight/dogfight_demo.gd     -- playable, the player flown by input
## Both read the same ships[] and events, the M1-M8 "pure spine, node wraps it" rule.

const FlightModel := preload("res://src/systems/flight/flight_model.gd")
const ShipDefense := preload("res://src/systems/flight/ship_defense.gd")
const ShipLoadout := preload("res://src/systems/flight/ship_loadout.gd")
const MissileLock := preload("res://src/systems/flight/missile_lock.gd")
const ProjectileField := preload("res://src/systems/flight/projectile_field.gd")
const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")

enum State { IDLE, RUNNING, COMPLETE, FAILED }

## How much faster and bigger a space fight is than the ships', pilots' and guns'
## own numbers (speed_scale, range_scale, ...). See its note.
const TUNE_PATH := "res://content/core/flow/space_fight.json"
static var _tune_cache: Dictionary = {}

const TEAM_PLAYER := "player"
const TEAM_HOSTILE := "hostile"

var content
var encounter: Dictionary = {}
var tune: Dictionary = {}        ## space_fight.json, or every scale 1.0 (set before start())
var state := State.IDLE
var t := 0.0
var rng_seed := 1

var ships: Array = []            ## every ship ever spawned (dead ones stay, alive=false)
var projectiles = ProjectileField.new()
var events: Array = []           ## this step's events (cleared each step)
var player_id := -1
var player_target_id := -1
var arena_center := Vector3.ZERO
var arena_radius := 1500.0
var arena_follow := false   ## the arena moves with the player (ShipPilot, in the cruiser's sky: everyone comes along)
## The player is out of the fight for now (ShipPilot: down in the cruiser's bay,
## docking, on foot, or under the edge of space): the director neither flies her
## nor lets anyone target or hit her, and everyone else fights on. Her flight model
## is the caller's to move meanwhile (the arena still follows it).
var player_sheltered := false
## Issue #46: the heading (radians about +Y) waves arrive from, so a fight that
## starts in the port's sky meets them ahead of the player. 0 = from -Z, as before.
var wave_yaw := 0.0

var wave_index := -1
var _wave_timer := 0.0
var _next_id := 1
## Issue #15: when set, every pilot is named as they spawn (NameHooks, from the
## ship's "naming" block) and the player's ship gets its own name. `name_scope`
## keeps a sortie's pilots apart from the last one's ("pilot:<encounter>/<n>").
## Null (the default, and in the pure tests) = nobody is named.
var names: NameBook
var name_scope := "pilot"

## Running totals for traces and the HUD.
var stats := { "shots": 0, "missiles": 0, "hits": 0, "missile_hits": 0, "kills": 0,
	"player_kills": 0, "waves": 0 }

## The human (or test) pilot's command for the player ship.
var _player_cmd := { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.6, "boost": false }
var _player_primary := false
var _player_secondary := false


func _init(content_ref = null, encounter_id: String = "", seed_value: int = 1) -> void:
	content = content_ref
	rng_seed = seed_value
	tune = load_tune()
	if content != null and encounter_id != "":
		encounter = content.get_encounter(encounter_id)
		if encounter.is_empty():
			push_warning("Dogfight: unknown encounter id: ", encounter_id)


# ---- setup ------------------------------------------------------------------

## Spawn the player and wingmen and arm the first wave.
func start() -> void:
	var arena: Dictionary = encounter.get("arena", {})
	arena_center = _vec(arena.get("center", [0, 0, 0]))
	arena_radius = float(arena.get("radius", 1500.0)) * scale("range_scale")
	var pl: Dictionary = encounter.get("player", {})
	if not pl.is_empty():
		player_id = spawn_ship(str(pl.get("ship", "")), TEAM_PLAYER, _vec(pl.get("spawn", [0, 0, 0])),
			_vec(pl.get("facing", [0, 0, -1])), "", true)
	for a in encounter.get("allies", []):
		spawn_ship(str(a.get("ship", "")), TEAM_PLAYER, _vec(a.get("spawn", [0, 0, 0])),
			_vec(a.get("facing", [0, 0, -1])), str(a.get("pilot", "")), false)
	wave_index = -1
	_arm_next_wave()
	state = State.RUNNING


## Add a ship by id. Returns its runtime id, or -1 if the ship id is unknown.
## pilot_id "" uses the ship's default pilot. A player ship has no brain until
## set_player_autopilot(true).
func spawn_ship(ship_id: String, team: String, pos: Vector3, facing: Vector3,
		pilot_id: String = "", is_player: bool = false) -> int:
	var cfg: Dictionary = content.get_ship(ship_id) if content != null else {}
	if cfg.is_empty():
		push_warning("Dogfight: unknown ship id: ", ship_id)
		return -1
	if is_player:
		cfg = ShipUpgrades.apply(cfg, ship_id)      # issue #207: what T-89 fitted
	elif team == TEAM_HOSTILE and cfg.get("dogfight_foe") is Dictionary:
		cfg = CoreContent._merge(cfg, cfg.dogfight_foe)   # as the enemy in a space fight: its own numbers
	var id := _next_id
	_next_id += 1
	var flight = FlightModel.new(cfg.get("flight", {}))
	flight.speed_scale = scale("speed_scale")
	flight.accel_scale = scale("accel_scale")
	flight.turn_mult = scale("turn_scale")
	flight.speed = flight.cruise_speed(flight.throttle)
	flight.position = pos
	flight.face(facing)
	var loadout = ShipLoadout.new(cfg, content)
	loadout.convergence *= scale("range_scale")
	for h in loadout.hardpoints:
		h.cfg = _space_weapon(h.cfg)
	var lock = MissileLock.new()
	lock.configure(loadout.group_config("secondary"))
	var pid := pilot_id if pilot_id != "" else str(cfg.get("pilot", ""))
	var ship := {
		"id": id,
		"ship_id": ship_id,
		"cfg": cfg,
		"look": str(cfg.get("look", ship_id)),
		"team": team,
		"pilot_id": pid,
		"is_player": is_player,
		"alive": true,
		"flight": flight,
		"defense": ShipDefense.new(cfg),
		"loadout": loadout,
		"lock": lock,
		"brain": null,
		"target_id": -1,
		"retarget_left": 0.0,
		"radius": float(cfg.get("hit_radius", 3.0)) * scale("hit_radius_scale"),
		"kills": 0,
		"pilot_name": "",
		"callsign": "",
		"vessel_name": "",
	}
	if names != null:
		var naming: Dictionary = cfg.get("naming", {})
		if is_player:
			ship.vessel_name = NameHooks.vessel(cfg, "vessel:player/" + ship_id, names)
		else:
			var key := "%s/%d" % [name_scope, id]
			ship.pilot_name = NameHooks.person(naming, key, names)
			ship.callsign = NameHooks.callsign(naming, key, names)
	if not is_player:
		ship.brain = _make_brain(pid, flight, id)
	ships.append(ship)
	events.append({ "type": "spawn", "id": id, "ship_id": ship_id, "team": team })
	return id


func _make_brain(pilot_id: String, flight, id: int):
	var prof: Dictionary = content.get_pilot(pilot_id) if content != null else {}
	var b = FighterBrain.new(prof, flight, rng_seed * 7919 + id * 104729)
	b.reach = scale("range_scale")
	return b


## One of tune's scales (1.0 when it is not there).
func scale(key: String) -> float:
	return float(tune.get(key, 1.0))


## A copy of a gun's or seeker's data blown up to the fight's speeds and distances.
func _space_weapon(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	for k in ["range", "lock_range", "splash_radius"]:
		if out.has(k):
			out[k] = float(out[k]) * scale("range_scale")
	if out.has("bolt_speed"):
		out["bolt_speed"] = float(out["bolt_speed"]) * scale("bolt_speed_scale")
	if out.has("turn_rate"):
		out["turn_rate"] = float(out["turn_rate"]) * scale("turn_scale")
	return out


## space_fight.json (read once).
static func load_tune() -> Dictionary:
	if _tune_cache.is_empty():
		var f := FileAccess.open(TUNE_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_tune_cache = d if d is Dictionary else { "loaded": false }
	return _tune_cache


## Let the AI fly the player ship (the headless trace's "bot pilot").
func set_player_autopilot(on: bool) -> void:
	var s = get_ship(player_id)
	if s.is_empty():
		return
	s.brain = _make_brain(s.pilot_id, s.flight, s.id) if on else null


func set_player_command(pitch: float, yaw: float, roll: float, throttle: float, boost: bool,
		primary: bool, secondary: bool) -> void:
	_player_cmd = { "pitch": pitch, "yaw": yaw, "roll": roll, "throttle": throttle, "boost": boost }
	_player_primary = primary
	_player_secondary = secondary


# ---- queries ----------------------------------------------------------------

func get_ship(id: int) -> Dictionary:
	for s in ships:
		if s.id == id:
			return s
	return {}


## What an enemy has on the player's ship right now: `locks` (hostile ships holding a
## seeker lock on her) and `missiles` (their seekers in flight at her). Nothing while
## she is down, sheltered, or flying with no enemy about. The cockpit's seeker warning
## (SeekerWarning) goes off on either.
func seekers_on_player() -> Dictionary:
	var out := { "locks": 0, "missiles": 0 }
	var me := get_ship(player_id)
	if me.is_empty() or not me.alive or player_sheltered:
		return out
	for s in ships:
		if s.alive and s.team != me.team and s.lock.is_locked() and s.lock.target_id == player_id:
			out.locks += 1
	for p in projectiles.items:
		if p.kind == "missile" and p.homing and p.team != me.team and p.target_id == player_id:
			out.missiles += 1
	return out


func alive_on(team: String) -> Array:
	var out: Array = []
	for s in ships:
		if s.alive and s.team == team:
			out.append(s)
	return out


func waves_total() -> int:
	return encounter.get("waves", []).size()


func hostiles_remaining_to_spawn() -> bool:
	return wave_index < waves_total()


func state_label() -> String:
	return State.keys()[state]


## Lead marker for the player's HUD: where to put the nose to hit the current target.
func player_lead() -> Dictionary:
	var me = get_ship(player_id)
	var tg = get_ship(player_target_id)
	if me.is_empty() or tg.is_empty() or not tg.alive:
		return { "valid": false }
	var spd := float(me.loadout.group_config("primary").get("bolt_speed", 300.0))
	return LeadSolver.intercept(me.flight.position, me.flight.velocity(),
		tg.flight.position, tg.flight.velocity(), spd)


## Cycle the player's target to the next live hostile (a HUD "next target" key).
func cycle_player_target() -> void:
	var hostiles := alive_on(TEAM_HOSTILE)
	if hostiles.is_empty():
		player_target_id = -1
		return
	var idx := -1
	for i in hostiles.size():
		if hostiles[i].id == player_target_id:
			idx = i
	player_target_id = hostiles[(idx + 1) % hostiles.size()].id
	var me = get_ship(player_id)
	if not me.is_empty():
		me.target_id = player_target_id
		me.retarget_left = 3.0


# ---- frame ------------------------------------------------------------------

## Advance the whole encounter by dt. Returns this step's events.
func step(dt: float) -> Array:
	events = []
	if state != State.RUNNING:
		return events
	t += dt
	if arena_follow:
		var me = get_ship(player_id)
		if not me.is_empty() and me.alive:
			arena_center = me.flight.position
	_run_waves(dt)

	for s in ships:
		if not s.alive or (s.is_player and player_sheltered):
			continue
		_pick_target(s, dt)
		var tg = get_ship(s.target_id)
		var flight = s.flight
		var to_target := Vector3.ZERO
		if not tg.is_empty():
			to_target = tg.flight.position - flight.position
		s.lock.update(dt, s.target_id if not tg.is_empty() else -1, flight.forward(), to_target)

		var primary := false
		var secondary := false
		if s.brain != null:
			var b = s.brain
			b.has_target = not tg.is_empty()
			if b.has_target:
				b.target_pos = tg.flight.position
				b.target_vel = tg.flight.velocity()
			b.arena_center = arena_center
			b.arena_radius = arena_radius
			var pc: Dictionary = s.loadout.group_config("primary")
			b.bolt_speed = float(pc.get("bolt_speed", 300.0))
			b.weapon_range = float(pc.get("range", 900.0))
			b.has_missiles = s.loadout.has_group("secondary")
			b.missile_locked = s.lock.is_locked()
			b.update(dt)
			flight.set_command_dict(b.command)
			primary = b.fire_primary
			secondary = b.fire_secondary
		elif s.is_player:
			flight.set_command_dict(_player_cmd)
			primary = _player_primary
			# Seekers launch on the key, locked or not: unlocked they fly straight.
			secondary = _player_secondary

		flight.step(dt)
		s.defense.step(dt)

		var spawns: Array = s.loadout.fire(dt, flight.transform(), flight.velocity(), primary,
			secondary, s.lock.target_id if s.lock.is_locked() else -1)
		for sp in spawns:
			var uid: int = projectiles.add(sp, s.id, s.team)
			if sp.kind == "missile":
				stats.missiles += 1
				if not s.is_player:
					s.lock.reset()     # the player holds a lock through a salvo; pilots lock afresh each seeker
				events.append({ "type": "missile", "id": s.id, "uid": uid, "target": sp.target_id, "at": flight.position })
				var mark = get_ship(int(sp.target_id))
				if not mark.is_empty() and mark.brain != null:
					mark.brain.notify_missile()
			else:
				stats.shots += 1
				events.append({ "type": "shot", "id": s.id, "at": flight.position })

	_resolve_hits(projectiles.step(dt, _targets()))
	_check_outcome()
	return events


func _run_waves(dt: float) -> void:
	if wave_index >= waves_total():
		return
	if wave_index >= 0 or _wave_timer > 0.0:
		# Wait for the current wave to clear, then count down to the next.
		if not alive_on(TEAM_HOSTILE).is_empty():
			return
		_wave_timer -= dt
		if _wave_timer > 0.0:
			return
	_spawn_wave(wave_index)
	_arm_next_wave()


func _arm_next_wave() -> void:
	wave_index += 1
	var waves: Array = encounter.get("waves", [])
	_wave_timer = float(waves[wave_index].get("delay", 2.0)) if wave_index < waves.size() else 0.0


func _spawn_wave(idx: int) -> void:
	var waves: Array = encounter.get("waves", [])
	if idx < 0 or idx >= waves.size():
		return
	var w: Dictionary = waves[idx]
	var dist := float(w.get("spawn_distance", 800.0)) * scale("range_scale")
	var anchor := arena_center
	var me = get_ship(player_id)
	if not me.is_empty() and me.alive:
		anchor = me.flight.position
	var group: Array = []
	for entry in w.get("ships", []):
		for i in int(entry.get("count", 1)):
			group.append(str(entry.get("ship", "")))
	var n := group.size()
	for i in n:
		# Fan the wave out on an arc ahead of the anchor so it arrives as a formation.
		var ang := (float(i) - (n - 1) * 0.5) * 0.28
		var dir := Vector3(sin(ang), 0.08 * (i % 3 - 1), -cos(ang)).rotated(Vector3.UP, wave_yaw)
		var pos := anchor + dir * dist
		spawn_ship(group[i], TEAM_HOSTILE, pos, anchor - pos, str(w.get("pilot", "")), false)
	stats.waves += 1
	events.append({ "type": "wave", "index": idx + 1, "count": n })


func _pick_target(s: Dictionary, dt: float) -> void:
	s.retarget_left -= dt
	var cur = get_ship(s.target_id)
	var cur_ok: bool = not cur.is_empty() and cur.alive and not (cur.is_player and player_sheltered)
	if cur_ok and s.retarget_left > 0.0:
		return
	var enemy_team := TEAM_HOSTILE if s.team == TEAM_PLAYER else TEAM_PLAYER
	var best := -1
	var best_score := INF
	for o in alive_on(enemy_team):
		if o.is_player and player_sheltered:
			continue
		var to: Vector3 = o.flight.position - s.flight.position
		# Prefer close targets that are already in front of the nose.
		var ang := LeadSolver.angle_deg(s.flight.forward(), to)
		var score := to.length() * (1.0 + ang / 90.0)
		if score < best_score:
			best_score = score
			best = o.id
	s.target_id = best
	var prof: Dictionary = s.brain.profile if s.brain != null else {}
	s.retarget_left = float(prof.get("retarget_interval", 1.5))
	if s.is_player:
		player_target_id = best


func _targets() -> Array:
	var out: Array = []
	for s in ships:
		out.append({ "id": s.id, "team": s.team, "position": s.flight.position,
			"radius": s.radius, "alive": s.alive and not (s.is_player and player_sheltered) })
	return out


func _resolve_hits(hits: Array) -> void:
	for h in hits:
		var victim = get_ship(h.target_id)
		if victim.is_empty() or not victim.alive:
			continue
		stats.hits += 1
		if h.kind == "missile":
			stats.missile_hits += 1
		_damage(victim, h, h.kind, h.damage, h.point)
		# A seeker's burst hurts every other enemy ship within its splash.
		var r := float(h.get("splash_radius", 0.0))
		if r <= 0.0:
			continue
		for o in ships:
			if o == victim or not o.alive or o.team == h.team or o.id == h.owner \
					or (o.is_player and player_sheltered):
				continue
			if o.flight.position.distance_to(h.point) <= r + float(o.radius):
				_damage(o, h, "splash", float(h.splash_damage), o.flight.position)


## One ship takes `amount` from hit `h` (kind "bolt", "missile" or "splash"): a hit
## event, and a kill event if that finished it.
func _damage(victim: Dictionary, h: Dictionary, kind: String, amount: float, point: Vector3) -> void:
	var absorbed: Dictionary = victim.defense.apply_damage(amount)
	if victim.brain != null:
		victim.brain.notify_hit()
	events.append({ "type": "hit", "id": victim.id, "by": h.owner, "kind": kind,
		"damage": amount, "shield": absorbed.shield, "hull": absorbed.hull, "point": point,
		"blast_size": float(h.get("blast_size", 0.0)) if kind == "missile" else 0.0 })
	if not victim.defense.is_alive():
		victim.alive = false
		stats.kills += 1
		var killer = get_ship(h.owner)
		if not killer.is_empty():
			killer.kills += 1
			if killer.is_player:
				stats.player_kills += 1
		events.append({ "type": "kill", "id": victim.id, "ship_id": victim.ship_id,
			"by": h.owner, "team": victim.team, "point": victim.flight.position,
			"who": who(victim) })


## How a ship's pilot is called out: '"Cinder" Lieutenant Varo Kesh', or just the
## name or the callsign, or "" when nobody named them.
static func who(ship: Dictionary) -> String:
	var cs := str(ship.get("callsign", ""))
	var pn := str(ship.get("pilot_name", ""))
	if cs != "" and pn != "":
		return "\"%s\" %s" % [cs, pn]
	return cs if cs != "" else pn


func _check_outcome() -> void:
	var me = get_ship(player_id)
	if not me.is_empty() and not me.alive:
		state = State.FAILED
		events.append({ "type": "failed" })
		return
	if wave_index >= waves_total() and alive_on(TEAM_HOSTILE).is_empty():
		state = State.COMPLETE
		events.append({ "type": "complete", "payout": int(encounter.get("payout", 0)) })


static func _vec(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
