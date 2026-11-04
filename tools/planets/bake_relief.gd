extends SceneTree
## Bakes the home ball's dunes into a flat print (a cubemap, 3x2 faces): what a
## neighbour's sky draws on a smooth ball instead of a lumpy low-poly rock
## (space_travel.gd, sand.gdshader relief_tex). RGB is the ground's normal (world
## axes, *0.5 + 0.5), A its height (HEIGHT_MIN..HEIGHT_MAX metres above the bare ball).
## Same heights as the ground you walk on (PlanetSphere.elevation, open dunes only:
## the port's plateau is 350 m across, under a texel from the moon).
##
##   godot --headless --path . -s res://tools/planets/bake_relief.gd -- [size=512]
##
## Writes assets/planets/port_desert_relief.png. Re-run when PlanetSphere's dunes change.

const OUT := "res://assets/planets/port_desert_relief.png"
const HEIGHT_MIN := -40.0
const HEIGHT_MAX := 80.0

var size := 512
var radius := 5000.0
var sphere


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			size = int(a.substr(5))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/worlds/port_desert.json"))
	radius = float(world.get("terrain", {}).get("sphere_radius", 5000.0))
	sphere = load("res://src/systems/planets/planet_sphere.gd").new(radius)
	var t0 := Time.get_ticks_msec()
	var faces: Array = []
	faces.resize(6)
	var task := WorkerThreadPool.add_group_task(func(f: int): faces[f] = _face(f), 6, -1, true, "relief bake")
	WorkerThreadPool.wait_for_group_task_completion(task)
	# Godot's cubemap import, arrangement 3x2: +X -X +Y on top, -Y +Z -Z below.
	var atlas := Image.create(size * 3, size * 2, false, Image.FORMAT_RGBA8)
	for f in 6:
		atlas.blit_rect(faces[f], Rect2i(0, 0, size, size), Vector2i((f % 3) * size, (f / 3) * size))
	atlas.save_png(ProjectSettings.globalize_path(OUT))
	print("RELIEF baked %dx%d faces in %d ms -> %s" % [size, size, Time.get_ticks_msec() - t0, OUT])
	quit()


## The direction through face f at face coords (s, t), each -1..1 (GL / Godot order).
static func face_dir(f: int, s: float, t: float) -> Vector3:
	match f:
		0: return Vector3(1.0, -t, -s).normalized()
		1: return Vector3(-1.0, -t, s).normalized()
		2: return Vector3(s, 1.0, t).normalized()
		3: return Vector3(s, -1.0, -t).normalized()
		4: return Vector3(s, -t, 1.0).normalized()
	return Vector3(-s, -t, -1.0).normalized()


func _face(f: int) -> Image:
	# Heights on the face's texel centres, one texel of border all round.
	var n := size + 2
	var pts := PackedVector3Array()
	pts.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		var t := (float(j - 1) + 0.5) / size * 2.0 - 1.0
		for i in n:
			var s := (float(i - 1) + 0.5) / size * 2.0 - 1.0
			var d := face_dir(f, s, t)
			var h: float = sphere.elevation(d)
			hs[j * n + i] = h
			pts[j * n + i] = d * (radius + h)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for j in size:
		for i in size:
			var k := (j + 1) * n + (i + 1)
			var du := pts[k + 1] - pts[k - 1]
			var dv := pts[k + n] - pts[k - n]
			var nm := du.cross(dv).normalized()
			if nm.dot(pts[k]) < 0.0:
				nm = -nm
			var a := clampf((hs[k] - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN), 0.0, 1.0)
			img.set_pixel(i, j, Color(nm.x * 0.5 + 0.5, nm.y * 0.5 + 0.5, nm.z * 0.5 + 0.5, a))
	return img
