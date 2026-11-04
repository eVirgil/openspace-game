extends GutTest
## LAN: another player's ship in flight is boxed on your flight HUD as an enemy is
## (RemoteShip.hud_target: where, the lead, the range, their hull from the packet),
## and the F11 map and the player waypoint find a player in their ship as well as
## on foot (NetSession.others / player_pos). A fake NetLink holds the bodies and
## ships the town would have.

const RemoteShip := preload("res://src/systems/net/remote_ship.gd")


class FakeLink extends Node:
	var bodies := {}
	var ship_bodies := {}
	var roster := {}


class FakeBody extends Node3D:
	var player_name := ""


var _role := ""
var _link: Node


func before_each() -> void:
	_role = NetSession.role
	_link = NetSession.link


func after_each() -> void:
	NetSession.role = _role
	NetSession.link = _link


func _remote(at: Vector3, flying: bool, hull := 1.0) -> Node3D:
	var rs = RemoteShip.new()
	rs.setup(7, "Pal", "")
	add_child_autofree(rs)
	rs.hear("", at, Quaternion.IDENTITY, flying, hull)
	return rs


func _link_with(rs: Node3D, body: Node3D) -> FakeLink:
	var link := FakeLink.new()
	add_child_autofree(link)
	link.roster[7] = { "name": "Pal" }
	if rs != null:
		link.ship_bodies[7] = rs
	if body != null:
		link.bodies[7] = body
	NetSession.link = link
	NetSession.role = NetSession.HOST
	return link


func _body(at: Vector3, shown: bool) -> Node3D:
	var b := FakeBody.new()
	b.player_name = "Pal"
	add_child_autofree(b)
	b.global_position = at
	b.visible = shown
	return b


func test_a_flying_friend_is_boxed_like_an_enemy() -> void:
	var rs = _remote(Vector3(0, 40, -100), true, 0.6)
	var t: Dictionary = rs.hud_target(Vector3.ZERO, Vector3.ZERO, 300.0)
	assert_false(t.is_empty(), "flying: your HUD boxes it")
	for k in ["pos", "lead", "lead_ok", "dist", "hull"]:
		assert_true(t.has(k), "it has %s, as AtmoFighter.hud_target does" % k)
	assert_almost_eq(float(t.hull), 0.6, 0.001, "the bar is their hull, from their packet")
	assert_almost_eq(float(t.dist), Vector3(0, 40, -100).length(), 0.01)
	assert_false(t.has("lock"), "no lock ring: seekers never lock on a friend")
	rs.hear("", Vector3(0, 5, 0), Quaternion.IDENTITY, false)
	assert_true(rs.hud_target(Vector3.ZERO, Vector3.ZERO, 300.0).is_empty(), "parked: no box")


func test_no_box_with_friendly_fire_off() -> void:
	var rs = _remote(Vector3(0, 40, -100), true)
	var cfg: Dictionary = NetSession.cfg()
	var was = cfg.get("friendly_fire", true)
	cfg["friendly_fire"] = false
	var t: Dictionary = rs.hud_target(Vector3.ZERO, Vector3.ZERO, 300.0)
	cfg["friendly_fire"] = was
	assert_true(t.is_empty(), "your guns cannot hit them, so they are no target")


func test_the_hud_draws_friends_and_the_enemy() -> void:
	var hud := FlightHud.new()
	add_child_autofree(hud)
	assert_eq(hud.friends, [], "none until the pilot fills them in")
	hud.friends = [{ "pos": Vector3(0, 0, -50), "lead": Vector3(0, 0, -50), "lead_ok": true, "dist": 50.0, "hull": 0.5 }]
	hud.gauge.queue_redraw()
	await wait_frames(2)
	assert_eq(hud.friends.size(), 1, "drawn without trouble, camera or not")


func test_the_map_finds_a_friend_on_foot() -> void:
	var rs = _remote(Vector3(50, 2, 50), false)
	_link_with(rs, _body(Vector3(10, 1, 10), true))
	var o: Array = NetSession.others()
	assert_eq(o.size(), 1)
	assert_eq(str(o[0].name), "Pal")
	assert_eq(o[0].pos, Vector3(10, 1, 10), "on foot: where they stand, not their parked ship")
	assert_false(bool(o[0].ship))
	assert_eq(NetSession.player_pos(7), Vector3(10, 1, 10))


func test_the_map_finds_a_friend_in_their_ship() -> void:
	var rs = _remote(Vector3(200, 900, -300), true)
	var body := _body(Vector3(10, 1, 10), false)
	_link_with(rs, body)
	var o: Array = NetSession.others()
	assert_eq(o.size(), 1, "in a ship they are still on the map")
	assert_eq(o[0].pos, Vector3(200, 900, -300), "where their ship is (the map puts it straight down)")
	assert_true(bool(o[0].ship))
	assert_eq(NetSession.player_pos(7), Vector3(200, 900, -300), "the waypoint follows the ship")


func test_sat_in_a_parked_ship_is_the_ship() -> void:
	var rs = _remote(Vector3(50, 2, 50), false)
	_link_with(rs, _body(Vector3(10, 1, 10), false))
	assert_eq(NetSession.player_pos(7), Vector3(50, 2, 50), "in the pilot's seat on the pad: their body is put away, the ship is them")


func test_a_flying_friend_with_no_body_here_is_still_on_the_map() -> void:
	var rs = _remote(Vector3(0, 3000, 0), true)
	_link_with(rs, null)
	var o: Array = NetSession.others()
	assert_eq(o.size(), 1, "up in this planet's space, only their ship is here")
	assert_eq(str(o[0].name), "Pal", "named from the roster")
	rs.hear("", Vector3(0, 2, 0), Quaternion.IDENTITY, false)
	assert_eq(NetSession.others().size(), 0, "a parked ship with nobody here is not them")
