class_name DarkMasterPost
extends Node3D
## Issue #303: the dark master, a Remnant officer in all-black guard armour with a
## red energy sword. Where he stands is DarkPact's to say:
##   - the cruiser's bay, at the corridor's door, once the general is dead. In a
##     story save he makes his offer there: the talk opens by itself when you walk
##     up, Esc can't leave it, and it ends on "join" or "refuse" (his brain says
##     which; after `turns` of his lines with neither, a Join / Refuse menu asks).
##     Join and he is gone from the cruiser (DarkPact.join). Refuse and he says
##     "Then I must destroy you." and fights. In free roam he only fights.
##   - the barracks roof, facing the front gate, while the Remnant hold the planet
##     (on the oath in a story save; always in free roam). On the oath he only
##     fights back, and killing him turns the Remnant on you.
## His blade hangs dark on his hip while he is at ease, in every mode; he draws and
## lights it the moment he is hostile and the fight is on (NpcBody.blade_drawn), and
## hangs it up again if he gives up on you (you are down, or gone past give_up_m).
## He fights with BladeFighter: comes at you, strikes in short rushes, then steps
## back and circles before coming again; bounds down off the roof or across the
## deck, turns most bolts from the front aside with his blade, and reels when your
## own blade blocks a blow. Blade on blade (your block, or his guard turning your
## cut) throws sparks and shoves you both apart (clash()). He is a NpcBody (a soldier
## profile, content/core/soldiers/dark_master.json) outside any garrison: this
## node drives him.
##
## Config and lines: content/core/npcs/dark_master.json; his card (his voice):
## content/core/npcs/dark_master_card.json. The headless test calls decide(),
## build_at(), strike() and the guard directly.

const CARD_PATH := "res://content/core/npcs/dark_master_card.json"
const CRUISER := "cruiser"
const ROOF := "barracks"

var demo                              ## town_demo.gd (or null in a test)
var player: CharacterBody3D
var gear: GearController
var cfg: Dictionary = {}
var bodies: Dictionary = {}           ## "cruiser" | "barracks" -> NpcBody
var fighters: Dictionary = {}         ## the same keys -> BladeFighter
var hostile: Dictionary = {}          ## the same keys -> true while he is fighting you
var menu: DroidMenu
var host: ConversationHost
var spot: TalkSpot
var said := ""                        ## his last line (tests)
var meeting := false                  ## the offer is on and you have not answered
var verdict := ""                     ## "join" | "refuse" once answered (tests)
var _meet_lines := 0
var _was_talking := false
var _leaps: Dictionary = {}           ## where -> { from, to, t }
var _close_at := 0                    ## ticks (ms): close the talk then (0 = not waiting)


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "DarkMasterPost"
	cfg = DarkPact.cfg()
	menu = DroidMenu.new()
	add_child(menu)


func npc_name() -> String:
	return str(NpcBrain._read(CARD_PATH).get("name", "the dark master"))


func _line(key: String) -> String:
	return DarkPact.line(key)


func body(where: String) -> NpcBody:
	var b = bodies.get(where)
	return b if b != null and is_instance_valid(b) else null


# ------------------------------------------------------------------ where he stands

func _physics_process(dt: float) -> void:
	_place()
	if host != null:
		_watch_talk()
	if _close_at > 0 and Time.get_ticks_msec() >= _close_at:
		_close_at = 0
		_close_talk()
	if player == null or not is_instance_valid(player):
		return
	for where in bodies.keys():
		var b := body(str(where))
		if b == null or b.dead:
			continue
		var h := bool(hostile.get(where, false))
		b.blade_drawn = blade_wanted(h, b)
		if h and not (_in_talk() and spot.body == b):
			_fight(str(where), b, dt)     # (not while his last word is still on screen)
		else:
			_stand(b)
	_meet()
	_talk_prompt()


## Build him where DarkPact wants him and you are near; take him away where it
## doesn't (a dead body stays where it fell).
func _place() -> void:
	var want_cruiser := DarkPact.on_cruiser() and _cruiser_near()
	var want_roof := DarkPact.on_roof() and _town_ready()
	for pair in [[CRUISER, want_cruiser], [ROOF, want_roof]]:
		var where := str(pair[0])
		var b := body(where)
		if bool(pair[1]) and b == null and not bodies.has(where):
			build_at(where)
		elif not bool(pair[1]) and b != null and not b.dead and not (_in_talk() and spot.body == b):
			_drop(where)
	_sync_spot()


func _cruiser_near() -> bool:
	var c = demo.cruiser if demo != null and "cruiser" in demo else null
	if c == null or player == null or not is_instance_valid(player):
		return false
	return c.distance(player.global_position) <= float(c.cfg.get("wake_distance", 2600.0))


func _town_ready() -> bool:
	var town = demo.town if demo != null and "town" in demo else null
	return town != null and not town.get_marker(str(cfg.get("roof", {}).get("marker", "trooper_tower"))).is_empty()


## Where he stands and which way he faces: { at, face } (world), or {} for nowhere.
func post_of(where: String) -> Dictionary:
	if where == CRUISER:
		var c = demo.cruiser if demo != null and "cruiser" in demo else null
		if c == null:
			return {}
		var cr: Dictionary = cfg.get("cruiser", {})
		var local := _v(cr.get("at", [0, CruiserHull.DECK_Y, 20]))
		var at: Vector3 = c.to_world(local)
		return { "at": at, "face": c.to_world(local + _v(cr.get("face", [0, 0, 1]))) - at }
	var town = demo.town if demo != null and "town" in demo else null
	if town == null:
		return {}
	var r: Dictionary = cfg.get("roof", {})
	var at: Vector3 = town.marker_pos(str(r.get("marker", "trooper_tower"))) + _v(r.get("offset", [0, 0, 0]))
	var gate: Vector3 = town.marker_pos(str(r.get("face", "gate")))
	return { "at": at, "face": gate - at }


## Build him at `where` ("cruiser" / "barracks"). Returns his body, or null.
func build_at(where: String) -> NpcBody:
	var post := post_of(where)
	if post.is_empty() or demo == null or not demo.has_method("make_soldier"):
		return null
	var face: Vector3 = post.face
	var parent: Node = demo.cruiser if where == CRUISER else null
	var b: NpcBody = demo.make_soldier(str(cfg.get("soldier", "dark_master")), post.at, atan2(face.x, face.z),
		"dark_master/" + where, "npc:dark_master/" + where, parent)
	if b == null:
		return null
	b.set_meta("dark_master", where)
	b.display_name = npc_name()
	b.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	hostile[where] = DarkPact.hostile_at(where)
	# Built mid-fight (free roam, or back after a refusal) the blade is already out.
	b.hold_blade(Color(str(cfg.get("blade_color", "#ff2a2a"))), str(cfg.get("hilt", "")), float(cfg.get("blade_length", -1.0)), grip(),
		blade_wanted(bool(hostile[where]), b))
	var pose: Dictionary = {}
	for jn in cfg.get("guard_pose", {}):
		pose[jn] = _v(cfg.guard_pose[jn])
	b.hold_pose = pose
	var f := BladeFighter.new(cfg.get("blade", {}), 303 + bodies.size())
	b.guard_hit = _guard_hit.bind(where)
	b.died.connect(_on_died.bind(where))
	b.hit_by.connect(_on_hit.bind(where))
	bodies[where] = b
	fighters[where] = f
	return b


## His blade in the rigged hand (cfg "grip"), or null for NpcBody's own.
func grip():
	var g: Dictionary = cfg.get("grip", {})
	if g.is_empty():
		return null
	var r := _v(g.get("rot", [0, 0, 0]))
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))), _v(g.get("offset", [0, 0, 0])))


## Gone from there (he left, or you are far away): a living body only.
func _drop(where: String) -> void:
	var b := body(where)
	bodies.erase(where)
	fighters.erase(where)
	hostile.erase(where)
	_leaps.erase(where)
	if b == null:
		return
	if demo != null and "npcs" in demo:
		demo.npcs.erase(b)
	b.queue_free()


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


# ------------------------------------------------------------------ the fight

## At ease: at his post, watching you.
func _stand(b: NpcBody) -> void:
	if b.arrived() or b.command.go_to == Vector3.INF:
		b.stop()
	if player.global_position.distance_to(b.global_position) < float(cfg.get("watch_m", 30.0)):
		b.face_point(player.global_position)
	else:
		b.clear_face()


## He has given up on you for now: you are down, or gone past give_up_m.
func given_up(b: NpcBody) -> bool:
	if player == null or not is_instance_valid(player):
		return true
	return bool(player.get("is_downed")) or player.global_position.distance_to(b.global_position) > float(cfg.get("give_up_m", 90.0))


## The blade out of its holster: hostile, and the fight is on.
func blade_wanted(is_hostile: bool, b: NpcBody) -> bool:
	return is_hostile and not given_up(b)


func _fight(where: String, b: NpcBody, dt: float) -> void:
	var f: BladeFighter = fighters[where]
	var p := player.global_position
	if given_up(b):
		b.stop()
		b.clear_face()
		return
	var flat := Vector2(p.x - b.global_position.x, p.z - b.global_position.z).length()
	var out := f.update(dt, flat, p.y - b.global_position.y)
	match str(out.act):
		"chase":
			b.go_to(p, flat > float(cfg.get("blade", {}).get("walk_in_m", 7.0)))   # runs from far off, walks in
			b.face_point(p)
		"back_off", "circle":
			b.go_to(_give_ground(b, p, f, str(out.act), float(out.get("side", 1.0))), false)
			b.face_point(p)
		"leap":
			_leap(where, b, f, dt)
		_:
			b.stop()
			b.face_point(p)
	if str(out.start) != "":
		b.act(str(out.start))
		if f.blows == 1 or randf() < float(cfg.get("bark_chance", 0.15)):
			b.say(_pick(cfg.get("lines", {}).get("barks", [])), 2.0, true)
	if bool(out.strike):
		strike(where)


## Where he steps while giving ground, facing you: straight back (back_off), or
## round you at his spacing (circle, `side` picks the way).
func _give_ground(b: NpcBody, p: Vector3, f: BladeFighter, act: String, side: float) -> Vector3:
	var away := Vector3(b.global_position.x - p.x, 0.0, b.global_position.z - p.z)
	var d := away.length()
	away = away / d if d > 0.01 else -b.forward()
	if act == "back_off":
		return b.global_position + away * 2.0
	var round_you := Vector3(-away.z, 0.0, away.x) * side
	return b.global_position + round_you * 2.0 + away * clampf(f.spacing() - d, -1.0, 1.0)


## A bound: off the roof or across the deck, to just short of you.
func _leap(where: String, b: NpcBody, f: BladeFighter, dt: float) -> void:
	if not _leaps.has(where):
		_leaps[where] = { "from": b.global_position, "to": f.leap_target(b.global_position, player.global_position), "t": 0.0 }
		b.stop()
	var l: Dictionary = _leaps[where]
	l.t = float(l.t) + dt / maxf(0.05, f.leap_seconds())
	b.velocity = Vector3.ZERO
	b.global_position = BladeFighter.leap_point(l.from, l.to, float(l.t), float(cfg.get("leap_arc", 3.0)))
	b.face_point(player.global_position)
	if float(l.t) >= 1.0:
		_leaps.erase(where)


## His blow lands now: on you if you are in reach and in front of him; your
## blade's block turns it and he reels. Returns "landed", "parried" or "".
func strike(where: String) -> String:
	var b := body(where)
	var f: BladeFighter = fighters.get(where)
	if b == null or f == null or player == null:
		return ""
	var to := player.global_position - b.global_position
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() > f.reach() + float(cfg.get("blade", {}).get("reach_slack", 0.6)) or absf(to.y) > 1.8:
		return ""
	if flat.length() > 0.3 and flat.normalized().dot(b.forward()) < 0.2:
		return ""
	if _player_blocking():
		f.on_parried()
		b.play_sfx("hurt")
		clash(b)
		return "parried"
	f.on_landed()
	if player.has_method("apply_damage_from"):
		player.apply_damage_from(float(cfg.get("blade", {}).get("damage", 26)), b)
	elif player.has_method("apply_damage"):
		player.apply_damage(float(cfg.get("blade", {}).get("damage", 26)))
	return "landed"


func _player_blocking() -> bool:
	var kit = demo.player_kit if demo != null and "player_kit" in demo else null
	if kit == null or kit.weapons == null or kit.weapons.combo == null:
		return false
	return kit.weapons.holder.current == "energy_blade" and kit.weapons.combo.blade.is_blocking()


## NpcBody.guard_hit: his blade turns bolts (and some cuts) from the front aside.
func _guard_hit(amount: float, shooter: Node, by_blade: bool, where: String) -> float:
	var b := body(where)
	var f: BladeFighter = fighters.get(where)
	if b == null or f == null:
		return amount
	var front := true
	if shooter is Node3D and is_instance_valid(shooter):
		var to := (shooter as Node3D).global_position - b.global_position
		to.y = 0.0
		front = to.length() < 0.3 or to.normalized().dot(b.forward()) > cos(deg_to_rad(float(cfg.get("blade", {}).get("guard_cone_deg", 70.0))))
	if not bool(hostile.get(where, false)):
		front = false              # caught off guard: the first shot gets through
	var turned := f.deflected
	var left := f.guard(amount, front, by_blade)
	if by_blade and f.deflected > turned and player != null and is_instance_valid(player) \
			and player.global_position.distance_to(b.global_position) <= f.reach() + 1.5:
		clash(b)                   # his guard turned your cut
	return left


## Blade on blade: a burst of sparks where they crossed, and you and he shoved
## apart. Returns where the sparks went (tests).
func clash(b: NpcBody) -> Vector3:
	if b == null or player == null or not is_instance_valid(player):
		return Vector3.INF
	var c: Dictionary = cfg.get("blade", {}).get("clash", {})
	var apart := Vector3(b.global_position.x - player.global_position.x, 0.0, b.global_position.z - player.global_position.z)
	apart = apart.normalized() if apart.length() > 0.01 else b.forward() * -1.0
	var at := (b.global_position + player.global_position) * 0.5 + Vector3.UP * float(c.get("height", 1.3))
	if b.is_inside_tree():
		ExplosionFx.clash(b.get_parent(), at, Color(str(cfg.get("blade_color", "#ff2a2a"))).lerp(Color.WHITE, 0.5))
	var push := float(c.get("push", 7.0))
	var fade := float(c.get("fade", 16.0))
	b.knock(apart * push, fade)
	if player.has_method("knock"):
		player.knock(-apart * push * float(c.get("player_share", 1.0)), fade)
	var kit = demo.player_kit if demo != null and "player_kit" in demo else null
	if kit != null and kit.weapons != null and kit.weapons.has_method("on_clash"):
		kit.weapons.on_clash()
	return at


## Hit by you while at ease: he fights back.
func _on_hit(shooter: Node, _amount: float, where: String) -> void:
	if shooter == player and not bool(hostile.get(where, false)) and not meeting:
		hostile[where] = true
		var b := body(where)
		if b != null:
			b.say(_line("provoked"), 2.5, true)


func _on_died(where: String) -> void:
	if spot != null and spot.body == body(where) and _in_talk():
		spot.hold_line = ""
		host.end_talk()
	meeting = false
	DarkPact.on_killed(where)
	# His blade falls where he does: a pickup, yours to activate in the inventory.
	var item := str(cfg.get("drops", ""))
	var b := body(where)
	if item != "" and b != null and gear != null and gear.drop_item({ "id": "dark_master_blade_" + where, "item": item, "reach": 2.6 }, b.global_position) != null:
		_toast(_line("blade_dropped"))


# ------------------------------------------------------------------ the offer (story mode)

## Join the town's conversation host as one of its AI characters.
func attach_host(h: ConversationHost) -> void:
	if h == null or host == h:
		return
	host = h
	var brain := NpcBrain.new(null, CARD_PATH)
	spot = TalkSpot.new(brain, null, Vector3.ZERO)
	spot.manual = true
	spot.radius = float(cfg.get("reach", 3.2))
	spot.face_height = 1.75
	brain.extra_brief = func(): return [_line("brief")] if meeting else [_line("brief_after")]
	brain.verdict.connect(_on_verdict)
	# Through add_spot, as the general: it gives his brain the AI service and wires
	# the host's reply handlers (the box unlocks when his line is done). Without it
	# every answer was canned even with AI on, and the box stayed locked after your
	# first line, with Esc only repeating his hold line. _sync_spot then keeps him
	# in or out of the host's list.
	host.add_spot(spot)
	brain.line_done.connect(_on_line)        # after the host's: his line is on screen first
	_sync_spot()


## His TalkSpot follows the body you can talk to: the cruiser's while his offer is
## due, the roof's while you are sworn to him and he is not fighting.
func _sync_spot() -> void:
	if spot == null or host == null:
		return
	if _in_talk():
		return
	var b: NpcBody = null
	if DarkPact.offer_due() and body(CRUISER) != null and not bool(hostile.get(CRUISER, false)):
		b = body(CRUISER)
	elif DarkPact.joined() and body(ROOF) != null and not bool(hostile.get(ROOF, false)):
		b = body(ROOF)
	spot.body = b
	if b == null or b.dead:
		host.spots.erase(spot)
		return
	spot.stand = b.global_position
	if not host.spots.has(spot):
		host.spots.append(spot)


func _in_talk() -> bool:
	return host != null and spot != null and host.is_talking() and host.active == spot


## You step out near him aboard the cruiser: the talk opens by itself.
func _meet() -> void:
	var b := body(CRUISER)
	if b == null or b.dead or not DarkPact.offer_due() or host == null or spot == null or host.is_talking() \
			or menu.is_open() or bool(player.get("piloting")) or spot.body != b:
		return
	if player.global_position.distance_to(b.global_position) <= float(cfg.get("meet_reach", 9.0)):
		begin_meeting()
		host.start_talk(spot)


func begin_meeting() -> void:
	meeting = true
	_meet_lines = 0
	if spot != null:
		spot.hold_line = _line("hold") % npc_name()
		spot.brain.builder.extra_actions = ["join", "refuse"]


func _on_verdict(kind: String) -> void:
	if meeting and kind in ["join", "refuse"]:
		decide(kind)


## His line in the meeting. An answer came with it (decide() ran already), or he
## ended the talk, or after enough lines with neither: the game asks you outright.
func _on_line(turn: Dictionary) -> void:
	if not meeting:
		return
	var applied: Array = turn.get("applied", [])
	_meet_lines += 1
	# Issue #328: with AI characters off his lines are written ones: fewer of them.
	var offline := host != null and host.llm != null and not host.llm.ai_on()
	var turns := int(cfg.get("turns_offline" if offline else "turns", cfg.get("turns", 4)))
	if applied.has("end_conversation") or _meet_lines >= turns:
		ask()


## The hard choice: Join / Refuse, nothing else (Esc asks again).
func ask() -> void:
	if not meeting or menu.is_open():
		return
	if _in_talk():
		spot.hold_line = ""
		host.end_talk()
	var opts := [{ "id": "join", "text": _line("choose_join") }, { "id": "refuse", "text": _line("choose_refuse") }]
	menu.open(_line("choose_title") % npc_name(), opts, _on_choice, DarkPact.line("offer"))
	if player != null:
		player.locked = true


func _on_choice(id: String) -> void:
	if player != null:
		player.locked = false
	if id in ["join", "refuse"]:
		decide(id)
	elif meeting:
		ask.call_deferred()


## Your answer. Join: the oath (DarkPact.join), his crew stands down, and he
## leaves the cruiser once the talk closes. Refuse: he fights. Returns false once
## answered.
func decide(kind: String) -> bool:
	if verdict != "" or not kind in ["join", "refuse"]:
		return false
	meeting = false
	verdict = kind
	if spot != null:
		spot.hold_line = ""
		spot.brain.builder.extra_actions = []
	if kind == "join":
		DarkPact.join()
		var c = demo.cruiser if demo != null and "cruiser" in demo else null
		if c != null and c.garrison != null:
			c.garrison.always_hostile = false
		_say(_line("joined"))
	else:
		DarkPact.refuse()
		_say(_line("refused"))
		hostile[CRUISER] = true
	if _in_talk():
		host.panel.post_notice(said)
		_close_at = Time.get_ticks_msec() + int(1000.0 * float(cfg.get("end_delay", {}).get(kind, 1.5)))
	return true


func _close_talk() -> void:
	if _in_talk():
		host.end_talk()


## The talk closed: an offer still open asks outright.
func _watch_talk() -> void:
	var talking := _in_talk()
	if _was_talking and not talking and meeting:
		ask()
	_was_talking = talking


## [E] beside him on the roof (sworn to him): talk.
func _talk_prompt() -> void:
	if spot == null or host == null or spot.body == null or host.is_talking() or menu.is_open() or meeting:
		return
	if not spot.in_range(player) or (gear != null and not gear.focus.is_empty()):
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(_line("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		host.start_talk(spot)


func _say(text: String) -> void:
	said = text
	var b := body(CRUISER) if body(CRUISER) != null else body(ROOF)
	if b != null and text != "":
		b.say(text, 3.0)
	_toast("%s: %s" % [npc_name(), text] if text != "" else "")


func _toast(text: String) -> void:
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 5.0)


func _pick(list: Array) -> String:
	return str(list[randi() % list.size()]) if not list.is_empty() else ""
