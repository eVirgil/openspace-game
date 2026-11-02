class_name GeneralPost
extends Node3D
## The Remnant general in a story save (issues #203, #204, #205, #213, #214).
##   - Where he stands: in the pit beside your wreck while the story is at the
##     "general" chapter (he meets you as you step out), then in the barracks yard
##     with one guard and an assassin droid. Gone while he is a bounty out at an
##     outpost, and for good once he is dead.
##   - An AI character on the town's ConversationHost, from his own card
##     (content/core/npcs/general_card.json). [E] beside him opens a menu, like
##     T-89's: talk, ask for work, hand over a droid.
##   - He, his guard and his droid face the front gate ("face": a town marker), in
##     a row abreast: their offsets are in the squad's own frame. In the pit the
##     row stands off your ship's tail, so you climb out boxed in against it.
##   - In the barracks yard (while the Remnant hold the moon) they are real: he and
##     his guard are garrison troopers (NpcBody, "squad" soldier profiles) and the
##     droid one of the Remnant's droids, so they can be shot, and they fight where
##     they stand when the town alarm goes up. Killed there he is gone for good
##     (WorldState.on_general_killed): Oda's bounty goes on someone else.
##   - The pit meeting opens the moment you climb out of your ship, and is his to
##     end: you cannot walk away (Esc) until he lets you go (let_go) or has you
##     searched (search). That verdict sets the Remnant standing you start with. If
##     his brain never gives one (or no model answers), the game has you searched
##     after four of his lines (the meeting's "default"). Either way he closes with
##     a hint at work for an outlander (the Work for the general quest), then he and
##     his escort walk out of the pit to the barracks ("leave"): no cut, so you
##     stand where you stood at the same time of day.
##   - Insults cost Remnant standing; too many in one talk and his guards search you
##     on the spot (the gate's rules: WorldState.search_player). In the pit meeting
##     that search is his verdict.
##   - His job (j_general_droids, issue #204): assassin droids from the desert, for
##     pay_mult times the droid merchant's resale, each raising Remnant standing.
##     Not while you are hostile. In good standing he tells you about the crashed
##     cruiser (issue #205: the quest's event, heard_of_wreck).
##   - His second job (j_general_repossess, issue #251): contraband smugglers
##     stashed inside the town, offered in talk. [E] hands him what you found,
##     for more than the fence would have paid, and raises Remnant standing.
##   - Once the Remnant has left the moon (issue #214) he stays, in the desert armour.
##
## Config: content/core/npcs/general.json. The headless test calls talk_ended(),
## on_insult(), decide(), take_job(), hand_over() and hand_over_contraband() directly.

const CFG_PATH := "res://content/core/npcs/general.json"
const CARD_PATH := "res://content/core/npcs/general_card.json"

var demo                              ## town_demo.gd (or null in a test)
var player: CharacterBody3D
var gear: GearController
var cfg: Dictionary = {}
var body: Node3D                      ## MerchantNPC, or NpcBody in the barracks yard
var guard: Node3D
var droid: Node3D                     ## DroidKit look, or DroidUnit in the barracks yard
var menu: DroidMenu
var host: ConversationHost
var spot: TalkSpot
var said := ""                        ## his last line (tests)
var searched := 0                     ## searches this session (tests)
var meeting := false                  ## the pit meeting is on and he has not given his verdict
var verdict := ""                     ## "let_go" | "search" once he has given it (tests)
var _where := ""                      ## "pit" | "barracks" | "" (away)
var _armoured := false
var _insults_seen := 0
var _talk_insults := 0
var _was_talking := false
var _was_locked := false
var _meet_lines := 0
var _free_at := 0                     ## ticks (ms): until then the pit is still his (T-89 waits)
var _leaving: Array = []              ## walking out of the pit: [{ node, path, i, wait }]
var _leave_t := 0.0


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "GeneralPost"
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	cfg = d if d is Dictionary else {}
	menu = DroidMenu.new()
	add_child(menu)
	_place()


func npc_name() -> String:
	return str(NpcBrain._read(CARD_PATH).get("name", "the general"))


func _l(key: String) -> String:
	return str(cfg.get("labels", {}).get(key, key))


func _line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, key))


# ------------------------------------------------------------------ where he is

## "pit" while he waits for you there, "barracks" after, "" while he is away (a
## bounty out at an outpost) or dead.
static func station() -> String:
	if not WorldState.story_mode() or WorldState.has_flag("general_dead") or general_hunted():
		return ""
	return "pit" if Story.chapter() in ["land", "general"] else "barracks"


## Issue #213: Oda's bounty is on him and he is out at the outpost (or dead there).
static func general_hunted() -> bool:
	return bool(WorldState.bounty.get("general", false)) and str(WorldState.bounty.get("state", "")) in ["out", "dead"]


func _place() -> void:
	if leaving():
		return                        # walking out of the pit: the barracks once they are there
	var want := station()
	var armour := Story.remnant_gone()
	if want == _where and armour == _armoured and (body != null or want == ""):
		return
	_where = want
	_armoured = armour
	for n in [body, guard, droid]:
		_drop(n)
	body = null
	guard = null
	droid = null
	if want == "":
		_sync_spot()
		return
	var at := _spot(cfg.get(want, {}))
	if want == "barracks" and not armour and _can_fight():
		_place_squad(at)
		_sync_spot()
		return
	var kit: CharacterKit = CharacterKit.new(demo._flat_mats(), 0.0) if demo != null and demo.get("use_look") else null
	body = _person(kit, cfg.get("armour_outfit" if armour else "outfit", {}), at, "General")
	if not armour:
		# The Remnant has left (issue #214): he stays on alone.
		guard = _person(kit, cfg.get("guard_outfit", {}), at + _row(at, "guard_offset"), "GeneralGuard")
		if demo != null and demo.get("use_look"):
			var look := DroidKit.build("assassin", {}, demo._flat_mats(), ShipSalesman.model_look({ "kind": "assassin" }))
			add_child(look)
			look.global_position = at + _row(at, "droid_offset")
			DroidKit.set_awake(look, true)
			droid = look
	_face_gate()
	_sync_spot()


## He and his escort face the front gate. People face +Z, the droid's look -Z.
func _face_gate() -> void:
	for n in [body, guard, droid]:
		if n == null:
			continue
		var to := _to_gate(n.global_position)
		if to != Vector3.ZERO:
			n.rotation.y = atan2(to.x, to.z) if n != droid else atan2(-to.x, -to.z)


## From `from` to the marker they face (flat), or zero when the town has none.
func _to_gate(from: Vector3) -> Vector3:
	var town = demo.town if demo != null and "town" in demo else null
	var mk := str(cfg.get("face", "gate"))
	if town == null or town.get_marker(mk).is_empty():
		return Vector3.ZERO
	var to: Vector3 = town.marker_pos(mk) - from
	to.y = 0.0
	return to if to.length() > 0.01 else Vector3.ZERO


func _yaw_to_gate(from: Vector3) -> float:
	var to := _to_gate(from)
	return atan2(to.x, to.z) if to != Vector3.ZERO else 0.0


## Where one of his escort stands from him: its offset (x across the row, z
## toward the gate) turned to the way the squad faces, so the row is abreast.
func _row(at: Vector3, key: String) -> Vector3:
	return Basis(Vector3.UP, _yaw_to_gate(at)) * _v(cfg.get(key, [0, 0, 0]))


## The barracks squad can be real soldiers: the town has a garrison to put them in.
func _can_fight() -> bool:
	return demo != null and demo.has_method("make_soldier") and demo.get("garrison") != null


## The barracks yard: he and his guard as garrison troopers, his droid as one of
## the Remnant's droids. None of them come back from the dead.
func _place_squad(at: Vector3) -> void:
	var sq: Dictionary = cfg.get("squad", {})
	body = _soldier(str(sq.get("general", "barracks_general")), at, "npc:general")
	if body == null:
		return
	body.display_name = npc_name()
	body.died.connect(_on_general_died)
	guard = _soldier(str(sq.get("guard", "general_guard")), at + _row(at, "guard_offset"), "npc:general/guard")
	var droids = demo.get("droids")
	if droids != null and sq.has("droid"):
		var here := at + _row(at, "droid_offset")
		var spec: Dictionary = (sq.droid as Dictionary).duplicate()
		spec["patrol"] = [here]
		spec["respawn"] = false
		spec["general_squad"] = true
		droid = droids.spawn_site_unit(spec)
		if droid != null and _to_gate(here) != Vector3.ZERO:
			droids._face(droid, _to_gate(here))


func _soldier(id: String, at: Vector3, key: String) -> NpcBody:
	var s: NpcBody = demo.make_soldier(id, at, _yaw_to_gate(at), key.trim_prefix("npc:"), key)
	if s == null:
		return null
	s.set_meta("general_squad", true)
	demo.garrison.add_member(s)
	return s


## Take one of his party away (he moved, or is away). A dead soldier or droid
## stays where it fell, and once he is dead the living ones stay on as troopers.
func _drop(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is NpcBody:
		if n.dead or WorldState.has_flag("general_dead"):
			return
		var g = demo.garrison_for(n) if demo != null else null
		if g != null:
			g.remove_member(n)
		demo.npcs.erase(n)
	elif n is DroidController.DroidUnit:
		if n.dead or WorldState.has_flag("general_dead"):
			return
		demo.droids.remove_site_unit(n)
		return
	n.queue_free()


## Shot dead in the barracks yard: gone for good, and the talk is over.
func _on_general_died() -> void:
	if _in_talk():
		host.end_talk()
	if menu.is_open():
		menu.choose("")
	if _was_locked and player != null:
		player.locked = false
		_was_locked = false
	WorldState.on_general_killed()
	_say(_line("killed") % npc_name())


## Dead, fighting or walking out of the pit: nobody talks to him then.
func _can_talk() -> bool:
	if body == null or not is_instance_valid(body) or leaving():
		return false
	if body is NpcBody:
		var g = demo.garrison_for(body) if demo != null else null
		return not body.dead and not (g != null and g.alarm != null and g.alarm.active())
	return true


## His TalkSpot follows his body: on the host while he stands somewhere, off it
## while he is away.
func _sync_spot() -> void:
	if spot == null or host == null:
		return
	spot.body = body
	if body == null or (body is NpcBody and body.dead) or leaving():
		host.spots.erase(spot)
		return
	spot.stand = body.global_position
	if not host.spots.has(spot):
		host.spots.append(spot)


func _person(kit: CharacterKit, outfit: Dictionary, at: Vector3, n: String) -> Node3D:
	var p := MerchantNPC.new(kit, "remnant_commander", outfit) if kit != null else MerchantNPC.new()
	p.name = n
	add_child(p)
	p.global_position = at
	if player != null:
		p.look_at_target = player
	return p


func _spot(where: Dictionary) -> Vector3:
	var town = demo.town if demo != null and "town" in demo else null
	var mk := str(where.get("marker", ""))
	var base := Vector3.ZERO
	if town != null and not town.get_marker(mk).is_empty():
		base = town.marker_pos(mk)
	return base + _v(where.get("offset", [0, 0, 0]))


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_walk_out(dt)
	_place()
	if host != null:
		_watch_talk()
	if player == null or not _can_talk():
		return
	if menu.is_open() or (host != null and host.is_talking()):
		return
	_meet_in_pit()
	if _was_locked:
		player.locked = false
		_was_locked = false
	var p := player.global_position
	var bp := body.global_position
	var near: bool = not bool(player.get("piloting")) and Vector2(p.x - bp.x, p.z - bp.z).length() <= float(cfg.get("reach", 3.2)) \
		and absf(p.y - bp.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not near:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(_l("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		open_menu()


## [E]: talk (his AI), ask for work, hand over droids or his run's contraband.
## keep_cursor: open again after a hand-over, the cursor where it was.
func open_menu(keep_cursor := false) -> void:
	var opts: Array = []
	if spot != null:
		opts.append({ "id": "chat", "text": _l("chat") })
	if not job_active():
		opts.append({ "id": "work", "text": _l("work") })
	for d in droids_to_hand_over():
		opts.append({ "id": "hand:%d" % int(d.uid), "text": _l("hand_over") % [DroidRoster.label(str(d.kind)), droid_pay()] })
	if WorldState.repossession_pay() > 0:
		opts.append({ "id": "contraband", "text": _l("hand_contraband") % WorldState.repossession_pay() })
	menu.open(_l("menu_title") % [npc_name(), int(WorldState.standing.get("imperial_remnant", 0))], opts, _on_menu, "", keep_cursor)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _on_menu(id: String) -> void:
	if id == "chat":
		_was_locked = false
		if host != null:
			host.start_talk(spot)
	elif id == "work":
		take_job()
	elif id.begins_with("hand:") or id == "contraband":
		if id == "contraband":
			hand_over_contraband()
		else:
			hand_over(int(id.substr(5)))
		if _can_talk():
			open_menu(true)     # a sale leaves the menu open (Esc walks away)


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 5.0)


# ------------------------------------------------------------------ talk (issue #203)

## Join the town's conversation host as one of its AI characters.
func attach_host(h: ConversationHost) -> void:
	if h == null or host == h:
		return
	host = h
	var brain := NpcBrain.new(null, CARD_PATH)
	spot = TalkSpot.new(brain, body, body.global_position if body != null else Vector3.ZERO)
	spot.manual = true
	spot.radius = float(cfg.get("reach", 3.2))
	spot.face_height = 1.65
	brain.extra_brief = func(): return [_line("brief")] if meeting else []
	brain.verdict.connect(_on_verdict)
	host.add_spot(spot)
	brain.line_done.connect(_on_line)        # after the host's: his line is on screen first
	_sync_spot()


## Issue #203: you step out of your ship and he is on you: the talk opens by
## itself the moment you are out, wherever you stand.
func _meet_in_pit() -> void:
	if _where != "pit" or Story.chapter() != "general" or host == null or spot == null or bool(player.get("piloting")):
		return
	_begin_meeting()
	host.start_talk(spot)


## The pit meeting: Esc can't leave, and his brain is told to end it with a verdict.
func _begin_meeting() -> void:
	meeting = true
	_meet_lines = 0
	if spot != null:
		spot.hold_line = _line("hold") % npc_name()
		spot.near_voice = true          # the talk opens a few steps off: heard as if beside him
		spot.brain.builder.extra_actions = ["let_go", "search"]


func _meet_cfg() -> Dictionary:
	return cfg.get("meeting", {})


## True while the pit is still his: the meeting, and a moment after it (T-89 waits).
func holding() -> bool:
	return meeting or _in_talk() or Time.get_ticks_msec() < _free_at


func _on_verdict(kind: String) -> void:
	if meeting:
		decide(kind)


## His brain's line in the meeting. A verdict came with it (decide() ran already),
## or he said end_conversation (that is letting them go), or after enough lines
## with neither the game gives his verdict for him (a search).
func _on_line(turn: Dictionary) -> void:
	if not meeting:
		return
	var applied: Array = turn.get("applied", [])
	if applied.has("end_conversation"):
		decide("let_go", false)
		return
	_meet_lines += 1
	# Issue #328: with AI characters off his lines are written ones: fewer of them.
	var offline := host != null and host.llm != null and not host.llm.ai_on()
	var turns := int(_meet_cfg().get("turns_offline" if offline else "turns", _meet_cfg().get("turns", 3)))
	if _meet_lines >= turns:
		decide_default()


## The game's verdict when his brain gave none: newcomers get searched (the
## meeting's "default"). A routine search costs the standing of "default"; if
## they mouthed off, it is the insolent one's.
func decide_default(close: bool = true) -> bool:
	var insolent := _talk_insults > 0 or (spot != null and spot.brain.insults > 0)
	return decide(str(_meet_cfg().get("default", "search")), close, "search" if insolent else "default")


## His verdict in the pit meeting: let them go, or have them searched. Sets the
## Remnant standing they start with (the meeting's standing for `why`, else for
## `kind`), and the talk closes a moment later (with `close` false, it is closing
## by itself). Returns false once he has given one.
func decide(kind: String, close: bool = true, why: String = "") -> bool:
	if verdict != "" or not kind in ["let_go", "search"]:
		return false
	meeting = false
	verdict = kind
	if spot != null:
		spot.hold_line = ""
		spot.near_voice = false
		spot.brain.builder.extra_actions = []
	var st: Dictionary = _meet_cfg().get("standing", {})
	WorldState.change_standing("imperial_remnant", int(st.get(why if why != "" else kind, 0)),
		"The Remnant general let a newcomer go." if kind == "let_go" else "The Remnant general had a newcomer searched.")
	WorldState.set_flag("general_" + kind)
	if kind == "search":
		searched += 1
		var took := WorldState.search_player()
		_say(_line("meeting_search") % (_line("meeting_took") % ", ".join(PackedStringArray(took)) if not took.is_empty() else _line("meeting_clean")))
		if _in_talk():
			host.panel.post_notice(said)
	hint_droid_job()
	if close and _in_talk():
		var t := get_tree().create_timer(float(_meet_cfg().get("end_delay", 3.0))) if is_inside_tree() else null
		if t != null:
			t.timeout.connect(_close_talk)
		else:
			host.end_talk()
	return true


## The end of the pit meeting: outlanders take any work, and he has something in
## mind (the droid job). Opens the Work for the general quest.
func hint_droid_job() -> void:
	Story.event("heard_of_droid_job")
	_say(_line("droid_hint"))
	if _in_talk():
		host.panel.post_notice(said)


func _in_talk() -> bool:
	return host != null and host.is_talking() and host.active == spot


func _close_talk() -> void:
	if _in_talk():
		host.end_talk()


## Each line he hears: an insult costs standing; when the talk ends, the story
## moves on (the pit meeting is over).
func _watch_talk() -> void:
	var talking: bool = host.is_talking() and host.active == spot
	if talking:
		var n: int = spot.brain.insults
		while _insults_seen < n:
			_insults_seen += 1
			on_insult()
	elif _was_talking:
		talk_ended()
	_was_talking = talking


## The player mouthed off: Remnant standing drops, and once too often in one talk
## his guards search them on the spot. Returns true when they were searched.
func on_insult() -> bool:
	WorldState.change_standing("imperial_remnant", int(cfg.get("insult_standing", -5)), "Someone mouthed off at the Remnant general.")
	_talk_insults += 1
	if _talk_insults < int(cfg.get("search_after", 2)):
		return false
	_talk_insults = 0
	if meeting:
		return decide("search")
	searched += 1
	var took := WorldState.search_player()
	_say(_line("searched") % ", ".join(PackedStringArray(took)) if not took.is_empty() else _line("searched_clean"))
	return true


## The talk is over: the pit meeting ends the chapter (T-89 next, and the pointer
## goes to him), and his tip comes if he likes you enough.
func talk_ended() -> void:
	if Story.chapter() == "general":
		decide_default(false)                   # the talk closed without his verdict: the game gives it
		Story.event("general_done")
		_free_at = Time.get_ticks_msec() + int(1000.0 * float(_meet_cfg().get("after", 2.5)))
		leave_pit()
	meeting = false
	_talk_insults = 0
	maybe_tip()


# ------------------------------------------------------------------ leaving the pit

func leaving() -> bool:
	return not _leaving.is_empty()


## The meeting is over: he, his guard and his droid walk out of the pit to the
## barracks on the town's navmesh, in single file. With no path (no navmesh yet,
## or a headless test without one) they are simply at the barracks next frame.
## Returns true when they set off.
func leave_pit() -> bool:
	if _where != "pit" or body == null or not is_instance_valid(body) or station() != "barracks":
		return false
	var nav = demo.get("nav") if demo != null else null
	if nav == null:
		return false
	var path: PackedVector3Array = nav.path(body.global_position, _spot(cfg.get("barracks", {})))
	if path.size() < 2:
		return false
	var lv: Dictionary = cfg.get("meeting", {}).get("leave", {})
	var gap := float(lv.get("gap_s", 0.8))
	var i := 0
	for n in [body, guard, droid]:
		if n == null or not is_instance_valid(n):
			continue
		# Each falls in behind him: from where they stand to his first corner, then his path.
		var mine := PackedVector3Array([n.global_position])
		mine.append_array(path.slice(1))
		_leaving.append({ "node": n, "path": mine, "i": 1, "wait": gap * i })
		i += 1
	_leave_t = 0.0
	return true


## One step of the walk out. When the last of them is in (or it took too long)
## they go, and _place() stands the barracks squad where they arrived.
func _walk_out(dt: float) -> void:
	if _leaving.is_empty():
		return
	var lv: Dictionary = cfg.get("meeting", {}).get("leave", {})
	var speed := float(lv.get("speed", 1.6))
	_leave_t += dt
	var done := true
	for w in _leaving:
		var n: Node3D = w.node
		if not is_instance_valid(n):
			continue
		w.wait = float(w.wait) - dt
		var path: PackedVector3Array = w.path
		if float(w.wait) > 0.0 or int(w.i) >= path.size():
			_gait(n, 0.0)
			done = done and int(w.i) >= path.size()
			continue
		done = false
		var to := path[int(w.i)] - n.global_position
		var step := speed * dt
		if to.length() <= step:
			n.global_position = path[int(w.i)]
			w.i = int(w.i) + 1
		else:
			n.global_position += to.normalized() * step
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 0.01:
			n.rotation.y = atan2(flat.x, flat.z) if n != droid else atan2(-flat.x, -flat.z)
		_gait(n, speed)
	if done or _leave_t >= float(lv.get("max_s", 90.0)):
		_leaving.clear()
		_where = ""                   # _place() builds the barracks squad
		_place()


func _gait(n: Node3D, speed: float) -> void:
	if n is MerchantNPC:
		(n as MerchantNPC).move_speed = speed


# ------------------------------------------------------------------ droids (issue #204)

static func job_id() -> String:
	return "j_general_droids"


func job_active() -> bool:
	return str(WorldState.jobs_taken.get(job_id(), "")) == "active"


## Ask him for work. Not while you are hostile. Returns true when you took it.
func take_job() -> bool:
	var open := WorldState.open_jobs("stranger").any(func(j): return str(j.id) == job_id())
	if not open:
		_say(_line("no_work"))
		return false
	WorldState.accept_job(job_id())
	_say(_line("job_taken") % droid_pay())
	return true


## What one droid pays: pay_mult times the droid merchant's resale.
func droid_pay() -> int:
	return int(cfg.get("pay_mult", 3)) * DroidRoster.resale(str(cfg.get("droid_kind", "assassin")))


func droids_to_hand_over() -> Array:
	if not job_active():
		return []
	var kind := str(cfg.get("droid_kind", "assassin"))
	return WorldState.droids.owned.filter(func(d): return str(d.kind) == kind)


## Hand one of your droids over: he pays, your Remnant standing goes up, and the
## job is open again for the next one. Returns the pay, or -1.
func hand_over(uid: int) -> int:
	var d := WorldState.droids.find(uid)
	if d.is_empty() or not droids_to_hand_over().has(d):
		return -1
	if not WorldState.droids.cargo_fits(uid, WorldState.inventory):
		return -1                                # its hold would spill: unload it first
	WorldState.droids.unload(uid, WorldState.inventory)
	WorldState.droids.remove(uid)
	if demo != null and demo.get("droids") != null:
		demo.droids._free_companion(uid)
	var pay := droid_pay()
	WorldState.credits += pay
	WorldState.change_standing("imperial_remnant", int(cfg.get("droid_standing", 5)), "Someone sold the Remnant general an assassin droid.")
	WorldState.jobs_taken.erase(job_id())       # open again
	WorldState.bump("general_droids")
	QuestNews.push("droid_delivered", "+%d cr" % pay)
	Story.event("general_droid_sold")
	_say(_line("paid") % pay)
	maybe_tip()
	return pay


## Issue #251: hand him the contraband of his run (WorldState.hand_over_contraband).
## Returns the pay, or 0 when there is nothing of his to hand over.
func hand_over_contraband() -> int:
	var pay := WorldState.hand_over_contraband(int(cfg.get("contraband_standing", 3)))
	if pay > 0:
		_say(_line("repossessed") % pay)
		maybe_tip()
	return pay


## Issue #205: in good standing he tells you about the crashed cruiser, once.
func maybe_tip() -> bool:
	if Quests.state("crashed_cruiser") != "" or int(WorldState.standing.get("imperial_remnant", 0)) < int(cfg.get("tip_standing", 15)):
		return false
	Story.event("heard_of_wreck")
	_say(_line("tip"))
	return true
