class_name AltitudeDetail
extends Node
## Less detail the higher you fly (issue #46). The town is lit for standing in it:
## real-time GI (SDFGI), SSAO, SSIL, volumetric fog, four shadow splits, lamps,
## people and hundreds of boulders. From a ship climbing at 300 m/s none of that
## reads, and SDFGI rebuilds its cascades every time the camera moves that fast,
## which is what made flying laggy. Each tier switches render features off and
## hides groups of nodes once you are above it, and gives them back on the way
## down (`hysteresis` metres lower, so hovering at a boundary never flickers).
## Issue #535: SDFGI and the sun's shadows fade out and in over a few tenths of a
## second as a tier takes or gives them (LookEnvironment._apply_quality(true)).
##
## Tiers are data: the "detail" block of content/core/worlds/<id>.json.
##   off:  LookEnvironment features ("sdfgi", "ssil", "ssao", "volumetric", "shadows")
##   hide: node groups this scene registers with add_group() ("people", "props")
## A hidden group's nodes also stop processing (NPC brains, the bar), so the
## CPU gets the same break as the GPU. Pure tier maths in tier_for(), for tests.

var tiers: Array = []                ## [{ above, off: [], hide: [] }], ascending
var hysteresis := 60.0
var look: LookEnvironment
var groups := {}                     ## name -> [Node]
var tier := -1                       ## index of the highest tier in force, -1 = full detail
var changes := 0                     ## tier changes so far (tests, traces)
var motion_cfg: Dictionary = {}
var motion_active := false
var motion_changes := 0               ## motion override transitions (tests, traces)
var _motion_enter_s := 0.0
var _motion_restore_s := 0.0


func _init() -> void:
	name = "AltitudeDetail"


func setup(cfg: Dictionary, look_env: LookEnvironment = null) -> void:
	look = look_env
	hysteresis = float(cfg.get("hysteresis", hysteresis))
	motion_cfg = cfg.get("motion", {})
	motion_active = false
	_motion_enter_s = 0.0
	_motion_restore_s = 0.0
	tiers = []
	for t in cfg.get("tiers", []):
		tiers.append({ "above": float(t.get("above", 0.0)), "off": t.get("off", []), "hide": t.get("hide", []) })
	tiers.sort_custom(func(a, b): return a.above < b.above)


## Nodes that `hide` can switch off as one (nulls and nodes already in the group
## are skipped). Issue #121: a node added while its group is held off (built
## after the ship had already climbed) is switched off at once, like the rest of
## its group; one added while the group is shown is left as it is.
func add_group(group: String, nodes: Array) -> void:
	var list: Array = groups.get(group, [])
	var held_off := hidden_groups().has(group)
	for n in nodes:
		if n != null and not list.has(n):
			list.append(n)
			if held_off and is_instance_valid(n):
				_show(n, false)
	groups[group] = list


## The tier for `altitude`, coming from tier `current`: climbing past a tier's
## `above` enters it, and you only leave it `hysteresis` metres below that.
func tier_for(altitude: float, current: int) -> int:
	var t := -1
	for i in tiers.size():
		var edge: float = tiers[i].above - (hysteresis if i <= current else 0.0)
		if altitude >= edge:
			t = i
	return t


## Call every frame with the viewer's altitude above sea level.
func _set_tier_for(altitude: float) -> bool:
	if look != null:
		look.set_view_altitude(altitude)     # issue #535: the sun's shadows reach the ground below
	var t := tier_for(altitude, tier)
	if t == tier:
		return false
	tier = t
	changes += 1
	return true


func update_for(altitude: float) -> void:
	if _set_tier_for(altitude):
		_apply()


## A flight-only quality override with separate enter/exit thresholds and time holds.
## Speed is metres per second; turn_rate is degrees per second. Non-flight states
## always restore the motion tier immediately, so walking and landed views stay crisp.
func update_motion(dt: float, altitude: float, speed: float, turn_rate: float, flying: bool) -> void:
	var tier_changed := _set_tier_for(altitude)
	var was_active := motion_active
	var enabled := not motion_cfg.is_empty()
	var above := float(motion_cfg.get("above", 550.0))
	var altitude_exit := above - float(motion_cfg.get("altitude_hysteresis", 60.0))
	var enter_speed := float(motion_cfg.get("enter_speed", 80.0))
	var exit_speed := float(motion_cfg.get("exit_speed", 35.0))
	var enter_turn := float(motion_cfg.get("enter_turn_deg_s", 90.0))
	var exit_turn := float(motion_cfg.get("exit_turn_deg_s", 30.0))
	var enter_hold := float(motion_cfg.get("enter_s", 0.1))
	var restore_hold := float(motion_cfg.get("restore_s", 0.75))
	if not flying or not enabled:
		motion_active = false
		_motion_enter_s = 0.0
		_motion_restore_s = 0.0
	elif motion_active:
		var should_restore := altitude < altitude_exit or (speed <= exit_speed and turn_rate <= exit_turn)
		if should_restore:
			_motion_restore_s += maxf(dt, 0.0)
			if _motion_restore_s >= restore_hold:
				motion_active = false
				_motion_restore_s = 0.0
		else:
			_motion_restore_s = 0.0
	else:
		var should_enter := altitude >= above and (speed >= enter_speed or turn_rate >= enter_turn)
		if should_enter:
			_motion_enter_s += maxf(dt, 0.0)
			if _motion_enter_s >= enter_hold:
				motion_active = true
				_motion_enter_s = 0.0
		else:
			_motion_enter_s = 0.0
	if motion_active != was_active:
		motion_changes += 1
	if tier_changed or motion_active != was_active:
		_apply()


## Everything off at or below the current tier, everything else back on.
func _apply() -> void:
	var off: Array = []
	var hidden := {}
	for i in tier + 1:
		off.append_array(tiers[i].off)
		for g in tiers[i].hide:
			hidden[str(g)] = true
	if motion_active:
		if not off.has("shadows"):
			off.append("shadows")
		hidden["small_props"] = true
	if look != null:
		look.set_suppressed(off)
	for g in groups:
		var show := not hidden.has(g)
		for n in groups[g]:
			if is_instance_valid(n):
				_show(n, show)


func _show(n: Node, show: bool) -> void:
	if n is Node3D or n is CanvasItem:
		n.visible = show
	n.process_mode = Node.PROCESS_MODE_INHERIT if show else Node.PROCESS_MODE_DISABLED


## What is held off right now (for the HUD, tests and traces).
func suppressed() -> Array:
	return look.suppressed.keys() if look != null else []


func hidden_groups() -> Array:
	var out: Array = []
	for i in tier + 1:
		for g in tiers[i].hide:
			if not out.has(g):
				out.append(g)
	if motion_active and not out.has("small_props"):
		out.append("small_props")
	return out
