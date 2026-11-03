class_name NetSession
extends RefCounted
## Issue #401: LAN play. On the same wifi one player hosts (F11 > Game) and friends
## join by the host's address; up to max_players smugglers walk the same port,
## each seeing the others' bodies, outfits and names. Free roam only: a guest's
## credits, gear and save stay their own files, and nothing of the host's world is
## sent but which planet to stand on.
##
## Godot's own multiplayer (SceneMultiplayer over ENet), host-authoritative: the
## host's game is the server, guests send their state and the host relays it.
## The RPCs live on one node, NetLink, put straight under the tree's root while a
## session is open, so it (and the connection) outlives the town reloading.
## No autoload: nothing runs until someone hosts or joins.
##
## State lives in static vars, like GameFlow and SaveSlots. The player's name and
## the last address typed are remembered (settings/lan.cfg) and changed in F11.

const CFG_PATH := "res://content/core/flow/lan.json"
const PREFS := "settings/lan.cfg"
const NetLink := preload("res://src/systems/net/net_link.gd")

const HOST := "host"
const GUEST := "guest"

static var root := "user://"     ## tests point this elsewhere
static var role := ""            ## "", HOST or GUEST
static var link: Node            ## /root/NetLink while a session is open
static var guest_spawn := false  ## the next town puts you beside T-89 (a guest just let in)
## A guest's own ship this session (Fleet.LAN): { look, pad, spot }: its livery,
## the landing pad the host gave it ("" = none free) and where it stands now
## (Fleet.spot's shape; {} until it is placed). Empty: not a guest, or no ship.
## Not saved: the guest's save keeps its own ships.
static var ship: Dictionary = {}
static var max_override := 0     ## tests: a smaller game than the data's
static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d if d is Dictionary else {}
		if _cfg.is_empty():
			push_warning("NetSession: could not read ", CFG_PATH)
	return _cfg


static func n(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


static func label(key: String) -> String:
	return str(cfg().get("labels", {}).get(key, key))


static func port() -> int:
	return int(n("port", 24890))


static func max_players() -> int:
	return max_override if max_override > 0 else int(n("max_players", 5))


static func active() -> bool:
	return role != "" and link != null and is_instance_valid(link)


static func is_host() -> bool:
	return active() and role == HOST


static func is_guest() -> bool:
	return active() and role == GUEST


## A name as it shows over a head: one line, trimmed, at most name_max letters.
static func clean_name(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if ch.unicode_at(0) >= 32 and ch != "\n" and ch != "\t":
			out += ch
	return out.strip_edges().left(int(n("name_max", 16)))


# ------------------------------------------------------------------ remembered

static func _prefs() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(root + PREFS)
	return c


static func _remember(key: String, value: String) -> void:
	var c := _prefs()
	c.set_value("lan", key, value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path((root + PREFS).get_base_dir()))
	c.save(root + PREFS)


static func saved_name() -> String:
	return str(_prefs().get_value("lan", "name", ""))


static func save_name(s: String) -> void:
	_remember("name", clean_name(s))


static func saved_address() -> String:
	return str(_prefs().get_value("lan", "address", ""))


static func save_address(s: String) -> void:
	_remember("address", s.strip_edges())


## This computer's addresses on the local network, for a host to read out.
static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.push_front(a)
		else:
			out.append(a)
	return out


# ------------------------------------------------------------------ session

## Host a game. Returns OK, or why not.
static func host(tree: SceneTree, player_name: String, outfit: Dictionary = {}) -> Error:
	leave()
	var l := _make_link(tree, player_name, outfit)
	var err: Error = l.start_host(port(), max_players())
	if err != OK:
		_drop_link()
		return err
	role = HOST
	return OK


## Join the game hosted at `address`. Returns OK when the attempt started (the
## answer comes later: NetLink's welcome, refusal or no answer).
static func join(tree: SceneTree, address: String, player_name: String, outfit: Dictionary = {}) -> Error:
	leave()
	var l := _make_link(tree, player_name, outfit)
	var err: Error = l.start_guest(address.strip_edges(), port())
	if err != OK:
		_drop_link()
		return err
	role = GUEST
	return OK


## Close the session (if any): everyone else is told, the other bodies go.
static func leave() -> void:
	if link != null and is_instance_valid(link):
		link.close()
	_drop_link()


static func _make_link(tree: SceneTree, player_name: String, outfit: Dictionary) -> Node:
	var l: Node = NetLink.new()
	l.name = "NetLink"
	l.my_name = clean_name(player_name)
	if l.my_name == "":
		l.my_name = str(cfg().get("default_name", "Smuggler"))
	l.my_outfit = outfit
	tree.root.add_child(l)
	link = l
	return l


static func _drop_link() -> void:
	if link != null and is_instance_valid(link):
		link.queue_free()
	link = null
	role = ""
	ship = {}


## The town calls this as it spawns the player: true once after a guest was let in.
static func take_guest_spawn() -> bool:
	var g := guest_spawn
	guest_spawn = false
	return g


## Where a guest stands on arrival: spawn_by_t89_m from T-89 at `t89`, on a ring
## by peer id so two guests never stand in each other.
static func spot_by(t89: Vector3, peer_id: int) -> Vector3:
	var a := float(peer_id % 7919) * 2.39996        # the golden angle: ids spread round him
	var r := n("spawn_by_t89_m", 2.2)
	return t89 + Vector3(sin(a), 0.0, cos(a)) * r


## This player's place among the players: 0 alone or hosting, a guest's join slot
## + 1 (their speeder's spot in the row outside the back gate, SpeederPost.line_spot).
static func my_slot() -> int:
	if not is_guest():
		return 0
	return int(link.roster.get(link.my_id(), {}).get("slot", 0)) + 1


## A guest's ship's livery for join slot `slot` (0 = the first guest).
static func livery(slot: int) -> String:
	var all: Array = cfg().get("liveries", [])
	return str(all[slot % all.size()]) if not all.is_empty() else ""


## Where a guest stands by landing pad `box` (a town box): spawn_by_pad_m past its
## edge, on the side toward `toward` (the town's middle), and the yaw to face it.
static func spot_by_pad(box: Dictionary, toward: Vector3) -> Array:
	var lo := Vector3(float(box.min[0]), float(box.min[1]), float(box.min[2]))
	var hi := Vector3(float(box.max[0]), float(box.max[1]), float(box.max[2]))
	var c := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var dir := Vector3(toward.x - c.x, 0.0, toward.z - c.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var at := c + dir * (minf(hi.x - lo.x, hi.z - lo.z) * 0.5 + n("spawn_by_pad_m", 1.5))
	return [at, atan2(c.x - at.x, c.z - at.z)]


## The other players on foot in this town: [{ id, name, pos }]. The F11 map shows
## them (mark_color), and one can be the waypoint ("player:<id>"). Only reads the
## bodies the town already has.
static func others() -> Array:
	var out: Array = []
	if not active():
		return out
	for id in link.bodies:
		var b = link.bodies[id]
		if b != null and is_instance_valid(b) and b.is_visible_in_tree():
			out.append({ "id": int(id), "name": str(b.player_name), "pos": (b as Node3D).global_position })
	return out


## Where player `id` stands in this town, or INF (in a ship, on another planet).
static func player_pos(id: int) -> Vector3:
	var b = link.bodies.get(id, null) if active() else null
	if b == null or not is_instance_valid(b) or not b.is_visible_in_tree():
		return Vector3.INF
	return (b as Node3D).global_position


## Player `id` is still in the game.
static func in_game(id: int) -> bool:
	return active() and link.roster.has(id)


static func mark_color() -> Color:
	return Color(str(cfg().get("mark_color", "#4da6ff")))


## One line for F11: hosting at, in whose game, or not connected; then who is here.
static func status_line() -> String:
	if not active():
		return label("offline")
	return link.status_line()
