extends Node3D
## Issue #401: another LAN player's ship, in this town: the one they fly, else the
## one they would call (their primary), parked or flying, in its look (a guest's
## livery) with "<name>'s ship" over it. Nothing to board: it is theirs, in their
## game. Friendly fire (lan.json "friendly_fire"): while they fly it, it carries a
## ShipHull your ship's cannons hit (in the town's sky; out in space NetFight tests
## the fight's bolts against `radius()`), and each hit goes to their game
## (NetLink.send_ship_hit), which lands it on the ship they fly. Nothing locks on
## it, but a seeker flying straight that runs into it hits it too. Parked, it is a
## picture. While it can be hit, your flight HUD boxes it as it does an enemy
## (hud_target: the box, its hull from their packets, the range and the lead pip).
##
## NetLink hands it every ship packet heard (hear); between packets it runs on at
## the speed it had, smoothed, and jumps when it is snap_m off.

const TownDecor := preload("res://src/systems/world/town_decor.gd")
const RemotePlayer := preload("res://src/systems/net/remote_player.gd")
const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")
const LEAD_MAX := 0.25            ## seconds it may run on past its last packet

var peer_id := 0
var look_id := ""
var model: Node3D
var tag: Label3D
var hull: ShipHull                ## the model's own shape, solid only while they fly it
var flying := false               ## their last packet: in the air (or out in space)
var player_name := ""             ## whose it is
var hull_frac := 1.0              ## their last packet: hull left, 0..1 (the HUD's bar)
var _radius := 4.0
var _mats: LookMaterials
var _pos := Vector3.INF           ## the last spot heard
var _rot := Quaternion.IDENTITY
var _vel := Vector3.ZERO
var _t := 0.0
var _placed := false


func setup(id: int, owner_name: String, look: String, mats: LookMaterials = null) -> void:
	peer_id = id
	look_id = look
	player_name = owner_name
	_mats = mats
	name = "RemoteShip_%d" % id
	tag = make_tag(NetSession.label("ship_tag") % owner_name if NetSession.label("ship_tag").contains("%s") else owner_name)


func _ready() -> void:
	_build()
	add_child(tag)
	visible = false               # until the first packet places it


func _build() -> void:
	if model != null:
		model.queue_free()
	model = ShipKit.new(_mats).build(look_id) if look_id != "" else Node3D.new()
	add_child(model)
	_build_hull()


## The hull fitted to the model, as ShipPilot fits its own (a box if it has no meshes).
func _build_hull() -> void:
	if hull != null:
		hull.queue_free()
	var acc := [null]
	TownDecor._merge_aabb(model, Transform3D.IDENTITY, acc)
	var box: AABB = acc[0] if acc[0] != null else AABB(Vector3(-4.5, -1.25, -4.0), Vector3(9.0, 2.5, 8.0))
	_radius = maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.5
	hull = ShipHull.new()
	hull.name = "ShipHull"
	hull.on_damage = _on_hit
	if acc[0] == null or not hull.fit(model):
		hull.fit_box(box.size, box.get_center())
	add_child(hull)
	_set_solid()


func _set_solid() -> void:
	if hull != null:
		hull.collision_layer = 1 if flying and visible and RemotePlayer.friendly_fire() else 0
		hull.collision_mask = 0


## How far from its middle a bolt in space counts as on it.
func radius() -> float:
	return _radius


## Whether your shots can land on it now.
func hittable() -> bool:
	return _placed and visible and flying and RemotePlayer.friendly_fire()


## How fast it moves, from its last two packets.
func velocity() -> Vector3:
	return _vel


## What your flight HUD draws for it while your guns can hit it, as for an enemy
## (AtmoFighter.hud_target): where it is, where to aim for bolts of `bolt_speed`
## fired from `from` moving at `from_vel`, the range and its hull. {} otherwise.
func hud_target(from: Vector3, from_vel: Vector3, bolt_speed: float) -> Dictionary:
	if not hittable() or not is_inside_tree():
		return {}
	var at := global_position
	var lead: Dictionary = LeadSolver.intercept(from, from_vel, at, _vel, bolt_speed)
	return { "pos": at, "lead": lead.point, "lead_ok": bool(lead.valid), "label": player_name,
		"dist": from.distance_to(at), "hull": hull_frac, "peer": peer_id }


## A bolt (or a cannon's splash) landed on the hull. Only your own ship's count: the
## town's guns hitting it are the owner's game's business, not yours.
func _on_hit(amount: float, shooter: Node) -> void:
	var scene := get_tree().current_scene if is_inside_tree() else null
	var pilot = scene.get("pilot") if scene != null else null
	var yours = pilot.get("hull") if pilot != null and is_instance_valid(pilot) else null
	if shooter != null and is_instance_valid(shooter) and shooter == yours and hittable():
		NetSession.link.send_ship_hit(peer_id, amount)


## A floating name for a ship (yours too: ShipPilot puts one over a LAN guest's own).
static func make_tag(text: String) -> Label3D:
	var t := Label3D.new()
	t.name = "ShipTag"
	t.text = text
	t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t.position.y = NetSession.n("ship_tag_height", 3.2)
	t.pixel_size = 0.012
	t.font_size = 40
	t.outline_size = 10
	t.modulate = Color(1.0, 0.93, 0.78)
	t.no_depth_test = false
	return t


## The latest packet: its look, where it is, which way it points, whether it flies
## and how much hull it has left (0..1).
func hear(look: String, pos: Vector3, rot: Quaternion, in_air := false, hull := 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	hull_frac = clampf(hull, 0.0, 1.0)
	if in_air != flying:
		flying = in_air
		_set_solid()
	if look != look_id:
		look_id = look
		if is_inside_tree():
			_build()
	if _pos != Vector3.INF and now > _t:
		_vel = (pos - _pos) / maxf(now - _t, 0.02)
	_pos = pos
	_rot = rot.normalized()
	_t = now
	if not _placed and is_inside_tree():
		global_position = pos
		quaternion = _rot
		_placed = true
		visible = true
		_set_solid()


func _physics_process(dt: float) -> void:
	if not _placed:
		return
	var since := clampf(Time.get_ticks_msec() / 1000.0 - _t, 0.0, LEAD_MAX)
	var to := _pos + _vel * since
	if global_position.distance_to(to) > maxf(NetSession.n("snap_m", 8.0), _vel.length() * 0.5):
		global_position = to
		quaternion = _rot
		return
	var k := 1.0 - exp(-NetSession.n("smooth_rate", 14.0) * dt)
	global_position = global_position.lerp(to, k)
	quaternion = quaternion.slerp(_rot, k)
