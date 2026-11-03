class_name AtmoFlight
extends RefCounted
## Flying a ship inside the planet's air (M14). Pure and headless-testable: the M10
## flight model plus the things that only matter near a planet -- the ground, the
## town's buildings, taking off, landing, crashing, and the air thinning out until
## space. The ship node (ShipPilot) reads input and draws; this decides.
##
## States:
##   PARKED   -- sitting on the ground. takeoff() lifts it.
##   LIFTOFF  -- rising straight up (wings levelled) to `liftoff_height` above the
##               ground, then FLYING at zero throttle (hovering).
##   FLYING   -- arcade flight: the ship moves along its nose. Zero throttle hovers
##               (this is a VTOL fighter, not a plane). The air thins with
##               altitude, so top speed rises toward `edge_speed_mult` x at the edge
##               of space; climbing nose-up costs speed (`climb_drag`).
##               Touching down gently lands it; hitting the ground or a building
##               faster than `crash_speed` crashes it.
##   LANDING  -- land() within `land_max_agl` of the ground: brakes to a stop,
##               levels, and settles straight down onto whatever is below.
##               abort_landing() calls it off: FLYING again at zero throttle,
##               coasting to a stop over `land_abort_coast` seconds.
##   CRASHED  -- stopped; the scene decides what happens next.
##   ADRIFT   -- issue #276: nobody at the controls (the pilot ejected). Zero
##               throttle, so nothing holds her up: she carries on with the momentum
##               she had, air drag (`adrift_drag`, per second) bleeding it off and
##               gravity (`adrift_gravity`) pulling her down, her nose turning
##               (`adrift_nose_rate`) the way she is going. Hitting the ground or a
##               building faster than `crash_speed` damages her: she crashes. Slower,
##               she comes to rest there, PARKED.
##
## Every number comes from the ship's "atmosphere" block (and its turn rates from
## "flight") in content/core/ships/*.json; where space starts comes from the world.

const FlightModel := preload("res://src/systems/flight/flight_model.gd")

enum State { PARKED, LIFTOFF, FLYING, LANDING, CRASHED, ADRIFT }

var cfg: Dictionary = {}        ## the ship's "atmosphere" block
var flight                      ## FlightModel (atmosphere speeds)
var ground: WorldGround
var state := State.PARKED
var events: Array = []          ## this step's events: { type, ... }
var space_altitude := 8000.0
var upper_start := 600.0
var clearance := 1.0            ## origin to belly, metres (the scene may set it from the model)
var body_radius := 2.0
var reached_space := false
var air_cap := INF              ## the most air_scale() may be here (ShipPilot eases it down by the cruiser)
var last_hit := ""
var crash_point := Vector3.ZERO
var drift := Vector3.ZERO       ## issue #276: her velocity while ADRIFT (m/s, world)
var coast_left := 0.0           ## landing called off (C again): seconds left of easing to a stop
var _coast_rate := 0.0          ## m/s per second she slows by while coasting

var _command := { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.0, "boost": false }


func setup(ship_cfg: Dictionary, world_ground: WorldGround) -> void:
	cfg = ship_cfg.get("atmosphere", {})
	var fc: Dictionary = (ship_cfg.get("flight", {}) as Dictionary).duplicate()
	for k in ["min_speed", "max_speed", "boost_speed", "accel", "boost_time", "boost_recharge", "boost_turn_scale"]:
		if cfg.has(k):
			fc[k] = cfg[k]
	flight = FlightModel.new(fc)
	flight.throttle = 0.0
	flight.speed = 0.0
	ground = world_ground
	clearance = float(cfg.get("clearance", clearance))
	body_radius = float(cfg.get("body_radius", body_radius))
	if ground != null:
		var atmo := ground.atmosphere()
		space_altitude = float(atmo.get("space_altitude", space_altitude))
		upper_start = float(atmo.get("upper_start", upper_start))


func p(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# ---- queries ----------------------------------------------------------------

func position() -> Vector3:
	return flight.position


func transform() -> Transform3D:
	return flight.transform()


func speed() -> float:
	return flight.speed


## "Up" where the ship is: straight up on a flat world and over the town, away
## from the planet's centre out over the home planet's ball (issue #77).
func up() -> Vector3:
	return ground.up_at(flight.position) if ground != null else Vector3.UP


## Height of the belly above whatever is under the ship, along up: the highest
## ground under its footprint (centre and four points around it), so a ship set
## down on a slope rests on it instead of sinking in.
func agl() -> float:
	if ground == null:
		return flight.position.y - clearance
	var u := up()
	var belly: Vector3 = flight.position - u * clearance
	var h := ground.height_above(belly)
	var b: Basis = flight.basis
	var fx := (b.x - u * b.x.dot(u)).normalized() * body_radius
	var fz := (b.z - u * b.z.dot(u)).normalized() * body_radius
	for off in [fx, -fx, fz, -fz]:
		h = minf(h, ground.height_above(belly + off))
	return h


## World y of the ground under the ship (flat-world readers; on the ball this is
## the point straight down along up).
func ground_below() -> float:
	return (flight.position - up() * (clearance + agl())).y


## Altitude above the planet's curved sea level (what "space" is measured against).
func altitude() -> float:
	return ground.altitude(flight.position) if ground != null else flight.position.y


## 0 at sea level, 1 at the edge of space.
func space_fraction() -> float:
	return clampf(altitude() / maxf(space_altitude, 1.0), 0.0, 1.0)


## How much faster thin air lets the ship go here (1 near the ground).
func air_scale() -> float:
	var k := clampf((altitude() - upper_start) / maxf(space_altitude - upper_start, 1.0), 0.0, 1.0)
	return minf(1.0 + (p("edge_speed_mult", 4.0) - 1.0) * pow(k, p("speed_curve", 1.0)), air_cap)


func can_land(known_agl: float = -INF) -> bool:
	var current_agl := agl() if not is_finite(known_agl) else known_agl
	if state != State.FLYING or current_agl > p("land_max_agl", 150.0):
		return false
	var at := position()
	return ground == null or ground.landable(at.x, at.z)


## A basis facing `yaw` radians about this planet's up at `at`.
func _upright(at: Vector3, yaw: float) -> Basis:
	var u: Vector3 = ground.up_at(at) if ground != null else Vector3.UP
	return PlanetSphere.tilt_to(u) * Basis(Vector3.UP, yaw)


func state_label() -> String:
	return State.keys()[state]


# ---- control ------------------------------------------------------------------

## Put the ship down at `at` (its belly on the ground there), facing `yaw` radians.
func park(at: Vector3, yaw: float) -> void:
	flight.basis = _upright(at, yaw)
	var u := up() if ground != null else Vector3.UP
	flight.position = at + u * (0.5 + clearance)
	if ground != null:
		flight.position -= up() * agl()
	flight.speed = 0.0
	flight.throttle = 0.0
	_command.throttle = 0.0
	state = State.PARKED


## Place the ship in the air, flying (a re-entry arrival or a test).
func place_flying(at: Vector3, facing: Vector3, speed_now: float, throttle: float) -> void:
	flight.position = at
	flight.face(facing, up())
	flight.speed = speed_now
	flight.throttle = throttle
	_command.throttle = throttle
	state = State.FLYING


func set_command(pitch: float, yaw: float, roll: float, throttle: float, boost: bool) -> void:
	_command = { "pitch": clampf(pitch, -1.0, 1.0), "yaw": clampf(yaw, -1.0, 1.0),
		"roll": clampf(roll, -1.0, 1.0), "throttle": clampf(throttle, 0.0, 1.0), "boost": boost }


func takeoff() -> bool:
	if state != State.PARKED:
		return false
	state = State.LIFTOFF
	events.append({ "type": "liftoff" })
	return true


## Issue #276: the pilot is gone. From the air only; she keeps the velocity she
## had and goes ADRIFT.
func abandon() -> bool:
	if state != State.FLYING and state != State.LANDING:
		return false
	drift = flight.velocity()
	if state == State.LANDING:
		drift -= up() * p("land_descent", 12.0)   # she was settling as well
	flight.throttle = 0.0
	_command = { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.0, "boost": false }
	state = State.ADRIFT
	return true


func land() -> bool:
	if not can_land():
		return false
	state = State.LANDING
	coast_left = 0.0
	events.append({ "type": "landing" })
	return true


## C again while LANDING: called off. FLYING at zero throttle, the way she was going
## easing to a stop over `land_abort_coast` seconds (any throttle or boost ends that).
func abort_landing() -> bool:
	if state != State.LANDING:
		return false
	state = State.FLYING
	flight.throttle = 0.0
	_command.throttle = 0.0
	coast_left = p("land_abort_coast", 2.0)
	_coast_rate = float(flight.speed) / maxf(coast_left, 0.01)
	return true


# ---- frame --------------------------------------------------------------------

## Advance one frame. Returns this step's events.
func step(dt: float) -> Array:
	events = []
	match state:
		State.LIFTOFF:
			_step_liftoff(dt)
		State.FLYING:
			_step_flying(dt)
		State.LANDING:
			_step_landing(dt)
		State.ADRIFT:
			_step_adrift(dt)
	return events


func _step_liftoff(dt: float) -> void:
	var left := p("liftoff_height", 18.0) - agl()
	var rise := minf(left, maxf(1.5, minf(p("liftoff_speed", 7.0), left * 1.5)) * dt)
	var u := up()
	flight.position += u * rise
	flight.basis = _level(flight.basis, dt * 3.0, u)
	if left <= 0.05:
		state = State.FLYING
		flight.speed = 0.0
		flight.throttle = 0.0
		_command.throttle = 0.0
		events.append({ "type": "airborne" })


func _step_flying(dt: float) -> void:
	var climb: float = flight.forward().dot(up())
	flight.speed_scale = air_scale() * (1.0 - p("climb_drag", 0.3) * maxf(0.0, climb))
	flight.accel_scale = maxf(air_scale(), 1.0)   # capped under 1, she still brakes as hard as ever
	if coast_left > 0.0:
		coast_left -= dt
		if float(_command.get("throttle", 0.0)) > 0.0 or bool(_command.get("boost", false)):
			coast_left = 0.0
		else:
			flight.accel_scale = _coast_rate / maxf(float(flight.cfg.get("accel", 25.0)), 0.01)
	_shed_overspeed(dt)
	flight.set_command_dict(_command)
	var before: Vector3 = flight.position
	flight.step(dt)
	_check_space()
	_collide(before, dt)


## Faster than this air lets her go (a space fight's speed handed on, or diving
## into thicker air): the excess over its top speed falls away smoothly
## (overspeed_brake per second), on top of the normal braking, so coming home
## from space she is back to air speeds well before the ground. Climb drag is
## left out, so pulling up does not bleed her any harder than before.
func _shed_overspeed(dt: float) -> void:
	var top := p("max_speed", 170.0)
	if flight.boosting:
		top = p("boost_speed", top * 1.5)
	top *= air_scale()
	if flight.speed > top:
		flight.speed = top + (flight.speed - top) * exp(-p("overspeed_brake", 1.0) * dt)


func _step_landing(dt: float) -> void:
	flight.speed = move_toward(flight.speed, 0.0, p("land_brake", 45.0) * dt)
	var u := up()
	flight.basis = _level(flight.basis, dt * 2.0, u)
	var before: Vector3 = flight.position
	var fwd: Vector3 = flight.forward()
	var h: Vector3 = (fwd - u * fwd.dot(u)).normalized() * float(flight.speed) * dt
	var a := agl()
	var down := p("land_descent", 12.0) if a > 8.0 else p("land_slow", 4.0)
	var drop := minf(down * dt, maxf(a, 0.0))
	flight.position = before + h - u * drop
	if ground.hit(flight.position, body_radius) != "":
		flight.position = before - u * drop    # sliding into something: only go down
		flight.speed = 0.0
	if agl() <= 0.02:
		_touch_down()


func _collide(before: Vector3, dt: float) -> void:
	if ground == null:
		return
	var pos: Vector3 = flight.position
	var hit_id := ground.hit(pos, body_radius)
	if hit_id != "":
		last_hit = hit_id
		if flight.speed > p("crash_speed", 32.0):
			_crash(pos, hit_id)
			return
		flight.position = before                  # bumped: stop against it
		flight.speed = 0.0
		events.append({ "type": "bump", "what": hit_id })
		return
	var u := up()
	var h := ground.height_above(pos - u * clearance)
	if h <= 0.0:
		var vertical: float = maxf(0.0, (before - pos).dot(u) / maxf(dt, 0.0001))
		if flight.speed > p("crash_speed", 32.0) and vertical > 4.0:
			_crash(pos - u * (clearance + h), "ground")
			return
		flight.position = pos - u * h
		if flight.speed <= p("touchdown_speed", 9.0):
			_touch_down()
		else:
			flight.speed = move_toward(flight.speed, 0.0, p("land_brake", 45.0) * dt)  # skidding
			events.append({ "type": "scrape" })


func _step_adrift(dt: float) -> void:
	var u := up()
	drift -= u * p("adrift_gravity", 20.0) * dt
	drift -= drift * minf(1.0, p("adrift_drag", 0.12) * dt)
	var before: Vector3 = flight.position
	flight.position = before + drift * dt
	flight.speed = drift.length()
	# The nose follows her way through the air, as far as she is going somewhere:
	# dropped from a hover she falls flat.
	var across := (drift - u * drift.dot(u)).length()
	if across > 1.0:
		var dir: Vector3 = drift / flight.speed
		var hint: Vector3 = flight.basis.y if absf(dir.dot(flight.basis.y)) < 0.99 else flight.basis.z
		var want := Basis.looking_at(dir, hint)
		var w := minf(1.0, p("adrift_nose_rate", 0.7) * dt * across / flight.speed)
		var q: Quaternion = flight.basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), w)
		flight.basis = Basis(q).orthonormalized()
	if ground == null:
		return
	var hit_id := ground.hit(flight.position, body_radius)
	if hit_id != "":
		last_hit = hit_id
		if flight.speed > p("crash_speed", 32.0):
			_crash(flight.position, hit_id)
			return
		flight.position = before                  # against it: only fall from here
		drift = -u * maxf(0.0, -drift.dot(u))
		flight.speed = drift.length()
		events.append({ "type": "bump", "what": hit_id })
		return
	var h := agl()
	if h <= 0.0:
		if flight.speed > p("crash_speed", 32.0):
			_crash(flight.position - u * (clearance + h), "ground")
			return
		drift = Vector3.ZERO
		_touch_down()


func _touch_down() -> void:
	flight.position -= up() * agl()
	flight.basis = _level(flight.basis, 1.0, up())
	flight.speed = 0.0
	flight.throttle = 0.0
	_command.throttle = 0.0
	state = State.PARKED
	events.append({ "type": "landed", "at": flight.position })


func _crash(at: Vector3, what: String) -> void:
	crash_point = at
	flight.speed = 0.0
	state = State.CRASHED
	events.append({ "type": "crashed", "at": at, "what": what })


func _check_space() -> void:
	if not reached_space and altitude() >= space_altitude:
		reached_space = true
		events.append({ "type": "reached_space", "altitude": altitude() })


## Ease a basis toward wings-level (against `up`), keeping its heading.
static func _level(b: Basis, w: float, up: Vector3 = Vector3.UP) -> Basis:
	var fwd := -b.z
	var flat := fwd - up * fwd.dot(up)
	if flat.length_squared() < 0.0001:
		var by := b.y - up * b.y.dot(up)
		flat = by if by.length() > 0.01 else (Vector3.FORWARD - up * up.z).normalized()
	var want := Basis.looking_at(flat.normalized(), up)
	var q := b.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), clampf(w, 0.0, 1.0))
	return Basis(q).orthonormalized()


# ---- hand-off ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var d: Dictionary = flight.to_dict()
	d["state"] = state_label()
	return d
