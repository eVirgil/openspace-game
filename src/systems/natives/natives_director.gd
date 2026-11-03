class_name NativesDirector
extends Node3D
## Issue #96: a planet's native people and wild animals, in play. Built by the
## town scene from the planet's "natives" (NativesData.resolve: its own config or
## its type's, the way the planet generator gives a planet everything else).
##
## Packs: 10 to 20 of one people on foot, children among them (the same bodies at
## 60%), a leader in the helmet carrying a tall pole with a rag on it so a pack is
## seen coming from far off. Every member of a pack wears the pack's colours.
## They walk their route over and over. Each NPC is an NpcBody (the guards' body,
## senses and health) walking open ground with no navmesh (free_walk), steering
## round the boulders and mesas the ground knows about (NativeSteer); far from the
## player (pack.far_lod_m) they are slid along the ground instead, no physics, so
## a pack can cross the desert where there is no collider.
##
## Camps (NativeCamp): a pack with a camp starts there, stops there on every loop
## of its route (sitting round the fire a while) and comes back to it for the
## night. A few of its members (the keepers) never leave it. Each tent has a chest:
## take what is in it and, if one of the pack sees you, they turn on you. Shoot
## the tents down and the camp is wrecked; it is back a few in-game hours later.
## In a friendly pack's standing tent, [Z] rests: the screen goes dark, you heal,
## it is morning, the game is saved.
##
## How a pack treats you is its own (WorldState.native_pack), never your standing
## with the Remnant:
##   friendly  the leader comes over and gestures (they do not speak the port's
##             language: yells, and trade by hand). [E] gestures back: one food for
##             quartz (a little more from an adults-only pack), reputation up.
##   hostile   a battle horn, then they come at you on sight with clubs, and throw
##             rocks from further off (the leader never throws). They fight to the
##             last; nobody flees. Survive survive_s (1 minute) without killing
##             one of them and without being downed, and they stop, offer trade and
##             are friendly from then on. Kill one and that pack is hostile for
##             good. Downed, you wake as from any other death and they go back to
##             their route.
## The moves (a club swing, a rock throw, the gestures) are NativeMoves, played
## over the walk by NpcBody.act(). They never speak through the voice service.
## Animals: each roams alone (SandPig); kill one and [E] at the carcass cuts food.
##
## Issue #402: in a LAN guest's town on the host's planet (TownDemo.lan_shared)
## the packs, camps and animals are the host's: this director builds them as ever
## but drives none of them; NetWorld moves them where the host's are, sends their
## hits to the host's game and kills them when the host's die. Trading, chests and
## resting stay this game's own, by the host's pack's mood (net_friendly).
##
## Not built yet: packs fighting each other and the Remnant, sandstorms (#175),
## stealing vehicles (#176).

signal traded(pack_id: String, quartz: int)
signal pack_won(pack_id: String)
signal pack_locked(pack_id: String)
signal looted(pack_id: String, items: Dictionary, seen: bool)
signal rested

var demo                              ## town_demo.gd
var ground: WorldGround
var gear: GearController
var player: CharacterBody3D
var natives: Dictionary = {}
var people: Dictionary = {}           ## the species data
var packs: Array = []                 ## see _make_pack
var pigs: Array = []                  ## SandPig
var camps: Array = []                 ## NativeCamp
var steer: NativeSteer                ## the rocks they walk round
var survive_s := 60.0                 ## issue #211: was 300 (the data's hostile.survive_s wins)
var menu: DroidMenu                   ## issue #211: what a friendly pack will trade
## Members far from the player (slid along the ground) step once in this many ticks.
var far_stride := 4
var trades := 0
var butchered := 0
var steals := 0
var rests := 0
var resting := false
var _rng := RandomNumberGenerator.new()
var _hud: CanvasLayer
var _timer_label: Label
var _fade: ColorRect
var _clock := 0.0
var _camp_check := 0.0
## Issue #402 (a LAN guest): pack id -> the host's pack turns on you, for a pack
## this game saw stealing or tearing its tents (NetWorld sets it).
var net_provoke: Callable


func setup(town_demo, n: Dictionary, world_ground: WorldGround, p_gear: GearController) -> void:
	demo = town_demo
	natives = n
	ground = world_ground
	gear = p_gear
	player = demo._player
	people = n.get("people", {}).get("data", {})
	survive_s = float(people.get("hostile", {}).get("survive_s", 60.0))
	name = "Natives"
	_rng.seed = 96


func _ready() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.position = Vector2(-240, 110)
	_timer_label.size = Vector2(480, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color("#ffb060"))
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_timer_label.add_theme_constant_override("outline_size", 6)
	_timer_label.visible = false
	_hud.add_child(_timer_label)
	_fade = ColorRect.new()
	_fade.name = "RestFade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	_hud.add_child(_fade)
	_queue_build()
	if not staged:
		while not build_step():
			pass


# ------------------------------------------------------------------ build (issue #121)

## True: _ready only queues the bodies and build_step() makes them, one per call
## (a staged planet handoff builds the scene over several frames). Set before
## add_child. Each body is a whole procedural character, tens to hundreds of ms.
var staged := false
var _build_queue: Array = []          ## Callables, run in order: the same order (and the
                                      ## same random draws) as building everything at once


func _queue_build() -> void:
	_build_queue.clear()
	_build_queue.append(func(): steer = NativeSteer.from_ground(ground))
	if not people.is_empty():
		var i := 0
		for p in natives.get("packs", []):
			var idx := i
			_build_queue.append(func(): _start_pack(p, idx))
			i += 1
	for f in natives.get("fauna", []):
		var state := { "f": f }
		_build_queue.append(func(): return _fauna_step(state))


## Make the next body (or start the next pack). True once everything is built.
func build_step() -> bool:
	while not _build_queue.is_empty():
		var job: Callable = _build_queue.pop_front()
		if job.call() == true:
			return _build_queue.is_empty()  # a body was made: one per call
	return true


## Whether every pack member and animal exists.
func is_built() -> bool:
	return _build_queue.is_empty()


func _line(key: String) -> String:
	return str(people.get("lines", {}).get(key, key))


func _voice(key: String) -> Array:
	return people.get("voice", {}).get(key, [])


func _camp_cfg() -> Dictionary:
	return people.get("camp", {})


# ------------------------------------------------------------------ ground

## A map point (metres along the ground from the port) on the ground.
func surface(m: Vector2) -> Vector3:
	var sp := ground.sphere() if ground != null else null
	if sp != null:
		return sp.surface_at(m.x, m.y)
	var h := ground.terrain.height_at(m.x, m.y) if ground != null and ground.terrain != null else 0.0
	return Vector3(m.x, h, m.y)


func up_at(p: Vector3) -> Vector3:
	return ground.up_at(p) if ground != null else Vector3.UP


func _on_ground(p: Vector3) -> Vector3:
	return ground.surface_below(p + up_at(p) * 4.0) if ground != null else p


## A map point on the ground, moved off any rock it lands on.
func _clear_surface(m: Vector2) -> Vector3:
	var at := surface(m)
	if steer != null:
		at = _on_ground(steer.clear_spot(at, up_at(at)))
	return at


# ------------------------------------------------------------------ packs

## A pack's record and root now, its members as the next jobs (in order). The
## pack is listed at once; one with no members yet is skipped every tick.
func _start_pack(p: Dictionary, index: int) -> bool:
	var pack := _make_pack(p, index)
	packs.append(pack)
	return false


func _make_pack(p: Dictionary, index: int) -> Dictionary:
	var id := str(p.get("id", "pack_%d" % index))
	var rec := WorldState.native_pack(id, str(p.get("attitude", "friendly")))
	var route: Array = (p.get("route", []) as Array).map(func(m): return _clear_surface(m))
	if route.is_empty():
		route = [surface(Vector2(600, 0))]
	var style := _style(str(p.get("style", "")), index)
	var size := clampi(int(p.get("size", 12)), 1, 40)
	var kids := clampi(int(p.get("children", 0)), 0, size - 1)
	var pack := {
		"id": id, "label": str(p.get("label", id)), "data": p, "rec": rec, "route": route, "route_i": 1 % route.size(),
		"members": [], "state": "travel", "attack_t": 0.0, "horned": false, "adults_only": kids == 0,
		"heading": Vector3.FORWARD, "center": route[0], "camp": null, "camp_i": -1, "camp_t": 0.0,
		"keepers": 0, "gesture_t": 0.0, "home_state": "travel",
	}
	var root := Node3D.new()
	root.name = "Pack_" + id
	add_child(root)
	pack["root"] = root
	_make_camp(pack, p, style)
	var jobs: Array = []
	for i in size:
		var slot := i
		jobs.append(func(): _add_member(pack, slot, size, kids, style); return true)
	_build_queue = jobs + _build_queue
	if bool(rec.get("friendly", false)) == false and bool(rec.get("won", false)):
		rec.friendly = true
	return pack


## The pack's camp, when it has one and its people make camps: a stop on the route
## (after route point "stop_after", the last by default), where the pack starts.
func _make_camp(pack: Dictionary, p: Dictionary, style: Dictionary) -> void:
	var pc = p.get("camp", null)
	if not (pc is Dictionary) or _camp_cfg().is_empty():
		return
	var cfg: Dictionary = _camp_cfg().duplicate(true)
	for k in pc:
		cfg[k] = pc[k]
	if style.has("hide"):
		cfg["hide"] = style.hide
	if style.has("rug"):
		cfg["rug"] = style.rug
	var at_m = pc.get("at", null)
	var route: Array = pack.route
	var at: Vector3 = _clear_surface(at_m if at_m is Vector2 else Vector2(float(at_m[0]), float(at_m[1]))) \
		if at_m != null else route[0]
	var camp := NativeCamp.new()
	camp.setup(str(pack.id), cfg, self, at)
	(pack.root as Node3D).add_child(camp)
	camp.build()
	camp.tent_hit.connect(_on_tent_hit.bind(pack))
	camp.wrecked.connect(_on_camp_wrecked.bind(pack))
	var st := WorldState.native_camp(str(pack.id))
	if float(st.get("wrecked_h", -1.0)) >= 0.0:
		if WorldState.game_hours - float(st.wrecked_h) >= float(cfg.get("return_hours", 4.0)):
			st.wrecked_h = -1.0
		else:
			camp.show_wrecked()
	camps.append(camp)
	var after := clampi(int(pc.get("stop_after", route.size() - 1)), 0, route.size() - 1)
	route.insert(after + 1, camp.center)
	pack.camp = camp
	pack.camp_i = after + 1
	pack.route_i = pack.camp_i
	pack.center = camp.center
	pack.keepers = clampi(int(cfg.get("keepers", 3)), 0, maxi(0, int(p.get("size", 12)) - 2))
	pack.state = "camp"
	pack.camp_t = float(cfg.get("stop_s", 45.0))
	_refresh_lids(pack)


## Member `i` of `pack` (the leader is 0, the children last; the last few stay at
## the camp).
func _add_member(pack: Dictionary, i: int, size: int, kids: int, style: Dictionary) -> void:
	var weapons: Dictionary = people.get("weapons", {})
	var melee: Array = weapons.get("melee", [])
	var thrown: Array = weapons.get("thrown", [])
	var route: Array = pack.route
	var child := i >= size - kids
	var thrower := not child and i > 0 and not thrown.is_empty() and _rng.randf() < float(weapons.get("thrower_share", 0.4))
	var w: Dictionary = (thrown[_rng.randi() % thrown.size()] if thrower else (melee[_rng.randi() % melee.size()] if not melee.is_empty() else {}))
	if i == 0 and not melee.is_empty():
		w = melee[0]                    # the chief: melee only, the first melee weapon (the club)
	var keeper := i > 0 and i >= size - int(pack.keepers)
	var camp: NativeCamp = pack.camp
	var at: Vector3
	if camp != null:
		at = camp.spots[i % camp.spots.size()]       # everyone starts at the camp, by the fire
	else:
		at = _on_ground(route[0] + _ring_offset(i, route[0]))
	var npc := _make_member(pack, i == 0, child, thrower, w, style, at)
	(pack.root as Node3D).add_child(npc)
	(pack.members as Array).append({ "npc": npc, "child": child, "thrower": thrower, "weapon": w, "cd": _rng.randf_range(0.0, 1.0),
		"slot": i, "keeper": keeper })
	npc.died.connect(_on_member_died.bind(pack, npc))
	npc.hit_by.connect(_on_member_hit.bind(pack))


func _style(id: String, index: int) -> Dictionary:
	var styles: Array = people.get("styles", [])
	for s in styles:
		if str(s.get("id", "")) == id:
			return s
	return styles[index % styles.size()] if not styles.is_empty() else {}


func _ring_offset(i: int, at: Vector3) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	var up := up_at(at)
	var a := TAU * float(i) / 7.0
	var r := 2.0 + float(i / 7) * 2.2
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	return side * cos(a) * r + fwd * sin(a) * r


## One member: the guards' body from the people's soldier block, in the pack's
## colours (the leader in the helmet), a child at child_scale, and what it fights
## with in its hand.
func _make_member(pack: Dictionary, leader: bool, child: bool, thrower: bool, w: Dictionary, style: Dictionary, at: Vector3) -> NpcBody:
	var body: Dictionary = people.get("body", {})
	var soldier: Dictionary = (people.get("soldier", {}) as Dictionary).duplicate(true)
	soldier["id"] = "native_" + str(natives.get("people", {}).get("id", "people"))
	soldier["archetype"] = str(body.get("archetype", "desert_nomad"))
	soldier["outfit"] = { "head": str(style.get("leader_head" if leader else "head", "")), "torso": str(style.get("torso", "")),
		"legs": str(style.get("legs", "")) }
	for k in soldier.outfit.keys():
		if soldier.outfit[k] == "":
			soldier.outfit.erase(k)
	if child:
		soldier["look_scale"] = float(body.get("child_scale", 0.6))
		soldier["hp"] = int(round(float(soldier.get("hp", 44)) * float(body.get("child_hp", 0.5))))
	# The body's weapon: a throw for a thrower; melee members carry the same unused
	# so the body has one. The throws are paced by _fight (cooldown_s and the
	# throw's wind-up), so the weapon itself never makes one wait.
	var tw: Dictionary = w if thrower else (people.get("weapons", {}).get("thrown", [{}]) as Array)[0]
	soldier["weapon"] = { "base": "pistol_blaster", "damage": float(tw.get("damage", 7)), "bolt_speed": float(tw.get("speed", 22.0)),
		"rate": 0.1, "range": float(tw.get("range", 16.0)), "mag": 999,
		"reload_time": 0.1, "noise_radius": 18.0, "bolt_color": str(tw.get("color", "#8a6a3a")),
		"bolt_matte": bool(tw.get("matte", false)), "bolt_length": float(tw.get("length", 0.9)),
		"bolt_radius": float(tw.get("radius", 0.035)), "sfx": str(tw.get("sfx", "")) }
	var npc := NpcBody.new()
	npc.post_id = "%s_%d" % [str(pack.id), (pack.members as Array).size()]
	npc.setup(soldier, at, _rng.randf() * TAU, demo._flat_mats() if demo.use_look else null)
	npc.free_walk = true
	npc.nav = null
	npc.bolt_parent = demo
	npc.target = player
	npc.target_armed = func(): return demo.player_kit != null and demo.player_kit.weapons.holder.current != ""
	npc.target_crouched = func(): return false
	if demo.use_look:
		_hand_weapon(npc, w, thrower, child)
		if leader:
			_standard(npc, body.get("standard", {}))
	return npc


## A club, a spear, a knife or a rock in the right hand (look only).
func _hand_weapon(npc: NpcBody, w: Dictionary, thrower: bool, child: bool) -> void:
	var joint = npc.joints.get("r_wrist") if npc.joints is Dictionary else null
	if not (joint is Node3D):
		return
	var mats: LookMaterials = demo._flat_mats()
	var wood := mats.flat(Color("#6a4a2a"), 0.95)
	var bone := mats.flat(Color("#d8ccb0"), 0.8)
	var look := str(w.get("look", "rock" if thrower else "club"))
	var mi := MeshInstance3D.new()
	mi.name = "HandWeapon"
	if look == "rock":
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.11
		s.radial_segments = 6
		s.rings = 3
		mi.mesh = s
		mi.material_override = mats.flat(Color(str(w.get("color", "#1a1714"))), 1.0)
		mi.position = Vector3(0, -0.08, 0.02)
		(joint as Node3D).add_child(mi)
		return
	var c := CylinderMesh.new()
	match look:
		"spear":
			c.top_radius = 0.025
			c.bottom_radius = 0.03
			c.height = 1.9
		"knife":
			c.top_radius = 0.01
			c.bottom_radius = 0.03
			c.height = 0.35
		_:
			c.top_radius = 0.07
			c.bottom_radius = 0.035
			c.height = 0.75
	mi.mesh = c
	mi.material_override = bone if look == "knife" else wood
	mi.rotation_degrees = Vector3(80, 0, 0)
	(joint as Node3D).add_child(mi)


## The leader's pole: tall, with a rag on top, seen from far off.
func _standard(npc: NpcBody, cfg: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var h := float(cfg.get("height", 4.2))
	var pole := MeshInstance3D.new()
	pole.name = "Standard"
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.04
	c.height = h
	pole.mesh = c
	pole.material_override = mats.flat(Color("#5a3e24"), 0.95)
	pole.position = Vector3(0.45, h * 0.5, 0.1)
	npc.add_child(pole)
	var rag := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.04, 0.7, 0.9)
	rag.mesh = b
	rag.material_override = mats.cloth(Color(str(cfg.get("cloth", "#b8762e"))))
	rag.position = Vector3(0.45, h - 0.45, 0.55)
	npc.add_child(rag)


func alive(pack: Dictionary) -> Array:
	return (pack.members as Array).filter(func(m): return is_instance_valid(m.npc) and not m.npc.dead)


func pack(id: String) -> Dictionary:
	for p in packs:
		if p.id == id:
			return p
	return {}


## Whoever leads now: the chief, or the first one still standing (a keeper only
## when nobody else is left).
func leader(pack: Dictionary) -> NpcBody:
	var a := alive(pack)
	for m in a:
		if not bool(m.get("keeper", false)):
			return m.npc
	return a[0].npc if not a.is_empty() else null


func _lead_entry(p: Dictionary, a: Array) -> Dictionary:
	for m in a:
		if not bool(m.get("keeper", false)):
			return m
	return a[0]


# ------------------------------------------------------------------ time of day

## The hour now (0..24) from the look's time of day; -1 with no look (headless).
func hour_now() -> float:
	var look = demo.get("look") if demo != null else null
	if look == null:
		return -1.0
	if float(look.hour) >= 0.0:
		return float(look.hour)
	return float(look.hour_of(str(look.current)))


## Night: they come into camp and stay by the fire until morning.
func is_night() -> bool:
	var h := hour_now()
	if h < 0.0:
		return false
	var c := _camp_cfg()
	return h >= float(c.get("night_from", 19.0)) or h < float(c.get("night_to", 6.5))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_clock += dt
	WorldState.game_hours += dt * float(_camp_cfg().get("game_hours_per_real_min", 0.5)) / 60.0
	var ppos := _player_pos()
	if net_copy():
		_net_tick(dt, ppos)
		return
	var timer_text := ""
	for p in packs:
		if not (p is Dictionary) or not p.has("members"):
			continue               # torn down (the scene is being freed)
		_tick_pack(p, dt, ppos)
		if p.state == "attack" and timer_text == "":
			var left := maxf(0.0, survive_s - float(p.attack_t))
			timer_text = _line("survive") % [int(left) / 60, int(left) % 60] if not bool(p.rec.locked) else ""
	_timer_label.text = timer_text
	_timer_label.visible = timer_text != ""
	for c in camps:
		if is_instance_valid(c):
			(c as NativeCamp).tick(dt, ppos)
	_camp_check -= dt
	if _camp_check <= 0.0:
		_camp_check = 2.0
		_check_camps(ppos)
	_tick_prompts()


## Issue #402: a guest's copies: the camps' fires and lids, the prompts; nobody walks
## or fights here (NetWorld moves them).
func _net_tick(dt: float, ppos: Vector3) -> void:
	_timer_label.visible = false
	for pig in pigs:
		if is_instance_valid(pig):
			(pig as SandPig).net_copy = true
	for npc in members():
		if not npc.has_meta("net_copy") and not npc.dead:
			net_slide(npc, npc.global_position)    # not the host's yet: held, not walking off
	for c in camps:
		if is_instance_valid(c):
			(c as NativeCamp).tick(dt, ppos)
	_camp_check -= dt
	if _camp_check <= 0.0:
		_camp_check = 2.0
		for p in packs:
			_refresh_lids(p)
	_tick_prompts()


## Whether this game's natives are copies of a LAN host's (issue #402).
func net_copy() -> bool:
	return demo != null and bool(demo.get("lan_shared"))


## Every pack member built, alive or dead.
func members() -> Array:
	var out: Array = []
	for p in packs:
		if p is Dictionary and p.has("members"):
			for m in p.members:
				if is_instance_valid(m.npc):
					out.append(m.npc)
	return out


## Issue #402: [pack id, slot] for a member (how a LAN host names it to a guest),
## or [] if it is none of theirs.
func net_key(npc: NpcBody) -> Array:
	for p in packs:
		for m in p.get("members", []):
			if m.npc == npc:
				return [str(p.id), int(m.slot)]
	return []


## Issue #402: the member at `slot` of pack `id` here (a guest's copy of the host's), or null.
func net_member(id: String, slot: int) -> NpcBody:
	for m in pack(id).get("members", []):
		if int(m.slot) == slot and is_instance_valid(m.npc):
			return m.npc
	return null


## Issue #402: a member this game has that the host's does not (killed there): gone.
func net_drop(npc: NpcBody) -> void:
	for p in packs:
		var list: Array = p.get("members", [])
		for m in list.duplicate():
			if m.npc == npc:
				list.erase(m)
	npc.queue_free()


## Issue #402: a guest's copy far from this game's player (or with no collider under
## it) is slid to `at` along the ground with no physics, as the host slides its own
## (true); near, it walks (false: NetWorld drives it).
func net_slide(npc: NpcBody, at: Vector3) -> bool:
	var ppos := _player_pos()
	var lod := float(people.get("pack", {}).get("far_lod_m", 90.0))
	if ppos != Vector3.INF and at.distance_to(ppos) <= lod and _has_floor(at):
		if npc.process_mode == Node.PROCESS_MODE_DISABLED:
			npc.process_mode = Node.PROCESS_MODE_INHERIT
			npc.global_position = _on_ground(at)
		_keep_up(npc)
		return false
	npc.process_mode = Node.PROCESS_MODE_DISABLED
	var g := _on_ground(at)
	npc.global_position = g
	npc.velocity = Vector3.ZERO
	if "controller" in npc and npc.controller != null:
		npc.controller.velocity = Vector3.ZERO
		npc.controller.body_pos = g
	return true


## How pack `p` takes you: the host's word in a LAN guest's game, else its record.
func is_friendly(p: Dictionary) -> bool:
	return bool(p.get("net_friendly", p.rec.friendly))


## A LAN guest's shot (their body in the host's game) counts as the player's against
## a pack: the pack is the same in every game (issue #402).
static func _by_guest(shooter) -> bool:
	return shooter != null and is_instance_valid(shooter) and shooter.get("peer_id") != null


func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		return Vector3.INF
	if bool(player.get("piloting")):
		var v = player.get("vehicle")
		if v is SpeederNode:
			return (v as SpeederNode).model.position        # they chase a speeder on foot
		return Vector3.INF
	return player.global_position


func _tick_pack(p: Dictionary, dt: float, ppos: Vector3) -> void:
	var a := alive(p)
	if a.is_empty():
		return
	var lead: NpcBody = _lead_entry(p, a).npc
	p.center = lead.global_position
	var d := lead.global_position.distance_to(ppos) if ppos != Vector3.INF else INF
	var near_d := INF                  # the nearest of them (a keeper by its fire counts)
	var noticed := false
	for m in a:
		noticed = noticed or (m.npc as NpcBody).perception.noticed
		if ppos != Vector3.INF:
			near_d = minf(near_d, (m.npc as NpcBody).global_position.distance_to(ppos))
	var pk: Dictionary = people.get("pack", {})
	var rec: Dictionary = p.rec
	p.gesture_t = maxf(0.0, float(p.gesture_t) - dt)
	match str(p.state):
		"travel", "greet", "camp":
			if not bool(rec.friendly):
				if ppos != Vector3.INF and (noticed or near_d < float(pk.get("notice_range", 45.0))):
					start_attack(p)
			elif ppos != Vector3.INF and d < float(pk.get("greet_range", 30.0)) and not resting:
				if p.state != "greet":
					p.home_state = p.state
					p.state = "greet"
					p.gesture_t = 0.0
					lead.act("gesture_wave")
				elif p.gesture_t <= 0.0 and d < float(pk.get("trade_reach", 4.5)) * 1.5:
					p.gesture_t = float(pk.get("offer_every_s", 7.0))
					lead.act("gesture_offer")
					lead.say(str(people.get("voice", {}).get("gesture_offer", "")), 3.0)
			elif p.state == "greet" and (d > float(pk.get("greet_range", 30.0)) * 1.6 or resting):
				p.state = p.home_state
			if p.state == "camp":
				p.camp_t = float(p.camp_t) - dt
				if p.camp_t <= 0.0 and not is_night():
					p.state = "travel"
					p.route_i = (int(p.camp_i) + 1) % (p.route as Array).size()
			elif p.state == "travel" and p.camp != null and is_night():
				p.route_i = p.camp_i      # home for the night
		"truce":
			if d > float(pk.get("greet_range", 30.0)) * 1.6:
				p.state = "travel"
		"attack":
			if ppos == Vector3.INF:
				_stand_down(p)               # downed (or flown off): back to their route
			elif near_d > float(people.get("hostile", {}).get("chase_leash_m", 160.0)):
				_stand_down(p)
			else:
				p.attack_t = float(p.attack_t) + dt
				if not bool(rec.locked) and int(rec.get("kills", 0)) == 0 and float(p.attack_t) >= survive_s:
					_win_over(p)
	for m in a:
		_tick_member(p, m, dt, ppos)


func _tick_member(p: Dictionary, m: Dictionary, dt: float, ppos: Vector3) -> void:
	var npc: NpcBody = m.npc
	var lod := float(people.get("pack", {}).get("far_lod_m", 90.0))
	# Physics only where the sand's collider is under them: it follows the player
	# and can lag tens of metres behind on the way in (they fell through it).
	var far := ppos == Vector3.INF or npc.global_position.distance_to(ppos) > lod \
			or not _has_floor(npc.global_position)
	if far:
		# Out of sight of the player: slid along the ground, no physics (there may
		# be no collider under them out here).
		if npc.process_mode != Node.PROCESS_MODE_DISABLED:
			npc.process_mode = Node.PROCESS_MODE_DISABLED
		# Nobody is looking: step at a fraction of the tick rate, each member on its
		# own tick (by slot), with the time of the ticks in between so the speed and
		# the route progress are the same as stepping every tick.
		var acc := float(m.get("far_acc", 0.0)) + dt
		var n := int(m.get("far_n", 0)) + 1
		m["far_acc"] = acc
		m["far_n"] = n
		if far_stride > 1 and (n + int(m.slot)) % far_stride != 0:
			return
		m["far_acc"] = 0.0
		dt = acc
		var far_goal := _goal_for(p, m, ppos)
		var speed := float(people.get("pack", {}).get("travel_speed", 1.6))
		if p.state == "attack" and far_goal == ppos:
			speed = float(people.get("pack", {}).get("charge_speed", 4.5))     # coming for you
		if steer != null:
			far_goal = steer.steer(npc.global_position, far_goal, up_at(npc.global_position))
		var to := far_goal - npc.global_position
		var step := to.normalized() * minf(speed * dt, to.length()) if to.length() > 0.5 else Vector3.ZERO
		var at := _on_ground(npc.global_position + step)
		npc.global_position = at
		npc.velocity = Vector3.ZERO
		if "controller" in npc and npc.controller != null:
			npc.controller.velocity = Vector3.ZERO
			npc.controller.body_pos = at
		return
	m["far_acc"] = 0.0
	var goal := _goal_for(p, m, ppos)
	if npc.process_mode == Node.PROCESS_MODE_DISABLED:
		npc.process_mode = Node.PROCESS_MODE_INHERIT
	_keep_up(npc)
	npc.command.crouch = false
	match str(p.state):
		"attack":
			if goal == ppos:
				_fight(p, m, dt, ppos)
			else:
				_walk_to(m, goal)         # a keeper staying by its camp
		"greet", "truce":
			if m.npc == leader(p) and ppos != Vector3.INF:
				var to_p := ppos - npc.global_position
				npc.go_to(ppos - to_p.normalized() * 2.6, false)
				npc.face_point(ppos)
			elif bool(m.get("keeper", false)) and p.camp != null:
				_sit_at(p, m, goal)
			else:
				npc.stop()
				if ppos != Vector3.INF:
					npc.face_point(ppos)
		"camp":
			_sit_at(p, m, goal)
		_:
			if bool(m.get("keeper", false)) and p.camp != null:
				_sit_at(p, m, goal)
			else:
				_walk_to(m, goal)
				npc.clear_face()


## Whether the ground under `p` has a collider to stand on (always, with no
## streaming terrain).
func _has_floor(p: Vector3) -> bool:
	var t = demo.terrain if demo != null else null
	if t == null or not t.has_method("collider_covers"):
		return true
	return t.collider_covers(p.x, p.z, 3.0)


## A member found under the sand (a collider swapped out beneath it) is put back
## on top, not left falling.
func _keep_up(npc: NpcBody) -> void:
	var g := _on_ground(npc.global_position)
	if (npc.global_position - g).dot(up_at(g)) < -0.4:
		npc.global_position = g + up_at(g) * 0.05
		npc.velocity = Vector3.ZERO


## Walk to `goal` round the rocks in the way (asked again every few tenths of a second).
func _walk_to(m: Dictionary, goal: Vector3) -> void:
	var npc: NpcBody = m.npc
	var to := goal
	if steer != null and steer.count > 0:
		if _clock - float(m.get("st", -1.0)) > 0.3 or (m.get("sgoal", Vector3.INF) as Vector3).distance_to(goal) > 3.0:
			m["sg"] = steer.steer(npc.global_position, goal, up_at(npc.global_position))
			m["st"] = _clock
			m["sgoal"] = goal
		to = m.sg
	npc.go_to(to, false)


## At the camp: walk to its spot by the fire, then sit (crouch) facing it.
func _sit_at(p: Dictionary, m: Dictionary, spot: Vector3) -> void:
	var npc: NpcBody = m.npc
	var camp: NativeCamp = p.camp
	if npc.global_position.distance_to(spot) > 1.2:
		_walk_to(m, spot)
		return
	npc.stop()
	npc.command.crouch = true
	if camp != null:
		npc.face_point(camp.center)


## Where a member walks: the leader along the route, the rest in rows behind it;
## at the camp each to its own spot by the fire. Fighting: at you (a keeper only
## near its camp).
func _goal_for(p: Dictionary, m: Dictionary, ppos: Vector3) -> Vector3:
	var camp: NativeCamp = p.camp
	var keeper := bool(m.get("keeper", false)) and camp != null
	if p.state == "attack" and ppos != Vector3.INF:
		if keeper and ppos.distance_to(camp.center) > float(_camp_cfg().get("guard_m", 60.0)):
			return _spot(p, m)
		return ppos
	if keeper or (p.state == "camp" and camp != null):
		return _spot(p, m)
	var route: Array = p.route
	var lead: NpcBody = leader(p)
	if m.npc == lead:
		var target: Vector3 = route[int(p.route_i)]
		if p.state == "travel" and lead.global_position.distance_to(target) < 4.0:
			if int(p.route_i) == int(p.camp_i) and camp != null:
				_arrive_at_camp(p)
				return _spot(p, m)
			p.route_i = (int(p.route_i) + 1) % route.size()
			target = route[int(p.route_i)]
		var up := up_at(lead.global_position)
		var h := target - lead.global_position
		h -= up * h.dot(up)
		if h.length() > 0.1:
			p.heading = h.normalized()
		return target
	var up2 := up_at(lead.global_position)
	var fwd: Vector3 = p.heading
	var right := fwd.cross(up2).normalized()
	var i := int(m.slot) - 1
	var row := i / 4 + 1
	var col := float(i % 4) - 1.5
	var sp := float(people.get("pack", {}).get("spacing", 2.6))
	return lead.global_position - fwd * float(row) * sp + right * col * sp


func _spot(p: Dictionary, m: Dictionary) -> Vector3:
	var camp: NativeCamp = p.camp
	return camp.spots[int(m.slot) % camp.spots.size()]


func _arrive_at_camp(p: Dictionary) -> void:
	p.state = "camp"
	p.camp_t = float((p.camp as NativeCamp).cfg.get("stop_s", 45.0))


## Hostile: run at the player; swing within reach, throw a rock from range. The
## blow lands (or the rock leaves the hand) partway through the move.
func _fight(p: Dictionary, m: Dictionary, dt: float, ppos: Vector3) -> void:
	var npc: NpcBody = m.npc
	var w: Dictionary = m.weapon
	m.cd = maxf(0.0, float(m.cd) - dt)
	var d := npc.global_position.distance_to(ppos)
	npc.face_point(ppos)
	var chest := ppos + up_at(ppos) * 1.2
	if float(m.get("release", -1.0)) >= 0.0:      # a rock on its way out of the hand
		npc.stop()
		npc.aim_point = chest
		m.release = float(m.release) - dt
		if m.release <= 0.0 and npc.fire_at(chest, dt):
			m.release = -1.0
		elif m.release < -0.6:
			m.release = -1.0              # the throw came to nothing
		return
	if float(m.get("strike", -1.0)) >= 0.0:       # a swing on its way down
		npc.stop()
		m.strike = float(m.strike) - dt
		if m.strike <= 0.0:
			m.strike = -1.0
			if d <= float(w.get("reach", 2.0)) + 0.8:
				_land_blow(npc, w)
		return
	if bool(m.thrower) and d >= float(w.get("min_range", 5.0)) and d <= float(w.get("range", 16.0)):
		npc.stop()
		npc.aim_point = chest
		if m.cd <= 0.0:
			m.cd = float(w.get("cooldown_s", 3.2))
			npc.act("throw")
			m.release = NativeMoves.length("throw") * NativeMoves.RELEASE
		return
	npc.aim_point = Vector3.INF
	var reach := float(w.get("reach", 2.0))
	if d <= reach:
		npc.stop()
		if m.cd <= 0.0:
			m.cd = float(w.get("cooldown_s", 1.1))
			var move := str(w.get("move", "swing"))
			npc.act(move)
			m.strike = NativeMoves.length(move) * float(NativeMoves.STRIKE.get(move, 0.5))
		return
	_walk_to(m, ppos)
	npc.command.sprint = true
	if _rng.randf() < dt * 0.15:
		_yell(npc)


func _land_blow(npc: NpcBody, w: Dictionary) -> void:
	if player != null and player.has_method("apply_damage_from"):
		player.apply_damage_from(float(w.get("damage", 8)), npc)
	elif player != null and player.has_method("apply_damage"):
		player.apply_damage(float(w.get("damage", 8)))
	hits += 1


var hits := 0                         ## melee blows that landed (traces)
var horns := 0


## A hostile pack sees you: the horn (only to start an attack), yells, and in.
func start_attack(p: Dictionary) -> void:
	if p.state == "attack":
		return
	p.state = "attack"
	p.attack_t = 0.0
	var lead := leader(p)
	if lead == null:
		return
	horns += 1
	_horn(lead)
	for m in alive(p):
		(m.npc as NpcBody).perception.awareness = 1.0
		(m.npc as NpcBody).perception.noticed = true
		(m.npc as NpcBody).hostile = true
	_yell(lead)
	_toast(_line("horn") % str(p.label))


func _stand_down(p: Dictionary) -> void:
	p.state = "travel"
	p.attack_t = 0.0
	for m in alive(p):
		(m.npc as NpcBody).hostile = false
		(m.npc as NpcBody).aim_point = Vector3.INF
		m.erase("release")
		m.erase("strike")


## Five minutes and nobody of theirs dead: they lower their weapons, and trade.
func _win_over(p: Dictionary) -> void:
	p.rec.friendly = true
	p.rec.won = true
	p.state = "truce"
	for m in alive(p):
		(m.npc as NpcBody).hostile = false
		(m.npc as NpcBody).aim_point = Vector3.INF
		(m.npc as NpcBody).stop()
		(m.npc as NpcBody).act("gesture_lower")
		m.erase("release")
		m.erase("strike")
	var lead := leader(p)
	var g = people.get("voice", {}).get("gesture_truce", "")
	if lead != null:
		lead.act("gesture_offer")
		if str(g) != "":
			lead.say(str(g), 4.0)
	_toast(_line("won") % str(p.label))
	pack_won.emit(str(p.id))


func _on_member_hit(shooter: Node, _amount: float, p: Dictionary) -> void:
	if not DroidController.by_player(shooter, player) and not _by_guest(shooter):
		return
	if bool(p.rec.friendly) and not bool(p.rec.get("won", false)):
		p.rec.friendly = false            # you started it
	elif bool(p.rec.get("won", false)):
		p.rec.friendly = false
		p.rec.won = false
	start_attack(p)


func _on_member_died(p: Dictionary, npc: NpcBody) -> void:
	if net_copy():
		return                            # the host's pack keeps the count
	var by = npc.last_hit_by
	if not DroidController.by_player(by, player) and not _by_guest(by) and not (by == null and npc.has_meta("net_hit_by")):
		return
	p.rec.kills = int(p.rec.get("kills", 0)) + 1
	p.rec.friendly = false
	p.rec.won = false
	if not bool(p.rec.locked):
		p.rec.locked = true
		_toast(_line("locked") % str(p.label))
		pack_locked.emit(str(p.id))
	start_attack(p)


## A friendly pack caught you at it (stealing, or tearing its tents down): it turns
## on you. Not for good: survive them without a kill and they come round again.
func _provoke(p: Dictionary) -> void:
	if net_provoke.is_valid():
		net_provoke.call(str(p.id))      # a guest: the host's pack turns
		return
	if bool(p.rec.friendly):
		p.rec.friendly = false
		p.rec.won = false
	start_attack(p)


## Whether any of pack `p` sees the player right now.
func seen_by(p: Dictionary) -> bool:
	for m in alive(p):
		if (m.npc as NpcBody).perception.visible:
			return true
	return false


func _horn(at: Node3D) -> void:
	var path := str(people.get("hostile", {}).get("horn", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = load(path)
	a.unit_size = 40.0
	a.max_distance = 600.0
	a.volume_db = -2.0
	at.add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _yell(npc: NpcBody) -> void:
	var y := _voice("yells")
	if not y.is_empty():
		npc.say(str(y[_rng.randi() % y.size()]), 1.6, true)


# ------------------------------------------------------------------ trade

## The friendly pack whose leader is within reach of the player, or {}.
func trade_pack() -> Dictionary:
	var ppos := _player_pos()
	if ppos == Vector3.INF or bool(player.get("piloting")):
		return {}
	var reach := float(people.get("pack", {}).get("trade_reach", 4.5))
	for p in packs:
		if not is_friendly(p) or not (p.state in ["greet", "truce", "travel", "camp"]):
			continue
		var lead := leader(p)
		if lead != null and lead.global_position.distance_to(ppos) <= reach:
			return p
	return {}


## Issue #211: E at a friendly pack's leader: food for quartz as ever, or any of
## their goods (whatever the town's vendors sell) for meat. A trade leaves the
## menu open (Esc walks away); keep_cursor holds the cursor where it was.
func open_trade(p: Dictionary, keep_cursor := false) -> void:
	if menu == null:
		menu = DroidMenu.new()
		add_child(menu)
	var opts: Array = [{ "id": "quartz", "text": _line("trade_quartz") }]
	var cc = gear.content if gear != null else null
	for g in goods():
		var label: String = str(cc.get_item(str(g.item)).get("label", g.item)) if cc != null else str(g.item)
		opts.append({ "id": str(g.item), "text": _line("trade_goods") % [int(g.food), label] })
	var lock: bool = player != null and not bool(player.get("locked"))
	if lock:
		player.locked = true
	var pick := func(id: String) -> void:
		if lock:
			player.locked = false
		if id == "":
			return
		if id == "quartz":
			trade(str(p.id))
		else:
			trade_goods(str(p.id), id)
		if is_friendly(p):
			open_trade(p, true)
	menu.open(_line("trade_menu") % [str(p.label), WorldState.inventory.count("food")], opts, pick, "", keep_cursor)


## The goods a pack trades for meat: [{ item, food }].
func goods() -> Array:
	return people.get("trade", {}).get("goods", [])


## Pack `id` trades `item` for its price in food. "traded", "no_food", "hostile",
## "none" or "" (not something they trade).
func trade_goods(id: String, item: String) -> String:
	var p := pack(id)
	if p.is_empty():
		return "none"
	if not is_friendly(p):
		return "hostile"
	var price := -1
	for g in goods():
		if str(g.item) == item:
			price = int(g.food)
	if price < 0:
		return ""
	if WorldState.inventory.count("food") >= price and not WorldState.inventory.room_after_paying(item, "food", price):
		_toast(Inventory.full_line())
		return "full"
	if not swap_food(item, price):
		_toast(_line("prompt_no_food"))
		return "no_food"
	p.rec.trades = int(p.rec.get("trades", 0)) + 1
	trades += 1
	var cc = gear.content if gear != null else null
	var label: String = str(cc.get_item(item).get("label", item)) if cc != null else item
	_toast(_line("traded_goods") % [price, label, str(p.label)])
	WorldState.log_event("Traded %d sand pig for a %s with the %s." % [price, label.to_lower(), str(p.label)])
	Story.event("nomad_traded")
	return "traded"


## Pay `price` food for one `item`. False (nothing taken) without enough food.
static func swap_food(item: String, price: int) -> bool:
	if WorldState.inventory.count("food") < price:
		return false
	WorldState.inventory.remove("food", price)
	WorldState.inventory.add(item)
	return true


## Gesture back at pack `id`: one food for its quartz. "traded", "no_food",
## "hostile" or "none".
func trade(id: String) -> String:
	var p := pack(id)
	if p.is_empty():
		return "none"
	if not is_friendly(p):
		return "hostile"
	var inv := WorldState.inventory
	var tcfg: Dictionary = people.get("trade", {})
	var wants: Array = tcfg.get("wants", ["food"])
	var food := ""
	for w in wants:
		if inv.has(str(w)):
			food = str(w)
	var lead := leader(p)
	if food == "":
		if lead != null:
			lead.act("gesture_no")
			lead.say(str(people.get("voice", {}).get("gesture_no_food", "")), 3.5)
		return "no_food"
	if not inv.room_after_paying(str(tcfg.get("gives", "quartz")), food, 1):
		_toast(Inventory.full_line())
		return "full"
	inv.remove(food)
	Story.event("nomad_traded")          # issue #211: the quest is any trade
	var n := int(tcfg.get("per_food", 1)) + (int(tcfg.get("adults_only_bonus", 1)) if bool(p.adults_only) else 0)
	inv.add(str(tcfg.get("gives", "quartz")), n)
	p.rec.rep = int(p.rec.get("rep", 0)) + int(tcfg.get("reputation_per_trade", 1))
	p.rec.trades = int(p.rec.get("trades", 0)) + 1
	trades += 1
	if lead != null:
		lead.act("gesture_thanks")
		lead.say(str(people.get("voice", {}).get("gesture_thanks", "")), 3.5)
		p.gesture_t = float(people.get("pack", {}).get("offer_every_s", 7.0))
	_toast(_line("traded") % [n, str(p.label), int(p.rec.rep)])
	WorldState.log_event("Traded sand pig for quartz with the %s." % str(p.label))
	traded.emit(id, n)
	return "traded"


# ------------------------------------------------------------------ camps: chests, tents, rest

func _box_key(i: int) -> String:
	return "tent_%d" % i


## Whether tent `i`'s chest in pack `p`'s camp has something in it (it fills again
## restock_hours after it was emptied).
func chest_full(p: Dictionary, i: int) -> bool:
	var st := WorldState.native_camp(str(p.id))
	var looted: Dictionary = st.get("looted", {})
	if not looted.has(_box_key(i)):
		return true
	return WorldState.game_hours - float(looted[_box_key(i)]) >= float((p.camp as NativeCamp).cfg.get("restock_hours", 4.0))


## What is in tent `i`'s chest: { item id: count }, rolled from the people's loot
## table (the same chest always holds the same thing until it is emptied).
func chest_items(p: Dictionary, i: int) -> Dictionary:
	if p.camp == null or not chest_full(p, i):
		return {}
	var cfg: Dictionary = (p.camp as NativeCamp).cfg
	var table: Array = cfg.get("loot", [])
	if table.is_empty():
		return {}
	var st := WorldState.native_camp(str(p.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%d/%d" % [str(p.id), i, int(st.get("fills", {}).get(_box_key(i), 0))])
	var total := 0.0
	for e in table:
		total += float(e.get("weight", 1.0))
	var out := {}
	for k in int(cfg.get("loot_rolls", 2)):
		var r := rng.randf() * total
		for e in table:
			r -= float(e.get("weight", 1.0))
			if r <= 0.0:
				var c: Array = e.get("count", [1, 1])
				var item := str(e.item)
				out[item] = int(out.get(item, 0)) + rng.randi_range(int(c[0]), int(c[1]))
				break
	return out


## The camp chest within reach of the player: { pack, tent } or {}.
func chest_near_player() -> Dictionary:
	var ppos := _player_pos()
	if ppos == Vector3.INF or bool(player.get("piloting")):
		return {}
	for p in packs:
		if p.camp == null:
			continue
		var i := (p.camp as NativeCamp).chest_near(ppos)
		if i >= 0:
			return { "pack": p, "tent": i }
	return {}


## Take what is in tent `i`'s chest. If any of the pack sees it, a friendly pack
## turns on you (a hostile one is coming anyway). Returns what was taken.
func take_chest(p: Dictionary, i: int) -> Dictionary:
	var items := chest_items(p, i)
	if items.is_empty():
		return {}
	if not WorldState.inventory.room_for_all(items):
		_toast(Inventory.full_line())
		return {}
	for k in items:
		WorldState.inventory.add(str(k), int(items[k]))
	var st := WorldState.native_camp(str(p.id))
	st.looted[_box_key(i)] = WorldState.game_hours
	if not st.has("fills"):
		st["fills"] = {}
	st.fills[_box_key(i)] = int(st.fills.get(_box_key(i), 0)) + 1
	(p.camp as NativeCamp).set_lid(i, true)
	steals += 1
	var seen := seen_by(p)
	var parts: Array = []
	for k in items:
		parts.append("%d %s" % [int(items[k]), _item_label(str(k))])
	_toast(_line("took") % ", ".join(parts))
	WorldState.log_event("Took %s from a tent of the %s." % [", ".join(parts), str(p.label)])
	if seen:
		_toast(_line("seen_stealing") % str(p.label))
		_provoke(p)
	looted.emit(str(p.id), items, seen)
	return items


func _item_label(id: String) -> String:
	var it := WorldState._item(id)
	return str(it.get("label", id)).to_lower() if not it.is_empty() else id


func _refresh_lids(p: Dictionary) -> void:
	var camp: NativeCamp = p.camp
	if camp == null:
		return
	for t in camp.tents:
		camp.set_lid(int(t.index), not chest_full(p, int(t.index)))


func _on_tent_hit(shooter: Node, _amount: float, p: Dictionary) -> void:
	if shooter == player and seen_by(p):
		_provoke(p)


func _on_camp_wrecked(p: Dictionary) -> void:
	if not net_copy():                    # a guest's: the host's camp keeps the hours
		WorldState.native_camp(str(p.id)).wrecked_h = WorldState.game_hours
	_toast(_line("camp_wrecked") % str(p.label))
	WorldState.log_event("The %s's camp was torn down." % str(p.label))


## Every couple of seconds: a wrecked camp whose hours are up is put back (only
## while the player is not standing in it), and emptied chests fill again.
func _check_camps(ppos: Vector3) -> void:
	for p in packs:
		var camp: NativeCamp = p.get("camp")
		if camp == null:
			continue
		if camp.is_wrecked:
			var st := WorldState.native_camp(str(p.id))
			var away := ppos == Vector3.INF or ppos.distance_to(camp.center) > float(camp.cfg.get("rebuild_unseen_m", 60.0))
			if away and WorldState.game_hours - float(st.get("wrecked_h", -1.0)) >= float(camp.cfg.get("return_hours", 4.0)):
				st.wrecked_h = -1.0
				camp.rebuild()
		_refresh_lids(p)


## The friendly pack's standing tent the player is inside: { pack, tent } or {}.
func rest_tent() -> Dictionary:
	var ppos := _player_pos()
	if ppos == Vector3.INF or bool(player.get("piloting")):
		return {}
	for p in packs:
		if p.camp == null or not is_friendly(p) or p.state == "attack":
			continue
		var i := (p.camp as NativeCamp).tent_at(ppos)
		if i >= 0 and not bool((p.camp as NativeCamp).tents[i].down):
			return { "pack": p, "tent": i }
	return {}


## Sleep in a friendly tent: the screen goes dark, you heal, it is morning, the game
## is saved, the screen comes back. `fade_s` 0 does it all at once (traces).
func rest(fade_s: float = -1.0) -> bool:
	if resting or rest_tent().is_empty():
		return false
	resting = true
	var rc: Dictionary = people.get("rest", {})
	if fade_s < 0.0:
		fade_s = float(rc.get("fade_s", 0.9))
	if player != null and "locked" in player:
		player.locked = true
	_fade.visible = true
	if fade_s > 0.0 and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, fade_s)
		await tw.finished
		await get_tree().create_timer(float(rc.get("dark_s", 0.8))).timeout
	_fade.color.a = 1.0
	_wake(rc)
	if fade_s > 0.0 and is_inside_tree():
		var tw2 := create_tween()
		tw2.tween_property(_fade, "color:a", 0.0, fade_s)
		await tw2.finished
	_fade.color.a = 0.0
	_fade.visible = false
	if player != null and "locked" in player:
		player.locked = false
	resting = false
	_toast(_line("rested"))
	rested.emit()
	return true


## In the dark: healed, the clock on to morning, saved.
func _wake(rc: Dictionary) -> void:
	if player != null and player.get("health") != null:
		player.health.heal(int(player.health.max_hp))
	var morning := float(rc.get("morning_hour", 8.0))
	var h := hour_now()
	var slept := fposmod(morning - h, 24.0) if h >= 0.0 else float(rc.get("hours_headless", 9.0))
	if slept < 0.5:
		slept += 24.0
	WorldState.game_hours += slept
	if demo != null and demo.has_method("set_hour") and demo.get("look") != null:
		demo.set_hour(morning)
	rests += 1
	WorldState.log_event("Slept in a tent of the desert people until morning.")
	for p in packs:
		_refresh_lids(p)
	var bar = demo.get("bar") if demo != null else null
	if bar != null and is_instance_valid(bar) and bar.has_method("_save_memory"):
		bar._save_memory()


func _tick_prompts() -> void:
	if gear == null or gear.hud == null or player == null or bool(player.get("locked")):
		return
	# [Z] rest rides along with whatever [E] does here (the leader follows you in).
	var rest_line := _line("prompt_rest") if not rest_tent().is_empty() else ""
	var tail := "      " + rest_line if rest_line != "" else ""
	if rest_line != "" and _just_rest():
		rest()
		return
	var tp := trade_pack()
	if not tp.is_empty():
		var n := WorldState.inventory.count("food")
		gear.hud.set_prompt((_line("prompt_trade") % n if n > 0 else _line("prompt_no_food")) + tail)
		if _just_interact():
			open_trade(tp)
		return
	var ch := chest_near_player()
	if not ch.is_empty():
		var full := not chest_items(ch.pack, int(ch.tent)).is_empty()
		gear.hud.set_prompt((_line("prompt_chest") if full else _line("prompt_chest_empty")) + tail)
		if full and _just_interact():
			take_chest(ch.pack, int(ch.tent))
		return
	if rest_line != "":
		gear.hud.set_prompt(rest_line)
		return
	var pig := carcass_near()
	if pig != null:
		gear.hud.set_prompt(_line("butcher") % str(pig.cfg.get("label", "animal")))
		if _just_interact():
			butcher(pig)


func _just_interact() -> bool:
	return InputMap.has_action("interact") and Input.is_action_just_pressed("interact")


func _just_rest() -> bool:
	return InputMap.has_action("rest") and Input.is_action_just_pressed("rest")


func _toast(text: String) -> void:
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast(text, 4.5)


# ------------------------------------------------------------------ animals

## One animal of fauna entry state.f (state keeps the count and tries between
## calls). True when one was placed (call again for the next), false when done.
func _fauna_step(state: Dictionary) -> bool:
	var f: Dictionary = state.f
	if not state.has("cfg"):
		state.cfg = NativesData.fauna(str(f.get("species", "")))
		state.around = f.get("around", Vector2.ZERO)
		state.r = float(f.get("radius", 900.0))
		state.site = demo.desert_site().walls.grow(60.0) if demo.has_method("desert_site") else Rect2()
		state.placed = 0
		state.tries = 0
	var cfg: Dictionary = state.cfg
	if cfg.is_empty():
		return false
	var around: Vector2 = state.around
	var r: float = state.r
	var site: Rect2 = state.site
	while int(state.placed) < int(f.get("count", 4)) and int(state.tries) < 200:
		state.tries = int(state.tries) + 1
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(r * 0.3, r)
		var m := around + Vector2(cos(a), sin(a)) * d
		if site.has_area() and site.has_point(m):
			continue
		var pig := SandPig.new()
		pig.setup(cfg, ground, surface(m), 1000 + int(state.placed), demo._flat_mats() if demo.use_look else null)
		pig.target = player
		add_child(pig)
		pig.killed.connect(func(_p): WorldState.bump("animals_killed"))
		pigs.append(pig)
		state.placed = int(state.placed) + 1
		if int(state.placed) < int(f.get("count", 4)) and int(state.tries) < 200:
			_build_queue.push_front(func(): return _fauna_step(state))
		return true
	return false


func carcass_near(reach: float = 2.8) -> SandPig:
	var ppos := _player_pos()
	if ppos == Vector3.INF or bool(player.get("piloting")):
		return null
	for pig in pigs:
		if is_instance_valid(pig) and pig.dead and not pig.butchered and pig.global_position.distance_to(ppos) <= reach:
			return pig
	return null


## Cut food from a dead animal into the player's pockets. Returns how many.
func butcher(pig: SandPig) -> int:
	if not WorldState.inventory.room_for(str(pig.cfg.get("food", {}).get("item", "food"))):
		_toast(Inventory.full_line())
		return 0
	var got := pig.butcher()
	if got.is_empty():
		return 0
	WorldState.inventory.add(str(got.item), int(got.count))
	butchered += 1
	_toast(_line("butchered") % [str(pig.cfg.get("label", "animal")), int(got.count)])
	return int(got.count)
