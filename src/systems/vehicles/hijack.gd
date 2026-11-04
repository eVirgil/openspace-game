extends Node
## Hijacking: on foot (or on your own speeder), within reach of a ship or speeder
## someone else is flying or riding, E hops you up onto it (`hop_s`, an arc over
## the line from you to its top, following it as it moves), then the one at the
## controls is thrown out (on their feet on the ground beside it, a little hurt)
## and you have it. Numbers and words: content/core/flow/hijack.json.
##
## Who can be taken:
##   - LAN (above all): another player in their ship (seated, on the ground or in
##     the air down here: NetLink's ship packet says so) or on their speeder
##     (NetLink's speeder packet). Their game owns it, so the hop ends with a word
##     to it (NetLink.hijack_take); it throws them out and answers with what it was
##     (ship id, look, where, speed, hull; a speeder's data and paint), and this
##     game builds that here and seats you (ShipPilot.seat_taken; a SpeederNode).
##     Everyone else sees their ship go and yours come, where it was. It stays
##     theirs: get out (or eject, or get off) and it is back in their game where
##     you left it, on the ground below; wreck it and it is wrecked there too.
##   - The Remnant interceptor, while it flies low enough to reach (coming down on
##     its pad, a jetpack's hop under it): its pilot is thrown clear and the ship is
##     stolen, as one taken off its pad (AtmoFighter.hijack).
## The town builds one (TownDemo.hijack); ShipPilot and SpeederNode leave E to it
## while it has something to take (claims_e).

const CFG_PATH := "res://content/core/flow/hijack.json"
const SHIP := "ship"
const SPEEDER := "speeder"

static var _cfg: Dictionary = {}

var demo                       ## town_demo.gd
var target: Dictionary = {}    ## what E would take now: { kind, peer (0: the AI), node, label, dist }
var hops := 0                  ## hops started (traces, tests)
var takes := 0                 ## vehicles taken (traces, tests)
var thrown := 0                ## times you were thrown out of yours (traces, tests)
var _hop: Dictionary = {}      ## the hop under way: { kind, peer, node, from, t, waiting, left }
var _cool := 0.0
var _prompt: Label
var _taken_speeders: Dictionary = {}   ## peer id -> your SpeederNode they ride (hidden here)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
	return _cfg


static func n(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func label(key: String) -> String:
	return str(cfg().get("labels", {}).get(key, key))


static func fmt(key: String, args: Array) -> String:
	var line := label(key)
	return line % args if line.count("%s") == args.size() else line


func setup(town) -> void:
	demo = town
	name = "Hijack"


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -200)
	_prompt.size = Vector2(600, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	layer.add_child(_prompt)


## E is ours this frame: there is something to take, or a hop is under way.
func claims_e() -> bool:
	return not target.is_empty() or not _hop.is_empty()


func hopping() -> bool:
	return not _hop.is_empty()


func _pilot():
	var p = demo.get("pilot") if demo != null else null
	return p if p != null and is_instance_valid(p) else null


func _player() -> CharacterBody3D:
	var p = demo.get("_player") if demo != null else null
	return p if p is CharacterBody3D and is_instance_valid(p) else null


func _link():
	return NetSession.link if NetSession.active() else null


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_cool -= dt
	if not _hop.is_empty():
		target = {}
		_prompt.visible = false
		_hop_step(dt)
		return
	target = find() if _cool <= 0.0 else {}
	_prompt.visible = not target.is_empty()
	if not target.is_empty():
		_prompt.text = fmt("prompt", [str(target.label)])
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			start(target)


## The nearest vehicle you could take now, or {}. You are on foot or riding your
## own speeder (not in a ship, not down, not mid-hop).
func find() -> Dictionary:
	var p := _player()
	var pilot = _pilot()
	if p == null or pilot == null or pilot.piloting or bool(p.get("is_downed")):
		return {}
	var on_speeder: bool = p.vehicle is SpeederNode and (p.vehicle as SpeederNode).riding
	if not on_speeder and (p.locked or p.piloting):
		return {}
	var me := p.global_position
	var best: Dictionary = {}
	var link = _link()
	if link != null:
		var now := Time.get_ticks_msec() / 1000.0
		var stale := NetSession.n("ship_stale_s", 2.0)
		for id in link.ship_bodies:
			var rs = link.ship_bodies[id]
			var s: Dictionary = link.ships.get(id, {})
			if rs == null or not is_instance_valid(rs) or not rs.is_visible_in_tree() \
					or not bool(s.get("seated", false)) or now - float(s.get("t", 0.0)) > stale:
				continue
			best = _closer(best, me, SHIP, int(id), rs, (rs as Node3D).global_position,
				fmt("ship_of", [str(rs.player_name)]))
		for id in link.ride_bodies:
			var rb = link.ride_bodies[id]
			var r: Dictionary = link.rides.get(id, {})
			if rb == null or not is_instance_valid(rb) or not rb.is_visible_in_tree() or now - float(r.get("t", 0.0)) > stale:
				continue
			best = _closer(best, me, SPEEDER, int(id), rb, (rb as Node3D).global_position,
				fmt("speeder_of", [str(rb.player_name)]))
	var foe = demo.get("interceptor")
	if foe != null and is_instance_valid(foe) and foe.has_method("can_hijack") and foe.can_hijack():
		best = _closer(best, me, SHIP, 0, foe, foe.position(), str(foe.cfg.get("label", "")))
	return best


func _closer(best: Dictionary, me: Vector3, kind: String, peer: int, node: Node, at: Vector3, text: String) -> Dictionary:
	var u := _up(at)
	var rel := me - at
	var along := rel.dot(u)
	var flat := (rel - u * along).length()
	var reach := n(kind + "_reach_m", 6.0)
	if flat > reach or absf(along) > n(kind + "_rise_m", 4.0):
		return best
	if not best.is_empty() and float(best.dist) <= flat:
		return best
	return { "kind": kind, "peer": peer, "node": node, "label": text, "dist": flat }


func _up(at: Vector3) -> Vector3:
	var pilot = _pilot()
	return pilot.ground.up_at(at) if pilot != null and pilot.ground != null else Vector3.UP


## Where on vehicle `node` you land.
func _top(kind: String, node: Node) -> Vector3:
	var at: Vector3 = node.position() if node.has_method("can_hijack") else (node as Node3D).global_position
	return at + _up(at) * n(kind + "_top_m", 1.5)


# ------------------------------------------------------------------ the hop

## Hop onto `t` (find()'s): off your speeder first if you ride one.
func start(t: Dictionary) -> bool:
	var p := _player()
	if p == null or t.is_empty() or not _hop.is_empty():
		return false
	if p.vehicle is SpeederNode and (p.vehicle as SpeederNode).riding:
		(p.vehicle as SpeederNode).dismount()
	_hop = { "kind": str(t.kind), "peer": int(t.peer), "node": t.node, "from": p.global_position,
		"t": 0.0, "waiting": false, "left": n("wait_s", 2.0) }
	p.locked = true
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_collide(p, false)
	hops += 1
	var link = _link()
	if int(t.peer) != 0 and link != null:
		link.hijack_warn.rpc_id(int(t.peer), str(t.kind))
	return true


func _hop_step(dt: float) -> void:
	var p := _player()
	var node = _hop.node
	if p == null or node == null or not is_instance_valid(node) or not _still_there():
		_slip()
		return
	var kind := str(_hop.kind)
	var top := _top(kind, node)
	_hop.t = float(_hop.t) + dt
	var f := clampf(float(_hop.t) / maxf(0.05, n("hop_s", 1.0)), 0.0, 1.0)
	var from: Vector3 = _hop.from
	var at := from.lerp(top, smoothstep(0.0, 1.0, f)) + _up(top) * sin(PI * f) * n("hop_arc_m", 1.8)
	p.global_position = at
	if f < 1.0:
		return
	if int(_hop.peer) == 0:
		_take_ai(node)
		return
	if not bool(_hop.waiting):
		_hop.waiting = true
		var link = _link()
		if link == null:
			_slip()
			return
		link.hijack_take.rpc_id(int(_hop.peer), kind)
	_hop.left = float(_hop.left) - dt
	if float(_hop.left) <= 0.0:
		_slip()


## The vehicle hopped at is still taken by someone (they did not get out, or go).
func _still_there() -> bool:
	var peer := int(_hop.peer)
	if peer == 0:
		return bool(_hop.node.can_hijack()) or bool(_hop.waiting)
	var link = _link()
	if link == null or not link.roster.has(peer):
		return false
	if bool(_hop.waiting):
		return true                     # their answer decides now
	if str(_hop.kind) == SHIP:
		return bool(link.ships.get(peer, {}).get("seated", false))
	return link.rides.has(peer)


## Back on your feet (falling from where you are), the hop over.
func _release() -> void:
	var p := _player()
	_hop = {}
	_cool = n("cooldown_s", 1.0)
	if p == null:
		return
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	_collide(p, true)
	p.velocity = Vector3.ZERO
	if p.get("controller") != null:
		p.controller.velocity = Vector3.ZERO
		p.controller.body_pos = p.global_position


func _slip() -> void:
	_release()
	_toast(label("slipped"))


func _collide(p: Node, on: bool) -> void:
	for ch in p.get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


func _take_ai(foe) -> void:
	_release()
	if foe.hijack():
		takes += 1
		_pilot().hud.toast(fmt("ai_thrown", [str(foe.cfg.get("label", ""))]), 4.0)


# ------------------------------------------------------------------ LAN: the hijacker's side

## Their game answered: `st` is what you took ({} = they got away first).
func on_answer(peer: int, kind: String, st: Dictionary) -> void:
	var mine := not _hop.is_empty() and int(_hop.peer) == peer and str(_hop.kind) == kind
	if st.is_empty():
		if mine:
			_slip()
		return
	if not mine:
		_send_back(peer, kind, st.get("xf", Transform3D.IDENTITY), false)   # too late: theirs again
		return
	_release()
	var ok := _seat_ship(peer, st) if kind == SHIP else _seat_speeder(peer, st)
	if not ok:
		_send_back(peer, kind, st.get("xf", Transform3D.IDENTITY), false)
		return
	takes += 1
	var link = _link()
	var who := str(link.roster.get(peer, {}).get("name", "")) if link != null else ""
	_toast(fmt("took", [fmt(kind + "_of", [who])]))


func _seat_ship(peer: int, st: Dictionary) -> bool:
	var pilot = _pilot()
	if pilot == null:
		return false
	if not pilot.hijack_let_go.is_connected(_on_ship_let_go):
		pilot.hijack_let_go.connect(_on_ship_let_go)
	return pilot.seat_taken(st, peer) >= 0


func _on_ship_let_go(peer: int, xf: Transform3D, wrecked: bool) -> void:
	_send_back(peer, SHIP, xf, wrecked)


func _seat_speeder(peer: int, st: Dictionary) -> bool:
	var pilot = _pilot()
	var p := _player()
	var c = st.get("cfg", {})
	if pilot == null or p == null or not (c is Dictionary) or (c as Dictionary).is_empty():
		return false
	var xf: Transform3D = st.get("xf", Transform3D.IDENTITY)
	var s := SpeederNode.new()
	s.setup(demo, pilot.ground, c, true, str(st.get("paint", "")))
	s.set_meta("hijacked_from", peer)
	demo.add_child(s)
	s.place(xf.origin, float(st.get("yaw", 0.0)))
	s.model.speed = float(st.get("speed", 0.0))
	p.global_position = s.model.position
	if not s.mount():
		s.queue_free()
		return false
	s.dismounted.connect(func(): _speeder_let_go(s))
	return true


## Off their speeder (or it burst under you): back to them where it is.
func _speeder_let_go(s: SpeederNode) -> void:
	if s.has_meta("given_back"):
		return
	s.set_meta("given_back", true)
	var peer := int(s.get_meta("hijacked_from", 0))
	var wrecked := not s.model.alive()
	_send_back(peer, SPEEDER, s.model.transform(), wrecked)
	var link = _link()
	if link != null:
		link.vehicle_gone.rpc(SPEEDER)
	if not wrecked:
		s.queue_free.call_deferred()


func _send_back(peer: int, kind: String, xf: Transform3D, wrecked: bool) -> void:
	var link = _link()
	if link != null and link.roster.has(peer) and peer != link.my_id():
		link.hijack_back.rpc_id(peer, kind, xf, wrecked)


# ------------------------------------------------------------------ LAN: the victim's side

## Player `peer` is hopping onto yours.
func on_warn(peer: int, kind: String) -> void:
	var link = _link()
	var who := str(link.roster.get(peer, {}).get("name", "")) if link != null else ""
	_toast(fmt("climbing", [who, label(kind)]), 2.0)


## Player `peer` is on top of yours: if you still sit in it, you are thrown out and
## it is theirs. Returns what it was for their game ({} = nothing to take).
func on_take(peer: int, kind: String) -> Dictionary:
	var p := _player()
	var pilot = _pilot()
	if p == null or pilot == null:
		return {}
	var st: Dictionary = {}
	var at := p.global_position
	if kind == SHIP:
		st = pilot.thrown_out(peer)
		if not st.is_empty():
			at = (st.xf as Transform3D).origin
	elif kind == SPEEDER and p.vehicle is SpeederNode and (p.vehicle as SpeederNode).can_be_hijacked():
		var s := p.vehicle as SpeederNode
		at = s.model.position
		st = s.thrown_out(peer)
		if not st.is_empty():
			_taken_speeders[peer] = s
	if st.is_empty():
		return {}
	thrown += 1
	_shove(p, at)
	var link = _link()
	var who := str(link.roster.get(peer, {}).get("name", "")) if link != null else ""
	_toast(fmt("thrown_out", [who, label(kind)]))
	return st


## Thrown clear: a little hurt, pushed away from the vehicle.
func _shove(p: CharacterBody3D, from: Vector3) -> void:
	var u := _up(p.global_position)
	var away := p.global_position - from
	away -= u * away.dot(u)
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	p.last_hit_from = from
	p.apply_damage(n("victim_damage", 6.0))
	if p.has_method("launch"):
		p.launch(u * n("victim_kick", 3.0), away * n("victim_push", 6.0), n("victim_push_fade", 10.0))


## Player `peer` let yours go at `xf` (or wrecked it).
func on_back(peer: int, kind: String, xf: Transform3D, wrecked: bool) -> void:
	var back := false
	if kind == SHIP:
		var pilot = _pilot()
		back = pilot != null and pilot.hijack_returned(peer, xf, wrecked)
	else:
		var s = _taken_speeders.get(peer, null)
		_taken_speeders.erase(peer)
		if s != null and is_instance_valid(s):
			s.hijack_returned(xf, wrecked)
			back = true
	if not back:
		return
	var link = _link()
	var who := str(link.roster.get(peer, {}).get("name", "")) if link != null else ""
	_toast(fmt("wrecked", [who, label(kind)]) if wrecked else fmt("given_back", [label(kind), who]))


## Player `peer` left the game holding yours: it is back where they took it.
func on_left(peer: int) -> void:
	var pilot = _pilot()
	if pilot != null:
		pilot.hijack_returned(peer, Transform3D(Basis.IDENTITY, Vector3.INF), false)
	var s = _taken_speeders.get(peer, null)
	_taken_speeders.erase(peer)
	if s != null and is_instance_valid(s):
		s.hijack_returned(s.model.transform(), false)


func _toast(text: String, secs := 4.0) -> void:
	var pilot = _pilot()
	if text == "" or pilot == null:
		return
	if pilot.piloting:
		pilot.hud.toast(text, secs)
	else:
		pilot._foot_toast(text)
