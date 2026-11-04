class_name LavaHaze
extends MeshInstance3D
## Heat shimmer over a lava ball (issue #272): a round sheet of hot air a little
## above the lava level, kept under whichever camera is drawing, shown only when
## that camera is near the ground (below max_altitude). The shader bends it onto
## the ball and wobbles what is behind it (lava_haze.gdshader). One small mesh and
## one screen read: cheap, and nothing at all once you fly up.
##
## Settings: the type's surface.haze in content/core/planets/types.json
## { radius, height, strength, max_altitude }.

const SHADER := preload("res://src/systems/look/shaders/lava_haze.gdshader")

var sphere: AsteroidSphere
var cfg: Dictionary = {}
var mat: ShaderMaterial
var max_altitude := 30.0
var height := 1.2
var active := false                    ## shown this frame (tests, traces)


func setup(s: AsteroidSphere, haze: Dictionary) -> LavaHaze:
	sphere = s
	cfg = haze
	name = "LavaHaze"
	max_altitude = float(haze.get("max_altitude", 30.0))
	height = float(haze.get("height", 1.2))
	var r := float(haze.get("radius", 90.0))
	var plane := PlaneMesh.new()
	plane.size = Vector2(r * 2.0, r * 2.0)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	mesh = plane
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(256, 5, 0.03))
	mat.set_shader_parameter("planet_center", s.center)
	mat.set_shader_parameter("shell_radius", s.radius + s.lava_level() + height)
	mat.set_shader_parameter("strength", float(haze.get("strength", 0.006)))
	mat.set_shader_parameter("reach", r)
	mat.set_shader_parameter("safe_center", s.center + Vector3(0, s.radius, 0))
	mat.set_shader_parameter("safe_radius", s.lava_keep_clear())
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = r
	visible = false
	return self


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if sphere == null or cam == null:
		_show(false)
		return
	var eye := cam.global_position
	var up := (eye - sphere.center).normalized()
	var alt := (eye - sphere.center).length() - sphere.radius - sphere.lava_level()
	if alt > max_altitude:
		_show(false)
		return
	_show(true)
	mat.set_shader_parameter("fade", 1.0 - smoothstep(max_altitude * 0.6, max_altitude, alt))
	global_transform = Transform3D(PlanetSphere.tilt_to(up), sphere.center + up * (sphere.radius + sphere.lava_level() + height))


func _show(on: bool) -> void:
	active = on
	visible = on
