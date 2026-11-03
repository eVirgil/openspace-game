extends GutTest
## LAN friendly fire for ships: another player's ship (RemoteShip) is solid to bolts
## only while they fly it, a seeker flying straight hits it as a cannon bolt does,
## your bolts and seekers in a space fight that cross it go to their game (NetFight), and a friend's hit lands on your ship in
## the fight's director (Dogfight.friendly_damage). The network itself is
## scripts/test_lan.sh's; here a fake NetLink takes what would be sent.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")
const RemoteShip := preload("res://src/systems/net/remote_ship.gd")
const NetFight := preload("res://src/systems/net/net_fight.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")


class FakeLink extends Node:
	var ship_bodies := {}
	var sent: Array = []

	func send_ship_hit(id: int, amount: float) -> void:
		sent.append([id, amount])


var content
var _role := ""
var _link: Node


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()
	_role = NetSession.role
	_link = NetSession.link


func after_each() -> void:
	NetSession.role = _role
	NetSession.link = _link


func _remote(at: Vector3, flying: bool) -> Node3D:
	var rs = RemoteShip.new()
	rs.setup(7, "Pal", "")
	add_child_autofree(rs)
	rs.hear("", at, Quaternion.IDENTITY, flying)
	return rs


func _fight() -> Dictionary:
	var df = Dogfight.new(content, "orbital_skirmish", 3)
	df.start()
	return { "df": df }


func test_remote_ship_is_solid_only_in_the_air() -> void:
	var rs = _remote(Vector3(0, 5, 0), false)
	assert_eq(rs.hull.collision_layer, 0, "parked: a picture, bolts pass")
	assert_false(rs.hittable())
	rs.hear("", Vector3(0, 30, 0), Quaternion.IDENTITY, true)
	assert_eq(rs.hull.collision_layer, 1, "flying: bolts hit its hull")
	assert_true(rs.hittable())
	assert_eq(rs.hull.collision_mask, 0, "it bumps into nothing itself")


func test_a_straight_seeker_hits_a_friends_ship() -> void:
	var rs = _remote(Vector3(0, 30, 0), true)
	var seeker = BoltScene.instantiate()
	seeker.blast_size = 1.0
	add_child_autofree(seeker)
	seeker._on_body_entered(rs.hull)
	assert_false(seeker._alive, "an unlocked seeker stops on it (and its hit is sent)")
	var bolt = BoltScene.instantiate()
	add_child_autofree(bolt)
	bolt._on_body_entered(rs.hull)
	assert_false(bolt._alive, "so does a cannon bolt")


func test_space_bolts_on_a_friends_ship_go_to_their_game() -> void:
	var rs = _remote(Vector3(0, 0, -50), true)
	var link := FakeLink.new()
	add_child_autofree(link)
	link.ship_bodies[7] = rs
	var nf = NetFight.new()
	link.add_child(nf)
	var fight := _fight()
	var df = fight.df
	var crossing := func(kind: String) -> void:
		df.projectiles.add({ "kind": kind, "origin": Vector3(0, 0, -45), "velocity": Vector3(0, 0, -300),
			"damage": 12.0 }, df.player_id, "player")
		var p: Dictionary = df.projectiles.items.back()
		p.prev = Vector3(0, 0, -45)
		p.pos = Vector3(0, 0, -55)
	df.projectiles.items.clear()
	crossing.call("bolt")
	crossing.call("missile")
	df.projectiles.add({ "kind": "bolt", "origin": Vector3(0, 0, -45), "velocity": Vector3(0, 0, -300),
		"damage": 12.0 }, 999, "hostile")               # not yours
	df.projectiles.items.back().prev = Vector3(0, 0, -45)
	df.projectiles.items.back().pos = Vector3(0, 0, -55)
	nf._hit_players(fight)
	assert_eq(link.sent, [[7, 12.0], [7, 12.0]], "your bolt's hit and your seeker's are sent, once each")
	assert_eq(df.projectiles.items.size(), 1, "they stop there; the other's bolt flies on")
	assert_eq(int(df.projectiles.items[0].owner), 999)
	rs.hear("", Vector3(0, 0, -50), Quaternion.IDENTITY, false)
	df.projectiles.items.clear()
	crossing.call("bolt")
	nf._hit_players(fight)
	assert_eq(link.sent.size(), 2, "a parked ship is not hit")


func test_a_friends_hit_lands_on_your_ship_in_the_fight() -> void:
	var df = _fight().df
	df.step(1.0 / 60.0)
	assert_eq(df.friendly_damage(5.0), 1, "it hurt")
	var hit := false
	for e in df.step(1.0 / 60.0):
		hit = hit or (str(e.type) == "hit" and int(e.id) == df.player_id)
	assert_true(hit, "the next step reports the hit on you")
	assert_eq(df.friendly_damage(100000.0), 2, "it shot you down")
	var failed := false
	for e in df.step(1.0 / 60.0):
		failed = failed or str(e.type) == "failed"
	assert_true(failed, "the fight is lost, as to any other gun")
	assert_eq(df.friendly_damage(5.0), 0, "nothing lands after")
