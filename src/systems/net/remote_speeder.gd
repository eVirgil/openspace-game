extends Node3D
## Another LAN player's speeder, in this town, while they ride it: the same model
## as theirs (a SpeederNode that is not rideable, built from their speeder's data
## and paint: NetLink.ride_look) with "<name>'s speeder" over it. A picture: its
## hull is off (nothing here hits or bumps it), and walking up to it lets you
## hijack it (Hijack). NetLink hands it every packet heard (hear); between packets
## it runs on at the speed it had, smoothed, as RemoteShip does.

const RemoteShip := preload("res://src/systems/net/remote_ship.gd")
const Hijack := preload("res://src/systems/vehicles/hijack.gd")
const LEAD_MAX := 0.25

var peer_id := 0
var player_name := ""
var look_key := ""                ## NetLink's key for its look (a new key: a new copy)
var speeder: SpeederNode
var _cfg: Dictionary = {}
var _paint := ""
var _demo
var _ground: WorldGround
var _pos := Vector3.INF
var _rot := Quaternion.IDENTITY
var _vel := Vector3.ZERO
var _t := 0.0
var _placed := false


func setup(id: int, owner_name: String, key: String, cfg: Dictionary, paint: String, demo, ground: WorldGround) -> void:
	peer_id = id
	player_name = owner_name
	look_key = key
	_cfg = cfg
	_paint = paint
	_demo = demo
	_ground = ground
	name = "RemoteSpeeder_%d" % id


func _ready() -> void:
	speeder = SpeederNode.new()
	speeder.setup(_demo, _ground, _cfg, false, _paint)
	add_child(speeder)
	speeder.transform = Transform3D.IDENTITY       # this node carries it
	if speeder.hull != null:
		speeder.hull.collision_layer = 0
		speeder.hull.collision_mask = 0
	var tag := RemoteShip.make_tag(Hijack.fmt("speeder_tag", [player_name]))
	tag.position.y = 2.0
	add_child(tag)
	visible = false


func hear(pos: Vector3, rot: Quaternion) -> void:
	var now := Time.get_ticks_msec() / 1000.0
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
	if speeder != null and speeder.transform != Transform3D.IDENTITY:
		speeder.transform = Transform3D.IDENTITY
	var since := clampf(Time.get_ticks_msec() / 1000.0 - _t, 0.0, LEAD_MAX)
	var to := _pos + _vel * since
	if global_position.distance_to(to) > maxf(NetSession.n("snap_m", 8.0), _vel.length() * 0.5):
		global_position = to
		quaternion = _rot
		return
	var k := 1.0 - exp(-NetSession.n("smooth_rate", 14.0) * dt)
	global_position = global_position.lerp(to, k)
	quaternion = quaternion.slerp(_rot, k)
