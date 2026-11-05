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
##   neighbours-- other planets in its sky you can fly to: { id, at, offset, radius, color... },
##                all placed from one system frame (issue #573: system_centre)
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
		var all: Dictionary = _types.get("types", {})
		for id in all.keys():
			all[id] = _with_base(all, str(id), [])
	return _types


## Issue #272: a type may name a "base" type and give only what differs (the lava
## moon is the asteroid with other rock, lava and sky). Dictionaries merge key by
## key, all the way down; anything else (numbers, arrays) replaces.
static func _with_base(all: Dictionary, id: String, seen: Array) -> Dictionary:
	var t: Dictionary = all.get(id, {})
	var base := str(t.get("base", ""))
	if base == "" or seen.has(id) or not all.has(base):
		return t
	var merged := _deep_merge(_with_base(all, base, seen + [id]), t)
	merged.erase("base")
	merged["base_type"] = base
	return merged


static func _deep_merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.get(k) is Dictionary and b[k] is Dictionary:
			out[k] = _deep_merge(out[k], b[k])
		else:
			out[k] = b[k] if not (b[k] is Dictionary or b[k] is Array) else b[k].duplicate(true)
	return out


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
	if str(tcfg.get("ground", "")) == "none":
		return _make_open_space(id, cfg, type, tcfg, cc)
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
	elif cfg.has("station_town"):
		# The planet's town is a space station's bay (the ringed giant): its
		# "station" landmark named here; no deck, no wall, no cantina.
		town_id = id + "_town"
		var slm: Dictionary = {}
		for lm in cfg.get("landmarks", []):
			if str(lm.get("id", "")) == str(cfg.station_town):
				slm = lm
		var sr := float(tcfg.get("surface", {}).get("radius", tcfg.get("body", {}).get("radius", 1500.0)))
		town = StationHull.town_for(town_id, slm, PlanetSphere.new(sr), { "planet": id })
		if town.is_empty():
			push_warning("PlanetGen: %s has no station landmark %s" % [id, str(cfg.station_town)])
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
		if cfg.has("domes"):
			opts["domes"] = cfg.domes              # a sealed station's other domes, off its landing pit
		town = TownGen.generate(town_id, size, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), opts)
	var world: Dictionary = {}
	if cfg.has("world"):
		world = CoreContent.resolve_layout(cc.get_world(str(cfg.world)), layout)    # issue #295: landmarks per layout
	else:
		world = _world_for(id, town_id, tcfg)
	if cfg.has("landmarks"):
		# A planet config's own landmarks join its world's (a space station over the
		# moon: content/core/stations/). Moving one to another planet is moving the block.
		world = world.duplicate()
		world["landmarks"] = (world.get("landmarks", []) as Array) + (cfg.landmarks as Array)
	world["ground"] = str(tcfg.get("ground", "terrain"))
	world["planet"] = id
	var style := str(cfg.get("style", tcfg.get("default_style", "desert")))
	# Issue #96: its native people and wild animals, from its own config or its type.
	var bd: Dictionary = town.get("bounds", {})
	var trect := Rect2()
	if not bd.is_empty():
		trect = Rect2(float(bd.min[0]), float(bd.min[1]), float(bd.max[0]) - float(bd.min[0]), float(bd.max[1]) - float(bd.min[1]))
	var natives := NativesData.resolve(id, cfg, tcfg, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), trect)
	var near := neighbours(id, cc, cfg)
	return {
		"id": id,
		"cfg": cfg,
		"type": type,
		"type_cfg": tcfg,
		"ground": str(tcfg.get("ground", "terrain")),
		"deck": bool(tcfg.get("deck", false)) and not cfg.has("station_town"),   # a town on a floating deck
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


## Issue #573: open space, a place with no planet (ground "none"). Its town is
## only the ship's pad and a spot to stand (hidden: the flight never leaves the
## seat out here), so the ship, pilot and HUD build as anywhere else; no natives,
## no people. Its world has no terrain and its atmosphere is all space.
static func _make_open_space(id: String, cfg: Dictionary, type: String, tcfg: Dictionary, cc) -> Dictionary:
	var town_id := id + "_town"
	var town := {
		"id": town_id,
		"boxes": [
			{ "id": "spawn_plate", "kind": "floor", "zone": "ground", "min": [-2.0, -0.2, -2.0], "max": [2.0, 0.0, 2.0], "hidden": true },
			{ "id": "ship", "kind": "ship", "zone": "ground", "min": [6.0, 0.0, -9.0], "max": [24.0, 5.0, 9.0], "hidden": true },
		],
		"markers": [ { "id": "player_spawn", "role": "spawn", "pos": [0.0, 0.0, 0.0] } ],
		"zones": [],
	}
	var world := {
		"id": id,
		"label": str(tcfg.get("label", id)),
		"town": town_id,
		"naming": { "town": "town", "planet": "planet" },
		"terrain": {},
		"landmarks": [],
		"atmosphere": tcfg.get("atmosphere", {}),
		"detail": types().get("detail", {}),
		"ground": "none",
		"planet": id,
	}
	var near := neighbours(id, cc)
	# WorldGround: altitude and up out here ([centre, radius, flat_radius, up_blend,
	# bubble], as each ball's own up; bubble: where its scene lets go, from its centre).
	world["void_bodies"] = near.map(func(n):
		var surf: Dictionary = types().get("types", {}).get(str(n.type), {}).get("surface", {})
		var ball := str(types().get("types", {}).get(str(n.type), {}).get("ground", "")) == "ball"
		var bubble := bubble_radius(str(n.id), true, cc)
		return [n.at, float(n.radius), float(surf.get("flat_radius", 130.0 if ball else 350.0)),
			float(surf.get("up_blend", 160.0 if ball else 450.0)), bubble if bubble > 0.0 else float(n.radius)])
	return {
		"id": id, "cfg": cfg, "type": type, "type_cfg": tcfg, "ground": "none", "deck": false,
		"size": 1, "town_id": town_id, "town": town, "world": world, "style": str(tcfg.get("default_style", "metallic")),
		"sky": tcfg.get("sky", {}), "features": [], "cantina": {}, "encounter": null,
		"name": str(cfg.get("name", "")), "town_name": "", "neighbours": near, "sky_painting": sky_painting(cfg, near),
		"natives": {}, "beast": {}, "barge": {}, "harmful_surface": {},
	}


# ------------------------------------------------------------------ the system frame (issue #573)

## Issue #573: the type data's "space" block (open space's id, hysteresis, margins).
static func space_cfg() -> Dictionary:
	return types().get("space", {})


## Open space's planet id.
static func open_space_id() -> String:
	return str(space_cfg().get("open_space", "open_space"))


static func is_open_space(id: String) -> bool:
	return id != "" and id == open_space_id()


## True for a place you can fly to and be on: not open space (ground "none").
static func is_planet(id: String, cc = null) -> bool:
	if cc == null:
		cc = _content()
	var cfg: Dictionary = cc.planets.get(id, {})
	return not cfg.is_empty() and str(types().get("types", {}).get(str(cfg.get("type", "")), {}).get("ground", "")) != "none"


## Metres past a bubble before leaving it (so the edge does not flip-flop).
static func hysteresis() -> float:
	return float(space_cfg().get("hysteresis", 300.0))


## A planet's bubble (from its centre, metres): its radius plus its handoff; 0
## for a planet with none. `leaving` adds the hysteresis.
static func bubble_radius(id: String, leaving := false, cc = null) -> float:
	if cc == null:
		cc = _content()
	var cfg: Dictionary = cc.planets.get(id, {})
	var h := handoff_altitude(str(cfg.get("type", "")))
	if cfg.is_empty() or h <= 0.0:
		return 0.0
	return ball_radius(cfg, cc) + h + (hysteresis() if leaving else 0.0)


## A planet's ball centre in the system frame, or null when it is not in it. The
## system frame is the home planet's scene: its port is the origin, so its centre
## is straight under it; every other planet's centre is its "at" from the port of
## the planet it is "near", to any depth. Every scene is this frame shifted to its
## own port (never turned), so the sun and stars agree in all of them.
static func system_centre(id: String, cc = null, depth := 0):
	if cc == null:
		cc = _content()
	var cfgs: Dictionary = cc.planets
	var cfg: Dictionary = cfgs.get(id, {})
	if cfg.is_empty() or not is_planet(id, cc):
		return null
	if id == home_id():
		return Vector3(0, -ball_radius(cfg, cc), 0)
	var near := str(cfg.get("near", ""))
	if depth >= 8 or not cfgs.has(near) or not cfg.has("at"):
		return null
	var pc = system_centre(near, cc, depth + 1)
	if pc == null:
		return null
	return (pc as Vector3) + Vector3(0, ball_radius(cfgs[near], cc), 0) + GameFlow.vec(cfg.at)


## Where a place's own origin (a planet's port, on top of its ball) is in the
## system frame: open space's is the system frame's own origin. INF when the
## place is not in the system.
static func system_port(id: String, cc = null) -> Vector3:
	if is_open_space(id):
		return Vector3.ZERO
	if cc == null:
		cc = _content()
	var c = system_centre(id, cc)
	if c == null:
		return Vector3.INF
	return (c as Vector3) + Vector3(0, ball_radius(cc.planets.get(id, {}), cc), 0)


## The system-frame port of a planet config that is not in the manifest (a test,
## a contributor trying one out): its "at" from the planet it is near.
static func _cfg_port(cfg: Dictionary, cc) -> Vector3:
	var near := str(cfg.get("near", ""))
	var pc = system_centre(near, cc)
	if pc == null or not cfg.has("at"):
		return Vector3.INF
	var r := ball_radius(cfg, cc)
	return (pc as Vector3) + Vector3(0, ball_radius(cc.planets[near], cc), 0) + GameFlow.vec(cfg.at) + Vector3(0, r, 0)


## A world dict for a generated planet: the same shape as content/core/worlds.
static func _world_for(id: String, town_id: String, tcfg: Dictionary) -> Dictionary:
	var platform := str(tcfg.get("ground", "terrain")) in ["platform", "sphere"]
	var surface: Dictionary = tcfg.get("surface", {})
	if str(tcfg.get("ground", "")) == "ball":
		# Issue #99: a real ball like the home planet (WorldTerrain asks the sphere).
		var w := {
			"id": id,
			"label": str(tcfg.get("label", id)),
			"town": town_id,
			"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
			"terrain": { "sphere_radius": float(surface.get("radius", 1500.0)) },
			"landmarks": [],
			"atmosphere": tcfg.get("atmosphere", {}),
			"detail": types().get("detail", {}),
		}
		if str(surface.get("kind", "")) == "gas":
			# A gas ball: this far below the deck's level a ship is in the clouds, lost.
			w["lethal_below"] = -float(surface.get("lethal_depth", 60.0))
		return w
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


## The planets you can fly to from place `id`: every other planet, where it hangs
## in this place's sky: "at" is the centre of its ball and "offset" its port, in
## metres from this place's own origin (its port; open space's is the system
## frame's origin).
##
## Issue #99: one map. Every place's scene is the same space, only shifted so its
## own origin is the origin (no turn, so the sun and the stars are the same in all
## of them): a point p here is p - offset in that planet's scene. Issue #573: all
## of it read from one system frame (system_centre, system_port), so a moon sees its
## sister moon and its grandparent the same way it sees its parent; "child" is a
## planet that is near this one, "parent" the one this one is near. Open space is
## never a neighbour.
static func neighbours(id: String, cc = null, own_cfg: Dictionary = {}) -> Array:
	if cc == null:
		cc = _content()
	var out: Array = []
	var all: Dictionary = cc.planets
	var mine: Dictionary = all.get(id, own_cfg)
	var here := system_port(id, cc) if all.has(id) or is_open_space(id) else _cfg_port(mine, cc)
	if here == Vector3.INF:
		return out
	for other in all:
		if other == id:
			continue
		var c = system_centre(str(other), cc)
		if c == null:
			continue
		var o: Dictionary = all[other]
		var n := _neighbour(o, (c as Vector3) - here, cc)
		n["offset"] = system_port(str(other), cc) - here
		n["child"] = str(o.get("near", "")) == id
		n["parent"] = str(mine.get("near", "")) == str(other)
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
		"haze": body.get("haze", {}),                     # a gas ball's air: SpaceTravel.make_haze
		"relief": str(body.get("relief", "")),            # its dunes as a flat print (a cubemap), or ""
		"relief_tilt": float(body.get("relief_tilt", 1.0)),
		"relief_crest": float(body.get("relief_crest", 0.12)),
		"sky_giant": bool(o.get("replaces_sky_painting", false)),
		# A gas ball's cloud tops, below its deck's level (radius): what you see of it.
		"cloud_radius": r - float(t.get("surface", {}).get("depth", 0.0)) if ball and str(t.get("surface", {}).get("kind", "")) == "gas" else r,
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
