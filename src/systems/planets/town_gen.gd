class_name TownGen
extends RefCounted
## A town of any size, from data (issue #45). Pure: returns the same layout
## dictionary content/core/towns/port_square.json holds (boxes, markers,
## routes, zones, garrison, locals), so TownLayout loads it, validates it rule for
## rule, and town_demo builds, dresses and populates it exactly like the port.
##
## size 1..100. 50 is the port's scale; the area inside the walls grows as
## (size / 50) ^ area_power (5x at 100). Size 1 is the smallest compound that holds
## what every town needs: a cantina with its owner and its stage, a Remnant guard
## at its door, a merchant in front of it, locals walking the street, and a
## landing bay. Every number is in content/core/planets/town_kit.json.
##
## Layout, west to east along the main street (gate in the east wall, like the
## port): [cantina] [square: the merchants' stalls both sides of the street]
## [landing bays both sides of the street] [market south / barracks north] ...
## [gate]. With opts.bay "pit" (issue #75: the asteroid) there are no bays inside
## the walls: the port's round landing pit sits outside the gate, past the apron,
## ringed in paving. Everything else inside the walls is
## a grid of lots, each holding one hut or tower, with lanes between them that the
## residents stroll round. Nothing overlaps by construction: every block is a
## rectangle, and a lot is only used if it keeps a lane clear of every block.
##
## Ids follow the port's, so the decor, the cantina dressing, the bar and the
## launch pad find what they look for: cantina_wall_w/n/s/e_s/e_n,
## cantina_door_lintel, cantina_roof, bar_counter; markers player_spawn, gate,
## desert_exit, cantina_door, bar_front, cantina_owner; the pad's box is "ship".

const KIT_PATH := "res://content/core/planets/town_kit.json"

var kit: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _boxes: Array = []
var _markers: Array = []
var _routes: Array = []
var _zones: Array = []
var _core: Array = []           ## Rect2s (x, z) nothing else may use (plus a lane)


func _init(kit_data: Dictionary = {}) -> void:
	kit = kit_data if not kit_data.is_empty() else _read(KIT_PATH)


## The town's layout. `opts`:
##   cantina_card / cantina_look  -- who runs its cantina (on the cantina_owner marker)
##   cantina_planet               -- issue #75: the planet whose own Oda runs it
##                                   (a generated card: see PlanetOwner)
##   bay                          -- "pit": the port's landing pit outside the gate
##   pit_clear                    -- how far past the walls (x their half-width) the
##                                   pit must start (the asteroid's dome)
##   club_dome                    -- issue #261 (a round station only): no cantina
##                                   building, the whole dome is the club, a rave
##                                   ({ style, bpm, dim } becomes the town's "club")
static func generate(town_id: String, size: int, seed: int = 1, opts: Dictionary = {}, kit_data: Dictionary = {}) -> Dictionary:
	var g := TownGen.new(kit_data)
	return g.build(town_id, size, seed, opts)


## How much bigger than the port, by area (1.0 at 50, 5.0 at 100).
func area_factor(size: int) -> float:
	return pow(clampf(float(size), 1.0, 100.0) / 50.0, float(kit.get("area_power", 2.3219)))


## How many of something a town of this size holds ("guards", "stalls"...).
func count(what: String, size: int) -> int:
	var c: Dictionary = kit.get("counts", {}).get(what, {})
	var n := int(round(float(c.get("per", 0)) * area_factor(size)))
	return clampi(n, int(c.get("min", 0)), int(c.get("max", 999)))


func build(town_id: String, size: int, seed: int, opts: Dictionary = {}) -> Dictionary:
	size = clampi(size, 1, 100)
	_rng.seed = seed * 7919 + size
	_boxes = []
	_markers = []
	_routes = []
	_zones = []
	_core = []
	var lane := float(kit.get("lane", 5.0))
	var margin := float(kit.get("margin", 3.0))
	var sh := float(kit.get("street_half", 6.0))
	var bay := float(kit.get("bay", 16.0))
	var wall: Dictionary = kit.get("wall", {})
	var wt := float(wall.get("thickness", 2.0))
	var guards := count("guards", size)
	var residents := count("residents", size)
	var stalls := count("stalls", size)
	var merchants := mini(count("merchants", size), stalls)
	var bays := count("bays", size)
	var ccfg: Dictionary = kit.get("cantina", {})
	var full := size >= int(ccfg.get("full_from_size", 20))
	var cdim: Dictionary = ccfg.get("full" if full else "small", {})
	var cl := float(cdim.get("length", 18.0))
	var cw := float(cdim.get("width", 14.0))
	var roamers := count("roamers", size)
	var pit := str(opts.get("bay", "")) == "pit"
	# Issue #75: every merchant works a stall in the square in front of the cantina;
	# the stalls nobody keeps fill the market (if there are two or more).
	var front := maxi(1, merchants)
	var rest := stalls - front
	var market := rest >= 2
	var barracks := size >= int(kit.get("barracks_from_size", 25)) and guards >= 3
	var tower := size >= int(kit.get("tower_from_size", 35)) and guards >= 4
	var cols := 0 if pit else int(ceil(bays / 2.0))
	var market_w := ceili(rest / 2.0) * 8.0 if market else 0.0
	var district_need := maxf(market_w, 32.0 if barracks else 0.0) + 16.0      # + gate clearance
	var square := maxf(float(kit.get("square", 8.0)), ceili(front / 2.0) * 8.0 + 4.0)
	# Inside the walls: big enough for the area factor and for what must fit.
	var area := float(kit.get("area_at_50", 30000.0)) * area_factor(size)
	var aspect := float(kit.get("aspect", 1.333))
	var w_need := margin + cl + square + cols * bay + district_need + margin
	var d_need := maxf(cw + 2.0 * (lane + margin), 2.0 * (sh + 6.0 + lane) + 2.0 * margin)
	if cols > 0:
		d_need = maxf(d_need, 2.0 * (sh + 1.0 + bay) + 2.0 * margin)
	if market:
		d_need = maxf(d_need, 2.0 * (sh + 21.0) + 2.0 * margin)
	if barracks:
		d_need = maxf(d_need, 2.0 * (sh + lane + 20.0) + 2.0 * margin)
	var w := snappedf(maxf(sqrt(area * aspect), w_need), 1.0)
	var d := snappedf(maxf(sqrt(area / aspect), d_need), 2.0)
	var xi0 := -w * 0.5
	var xi1 := w * 0.5
	var zi0 := -d * 0.5
	var zi1 := d * 0.5

	# Issue #99: a sealed station is round: no square walls, a ring (built by
	# AsteroidWorld) round the whole town, its gate on the main street.
	var ring_cfg: Dictionary = opts.get("ring", {})
	var round := not ring_cfg.is_empty()
	var rw := ceilf(Vector2((xi1 - xi0) * 0.5, (zi1 - zi0) * 0.5).length() + 3.0)
	var rc := Vector2((xi0 + xi1) * 0.5, (zi0 + zi1) * 0.5)
	var station := {}
	if round:
		_ground_round(rc, rw)
	else:
		_ground(town_id, xi0 - wt, xi1 + wt, zi0 - wt, zi1 + wt, wt, wall)
	var x := xi0 + margin
	var dome: Dictionary = opts.get("club_dome", {}) if round else {}
	var cantina := _cantina(x, cl, cw, float(cdim.get("height", 5.5)), float(ccfg.get("door_half", 2.0)), opts,
		size >= int(ccfg.get("patrons_from_size", 10)), full, Rect2(rc.x - rw, rc.y - rw, rw * 2.0, rw * 2.0) if not dome.is_empty() else Rect2())
	_front_stalls(cantina.end, square, front, sh)
	if round and dome.is_empty():
		_cantina_homes(cantina, sh)
	x = cantina.end + square
	if pit and round:
		var pk: Dictionary = kit.get("pit", {})
		var half := float(pk.get("half", 28.0))
		var pring := float(pk.get("ring", 6.0))
		var hall_min := float(ring_cfg.get("hall_min", 14.0))
		var px := ceilf(rc.x + rw + hall_min + pring + half)
		_pit(px, ["ramp_ne"])
		var hw := float(ring_cfg.get("hall_width", 9.0)) * 0.5
		var hall_end := px - half - pring
		_box("hall_floor", "hall", "floor", [rc.x + rw, -0.5, -hw], [hall_end, 0, hw])
		_zones.append({ "id": "hall", "min": [rc.x + rw, -hw], "max": [hall_end, hw] })
		_marker("desert_exit", [snappedf((rc.x + rw + hall_end) * 0.5, 0.5), 0, 0], "waypoint")
		station = {
			"center": [rc.x, 0.0, rc.y], "radius": rw,
			"gate_half": hw, "wall_height": float(ring_cfg.get("wall_height", 6.0)),
			"dome_height": float(ring_cfg.get("dome_height", 0.85)) * rw,
			"hall": { "x0": rc.x + rw, "rim": px - half, "end": px - 10.0, "half": hw,
				"height": float(ring_cfg.get("hall_height", 5.0)) },
			"pit": { "center": [px, 0.0, 0.0], "radius": half, "liner_height": float(ring_cfg.get("liner_height", 13.0)),
				"door_height": float(ring_cfg.get("liner_door_height", 6.0)) },
		}
	elif pit:
		var spread := float(opts.get("pit_clear", 1.0))
		var ring := float(kit.get("pit", {}).get("ring", 6.0))
		var half := float(kit.get("pit", {}).get("half", 28.0))
		var start := maxf(xi1 + wt + float(kit.get("apron", 30.0)), (xi0 + xi1) * 0.5 + (xi1 - xi0 + 2.0 * wt) * 0.5 * spread + 6.0)
		_pit(ceilf(start + ring + half))     # whole metres: the zone check is exact
	else:
		_spaceport(x, cols, bays, sh, bay)
	x += cols * bay
	var district_x0 := x + lane
	if market:
		_market(district_x0, rest, 0, sh, opts)
	var tower_rect := Rect2()
	if barracks:
		_barracks(xi1 - 16.0 - 30.0, sh + lane)
	if tower:
		tower_rect = _watchtower(xi1)
	_street(cantina.end, xi1, sh)
	_guards(guards, cantina, xi1, sh, district_x0, tower)
	_roamers(roamers, float(cantina.end), xi1 - wt, sh)
	_lots(xi0, xi1, zi0, zi1, sh, residents)
	var zones := _zone_list(xi0, xi1, zi0, zi1, sh)
	var klaxon := ""
	for m in _markers:
		if str(m.get("role", "")) == "trooper_post":
			klaxon = str(m.id) if klaxon == "" or str(m.id) == "trooper_tower" else klaxon
	var alarms: Dictionary = kit.get("alarms", {})
	return {
		"id": town_id,
		"kind": "port",
		"units": "meters",
		"generated": { "by": "TownGen", "size": size, "seed": seed, "area_factor": snappedf(area_factor(size), 0.0001) },
		"note": "Generated by src/systems/planets/town_gen.gd (issue #45) from content/core/planets/town_kit.json. Do not edit: change the planet's town_size or seed.",
		"bounds": { "min": [rc.x - rw, rc.y - rw], "max": [rc.x + rw, rc.y + rw] } if round \
			else { "min": [xi0 - wt, zi0 - wt], "max": [xi1 + wt, zi1 + wt] },
		"station": station,
		"player_clearance": 0.6,
		"walk_speed_hint": 4.5,
		"blocking_kinds": ["wall", "solid", "cover", "counter", "ship"],
		"zones": zones,
		"boxes": _boxes,
		"markers": _markers,
		"routes": _routes,
		"garrison": { "alarm": alarms.get("garrison", {}), "klaxon_marker": klaxon },
		"locals": { "alarm": alarms.get("locals", {}) },
		"counts": { "guards": guards, "residents": residents, "roamers": roamers, "stalls": stalls, "merchants": front,
			"bays": 1 if pit else bays },
		"club": dome.duplicate(),
	}


# ------------------------------------------------------------------ blocks

## Issue #99: the round station's floor: one square of paving under the whole
## ring (AsteroidWorld draws it round), the gate on the main street.
func _ground_round(c: Vector2, r: float) -> void:
	_box("ground", "ground", "floor", [c.x - r, -0.5, c.y - r], [c.x + r, 0, c.y + r])
	_marker("gate", [c.x + r - 1.0, 0, c.y], "waypoint")


func _ground(_town_id: String, x0: float, x1: float, z0: float, z1: float, wt: float, wall: Dictionary) -> void:
	var h := float(wall.get("height", 6.0))
	var gh := float(wall.get("gate_width", 12.0)) * 0.5
	var apron := float(kit.get("apron", 30.0))
	_box("ground", "ground", "floor", [x0, -0.5, z0], [x1, 0, z1])
	_box("gate_apron", "ground", "floor", [x1, -0.5, z0], [x1 + apron, 0, z1])
	_box("wall_east_s", "perimeter", "wall", [x1 - wt, 0, z0], [x1, h, -gh])
	_box("wall_east_n", "perimeter", "wall", [x1 - wt, 0, gh], [x1, h, z1])
	_box("gate_lintel", "perimeter", "overhead", [x1 - wt, h - 1.0, -gh], [x1, h, gh])
	_box("wall_west", "perimeter", "wall", [x0, 0, z0], [x0 + wt, h, z1])
	_box("wall_north", "perimeter", "wall", [x0 + wt, 0, z1 - wt], [x1 - wt, h, z1])
	_box("wall_south", "perimeter", "wall", [x0 + wt, 0, z0], [x1 - wt, h, z0 + wt])
	_marker("gate", [x1 - wt * 0.5, 0, 0], "waypoint")
	_marker("desert_exit", [x1 + 6.0, 0, 0], "waypoint")


## `dome` (issue #261): the dome's floor when the whole dome is the club: no
## building, the club's stage, DJ, dancer and crowd from the kit's "club_dome".
func _cantina(x0: float, l: float, w: float, h: float, door: float, opts: Dictionary, patrons: bool, full: bool = false,
		dome := Rect2()) -> Dictionary:
	var x1 := x0 + l
	var z0 := -w * 0.5
	var z1 := w * 0.5
	if dome.has_area():
		_club_dome(dome)
		_cantina_bar(x0, l, w, opts)
		_marker("cantina_door", [x1 + 1.0, 0, 0], "waypoint")
		_core.append(Rect2(x0, z0, l, w))
		_zones.append({ "id": "cantina", "min": [dome.position.x, dome.position.y], "max": [dome.end.x, dome.end.y] })
		return { "x0": x0, "end": x1, "z0": z0, "z1": z1 }
	_box("cantina_wall_w", "cantina", "wall", [x0, 0, z0], [x0 + 0.5, h, z1])
	_box("cantina_wall_n", "cantina", "wall", [x0 + 0.5, 0, z1 - 0.5], [x1 - 0.5, h, z1])
	_box("cantina_wall_s", "cantina", "wall", [x0 + 0.5, 0, z0], [x1 - 0.5, h, z0 + 0.5])
	_box("cantina_wall_e_s", "cantina", "wall", [x1 - 0.5, 0, z0], [x1, h, -door])
	_box("cantina_wall_e_n", "cantina", "wall", [x1 - 0.5, 0, door], [x1, h, z1])
	_box("cantina_door_lintel", "cantina", "overhead", [x1 - 0.5, 3.0, -door], [x1, h, door])
	_box("cantina_roof", "cantina", "roof", [x0, h, z0], [x1, h + 0.3, z1])
	var cx0 := _cantina_bar(x0, l, w, opts)
	var cz0 := snappedf(-w * 0.3, 0.1)
	var cz1 := snappedf(w * 0.18, 0.1)
	# Issue #75: every cantina has a stage, off the path from the door to the bar.
	var st: Dictionary = kit.get("cantina", {}).get("stage", {})
	var sd := float(st.get("full" if full else "small", 4.0))
	var sz1 := z1 - 0.6
	var sx := x0 + l * float(st.get("at", 0.68))
	_box("cantina_stage", "cantina", "cover", [snappedf(sx - sd * 0.5, 0.1), 0, snappedf(sz1 - sd, 0.1)],
		[snappedf(sx + sd * 0.5, 0.1), float(st.get("height", 0.6)), snappedf(sz1, 0.1)], { "shape": "round", "look": "stage", "standable": true })
	if bool(opts.get("stage_dancer", false)):
		var stage_y := float(st.get("height", 0.6))
		var dancer_x := snappedf(sx, 0.1)
		_markers.append({
			"id": "cantina_dancer",
			"pos": [dancer_x, stage_y, snappedf(sz1 - sd * 0.5, 0.1)],
			"role": "ambient", "soldier": "cantina_dancer",
			"face": [dancer_x, 0.0, 0.0],
		})
	_marker("cantina_door", [x1 + 1.0, 0, 0], "waypoint")
	if patrons:
		var n := 1
		for z in [cz0 + 3.2, cz1 - 1.6]:
			_markers.append({ "id": "patron_%d" % n, "pos": [cx0 + 2.75, 0, snappedf(z, 0.1)], "role": "ambient",
				"soldier": "local_patron", "face": [cx0 - 2.0, 0, 0] })
			n += 1
	_core.append(Rect2(x0, z0, l, w))
	_zones.append({ "id": "cantina", "min": [x0, z0], "max": [x1, z1] })
	return { "x0": x0, "end": x1, "z0": z0, "z1": z1 }


## The bar: its counter, the owner behind it and the spot in front of it. Returns
## the counter's back edge.
func _cantina_bar(x0: float, l: float, w: float, opts: Dictionary) -> float:
	var cx0 := x0 + 0.5 + maxf(4.0, l * 0.25)
	var cz0 := snappedf(-w * 0.3, 0.1)
	var cz1 := snappedf(w * 0.18, 0.1)
	_box("bar_counter", "cantina", "counter", [cx0, 0, cz0], [cx0 + 2.0, 1.1, cz1])
	var owner := { "id": "cantina_owner", "pos": [cx0 - 2.0, 0, 0], "role": "npc", "npc": "cantina_owner" }
	if opts.has("cantina_card"):
		owner["card"] = str(opts.cantina_card)
	if opts.has("cantina_look"):
		owner["look"] = str(opts.cantina_look)
	if opts.has("cantina_planet"):
		owner["planet"] = str(opts.cantina_planet)
	_markers.append(owner)
	_marker("bar_front", [cx0 + 3.5, 0, 0], "interact")
	return cx0


## Issue #261: the whole dome is the club, a rave (the kit's "club_dome", metres from
## the ring's centre): a round stage with the DJ alone on it behind the desk, facing
## the dance floor; the station's dancer on the floor beside it; ravers standing on
## the dance floor and walking loops round the room, bottles in hand.
func _club_dome(dome: Rect2) -> void:
	var k: Dictionary = kit.get("club_dome", {})
	var c := dome.get_center()
	var st: Dictionary = k.get("stage", {})
	var at := c + _v2(st.get("at", [0.0, 0.0]))
	var r := float(st.get("diameter", 8.0)) * 0.5
	var h := float(st.get("height", 0.9))
	_box("cantina_stage", "cantina", "cover", [at.x - r, 0, at.y - r], [at.x + r, h, at.y + r],
		{ "shape": "round", "standable": true, "band": true, "note": "Issue #261: the rave's stage; the DJ plays here alone." })
	var floor_mid: Vector2 = c + (_v2(k.floor.min) + _v2(k.floor.max)) * 0.5
	var dj := at + (floor_mid - at).normalized() * -0.6
	_markers.append({ "id": "band_dj", "pos": [snappedf(dj.x, 0.01), h, snappedf(dj.y, 0.01)], "role": "ambient", "soldier": "club_dj_rave",
		"prop": "dj_desk", "face": [floor_mid.x, h, floor_mid.y] })
	var dz := c + _v2(k.get("dancer", [r + 2.0, 0.0]))
	_markers.append({ "id": "cantina_dancer", "pos": [dz.x, 0.0, dz.y], "role": "ambient", "soldier": "cantina_dancer",
		"face": [floor_mid.x, 0.0, floor_mid.y] })
	var n := 1
	for p in k.get("standing", []):
		var q := c + _v2(p)
		_markers.append({ "id": "raver_%d" % n, "pos": [q.x, 0, q.y], "role": "ambient", "soldier": "local_raver",
			"face": [at.x, h, at.y] })
		n += 1
	var w := 1
	for loop in k.get("walks", []):
		var pts: Array = []
		for p in loop:
			var q := c + _v2(p)
			pts.append([q.x, q.y])
		var rid := "club_walk_%d" % w
		_routes.append({ "id": rid, "points": pts })
		_markers.append({ "id": "raver_walk_%d" % w, "pos": [pts[0][0], 0, pts[0][1]], "role": "ambient", "soldier": "local_raver",
			"patrol": rid })
		w += 1


static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Issue #75: the merchants' stalls, in the square in front of the cantina, both
## sides of the street (the port's stall: a counter facing the street, a back
## panel, the merchant between them).
func _front_stalls(x0: float, length: float, n: int, sh: float) -> void:
	for i in n:
		var north := i % 2 == 0
		var sx := x0 + 2.0 + (i / 2) * 8.0
		var sg := 1.0 if north else -1.0
		var id := "stall_f%s%d" % ["n" if north else "s", i / 2 + 1]
		var c0 := sg * (sh + 1.0)
		var c1 := sg * (sh + 2.0)
		var b0 := sg * (sh + 4.6)
		var b1 := sg * (sh + 5.0)
		_box(id, "square", "cover", [sx, 0, minf(c0, c1)], [sx + 4.0, 1.1, maxf(c0, c1)],
			{ "look": "stall", "face": "-z" if north else "+z" })
		_box(id + "_back", "square", "solid", [sx, 0, minf(b0, b1)], [sx + 4.0, 2.6, maxf(b0, b1)], { "look": "stall_back" })
		_markers.append({ "id": "vendor_%d" % (i + 1), "pos": [sx + 2.0, 0, sg * (sh + 3.3)], "role": "ambient",
			"soldier": "local_merchant", "face": [sx + 2.0, 0, 0] })
	_core.append(Rect2(x0, -(sh + 5.5), length, 2.0 * (sh + 5.5)))
	_zones.append({ "id": "square", "min": [x0, -(sh + 5.5)], "max": [x0 + length, sh + 5.5] })


## Issue #114: on the station, four short gray homes beside the cantina, two
## each side of the street past the square's stalls, their doors facing in.
func _cantina_homes(cantina: Dictionary, sh: float) -> void:
	var z0 := maxf(sh + 5.5, float(cantina.z1)) + 1.0
	var looks := [["hut_block", "hut_round"], ["hut_stepped", "hut_block"]]
	for side in 2:
		var north := side == 0
		var sg := 1.0 if north else -1.0
		for k in 2:
			var x0 := float(cantina.end) - 2.0 + k * 10.0
			var h := 3.5 if k == 0 else 4.0
			var extra := { "look": looks[side][k], "face": "-z" if north else "+z", "style": "gray" }
			if looks[side][k] == "hut_round":
				extra["shape"] = "round"
			_box("cantina_home_%s_%02d" % ["n" if north else "s", k + 1], "cantina_homes", "solid",
				[x0, 0, minf(sg * z0, sg * (z0 + 6.0))], [x0 + 6.0, h, maxf(sg * z0, sg * (z0 + 6.0))], extra)
	var x := float(cantina.end) - 2.0
	_core.append(Rect2(x, -(z0 + 6.0), 16.0, 2.0 * (z0 + 6.0)))
	_zones.append({ "id": "cantina_homes", "min": [x, -(z0 + 6.0)], "max": [x + 16.0, z0 + 6.0] })


## Issue #75: locals who walk the streets (and fight, like every local): loops up
## and down the main street from the cantina door to the gate, each its own.
func _roamers(n: int, x_door: float, x_gate: float, _sh: float) -> void:
	for k in n:
		var zr := 1.5 + float(k % 3) * 1.5
		var inset := float(k % 2) * 6.0
		var xa := x_door + 2.0 + inset
		var xb := maxf(xa + 6.0, x_gate - 3.0 - inset)
		var id := "roamer_%d" % (k + 1)
		_routes.append({ "id": "roam_" + id, "points": [[xa, -zr], [xb, -zr], [xb, zr], [xa, zr], [xa, -zr]] })
		_markers.append({ "id": id, "pos": [xa, 0, -zr], "role": "ambient", "soldier": "local_resident",
			"patrol": "roam_" + id })


## Issue #75: the port's round landing pit (content/core/planets/town_kit.json
## "pit", copied from port_town.json), centred at (cx, 0), ringed in paving.
func _pit(cx: float, drop: Array = []) -> void:
	var pk: Dictionary = kit.get("pit", {})
	var half := float(pk.get("half", 28.0))
	var ring := float(pk.get("ring", 6.0))
	var o := half + ring
	for b in pk.get("boxes", []):
		if drop.has(str(b.id)):
			continue                   # issue #99: the station's pit has one way out, the hallway
		var nb: Dictionary = (b as Dictionary).duplicate(true)
		if nb.has("gaps"):
			nb["gaps"] = (nb.gaps as Array).filter(func(g): return not drop.has(str(g)))
		nb["zone"] = "landing_bay"
		nb["min"] = [float(b.min[0]) + cx, b.min[1], b.min[2]]
		nb["max"] = [float(b.max[0]) + cx, b.max[1], b.max[2]]
		_boxes.append(nb)
	_box("bay_ground_n", "landing_bay", "floor", [cx - o, -0.5, half], [cx + o, 0, o])
	_box("bay_ground_s", "landing_bay", "floor", [cx - o, -0.5, -o], [cx + o, 0, -half])
	_box("bay_ground_w", "landing_bay", "floor", [cx - o, -0.5, -half], [cx - half, 0, half])
	_box("bay_ground_e", "landing_bay", "floor", [cx + half, -0.5, -half], [cx + o, 0, half])
	var sp: Array = pk.get("spawn", [6, -6, 13])
	_marker("player_spawn", [float(sp[0]) + cx, float(sp[1]), float(sp[2])], "spawn")
	_zones.append({ "id": "landing_bay", "min": [cx - o, -o], "max": [cx + o, o] })


func _spaceport(x0: float, cols: int, bays: int, sh: float, cell: float) -> Dictionary:
	var sizes: Dictionary = kit.get("ship_boxes", {})
	var ships: Array = kit.get("bay_ships", ["freighter"])
	var z_n0 := sh + 1.0
	var z_s1 := -sh - 1.0
	for i in bays:
		var col := i / 2
		var north := i % 2 == 0
		var cx := x0 + col * cell + cell * 0.5
		var cz := (z_n0 + cell * 0.5) if north else (z_s1 - cell * 0.5)
		var ship_id := "" if i == 0 else str(ships[(i - 1) % ships.size()])
		var dims: Array = sizes.get("pad" if i == 0 else ship_id, [9.0, 2.5, 8.0])
		var hx := float(dims[0]) * 0.5
		var hz := float(dims[2]) * 0.5
		var extra := {}
		if i > 0:
			extra = { "ship": ship_id, "parked_yaw_deg": 90 if north else -90 }
		var id := "ship" if i == 0 else "ship_%d" % (i + 1)
		_box(id, "spaceport", "ship", [snappedf(cx - hx, 0.01), 0, snappedf(cz - hz, 0.01)],
			[snappedf(cx + hx, 0.01), float(dims[1]), snappedf(cz + hz, 0.01)], extra)
		if i == 0:
			_marker("player_spawn", [cx, 0, z_n0 + 1.5], "spawn")
	var z0 := (z_s1 - cell) if bays > 1 else z_n0
	_core.append(Rect2(x0, z_n0, cols * cell, cell))
	if bays > 1:
		_core.append(Rect2(x0, z_s1 - cell, cols * cell, cell))
	_zones.append({ "id": "spaceport", "min": [x0, z0], "max": [x0 + cols * cell, z_n0 + cell] })
	return { "x0": x0, "x1": x0 + cols * cell }


## Two rows of stalls facing an aisle south of the main street, the port's own
## stall (a counter on the aisle, a back panel, the merchant between them).
func _market(x0: float, stalls: int, merchants: int, sh: float, _opts: Dictionary) -> void:
	var za := -(sh + 10.0)
	var per_row := ceili(stalls / 2.0)
	var placed := 0
	var vendor := 0
	for row in 2:
		var north := row == 0
		for i in per_row:
			if placed >= stalls:
				break
			placed += 1
			var sx := x0 + i * 8.0
			var id := "stall_%s%d" % ["n" if north else "s", i + 1]
			if north:
				_box(id, "market", "cover", [sx, 0, za + 4.0], [sx + 4.0, 1.1, za + 5.0], { "look": "stall", "face": "-z" })
				_box(id + "_back", "market", "solid", [sx, 0, za + 8.6], [sx + 4.0, 2.6, za + 9.0], { "look": "stall_back" })
			else:
				_box(id, "market", "cover", [sx, 0, za - 5.0], [sx + 4.0, 1.1, za - 4.0], { "look": "stall", "face": "+z" })
				_box(id + "_back", "market", "solid", [sx, 0, za - 9.0], [sx + 4.0, 2.6, za - 8.6], { "look": "stall_back" })
			if vendor < merchants:
				vendor += 1
				var mz := za + 7.3 if north else za - 7.3
				_markers.append({ "id": "vendor_%d" % vendor, "pos": [sx + 2.0, 0, mz], "role": "ambient",
					"soldier": "local_merchant", "face": [sx + 2.0, 0, za] })
	var w := per_row * 8.0
	_core.append(Rect2(x0 - 1.0, za - 10.0, w + 2.0, 20.0))
	_zones.append({ "id": "market", "min": [x0 - 1.0, za - 10.0], "max": [x0 + w + 1.0, za + 10.0] })


func _barracks(x0: float, z0: float) -> void:
	_box("barracks_hall", "barracks", "solid", [x0, 0, z0 + 2.0], [x0 + 30.0, 6.0, z0 + 20.0],
		{ "look": "hall", "face": "-z", "style": "garrison" })
	_core.append(Rect2(x0, z0, 30.0, 22.0))
	_zones.append({ "id": "barracks", "min": [x0, z0], "max": [x0 + 30.0, z0 + 22.0] })


func _watchtower(xi1: float) -> Rect2:
	var r := Rect2(xi1 - 10.0, 13.0, 6.0, 6.0)
	_box("watchtower", "gatehouse", "solid", [r.position.x, 0, r.position.y], [r.end.x, 12.0, r.end.y],
		{ "look": "watchtower", "face": "-x", "style": "garrison" })
	_core.append(r)
	_zones.append({ "id": "gatehouse", "min": [r.position.x, r.position.y], "max": [r.end.x, r.end.y] })
	return r


func _street(x0: float, x1: float, sh: float) -> void:
	_zones.append({ "id": "main_street", "min": [x0, -sh], "max": [x1, sh] })


## Remnant posts, most important first: the gate pair, the cantina door, the
## tower, then along the north side of the street.
func _guards(n: int, cantina: Dictionary, xi1: float, sh: float, district_x0: float, tower: bool) -> void:
	var posts: Array = []
	var door := float(cantina.end)
	if n >= 2:
		posts.append({ "id": "trooper_gate_n", "pos": [xi1 - 3.0, 0, 9.0], "soldier": "gate_guard" })
		posts.append({ "id": "trooper_gate_s", "pos": [xi1 - 3.0, 0, -9.0], "soldier": "gate_guard" })
	posts.append({ "id": "trooper_door", "pos": [door + 1.5, 0, 3.5], "soldier": "gate_guard",
		"face": [door + 20.0, 0, 3.5] })
	if tower:
		posts.append({ "id": "trooper_tower", "pos": [xi1 - 7.0, 12.0, 16.0], "soldier": "tower_sentry" })
	var x := district_x0 + 4.0
	var k := 1
	while posts.size() < n and x < xi1 - 16.0:
		posts.append({ "id": "trooper_street_%d" % k, "pos": [snappedf(x, 0.1), 0, sh + 1.2], "soldier": "yard_trooper",
			"face": [snappedf(x, 0.1), 0, 0] })
		x += 18.0
		k += 1
	for i in mini(n, posts.size()):
		var p: Dictionary = posts[i]
		p["role"] = "trooper_post"
		_markers.append(p)


## The rest of the town: a grid of lots, each a hut (or now and then a tower),
## and the residents strolling round some of them.
func _lots(xi0: float, xi1: float, zi0: float, zi1: float, sh: float, residents: int) -> void:
	var lane := float(kit.get("lane", 5.0))
	var lot := float(kit.get("lot", 14.0))
	var pitch := lot + lane
	var inner := Rect2(xi0 + lane, zi0 + lane, (xi1 - xi0) - 2.0 * lane, (zi1 - zi0) - 2.0 * lane)
	var gate_clear := Rect2(xi1 - 16.0, -16.0, 16.0, 32.0)
	var street := Rect2(xi0, -sh, xi1 - xi0, 2.0 * sh)
	var lots: Array = []
	var z := zi0 + lane
	while z + lot <= zi1 - lane:
		var x := xi0 + lane
		while x + lot <= xi1 - lane:
			var r := Rect2(x, z, lot, lot)
			var grown := r.grow(lane - 0.01)
			var ok := inner.encloses(r) and not grown.intersects(street) and not r.grow(2.0).intersects(gate_clear)
			for c in _core:
				if grown.intersects((c as Rect2).grow(0.5)):
					ok = false
					break
			if ok:
				lots.append(r)
			x += pitch
		z += pitch
	var towers_ok := residents >= 3
	var share := float(kit.get("tower_share", 0.3))
	var n := 0
	for r in lots:
		n += 1
		var north: bool = (r as Rect2).get_center().y > 0.0
		var pool: Array = kit.get("towers", []) if towers_ok and north and _rng.randf() < share else kit.get("huts", [])
		_building("house_%s_%02d" % ["e" if north else "w", n], r, _weighted(pool), north)
	# Residents stroll round a lot each, along the lanes.
	var order := range(lots.size())
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for i in mini(residents, lots.size()):
		var r: Rect2 = (lots[order[i]] as Rect2).grow(lane * 0.5)
		var id := "resident_%d" % (i + 1)
		var pts := [[r.position.x, r.position.y], [r.end.x, r.position.y], [r.end.x, r.end.y], [r.position.x, r.end.y],
			[r.position.x, r.position.y]]
		_routes.append({ "id": "stroll_" + id, "points": pts })
		_markers.append({ "id": id, "pos": [r.position.x, 0, r.position.y], "role": "ambient",
			"soldier": "local_resident", "patrol": "stroll_" + id })


func _building(id: String, lot: Rect2, look: Dictionary, north: bool) -> void:
	var wr: Array = look.get("w", [5, 7])
	var round := bool(look.get("round", false))
	var bw := float(_rng.randi_range(int(wr[0]), int(wr[1])))
	var dr: Array = look.get("d", wr)
	var bd := bw if round else float(_rng.randi_range(int(dr[0]), int(dr[1])))
	var hr: Array = look.get("h", [4.0, 5.0])
	var h := snappedf(_rng.randf_range(float(hr[0]), float(hr[1])), 0.5)
	var slack_x := (lot.size.x - bw) * 0.5 - 1.0
	var slack_z := (lot.size.y - bd) * 0.5 - 1.0
	var c := lot.get_center() + Vector2(_rng.randf_range(-slack_x, slack_x), _rng.randf_range(-slack_z, slack_z))
	c = Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
	var extra := { "look": str(look.look), "face": "-z" if north else "+z" }
	if round:
		extra["shape"] = "round"
	_box(id, "residential_e" if north else "residential_w", "solid",
		[c.x - bw * 0.5, 0, c.y - bd * 0.5], [c.x + bw * 0.5, h, c.y + bd * 0.5], extra)


func _zone_list(xi0: float, xi1: float, zi0: float, zi1: float, _sh: float) -> Array:
	var out := _zones.duplicate()
	out.append({ "id": "residential_e", "min": [xi0, 0.0], "max": [xi1, zi1] })
	out.append({ "id": "residential_w", "min": [xi0, zi0], "max": [xi1, 0.0] })
	return out


# ------------------------------------------------------------------ helpers

func _box(id: String, zone: String, kind: String, mn: Array, mx: Array, extra: Dictionary = {}) -> void:
	var b := { "id": id, "zone": zone, "kind": kind, "min": mn, "max": mx }
	for k in extra:
		b[k] = extra[k]
	_boxes.append(b)


func _marker(id: String, pos: Array, role: String) -> void:
	_markers.append({ "id": id, "pos": pos, "role": role })


func _weighted(pool: Array) -> Dictionary:
	var total := 0.0
	for p in pool:
		total += float(p.get("weight", 1))
	var r := _rng.randf() * total
	for p in pool:
		r -= float(p.get("weight", 1))
		if r <= 0.0:
			return p
	return pool.back()


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
