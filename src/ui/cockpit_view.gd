class_name CockpitView
extends Control
## The cockpit view (issue #181): V in a ship, the same cockpit for every ship.
## Most of the view is the canopy, glass with a faint tint; its frame (two struts
## and a bow across the top) comes back over your head, and
## a dashboard runs across the bottom, its instruments working from the same values
## the chase view's HUD gets (CockpitDash paints it).
##
## The cockpit camera is locked to the ship (ChaseCamera.COCKPIT), so the cockpit
## hangs on it and never moves against the view. FlightHud hands it `values`
## (show_values) and redraws it.
##
## The canopy's frame, the dash and the yoke are modelled: meshes on the camera
## (frame_mesh, dash_mesh, build_yoke) in the ship's own hull material
## (`hull_material`), the dash and yoke a darker shade of it (DASH_SHADE), so the
## sun, the sky and their reflections light them exactly as they light the
## outside of the ship. The struts stand on the dash and run down into it, so they
## grow out of it. Each mesh is built from the screen and the lens, so one cockpit
## fits every ship.
##
## The instruments are painted: CockpitDash draws them flat into a SubViewport,
## and the dash's surface (cockpit_dash.gdshader) wears that texture, mapped so
## the panel leans away from you (project()): its far edge shrinks toward the
## middle, the dials go oval and the plates' sides lean in. Where the paint is,
## the dash is glass over backlit dials. The yoke stands in front, below the
## dash's top so the view stays open, and follows the stick: it turns with roll
## (and yaw, which the mouse drives), and comes back toward you as you pull up.
##
## The glass catches the light: the sun and any bolt going by (gather_lights) glint
## on the dials, and glow faintly on the canopy round where they are.

const DashShader := preload("res://src/systems/look/shaders/cockpit_dash.gdshader")

const GLASS := Color(0.55, 0.75, 0.9, 0.06)
const FRAME_METAL := Color(0.69, 0.74, 0.79, 1.0)  ## the frame's skin when the ship gives none
const GRIP := Color(0.05, 0.045, 0.04, 1.0)   ## the yoke's rubber grips
const SEEKER_LAMP := Color(1.0, 0.1, 0.06, 1.0)   ## the seeker warning's glareshield lamps, lit
const YOKE_TURN := 28.0           ## degrees the yoke turns at full roll
const YOKE_AHEAD := 0.5            ## m ahead of your eye, the yoke's hub
const YOKE_SPAN := 0.12            ## m from the hub out to each horn
const YOKE_RISE := 0.115           ## m from the hub up to the horns' tips
const YOKE_PULL := 0.05            ## m the yoke comes back toward you at full pull
const TILT := 0.55                 ## how fast the dash recedes going up it (project())
const PANEL_TOP := 0.66            ## the dash's texture starts this far down the screen (before the lean)
const PANEL_SCALE := 1.5           ## the dash's texture is drawn this much finer than the screen, so it stays crisp warped
const BACKLIGHT := 0.55            ## how brightly the dials are lit from behind (cockpit_dash.gdshader)
const SUN_GLINT := 0.5             ## the sun's glints at full daylight, 0..1
const BOLT_RANGE := 90.0           ## m: bolts further off than this put no light on the glass
const BOLT_FALLOFF := 14.0         ## m: a bolt this far off glints at half strength
const MAX_GLINTS := 6
const FRAME_FOV := 70.0            ## degrees: the lens the canopy frame is laid out for, when no camera says
const FRAME_FOOT := 1.0            ## m ahead of your eye, where the struts stand on the dash
const FRAME_THICK := 0.09          ## m across the frame's struts and bow
const FRAME_SIDES := 18            ## faces round each frame tube
const FRAME_SINK := 0.2            ## m each strut runs on down past its foot, out of sight inside the dash
const DASH_SHADE := 0.38           ## the dash's skin is the hull's colour times this
const DASH_LIP := 0.025            ## share of the screen height the dash's top edge rolls over in
const BOW_AHEAD := 0.58            ## m ahead of your eye, the bow over the top of the glass
const BOW_TOP := 0.44              ## m above your eye, the bow at its middle
const BOW_SIDE := Vector2(0.62, 0.27)  ## m: where the bow meets each strut (out, up)
const OVERHEAD := Vector3(0.3, 0.5, 0.05)  ## m: where a strut has got to once it is over and behind you

var values: Dictionary = {}
var vessel_name := ""
var yoke := Vector3.ZERO            ## the yoke as drawn (pitch, yaw, roll), eased toward the stick
var lights: Array = []              ## gather_lights(), this frame
var dash: CockpitDash
var _dash_vp: SubViewport
var _sun: DirectionalLight3D
var _sun_look := 0.0                ## seconds until the next look for a sun, when there is none
var hull_material: Material         ## the ship's skin, for the canopy frame (ShipPilot sets it on boarding)
var _frame: MeshInstance3D
var _frame_fit := ""                ## the screen and lens the frame's mesh was built for
var _frame_metal: StandardMaterial3D
var _dash_body: MeshInstance3D
var _dash_skin: ShaderMaterial      ## the dash's surface: a darker shade of the skin, the instruments on it
var _yoke_skin: Material            ## the yoke's darker shade of the skin
var _skin_of: Material              ## the skin those two were made from
var _yoke: Node3D


func _ready() -> void:
	name = "Cockpit"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dash_vp = SubViewport.new()
	_dash_vp.name = "DashView"
	_dash_vp.transparent_bg = true
	_dash_vp.disable_3d = true
	_dash_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_dash_vp)
	dash = CockpitDash.new()
	_dash_vp.add_child(dash)


func _process(dt: float) -> void:
	var on := is_visible_in_tree()
	_dash_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_fit(get_viewport_rect().size)
	_place_frame(on)
	if not on:
		return
	lights = gather_lights(dt)
	dash.values = values
	dash.vessel_name = vessel_name
	dash.lights = lights
	dash.queue_redraw()
	var want := Vector3(_v("stick_pitch"), _v("stick_yaw"), _v("stick_roll"))
	if not yoke.is_equal_approx(want):
		yoke = yoke.lerp(want, minf(1.0, dt * 10.0))
	_pose_yoke()
	queue_redraw()


func _exit_tree() -> void:
	for n in [_frame, _dash_body, _yoke]:
		if is_instance_valid(n):
			n.queue_free()


func _v(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))


## The canopy frame, the dash and the yoke ride on whichever camera is drawing the
## cockpit, wearing the ship's skin; their meshes are rebuilt only when the screen
## or the lens changes.
func _place_frame(on: bool) -> void:
	var cam := get_viewport().get_camera_3d() if on else null
	if cam == null:
		for n in [_frame, _dash_body, _yoke]:
			if is_instance_valid(n):
				n.visible = false
		return
	if not is_instance_valid(_frame):
		_frame = _on_camera("CanopyFrame")
		_dash_body = _on_camera("DashBody")
		_dash_skin = ShaderMaterial.new()
		_dash_skin.shader = DashShader
		_dash_skin.set_shader_parameter("panel", _dash_vp.get_texture())
		_dash_skin.set_shader_parameter("backlight", BACKLIGHT)
		_dash_body.material_override = _dash_skin
		_yoke = Node3D.new()
		_yoke.name = "Yoke"
		_frame_fit = ""
		_skin_of = null
	var vp := get_viewport_rect().size
	var fit := "%s %s" % [vp, cam.fov]
	for n in [_frame, _dash_body, _yoke]:
		var n3 := n as Node3D
		if n3.get_parent() != cam:
			if n3.get_parent() != null:
				n3.get_parent().remove_child(n3)
			cam.add_child(n3)
		n3.visible = true
	_frame.transform = Transform3D.IDENTITY
	_dash_body.transform = Transform3D.IDENTITY
	if hull_material == null and _frame_metal == null:
		_frame_metal = StandardMaterial3D.new()
		_frame_metal.albedo_color = FRAME_METAL
		_frame_metal.metallic = 0.85
		_frame_metal.roughness = 0.32
	var skin: Material = hull_material if hull_material != null else _frame_metal
	_frame.material_override = skin
	if _skin_of != skin:
		_skin_of = skin
		_yoke_skin = dash_skin(skin)
		var base := _yoke_skin as BaseMaterial3D
		if base != null:
			_dash_skin.set_shader_parameter("skin", base.albedo_color)
			_dash_skin.set_shader_parameter("skin_metallic", base.metallic)
			_dash_skin.set_shader_parameter("skin_roughness", base.roughness)
		_frame_fit = ""
	if fit != _frame_fit:
		_frame.mesh = frame_mesh(vp, cam.fov)
		_dash_body.mesh = dash_mesh(vp, cam.fov)
		for c in _yoke.get_children():
			c.free()
		_yoke.add_child(build_yoke(_yoke_skin))
		_frame_fit = fit
	_pose_yoke()


## The yoke where the stick puts it (yoke_pose): its hub low in the middle of the
## screen, YOKE_AHEAD in front of you, turned about its column and drawn back
## toward you as you pull.
func _pose_yoke() -> void:
	if not is_instance_valid(_yoke) or _yoke.get_parent() == null:
		return
	var cam := _yoke.get_parent() as Camera3D
	var vp := get_viewport_rect().size
	var pose := yoke_pose(yoke)
	var hub := frame_unproject(vp, Vector2(vp.x * 0.5, vp.y * 0.99), YOKE_AHEAD, cam.fov if cam != null else FRAME_FOV)
	hub += Vector3(0.0, -0.01, YOKE_PULL) * float(pose.pull)
	_yoke.transform = Transform3D(Basis(Vector3.BACK, -float(pose.angle)), hub)


func _on_camera(n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The dash's and the yoke's skin: the hull's, its colour darkened (DASH_SHADE),
## its finish kept, so it shines the same way but sits darker than the struts.
static func dash_skin(skin: Material) -> Material:
	var base := skin as BaseMaterial3D
	if base == null:
		return skin
	var m := base.duplicate() as BaseMaterial3D
	var c := base.albedo_color
	m.albedo_color = Color(c.r * DASH_SHADE, c.g * DASH_SHADE, c.b * DASH_SHADE, c.a)
	return m


## Size the dash's texture and the shader to the screen: the panel runs far enough
## past each side that its top still reaches the screen's edges once it leans.
func _fit(vp: Vector2) -> void:
	var top := vp.y * PANEL_TOP
	var margin := ceilf(vp.x * 0.5 * TILT * (1.0 - PANEL_TOP))
	var size := Vector2i(ceili((vp.x + margin * 2.0) * PANEL_SCALE), ceili((vp.y - top) * PANEL_SCALE))
	if _dash_vp.size == size and dash.screen == vp:
		return
	_dash_vp.size = size
	dash.screen = vp
	dash.margin = margin
	dash.top = top
	dash.scale_by = PANEL_SCALE
	dash.size = Vector2(size)


## Where panel point p (CockpitDash's flat drawing) lands on screen once the dash
## leans away: the bottom edge stays put, and the higher up the panel the further
## off it is, so it shrinks toward the middle and rises less.
static func project(vp: Vector2, p: Vector2) -> Vector2:
	var v := (vp.y - p.y) / maxf(vp.y, 1.0)
	var z := 1.0 + TILT * v
	return Vector2(vp.x * 0.5 + (p.x - vp.x * 0.5) / z, vp.y * (1.0 - v / z))


## The dash's top edge on screen, left to right, past both sides of the screen.
static func rim(vp: Vector2) -> PackedVector2Array:
	var margin := vp.x * 0.5 * TILT * (1.0 - PANEL_TOP)
	var out := PackedVector2Array()
	for i in 49:
		var x := lerpf(-margin, vp.x + margin, float(i) / 48.0)
		out.append(project(vp, Vector2(x, CockpitDash.dash_top(vp, x))))
	return out


## The dash's top edge on screen at x.
static func rim_y(line: PackedVector2Array, x: float) -> float:
	for i in line.size() - 1:
		if x <= line[i + 1].x:
			return lerpf(line[i].y, line[i + 1].y, clampf(inverse_lerp(line[i].x, line[i + 1].x, x), 0.0, 1.0))
	return line[line.size() - 1].y


## What lights the glass this frame: the sun, and the nearest bolts in flight. Each
## { dir: unit vector toward it in the camera's frame (x right, y up, -z ahead),
## color, power 0..1, and screen: where it is on screen, when it is ahead }.
func gather_lights(dt: float = 0.0) -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return []
	var to_cam := cam.global_basis.orthonormalized().inverse()
	var out: Array = []
	var sun := _find_sun(cam, dt)
	if sun != null:
		var toward := sun.global_basis.z.normalized()
		var l := {"dir": to_cam * toward, "color": sun.light_color, "sun": true,
			"power": SUN_GLINT * clampf(sun.light_energy / 3.0, 0.0, 1.0)}
		var far := cam.global_position + toward * 1000.0
		if not cam.is_position_behind(far):
			l.screen = cam.unproject_position(far)
		out.append(l)
	var bolts: Array = []
	for b in get_tree().get_nodes_in_group("glints"):
		var n := b as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var rel := n.global_position - cam.global_position
		var d := rel.length()
		if d > BOLT_RANGE or d < 0.01:
			continue
		var p := 1.0 / (1.0 + pow(d / BOLT_FALLOFF, 2.0)) * (1.0 - d / BOLT_RANGE)
		var l := {"dir": to_cam * (rel / d), "color": n.get_meta("glint_color", Color.WHITE), "power": p}
		if not cam.is_position_behind(n.global_position):
			l.screen = cam.unproject_position(n.global_position)
		bolts.append(l)
	bolts.sort_custom(func(a, b): return a.power > b.power)
	out.append_array(bolts.slice(0, MAX_GLINTS))
	return out


## The scene's sun: the brightest directional light in the camera's world. Looked
## for again only once a second while there is none.
func _find_sun(cam: Camera3D, dt: float) -> DirectionalLight3D:
	if is_instance_valid(_sun) and _sun.is_visible_in_tree():
		return _sun
	_sun = null
	_sun_look -= dt
	if _sun_look > 0.0:
		return null
	_sun_look = 1.0
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var l := n as DirectionalLight3D
		if l.is_visible_in_tree() and l.get_world_3d() == cam.get_world_3d() \
				and (_sun == null or l.light_energy > _sun.light_energy):
			_sun = l
	return _sun


func _draw() -> void:
	var vp := get_viewport_rect().size
	var line := rim(vp)
	# The glass, down to the dash's edge.
	var glass := PackedVector2Array([Vector2(vp.x, 0), Vector2(0, 0)])
	glass.append_array(line)
	draw_colored_polygon(glass, GLASS)
	# A couple of faint streaks of glare on it, brighter with the sun ahead.
	var sun_ahead := 0.0
	for l in lights:
		if l.get("sun", false):
			sun_ahead = float(l.power) * clampf(-(l.dir as Vector3).z, 0.0, 1.0) / SUN_GLINT
	draw_line(Vector2(vp.x * 0.62, vp.y * 0.08), Vector2(vp.x * 0.7, vp.y * 0.3), Color(1, 1, 1, 0.05 + 0.04 * sun_ahead), 6.0)
	draw_line(Vector2(vp.x * 0.66, vp.y * 0.06), Vector2(vp.x * 0.72, vp.y * 0.22), Color(1, 1, 1, 0.035 + 0.03 * sun_ahead), 3.0)
	_draw_canopy_shine(vp, line)
	_draw_seeker_lamps(vp, line)


## The seeker warning's lamps: a pair of red lamps on the glareshield, either side of
## the gunsight, that flash together (FlightHud's `seeker_lamp`) while the alarm
## sounds. They sit above the dash's edge, clear of the HUD's frame over the dash.
func _draw_seeker_lamps(vp: Vector2, line: PackedVector2Array) -> void:
	if not bool(values.get("seeker_lamp", false)):
		return
	var r := maxf(3.0, vp.y * 0.006)
	for x in [vp.x * 0.3, vp.x * 0.7]:
		var at := Vector2(x, rim_y(line, x) - r * 4.0)
		CockpitDash.halo(self, at, r * 4.5, Color(SEEKER_LAMP, 0.18))
		draw_circle(at, r * 1.3, Color(0.1, 0.02, 0.02, 0.8))
		draw_circle(at, r, SEEKER_LAMP)


## The sun and bolts ahead light the canopy faintly round where they are: a wide
## haze round the sun, a small coloured bloom round a bolt, more the closer it is.
func _draw_canopy_shine(vp: Vector2, line: PackedVector2Array) -> void:
	for l in lights:
		if not l.has("screen"):
			continue
		var at: Vector2 = l.screen
		if at.y > rim_y(line, at.x):
			continue
		var col := Color(l.color)
		if l.get("sun", false):
			CockpitDash.halo(self, at, vp.y * 0.5, Color(col, 0.07 * float(l.power) / SUN_GLINT))
		else:
			CockpitDash.halo(self, at, vp.y * (0.04 + 0.16 * float(l.power)), Color(col, 0.16 * float(l.power)))


## The canopy's frame (modelled in metres round your eye, seen through a `fov`
## lens on a `vp` screen): two struts from the dash's shoulders up and back over
## your head, and a bow across the top of the glass between them, each a round
## tube FRAME_THICK across. Perspective does the rest: the nearer a part is the
## wider it draws, so the struts swell and sweep out to the top corners as they
## pass overhead, which is what makes them feel like they go over you.
static func frame_mesh(vp: Vector2, fov := FRAME_FOV) -> ArrayMesh:
	var line := rim(vp)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, bow_path())
	for side in [-1.0, 1.0]:
		var path := strut_path(vp, line, side, fov)
		var down := (path[0] - path[1]).normalized()
		path.insert(0, path[0] + down * FRAME_SINK)
		_tube(st, path)
	return st.commit()


## The dash (seen through a `fov` lens on a `vp` screen): a face leaning back from
## upright (CockpitDash.LEAN) whose top edge is the dash's edge on screen (rim),
## filling everything under it. Over its top DASH_LIP the face rolls over to a top
## facing up and away, so the edge catches the sky and the sun. Its UVs put
## CockpitDash's flat panel where project() says it lands, so the painted
## instruments lean away with it.
static func dash_mesh(vp: Vector2, fov := FRAME_FOV) -> ArrayMesh:
	var line := rim(vp)
	var lean := deg_to_rad(CockpitDash.LEAN)
	var face := Vector3(0.0, sin(lean), cos(lean))
	var top := Vector3(0.0, 0.96, -0.28)
	var lip := [0.0, 0.08, 0.2, 0.36, 0.56, 0.8, 1.0]   # in DASH_LIP, down from the edge
	var below := 32                                     # rows from the lip to under the screen
	var cols := 64
	var margin := ceilf(vp.x * 0.5 * TILT * (1.0 - PANEL_TOP))
	var panel_top := vp.y * PANEL_TOP
	var grid: Array = []
	for j in lip.size() + below:
		var row: Array = []
		for i in cols + 1:
			var x := lerpf(-vp.x * 0.1, vp.x * 1.1, float(i) / cols)
			var edge := rim_y(line, x)
			var y: float
			var roll := 1.0
			if j < lip.size():
				y = edge + float(lip[j]) * DASH_LIP * vp.y
				roll = smoothstep(0.0, 1.0, float(lip[j]))
			else:
				y = lerpf(edge + DASH_LIP * vp.y, vp.y * 1.05, float(j - lip.size() + 1) / below)
			var p := unproject(vp, Vector2(x, y))
			row.append({
				"at": dash_point(vp, Vector2(x, y), fov),
				"n": top.slerp(face, roll),
				"uv": Vector2((p.x + margin) / (vp.x + margin * 2.0), (p.y - panel_top) / (vp.y - panel_top)),
			})
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in grid.size() - 1:
		for i in cols:
			for q in [[j, i], [j, i + 1], [j + 1, i + 1], [j, i], [j + 1, i + 1], [j + 1, i]]:
				var v: Dictionary = grid[q[0]][q[1]]
				st.set_normal(v.n)
				st.set_uv(v.uv)
				st.add_vertex(v.at)
	return st.commit()


## Where on CockpitDash's flat panel screen point s shows, once it leans away:
## project() run backward.
static func unproject(vp: Vector2, s: Vector2) -> Vector2:
	var a := 1.0 - s.y / maxf(vp.y, 1.0)
	var v := a / maxf(1.0 - a * TILT, 0.001)
	var z := 1.0 + TILT * v
	return Vector2(vp.x * 0.5 + (s.x - vp.x * 0.5) * z, vp.y * (1.0 - v))


## Where the line of sight through screen point s meets the dash's face: a plane
## leaning back CockpitDash.LEAN from upright, through the middle of the dash's
## edge FRAME_FOOT ahead of your eye.
static func dash_point(vp: Vector2, s: Vector2, fov := FRAME_FOV) -> Vector3:
	var lean := deg_to_rad(CockpitDash.LEAN)
	var n := Vector3(0.0, sin(lean), cos(lean))
	var mid := frame_unproject(vp, project(vp, Vector2(vp.x * 0.5, CockpitDash.dash_top(vp, vp.x * 0.5))), FRAME_FOOT, fov)
	var d := frame_unproject(vp, s, 1.0, fov)
	return d * (n.dot(mid) / n.dot(d))


## The bow's centre line, over the top of the glass from one strut to the other.
static func bow_path() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 25:
		var u := lerpf(-1.0, 1.0, float(i) / 24.0)
		out.append(Vector3(u * BOW_SIDE.x, lerpf(BOW_TOP, BOW_SIDE.y, u * u), -BOW_AHEAD))
	return out


## One strut's centre line in metres round your eye (x right, y up, -z ahead), from
## its foot on the dash's edge (on its face, dash_point), through the bow's end, to over and behind your head.
static func strut_path(vp: Vector2, line: PackedVector2Array, side: float, fov := FRAME_FOV) -> Array[Vector3]:
	var bx := vp.x * 0.5 + side * vp.x * 0.33
	var foot := dash_point(vp, Vector2(bx, rim_y(line, bx) + 2.0), fov)
	var mid := Vector3(side * BOW_SIDE.x, BOW_SIDE.y, -BOW_AHEAD)
	var top := Vector3(side * OVERHEAD.x, OVERHEAD.y, OVERHEAD.z)
	var pull := mid * 2.0 - (foot + top) * 0.5      # so the curve passes through mid
	var out: Array[Vector3] = []
	for i in 41:
		var t := float(i) / 40.0
		out.append(foot.lerp(pull, t).lerp(pull.lerp(top, t), t))
	return out


## Where a point round your eye (m: x right, y up, -z ahead) lands on screen
## (`fov` is the lens's vertical angle, as Camera3D's).
static func frame_project(vp: Vector2, p: Vector3, fov := FRAME_FOV) -> Vector2:
	return vp * 0.5 + Vector2(p.x, -p.y) * _focal(vp, fov) / -p.z


## The point `depth` m ahead of your eye that lands on screen at s.
static func frame_unproject(vp: Vector2, s: Vector2, depth: float, fov := FRAME_FOV) -> Vector3:
	var d := (s - vp * 0.5) * depth / _focal(vp, fov)
	return Vector3(d.x, -d.y, -depth)


static func _focal(vp: Vector2, fov := FRAME_FOV) -> float:
	return vp.y * 0.5 / tan(deg_to_rad(fov) * 0.5)


## A round tube of radius `r` along `path`, its rings turned along it without
## twisting (each ring's "up" carried over from the last), normals pointing out.
static func _tube(st: SurfaceTool, path: Array[Vector3], r := FRAME_THICK * 0.5) -> void:
	var up := Vector3.UP
	var rings: Array = []
	for i in path.size():
		var axis := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		up = (up - axis * up.dot(axis))
		if up.length() < 0.001:
			up = axis.cross(Vector3.RIGHT)
		up = up.normalized()
		var side := axis.cross(up)
		var ring: Array = []
		for k in FRAME_SIDES + 1:
			var a := TAU * float(k) / FRAME_SIDES
			ring.append(up * cos(a) + side * sin(a))
		rings.append(ring)
	for i in path.size() - 1:
		for k in FRAME_SIDES:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k + 1]
			var c: Vector3 = rings[i + 1][k + 1]
			var d: Vector3 = rings[i + 1][k]
			for q in [[a, i], [c, i + 1], [b, i], [a, i], [d, i + 1], [c, i + 1]]:
				var n: Vector3 = q[0]
				st.set_normal(n)
				st.add_vertex(path[q[1]] + n * r)


## How the yoke sits for a stick of (pitch, yaw, roll), each -1..1: turned by
## `angle` (radians, + clockwise on screen, as for a right roll), and pulled back
## toward you by `pull` (-1 pushed full forward .. 1 pulled full back). Yaw turns it
## too, at half the rate: the mouse steers with yaw, and the yoke should answer it.
static func yoke_pose(stick: Vector3) -> Dictionary:
	return {
		"angle": deg_to_rad(YOKE_TURN) * clampf(stick.z + stick.y * 0.5, -1.0, 1.0),
		"pull": clampf(stick.x, -1.0, 1.0),
	}


## The yoke, round its hub (x right, y up, z toward you): a ram's-horn wheel of
## metal tube in `skin`, rubber grips on the tops of its horns with a trigger cap
## on the right and a thumb hat on the left, a boss over the hub, and a column
## down out of sight. The horns lean back toward you as they rise.
static func build_yoke(skin: Material) -> Node3D:
	var root := Node3D.new()
	var half := [Vector2(0.0, -0.012), Vector2(0.45, -0.007), Vector2(0.8, 0.12), Vector2(1.0, 0.4), Vector2(1.04, 1.0)]
	var horn: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var pts: Array = half.duplicate()
		if side < 0.0:
			pts.reverse()
		for i in pts.size():
			if side > 0.0 and i == 0:
				continue                         # the middle is already in from the left
			var q: Vector2 = pts[i]
			horn.append(_yoke_point(q.x * side, q.y))
	var line := _smooth(horn, 6)
	var tubes := SurfaceTool.new()
	tubes.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(tubes, line, 0.011)
	var column: Array[Vector3] = [Vector3(0, 0.0, -0.02), Vector3(0, -0.2, -0.04), Vector3(0, -0.45, -0.06)]
	_tube(tubes, column, 0.016)
	tubes.set_material(skin)
	var grips := SurfaceTool.new()
	grips.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = GRIP
	rubber.roughness = 0.85
	for side in [-1.0, 1.0]:
		var a := _yoke_point(side * lerpf(1.0, 1.04, 0.1), lerpf(0.4, 1.0, 0.1))
		var b := _yoke_point(side * 1.04, 1.0)
		var grip: Array[Vector3] = []
		for k in 9:
			grip.append(a.lerp(b, float(k) / 8.0))
		_tube(grips, grip, 0.013)
		var cap := MeshInstance3D.new()
		var button := CylinderMesh.new()
		button.top_radius = 0.008
		button.bottom_radius = 0.01
		button.height = 0.008
		cap.mesh = button
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.55, 0.1, 0.07) if side > 0.0 else Color(0.32, 0.32, 0.33)
		cm.roughness = 0.4
		cap.material_override = cm
		cap.position = b + (b - a).normalized() * 0.003
		cap.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		root.add_child(cap)
	grips.set_material(rubber)
	var mesh := tubes.commit()
	grips.commit(mesh)
	var body := MeshInstance3D.new()
	body.name = "Wheel"
	body.mesh = mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var boss := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.026
	disc.bottom_radius = 0.03
	disc.height = 0.024
	boss.mesh = disc
	boss.material_override = skin
	boss.rotation_degrees = Vector3(90, 0, 0)
	boss.position = Vector3(0, 0, 0.008)
	root.add_child(boss)
	return root


## A point on the yoke's wheel at (u, v): u out along the span (YOKE_SPAN), v up
## toward the horns' tips (YOKE_RISE); the higher, the further back toward you.
static func _yoke_point(u: float, v: float) -> Vector3:
	return Vector3(u * YOKE_SPAN, v * YOKE_RISE, maxf(v, 0.0) * 0.035)


## A smooth line through `pts` (Catmull-Rom), `per` points between each pair.
static func _smooth(pts: Array[Vector3], per: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for k in per:
			var t := float(k) / per
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (p1 * 2.0 + (p2 - p0) * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out
