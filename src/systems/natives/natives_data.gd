class_name NativesData
extends RefCounted
## Issue #96: the native peoples and wild animals of a planet, as data. Pure.
##
## A people is content/core/species/<id>.json (the dune people of the home planet,
## or a template like desert_folk that each generated planet turns into its own
## people). An animal is content/core/fauna/<id>.json. A planet gets them the way
## it gets everything else from the planet generator:
##
##   - its own config's "natives" block, if it has one (the home planet's packs,
##     routes and animals are written out there), or
##   - its type's "natives" block (content/core/planets/types.json): which people
##     template, how many packs, how hostile, how far out they roam, and which
##     animals and how many; laid out here from the planet's seed, so the same
##     planet always has the same packs, and no two planets share a people.
##
## resolve() returns { people: { id, label, data }, packs: [ { id, attitude, size,
## children, style, route: [Vector2 map points], camp: { at: Vector2, stop_after } } ], fauna: [ { species, count,
## around: Vector2, radius } ] }, or {} for a planet with none. Planets with no
## breathable ground (platform and ball types) get none.

const SPECIES_DIR := "res://content/core/species/"
const FAUNA_DIR := "res://content/core/fauna/"

static var _cache: Dictionary = {}


## A people's data, with its "base" filled in (a template lists only what differs).
static func species(id: String) -> Dictionary:
	if id == "":
		return {}
	var key := "species:" + id
	if _cache.has(key):
		return _cache[key]
	var d: Dictionary = _read(SPECIES_DIR + id + ".json")
	var base := str(d.get("base", ""))
	if base != "" and base != id:
		d = _merged(species(base), d)
	_cache[key] = d
	return d


static func fauna(id: String) -> Dictionary:
	var key := "fauna:" + id
	if not _cache.has(key):
		_cache[key] = _read(FAUNA_DIR + id + ".json")
	return _cache[key]


## Everything native to a planet (see the top of this file). `town_rect` keeps
## generated routes out of the town (x, z).
static func resolve(planet_id: String, cfg: Dictionary, tcfg: Dictionary, seed: int, town_rect: Rect2 = Rect2()) -> Dictionary:
	var own = cfg.get("natives", null)
	if own is bool and not own:
		return {}
	if own is Dictionary and not (own as Dictionary).is_empty():
		return _authored(planet_id, own)
	var gen: Dictionary = tcfg.get("natives", {})
	if gen.is_empty() or str(tcfg.get("ground", "terrain")) != "terrain":
		return {}
	return _generated(planet_id, gen, seed, town_rect)


static func _authored(planet_id: String, n: Dictionary) -> Dictionary:
	var sid := str(n.get("species", ""))
	var data := species(sid)
	var packs: Array = []
	for p in n.get("packs", []):
		var q: Dictionary = (p as Dictionary).duplicate(true)
		q["route"] = (p.get("route", []) as Array).map(func(a): return Vector2(float(a[0]), float(a[1])))
		if q.get("camp") is Dictionary and q.camp.has("at"):
			var at: Array = q.camp.at
			q.camp["at"] = Vector2(float(at[0]), float(at[1]))
		packs.append(q)
	var fa: Array = []
	for f in n.get("fauna", []):
		var g: Dictionary = (f as Dictionary).duplicate(true)
		var ar: Array = f.get("around", [0, 0])
		g["around"] = Vector2(float(ar[0]), float(ar[1]))
		fa.append(g)
	return { "planet": planet_id, "people": { "id": sid, "label": str(data.get("label", sid)), "data": data }, "packs": packs, "fauna": fa,
		"locals_say": n.get("locals_say", []) }


## A generated planet: its own people from the type's template, packs on loops
## round the town at the type's distances, half or so hostile, and its animals.
static func _generated(planet_id: String, gen: Dictionary, seed: int, town_rect: Rect2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 92821 + 96
	var template := str(gen.get("people", ""))
	var data := species(template).duplicate(true)
	var out := { "planet": planet_id, "packs": [], "fauna": [] }
	if not data.is_empty():
		var label := str(data.get("label", template))
		var who := ""
		if WorldState.names != null:
			who = WorldState.names.name_for("town", "people:" + planet_id)
		if who != "":
			label = "the %s folk" % who
		data["label"] = label
		# Its own looks: the template's styles in an order of the planet's own.
		var styles: Array = (data.get("styles", []) as Array).duplicate()
		for i in range(styles.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = styles[i]
			styles[i] = styles[j]
			styles[j] = t
		data["styles"] = styles
		out["people"] = { "id": planet_id + "_people", "label": label, "data": data }
		var cnt: Array = gen.get("packs", [2, 3])
		var n := rng.randi_range(int(cnt[0]), int(cnt[1]))
		var size: Array = gen.get("pack_size", [10, 20])
		var far: Array = gen.get("route_radius", [500.0, 1400.0])
		var hostile := float(gen.get("hostile_share", 0.5))
		var kids := float(gen.get("children_share", 0.15))
		var adults_only := float(gen.get("adults_only_share", 0.25))
		for i in n:
			var s := rng.randi_range(int(size[0]), int(size[1]))
			var r := rng.randf_range(float(far[0]), float(far[1]))
			var a0 := TAU * float(i) / float(n) + rng.randf_range(-0.4, 0.4)
			var route: Array = []
			for k in 4:
				var a := a0 + k * 0.45
				var rr := r * rng.randf_range(0.85, 1.15)
				var m := Vector2(cos(a) * rr, sin(a) * rr)
				if town_rect.has_area() and town_rect.grow(120.0).has_point(m):
					m = m.normalized() * (town_rect.size.length() * 0.5 + 200.0)
				route.append(m)
			var no_kids := rng.randf() < adults_only
			out.packs.append({ "id": "%s_pack_%d" % [planet_id, i + 1],
				"attitude": "hostile" if rng.randf() < hostile else "friendly",
				"size": s, "children": 0 if no_kids else int(round(s * kids)),
				"style": str(styles[i % maxi(styles.size(), 1)].get("id", "")) if not styles.is_empty() else "",
				"route": route,
				# Its camp halfway between the end of its loop and the start: a stop
				# on every loop (only built when the people make camps).
				"camp": { "at": (route[route.size() - 1] as Vector2).lerp(route[0], 0.5), "stop_after": route.size() - 1 } })
	for f in gen.get("fauna", []):
		out.fauna.append({ "species": str(f.get("species", "")), "count": int(f.get("count", 4)),
			"around": Vector2.ZERO, "radius": float(f.get("radius", 900.0)) })
	if out.packs.is_empty() and out.fauna.is_empty():
		return {}
	return out


static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = _merged(out[k], over[k])
		else:
			out[k] = over[k]
	return out


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
