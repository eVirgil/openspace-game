extends Node3D
## Issue #401: another LAN player's ship, in this town: the one they fly, else the
## one they would call (their primary), parked or flying, in its look (a guest's
## livery) with "<name>'s ship" over it. A picture only: nothing to board or hit;
## it is theirs, in their game.
##
## NetLink hands it every ship packet heard (hear); between packets it runs on at
## the speed it had, smoothed, and jumps when it is snap_m off.

const LEAD_MAX := 0.25            ## seconds it may run on past its last packet

var peer_id := 0
var look_id := ""
var model: Node3D
var tag: Label3D
var _mats: LookMaterials
var _pos := Vector3.INF           ## the last spot heard
var _rot := Quaternion.IDENTITY
var _vel := Vector3.ZERO
var _t := 0.0
var _placed := false


func setup(id: int, owner_name: String, look: String, mats: LookMaterials = null) -> void:
	peer_id = id
	look_id = look
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


## The latest packet: its look, where it is and which way it points.
func hear(look: String, pos: Vector3, rot: Quaternion) -> void:
	var now := Time.get_ticks_msec() / 1000.0
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
