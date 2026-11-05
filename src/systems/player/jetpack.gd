extends RefCounted
## Jetpack (M13). Pure and headless-testable, like the M1 character controller.
## It owns the fuel meter (the pack's stamina) and decides, each physics frame,
## how much upward thrust to add. The player node feeds it "is jump held" and "am I
## on the ground"; the controller adds the thrust to its vertical velocity.
##
## How it plays:
##   - Tap jump: an ordinary jump. Thrust only starts once jump has been held for
##     `kick_in` seconds in the air, so taps never burn fuel.
##   - Hold jump: after the kick-in, thrust pushes up (stronger than gravity) until
##     you let go or the fuel runs out, capped at `max_rise` m/s.
##   - Fuel is seconds of thrust. It refills after `recharge_delay` seconds of not
##     thrusting: at `recharge_ground` per second on the ground, `recharge_air` in
##     the air (0 by default, so you cannot feather a hover forever).
##   - An empty pack needs `min_fuel_to_start` before it will light again, so it
##     does not stutter on the last drops.
##   - Lighting it shoves you forward at `push` m/s on top of your own movement,
##     fading by `push_fade` m/s per second (the body applies it, see
##     character_body.gd).
##
## Every number comes from the item's "jetpack" block in content/core/items/*.json.

var cfg: Dictionary
var fuel := 0.0
var thrusting := false
var _held_for := 0.0        ## seconds jump has been held this press
var _since_thrust := 1000.0
var _was_held := false
## Out in space (character_body.space_recharge): refuel in the air at this rate
## instead of recharge_air(). Below 0: the item's own.
var air_recharge_override := -1.0

## Totals for traces and the HUD.
var burns := 0              ## times the pack lit
var burned := 0.0           ## seconds of thrust used


func _init(jet_cfg: Dictionary = {}) -> void:
	cfg = jet_cfg
	fuel = fuel_max()


# ---- tuning (data-driven, with safe defaults) ------------------------------

func fuel_max() -> float:
	return float(cfg.get("fuel", 1.8))


func thrust() -> float:
	return float(cfg.get("thrust", 36.0))


func max_rise() -> float:
	return float(cfg.get("max_rise", 9.0))


func kick_in() -> float:
	return float(cfg.get("kick_in", 0.18))


func min_fuel_to_start() -> float:
	return float(cfg.get("min_fuel_to_start", 0.2))


func recharge_delay() -> float:
	return float(cfg.get("recharge_delay", 0.8))


func recharge_ground() -> float:
	return float(cfg.get("recharge_ground", 0.6))


func recharge_air() -> float:
	return float(cfg.get("recharge_air", 0.0))


## The shove forward as the pack lights (m/s), and how fast it fades (m/s per second).
func push() -> float:
	return float(cfg.get("push", 0.0))


func push_fade() -> float:
	return float(cfg.get("push_fade", 5.0))


## 0..1, for the HUD meter.
func fraction() -> float:
	return clampf(fuel / maxf(fuel_max(), 0.001), 0.0, 1.0)


func is_full() -> bool:
	return fuel >= fuel_max() - 0.0001


# ---- frame --------------------------------------------------------------------

## Advance one physics frame. Returns the upward acceleration (m/s^2) to add this
## frame: thrust() while burning, else 0.
func step(dt: float, jump_held: bool, on_ground: bool) -> float:
	if jump_held:
		_held_for = (_held_for + dt) if _was_held else dt
	else:
		_held_for = 0.0
	_was_held = jump_held

	var want := jump_held and not on_ground and _held_for >= kick_in()
	if want and not thrusting:
		# Lighting the pack needs a little in the tank; keeping it lit does not.
		want = fuel >= min_fuel_to_start()
	if want and fuel > 0.0:
		if not thrusting:
			burns += 1
		thrusting = true
		var use := minf(fuel, dt)
		fuel -= use
		burned += use
		_since_thrust = 0.0
		return thrust()

	thrusting = false
	_since_thrust += dt
	if _since_thrust >= recharge_delay():
		var air := air_recharge_override if air_recharge_override >= 0.0 else recharge_air()
		var rate := recharge_ground() if on_ground else air
		fuel = minf(fuel_max(), fuel + rate * dt)
	return 0.0


## Fill the tank (a fresh pack, or a test).
func refill() -> void:
	fuel = fuel_max()


# ---- save -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return { "fuel": fuel }


func from_dict(d: Dictionary) -> void:
	fuel = clampf(float(d.get("fuel", fuel_max())), 0.0, fuel_max())
