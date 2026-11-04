class_name AltitudeSky
extends Node3D
## The sky by altitude (M14). Near the ground the time-of-day preset rules
## (LookEnvironment). Climbing, the sky darkens toward black, clouds thin out, the
## haze clears, the ringed planet sharpens and stars come out, until at the edge of
## space it is night above a lit planet. One number drives it: `level` 0..1, from
## altitude between the world's `upper_start` and `sky_black_at`.
##
## It reads the current preset every time it applies, so cycling the lighting (L)
## still works at any height. Colours of space: content/look/world.json "space".

const LOOK_PATH := "res://content/look/world.json"

var env: LookEnvironment
var upper_start := 600.0
var black_at := 7000.0
var level := 0.0
var space: Dictionary = {}
var _stars: MultiMeshInstance3D
var _star_mat: StandardMaterial3D
var _applied := -1.0
var _applied_preset := ""


func setup(look_env: LookEnvironment, atmosphere: Dictionary) -> void:
	env = look_env
	upper_start = float(atmosphere.get("upper_start", upper_start))
	black_at = float(atmosphere.get("sky_black_at", black_at))


func _ready() -> void:
	name = "AltitudeSky"
	space = ItemKit._read_json(LOOK_PATH).get("space", {})
	_build_stars()


## 0 at or below upper_start, 1 at sky_black_at and above.
func level_for(altitude: float) -> float:
	return smoothstep(upper_start, black_at, altitude)


## Set the sky for an altitude, and keep the stars centred on the viewer.
func update_for(altitude: float, viewer: Vector3) -> void:
	level = level_for(altitude)
	if _stars != null:
		_stars.global_position = viewer
		_stars.visible = level > 0.02
		_star_mat.albedo_color.a = level
	if env == null or env.sky_mat == null:
		return
	env.set_space_level(level)
	if absf(level - _applied) < 0.003 and env.current == _applied_preset:
		return
	_applied = level
	_applied_preset = env.current
	var pr: Dictionary = env.presets.get(env.current, {})
	var k: Dictionary = pr.get("sky", {})
	var fog: Dictionary = pr.get("fog", {})
	if k.is_empty():
		return
	var m := env.sky_mat
	m.set_shader_parameter("zenith_color", _mix(k, "zenith", "zenith"))
	m.set_shader_parameter("horizon_color", _mix(k, "horizon", "horizon"))
	m.set_shader_parameter("ground_color", _mix(k, "ground", "ground"))
	m.set_shader_parameter("cloud_cover", lerpf(float(k.get("cloud_cover", 0.4)), float(space.get("cloud_cover", 0.0)), level))
	m.set_shader_parameter("sky_energy", lerpf(float(k.get("energy", 1.0)), float(space.get("sky_energy", 0.35)), level))
	env.set_planet_visibility(lerpf(float(k.get("planet_visibility", 0.75)), float(space.get("planet_visibility", 1.0)), level))
	if env.env != null and not fog.is_empty():
		# Issue #77: from above the home planet's ball you look across the whole
		# planet (10-20 km of air): clear nearly all of it so the ball reads.
		var thin := float(space.get("fog_density_scale", 0.15))
		if PlanetSphere.current != null:
			thin = minf(thin, float(space.get("ball_fog_density_scale", 0.01)))
		env.env.fog_density = float(fog.get("density", 0.00016)) * lerpf(1.0, thin, level)
		env.env.fog_sky_affect = float(fog.get("sky_affect", 0.3)) * (1.0 - level)
	var vol: Dictionary = pr.get("volumetric", {})
	if env.env != null and not vol.is_empty():
		env.env.volumetric_fog_density = float(vol.get("density", 0.003)) * (1.0 - level)


func _mix(k: Dictionary, key: String, space_key: String) -> Color:
	var a := Color.html(str(k.get(key, "#808080")))
	var b := Color.html(str(space.get(space_key, "#000000")))
	return a.lerp(b, level)


func _build_stars() -> void:
	var st: Dictionary = space.get("stars", {})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	var sz := float(st.get("size", 40.0))
	quad.size = Vector2(sz, sz)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.albedo_color = Color(str(st.get("color", "#e9e6f2")))
	_star_mat.albedo_color.a = 0.0
	_star_mat.disable_fog = true
	quad.material = _star_mat
	mm.mesh = quad
	var n := int(st.get("count", 1200))
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var dist := float(st.get("distance", 60000.0))
	for i in n:
		# On the ball "up" turns with you: stars all round (the planet hides its share).
		var low := -1.0 if PlanetSphere.current != null else 0.02
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(low, 1), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.3, 1.0)), v * dist))
	_stars = MultiMeshInstance3D.new()
	_stars.name = "Stars"
	_stars.multimesh = mm
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stars.visible = false
	_stars.extra_cull_margin = dist
	add_child(_stars)
