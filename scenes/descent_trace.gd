extends Node
## Issue #574 descent trace (rendered, the real scene changes): the judge for
## "seamless space-to-ground flight including flying low". For each planet in
## ROUTES: start in open space just outside its bubble, fly in (its scene takes
## over with no fade), dive to LOW_AGL metres over the ground, skim for LOW_S
## seconds at full throttle with boost, then climb out until open space takes
## over again. Frame times are measured per leg (open, switch, descent, low,
## climb) as p50 / p95 / p99 / worst, against the budget below, and every frame
## over the budget is listed with what ran on it (staged build steps, the
## altitude tier, terrain mesh uploads). The low pass also checks the ship's
## height read-out against the height function (the ground you can hit is the
## height function, not the drawn mesh).
##
## Writes test_results/descent_trace.txt. Run it rendered as the main scene:
##   godot --rendering-driver vulkan --path . res://scenes/descent_trace.tscn
## It boots the real town (the bar loads and saves the save in play): back up
## user://save*.json first.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const OUT := "res://test_results/descent_trace.txt"
const SWITCH_BUDGET_MS := 50.0          ## the switch frame
const FRAME_BUDGET_MS := 33.0           ## every other frame
const LOW_AGL := 30.0
const LOW_S := 60.0
var ROUTES: Array = OS.get_environment("DESCENT_ROUTES").split(",") if OS.get_environment("DESCENT_ROUTES") != "" else ["port_desert", "grit_station"]   ## DESCENT_ROUTES=port_desert: one

var lines := PackedStringArray()
var demo
var phase := "setup"
var route := ""
var _last := 0
var _frames: Array = []                 ## { route, phase, ms, note }
var _staged_seen := 0
var _uploads_seen := 0
var _tier_seen := -2
var _scene_id := 0
var _switched := false
var _low_t := 0.0
var _agl_err := 0.0
var _crashes := 0
var _pipes_seen := 0



func _ready() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	GameFlow.reset()
	GameFlow.resumed = true
	GameFlow.dogfight_override = false        # about the flight, not the fight
	_run.call_deferred()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var cur = get_tree().current_scene
	if cur != null and cur != self and cur.get_instance_id() != _scene_id and "pilot" in cur:
		_scene_id = cur.get_instance_id()
		demo = cur
		_switched = true
		_staged_seen = 0
		_uploads_seen = 0
	if _last > 0 and phase != "setup" and demo != null and is_instance_valid(demo):
		var ms := (now - _last) / 1000.0
		var note := PackedStringArray()
		if demo.staged != null and demo.staged.history.size() > _staged_seen:
			for h in demo.staged.history.slice(_staged_seen):
				if float(h.ms) >= 2.0:
					note.append("%s:%.0f" % [h.name, h.ms])
			_staged_seen = demo.staged.history.size()
		if demo.terrain is PlanetTerrain:
			var up: int = (demo.terrain as PlanetTerrain).perf_mesh_submit_count
			if up > _uploads_seen:
				note.append("uploads:%d" % (up - _uploads_seen))
			_uploads_seen = up
		if demo.detail != null and demo.detail.tier != _tier_seen:
			if _tier_seen != -2:
				note.append("tier:%d>%d" % [_tier_seen, demo.detail.tier])
			_tier_seen = demo.detail.tier
		var ph := "switch" if _switched else phase
		_switched = false
		if demo.pilot != null and demo.pilot.atmo != null:
			note.append("alt:%d" % int(demo.pilot.atmo.altitude()))
		var vp := get_viewport().get_viewport_rid()
		var pipes := 0
		for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
				Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
				Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
			pipes += int(Performance.get_monitor(m))
		note.append("cpu:%.0f/%.0f gpu:%.0f rcpu:%.0f setup:%.0f" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.get_frame_setup_time_cpu()])
		if pipes > _pipes_seen:
			note.append("pipelines:%d" % (pipes - _pipes_seen))
		_pipes_seen = pipes
		_frames.append({ "route": route, "phase": ph, "ms": ms, "note": " ".join(note) })
	_last = now



## The autopilot: hold the heading along the ground, pitch for the height wanted.
func _physics_process(dt: float) -> void:
	if demo == null or not is_instance_valid(demo) or demo.pilot == null:
		return
	var p = demo.pilot
	if not p.piloting or p.atmo.state != AtmoFlight.State.FLYING:
		return
	var up: Vector3 = p.atmo.up()
	var fwd: Vector3 = p.atmo.flight.forward()
	var flat := (fwd - up * fwd.dot(up))
	flat = flat.normalized() if flat.length_squared() > 0.0001 else up.cross(Vector3.RIGHT).normalized()
	var pitch := 0.0
	var boost := false
	match phase:
		"open", "descent":
			var agl: float = p.atmo.agl()
			pitch = deg_to_rad(-35.0) if agl > 600.0 else clampf((LOW_AGL - agl) * 0.01, -0.35, 0.3)
			if phase == "descent" and agl < LOW_AGL * 2.0:
				phase = "low"
				_low_t = 0.0
		"low":
			boost = true
			_low_t += dt
			var ahead: Vector3 = p.atmo.position() + fwd * p.atmo.speed() * 0.6
			var g: WorldGround = p.ground
			var h := minf(p.atmo.agl(), g.height_above(ahead))
			pitch = clampf((LOW_AGL - h) * 0.02, -0.25, 0.45)
			# The read-out is the height function: the ground you can hit.
			_agl_err = maxf(_agl_err, absf(p.atmo.agl() - g.height_above(p.atmo.position() - up * p.atmo.clearance)))
			if _low_t >= LOW_S:
				phase = "climb"
		"climb":
			pitch = deg_to_rad(50.0)
	var want := (flat * cos(pitch) + up * sin(pitch)).normalized()
	p.atmo.flight.face(want, up)
	p.set_external_command({ "throttle": 1.0, "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "boost": boost })


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Open space, just outside planet `id`'s bubble, nose in toward it.
func _start_outside(id: String) -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var centre: Vector3 = PlanetGen.system_centre(id, cc)
	var r := PlanetGen.bubble_radius(id, false, cc)
	var dir := Vector3(0.35, 1.0, 0.25).normalized()
	var at := centre + dir * (r + 400.0)
	var to_ground := (centre - at).normalized()
	var side := to_ground.cross(Vector3.UP).normalized()
	var facing := (to_ground + side * 0.9).normalized()      # in at a slant, not straight down
	var b := Basis.looking_at(facing, dir)
	GameFlow.planet_id = PlanetGen.open_space_id()
	GameFlow.arrival = { "mode": "handoff", "from": id, "to": GameFlow.planet_id, "ship": "", "name": "",
		"handoff": { "position": at, "basis": b, "speed": 400.0, "throttle": 1.0 } }
	var old = get_tree().current_scene
	var fresh = (load("res://scenes/town_demo.tscn") as PackedScene).instantiate()
	if old != null and old != self:
		get_tree().root.remove_child(old)
		old.queue_free()
	get_tree().root.add_child(fresh)
	get_tree().current_scene = fresh


func _run() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await frames(5)
	if OS.get_environment("DESCENT_COLD") != "1":
		# A session that has been somewhere already: shaders compiled, models loaded.
		for id in ROUTES:
			GameFlow.planet_id = "" if str(id) == PlanetGen.home_id() else str(id)
			GameFlow.arrival = {}
			var old = get_tree().current_scene
			var warm = (load("res://scenes/town_demo.tscn") as PackedScene).instantiate()
			if old != null and old != self:
				get_tree().root.remove_child(old)
				old.queue_free()
			get_tree().root.add_child(warm)
			get_tree().current_scene = warm
			await frames(90)
	for id in ROUTES:
		route = str(id)
		phase = "setup"
		_start_outside(route)
		await frames(30)
		phase = "open"
		# In: until this planet's scene takes over.
		var t0 := Time.get_ticks_msec()
		while (demo == null or str(demo.planet.get("id", "")) != route) and Time.get_ticks_msec() - t0 < 60000:
			await get_tree().process_frame
		out(route.to_upper() + "_ARRIVED", demo != null and str(demo.planet.get("id", "")) == route)
		phase = "descent"
		t0 = Time.get_ticks_msec()
		while phase != "climb" and Time.get_ticks_msec() - t0 < 180000:
			await get_tree().process_frame
			if demo.pilot.atmo.state == AtmoFlight.State.CRASHED:
				_crashes += 1
				break
		# Out: until open space takes over again.
		t0 = Time.get_ticks_msec()
		while str(demo.planet.get("id", "")) == route and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
		out(route.to_upper() + "_LEFT", str(demo.planet.get("id", "")) != route)
		await frames(60)
		if is_instance_valid(SceneReaper._node):
			out(route.to_upper() + "_REAPER_SLOWEST", SceneReaper._node.slowest)
			SceneReaper._node.slowest = {}
		await frames(30)
		phase = "setup"
	_report()
	get_tree().quit()


func _report() -> void:
	out("CRASHES", _crashes)
	out("LOW_AGL_READOUT_ERR_M", snappedf(_agl_err, 0.01))
	var over := 0
	for id in ROUTES:
		for ph in ["open", "switch", "descent", "low", "climb"]:
			var ms: Array = _frames.filter(func(f): return f.route == id and f.phase == ph).map(func(f): return float(f.ms))
			if ms.is_empty():
				continue
			ms.sort()
			var k := "%s_%s" % [str(id).to_upper(), ph.to_upper()]
			out(k, "n=%d p50=%.1f p95=%.1f p99=%.1f worst=%.1f" % [ms.size(), _pct(ms, 0.5), _pct(ms, 0.95), _pct(ms, 0.99), ms[ms.size() - 1]])
			var mid: Array = _frames.filter(func(f): return f.route == id and f.phase == ph)
			if mid.size() > 10:
				out(k + "_MID_NOTE", mid[mid.size() / 2].note)
	for f in _frames:
		var budget := SWITCH_BUDGET_MS if f.phase == "switch" else FRAME_BUDGET_MS
		if float(f.ms) > budget:
			over += 1
			out("OVER", "%s %s %.1f ms  %s" % [f.route, f.phase, f.ms, f.note])
	out("FRAMES_OVER_BUDGET", over)
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(lines) + "\n")


static func _pct(sorted: Array, q: float) -> float:
	return float(sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)])
