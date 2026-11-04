class_name PlanetGen
extends RefCounted
## The planet generator (issue #45). A planet is one small file,
## content/core/planets/<id>.json (name, type, town_size, style, where it hangs in
## a neighbour's sky); this turns it into everything the town scene builds:
##
##   town      -- the layout (TownGen at its town_size, or an authored town: a saved
##                layout from content/core/towns/ named by town_layout, issue #237)
##   world     -- the world dict ShipPilot, the sky and the detail tiers read
##                (an authored world, or one made from the planet's type)
##   type_cfg  -- content/core/planets/types.json for its type: ground (terrain,
##                platform or sphere), sand and rock colours, the sea / lava / gas / rock under
##                a platform, sky colours, atmosphere, how it looks from space
##   style     -- the town style (TownStyle spec: a preset or words)
##   sky       -- values laid over every time-of-day preset
##   neighbours-- other planets in its sky you can fly to: { id, at, radius, color... }
##   cantina   -- who runs the cantina { card, look }
##   natives   -- issue #96: its native packs and wild animals (NativesData.resolve)
##   beast     -- its beast, if it has one: the "beast" block of its file ({} if none;
##                PlanetBeast.config lays it over content/core/hazards/beast.json)
##   harmful_surface -- issue #298: you can't breathe on its surface without
##                armour ({} = fine): the planet's own block, else its type's
##   barge     -- issue #269: its party barge, if it has one: the "barge" block of its
##                file ({} if none; PartyBarge.config lays it over
##                content/core/barges/party_barge.json)
##
## Pure and cheap: no nodes. Town scenes ask for the current planet
## (GameFlow.planet()); tests can build any planet without a scene.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TYPES_PATH := "res://content/core/planets/types.json"

static var _types: Dictionary = {}
static var _cache: Dictionary = {}       ## planet id -> built planet (built once per run)
static var layout_override: Dictionary = {}   ## issue #237: planet id -> town layout picked in F11 (this run only)


static func types() -> Dictionary:
	if _types.is_empty():
		_types = TownGen._read(TYPES_PATH)
	return _types


static func home_id() -> String:
	return str(types().get("home", "port_desert"))


## Every planet id in the manifest.
static func ids(content = null) -> Array:
	var cc = content if content != null else _content()
	return cc.planets.keys()


## A planet, built (cached: the same planet is the same dictionary all run).
static func build(planet_id: String, content = null) -> Dictionary:
	if _cache.has(planet_id):
		return _cache[planet_id]
	var cc = content if content != null else _content()
	var cfg: Dictionary = cc.planets.get(planet_id, {})
	if cfg.is_empty():
		push_warning("PlanetGen: unknown planet " + planet_id)
		return {}
	var p := make(cfg, cc)
	_cache[planet_id] = p
	return p


## Issue #237: the saved town layouts a planet with an authored town can pick.
static func layouts(content = null) -> Array:
	var cc = content if content != null else _content()
	return cc.towns.keys()


## Issue #237: build `planet_id`'s town to `layout` for the rest of this run
## (F11). "" goes back to the layout its file names.
static func set_layout(planet_id: String, layout: String) -> void:
	if layout == "":
		layout_override.erase(planet_id)
	else:
		layout_override[planet_id] = layout
	_cache.erase(planet_id)


## Build from a config dictionary (also for configs not in the manifest: tests,
## a contributor trying one out).
static func make(cfg: Dictionary, cc = null) -> Dictionary:
	if cc == null:
		cc = _content()
	var id := str(cfg.get("id", "planet"))
	var type := str(cfg.get("type", "sand"))
	var tcfg: Dictionary = types().get("types", {}).get(type, {})
	if tcfg.is_empty():
		push_warning("PlanetGen: unknown planet type %s (%s); using sand" % [type, id])
		type = "sand"
		tcfg = types().types.sand
	var size := clampi(int(cfg.get("town_size", 50)), 1, 100)
	var town_id := str(cfg.get("town", ""))
	var town: Dictionary = {}
	var layout := str(layout_override.get(id, cfg.get("town_layout", "")))
	if town_id != "" and layout != "":
		# Issue #237: an authored town built to a saved layout (content/core/towns/).
		town = cc.town_from_layout(layout, town_id)
		var lsize := int(town.get("size", size))
		if lsize != size and not layout_override.has(id):
			push_warning("PlanetGen: %s wants town_size %d but layout %s is size %d" % [id, size, layout, lsize])
		size = lsize
	elif town_id != "":
		town = cc.get_location(town_id)            # authored
	else:
		town_id = id + "_town"
		var opts := {}
		var co: Dictionary = cfg.get("cantina_owner", {})
		if co.has("card"):
			opts["cantina_card"] = str(co.card)
		if co.has("look"):
			opts["cantina_look"] = str(co.look)
		if not co.has("card"):
			opts["cantina_planet"] = id          # issue #75: her own Oda (PlanetOwner)
		if str(tcfg.get("landing_bay", "")) == "pit":
			opts["bay"] = "pit"
		if bool(tcfg.get("enclosed", false)):
			opts["ring"] = tcfg.get("station", {})      # issue #99: a sealed, round station
		if bool(cfg.get("stage_dancer", false)):
			opts["stage_dancer"] = true
		if cfg.has("club_dome"):
			opts["club_dome"] = cfg.club_dome      # issue #261: the whole dome is the club
		town = TownGen.generate(town_id, size, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), opts)
	var world: Dictionary = {}
	if cfg.has("world"):
		world = CoreContent.resolve_layout(cc.get_world(str(cfg.world)), layout)    # issue #295: landmarks per layout
	else:
		world = _world_for(id, town_id, tcfg)
	world["ground"] = str(tcfg.get("ground", "terrain"))
	world["planet"] = id
	var style := str(cfg.get("style", tcfg.get("default_style", "desert")))
	# Issue #96: its native people and wild animals, from its own config or its type.
	var bd: Dictionary = town.get("bounds", {})
	var trect := Rect2()
	if not bd.is_empty():
		trect = Rect2(float(bd.min[0]), float(bd.min[1]), float(bd.max[0]) - float(bd.min[0]), float(bd.max[1]) - float(bd.min[1]))
	var natives := NativesData.resolve(id, cfg, tcfg, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), trect)
	var near := neighbours(id, cc)
	return {
		"id": id,
		"cfg": cfg,
		"type": type,
		"type_cfg": tcfg,
		"ground": str(tcfg.get("ground", "terrain")),
		"size": size,
		"town_id": town_id,
		"town": town,
		"world": world,
		"style": style,
		"sky": tcfg.get("sky", {}),
		"features": cfg.get("features", []),
		"cantina": cfg.get("cantina_owner", {}),
		"encounter": cfg.get("encounter", null),
		"name": str(cfg.get("name", "")),
		"town_name": str(cfg.get("town_name", "")),
		"neighbours": near,
		"sky_painting": sky_painting(cfg, near),
		"natives": natives,
		"beast": cfg.get("beast", {}),
		"barge": cfg.get("barge", {}),
		"harmful_surface": cfg.get("harmful_surface", tcfg.get("harmful_surface", {})),
	}


## A world dict for a generated planet: the same shape as content/core/worlds.
static func _world_for(id: String, town_id: String, tcfg: Dictionary) -> Dictionary:
	var platform := str(tcfg.get("ground", "terrain")) in ["platform", "sphere"]
	var surface: Dictionary = tcfg.get("surface", {})
	if str(tcfg.get("ground", "")) == "ball":
		# Issue #99: a real ball like the home planet (WorldTerrain asks the sphere).
		return {
			"id": id,
			"label": str(tcfg.get("label", id)),
			"town": town_id,
			"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
			"terrain": { "sphere_radius": float(surface.get("radius", 1500.0)) },
			"landmarks": [],
			"atmosphere": tcfg.get("atmosphere", {}),
			"detail": types().get("detail", {}),
		}
	return {
		"id": id,
		"label": str(tcfg.get("label", id)),
		"town": town_id,
		"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
		"terrain": {
			"extent": 0.0 if platform else 6000.0,
			"skirt_height": -float(surface.get("depth", 160.0)) if platform else 4.0,
			"flat_height": -float(surface.get("depth", 160.0)) if platform else 0.0,
			"planet_radius": 60000.0,
			"curve_from": 6000.0,
		},
		"landmarks": [],
		"atmosphere": tcfg.get("atmosphere", {}),
		"detail": types().get("detail", {}),
	}


## The planets you can fly to from `id`: the ones that name it as "near" (where
## they hang in its sky is their "at": the centre of their ball, in metres from
## this planet's port), and the one it is near itself.
##
## Issue #99: one map. Every planet's scene is the same space, only shifted so its
## own port is the origin (no turn, so the sun and the stars are the same in all
## of them). A planet's port sits on top of its ball, so a neighbour's port is at
## `offset` = its centre + (0, its radius, 0) here; a point p here is p - offset
## in its scene. Seen from a child, its parent's centre is (0, -parent radius, 0)
## minus the child's own offset, exactly: nothing is mirrored or scaled any more.
static func neighbours(id: String, cc = null) -> Array:
	if cc == null:
		cc = _content()
	var out: Array = []
	var all: Dictionary = cc.planets
	var mine: Dictionary = all.get(id, {})
	for other in all:
		if other == id:
			continue
		var o: Dictionary = all[other]
		if str(o.get("near", "")) == id and o.has("at"):
			var at := GameFlow.vec(o.at)
			var n := _neighbour(o, at, cc)
			n["offset"] = at + Vector3(0, float(n.radius), 0)
			n["child"] = true
			out.append(n)
	if str(mine.get("near", "")) != "" and all.has(str(mine.near)):
		var home: Dictionary = all[str(mine.near)]
		var my_offset := GameFlow.vec(mine.get("at", [0, 0, -20000])) + Vector3(0, ball_radius(mine, cc), 0)
		var n := _neighbour(home, Vector3.ZERO, cc)
		n["at"] = Vector3(0, -float(n.radius), 0) - my_offset
		n["offset"] = -my_offset
		n["child"] = false
		out.append(n)
	return out


## A planet's radius: its ball's (the world's sphere_radius, or a ball type's
## surface radius), else how big it looks from a neighbour's sky (body.radius).
static func ball_radius(o: Dictionary, cc = null) -> float:
	var t: Dictionary = types().get("types", {}).get(str(o.get("type", "sand")), {})
	if o.has("world") and cc != null:
		var r := float(cc.get_world(str(o.world)).get("terrain", {}).get("sphere_radius", 0.0))
		if r > 0.0:
			return r
	if str(t.get("ground", "")) == "ball":
		return float(t.get("surface", {}).get("radius", 1500.0))
	var ob: Dictionary = o.get("body", {})
	return float(o.get("body_radius", ob.get("radius", t.get("body", {}).get("radius", 1000.0))))


## How close to a planet's surface its own scene takes over (issue #99), or 0 when
## it never hands over seamlessly (its parent's scene fades to it, as before).
static func handoff_altitude(type: String) -> float:
	return float(types().get("types", {}).get(type, {}).get("space", {}).get("handoff", 0.0))


static func _neighbour(o: Dictionary, at: Vector3, cc) -> Dictionary:
	var t: Dictionary = types().get("types", {}).get(str(o.get("type", "sand")), {})
	var body: Dictionary = t.get("body", {}).duplicate()
	body.merge(o.get("body", {}), true)          # the planet's own look from space wins
	# Issue #77: a planet that is a real ball (its world's terrain.sphere_radius)
	# looks its true size from a neighbour's sky. Issue #99: so does a ball type.
	var r := ball_radius(o, cc)
	var ball := str(t.get("ground", "")) == "ball"
	if o.has("world") and cc != null:
		ball = ball or float(cc.get_world(str(o.world)).get("terrain", {}).get("sphere_radius", 0.0)) > 0.0
	return {
		"id": str(o.get("id", "")),
		"type": str(o.get("type", "sand")),
		"at": at,
		"ball": ball,
		"radius": r,
		"color": Color(str(body.get("color", "#a08060"))),
		"dark": Color(str(body.get("dark", "#504030"))),
		"bands": float(body.get("bands", 0.0)),          # > 0: banded like the sky painting
		"ring": body.get("ring", {}),                     # { inner, outer, color, normal }, radii
		"sky_giant": bool(o.get("replaces_sky_painting", false)),
	}


## False when the painted ringed giant must not show in this planet's sky: the
## planet is the real giant, or the real one hangs in its sky (a neighbour with
## replaces_sky_painting).
static func sky_painting(cfg: Dictionary, near: Array) -> bool:
	if bool(cfg.get("replaces_sky_painting", false)):
		return false
	for n in near:
		if bool(n.get("sky_giant", false)):
			return false
	return true


## Generated names: the planet's (and its town's) own "name" in the config wins,
## reserved in the name book so nothing else gets it; otherwise the name engine.
static func reserve_names(p: Dictionary, book: NameBook = null) -> void:
	var b := book if book != null else WorldState.names
	var world: Dictionary = p.get("world", {})
	if str(p.get("name", "")) != "":
		b.reserve(str(p.name), "planet:" + str(world.get("id", p.id)))
	if str(p.get("town_name", "")) != "":
		b.reserve(str(p.town_name), "town:" + str(world.get("town", p.town_id)))


## The planet's display name (generated or reserved).
static func display_name(p: Dictionary, book: NameBook = null) -> String:
	reserve_names(p, book)
	return NameHooks.planet(p.get("world", {}), book)


static func clear_cache() -> void:
	_cache = {}
	_types = {}


static func _content():
	var cc := CoreContent.new()
	cc.load_from()
	return cc
