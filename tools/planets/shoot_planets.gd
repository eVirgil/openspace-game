extends SceneTree
## Review renders for the planet generator (issue #45): the asteroid station (its
## size-1 town, the glass and the gate shield, the cantina and its owner, the rock
## below), the town style kit on generated towns, every planet type, and towns at
## sizes 1 to 100 from the air. Saves PNGs to test_results/planets/.
##
## Needs a real renderer: ./tools/planets/shoot_planets.sh [scenes=a,b] [preset=dusk]
## Each scene builds the town scene for one planet (a manifest planet, or a config
## made up here), places a fixed camera per shot, lets it settle and saves.

const OUT := "res://test_results/planets"

var _only: Array = []
var _preset := "golden"
var _scenes: Array = []


func _initialize() -> void:
	Disclaimers.launch_shown = true          # review stills: no launch notice over the frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scenes="):
			_only = a.substr(7).split(",")
		elif a.begins_with("preset="):
			_preset = a.substr(7)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_scenes = [
		{ "id": "grit_station", "bar": true, "shots": ["overview", "street", "gate_from_hall", "hall", "pit", "cantina", "out_back", "rock", "ball", "home_from_station", "sun"] },
		{ "id": "port_desert", "shots": ["station_from_port_space", "giant_from_port", "giant_from_space", "giant_close"] },
		{ "id": "ringed_giant", "shots": ["station_over_giant", "bay_from_spawn", "ball", "dropping_in", "clouds_from_station", "low_over_clouds"] },
		{ "id": "style_metallic", "cfg": { "type": "sand", "town_size": 30, "style": "metallic", "seed": 7 }, "shots": ["aerial"] },
		{ "id": "style_snowy", "cfg": { "type": "snow", "town_size": 30, "style": "snowy", "seed": 7 }, "shots": ["aerial", "street"] },
		{ "id": "style_pastel", "cfg": { "type": "water", "town_size": 30, "style": "pastel", "seed": 7 }, "shots": ["aerial", "street"] },
		{ "id": "style_red_matte_metal", "cfg": { "type": "red_desert", "town_size": 30, "style": "red matte metal", "seed": 7 }, "shots": ["aerial"] },
		{ "id": "type_lava", "cfg": { "type": "lava", "town_size": 20, "seed": 3 }, "shots": ["aerial", "edge"] },
		{ "id": "type_gas", "cfg": { "type": "gas", "town_size": 20, "seed": 3 }, "shots": ["aerial"] },
		{ "id": "size_10", "cfg": { "type": "sand", "town_size": 10, "seed": 5 }, "shots": ["map"] },
		{ "id": "size_50", "cfg": { "type": "sand", "town_size": 50, "seed": 5 }, "shots": ["map"] },
		{ "id": "size_100", "cfg": { "type": "sand", "town_size": 100, "seed": 5 }, "shots": ["map"] },
	]
	_run()


func _run() -> void:
	for s in _scenes:
		if not _only.is_empty() and not _only.has(s.id):
			continue
		WorldState.reset()
		GameFlow.reset()
		GameFlow.change_scene = func(_p: String) -> void: pass
		if s.has("cfg"):
			var cfg: Dictionary = s.cfg.duplicate()
			cfg["id"] = s.id
			PlanetGen._cache[s.id] = PlanetGen.make(cfg)
		GameFlow.planet_id = s.id
		var demo = load("res://scenes/town_demo.gd").new()
		demo.preset = _preset
		demo.with_bar = bool(s.get("bar", false))
		demo.npc_brains = false
		get_root().add_child(demo)
		for i in 20:
			await process_frame
		var cam := Camera3D.new()
		cam.far = 60000.0
		cam.fov = 62.0
		demo.add_child(cam)
		cam.current = true
		for layer in demo.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false   # review stills: no HUD, dialogue or prompts
		if demo.retro_hud != null:
			demo.retro_hud.visible = false
		if demo.place_card != null:
			demo.place_card.visible = false
		if demo.pilot != null:
			demo.pilot.process_mode = Node.PROCESS_MODE_DISABLED
			demo.pilot._foot_prompt.visible = false
		for shot in s.shots:
			var v := _view(demo, str(shot))
			cam.global_position = v[0]
			cam.look_at(v[1], Vector3.UP)
			for i in 45:
				await process_frame
			var path := ProjectSettings.globalize_path("%s/%s_%s.png" % [OUT, s.id, shot])
			get_root().get_texture().get_image().save_png(path)
			print("SHOT ", s.id, " ", shot, " -> ", path)
		demo.queue_free()
		for i in 5:
			await process_frame
	print("SHOOT planets: done")
	quit()


func _neighbour(demo, id: String) -> Dictionary:
	for n in demo.planet.neighbours:
		if n.id == id:
			return n
	return demo.planet.neighbours[0]


## [eye, target] for a shot, from the town's own data.
func _view(demo, shot: String) -> Array:
	var t = demo.town
	var b: Dictionary = t.data.bounds
	var x0 := float(b.min[0])
	var x1 := float(b.max[0])
	var z0 := float(b.min[1])
	var z1 := float(b.max[1])
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var w := maxf(x1 - x0, z1 - z0)
	match shot:
		"overview", "aerial":
			return [c + Vector3(w * 0.55, w * 0.45, w * 0.75), c + Vector3(0, -2, 0)]
		"map":
			return [c + Vector3(0.01, w * 0.95, w * 0.35), c]
		"gate":
			var g: Vector3 = t.marker_pos("gate")
			return [g + Vector3(22, 3.0, 7), g + Vector3(-6, 2.0, 0)]
		"cantina":
			var f: Vector3 = t.marker_pos("bar_front")
			var o: Vector3 = t.marker_pos("cantina_owner")
			return [o + Vector3(4.2, 1.75, 1.4), o + Vector3(0, 1.35, 0)]
		"out_back":
			var v: Vector3 = t.marker_pos("vendor_1")
			return [v + Vector3(6.0, 2.0, 2.5), v + Vector3(0, 1.0, 0)]
		"below":
			return [c + Vector3(w * 1.6, -w * 0.25, w * 1.4), c + Vector3(0, -60, 0)]
		"street":
			var d: Vector3 = t.marker_pos("cantina_door")
			return [d + Vector3(24, 3.0, 9), d + Vector3(0, 3.0, 0)]
		"edge":
			var g2: Vector3 = t.marker_pos("desert_exit")
			return [g2 + Vector3(40, 6, 30), g2 + Vector3(0, -40, 0)]
		"from_port_sky":
			return [c + Vector3(-500, 260, 300), c + Vector3(0, -80, 0)]
		# Issue #99: the sealed station, the asteroid's ball, and each planet from the other.
		"gate_from_hall":
			var hg: Dictionary = demo.platform.hall
			return [Vector3(float(hg.x0) + 12.0, 1.7, 2.0), Vector3(float(hg.x0) - 6.0, 1.5, -1.0)]
		"hall":
			var hl: Dictionary = demo.platform.hall
			return [Vector3(float(hl.x0) + 3.0, 1.7, -2.5), Vector3(float(hl.end), -1.5, 0.5)]
		"pit":
			var pc: Vector3 = demo.platform.pit_c
			return [pc + Vector3(14, -4.3, 10), pc + Vector3(-28, 2.0, 0)]
		"rock":
			return [c + Vector3(160, 40, 260), c + Vector3(40, 0, 0)]
		"ball":
			var r: float = demo.terrain.sphere.radius
			return [Vector3(r * 2.2, r * 0.4, r * 2.2), Vector3(0, -r, 0)]
		"home_from_station":
			var hn: Dictionary = demo.planet.neighbours[0]
			return [Vector3(0, 2600, 0), hn.at]
		"sun":
			var se := c + Vector3(0, 20, 0)
			return [se, se + demo.look.sun_dir * 100.0]
		# The ringed giant (content/core/planets/ringed_giant.json) from the port: where
		# the sky painting was, and up close in space.
		"giant_from_port":
			var gd: Vector3 = _neighbour(demo, "ringed_giant").at
			var eye := c + Vector3(0, 4.0, 0)
			return [eye, eye + gd.normalized() * 1000.0]
		"giant_from_space":
			var gn: Dictionary = _neighbour(demo, "ringed_giant")
			var gat: Vector3 = gn.at
			return [gat * 0.6 + Vector3(0, 9000, 0), gat]
		# Nearly at the giant, still in the port's scene: 5 km off its clouds.
		"giant_close":
			var gc: Dictionary = _neighbour(demo, "ringed_giant")
			var gca: Vector3 = gc.at
			var side := gca.normalized().cross(Vector3.UP).normalized()
			return [gca - gca.normalized() * (float(gc.radius) + 5000.0) + side * 1500.0, gca]
		# The giant's own scene, close: dropping in past the handoff, the clouds from the
		# station's bay mouth, and skimming just over the cloud tops.
		"dropping_in":
			return [Vector3(1400, 1700, 900), Vector3(0, -300, 0)]
		"clouds_from_station":
			return [Vector3(-190, 204, 10), Vector3(-1400, -60, 220)]
		"low_over_clouds":
			return [Vector3(500, -95, 500), Vector3(1700, -104, 1300)]
		# The space station (content/core/stations/) over the top of the giant.
		"station_over_giant":
			return [Vector3(520, 120, 460), Vector3(20, 200, 0)]
		"bay_from_spawn":
			var spn: Vector3 = t.marker_pos("player_spawn")
			var shp: Dictionary = t.get_box("ship")
			var sc := Vector3((float(shp.min[0]) + float(shp.max[0])) * 0.5, float(shp.min[1]) + 1.5, (float(shp.min[2]) + float(shp.max[2])) * 0.5)
			return [spn + Vector3(0, 1.7, 0) + (spn - sc).normalized() * 4.0, sc]
		"deck_over_clouds":
			return [c + Vector3(w * 1.4, -40.0, w * 1.1), c + Vector3(0, -20.0, 0)]
		"station_from_port_space":
			var sn: Dictionary = demo.planet.neighbours[0]
			return [(sn.at as Vector3) + Vector3(-2500, 1800, 3500), sn.at]
	return [c + Vector3(0, 50, 80), c]
