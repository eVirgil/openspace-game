class_name GlobeMap
extends RefCounted
## The F11 Map page's places and the waypoint it sets. Pure and static, like
## Objective: it reads the world's data and WorldState, and the page (GlobeView)
## draws it.
##
## Only what stays put: the port, the world's landmarks (outposts, droid relays,
## traders, wrecks), the planet's native camps and, zoomed in, the port's own
## stops (the cantina, the ship dealer, the stalls). Each pin is
## { id, kind, label, map: Vector2, arrive, town }: map coordinates, metres along
## the ground from the port (PlanetSphere), so a pin sits exactly where the
## landmark is built.
##
## Who holds a place (Territory): the Remnant's outposts and the port's barracks
## also carry { owner, short, hold, status }. The globe draws what the locals hold
## green (yellow-green and "Resupply needed" while their supplies run short), a
## ring round a held outpost for the time left (`hold`, 0..1, -1 = none; issue
## #425: the Remnant's too once the cruiser has fallen, orange while they run
## short and you could resupply them), and
## `status` joins the name on hover. Read when the pins are built, which the page
## does each time it opens.
##
## Off planet: every planet you can fly to from here (SpaceTravel's bodies) and
## the Remnant cruiser when this world has one, as { id, kind, label, target }.
##
## The waypoint lives in WorldState.map_waypoint (saved): { id, label, target,
## planet, arrive }. One pointer at a time: setting it turns any quest's waypoint
## off, and switching a quest's on clears it (Quests.toggle_waypoint). Its target
## is a word ObjectiveHud.where understands: map:<x>,<z>, planet:<id>, cruiser.
##
## The page can also show somewhere you are not (GlobeMap.other_planet: another
## planet's ball, from its data; CruiserMapView: the Remnant cruiser's side view,
## cruiser_pins). A waypoint set there keeps its own planet: until you are on it
## the pointer leads to that planet ("planet:<id>"), then to the place itself.
##
## Every line and label: content/core/flow/map.json.

const PATH := "res://content/core/flow/map.json"
const LOOK_PATH := "res://content/look/map.json"
const LOCATION_DIR := "res://content/core/locations"
const VENDOR_DIR := "res://content/core/vendors"

static var _cfg: Dictionary = {}
static var _look: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = _read(PATH)
	return _cfg


static func look() -> Dictionary:
	if _look.is_empty():
		_look = _read(LOOK_PATH)
	return _look


static func line(key: String) -> String:
	return str(cfg().get("lines", {}).get(key, ""))


static func kind_cfg(kind: String) -> Dictionary:
	return cfg().get("kinds", {}).get(kind, {})


# ------------------------------------------------------------------ pins

## Every pin on this planet's surface. `world` is the scene's world (landmarks
## already laid out for its town), `planet` the planet (its native packs),
## `town` the port's own stops (town_pins).
static func pins(world: Dictionary, planet: Dictionary, town: Array = []) -> Array:
	var port := _pin("port", "port", _kind_label("port"), Vector2.ZERO)
	_stamp_owner(port, Territory.BARRACKS)
	var out: Array = [port]
	var skip: Array = cfg().get("skip", [])
	for lm in world.get("landmarks", []):
		var id := str(lm.get("id", ""))
		if id in skip or not lm.has("at"):
			continue
		var kind := str(lm.get("kind", ""))
		var label := ""
		if kind == "location":
			var loc := _location(str(lm.get("location", id)))
			kind = str(loc.get("kind", "post"))
			label = str(loc.get("label", ""))
		if kind_cfg(kind).is_empty() or kind in ["cruiser", "planet", "port"]:
			continue             # the cruiser is off planet; anything unnamed is not a place
		label = str(cfg().get("labels", {}).get(id, label if label != "" else _kind_label(kind)))
		var at: Array = lm.at
		var pin := _pin(id, kind, _cap(label), Vector2(float(at[0]), float(at[2])))
		if Story.OUTPOSTS.has(id):
			_stamp_owner(pin, id)
		out.append(pin)
	for pack in planet.get("natives", {}).get("packs", []):
		var camp = pack.get("camp", null)
		var at = camp.get("at", null) if camp is Dictionary else null
		if not (at is Array or at is Vector2):
			continue
		var p := _pin("camp_" + str(pack.id), "camp", str(cfg().get("camp_label", "%s")) % str(pack.get("label", pack.id)),
			at if at is Vector2 else Vector2(float(at[0]), float(at[1])))
		p["hostile"] = str(pack.get("attitude", "")) == "hostile"
		out.append(p)
	for t in town:
		out.append(t)
	return out


## The port's own stops in a built town: the data's markers and this town's
## vendors, each at its marker. `to_map` turns a world position into map (x, z).
static func town_pins(town, town_id: String, to_map: Callable) -> Array:
	var out: Array = []
	if town == null:
		return out
	var stops: Array = cfg().get("town", []).duplicate()
	for v in _vendors():
		if str(v.get("location", "")) == town_id:
			stops.append({ "marker": str(v.get("marker", "")), "kind": "vendor", "label": str(v.get("label", "")) })
	var seen := {}
	for s in stops:
		var m := str(s.get("marker", ""))
		if m == "" or seen.has(m) or town.get_marker(m).is_empty():
			continue
		seen[m] = true
		var p := _pin("town_" + m, str(s.get("kind", "vendor")), str(s.get("label", m)), to_map.call(town.marker_pos(m)))
		p["town"] = true
		out.append(p)
	return out


## A spot the player clicked on bare ground.
static func spot_pin(map: Vector2) -> Dictionary:
	return _pin("spot", "spot", line("marked"), map)


## The places off this planet: [{ id, kind, label, target }]. `bodies` are
## SpaceTravel's ({ id, name }).
static func off_planet(bodies: Array, world: Dictionary) -> Array:
	var out: Array = []
	for b in bodies:
		var label := str(b.get("name", ""))
		out.append({ "id": "planet_" + str(b.id), "kind": "planet",
			"label": label if label != "" else str(b.id).capitalize(), "target": "planet:" + str(b.id) })
	for lm in world.get("landmarks", []):
		if str(lm.get("kind", "")) == "cruiser":
			out.append({ "id": str(lm.id), "kind": "cruiser", "label": _kind_label("cruiser"), "target": "cruiser" })
	return out


## Unit direction from the planet's centre for map (x, z) on a ball of `radius`
## (PlanetSphere.map_dir: the port is +Y).
static func dir(map: Vector2, radius: float) -> Vector3:
	var d := map.length()
	if d < 0.0001:
		return Vector3.UP
	var th := d / radius
	var s := sin(th) / d
	return Vector3(map.x * s, cos(th), map.y * s)


## Map (x, z) for a unit direction from the centre (PlanetSphere.dir_map).
static func dir_map(d: Vector3, radius: float) -> Vector2:
	var h := Vector2(d.x, d.z)
	var hl := h.length()
	if hl < 0.0000001:
		return Vector2.ZERO if d.y > 0.0 else Vector2(PI * radius, 0.0)
	return h / hl * atan2(hl, d.y) * radius


# ------------------------------------------------------------------ the waypoint

## Point the HUD at `pin` (a surface pin, or an off_planet entry) on `planet_id`.
static func set_waypoint(pin: Dictionary, planet_id: String) -> void:
	var target := str(pin.get("target", ""))
	if target == "":
		var m: Vector2 = pin.map
		target = "map:%.1f,%.1f" % [m.x, m.y]
	WorldState.map_waypoint = { "id": str(pin.id), "label": str(pin.label), "target": target,
		"planet": planet_id, "arrive": float(pin.get("arrive", kind_cfg(str(pin.get("kind", ""))).get("arrive", 30.0))) }
	for k in WorldState.quests:
		WorldState.quests[k].waypoint = false
	WorldState.objective_pin = ""


static func clear_waypoint() -> void:
	WorldState.map_waypoint = {}


## The waypoint's pin id, or "".
static func waypoint_id() -> String:
	return str(WorldState.map_waypoint.get("id", ""))


## { text, target, arrive, map } for the pointer, or {} when there is none.
## A planet's shows anywhere but that planet, and clears itself once you are there.
## A surface or cruiser waypoint on another planet leads to that planet first (and
## never clears itself on the way: arrive -1), then to the place once you land.
static func waypoint() -> Dictionary:
	var w := WorldState.map_waypoint
	if w.is_empty():
		return {}
	var here := GameFlow.current_planet_id()
	var target := str(w.get("target", ""))
	if target.begins_with("planet:"):
		if target.get_slice(":", 1) == here:
			clear_waypoint()
			return {}
	elif str(w.get("planet", "")) != here:
		var there := str(w.get("planet", ""))
		if there == "":
			return {}
		return { "text": line("waypoint_there") % [str(w.get("label", "")), planet_name(there)],
			"target": "planet:" + there, "arrive": -1.0, "map": true }
	return { "text": line("waypoint") % str(w.get("label", "")), "target": target,
		"arrive": float(w.get("arrive", 30.0)), "map": true }


# ------------------------------------------------------------------ elsewhere

static var _others := {}                ## planet id -> { planet, sphere }


## Another planet's map, from its data (the page shows it without going there):
## { planet: PlanetGen.build, sphere: its ball seated on its town as its scene
## seats it (PlanetTerrain.for_planet) }, or {} when it is not a ball. Once a session.
static func other_planet(id: String) -> Dictionary:
	if _others.has(id):
		return _others[id]
	var planet := PlanetGen.build(id)
	var out := {}
	var pt := PlanetTerrain.for_planet(planet)
	if pt != null:
		out = { "planet": planet, "sphere": pt.sphere }
		pt.free()
	_others[id] = out
	return out


## A planet's name for the map's title and its lines.
static func planet_name(id: String) -> String:
	var n := PlanetGen.display_name(PlanetGen.build(id))
	return n if n != "" else id.capitalize()


## The cruiser's places for its side view (CruiserHull.map_places), as pins:
## { id, kind, label, target, rect, arrive }.
static func cruiser_pins() -> Array:
	var out: Array = []
	var names: Dictionary = cfg().get("cruiser_places", {})
	for p in CruiserHull.map_places():
		out.append({ "id": "cruiser_" + str(p.id), "kind": "cruiser_place", "label": str(names.get(str(p.id), str(p.id).capitalize())),
			"target": "cruiser:" + str(p.id), "rect": p.rect, "arrive": float(kind_cfg("cruiser_place").get("arrive", 10.0)) })
	return out


# ------------------------------------------------------------------ helpers

## Who holds `place` (an outpost id, or Territory.BARRACKS for the port): owner,
## whether the locals' supplies there are short (shown only once you have taken
## Oda's supply run: Territory.supplier), and the hover line for it.
static func _stamp_owner(pin: Dictionary, place: String) -> void:
	var who := Territory.owner(place)
	var is_short := Territory.short_shown(place)
	pin["owner"] = who
	pin["short"] = is_short
	pin["hold"] = Territory.hold_frac(place)
	pin["status"] = ""
	if who != Territory.LOCALS:
		if float(pin.hold) >= 0.0:         # issue #425: the Remnant cut off, on a clock
			var rleft := int(maxf(0.0, Territory.hold_left(place)))
			pin["status"] = (line("short") if is_short else line("remnant_held_for")) % [rleft / 60, rleft % 60]
		return
	if place == Territory.BARRACKS or WorldState.has_flag(Territory.DRIVEN_OFF):
		pin["status"] = line("held")
		return
	var left := int(maxf(0.0, Territory.hold_left(place)))
	pin["status"] = (line("short") if is_short else line("held_for")) % [left / 60, left % 60]


static func _pin(id: String, kind: String, label: String, map: Vector2) -> Dictionary:
	return { "id": id, "kind": kind, "label": label, "map": map,
		"arrive": float(kind_cfg(kind).get("arrive", 30.0)), "town": false }


static func _kind_label(kind: String) -> String:
	return str(kind_cfg(kind).get("label", kind.capitalize()))


## "the deep dunes outpost" -> "The deep dunes outpost"
static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


static func _location(id: String) -> Dictionary:
	return _read("%s/%s.json" % [LOCATION_DIR, id])


static var _vendor_list: Array = []


static func _vendors() -> Array:
	if _vendor_list.is_empty():
		var da := DirAccess.open(VENDOR_DIR)
		if da != null:
			for f in da.get_files():
				if f.ends_with(".json"):
					var d := _read(VENDOR_DIR + "/" + f)
					if not d.is_empty():
						_vendor_list.append(d)
	return _vendor_list


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}
