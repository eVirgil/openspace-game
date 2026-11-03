class_name PartyBarge
extends AnimatableBody3D
## Issue #269: a planet's party barge. A big barge floating over the sand that is
## one long party, a franchise of the town's cantina club: the cantina's band on
## the top deck playing the planet's club music, a DJ on the lower deck under the
## lights of a small rave, a crowd dancing on every deck (steerage too), and an
## ugly boss who runs it like a king. Buy it from him or beat him and it is yours.
##
## #269 cleanup: driving is a control panel at the stern. Dial a course, engage,
## and it goes on autopilot while you walk the decks; it stops dead if it runs
## into anything, and blows up if it runs into the planet's beast (it is built
## again at its home after a while). Everyone on board can be killed, and falls
## as a ragdoll (Ragdoll, riding the deck); they are back after `respawn_s`
## seconds of play (or the next time the scene is built). Hurt anyone and the
## crowd and the guards fight back (see _provoke); nothing that happens on board,
## the shots you fire there included, touches your standing with anyone.
##
## Perf: until it is yours it is parked at its home and never moves, so neither do
## its colliders. The people on board are only built when you first come within
## `party_m` (one a physics tick), the club's lights and props only animate within
## `anim_m`, and the look is only moved between ticks while the barge is moving.
##
## A planet component, like the beast and the natives: a planet has one only if
## its file has a "barge" block (content/core/planets/<id>.json); the numbers
## every barge shares are content/core/barges/party_barge.json, and the block may
## override any of them. PlanetGen passes it through; the town scene builds it as
## a late stage (with_barge).
##
## Three decks, all walkable (box colliders, so what you see is what you stand on):
##   top       open deck: the band's stage at the bow, a checker dance floor under
##             an awning, two masts of solar sails, a bar, the boss's dais, the
##             control panel at the stern; a gangplank down to the sand
##   lower     the DJ and a small rave at the bow, a lounge aft, down a ramp from
##             the top deck (port side)
##   steerage  the hold, down a second ramp (starboard): crates, hammocks, lamps
##
## The body is an AnimatableBody3D moved here in _physics_process, so whoever
## stands on a deck rides along. What you see hangs off `look` (BargeLook, or flat
## colours without the look layer), drawn between physics ticks like the player
## (render smoothing), so it glides instead of stepping. Facing -Z is the bow;
## local y = 0 is the sand under its middle.

signal taken_over(how: String)
signal console_taken
signal console_left
signal blocked(what: String)
signal exploded
signal rebuilt

const DATA := "res://content/core/barges/party_barge.json"
const BodyAnimatorT := preload("res://src/systems/anim/body_animator.gd")
const CharBody := preload("res://src/systems/player/character_body.gd")
const LAYER_ENEMIES := 1 << 3
const HAND_POLES := { "l": Vector3(0.7, -0.6, -0.4), "r": Vector3(-0.7, -0.6, -0.4) }

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var planet_id := ""
var cfg: Dictionary = {}
var barge_name := "the party barge"
var boss_name := "the boss"
var owned := false
var at_console := false              ## the player is at the control panel
var autopilot := false               ## under way on the course set at the panel
var speed := 0.0
var heading := Vector3.FORWARD        ## along the ground: where the bow points
var course := Vector3.FORWARD         ## along the ground: the course dialled in
var home := Vector3.ZERO
var travelled := 0.0
var boss_hp := 400.0
var party_frames := 0                 ## frames the crowd and band were animated (traces)
var people: Array = []                ## { node, body, look, hit, deck, kind, perform, spot, yaw, off, hp, dead, back_at, fall, ragdoll, fighter, armed }
var band: Array = []                  ## the performers: the band on top, the DJ below
var boss: Node3D
var console_spot := Vector3.ZERO      ## local: where you stand at the panel
var blocked_by := ""                  ## what it last ran into ("" while clear)
var stops := 0                        ## times it ran into something (traces)
var wrecked := false                  ## blown up; built again at home later
var wrecks := 0
var kills := 0                        ## people killed on board (traces)
var respawned := 0
var fights := 0                       ## times the party was provoked (traces)
var roused := 0                       ## people swapped for fighters (traces)
var gangplank_down := true
var look: Node3D                      ## everything seen; collision stays on the body
var dressing                          ## BargeLook, with the look layer
var parts: Array = []                 ## { mesh, xf, finish, group }: drawn merged, one mesh a finish
var external := {}                    ## a trace's panel command: { dial, engage, stop }
var _ground := Vector3.ZERO           ## the sand point under the middle
var _lift := 0.0                      ## how far it rides above that point (dunes under the ends)
var _lift_to := 0.0
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _tick := 0
var _L := 40.0
var _W := 12.0
var _y := [1.8, 5.2, 8.6]             ## floor tops: steerage, lower, top
var _shapes: Array = []               ## every CollisionShape3D on the body
var _plank_shapes: Array = []         ## the gangplank's
var _boss_home := Vector3.ZERO
var _prompt: Label
var _music: ClubMusic
var party_built := false              ## the people on board exist (built near, see party_m)
var _pending: Array = []              ## people still to build: { look, at, deck, kind, yaw, perform }
var _awake := true                    ## the club's props animate (within anim_m; the first tick far off stops them)
var _rebuild_at := 0.0
var _xf_prev := Transform3D()
var _xf_curr := Transform3D()
var _xf_frame := -1
var _people_root: Node3D
var _playlist := ""
var _folk                             ## Townsfolk running the fighters (made when first provoked)
var _rousing: Array = []              ## people still to swap for fighters, nearest the player first
var _calm_t := 0.0                    ## seconds the fighters' alarm has been down
var _carry := Transform3D.IDENTITY    ## how the deck moved this tick (the fallen ride along)


static func defaults() -> Dictionary:
	var f := FileAccess.open(DATA, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


## The planet's barge (a built planet, PlanetGen.build): the defaults with its
## "barge" block laid over (one level deep for the dictionaries), or {} if none.
static func config(planet: Dictionary) -> Dictionary:
	var own: Dictionary = planet.get("barge", {})
	if own.is_empty():
		return {}
	var c := defaults()
	for k in own:
		if own[k] is Dictionary and c.get(k) is Dictionary:
			var d: Dictionary = (c[k] as Dictionary).duplicate(true)
			d.merge(own[k], true)
			c[k] = d
		else:
			c[k] = own[k]
	return c


static func lives_on(planet: Dictionary) -> bool:
	return not config(planet).is_empty()


static func owned_flag(id: String) -> String:
	return "barge_owned_" + id


static func is_owned(id: String) -> bool:
	return WorldState.has_flag(owned_flag(id))


func setup(town_demo, world_ground: WorldGround, planet: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	player = demo._player
	planet_id = str(planet.get("id", ""))
	cfg = config(planet)
	barge_name = str(cfg.get("name", "the party barge"))
	boss_name = str(cfg.get("boss", {}).get("name", "the boss"))
	boss_hp = float(cfg.get("boss", {}).get("hp", 400))
	owned = is_owned(planet_id)
	_L = float(cfg.get("length", 40.0))
	_W = float(cfg.get("width", 12.0))
	var h := float(cfg.get("hover_m", 1.2))
	var gap := float(cfg.get("deck_gap", 3.4))
	_y = [h + 0.6, h + 0.6 + gap, h + 0.6 + gap * 2.0]
	_rng.seed = 269
	name = "PartyBarge"
	sync_to_physics = true
	process_physics_priority = -1          # moves before the player, who rides it


func _ready() -> void:
	look = Node3D.new()
	look.name = "Look"
	add_child(look)
	_people_root = Node3D.new()
	_people_root.name = "People"
	look.add_child(_people_root)
	var hm: Array = cfg.get("home", [0, 0])
	home = _surface(Vector2(float(hm[0]), float(hm[1])))
	_ground = home
	heading = _flat(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), home).normalized()
	course = heading
	_measure_lift()
	_place(0.0)
	_build_hull()
	_build_top()
	_build_below()
	_plan_people()
	_build_prompt()
	if demo != null and bool(demo.get("use_look")):
		dressing = BargeLook.new()
		look.add_child(dressing)
		dressing.build(self)
	else:
		_flat_look()
	_draw_range()
	var club := str(demo.planet.get("cfg", {}).get("club", Sound.lib().cfg.get("club", {}).get("default", ""))) \
		if demo != null and demo.get("planet") is Dictionary else ""
	club = str(cfg.get("club", club))
	if club != "" and player != null:
		_playlist = club
		_music = ClubMusic.new().setup_follow(club, self, _L * 0.5, player)
		_music.inside_fn = func(p: Vector3) -> bool: return deck_of(p) != ""
		add_child(_music)
	_record_xf()


# ------------------------------------------------------------------ ground

func _surface(m: Vector2) -> Vector3:
	var sp := ground.sphere() if ground != null else null
	if sp != null:
		return sp.surface_at(m.x, m.y)
	var hgt := ground.terrain.height_at(m.x, m.y) if ground != null and ground.terrain != null else 0.0
	return Vector3(m.x, hgt, m.y)


func _up(p: Vector3) -> Vector3:
	return ground.up_at(p) if ground != null else Vector3.UP


func _flat(v: Vector3, at: Vector3) -> Vector3:
	var u := _up(at)
	return v - u * v.dot(u)


func _ground_at(at: Vector3) -> Vector3:
	return ground.surface_below(at + _up(at) * 8.0) if ground != null else Vector3(at.x, 0.0, at.z)


## Level along the planet's up over the sand under its middle, lifted (smoothly)
## so the sand under the bow, stern and sides stays below the keel.
func _place(dt: float) -> void:
	var u := _up(_ground)
	heading = _flat(heading, _ground).normalized()
	_lift = _lift_to if dt <= 0.0 else lerpf(_lift, _lift_to, 1.0 - exp(-dt * 1.2))
	global_transform = Transform3D(Basis.looking_at(heading, u), _ground + u * _lift)


func _measure_lift() -> void:
	var u := _up(_ground)
	var b := Basis.looking_at(heading, u)
	var top := 0.0
	for o in [Vector3(0, 0, -_L * 0.45), Vector3(0, 0, _L * 0.45), Vector3(-_W * 0.45, 0, 0), Vector3(_W * 0.45, 0, 0)]:
		top = maxf(top, (_ground_at(_ground + b * o) - _ground).dot(u))
	_lift_to = minf(top, float(cfg.get("max_lift_m", 4.0)))


## Which deck a world point is on ("top", "lower", "steerage"), or "" off the barge.
func deck_of(p: Vector3) -> String:
	if wrecked:
		return ""
	var l := global_transform.affine_inverse() * p
	if absf(l.x) > _W * 0.5 or absf(l.z) > _L * 0.5:
		return ""
	if l.y < _y[0] - 0.6 or l.y > _y[2] + 4.0:
		return ""
	if l.y >= _y[2] - 0.6:
		return "top"
	if l.y >= _y[1] - 0.6:
		return "lower"
	return "steerage"


## Whether the player is on board (any deck, or the gangplank).
func aboard(p: Vector3) -> bool:
	if deck_of(p) != "":
		return true
	if wrecked or not gangplank_down:
		return false
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < 2.5 and l.z > _L * 0.5 and l.z < _L * 0.5 + 24.0 and l.y > -2.0 and l.y < _y[2] + 3.0


# ------------------------------------------------------------------ building blocks

## A part of the barge: drawn (merged with every other part of its finish) and,
## when solid, stood on and walked into. Local space.
func _part(mesh: Mesh, xf: Transform3D, finish: String, group := "") -> void:
	parts.append({ "mesh": mesh, "xf": xf, "finish": finish, "group": group })


func _box(size: Vector3, at: Vector3, finish: String, solid := true, rot := Basis.IDENTITY, group := "") -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_part(bm, Transform3D(rot, at), finish, group)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(rot, at)
		add_child(cs)
		_shapes.append(cs)
		if group == "gangplank":
			_plank_shapes.append(cs)


func _cyl(r: float, h: float, at: Vector3, finish: String, solid := false, rot := Basis.IDENTITY, group := "") -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	_part(cm, Transform3D(rot, at), finish, group)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		cs.shape = sh
		cs.transform = Transform3D(rot, at)
		add_child(cs)
		_shapes.append(cs)


func _ball(r: float, at: Vector3, finish: String) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	_part(sm, Transform3D(Basis.IDENTITY, at), finish)


## A floor slab (top surface at y) over the inside of the hull, with a stairwell hole.
func _floor(y: float, hole: Rect2, finish: String) -> void:
	var x0 := -_W * 0.5 + 0.4
	var x1 := _W * 0.5 - 0.4
	var z0 := -_L * 0.5 + 0.4
	var z1 := _L * 0.5 - 0.4
	var t := 0.3
	var rects: Array = []
	if hole.size == Vector2.ZERO:
		rects.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	else:
		var hx0 := hole.position.x
		var hx1 := hole.end.x
		var hz0 := hole.position.y
		var hz1 := hole.end.y
		rects.append(Rect2(x0, z0, hx0 - x0, z1 - z0))
		rects.append(Rect2(hx1, z0, x1 - hx1, z1 - z0))
		rects.append(Rect2(hx0, z0, hx1 - hx0, hz0 - z0))
		rects.append(Rect2(hx0, hz1, hx1 - hx0, z1 - hz1))
	for r in rects:
		if r.size.x > 0.01 and r.size.y > 0.01:
			_box(Vector3(r.size.x, t, r.size.y), Vector3(r.get_center().x, y - t * 0.5, r.get_center().y), finish)


## A walkable ramp from a (top) to b (bottom), w wide; its top face runs through both.
func _ramp(a: Vector3, b: Vector3, w: float, finish: String, group := "") -> void:
	var d := b - a
	var along := d.normalized()
	var side := Vector3.UP.cross(along).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var n := along.cross(side).normalized()
	if n.y < 0.0:
		n = -n
	var t := 0.3
	var basis := Basis(side, n, -along)
	_box(Vector3(w, t, d.length() + 0.4), (a + b) * 0.5 - n * t * 0.5, finish, true, basis, group)


# ------------------------------------------------------------------ the hull

const HOLE_TOP := Rect2(-5.6, -6.0, 2.4, 9.0)      ## top deck -> lower (port), x, z
const HOLE_LOWER := Rect2(3.2, 4.0, 2.4, 9.0)      ## lower -> steerage (starboard)
const MASTS := [-4.2, 5.0]                         ## z of the two masts on the centre line
const STAGE_D := 5.6                               ## how deep the band's stage is, from the bow wall


## The decks' height and the bow's prow. BargeLook draws the hull's skin round
## these from the same numbers.
func dims() -> Dictionary:
	return { "length": _L, "width": _W, "hover": float(cfg.get("hover_m", 1.2)), "decks": _y,
		"prow": float(cfg.get("prow_m", 6.0)) }


func _build_hull() -> void:
	var h := float(cfg.get("hover_m", 1.2))
	var top := float(_y[2])
	var wall_h := top + 1.1 - h
	# Bottom (the steerage floor), sides, bow and stern. Rusted iron inside and out.
	_box(Vector3(_W, _y[0] - h, _L), Vector3(0, (h + _y[0]) * 0.5, 0), "hull")
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.4, wall_h, _L), Vector3(sx * (_W * 0.5 - 0.2), h + wall_h * 0.5, 0), "hull")
		_box(Vector3(0.5, 0.18, _L + 0.2), Vector3(sx * (_W * 0.5 - 0.2), top + 1.19, 0), "trim", false)   # gunwale
	_box(Vector3(_W - 0.8, wall_h, 0.4), Vector3(0, h + wall_h * 0.5, -_L * 0.5 + 0.2), "hull")
	# The stern: solid up to the top deck, a bulwark either side of the gangplank.
	_box(Vector3(_W - 0.8, top - h, 0.4), Vector3(0, (h + top) * 0.5, _L * 0.5 - 0.2), "hull")
	for sx in [-1.0, 1.0]:
		_box(Vector3(_W * 0.5 - 2.0, 1.1, 0.4), Vector3(sx * (_W * 0.25 + 0.6), top + 0.55, _L * 0.5 - 0.2), "hull")
	# Decks: planks on top and in the lounge, darker boards down in steerage.
	_floor(_y[1], HOLE_LOWER, "deck")
	_floor(top, HOLE_TOP, "deck")
	_box(Vector3(_W - 0.8, 0.02, _L - 0.8), Vector3(0, _y[0] + 0.01, 0), "steerage", false)
	# Stairs: top -> lower down the port side, lower -> steerage down the starboard.
	var cx := HOLE_TOP.get_center().x
	_ramp(Vector3(cx, top, HOLE_TOP.position.y), Vector3(cx, _y[1], HOLE_TOP.end.y), HOLE_TOP.size.x - 0.2, "deck")
	cx = HOLE_LOWER.get_center().x
	_ramp(Vector3(cx, _y[1], HOLE_LOWER.position.y), Vector3(cx, _y[0], HOLE_LOWER.end.y), HOLE_LOWER.size.x - 0.2, "steerage")
	# Gangplank: stern to the sand (its foot sinks a little into it). Up while under way.
	_ramp(Vector3(0, top, _L * 0.5 - 0.3), Vector3(0, -1.0, _L * 0.5 + 22.0), 3.0, "deck", "gangplank")
	for sx in [-1.0, 1.0]:
		for i in 6:
			var f := float(i) / 5.0
			var p := Vector3(sx * 1.6, lerpf(top, -1.0, f) + 0.5, lerpf(_L * 0.5, _L * 0.5 + 22.0, f))
			_cyl(0.05, 1.0, p, "brass", false, Basis.IDENTITY, "gangplank")
	# Railings round the stairwells (so nobody steps in by mistake).
	_box(Vector3(0.1, 1.0, HOLE_TOP.size.y), Vector3(HOLE_TOP.end.x + 0.05, top + 0.5, HOLE_TOP.get_center().y), "brass")
	_box(Vector3(HOLE_TOP.size.x, 1.0, 0.1), Vector3(HOLE_TOP.get_center().x, top + 0.5, HOLE_TOP.end.y + 0.05), "brass")
	_box(Vector3(0.1, 1.0, HOLE_LOWER.size.y), Vector3(HOLE_LOWER.position.x - 0.05, _y[1] + 0.5, HOLE_LOWER.get_center().y), "brass")
	_box(Vector3(HOLE_LOWER.size.x, 1.0, 0.1), Vector3(HOLE_LOWER.get_center().x, _y[1] + 0.5, HOLE_LOWER.end.y + 0.05), "brass")


func _build_top() -> void:
	var top := float(_y[2])
	var bow := -_L * 0.5 + 0.4
	# Masts and their solar sails: panels on yards, tipped back a little.
	for mz in MASTS:
		_cyl(0.32, 16.0, Vector3(0, top + 8.0, mz), "trim", true)
		for k in 2:
			var w := _W * (0.92 if k == 0 else 0.62)
			var hgt := 6.4 if k == 0 else 2.6
			var y := top + 4.8 + hgt * 0.5 if k == 0 else top + 13.0
			var tilt := Basis(Vector3.RIGHT, -0.16)
			_box(Vector3(w, hgt, 0.08), Vector3(0, y, mz + 0.85), "solar", false, tilt)
			_box(Vector3(w + 0.3, 0.16, 0.16), Vector3(0, y + hgt * 0.5 + 0.08, mz + 0.85 - 0.5 * hgt * sin(0.16)), "trim", false)   # yard
			_box(Vector3(w + 0.3, 0.12, 0.12), Vector3(0, y - hgt * 0.5 - 0.06, mz + 0.85 + 0.5 * hgt * sin(0.16)), "trim", false)
			_box(Vector3(0.12, 0.12, 0.85), Vector3(0, y + hgt * 0.5 + 0.08, mz + 0.42 - 0.5 * hgt * sin(0.16)), "trim", false)    # to the mast
	# The band's stage at the bow (low enough to step up) and its back wall.
	var sz := bow + STAGE_D * 0.5
	_box(Vector3(_W - 1.2, 0.12, STAGE_D), Vector3(0, top + 0.06, sz), "stage")
	_box(Vector3(_W - 1.2, 3.4, 0.2), Vector3(0, top + 1.7, bow + 0.15), "hull", false)
	# The awning over the dance floor, on brass poles.
	var a0 := bow + STAGE_D + 0.4
	var a1 := -6.6
	for sx in [-1.0, 1.0]:
		for z in [a0, a1]:
			_cyl(0.07, 4.4, Vector3(sx * (_W * 0.5 - 0.7), top + 2.2, z), "brass")
	var n := 8
	for i in n:
		var w := (a1 - a0) / n
		_box(Vector3(_W - 1.2, 0.05, w), Vector3(0, top + 4.42, a0 + w * (i + 0.5)), "awning" if i % 2 == 0 else "awning_stripe", false)
	# String lights along both gunwales.
	for sx in [-1.0, 1.0]:
		for i in 22:
			var z := lerpf(-_L * 0.5 + 1.0, _L * 0.5 - 1.0, i / 21.0)
			_ball(0.08, Vector3(sx * (_W * 0.5 - 0.2), top + 1.6 + 0.22 * sin(i * 1.3), z), "lamp")
	# The bar (starboard).
	_box(Vector3(1.0, 1.1, 6.0), Vector3(_W * 0.5 - 1.2, top + 0.55, -1.0), "bar")
	_box(Vector3(1.2, 0.08, 6.2), Vector3(_W * 0.5 - 1.2, top + 1.14, -1.0), "brass", false)
	# The boss's dais and lounger, facing the stern.
	_boss_home = Vector3(0, top + 0.12, 10.5)
	_box(Vector3(4.0, 0.12, 3.0), Vector3(0, top + 0.06, 10.5), "brass")
	_box(Vector3(3.2, 0.6, 1.6), Vector3(0, top + 0.42, 11.3), "velvet", false)
	_box(Vector3(3.2, 1.6, 0.3), Vector3(0, top + 0.92, 9.4), "velvet", false)
	# The control panel near the stern, starboard: you stand aft of it, facing the bow.
	console_spot = Vector3(3.6, top + 0.05, 17.1)
	_box(Vector3(1.8, 1.0, 0.8), Vector3(3.6, top + 0.5, 16.1), "console")


func _build_below() -> void:
	var y1 := float(_y[1])
	var bow := -_L * 0.5 + 0.4
	# The DJ's desk at the bow end of the lower deck (its look is BargeLook's).
	_box(Vector3(1.6, 1.0, 0.7), Vector3(0, y1 + 0.5, bow + 3.0 + 0.55), "console", true)
	# Steerage: crates and hammocks.
	for i in 6:
		_box(Vector3(1.2, 1.0, 1.2), Vector3(-4.6, _y[0] + 0.5, -16.0 + i * 1.6), "crate")
	for i in 4:
		_box(Vector3(0.9, 0.08, 2.4), Vector3(-3.0 + i * 1.6, y1 - 1.0, -6.0), "awning", false, Basis(Vector3.FORWARD, 0.08 * (i % 2 * 2 - 1)))


## The hull and decks (the big merged meshes, which the look's own pass leaves
## drawn at any distance) stop being drawn past draw_m, fading over the last tenth,
## so the barge is not drawn from the town. Small props keep their own, shorter range.
func _draw_range() -> void:
	var end := float(cfg.get("draw_m", 1500.0))
	for n in look.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.visibility_range_end <= 0.0:
			gi.visibility_range_end = end
			gi.visibility_range_end_margin = end * 0.1
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Without the look layer: every finish in one flat colour.
func _flat_look() -> void:
	var colors: Dictionary = cfg.get("colors", {})
	var mats := {}
	for f in finishes():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(colors.get(f, "#888888")))
		m.roughness = 0.85
		if f in ["lamp", "screen", "solar"]:
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 0.6 if f == "solar" else 2.0
		mats[f] = m
	for mi in merged(mats):
		look.add_child(mi)


## The finishes the parts use.
func finishes() -> Array:
	var out: Array = []
	for p in parts:
		if not out.has(p.finish):
			out.append(p.finish)
	return out


## The parts as one MeshInstance3D a finish (and a group: the gangplank is its own,
## so it can be raised), in `mats` (finish -> Material).
func merged(mats: Dictionary) -> Array:
	var sets := {}
	for p in parts:
		var key := "%s|%s" % [p.finish, p.group]
		if not sets.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sets[key] = st
		(sets[key] as SurfaceTool).append_from(p.mesh, 0, p.xf)
	var out: Array = []
	for key in sets:
		var bits: PackedStringArray = str(key).split("|")
		var mi := MeshInstance3D.new()
		mi.name = "Barge_" + bits[0] + ("_" + bits[1] if bits[1] != "" else "")
		mi.mesh = (sets[key] as SurfaceTool).commit()
		mi.material_override = mats.get(bits[0])
		if bits[1] == "gangplank":
			mi.set_meta("gangplank", true)
		if bits[0] in ["lamp", "screen", "awning", "awning_stripe"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mi)
	return out


# ------------------------------------------------------------------ the people

## Who stands where (cheap): the people themselves are built later, one a
## physics tick, when the player first comes within party_m (_build_party).
func _plan_people() -> void:
	var crowd: Dictionary = cfg.get("crowd", {})
	var looks: Array = cfg.get("crowd_looks", ["local"])
	var top := float(_y[2])
	# Only armed_share of the crowd carry a pistol, spread evenly through it; the rest
	# keep dancing when a fight starts (_provoke).
	var share := clampf(float(cfg.get("armed_share", 1.0)), 0.0, 1.0)
	var dancers := [0]
	var add := func(look_id: String, at: Vector3, deck: String, kind: String, yaw: float, perform: String) -> void:
		var armed := true
		if kind == "dancer":
			armed = floori((dancers[0] + 1) * share) > floori(dancers[0] * share)
			dancers[0] += 1
		_pending.append({ "look": look_id, "at": at, "deck": deck, "kind": kind, "yaw": yaw, "perform": perform, "armed": armed })
	for i in int(crowd.get("top", 12)):
		add.call(looks[i % looks.size()], _free_spot("top"), "top", "dancer", INF, "")
	for i in int(crowd.get("lower", 7)):
		add.call(looks[(i + 1) % looks.size()], _free_spot("lower"), "lower", "dancer", INF, "")
	for i in int(crowd.get("steerage", 9)):
		add.call(looks[(i + 2) % looks.size()], _free_spot("steerage"), "steerage", "dancer", INF, "")
	# The cantina's band on the stage at the bow, facing aft over the dance floor.
	var bz := -_L * 0.5 + 0.4 + STAGE_D * 0.45
	var kinds: Array = cfg.get("band", ["drum", "bass"])
	for i in kinds.size():
		var x := lerpf(-1.8, 1.8, float(i) / maxf(1.0, kinds.size() - 1.0))
		add.call(str(cfg.get("band_look", "club_band")), Vector3(x, top + 0.12, bz), "top", "band", 0.0, str(kinds[i]))
	# The DJ at the bow end of the lower deck, behind the desk.
	add.call(str(cfg.get("band_look", "club_band")), Vector3(0, _y[1], -_L * 0.5 + 0.4 + 3.0), "lower", "band", 0.0, "dj")
	# Guards either side of the dais (they groove too; they never draw).
	for i in int(cfg.get("guards", 2)):
		add.call(str(cfg.get("guard_look", "desert_guard")), _boss_home + Vector3((i * 2 - 1) * 2.6, 0, -0.5), "top", "guard", 0.0, "")
	add.call("cantina_owner", _boss_home, "top", "boss", 0.0, "")


## The next person on the list, once the player has come within party_m.
func _build_party() -> void:
	if party_built or player == null or not is_instance_valid(player):
		return
	# From _ground (set in _ready): the body's own transform reads the origin for its
	# first tick.
	if people.is_empty() and player.global_position.distance_to(_ground) > float(cfg.get("party_m", 220.0)):
		return
	var s: Dictionary = _pending.pop_front()
	var p := _add_person(s.look, s.at, s.deck, s.kind, s.yaw)
	p.armed = s.armed
	if s.perform != "":
		p.perform = s.perform
		band.append(p)
	if s.kind == "boss":
		_build_boss(p)
	if _pending.is_empty():
		party_built = true
		_party_changed()


## A clear spot on a deck (local), away from the stairwells, masts, bar, stage,
## tables and dais; on the lower deck mostly on the light-up floor.
func _free_spot(deck: String) -> Vector3:
	var y: float = _y[2] if deck == "top" else (_y[1] if deck == "lower" else _y[0])
	for tries in 40:
		var x := _rng.randf_range(-_W * 0.5 + 1.2, _W * 0.5 - 1.4)
		var z := _rng.randf_range(-_L * 0.5 + 2.0, _L * 0.5 - 2.0)
		var ok := true
		match deck:
			"top":
				z = _rng.randf_range(-_L * 0.5 + STAGE_D + 1.2, 7.5)
				ok = not HOLE_TOP.grow(0.8).has_point(Vector2(x, z)) and x < _W * 0.5 - 2.2
				for mz in MASTS:
					ok = ok and Vector2(x, z).distance_to(Vector2(0, mz)) > 1.2
				ok = ok and not Rect2(-_W * 0.5, 3.5, 2.6, 6.0).has_point(Vector2(x, z))
			"lower":
				if tries < 30 and _rng.randf() < 0.75:
					x = _rng.randf_range(-2.6, 2.6)
					z = _rng.randf_range(-_L * 0.5 + 5.6, -8.4)
				ok = not HOLE_LOWER.grow(0.8).has_point(Vector2(x, z)) and not Rect2(-6, -6.5, 3.6, 11.0).has_point(Vector2(x, z)) \
					and z > -_L * 0.5 + 5.0 and not Rect2(-5.0, 4.6, 4.2, 7.6).has_point(Vector2(x, z))
			_:
				ok = not Rect2(2.4, 3.5, 4.0, 10.5).has_point(Vector2(x, z)) and x > -3.6
		if ok:
			return Vector3(x, y, z)
	return Vector3(0, y, 0)


func _add_person(look_id: String, at: Vector3, deck: String, kind: String, yaw := INF) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "%s_%d" % [kind, people.size()]
	holder.position = at
	holder.rotation.y = _rng.randf() * TAU if yaw == INF else yaw
	_people_root.add_child(holder)
	var body: Node3D = null
	if demo != null and bool(demo.get("use_look")) and demo.has_method("_kit"):
		body = demo._kit().build(look_id, "idle")
		holder.add_child(body)
	else:
		body = Node3D.new()                 # headless: a stand-in that still moves
		body.name = "Stand"
		holder.add_child(body)
	var p := { "node": holder, "body": body, "look": look_id, "deck": deck, "kind": kind, "perform": "", "off": _rng.randf() * 30.0,
		"spot": at, "yaw": holder.rotation.y, "beat": 0.0, "hp": float(cfg.get("person_hp", 60)), "dead": false,
		"back_at": 0.0, "fall": 0.0, "rest": body.transform, "ragdoll": null, "fighter": null, "armed": true }
	p.hit = _hit_for(p)
	people.append(p)
	return p


## Something bolts and blades find: a capsule where the person stands, on the body
## (so it rides along), that sends the damage here.
func _hit_for(p: Dictionary) -> StaticBody3D:
	var hit := PartyHit.new()
	hit.barge = self
	hit.who = p
	hit.name = "Hit_" + str(p.node.name)
	hit.collision_layer = LAYER_ENEMIES
	hit.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9 if p.kind == "boss" else 0.35
	cap.height = 2.6 if p.kind == "boss" else 1.8
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	hit.add_child(cs)
	add_child(hit)
	hit.position = p.spot
	return hit


func _joint(body: Node3D, jn: String) -> Node3D:
	var j = body.get_meta("joints", {}) if body.has_meta("joints") else {}
	return j.get(jn) if j is Dictionary else null


## A bit of look on someone (the boss's warts, belly and nose), flat coloured.
func _bit(mesh: Mesh, at: Vector3, color: String, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.8
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	return sm


## The boss: big, wide and ugly, warts and all, on his dais.
func _build_boss(p: Dictionary) -> void:
	boss = p.node
	var body: Node3D = p.body
	body.scale *= Vector3(2.0, 1.25, 2.0)
	p.rest = body.transform
	var head := _joint(body, "head")
	var chest := _joint(body, "chest")
	if chest != null:
		_bit(_sphere(0.32), Vector3(0, -0.22, 0.14), "#7a5a3a", chest).scale = Vector3(1.15, 0.95, 1.0)
	if head != null:
		for k in 6:
			_bit(_sphere(0.03 + 0.02 * (k % 3)), Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(0.0, 0.16), _rng.randf_range(0.02, 0.12)), "#6f7a4a", head)
		_bit(_sphere(0.07), Vector3(0, 0.02, 0.13), "#8a6a4a", head)     # a big nose
	if owned:
		_boss_below()


## What bolts and blades hit on board: one per person.
class PartyHit:
	extends StaticBody3D
	var barge
	var who: Dictionary
	var dead := false
	var damage_usec := 0

	func apply_damage(amount: float) -> void:
		damage_usec = Time.get_ticks_usec()
		barge.hurt(who, amount)

	func apply_damage_from(amount: float, shooter: Node) -> void:
		damage_usec = Time.get_ticks_usec()
		barge.hurt(who, amount, shooter)

	func apply_blade_hit(amount: float, sweep: Vector3) -> void:
		damage_usec = Time.get_ticks_usec()
		barge.hurt(who, amount, barge.player, sweep)


## The party never stops: everyone dances (the cantina's dance loop), the band and
## the DJ play their sets (ClubMoves) with their hands on their instruments, the
## boss bounces with laughter. Full rate close by, a quarter rate farther out,
## nothing past anim_m; the dead fall and lie still.
func _animate(dt: float) -> void:
	if player == null or not is_instance_valid(player) or wrecked:
		return
	for p in people:
		if p.dead and p.fighter == null:
			_fall(p, dt)
	var d := player.global_position.distance_to(global_position)
	_people_root.visible = d < float(cfg.get("people_m", 320.0))
	var near := d <= float(cfg.get("anim_m", 160.0))
	if near != _awake:
		_awake = near
		if dressing != null:
			dressing.wake(near)
	if not near:
		return
	if d > float(cfg.get("anim_near_m", 50.0)) and _tick % 4 != 0:
		return
	party_frames += 1
	var kit = demo._kit() if demo != null and demo.has_method("_kit") and bool(demo.get("use_look")) else null
	var bpm := float(cfg.get("bpm", 100.0))
	for p in people:
		var body: Node3D = p.body
		if p.dead or p.fighter != null:
			continue
		var t: float = _t + float(p.off)
		p.beat = t
		if not body.has_meta("joints"):
			body.position.y = 0.08 * absf(sin(t * 4.2))       # headless stand-in
			body.rotation.y = 0.3 * sin(t * 1.3)
			continue
		var joints: Dictionary = body.get_meta("joints")
		if p.kind == "dancer":
			var pose: Dictionary = BodyAnimatorT.dance_pose(t)
			for jn in pose.joints:
				if joints.has(jn):
					(joints[jn] as Node3D).rotation_degrees = pose.joints[jn]
			if joints.has("pelvis"):
				(joints.pelvis as Node3D).position.y = float(pose.pelvis_y)
				(joints.pelvis as Node3D).position.x = float(pose.pelvis_x)
			body.rotation.y = float(pose.yaw)
		elif p.kind == "band" and p.perform != "":
			_perform(p, joints, _t, bpm, kit)
		else:
			# Guards and the boss: a nod, a sway and a bounce on the beat.
			var b := t * TAU * 2.0
			var k := 1.6 if p.kind == "boss" else 1.0
			if joints.has("head"):
				(joints.head as Node3D).rotation_degrees = Vector3(10.0 * sin(b) * k, 8.0 * sin(b * 0.5), 0)
			if joints.has("chest"):
				(joints.chest as Node3D).rotation_degrees = Vector3(4.0 * sin(b) * k, 12.0 * sin(b * 0.25), 6.0 * sin(b * 0.5))
			if joints.has("pelvis"):
				(joints.pelvis as Node3D).position.y = BodyAnimatorT.PELVIS_Y - 0.04 * absf(sin(b * 0.5)) * k
			if joints.has("l_knee"):
				(joints.l_knee as Node3D).rotation_degrees.x = 10.0 * absf(sin(b * 0.5))
			if joints.has("r_knee"):
				(joints.r_knee as Node3D).rotation_degrees.x = 10.0 * absf(sin(b * 0.5 + PI * 0.5))
		_sync_skins(body)


## A performer's set (ClubMoves), hands put on the instrument with the kit's arm IK
## the way NpcBody does it in the cantina.
func _perform(p: Dictionary, joints: Dictionary, t: float, bpm: float, kit) -> void:
	var out: Dictionary = ClubMoves.pose(str(p.perform), t + float(p.off), bpm)
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	if joints.has("pelvis"):
		(joints.pelvis as Node3D).position.y = float(out.pelvis_y)
		(joints.pelvis as Node3D).position.x = float(out.pelvis_x)
	var chest := joints.get("chest") as Node3D
	if kit == null or chest == null:
		return
	var hands: Dictionary = out.get("hands", {})
	var reach: Dictionary = out.get("reach", {})
	var to_chest := chest.global_transform.affine_inverse() * (p.node as Node3D).global_transform
	for side in ["l", "r"]:
		var w := float(reach.get(side, 0.0))
		var at = hands.get(side)
		var wrist := joints.get(side + "_wrist") as Node3D
		if w <= 0.01 or at == null or wrist == null:
			continue
		var from := chest.global_transform.affine_inverse() * wrist.global_position
		kit.reach(p.body, side, from.lerp(to_chest * (at as Vector3), w), HAND_POLES[side])


## SkinnedBody.sync already does every layer in the body's "skins".
func _sync_skins(body: Node3D) -> void:
	var skins: Array = body.get_meta("skins", [])
	if not skins.is_empty():
		skins[0].sync(body)


## Down on the deck: a ragdoll (started by _kill) carried along by the deck while
## it settles, then lying still in the barge's own frame so it rides along. The
## headless stand-in, with no joints, tips over backwards instead.
func _fall(p: Dictionary, dt: float) -> void:
	var rd: Ragdoll = p.ragdoll
	if rd != null:
		rd.carry(_carry)
		var moving := not rd.asleep
		rd.step(dt)
		if moving:
			_sync_skins(p.body)
		return
	if float(p.fall) >= 1.0:
		return
	p.fall = minf(1.0, float(p.fall) + dt * 2.5)
	var body: Node3D = p.body
	var k := float(p.fall) * float(p.fall)
	var rest: Transform3D = p.rest
	body.transform = rest
	body.rotate_object_local(Vector3.RIGHT, -PI * 0.5 * k)
	body.position = rest.origin + Vector3(0, 0.18 * k, 0)
	if body.has_meta("joints"):
		var joints: Dictionary = body.get_meta("joints")
		for jn in ["l_shoulder", "r_shoulder"]:
			if joints.has(jn):
				(joints[jn] as Node3D).rotation_degrees = Vector3(-20.0, 0, 70.0 if jn == "l_shoulder" else -70.0) * k
		_sync_skins(body)


# ------------------------------------------------------------------ hurting people

## Someone on board was hit by `by` (null: we don't know, so the player). The
## player (or their droid) hitting anyone provokes the party (_provoke), but no
## standing moves; at zero they drop as a ragdoll, and are back on their feet
## after respawn_s seconds of play. The boss can't die while it is his barge:
## beat him and he hands it over. `sweep`: a sword's cut, which flings the body.
func hurt(p: Dictionary, amount: float, by: Node = null, sweep := Vector3.ZERO) -> void:
	if p.dead or wrecked or amount <= 0.0:
		return
	if by == null or DroidController.by_player(by, player):
		_provoke()
	if p.kind == "boss" and not owned:
		hurt_boss(amount)
		return
	p.hp = float(p.hp) - amount
	if float(p.hp) <= 0.0:
		_kill(p, amount, by, sweep)


func _kill(p: Dictionary, amount := 0.0, by: Node = null, sweep := Vector3.ZERO) -> void:
	p.dead = true
	p.fall = 0.0
	_go_limp(p, amount, by, sweep)
	p.back_at = WorldState.clock + float(cfg.get("respawn_s", 180.0))
	(p.hit as PartyHit).dead = true
	(p.hit as PartyHit).collision_layer = 0
	kills += 1
	_party_changed()


## The ragdoll the way NpcBody falls: pushed away from whoever hit them, or
## flung along a sword's cut; the deck it lands on is the barge's own collision.
func _go_limp(p: Dictionary, amount: float, by: Node, sweep: Vector3) -> void:
	var body: Node3D = p.body
	if not body.has_meta("joints") or not body.is_inside_tree():
		return
	var rc := Ragdoll.load_config()
	var at := (p.node as Node3D).global_position
	var from := Vector3.INF
	var fling := Vector3.ZERO
	if sweep != Vector3.ZERO:
		var cut := Vector3(sweep.x, 0.0, sweep.z).normalized()
		from = at - cut
		fling = cut * float(rc.get("blade_fling", 8.0)) + _up(at) * float(rc.get("blade_fling_up", 5.5))
	elif by is Node3D and is_instance_valid(by):
		from = (by as Node3D).global_position
	var rd := Ragdoll.new(body.get_meta("joints"), rc)
	rd.start(fling, Ragdoll.kick_for(at, from, amount, rc), get_world_3d().direct_space_state, [(p.hit as PartyHit).get_rid()])
	p.ragdoll = rd


func _respawn(p: Dictionary) -> void:
	if p.fighter != null:
		_settle(p)
	if p.ragdoll != null:
		(p.ragdoll as Ragdoll).stop()
		p.ragdoll = null
	p.dead = false
	p.fall = 0.0
	p.hp = float(cfg.get("person_hp", 60))
	(p.body as Node3D).transform = p.rest
	(p.hit as PartyHit).dead = false
	(p.hit as PartyHit).collision_layer = LAYER_ENEMIES
	respawned += 1
	_party_changed()


func _tick_respawns() -> void:
	for p in people:
		if p.dead and WorldState.clock >= float(p.back_at):
			_respawn(p)


## The party is on while the barge is whole and anyone in the band or the DJ is
## still playing.
func party_on() -> bool:
	if wrecked:
		return false
	if not party_built:
		return true                   # the band is on, just not built yet
	for p in band:
		if not p.dead:
			return true
	return false


func _party_changed() -> void:
	if _music != null:
		_music.playlist = _playlist if party_on() else ""


# ------------------------------------------------------------------ fighting back

## The player hurt someone on board: the crowd and the guards fight back. Each is
## swapped where they stand for a real NpcBody (profiles content/core/soldiers/
## barge_*.json, "fighters" in the barge's data, wearing their own look; the
## unarmed share of the crowd, "armed_share", keeps dancing), one a
## tick, nearest the player first, run by a Townsfolk of the barge's own with
## standing off, so the fight costs no one's standing. The band plays on and the
## boss only shouts. Once their alarm is down, each walks back to its spot (which
## rides with the barge) and dances again (_tick_fight). Without the town's
## brains (npc_brains off) nobody fights.
func _provoke() -> void:
	if wrecked or demo == null or not bool(demo.get("npc_brains")) or not demo.has_method("make_npc"):
		return
	if _folk == null:
		_folk = demo.make_townsfolk("BargeFolk", [])
		_folk.standing = false
	fights += 1
	_folk.provoke()
	_calm_t = 0.0
	var kinds: Dictionary = cfg.get("fighters", {})
	var ppos: Vector3 = player.global_position if player != null and is_instance_valid(player) else global_position
	_rousing = people.filter(func(p): return not p.dead and p.fighter == null and p.armed and kinds.has(p.kind))
	_rousing.sort_custom(func(a, b): return to_global(a.spot).distance_to(ppos) < to_global(b.spot).distance_to(ppos))
	# The nearest one now: an alarm raised with nobody alive to fight stands down at once.
	if not _rousing.is_empty():
		_rouse(_rousing.pop_front())


func _rouse(p: Dictionary) -> void:
	var id := str(cfg.get("fighters", {}).get(p.kind, ""))
	var soldier: Dictionary = demo._content().get_soldier(id).duplicate(true)
	if soldier.is_empty():
		return
	soldier["archetype"] = p.look
	var here := to_global(p.spot)
	var f: Vector3 = global_basis * (Basis(Vector3.UP, float(p.yaw)) * Vector3.FORWARD)
	var g: NpcBody = demo.make_npc(soldier, here, atan2(-f.x, -f.z), "", "npc:%s/barge_%s" % [planet_id, p.node.name])
	g.free_walk = true                  # no navmesh out here: straight across the deck
	g.nav = null
	g.died.connect(_on_fighter_died.bind(p))
	p.fighter = g
	(p.node as Node3D).visible = false
	(p.hit as PartyHit).collision_layer = 0
	_folk.add_member(g)
	if _folk.alarm.active():
		g.perception.awareness = 1.0
		g.perception.noticed = true
	roused += 1


## Back to dancing: the fighter goes and the dancer is there again (still dead,
## if the fighter died: back at respawn like everyone).
func _settle(p: Dictionary) -> void:
	var g = p.fighter
	p.fighter = null
	if g != null and is_instance_valid(g):
		_folk.remove_member(g)
		g.queue_free()
	(p.node as Node3D).visible = true
	if not p.dead:
		p.hp = float(cfg.get("person_hp", 60))
		(p.hit as PartyHit).collision_layer = 0 if wrecked else LAYER_ENEMIES


func _on_fighter_died(p: Dictionary) -> void:
	p.dead = true
	p.back_at = WorldState.clock + float(cfg.get("respawn_s", 180.0))
	kills += 1


## One tick of the fight: the next fighters swapped in, every fighter's spot kept
## on the deck as it moves, and once the alarm has been down a moment, those back
## at their spot (or everyone, after calm_back_s) swapped back to dancing.
func _tick_fight(dt: float) -> void:
	if _folk == null:
		return
	var calm: bool = not _folk.alarm.active()
	_calm_t = _calm_t + dt if calm else 0.0
	var settled := _calm_t > 1.0
	if settled:
		_rousing.clear()
	for i in int(cfg.get("rouse_per_tick", 1)):
		if _rousing.is_empty():
			break
		var r: Dictionary = _rousing.pop_front()
		if not r.dead and r.fighter == null:
			_rouse(r)
	for p in people:
		var g = p.fighter
		if g == null or not is_instance_valid(g) or g.dead:
			continue
		var spot := to_global(p.spot)
		g.post_pos = spot
		var b = _folk.brains.get(g)
		if b != null:
			b.patrol_points = [spot]
		if settled and (g.global_position.distance_to(spot) < 1.2 or _calm_t > float(cfg.get("calm_back_s", 20.0))):
			_settle(p)


## Nobody counts shots fired here (PlayerWeapons.off_record_zone): on board, on
## the gangplank or on the sand round it.
func off_record(p: Vector3) -> bool:
	return p.distance_to(global_position) < float(cfg.get("off_record_m", 60.0))


# ------------------------------------------------------------------ taking it over

func hurt_boss(amount: float) -> void:
	if owned or amount <= 0.0:
		return
	var was := boss_hp
	boss_hp -= amount
	if was >= float(cfg.get("boss", {}).get("hp", 400)):
		_toast(line("boss_hurt"))
	if boss_hp <= 0.0:
		_take_over("beaten")


## Buy it: the boss's price in credits. False if you can't afford it.
func buy() -> bool:
	if owned:
		return false
	var price := int(cfg.get("boss", {}).get("price", 1500))
	if WorldState.credits < price:
		return false
	WorldState.credits -= price
	_take_over("bought")
	return true


func _take_over(how: String) -> void:
	owned = true
	WorldState.set_flag(owned_flag(planet_id))
	WorldState.log_event("Took %s from %s." % [barge_name, boss_name])
	_toast(line("bought" if how == "bought" else "boss_beaten"))
	_boss_below()
	taken_over.emit(how)


## The old boss goes below to the lounge and keeps on partying (and from now on
## is just another partygoer).
func _boss_below() -> void:
	if boss == null:
		return
	var spot := Vector3(-1.0, _y[1], -2.0)
	boss.position = spot
	for p in people:
		if p.node == boss:
			p.deck = "lower"
			p.spot = spot
			(p.hit as Node3D).position = spot


func line(key: String) -> String:
	var v = cfg.get("lines", {}).get(key, "")
	if v is Array:
		v = v[_rng.randi() % v.size()] if not (v as Array).is_empty() else ""
	return str(v).replace("{name}", barge_name).replace("{boss}", boss_name) \
		.replace("{price}", str(int(cfg.get("boss", {}).get("price", 1500))))


func _toast(text: String) -> void:
	var gear = demo.get("gear") if demo != null else null
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 5.0)


# ------------------------------------------------------------------ the control panel

func near_boss() -> bool:
	if owned or boss == null or player == null or wrecked:
		return false
	return player.global_position.distance_to(boss.global_position) <= float(cfg.get("boss", {}).get("reach_m", 4.5))


func near_console() -> bool:
	return player != null and not wrecked and player.global_position.distance_to(to_global(console_spot)) <= 2.2


## Step up to the panel (yours only). The player stands still at it, riding along,
## until they step away; the barge keeps its course either way.
func take_console() -> bool:
	if not owned or at_console or player == null or wrecked:
		return false
	at_console = true
	player.locked = true
	if not autopilot:
		course = heading
	var at := to_global(console_spot) + _up(global_position) * 0.05
	player.global_position = at
	player.velocity = Vector3.ZERO
	if "controller" in player and player.controller != null:
		player.controller.velocity = Vector3.ZERO
		player.controller.body_pos = at
	_toast(line("at_console"))
	console_taken.emit()
	return true


func leave_console() -> void:
	if not at_console:
		return
	at_console = false
	external = {}
	if player != null:
		player.locked = false
	_toast(line("let_go_cruising" if autopilot else "let_go"))
	console_left.emit()


## Under way on the course dialled in.
func engage() -> bool:
	if not owned or wrecked:
		return false
	autopilot = true
	blocked_by = ""
	_toast(line("engaged"))
	return true


func all_stop() -> void:
	if autopilot:
		_toast(line("all_stop"))
	autopilot = false


## Signed angle (radians, + to starboard) from a to b about up.
func _turn_to(a: Vector3, b: Vector3, up: Vector3) -> float:
	return -a.signed_angle_to(b, up)


## The course as the panel says it: degrees off the bow, to port or starboard.
func course_text() -> String:
	var deg := rad_to_deg(_turn_to(heading, course, _up(_ground)))
	if absf(deg) < 2.0:
		return line("dead_ahead")
	return line("to_port" if deg < 0.0 else "to_starboard").replace("{deg}", str(int(roundf(absf(deg)))))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_t += dt
	_tick += 1
	if wrecked:
		if WorldState.clock >= _rebuild_at:
			_rebuild()
		_record_xf()
		return
	if not _pending.is_empty():
		_build_party()
	_read_input(dt)
	var was := global_transform
	_move(dt)
	_carry = global_transform * was.affine_inverse()
	_animate(dt)
	_tick_fight(dt)
	if _tick % 30 == 0:
		_tick_respawns()
	_record_xf()


## Note this tick's resting transform for render smoothing (BargeLook draws
## between the last two).
func _record_xf() -> void:
	var f := Engine.get_physics_frames()
	if _xf_frame < 0 or f - _xf_frame > 1 or _xf_curr.origin.distance_to(global_transform.origin) > 4.0:
		_xf_prev = global_transform
	else:
		_xf_prev = _xf_curr
	_xf_curr = global_transform
	_xf_frame = f


## Setting look.transform moves every node under it (the hull, the people, the
## club), so it is only set while the barge is moving between ticks.
func _process(_dt: float) -> void:
	if look == null:
		return
	var want := Transform3D.IDENTITY
	if CharBody.smoothing_active() and Engine.get_physics_frames() - _xf_frame <= 1 and _xf_prev != _xf_curr:
		var at := _xf_prev.interpolate_with(_xf_curr, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))
		want = global_transform.affine_inverse() * at
	if look.transform != want:
		look.transform = want
	if dressing != null and _awake:
		dressing.show_panel(_turn_to(heading, course, _up(_ground)), autopilot, blocked_by != "")


func _read_input(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var e := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	var text := ""
	var gear = demo.get("gear") if demo != null else null
	var gear_busy: bool = gear != null and not (gear.focus as Dictionary).is_empty()
	if at_console:
		if e:
			leave_console()
		else:
			var dial := _axis("move_left", "move_right")
			var go := _just("move_forward")
			var halt := _just("move_back")
			if not external.is_empty():
				dial = float(external.get("dial", 0.0))
				go = bool(external.get("engage", false))
				halt = bool(external.get("stop", false))
				external.erase("engage")
				external.erase("stop")
			if dial != 0.0:
				course = course.rotated(_up(_ground), -dial * deg_to_rad(float(cfg.get("drive", {}).get("dial_deg_s", 30.0))) * dt)
			if go:
				engage()
			elif halt:
				all_stop()
			text = line("console_under_way" if autopilot else "console").replace("{course}", course_text())
	elif not player.locked and not bool(player.get("piloting")) and not gear_busy:
		if near_console():
			text = line("console_prompt")
			if e:
				if owned:
					take_console()
				else:
					_toast(line("console_locked"))
		elif near_boss():
			var can_buy := WorldState.credits >= int(cfg.get("boss", {}).get("price", 1500))
			text = line("buy_prompt" if can_buy else "talk_prompt")
			if e:
				if can_buy:
					buy()
				else:
					_toast(line("talk"))
	if _prompt != null:
		_prompt.text = text
		_prompt.visible = text != ""


func _axis(neg: String, pos: String) -> float:
	var a := 0.0
	if InputMap.has_action(pos) and Input.is_action_pressed(pos):
		a += 1.0
	if InputMap.has_action(neg) and Input.is_action_pressed(neg):
		a -= 1.0
	return a


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## On autopilot: swing round to the course and go, slowly, slower in a tight turn.
## Off it: it comes to a stop and stays put (nobody's barge never moves; parked,
## nothing here runs, so its colliders stay still). Into anything: dead stop.
func _move(dt: float) -> void:
	if not autopilot and speed <= 0.001:
		speed = 0.0
		if not gangplank_down:
			_gangplank(true)
		return
	var d: Dictionary = cfg.get("drive", {})
	var up := _up(_ground)
	var want := heading
	var target := 0.0
	var rate := float(d.get("turn_rate", 0.22))
	if autopilot:
		want = _flat(course, _ground).normalized()
		course = want
		var off := absf(_turn_to(heading, want, up))
		target = float(d.get("max_speed", 4.5)) * clampf(1.0 - off / (PI * 0.4), 0.0, 1.0)
	var accel := float(d.get("accel", 0.6)) if target > speed else float(d.get("brake", 1.2))
	speed = move_toward(speed, target, accel * dt)
	var err := _turn_to(heading, want, up)
	heading = heading.rotated(up, -clampf(err, -rate * dt, rate * dt))
	if _tick % 6 == 0:
		_measure_lift()
		if speed > 0.05:
			var what := _ahead()
			if what != "":
				_stop_against(what)
	if speed > 0.001:
		var step := heading * speed * dt
		_ground = _ground_at(_ground + step)
		travelled += step.length()
	_place(dt)
	if _tick % 3 == 0 and speed > float(cfg.get("beast_min_speed", 0.3)) and _touching_beast():
		explode()
		return
	var down := not autopilot and speed < 0.3
	if down != gangplank_down:
		_gangplank(down)


## What is just ahead of the bow, low and high, or "" when clear: the world's
## boxes, rocks and columns (WorldGround.hit). The sand itself is never in the way.
func _ahead() -> String:
	if ground == null:
		return ""
	var reach := speed * 0.6 + 0.6
	var prow := float(cfg.get("prow_m", 6.0))
	var fwd := global_transform.basis * Vector3(0, 0, -1)
	for y in [_y[0] + 0.6, _y[2] + 1.0]:
		for x in [-_W * 0.5, 0.0, _W * 0.5]:
			var z := -_L * 0.5 - (prow * 0.8 if x == 0.0 else 0.0)
			var p := to_global(Vector3(x, y, z)) + fwd * reach
			var what := ground.hit(p, 0.8)
			if what != "":
				return what
	return ""


func _stop_against(what: String) -> void:
	speed = 0.0
	stops += 1
	blocked_by = what
	if autopilot:
		autopilot = false
		_toast(line("blocked"))
		blocked.emit(what)


func _beast():
	var b = demo.get("beast") if demo != null else null
	if b == null or not is_instance_valid(b) or bool(b.get("dead")):
		return null
	return b


## Whether any part of the beast (its head or a segment) is inside the hull's box.
func _touching_beast() -> bool:
	var b = _beast()
	if b == null:
		return false
	var spheres := [[(b as Node3D).global_position, float(b.get("radius"))]]
	for s in b.get("segments"):
		spheres.append([(s.node as Node3D).global_position, float(s.r)])
	var inv := global_transform.affine_inverse()
	var lo := Vector3(-_W * 0.5, 0.0, -_L * 0.5 - float(cfg.get("prow_m", 6.0)))
	var hi := Vector3(_W * 0.5, _y[2] + 1.2, _L * 0.5)
	for s in spheres:
		var l: Vector3 = inv * (s[0] as Vector3)
		var q := l.clamp(lo, hi)
		if q.distance_to(l) <= float(s[1]):
			return true
	return false


func _gangplank(down: bool) -> void:
	gangplank_down = down
	for cs in _plank_shapes:
		(cs as CollisionShape3D).set_deferred("disabled", not down)
	for mi in look.get_children():
		if mi is MeshInstance3D and mi.has_meta("gangplank"):
			(mi as MeshInstance3D).visible = down


# ------------------------------------------------------------------ blowing up

## Up it goes: fire along the hull, everyone on board gone with it, anyone standing
## on it hurt and thrown clear. It is built again at its home after rebuild_s
## seconds of play (still yours, if it was).
func explode() -> void:
	if wrecked:
		return
	var up := _up(global_position)
	if player != null and is_instance_valid(player) and aboard(player.global_position):
		if at_console:
			leave_console()
		var away := _flat(player.global_position - global_position, global_position).normalized()
		player.apply_damage_from(float(cfg.get("blast_damage", 70)), self)
		if player.has_method("launch"):
			player.launch(up * 9.0 + away * 4.0, away * 6.0, 3.0)
	at_console = false
	autopilot = false
	speed = 0.0
	wrecked = true
	wrecks += 1
	for k in 3:
		var at := to_global(Vector3(_rng.randf_range(-2.0, 2.0), _y[1], lerpf(-_L * 0.35, _L * 0.35, k / 2.0)))
		ExplosionFx.big(get_parent(), at, 2.4)
		Sound.play("vehicle_boom", at)
	look.visible = false
	for cs in _shapes:
		(cs as CollisionShape3D).set_deferred("disabled", true)
	_rousing.clear()
	for p in people:
		if p.fighter != null:
			_settle(p)               # the fighters go up with it too
		(p.hit as PartyHit).collision_layer = 0
	_rebuild_at = WorldState.clock + float(cfg.get("rebuild_s", 240.0))
	_party_changed()
	if _prompt != null:
		_prompt.visible = false
	_toast(line("exploded"))
	exploded.emit()


func _rebuild() -> void:
	wrecked = false
	_ground = home
	heading = _flat(heading, home).normalized()
	course = heading
	speed = 0.0
	blocked_by = ""
	_measure_lift()
	_place(0.0)
	look.visible = true
	for cs in _shapes:
		(cs as CollisionShape3D).set_deferred("disabled", false)
	_gangplank(true)
	for p in people:
		if p.dead:
			_respawn(p)
		else:
			(p.hit as PartyHit).collision_layer = LAYER_ENEMIES
	_party_changed()
	rebuilt.emit()


func _build_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-360, -170)
	_prompt.size = Vector2(720, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	layer.add_child(_prompt)
