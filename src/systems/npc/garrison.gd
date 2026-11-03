class_name Garrison
extends Node
## The town's Remnant garrison (M15): the director that runs every trooper in
## town, like the dogfight director runs the fighter brains. Each frame it reads
## the bodies and the world into three pure pieces and writes the results back:
##
##   Checkpoint (gate guards)   what the gate does: wave, papers, search (pockets
##                              included), bribe, warn, go hostile
##   TownAlarm  (everyone)      whether the whole garrison is fighting, and the
##                              shared last sighting; calm again when you flee,
##                              are knocked out, or nobody is left
##   GuardBrain (one each)      how each trooper does its part: patrol, attend,
##                              cover and bursts, hold a tower, search, go home
##
## Who is in it: every NpcBody with a soldier profile. Their profile's "role" says
## what they do: "gate" (on the checkpoint), "sentry" (the tower: never leaves it),
## "yard" (barracks troopers: patrol, then run to the fight on the alarm).
##
## Issue #55: a speeder ridden into town, or a ship lifting off in it, is hostile:
## the first trooper to notice it sounds the alarm and the garrison shoots its hull.
##
## Issue #308: checkpoint zones. The barracks yard (the town's "garrison"
## "checkpoints") and the ring round each outpost (its location's "zone") each run
## a Checkpoint of their own, in zone mode, with the troopers there: walk in below
## the wave band and the nearest one walks up and the same card opens.
##
## The locals work their checkpoints the same way: their guards on the barracks
## posts (the front gate and the yard) and at each outpost they hold get a garrison
## of their own, the same checkpoints in the same places on your standing with the
## locals (`faction`, from the guards' profile; the rules from checkpoint_of).
## What is the Remnant's alone stays theirs: edgier for lost outposts, shooting on
## sight once the fleet is beaten, the bounty on a trooper. The barracks' alarm and
## the town's locals' go up together (alarm_up, join_alarm).
##
## It also owns: the choice card, subtitles and health bar (CheckpointHud), the
## alarm klaxon, confiscating what a search turns up, and what happens when the
## player is downed (knocked out, dragged to the pit, robbed a little).
##
## Nothing here is a number: the soldier profiles (content/core/soldiers/), the
## town's "garrison" block, the barks (content/core/dialogue/gate_guard_lines.json)
## and the sounds (content/look/npc_sounds.json).

const LINES_PATH := "res://content/core/dialogue/gate_guard_lines.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const BAND_TITLES := {
	"papers": "CHECKPOINT  -  papers",
	"search": "CHECKPOINT  -  papers and a search",
	"night_hostile": "CHECKPOINT  -  they know your face",
	"found": "SEARCH  -  they found something",
}

var demo
var town
var player: CharacterBody3D
var members: Array = []           ## every NpcBody in the garrison
var guards: Array = []            ## the ones on the gate checkpoint (role "gate")
var brains: Dictionary = {}       ## NpcBody -> GuardBrain
var checkpoint: Checkpoint
var alarm: TownAlarm
var hud: CheckpointHud
var profile: Dictionary = {}      ## the gate guards' profile (checkpoint rules)
var lines: Dictionary = {}
var gate_pos := Vector3.ZERO
var spots: Array = []             ## cover spots in town (CoverPicker)
var claimed: Dictionary = {}      ## NpcBody -> Vector3 its cover spot
var content: CoreContent
var klaxon: AudioStreamPlayer3D
var klaxon_left := 0.0

## Hooks a trace can replace (the greybox has no hand weapons).
var player_armed: Callable
## Issue #64: dead troopers come back. respawn_rule(NpcBody) -> { delay, at, ... }
## or {} (stays dead); spawner(that entry) -> the new NpcBody, or null for not now.
## The town scene sets both (town_demo.respawn_rule / respawn).
var respawn_rule: Callable
var spawner: Callable
var respawns: Array = []          ## [{ t, ...rule }] waiting, soonest first
var respawned := 0
## Issue #64: each desert outpost runs its own garrison (its own alarm), so a
## fight out there does not put the town on alert. Only one garrison handles the
## player being knocked out (and draws the health bar): handles_player.
var handles_player := true
var klaxon_at := Vector3.INF      ## INF = the town's klaxon marker
var faction := "imperial_remnant" ## whose standing the checkpoint reads and moves (the gate guards' faction)
var always_hostile := false       ## issue #193: the Remnant cruiser's crew shoot on sight, whatever your standing
## An outpost's garrison fights the player in a speeder or ship as on foot (set
## before setup). Out there the vehicle is no offence by itself: no "vehicle" alarm.
var vehicles_anywhere := false
var knockout_s := 1.6             ## black screen before you wake in the pit
## Issue #308: checkpoint zones, set before setup: [{ id, place, roles, and either
## center (Vector3) + radius or min + max ([x, z]), checkpoint: { what differs
## from the troopers' checkpoint block } }]. setup makes `zones` from them:
## [{ spec, checkpoint, guards }], guards = the members with one of its roles.
var zone_specs: Array = []
var zones: Array = []

## Numbers the traces read.
var barks_said: Array = []        ## [key, ...] in order
var bark_times: Array = []        ## game seconds, one per barks_said entry
var alarm_t := -1.0               ## game seconds when the alarm last went up
var cards_shown := 0
var knockouts := 0
var kills := 0
var rewards_paid := 0             ## issue #76: credits paid for troopers the player killed
var klaxon_plays := 0
var confiscated: Array = []       ## item ids taken by searches

var _rng := RandomNumberGenerator.new()
var _had_gate := false
var _attacked := false
var unfound: Array = []         ## issue #307: bodies of silent sword kills nobody has found yet
var silent_kills := 0           ## (traces)
var _lock_left := 0.0
var _ko_left := 0.0
var _ko_done := false
var _spots_checked := false
var _spot_i := 0
var _spots_ok: Array = []
const SPOTS_PER_FRAME := 150
var _last_key := ""
var _last_key_t := -100.0
var _clock := 0.0
var _warn_left: Dictionary = {}   ## NpcBody -> seconds until a sentry/yard "halt" becomes the alarm
var _card: Dictionary = {}        ## a card waiting for the lead guard to walk up: { title, choices }
var _card_wait := 0.0
var _face_g: NpcBody = null       ## the guard the player is turning to face
var _face_left := 0.0

## The alarm went up here (any cause). The locals' gate and the town's locals pass
## it to each other (join_alarm).
signal alarm_up(at: Vector3)


## `all` = every soldier NpcBody in town. Gate guards are those whose role is "gate".
func setup(town_demo, all: Array) -> void:
	demo = town_demo
	town = demo.town
	player = demo._player
	members = all
	_rng.seed = 7
	content = CoreContent.new()
	content.load_from()
	guards = members.filter(func(g): return str(g.profile.get("role", "gate")) == "gate")
	_had_gate = not guards.is_empty()
	profile = guards[0].profile if guards.size() > 0 else (members[0].profile if members.size() > 0 else {})
	# One set of gate rules for whoever holds it (the locals' guards: checkpoint_of).
	var of := str(profile.get("checkpoint_of", ""))
	if of != "" and not profile.has("checkpoint"):
		profile = CoreContent._merge({ "checkpoint": content.get_soldier(of).get("checkpoint", {}) }, profile)
	faction = str(profile.get("faction", faction))
	checkpoint = Checkpoint.new(profile.get("checkpoint", {}))
	var gcfg: Dictionary = town.data.get("garrison", {}) if town.data is Dictionary else {}
	alarm = TownAlarm.new(gcfg.get("alarm", {}))
	lines = CharacterKit._read_json(LINES_PATH).get("lines", {})
	gate_pos = town.marker_pos("gate")
	for spec in zone_specs:
		_add_zone(spec)
	for g in members:
		_adopt(g)
	# Cover anywhere in town: the yard troopers fight wherever the alarm takes them.
	var b0 := TownNav.town_bounds(town)
	spots = town_spots(town, b0)
	hud = CheckpointHud.new()
	add_child(hud)
	hud.chosen.connect(_on_chosen)
	_build_klaxon(gcfg)
	if handles_player and player != null and player.has_signal("downed"):
		player.downed.connect(_on_player_downed)
		player.hurt.connect(func(_a): _hp_hud(true))


## Issue #308: a zone's own checkpoint, on the troopers' rules with the zone's changes.
func _add_zone(spec: Dictionary) -> void:
	var cfg := CoreContent._merge(profile.get("checkpoint", {}), spec.get("checkpoint", {}))
	cfg["place"] = str(spec.get("place", spec.get("id", "the checkpoint")))
	zones.append({ "spec": spec, "checkpoint": Checkpoint.new(cfg, 23 + zones.size() * 13), "guards": [] })


## The zones trooper `g` stands in (by its role).
func _zones_for(g: NpcBody) -> Array:
	var role := str(g.profile.get("role", "gate"))
	return zones.filter(func(z): return (z.spec.get("roles", []) as Array).has(role))


## How far `p` is outside a zone's edge: 0 or less inside, INF for nowhere.
static func zone_out(spec: Dictionary, p: Vector3) -> float:
	if p == Vector3.INF:
		return INF
	if spec.has("radius"):
		return p.distance_to(spec.center) - float(spec.radius)
	var lo: Array = spec.get("min", [0, 0])
	var hi: Array = spec.get("max", [0, 0])
	var dx := maxf(maxf(float(lo[0]) - p.x, p.x - float(hi[0])), 0.0)
	var dz := maxf(maxf(float(lo[1]) - p.z, p.z - float(hi[1])), 0.0)
	return Vector2(dx, dz).length()


## The gate and every zone: [{ checkpoint, guards }, ...], the gate first.
func _posts() -> Array:
	return [{ "checkpoint": checkpoint, "guards": guards }] + zones


## A brain for one trooper: its patrol (its marker's route, else its post), its
## senses on vehicles, and its death and hits wired to the garrison.
func _adopt(g: NpcBody) -> void:
	var b := GuardBrain.new(g.profile, 101 + brains.size() * 37)
	var m: Dictionary = town.get_marker(g.post_id)
	var pts: Array = town.route_points_3d(str(m.get("patrol", ""))) if m.has("patrol") else []
	b.patrol_points = pts if pts.size() >= 2 else [g.post_pos]
	b.post_facing = g.post_facing
	brains[g] = b
	for z in _zones_for(g):
		if not z.guards.has(g):
			z.guards.append(g)
	g.sees_vehicles = true
	g.vehicles_anywhere = vehicles_anywhere
	g.watches_guests = true
	g.died.connect(_on_guard_died.bind(g))
	g.hit_by.connect(_on_guard_hit.bind(g))


## Issue #64: a trooper joins after setup (one come back from the dead, the
## bounty target at an outpost). Gate guards join the checkpoint.
func add_member(g: NpcBody) -> void:
	if g == null or brains.has(g):
		return
	if not members.has(g):
		members.append(g)          # (members may be the town's own npcs list, which has it already)
	if str(g.profile.get("role", "gate")) == "gate":
		guards.append(g)
	_adopt(g)


## And leaves (the garrison pulls out of town, a contract is called off).
func remove_member(g: NpcBody) -> void:
	members.erase(g)
	guards.erase(g)
	brains.erase(g)
	claimed.erase(g)
	_warn_left.erase(g)
	for z in zones:
		z.guards.erase(g)


## A trooper comes back as a new face: not while the alarm is up (they wait for
## it to end), and the garrison's memory of the player does not pass to them.
func _tick_respawns() -> void:
	if alarm != null and alarm.active():
		return
	while not respawns.is_empty() and _clock >= float(respawns[0].t):
		var r: Dictionary = respawns.pop_front()
		var g = spawner.call(r) if spawner.is_valid() else null
		if g != null:
			respawned += 1
			g.set_meta("fresh", true)
			add_member(g)


func _build_klaxon(gcfg: Dictionary) -> void:
	var c: Dictionary = NpcBody.sound_cfg().get("alarm", {})
	klaxon = AudioStreamPlayer3D.new()
	klaxon.name = "Klaxon"
	var path := str(c.get("stream", ""))
	if path != "" and ResourceLoader.exists(path):
		klaxon.stream = load(path)
	klaxon.volume_db = float(c.get("volume_db", -2.0))
	klaxon.unit_size = float(c.get("unit_size", 40.0))
	klaxon.max_distance = float(c.get("max_distance", 400.0))
	klaxon.bus = Sound.SFX_BUS
	add_child(klaxon)
	var mk := str(gcfg.get("klaxon_marker", ""))
	klaxon.position = (town.marker_pos(mk) if not town.get_marker(mk).is_empty() else gate_pos) + Vector3(0, 2.0, 0)
	if klaxon_at != Vector3.INF:
		klaxon.position = klaxon_at + Vector3(0, 4.0, 0)


func _physics_process(dt: float) -> void:
	if checkpoint == null or player == null:
		return
	_clock += dt
	_tick_respawns()
	_check_spots()
	_tick_locks(dt)
	_tick_klaxon(dt)
	var alive := _alive()
	var ppos := _player_pos()
	var gate_noticed := false
	var seen := false
	var nearest := INF
	var recent_shot := false
	var shot_window := float(profile.get("checkpoint", {}).get("recent_shot_s", 30.0))
	var seen_at := Vector3.INF        ## the player where seen, else a guest (LAN)
	for g in alive:
		var p: Perception = g.perception
		var gt = g.guest_target()
		var tpos: Vector3 = gt.global_position if gt != null else ppos
		seen = seen or p.visible
		if p.visible and (gt == null or seen_at == Vector3.INF):
			seen_at = tpos
		# The gate asks the player for papers; a guest it knows by standing (_watch_for_trouble).
		if guards.has(g) and gt == null:
			gate_noticed = gate_noticed or p.noticed
		if p.heard_kind == "shot" and p.since_heard < shot_window:
			recent_shot = true
		if tpos != Vector3.INF:
			nearest = minf(nearest, g.global_position.distance_to(tpos))
	var night := (profile.get("checkpoint", {}).get("night_times", ["dusk"]) as Array).has(WorldState.time_of_day)
	var vehicle := _hostile_vehicle()

	# The gate. Issue #187: edgier for every outpost the Remnant have lost.
	var gate_alive := alive.filter(func(g): return guards.has(g))
	checkpoint.strict = Territory.gate_strict() if remnant() else 0
	checkpoint.bribe_mult = Territory.bribe_mult() if remnant() else 1.0
	checkpoint.update(dt, {
		"standing": int(WorldState.standing.get(faction, 0)), "night": night,
		"credits": WorldState.credits, "player_pos": ppos, "gate_pos": gate_pos, "gate_x": gate_pos.x,
		# Nobody asks a speeder for its papers: that is the alarm's business.
		"noticed": gate_noticed and _ko_left <= 0.0 and vehicle == null,
		"armed": player_armed.call() if player_armed.is_valid() else false,
		# Hurting a trooper is the garrison's alarm (below), not a gate matter.
		"recent_shot": recent_shot, "attacked": false,
		"guards_alive": gate_alive.size(), "contraband": contraband(),
	})
	_handle(checkpoint.drain())
	_tick_zones(dt, alive, ppos, night, recent_shot, vehicle)

	# The rest of the garrison: a remembered face, or a wanted one by daylight.
	if not alarm.active() and ppos != Vector3.INF and _ko_left <= 0.0:
		_watch_for_trouble(dt, alive, night)
	if vehicle != null and not alarm.active():
		for g in alive:
			if g.perception.noticed:
				_say(g, "contact")
				_raise("vehicle")
				break
	if not alarm.active():
		_find_bodies(alive)
	if _attacked:
		_raise("attacked")
	_attacked = false

	alarm.update(dt, { "seen": seen and _ko_left <= 0.0, "player_pos": seen_at if seen_at != Vector3.INF else ppos,
		"nearest_dist": nearest, "alive": alive.size() })
	_handle(alarm.drain())
	if alarm.active():
		for post in _posts():
			post.checkpoint.set_alarm(true)

	_order_brains()
	for g in alive:
		_run_brain(g, dt, ppos)
	_tick_card(dt)
	_tick_face(dt)
	_hp_hud(false)


## Issue #308: each zone's checkpoint, on what its own troopers see. Nobody asks
## for papers from a speeder or ship, or once the Remnant shoot on sight anyway.
func _tick_zones(dt: float, alive: Array, ppos: Vector3, night: bool, recent_shot: bool, vehicle: Node) -> void:
	if zones.is_empty():
		return
	var asks: bool = _ko_left <= 0.0 and vehicle == null and player.get("piloting") != true \
		and not _shoot_on_sight()
	for z in zones:
		var mine := alive.filter(func(g): return z.guards.has(g))
		var noticed := false
		for g in mine:
			noticed = noticed or (g.perception.noticed and g.guest_target() == null)
		var cp: Checkpoint = z.checkpoint
		cp.strict = Territory.gate_strict() if remnant() else 0
		cp.bribe_mult = Territory.bribe_mult() if remnant() else 1.0
		cp.update(dt, {
			"standing": int(WorldState.standing.get(faction, 0)), "night": night,
			"credits": WorldState.credits, "player_pos": ppos, "zone_out": zone_out(z.spec, ppos),
			"noticed": noticed and asks,
			"armed": player_armed.call() if player_armed.is_valid() else false,
			"recent_shot": recent_shot, "attacked": false,
			"guards_alive": mine.size(), "contraband": contraband(),
		})
		_handle(cp.drain(), z)


## Sentries and barracks troopers do not run the checkpoint, but they know a face
## the garrison remembers, and they know who is wanted on sight (by day).
func _watch_for_trouble(dt: float, alive: Array, night: bool) -> void:
	var standing := int(WorldState.standing.get(faction, 0))
	# Issue #64: after the fleet is beaten, what is left of them shoots on sight.
	var wanted := (checkpoint.base_band(standing) == "hostile" and not night) or _shoot_on_sight()
	for g in alive:
		# LAN: a guest the gate guards too know only by standing, as a sentry does
		# (the gate's papers are the player's business).
		var gt = g.guest_target()
		var sentry := bool(g.profile.get("alarm", {}).get("raise_on_hostile_sight", false))
		var gate := guards.has(g)
		if not ((sentry and not gate) or (gate and gt != null)):
			continue
		if not g.perception.noticed:
			_warn_left.erase(g)
			continue
		var at: Vector3 = gt.global_position if gt != null else Vector3.INF
		if alarm.remembers() and not g.has_meta("fresh"):
			_say(g, "contact")
			_raise("remembered", at)
			return
		if wanted:
			if not _warn_left.has(g):
				_warn_left[g] = float(profile.get("checkpoint", {}).get("warn_s", 3.0))
				_say(g, "halt_hostile")
			_warn_left[g] -= dt
			if _warn_left[g] <= 0.0:
				_raise("spotted", at)
				return


## Sound the town alarm. The checkpoint's own "hostile" already took the standing
## hit for a gate fight; anything else costs it here. `at`: where (a guest), else the player.
func _raise(why: String, at := Vector3.INF) -> void:
	if not alarm.raise(why, at if at != Vector3.INF else _player_pos()):
		return
	_handle(alarm.drain())
	if why != "gate":
		var gcfg: Dictionary = town.data.get("garrison", {}).get("alarm", {})
		WorldState.set_flag("gate_fight")
		if WorldState.cooldown_ok("gate_fight", float(profile.get("checkpoint", {}).get("standing_cooldown_s", 120.0))):
			WorldState.change_standing(faction, int(gcfg.get("raise_standing", -10)),
				"The Remnant garrison sounded the alarm." if remnant() else "The locals' guards sounded the alarm.")


## Another director's alarm went up (the town's locals for the locals' gate, and
## back): this one fights too. It costs no standing here; that was paid there.
func join_alarm(at: Vector3) -> void:
	if alarm != null and alarm.raise("joined", at):
		_handle(alarm.drain())


## The Remnant's own garrisons (not the locals').
func remnant() -> bool:
	return faction == "imperial_remnant"


## Shoot on sight, whatever your standing: the Remnant once the fleet is beaten, the cruiser's crew.
func _shoot_on_sight() -> bool:
	return always_hostile or (remnant() and Story.remnant_hostile())


func _order_brains() -> void:
	var posts := _posts()
	var leads := posts.map(func(post): return _lead(post.guards))
	for g in brains:
		if g.dead:
			continue
		var b: GuardBrain = brains[g]
		b.walk_up = 0.0
		if alarm.active():
			b.engage()
			b.alarm_pos = alarm.last_known
			continue
		b.alarm_pos = Vector3.INF
		var asking := false
		for i in posts.size():
			var cp: Checkpoint = posts[i].checkpoint
			if not posts[i].guards.has(g):
				continue
			match cp.state:
				Checkpoint.State.CHALLENGE, Checkpoint.State.SEARCHING, Checkpoint.State.WARN, Checkpoint.State.FOUND:
					b.attend()
					asking = true
					# The nearest one comes over to ask (not to chase a man pushing through).
					if g == leads[i] and cp.state != Checkpoint.State.WARN:
						b.walk_up = cp.n("talk_dist", 2.2)
		if not asking and b.state == GuardBrain.State.ATTEND:
			b.patrol()


func _run_brain(g: NpcBody, dt: float, ppos: Vector3) -> void:
	var b: GuardBrain = brains[g]
	var vel := Vector3.ZERO
	var gt = g.guest_target()
	if gt != null:
		g.brief(b, gt.global_position, gt.velocity)      # LAN: the guest it is watching
	else:
		if ppos != Vector3.INF:
			var v := target_vehicle()
			vel = v.threat_velocity() if v != null else player.velocity
		g.brief(b, ppos, vel)
	b.update(dt)
	if b.want_cover:
		b.want_cover = false
		b.cover = _pick_cover(g, b)
	g.carry_out(b, dt)
	if b.bark != "":
		_say(g, b.bark)


## A cover spot for this trooper against the threat, not taken by another, within
## its profile's cover_search_radius, and on its own side of the town wall.
## Returning the spot it already holds (no better one) means "none": the brain
## then fights in the open and moves on the last known position.
func _pick_cover(g: NpcBody, b: GuardBrain) -> Vector3:
	_check_spots()
	var threat: Vector3 = b.target_pos if b.visible else b.last_seen
	if threat == Vector3.INF:
		threat = b.alarm_pos
	if threat == Vector3.INF:
		threat = _player_pos()
	if threat == Vector3.INF:
		return Vector3.INF
	var taken: Array = []
	for other in claimed:
		if other != g and not other.dead:
			taken.append(claimed[other])
	var c: Dictionary = g.profile.get("combat", {})
	var reach := float(c.get("cover_search_radius", 28.0))
	var side := signf(g.global_position.x - gate_pos.x)
	var mine: Array = []
	for sp in spots_near(g.global_position, reach):
		var sp_pos: Vector3 = sp.pos
		if signf(sp_pos.x - gate_pos.x) == side and Vector2(sp_pos.x - g.global_position.x, sp_pos.z - g.global_position.z).length() <= reach:
			mine.append(sp)
	var i := CoverPicker.pick(g.global_position, threat, mine, taken,
		float(c.get("cover_min_threat_dist", 6.0)), float(c.get("cover_max_threat_dist", 40.0)))
	if i < 0:
		claimed.erase(g)
		return Vector3.INF
	var p: Vector3 = mine[i].pos
	if claimed.has(g) and (claimed[g] as Vector3).distance_to(p) < 1.2 and g.global_position.distance_to(p) < 1.5:
		claimed.erase(g)
		return Vector3.INF
	claimed[g] = p
	return p


## Spots within `r` of `p`, from an 8 m grid (the town has ~2,900 spots; a full
## scan per cover request, five troopers asking every couple of seconds, made
## frame spikes).
const GRID := 8.0
var _grid: Dictionary = {}
var _grid_of: Array = []


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / GRID), floori(z / GRID))


func spots_near(p: Vector3, r: float) -> Array:
	if not is_same(_grid_of, spots):   # identity, not a 2,900-entry compare
		_grid.clear()
		for sp in spots:
			var c := _cell((sp.pos as Vector3).x, (sp.pos as Vector3).z)
			if not _grid.has(c):
				_grid[c] = []
			_grid[c].append(sp)
		_grid_of = spots
	var out: Array = []
	var lo := _cell(p.x - r, p.z - r)
	var hi := _cell(p.x + r, p.z + r)
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var c := Vector2i(cx, cz)
			if _grid.has(c):
				out.append_array(_grid[c])
	return out


## The town's cover spots, made once per town a session: the town's garrison and
## each outpost's all ask for the same ones (~56 ms each, four in one frame when the
## port is built again on the way home from the moon). Shared, so read only; a
## garrison that drops the unreachable ones keeps its own list (_check_spots).
static var _town_spots := {}


static func town_spots(t, bounds: AABB) -> Array:
	var data: Dictionary = t.data if t.data is Dictionary else {}
	var key := "%s/%d/%s" % [str(data.get("id", "")), t.boxes().size(), bounds]
	if not _town_spots.has(key):
		_town_spots[key] = CoverPicker.candidates(t.boxes(), bounds.get_center(), bounds.size.length())
	return _town_spots[key]


## Drop spots the navmesh cannot reach, a slice a frame once the mesh is in
## (thousands of nearest-point queries in one frame cost ~80 ms). Until it is
## done, picks use the spots not yet checked too.
func _check_spots() -> void:
	if _spots_checked or demo.nav == null or not demo.nav.is_ready:
		return
	var end := mini(_spot_i + SPOTS_PER_FRAME, spots.size())
	for k in range(_spot_i, end):
		var s: Dictionary = spots[k]
		var c: Vector3 = demo.nav.closest(s.pos)
		if c != Vector3.INF and Vector2(c.x - s.pos.x, c.z - s.pos.z).length() < 0.5:
			_spots_ok.append(s)
	_spot_i = end
	if _spot_i >= spots.size():
		spots = _spots_ok
		_spots_ok = []
		_spots_checked = true


# ------------------------------------------------------------------ contraband

## What the player carries that the Remnant would confiscate: [{ id, label, count, value }].
func contraband() -> Array:
	var out: Array = []
	var inv: Inventory = WorldState.inventory
	for id in inv.item_ids():
		var it: Dictionary = content.get_item(str(id))
		if bool(it.get("contraband", false)):
			out.append({ "id": str(id), "label": str(it.get("label", id)), "count": inv.count(str(id)), "value": int(it.get("value", 0)) })
	return out


# ------------------------------------------------------------------ events

## `post`: the zone the events came from ({} = the gate, or the alarm).
func _handle(events: Array, post: Dictionary = {}) -> void:
	var who: Array = post.get("guards", guards)
	var cp: Checkpoint = post.get("checkpoint", checkpoint)
	for e in events:
		match str(e.type):
			"bark":
				_say(_lead(who), str(e.key))
			"card":
				var title: String = BAND_TITLES.get(str(e.band), "CHECKPOINT")
				if str(e.band) == "found":
					title += ":  " + ", ".join((e.get("found", []) as Array).map(func(it): return "%s x%d" % [it.label, int(it.count)]))
				# Held until the guard asking has walked up (_tick_card).
				_card = { "title": title, "choices": e.choices, "guards": who, "checkpoint": cp }
				_card_wait = 0.0
			"card_close":
				_card = {}
				_face_left = 0.0
				hud.hide_card()
			"lock_player":
				player.locked = true
				_lock_left = float(e.seconds)
			"standing":
				var key := str(e.get("cooldown", ""))
				var cd := float(profile.get("checkpoint", {}).get("standing_cooldown_s", 120.0))
				if key == "" or WorldState.cooldown_ok(key, cd):
					WorldState.change_standing(faction, int(e.delta), str(e.get("why", "")))
			"bribe":
				WorldState.on_gate_bribe(int(e.price))
				hud.toast("-%d cr" % int(e.price), 2.0)
			"flag":
				WorldState.set_flag(str(e.name))
			"confiscate":
				var names: Array = []
				for id in e.items:
					var n := WorldState.inventory.count(str(id))
					WorldState.inventory.remove(str(id), n)
					confiscated.append(str(id))
					names.append(str(content.get_item(str(id)).get("label", id)))
				WorldState.log_event("%s confiscated %s." % [cp.place(), ", ".join(names).to_lower()])
				hud.toast("Confiscated: " + ", ".join(names), 3.0)
			"hostile":
				_raise("gate")
			"alarm":
				alarm_t = _clock
				for g in _alive():
					g.perception.awareness = 1.0
					g.perception.noticed = true
				alarm_up.emit(alarm.last_known)
				if str(e.get("why", "")) == "joined":
					continue          # someone else's fight: they shouted for it
				_say(_lead(_alive()), "alarm")
				klaxon_left = float(NpcBody.sound_cfg().get("alarm", {}).get("seconds", 8.0))
				klaxon_plays += 1
				if klaxon.stream != null and klaxon.is_inside_tree():
					klaxon.play()
				hud.toast("ALARM", 2.5)
			"calm":
				for p in _posts():
					p.checkpoint.set_alarm(false)
				_warn_left.clear()
				for g in _alive():
					var b: GuardBrain = brains[g]
					if str(e.why) == "downed":
						b.stand_down()
					else:
						b.calm()
				claimed.clear()


## Show the held card once the lead gate guard is close (or has had long enough to
## get there), and turn the player to face him.
func _tick_card(dt: float) -> void:
	if _card.is_empty():
		return
	_card_wait += dt
	var cfg: Dictionary = (_card.checkpoint as Checkpoint).cfg
	var g := _lead(_card.guards)
	var off := g.global_position - player.global_position if g != null else Vector3.ZERO
	var close := g == null or Vector2(off.x, off.z).length() <= float(cfg.get("talk_dist", 2.2)) + 0.5
	if not close and _card_wait < float(cfg.get("card_wait_s", 6.0)):
		return
	cards_shown += 1
	hud.show_card(str(_card.title), _card.choices)
	_card = {}
	if g != null:
		_face_g = g
		_face_left = float(cfg.get("face_turn_s", 0.4))


## Ease the view (and the body under it) round to the guard, eyes level with his.
func _tick_face(dt: float) -> void:
	if _face_left <= 0.0:
		return
	_face_left -= dt
	var rig = demo.get("_rig")
	if rig == null or not is_instance_valid(_face_g) or _face_g.dead:
		_face_left = 0.0
		return
	var tilt: Basis = player.get("tilt") if player.get("tilt") is Basis else Basis.IDENTITY
	var d: Vector3 = tilt.inverse() * (_face_g.global_position - player.global_position)
	if Vector2(d.x, d.z).length() < 0.3:
		_face_left = 0.0
		return
	var cam = rig.rig
	var want_yaw := atan2(d.x, d.z)
	var want_pitch := clampf(atan2(d.y, Vector2(d.x, d.z).length()), float(cam.min_pitch), float(cam.max_pitch))
	var f := 1.0 if _face_left <= 0.0 else 1.0 - exp(-14.0 * dt)
	cam.yaw = lerp_angle(cam.yaw, want_yaw, f)
	cam.pitch = lerpf(cam.pitch, want_pitch, f)
	if "player_kit" in demo and demo.player_kit != null and demo.player_kit.avatar != null:
		demo.player_kit.avatar.facing_yaw = cam.yaw


func _tick_klaxon(dt: float) -> void:
	if klaxon_left <= 0.0:
		return
	klaxon_left -= dt
	if klaxon_left <= 0.0 or not alarm.active():
		klaxon_left = 0.0
		klaxon.stop()
	elif klaxon.stream != null and not klaxon.playing and klaxon.is_inside_tree():
		klaxon.play()   # loop the wail while it lasts


func _on_chosen(id: String) -> void:
	choose(id)


## Game seconds since the first time `key` was said (or -1), for traces.
func first_said(key: String) -> float:
	var i := barks_said.find(key)
	return bark_times[i] if i >= 0 else -1.0


## Pick a card choice from code (traces, tests). Same path as the card.
func choose(id: String) -> bool:
	for post in _posts():
		if post.checkpoint.card_open:
			var ok: bool = post.checkpoint.answer(id)
			_handle(post.checkpoint.drain(), post)
			return ok
	return false


# ------------------------------------------------------------------ troopers

func _on_guard_hit(shooter: Node, _amount: float, g: NpcBody) -> void:
	if _is_player(shooter) or NpcBody.is_guest(shooter):
		if SilentKill.unaware_cut(g):
			_check_cut.call_deferred(g)        # issue #307: silent if the cut killed him unseen
			return
		_attacked = true
		brains[g].notify_hit()
	elif shooter != null:
		brains[g].notify_hit()


func _on_guard_died(g: NpcBody) -> void:
	kills += 1
	claimed.erase(g)
	var r: Dictionary = respawn_rule.call(g) if respawn_rule.is_valid() else {}
	if not r.is_empty():
		r["t"] = _clock + float(r.get("delay", 60.0))
		respawns.append(r)
		respawns.sort_custom(func(a, b): return float(a.t) < float(b.t))
	var left := _alive()
	var delta := int(g.profile.get("checkpoint", profile.get("checkpoint", {})).get("standing", {}).get("guard_killed", -15))
	# An outpost's garrison has no gate: its dead never take the checkpoint down.
	if remnant():
		WorldState.on_guard_killed(delta, handles_gate() and left.filter(func(x): return guards.has(x)).is_empty(), "gate" if handles_gate() else "")
	elif _is_player(g.last_hit_by):
		WorldState.change_standing(faction, delta, "One of the locals' guards was killed.")
	# Issue #76: a Remnant soldier you killed is worth its kill_reward (20 cr).
	var reward := int(g.profile.get("kill_reward", 0))
	if reward > 0 and _is_player(g.last_hit_by):
		WorldState.on_guard_reward(reward)
		rewards_paid += reward
		hud.toast("+%d cr" % reward, 2.0)
	if SilentKill.unaware_cut(g) and not SilentKill.witnessed(g, left):
		silent_kills += 1                  # issue #307: cut down unseen; the body waits to be found
		unfound.append(g)
		return
	if not left.is_empty():
		_say(_nearest(left, g.global_position), "man_down")
		_attacked = true      # a trooper dropping is a fight, whoever started it


## Issue #307: an unaware trooper was cut. Dead and unseen: nobody knows. Still
## standing, or someone saw: it is a fight.
func _check_cut(g: NpcBody) -> void:
	if is_instance_valid(g) and g.dead and not SilentKill.witnessed(g, _alive()):
		return
	_attacked = true
	if is_instance_valid(g) and brains.has(g):
		brains[g].notify_hit()


## Issue #307: a trooper who walks within sight of a silent kill finds the body.
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


# ------------------------------------------------------------------ the player

func _on_player_downed() -> void:
	if _ko_left > 0.0:
		return
	knockouts += 1
	# The town's garrison sleeps with the town's people while you are high up (the
	# altitude detail tier): downed up there (aboard the cruiser) it must still
	# count you out and wake you in the pit. The pit brings the tier back down,
	# and that sets this back with the rest of the people.
	if not can_process():
		process_mode = Node.PROCESS_MODE_INHERIT
	var lead := _lead(_alive())
	if lead != null:
		_say(lead, "downed")
	player.locked = true
	_ko_left = knockout_s
	_ko_done = false
	hud.hide_card()


func _tick_locks(dt: float) -> void:
	if _lock_left > 0.0:
		_lock_left -= dt
		if _lock_left <= 0.0 and _ko_left <= 0.0:
			player.locked = false
	if _ko_left > 0.0:
		_ko_left -= dt
		hud.fade.color.a = clampf(1.0 - _ko_left / knockout_s * 0.5, 0.0, 1.0)
		if _ko_left <= 0.0 and not _ko_done:
			_ko_done = true
			_wake_in_pit()
	elif hud.fade.color.a > 0.0:
		hud.fade.color.a = maxf(0.0, hud.fade.color.a - dt * 1.5)


func _wake_in_pit() -> void:
	var taken := WorldState.on_player_downed()
	# Downed, by whoever: the Remnant let it go, just. Their standing comes up to
	# the lowest they do not shoot on sight (never down: it only ever helps), and
	# every garrison forgets the fight and your face (forgive_player), so you do
	# not wake to troopers waiting at the pit.
	player.set("last_shooter", null)
	var now := int(WorldState.standing.get("imperial_remnant", 0))
	var floor_ok := checkpoint.lowest_tolerated()
	if now < floor_ok:
		WorldState.change_standing("imperial_remnant", floor_ok - now, "The Remnant dragged you to the pit and let it go.")
	player.global_position = town.spawn_pos() + Vector3(0, 0.05, 0)
	if player.has_method("align_to_ground"):
		player.call("align_to_ground", true)
	else:
		player.velocity = Vector3.ZERO
		player.controller.velocity = Vector3.ZERO
	player.revive()
	player.locked = false
	if demo != null and demo.has_method("day_trigger"):
		demo.day_trigger("respawn")      # issue #381: you wake to a new part of the day
	forgive_player()
	var outs = demo.get("outposts")
	if outs != null:
		for og in outs.garrisons.values():
			if og != self and is_instance_valid(og):
				og.forgive_player()
	# The locals let it go too, the town's and every outpost's.
	var folk = demo.get("townsfolk")
	if folk != null and is_instance_valid(folk):
		folk.forgive_player()
	var lg = demo.get("locals_garrison")
	if lg != null and lg != self and is_instance_valid(lg):
		lg.forgive_player()
	if outs != null:
		for tf in outs.folks.values():
			if is_instance_valid(tf):
				tf.forgive_player()
	var dr = demo.get("droids")
	if dr != null and is_instance_valid(dr):
		dr.forgive_player()
	hud.toast("You wake up in the pit. They took %d cr." % taken, 4.0)
	var pl = demo.get("pilot")
	if pl != null and is_instance_valid(pl):
		pl.woke_in_pit()                 # issue #368: your primary ship is on the pad


## The player died and woke in the pit: this garrison lets it go. The alarm and
## its klaxon stop, the fight and the player's face are forgotten, the gate starts
## over and every trooper goes back to its round with fresh eyes.
func forgive_player() -> void:
	alarm.stand_down()
	checkpoint.on_player_downed()
	_handle(checkpoint.drain())
	for z in zones:
		z.checkpoint.on_player_downed()
		_handle(z.checkpoint.drain(), z)
	_handle(alarm.drain())
	_attacked = false
	_warn_left.clear()
	_card = {}
	klaxon_left = 0.0
	if klaxon != null:
		klaxon.stop()
	claimed.clear()
	for g in _alive():
		g.perception = Perception.new(g.profile.get("perception", {}))
		var b: GuardBrain = brains.get(g)
		if b != null and b.state != GuardBrain.State.PATROL and b.state != GuardBrain.State.RETURN:
			b.stand_down()


## Where the garrison's target is: the player on foot, or the speeder / ship they
## are in while it is a target (target_vehicle; it carries the player's position).
## INF for nobody to fight.
func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player) or _ko_left > 0.0:
		return Vector3.INF
	if player.get("piloting") == true and target_vehicle() == null:
		return Vector3.INF
	return player.global_position


## Issue #55: the speeder or ship the player is in, while it is hostile in town.
func _hostile_vehicle() -> Node:
	if player == null or not is_instance_valid(player) or player.get("piloting") != true:
		return null
	var v = player.get("vehicle")
	if v == null or not is_instance_valid(v) or not v.hostile_in_town():
		return null
	return v


## The speeder or ship the troopers see and shoot at: the one hostile in town, or
## (an outpost's garrison) whatever the player is in. null when on foot or none.
func target_vehicle() -> Node:
	var v := _hostile_vehicle()
	if v != null or not vehicles_anywhere or player == null or not is_instance_valid(player) \
			or player.get("piloting") != true:
		return v
	v = player.get("vehicle")
	return v if v != null and is_instance_valid(v) and v.targetable() else null


## The player, or a bolt from the speeder or ship they are in.
func _is_player(shooter: Node) -> bool:
	if shooter == null:
		return false
	if shooter == player:
		return true
	var v = player.get("vehicle") if player != null and is_instance_valid(player) else null
	return v != null and is_instance_valid(v) and shooter == v.hull_body()


## This garrison holds the town's front gate (it had gate guards to begin with).
func handles_gate() -> bool:
	return _had_gate


func _hp_hud(hurt: bool) -> void:
	if not handles_player or player == null or player.get("health") == null:
		return
	hud.set_hp(float(player.health.hp) / maxf(1.0, float(player.max_health)), hurt)


# ------------------------------------------------------------------ helpers

func _alive() -> Array:
	var out: Array = []
	for g in members:
		if is_instance_valid(g) and not g.dead:
			out.append(g)
	return out


## Who speaks: the living one in `among` nearest the player.
func _lead(among: Array) -> NpcBody:
	var live := among.filter(func(g): return is_instance_valid(g) and not g.dead)
	if live.is_empty() or player == null:
		return null
	return _nearest(live, player.global_position)


func _nearest(among: Array, at: Vector3) -> NpcBody:
	var best: NpcBody = null
	var bd := INF
	for g in among:
		var d: float = g.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = g
	return best


func _say(g: NpcBody, key: String) -> void:
	var list: Array = lines.get(key, [])
	if g == null or list.is_empty():
		return
	# Two troopers shouting the same thing in the same breath is a choir, not a garrison.
	if key == _last_key and _clock - _last_key_t < 1.5:
		return
	_last_key = key
	_last_key_t = _clock
	var text := str(list[_rng.randi() % list.size()])
	barks_said.append(key)
	bark_times.append(_clock)
	var shout_keys: Array = NpcBody.sound_cfg().get("shout_keys", [])
	g.say(text, 2.6, shout_keys.has(key))
	if player != null and g.global_position.distance_to(player.global_position) < 35.0:
		var who: String = g.display_name if g.display_name != "" else str(g.profile.get("label", "Trooper"))
		hud.say(who, text)
