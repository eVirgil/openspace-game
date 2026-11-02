extends SceneTree
## Renders the export icon's foreground: the player smuggler's bust facing forward
## in the black hat (head piece "player:black"), lit by a blue glow on the image's
## left and a red glow on its right, as if two blades were held close either side
## of the face. Transparent 1024 px; tools/look/icon_compose.gd puts it on the tile.
## Needs a window (not --headless) to render. The first load prints autoload compile
## errors (NpcVoice) when run with -s; the render still goes through.
##   godot --path . -s res://tools/look/icon_bust.gd -- out=/tmp/bust.png [cy=0.06] [dist=1.35] [glow=0.45] [side=0.36]

var _frame := 0
var _vp: SubViewport
var _out := ""
var _body: Node3D
var _cam: Camera3D
var _blue: OmniLight3D
var _red: OmniLight3D
var _cy := 0.06     ## camera aim above the head bone, metres
var _dist := 1.35   ## camera distance, metres
var _side := 0.36   ## how far each glow sits off the face, metres

func _initialize() -> void:
	var glow := 0.45
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("cy="):
			_cy = float(a.substr(3))
		elif a.begins_with("dist="):
			_dist = float(a.substr(5))
		elif a.begins_with("glow="):
			glow = float(a.substr(5))
		elif a.begins_with("side="):
			_side = float(a.substr(5))
	_vp = SubViewport.new()
	_vp.size = Vector2i(1024, 1024)
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5a5e66")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var fill := DirectionalLight3D.new()   # neutral, from the front and above, so the hat stays black
	fill.light_color = Color("#c8ccd4")
	fill.light_energy = 1.25
	fill.rotation_degrees = Vector3(-30, 0, 0)
	_vp.add_child(fill)
	_blue = _glow(Color("#3aa8ff"), glow)
	_red = _glow(Color("#ff2a2a"), glow)
	var kit := CharacterKit.new(LookMaterials.new(), 0.0)
	_body = kit.build("player_smuggler", "idle", { "head": "player:black" })
	_vp.add_child(_body)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_vp.add_child(_cam)
	_cam.make_current()

func _glow(c: Color, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = 0.9
	l.omni_attenuation = 2.2
	_vp.add_child(l)
	return l

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 5:
		# The skeleton has posed by now; frame on its head bone.
		var hp := Vector3.ZERO
		for sk in _body.find_children("*", "Skeleton3D", true, false):
			var i: int = sk.find_bone("Head")
			if i >= 0:
				hp = sk.global_transform * sk.get_bone_global_pose(i).origin
		# He faces +Z, toward the camera. The glows stand off each cheek, a little behind it.
		_blue.position = hp + Vector3(-_side, -0.08, -0.08)
		_red.position = hp + Vector3(_side, -0.08, -0.08)
		_cam.position = hp + Vector3(0, _cy + 0.04, _dist)
		_cam.look_at(hp + Vector3(0, _cy, 0))
	if _frame == 30:
		_vp.get_texture().get_image().save_png(_out)
		print("icon_bust: wrote ", _out)
		quit()
	return false
