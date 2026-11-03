class_name DogfightView
extends Node3D
## The visible half of a dogfight (issue #46): every ship, bolt and explosion the
## pure director (dogfight.gd) owns, drawn and kept in step. No input, no camera,
## no HUD, so the same view draws the stand-alone space scene (dogfight_demo) and
## a fight in the port's own sky (SpaceFight), where the player's ship is the
## town's parked model and is left out with `skip_id`.

const ShipNode := preload("res://src/systems/flight/ship_node.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var kit: ShipKit
var skip_id := -1           ## a runtime ship id this view does not draw (-1 = draw all)
var ship_nodes := {}        ## runtime id -> ShipNode
var bolt_nodes := {}        ## projectile uid -> Node3D (from ShipKit.build_bolt)
var _fx: Array = []         ## { node, t, life, size }


func _init(ship_kit: ShipKit = null) -> void:
	name = "DogfightView"
	kit = ship_kit if ship_kit != null else ShipKit.new()


## Draw the director's ships and bolts where they are now.
func sync(df) -> void:
	_sync_ships(df)
	_sync_bolts(df)


func _sync_ships(df) -> void:
	for s in df.ships:
		if s.id == skip_id or s.get("unseen", false):
			continue                # (a LAN guest's ship in the host's fight is their RemoteShip)
		var node = ship_nodes.get(s.id)
		if node == null:
			node = ShipNode.new()
			add_child(node)
			node.setup(kit, s.look, s.id, s.team)
			if s.get("is_player", false):
				kit.dress(node.visual, ShipUpgrades.fitted(str(s.ship_id)))
			ship_nodes[s.id] = node
		node.sync(s.flight, s.alive)


func _sync_bolts(df) -> void:
	var live := {}
	for p in df.projectiles.items:
		live[p.uid] = true
		var mi = bolt_nodes.get(p.uid)
		if mi == null:
			var style := "missile" if p.kind == "missile" else ("player" if p.team == Dogfight.TEAM_PLAYER else "hostile")
			mi = kit.build_bolt(style)
			add_child(mi)
			bolt_nodes[p.uid] = mi
		var v: Vector3 = p.vel
		if v.length_squared() > 0.0001:
			var up := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.BACK
			mi.global_transform = Transform3D(Basis.looking_at(v, up), p.pos)
	for uid in bolt_nodes.keys():
		if not live.has(uid):
			bolt_nodes[uid].queue_free()
			bolt_nodes.erase(uid)


## Flashes for the director's hits, an explosion for each kill, and (issue #16) the sound of
## every gun, missile, hit and kill where it happened.
func on_event(e: Dictionary) -> void:
	match str(e.type):
		"shot":
			Sound.play("ship_laser", e.at)
		"missile":
			Sound.play("ship_missile", e.at)
		"hit":
			flash(e.point, 1.2 if e.kind == "bolt" else 4.0, 0.15, Color("#ffd28a"))
			if e.kind == "bolt":
				ExplosionFx.bolt(self, e.point)
			elif float(e.get("blast_size", 0.0)) > 0.0:
				# A seeker goes up like a ship does (its splash is the "splash" hits).
				ExplosionFx.big(self, e.point, float(e.blast_size), true)
				Sound.play("vehicle_boom", e.point)
			else:
				ExplosionFx.small(self, e.point)
			Sound.play("ship_hit", e.point)
		"kill":
			Sound.play("vehicle_boom", e.point)
			ExplosionFx.big(self, e.point, 1.2, true)


func flash(point: Vector3, size: float, life: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 6.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = point
	mi.scale = Vector3.ONE * size * 0.3
	_fx.append({ "node": mi, "t": 0.0, "life": life, "size": size })


## Grow and fade the flashes.
func tick(dt: float) -> void:
	var keep: Array = []
	for f in _fx:
		f.t += dt
		var k: float = f.t / f.life
		if k >= 1.0:
			f.node.queue_free()
			continue
		f.node.scale = Vector3.ONE * f.size * (0.3 + k)
		var m: StandardMaterial3D = f.node.material_override
		m.albedo_color.a = 1.0 - k
		keep.append(f)
	_fx = keep
