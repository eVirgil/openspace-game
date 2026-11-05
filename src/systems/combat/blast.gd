class_name Blast
extends RefCounted
## Issue #372: a burst that wrecks everything round it. The grenade's, and built to
## be any explosion's (a mine, a charge, a barrel): one call with a config.
##
## Everyone within `blast_radius` takes `blast_damage`, the same at any distance:
## people through apply_blast when they have it (NpcBody: the dead are flung away
## from the burst) or the hit they already take from a bolt, so the town alarm,
## standing and kill rewards work as for any shot. Droids, speeders and the party
## barge are destroyed (`vehicle_damage`, the barge through its own explode()).
## The player and the player's droids are hurt too (`player_damage`, and the
## droid takes the blast like anyone). Parked ships and cruiser hulls are left alone.
##
## cfg keys (content/core/weapons/grenade.json): blast_radius, blast_damage,
## vehicle_damage, player_damage, blast_size, noise_radius.

const MAX_HITS := 128


## The fireball, the boom and the noise at `at`, then the damage. `host` is the
## node the effects go under (the town); `shooter` who threw it (the player);
## `player` the local player (friendly fire). Returns each thing it hurt.
static func burst(host: Node, at: Vector3, cfg: Dictionary, shooter: Node, player: Node = null) -> Array:
	if host != null and host.is_inside_tree():
		ExplosionFx.big(host, at, float(cfg.get("blast_size", 0.7)))
		Sound.play("vehicle_boom", at)
	NoiseEvents.emit(at, float(cfg.get("noise_radius", 90.0)), "explosion")
	var world: World3D = (host as Node3D).get_world_3d() if host is Node3D and host.is_inside_tree() else null
	if world == null:
		return []
	return damage(world.direct_space_state, at, cfg, shooter, player)


## Only the damage: everything within the radius of `at`. Returns what it hurt.
static func damage(space: PhysicsDirectSpaceState3D, at: Vector3, cfg: Dictionary, shooter: Node, player: Node = null) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(cfg.get("blast_radius", 6.0))
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collide_with_areas = false
	var seen := {}
	var out: Array = []
	for r in space.intersect_shape(q, MAX_HITS):
		var t := target(r.collider)
		if t == null or seen.has(t.get_instance_id()):
			continue
		seen[t.get_instance_id()] = true
		if hit(t, at, cfg, shooter, player):
			out.append(t)
	return out


## What a collider stands for: the party barge (anything on it), a speeder (its
## hull's parent), or whatever takes damage (the collider or its parent). null for
## walls, the ground, ships' hulls.
static func target(c: Object) -> Object:
	if c == null or c is ShipHull:
		return null
	var n: Node = c as Node
	var depth := 0
	while n != null and depth < 6:
		if n is PartyBarge:
			return n
		if n is SpeederNode:
			return n
		n = n.get_parent()
		depth += 1
	if c.has_method("apply_damage"):
		return c
	var p: Node = (c as Node).get_parent() if c is Node else null
	if p != null and p.has_method("apply_damage") and not p is ShipHull:
		return p
	return null


## Hurt one target. Returns whether it took anything.
static func hit(t: Object, at: Vector3, cfg: Dictionary, shooter: Node, player: Node = null) -> bool:
	var dmg := float(cfg.get("blast_damage", 400.0))
	var wreck := float(cfg.get("vehicle_damage", 5000.0))
	if t is PartyBarge:
		if (t as PartyBarge).wrecked:
			return false
		(t as PartyBarge).explode()
		return true
	if t is SpeederNode:
		(t as SpeederNode).apply_damage(wreck)
		return true
	if player != null and t == player:
		if "last_hit_from" in t:
			t.last_hit_from = at
		t.apply_damage(float(cfg.get("player_damage", 60.0)))
		return true
	if t.has_method("apply_blast"):
		t.apply_blast(dmg, at, shooter, wreck, float(cfg.get("blast_radius", 6.0)))
		return true
	if t.has_method("apply_damage_from"):
		t.apply_damage_from(dmg, shooter)
		return true
	if t.has_method("apply_damage"):
		t.apply_damage(dmg)
		return true
	return false
