extends Node
## Issue #401: the one node LAN play's RPCs travel on, at /root/NetLink on every
## game in the session (NetSession puts it there), so its path is the same for all
## and it outlives the town reloading.
##
## Host: listens, lets guests in (hello -> welcome, or a refusal when full or on
## another version), keeps the roster and tells everyone who came and went. Every
## player sends their state (state) send_rate times a second; the host relays it
## (SceneMultiplayer's server relay). Each game puts a RemotePlayer in its town for
## every other player on the same planet.
##
## Tests: `local_state` (and `local_outfit`) replace reading the town's player, `with_bodies` false
## keeps bodies out, `arrive_on_welcome` false keeps a guest's town from reloading.

signal welcomed(planet_id: String)
signal refused(why: String)
signal player_joined(id: int, player_name: String)
signal player_left(id: int, player_name: String)
signal host_left
signal turned_away(id: int, why: String)     ## host: a guest refused (full, another version)

const RemotePlayer := preload("res://src/systems/net/remote_player.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")

## State packet flags.
const F_GROUNDED := 1
const F_CROUCH := 2
const F_SPRINT := 4
const F_VISIBLE := 8
const F_SLIDE := 16

var my_name := ""
var my_outfit: Dictionary = {}
var roster: Dictionary = {}        ## peer id -> { name, outfit } (the host is 1)
var states: Dictionary = {}        ## peer id -> the last state heard ({ planet, pos, yaw, ... , t })
var bodies: Dictionary = {}        ## peer id -> RemotePlayer in this town
var address := ""                  ## the host's (a guest), for the status line
var host_name := ""
var welcomed_in := false           ## a guest the host has let in
var local_state: Callable = Callable()
var local_outfit: Callable = Callable()   ## tests: replaces reading the town's avatar
var with_bodies := true
var arrive_on_welcome := true
var _max := 5
var _send_left := 0.0
var _wait_left := -1.0             ## a join's time left to hear from the host
var _kick: Dictionary = {}         ## peer id -> seconds until a refused guest is dropped
var _hooked: Object = null         ## the town's PlayerWeapons whose shots are being sent
var _fit_left := 0.0               ## seconds to the next look at what you wear
var outfits_heard := 0             ## the others' outfit changes heard (tests)
var hits_taken := 0                ## friendly fire landed on you (tests)
var shots_seen := 0                ## the others' bolts shown here (tests)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS       # the F11 panel pauses the game; the others still move


func _mp() -> MultiplayerAPI:
	return get_tree().get_multiplayer()


func start_host(port: int, max_players: int) -> Error:
	_max = max_players
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)   # one slot spare: one too many hears "full" instead of timing out
	if err != OK:
		return err
	_mp().multiplayer_peer = peer
	roster[1] = { "name": my_name, "outfit": my_outfit }
	host_name = my_name
	_mp().peer_disconnected.connect(_on_peer_gone)
	return OK


func start_guest(at: String, port: int) -> Error:
	address = at
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(at, port)
	if err != OK:
		return err
	_mp().multiplayer_peer = peer
	_mp().connected_to_server.connect(_on_connected)
	_mp().connection_failed.connect(_on_no_answer)
	_mp().server_disconnected.connect(_on_host_gone)
	_mp().peer_disconnected.connect(_on_peer_gone)
	_wait_left = NetSession.n("connect_timeout", 6.0)
	return OK


## Leave: the connection closes (the others hear it at once) and the bodies go.
func close() -> void:
	var peer := _mp().multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	_mp().multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in bodies.keys():
		_drop_body(id)
	roster.clear()
	states.clear()


func _exit_tree() -> void:
	close()


func my_id() -> int:
	return _mp().get_unique_id()


# ------------------------------------------------------------------ joining

func _on_connected() -> void:
	_wait_left = -1.0
	hello.rpc_id(1, my_name, my_outfit, _version())


func _on_no_answer() -> void:
	_wait_left = -1.0
	var line := NetSession.label("no_answer")
	_toast(line % address if line.contains("%s") else line)
	refused.emit("no_answer")
	NetSession.leave()


static func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Guest -> host: let me in.
@rpc("any_peer", "call_remote", "reliable")
func hello(player_name: String, outfit: Dictionary, version: String) -> void:
	if not _mp().is_server():
		return
	var id := _mp().get_remote_sender_id()
	if roster.has(id):
		return
	if version != _version():
		_refuse(id, "refused_version")
		return
	if roster.size() >= _max:
		_refuse(id, "refused_full")
		return
	var nm := _unique(NetSession.clean_name(player_name))
	var fit := PlayerOutfit.sanitize(outfit)
	for other in roster:
		if other != 1:
			joined.rpc_id(other, id, nm, fit)
	roster[id] = { "name": nm, "outfit": fit }
	welcome.rpc_id(id, nm, GameFlow.current_planet_id(), roster)
	_on_joined(id, nm)


func _unique(nm: String) -> String:
	if nm == "":
		nm = str(NetSession.cfg().get("default_name", "Smuggler"))
	var taken: Array = roster.values().map(func(r): return str(r.name))
	var out := nm
	var k := 2
	while taken.has(out):
		out = "%s %d" % [nm, k]
		k += 1
	return out


func _refuse(id: int, why: String) -> void:
	nope.rpc_id(id, why)
	turned_away.emit(id, why)
	_kick[id] = 1.0          # the refusal gets there before the door shuts


## Host -> a guest it will not let in.
@rpc("authority", "call_remote", "reliable")
func nope(why: String) -> void:
	_toast(NetSession.label(why))
	refused.emit(why)
	NetSession.leave()


## Host -> the guest just let in: your name (made unique), the planet, who is here.
@rpc("authority", "call_remote", "reliable")
func welcome(your_name: String, planet_id: String, who: Dictionary) -> void:
	my_name = your_name
	roster = who
	host_name = str(who.get(1, {}).get("name", ""))
	welcomed_in = true
	welcomed.emit(planet_id)
	if arrive_on_welcome:
		_arrive(planet_id)


## The guest's game goes to the host's planet, beside T-89 (DevSettingsPanel.lan_arrive).
func _arrive(planet_id: String) -> void:
	var scene := get_tree().current_scene
	var panel = scene.get("dev_settings") if scene != null else null
	if panel != null and panel.has_method("lan_arrive"):
		panel.lan_arrive(planet_id)


## Host -> everyone already here: someone new.
@rpc("authority", "call_remote", "reliable")
func joined(id: int, player_name: String, outfit: Dictionary) -> void:
	roster[id] = { "name": player_name, "outfit": outfit }
	_on_joined(id, player_name)


func _on_joined(id: int, nm: String) -> void:
	var line := NetSession.label("joined")
	_toast(line % nm if line.contains("%s") else line)
	player_joined.emit(id, nm)


# ------------------------------------------------------------------ leaving

func _on_peer_gone(id: int) -> void:
	_kick.erase(id)
	if _mp().is_server() and roster.has(id):
		left.rpc(id)
	_gone(id)


## Host -> everyone: that one left.
@rpc("authority", "call_remote", "reliable")
func left(id: int) -> void:
	_gone(id)


func _gone(id: int) -> void:
	_drop_body(id)
	states.erase(id)
	if not roster.has(id):
		return
	var nm := str(roster[id].name)
	roster.erase(id)
	var line := NetSession.label("left")
	_toast(line % nm if line.contains("%s") else line)
	player_left.emit(id, nm)


func _on_host_gone() -> void:
	_toast(NetSession.label("host_left"), 6.0)
	host_left.emit()
	NetSession.leave()      # you play on in your own game, where you stand


# ------------------------------------------------------------------ state

## Every player -> every other (the host relays): where I am and what I am doing.
## [planet, position, yaw, velocity, flags, weapon, drawn, aim pitch, ground tilt]
@rpc("any_peer", "call_remote", "unreliable_ordered")
func state(pkt: Array) -> void:
	var id := _mp().get_remote_sender_id()
	if pkt.size() < 9 or (_mp().is_server() and not roster.has(id)):
		return
	states[id] = {
		"planet": str(pkt[0]), "pos": pkt[1] as Vector3, "yaw": float(pkt[2]), "vel": pkt[3] as Vector3,
		"flags": int(pkt[4]), "weapon": str(pkt[5]), "drawn": float(pkt[6]), "pitch": float(pkt[7]),
		"tilt": pkt[8] as Quaternion, "t": Time.get_ticks_msec() / 1000.0,
	}


func _physics_process(dt: float) -> void:
	for id in _kick.keys():
		_kick[id] -= dt
		if _kick[id] <= 0.0:
			_kick.erase(id)
			var peer := _mp().multiplayer_peer as ENetMultiplayerPeer
			if peer != null:
				peer.disconnect_peer(id)
	if _wait_left >= 0.0:
		_wait_left -= dt
		if _wait_left < 0.0:
			_on_no_answer()
			return
	if not _connected():
		return
	_send_left -= dt
	if _send_left <= 0.0:
		_send_left = 1.0 / maxf(1.0, NetSession.n("send_rate", 20.0))
		var pkt: Array = local_state.call() if local_state.is_valid() else town_state()
		if not pkt.is_empty() and (_mp().is_server() or welcomed_in):
			state.rpc(pkt)
	if with_bodies:
		_place_bodies()
	_hook_shots()
	_fit_left -= dt
	if _fit_left <= 0.0:
		_fit_left = NetSession.n("outfit_check_s", 1.0)
		_send_outfit()


func _connected() -> bool:
	var peer := _mp().multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## The town's player as a state packet ([] when there is none: a flight scene, a
## loading town).
func town_state() -> Array:
	var scene := get_tree().current_scene
	var p = scene.get("_player") if scene != null else null
	if not (p is CharacterBody3D) or not is_instance_valid(p) or not p.is_inside_tree():
		return []
	var body := p as CharacterBody3D
	var ctl = body.get("controller")
	var flags := 0
	if body.is_on_floor():
		flags |= F_GROUNDED
	if ctl != null and ctl.crouching():
		flags |= F_CROUCH
	if ctl != null and bool(ctl.command.sprint):
		flags |= F_SPRINT
	if ctl != null and ctl.is_sliding():
		flags |= F_SLIDE
	if body.is_visible_in_tree():
		flags |= F_VISIBLE
	var rig_node = scene.get("_rig")
	var rig = rig_node.rig if rig_node != null and is_instance_valid(rig_node) else null
	var kit = scene.get("player_kit")
	var weapon := ""
	var drawn := 0.0
	if kit != null and is_instance_valid(kit) and kit.avatar != null:
		weapon = str(kit.avatar.current)
		drawn = float(kit.avatar.drawn)
	var tilt = body.get("tilt")
	return [GameFlow.current_planet_id(), body.global_position, rig.yaw if rig != null else body.rotation.y,
		body.velocity, flags, weapon, drawn, rig.pitch if rig != null else 0.0,
		(tilt as Basis).get_rotation_quaternion() if tilt is Basis else Quaternion.IDENTITY]


## A body in this town for every other player on this planet who is not in a ship.
func _place_bodies() -> void:
	var scene := get_tree().current_scene
	var here := GameFlow.current_planet_id()
	var town := scene != null and scene.get("_player") != null
	for id in roster:
		if id == my_id():
			continue
		var s: Dictionary = states.get(id, {})
		var show := town and not s.is_empty() and str(s.planet) == here
		var b = bodies.get(id, null)
		if b != null and (not is_instance_valid(b) or b.get_parent() != scene):
			_drop_body(id)
			b = null
		if not show:
			if b != null:
				_drop_body(id)
			continue
		if b == null:
			var mats = scene.call("_flat_mats") if scene.has_method("_flat_mats") else null
			b = RemotePlayer.new()
			b.setup(id, str(roster[id].name), roster[id].get("outfit", {}), mats)
			scene.add_child(b)
			bodies[id] = b
		b.hear(s)


func _drop_body(id: int) -> void:
	var b = bodies.get(id, null)
	bodies.erase(id)
	if b != null and is_instance_valid(b):
		b.queue_free()


# ------------------------------------------------------------------ outfits

## What you wear changed (the character builder, another save's outfit): tell the
## others. Read off the town's avatar, so every way of changing it is caught.
func _send_outfit() -> void:
	var fit: Dictionary = {}
	if local_outfit.is_valid():
		fit = local_outfit.call()
	else:
		var scene := get_tree().current_scene
		var kit = scene.get("player_kit") if scene != null else null
		if kit == null or not is_instance_valid(kit) or kit.avatar == null:
			return
		fit = kit.avatar.worn_outfit()
	if fit.is_empty() or fit.hash() == my_outfit.hash():
		return
	my_outfit = fit
	if roster.has(my_id()):
		roster[my_id()]["outfit"] = fit
	if _mp().is_server() or welcomed_in:
		outfit.rpc(fit)


## Every player -> every other (the host relays): what I wear now. The host keeps
## it on the roster, so someone joining later sees it too.
@rpc("any_peer", "call_remote", "reliable")
func outfit(fit: Dictionary) -> void:
	var id := _mp().get_remote_sender_id()
	if not roster.has(id):
		return
	var clean := PlayerOutfit.sanitize(fit)
	roster[id]["outfit"] = clean
	outfits_heard += 1
	var b = bodies.get(id, null)
	if b != null and is_instance_valid(b):
		b.wear(clean)


# ------------------------------------------------------------------ shots and friendly fire

## Send the town's player's shots to the others (a new town builds new weapons).
func _hook_shots() -> void:
	var scene := get_tree().current_scene
	var kit = scene.get("player_kit") if scene != null else null
	var w = kit.weapons if kit != null and is_instance_valid(kit) else null
	if w == null or w == _hooked:
		return
	_hooked = w
	w.bolt_fired.connect(func(origin: Vector3, dir: Vector3, reach: float, b: Node):
		if _connected() and (_mp().is_server() or welcomed_in):
			shot.rpc([GameFlow.current_planet_id(), origin, dir, float(b.speed), b.color, reach, float(b.streak_length)]))


## Every player -> every other: a bolt I fired, from, which way, how fast, its
## colour and how far it went before it hit something (in my game). Shown here as
## a streak that flies that far and touches nothing: what it hit is the shooter's
## game's to say (a hit on you comes as `hit`).
@rpc("any_peer", "call_remote", "reliable")
func shot(pkt: Array) -> void:
	var id := _mp().get_remote_sender_id()
	var scene := get_tree().current_scene
	if pkt.size() < 7 or not roster.has(id) or scene == null or scene.get("_player") == null \
			or str(pkt[0]) != GameFlow.current_planet_id():
		return
	var b = BoltScene.instantiate()
	b.direction = (pkt[2] as Vector3).normalized()
	b.speed = float(pkt[3])
	b.damage = 0.0
	b.range_m = float(pkt[5])
	b.color = pkt[4] as Color
	b.streak_length = float(pkt[6])
	b.stylize = true
	b.shooter = bodies.get(id, null)
	scene.add_child(b)
	b.global_position = pkt[1] as Vector3
	b.monitoring = false               # a picture of the shot, never a hit
	b.collision_mask = 0
	b.remove_from_group("bolts")       # your blade does not deflect it either
	shots_seen += 1


## Your bolt or blade landed on player `id`'s body here: tell their game.
func send_hit(id: int, amount: float, from: Vector3) -> void:
	if roster.has(id) and id != my_id():
		hit.rpc_id(id, amount, from)


## A player's bolt or blade -> the player it landed on: take `amount`, from `from`.
## Your own game applies it, through the same door as a guard's bolt.
@rpc("any_peer", "call_remote", "reliable")
func hit(amount: float, from: Vector3) -> void:
	var id := _mp().get_remote_sender_id()
	if not roster.has(id) or not RemotePlayer.friendly_fire():
		return
	var dmg := clampf(amount, 0.0, 500.0) * NetSession.n("friendly_fire_scale", 1.0)
	hits_taken += 1
	var scene := get_tree().current_scene
	var p = scene.get("_player") if scene != null else null
	if not (p is CharacterBody3D) or not is_instance_valid(p) or dmg <= 0.0:
		return
	var shooter = bodies.get(id, null)
	if shooter != null and is_instance_valid(shooter):
		p.apply_damage_from(dmg, shooter)
	else:
		p.last_hit_from = from
		p.apply_damage(dmg)


# ------------------------------------------------------------------ words

func _toast(text: String, secs := 4.0) -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	var gear = scene.get("gear") if scene != null else null
	if gear != null and is_instance_valid(gear) and gear.hud != null:
		gear.hud.toast(text, secs)
	else:
		print("LAN: ", text)


func names() -> Array:
	var ids := roster.keys()
	ids.sort()
	return ids.map(func(i): return str(roster[i].name))


func status_line() -> String:
	var head := ""
	if _mp().is_server():
		var at := NetSession.local_addresses()
		var line := NetSession.label("hosting")
		head = line % (at[0] if not at.is_empty() else "this computer's address") if line.contains("%s") else line
	elif welcomed_in:
		var line := NetSession.label("guest")
		head = line % host_name if line.contains("%s") else line
	else:
		var line := NetSession.label("connecting")
		return line % address if line.contains("%s") else line
	var here := NetSession.label("here")
	var who := ", ".join(names())
	return head + "\n" + (here % ("%s  (%d of %d)" % [who, roster.size(), _max_shown()]) if here.contains("%s") else who)


func _max_shown() -> int:
	return _max if _mp().is_server() else NetSession.max_players()
