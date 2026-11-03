class_name LookEnvironment
extends Node3D
## Sky, sun, fog and post-processing for a time-of-day preset from
## content/look/time_of_day.json. Add it to a scene, then call apply("golden").
## Materials that need the sun direction register with track_material().
## apply_hour(h) blends between presets by the "hours" keys in the same file
## (the F11 demo settings' time-of-day slider).

const PRESETS_PATH := "res://content/look/time_of_day.json"
const SKY_SHADER := preload("res://src/systems/look/shaders/desert_sky.gdshader")
const SETTINGS_PATH := "user://settings/graphics.cfg"

## The player's "Indirect light" setting (F11 > Options), 0..1: scales the sky's
## ambient fill, SDFGI's bounce light and SSIL. On some Windows GPUs these came out
## far too bright on near things (the hands in first person, a ship's interior);
## turning it down there tames them. 0 turns SDFGI off. Saved per machine.
static var _indirect := -1.0


static func indirect_level() -> float:
	if _indirect < 0.0:
		var f := ConfigFile.new()
		_indirect = clampf(float(f.get_value("light", "indirect", 1.0)), 0.0, 1.0) if f.load(SETTINGS_PATH) == OK else 1.0
	return _indirect


static func save_indirect_level(level: float) -> void:
	_indirect = clampf(level, 0.0, 1.0)
	_save_setting("light", "indirect", _indirect)


## The player's "Low graphics" setting (F11 > Options), for slower PCs: holds the
## expensive render features off on the ground too (as AltitudeDetail does high up),
## shortens the sun's shadows, draws the 3D world at a lower resolution and thins
## the blowing sand. Each of those is a piece (time_of_day.json "low_graphics"
## pieces) with its own checkbox, so one can be tried at a time; Low graphics is
## all of them. Saved per machine, a key per piece.
static var _cut := {}                ## piece id -> true when cut; empty until loaded
static var _low_cfg: Dictionary = {}


static func low_cfg() -> Dictionary:
	if _low_cfg.is_empty():
		_low_cfg = load_presets().get("low_graphics", {})
	return _low_cfg


static func pieces() -> Array:
	return low_cfg().get("pieces", [])


## Is this piece of Low graphics on (its feature cut)?
static func cut(id: String) -> bool:
	if _cut.is_empty():
		var f := ConfigFile.new()
		var loaded := f.load(SETTINGS_PATH) == OK
		var all := loaded and bool(f.get_value("quality", "low", false))   # saved before the pieces
		for p in pieces():
			var in_low := bool(p.get("low", true))
			_cut[p.id] = bool(f.get_value("quality", p.id, all and in_low)) if loaded else false
	return bool(_cut.get(id, false))


static func save_cut(id: String, on: bool) -> void:
	cut(id)
	_cut[id] = on
	_save_setting("quality", id, on)


## Every piece Low graphics takes in is cut (bloom is not one of them).
static func low_graphics() -> bool:
	for p in pieces():
		if bool(p.get("low", true)) and not cut(p.id):
			return false
	return not pieces().is_empty()


static func save_low_graphics(on: bool) -> void:
	for p in pieces():
		if bool(p.get("low", true)):
			save_cut(p.id, on)


## The render features the cut pieces hold off ("sdfgi", "volumetric", "glow"...).
static func cut_features() -> Array:
	var out := []
	for p in pieces():
		if cut(p.id):
			out.append_array(p.get("off", []))
	return out


static func _save_setting(section: String, key: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	var f := ConfigFile.new()
	f.load(SETTINGS_PATH)
	f.set_value(section, key, value)
	f.save(SETTINGS_PATH)

var presets: Dictionary = {}
var default_preset := "golden"
var current := ""                    ## the preset applied, or the nearest one to `hour`
var hours: Array = []                ## [{ hour, preset }] ascending, from the json
var hour := -1.0                     ## last apply_hour(), -1 after a plain apply()
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var sun_dir := Vector3(0, 0.15, -1)
var lamp_level := 0.0
var ambient_energy_scale := 1.0
var suppressed := {}                 ## issue #46: feature -> true, held off (set_suppressed)
var shadow_cap := 0.0                ## the sun's shadow range held to this many metres (0: the preset's)
var _shadow_distance := 0.0          ## what the preset asks for
var _wanted := {}                    ## what the preset asks for: ssao, ssil, sdfgi, volumetric, shadows
var _ambient_energy_base := 1.0
## Up in space every planet is lit alike (moon handoff): the ambient fill eases from
## this planet's own (its sky's ambient, its scene's scale) to the plain preset's
## as AltitudeSky's level goes to 1, so two planets' scenes match up there.
var space_presets: Dictionary = {}   ## the presets as loaded, before a planet lays its sky over them
var space_level := 0.0
var _ambient_space := 1.0
var _tracked: Array[ShaderMaterial] = []
var _lamps: Array[Light3D] = []
var _lamp_mats: Array[StandardMaterial3D] = []


static func load_presets(path: String = PRESETS_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LookEnvironment: cannot open %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## One shared seamless noise texture. Made synchronously from an Image so the
## first rendered frame already has it (NoiseTexture2D generates on a thread).
## Made once per (size, seed, freq) a run and shared (a 512 one is ~25 ms, and a
## planet handoff's first frame asked for several): nothing writes to them.
static func make_noise_texture(size: int = 512, seed_value: int = 7, freq: float = 0.012) -> ImageTexture:
	var key := Vector3(size, seed_value, freq)
	if not _noise_cache.has(key):
		_noise_cache[key] = _new_noise_texture(size, seed_value, freq)
	return _noise_cache[key]


static var _noise_cache: Dictionary = {}     ## Vector3(size, seed, freq) -> ImageTexture


static func _new_noise_texture(size: int, seed_value: int, freq: float) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.frequency = freq
	var img := n.get_seamless_image(size, size)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


func _init() -> void:
	name = "LookEnvironment"
	var data := load_presets()
	presets = data.get("presets", {})
	space_presets = presets.duplicate(true)
	default_preset = data.get("default", "golden")
	hours = data.get("hours", [])

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", make_noise_texture(512, 11, 0.02))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssil_radius = 6.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.4
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_gi_inject = 0.6
	env.adjustment_enabled = true
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


## Issue #77: on the home planet's ball, turn the sky's gradient and clouds to
## the up of whoever is looking (the drawing camera), wherever on the ball they are.
## Up in space (space_level) it turns to `space_frame` instead when a scene sets
## one: the moon's scene takes its parent planet's up there, so the sky is the one
## the parent's scene draws at that point and a handoff changes nothing.
var space_frame: Callable = Callable()   ## world point -> Basis, or none (this ball's own up)


func _process(_dt: float) -> void:
	if sky_mat == null or PlanetSphere.current == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var frame: Basis = PlanetSphere.current.tilt_at(cam.global_position)
	if space_level > 0.0 and space_frame.is_valid():
		var far: Basis = space_frame.call(cam.global_position)
		frame = Basis(frame.get_rotation_quaternion().slerp(far.get_rotation_quaternion(), space_level))
	sky_mat.set_shader_parameter("sky_frame", frame)


func track_material(m: ShaderMaterial) -> void:
	_tracked.append(m)
	m.set_shader_parameter("sun_dir", sun_dir)


func track_lamp(light: Light3D, glow_mat: StandardMaterial3D = null) -> void:
	_lamps.append(light)
	if glow_mat != null:
		_lamp_mats.append(glow_mat)
	_apply_lamps()


## Emissive surfaces (windows, lamp bulbs) that brighten when the preset turns lamps on.
func track_glow(m: StandardMaterial3D) -> void:
	_lamp_mats.append(m)
	_apply_lamps()


## A sealed or shadow-heavy scene can raise ambient fill without changing presets.
func set_ambient_energy_scale(scale: float) -> void:
	ambient_energy_scale = maxf(0.0, scale)
	if env != null:
		env.ambient_light_energy = ambient_now()


## How far up into space the viewer is (AltitudeSky.level, 0..1).
func set_space_level(level: float) -> void:
	if absf(level - space_level) < 0.001:
		return
	space_level = clampf(level, 0.0, 1.0)
	if env != null:
		env.ambient_light_energy = ambient_now()


func ambient_now() -> float:
	var low := float(low_cfg().get("ambient", 1.0)) if cut("fill") else 1.0
	return lerpf(_ambient_energy_base * ambient_energy_scale, _ambient_space, space_level) * indirect_level() * low


## Set (and save) the Indirect light setting, and show it at once.
func set_indirect(level: float) -> void:
	save_indirect_level(level)
	if env != null:
		env.ambient_light_energy = ambient_now()
	_apply_quality()


## Set (and save) the Low graphics setting, and show it at once.
func set_low_graphics(on: bool) -> void:
	save_low_graphics(on)
	apply_low()


## Set (and save) one piece of Low graphics ("fog", "shadows"...), and show it at once.
func set_cut(id: String, on: bool) -> void:
	save_cut(id, on)
	apply_low()


## Show the saved Low graphics pieces (after save_cut / save_low_graphics).
func apply_low() -> void:
	if env != null:
		env.ambient_light_energy = ambient_now()
	_apply_quality()
	_apply_shadow_range()
	_apply_render_scale()


func _enter_tree() -> void:
	_apply_render_scale()


## Low graphics draws the 3D world in this viewport at render_scale and scales it
## up with FSR; 2D (the HUD, menus) is drawn at full size either way.
func _apply_render_scale() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	var low := cut("resolution")
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if low else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(low_cfg().get("render_scale", 1.0)), 0.25, 1.0) if low else 1.0


func apply(preset_id: String = "") -> void:
	if preset_id == "":
		preset_id = default_preset
	if not presets.has(preset_id):
		push_error("LookEnvironment: unknown preset '%s'" % preset_id)
		return
	current = preset_id
	hour = -1.0
	_ambient_space = _space_ambient(space_presets.get(preset_id, presets[preset_id]))
	_apply_values(presets[preset_id])


## A time of day in hours (0..24), blended between the two presets keyed around
## it. `current` becomes whichever of those two is nearer.
func apply_hour(h: float) -> void:
	var k := keys_at_hour(h)
	if k.is_empty():
		return
	hour = h
	current = str(k.a) if float(k.t) < 0.5 else str(k.b)
	_ambient_space = lerpf(_space_ambient(space_presets.get(k.a, presets[k.a])),
		_space_ambient(space_presets.get(k.b, presets[k.b])), float(k.t))
	_apply_values(blend(presets[k.a], presets[k.b], float(k.t)))


## The two presets around hour `h` and how far from the first: { a, b, t }.
func keys_at_hour(h: float) -> Dictionary:
	var keys: Array = hours.filter(func(e): return presets.has(str(e.get("preset", ""))))
	if keys.is_empty():
		return {}
	var first: Dictionary = keys[0]
	if h <= float(first.hour):
		return { "a": str(first.preset), "b": str(first.preset), "t": 0.0 }
	for i in range(1, keys.size()):
		var lo: Dictionary = keys[i - 1]
		var hi: Dictionary = keys[i]
		if h <= float(hi.hour):
			var span := maxf(0.001, float(hi.hour) - float(lo.hour))
			return { "a": str(lo.preset), "b": str(hi.preset), "t": (h - float(lo.hour)) / span }
	var last: Dictionary = keys[keys.size() - 1]
	return { "a": str(last.preset), "b": str(last.preset), "t": 0.0 }


## The hour key of a preset (its first), so a preset button can move the slider.
func hour_of(preset_id: String) -> float:
	for e in hours:
		if str(e.get("preset", "")) == preset_id:
			return float(e.hour)
	return -1.0


static func _space_ambient(p: Dictionary) -> float:
	return float(p.get("ambient", {}).get("energy", 1.0))


## Two preset dictionaries mixed at t: numbers lerp, "#rrggbb" colors lerp,
## anything else (bools) switches at the halfway point.
static func blend(a: Variant, b: Variant, t: float) -> Variant:
	if a is Dictionary and b is Dictionary:
		var out := {}
		for key in a:
			out[key] = blend(a[key], b[key], t) if b.has(key) else a[key]
		return out
	if (a is float or a is int) and (b is float or b is int):
		return lerpf(float(a), float(b), t)
	if a is String and b is String and a.begins_with("#") and b.begins_with("#"):
		return "#" + Color.html(a).lerp(Color.html(b), t).to_html(false)
	return a if t < 0.5 else b


func _apply_values(p: Dictionary) -> void:
	var s: Dictionary = p["sun"]
	var k: Dictionary = p["sky"]
	var fog: Dictionary = p["fog"]
	var vol: Dictionary = p["volumetric"]
	var post: Dictionary = p["post"]

	sun_dir = direction(float(s["azimuth_deg"]), float(s["elevation_deg"]))
	sun.transform.basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = Color.html(s["color"])
	sun.light_energy = float(s["energy"])
	sun.light_angular_distance = float(s["angular_size"])
	_shadow_distance = float(s["shadow_distance"])
	_apply_shadow_range()
	sun.light_volumetric_fog_energy = float(s["fog_energy"])

	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("zenith_color", Color.html(k["zenith"]))
	sky_mat.set_shader_parameter("horizon_color", Color.html(k["horizon"]))
	sky_mat.set_shader_parameter("ground_color", Color.html(k["ground"]))
	sky_mat.set_shader_parameter("sun_glow_color", Color.html(k["sun_glow"]))
	sky_mat.set_shader_parameter("sun_disk_color", Color.html(k["sun_disk"]))
	sky_mat.set_shader_parameter("glow_strength", float(k["glow_strength"]))
	sky_mat.set_shader_parameter("horizon_falloff", float(k["horizon_falloff"]))
	sky_mat.set_shader_parameter("sky_energy", float(k["energy"]))
	sky_mat.set_shader_parameter("cloud_cover", float(k["cloud_cover"]))
	sky_mat.set_shader_parameter("cloud_color", Color.html(k["cloud_color"]))
	sky_mat.set_shader_parameter("cloud_shadow", Color.html(k["cloud_shadow"]))
	sky_mat.set_shader_parameter("planet_dir", direction(float(k["planet_azimuth_deg"]), float(k["planet_elevation_deg"])))
	sky_mat.set_shader_parameter("planet_radius", float(k["planet_radius"]))
	sky_mat.set_shader_parameter("planet_visibility", float(k["planet_visibility"]))
	sky_mat.set_shader_parameter("planet_color_a", Color.html(k["planet_a"]))
	sky_mat.set_shader_parameter("planet_color_b", Color.html(k["planet_b"]))
	sky_mat.set_shader_parameter("ring_color", Color.html(k["ring"]))

	_ambient_energy_base = float(p["ambient"]["energy"])
	env.ambient_light_energy = ambient_now()
	env.fog_enabled = true
	env.fog_density = float(fog["density"])
	env.fog_aerial_perspective = float(fog["aerial"])
	env.fog_sun_scatter = float(fog["sun_scatter"])
	env.fog_light_color = Color.html(fog["color"])
	env.fog_sky_affect = float(fog["sky_affect"])
	env.fog_height = float(fog.get("height", 0.0))
	# Issue #77: height fog is measured on world y; on the home planet's ball the
	# ground falls below it a few hundred metres out and the whole planet drowns.
	env.fog_height_density = 0.0 if PlanetSphere.current != null else float(fog.get("height_density", 0.0))

	env.volumetric_fog_enabled = bool(vol["enabled"])
	env.volumetric_fog_density = float(vol["density"])
	env.volumetric_fog_albedo = Color.html(vol["albedo"])
	env.volumetric_fog_anisotropy = float(vol["anisotropy"])
	env.volumetric_fog_length = float(vol["length"])

	env.tonemap_exposure = float(post["exposure"])
	env.tonemap_white = float(post["white"])
	env.glow_intensity = float(post["glow"])
	env.glow_bloom = float(post["glow_bloom"])
	env.adjustment_contrast = float(post["contrast"])
	env.adjustment_saturation = float(post["saturation"])
	env.adjustment_brightness = float(post["brightness"])
	_wanted = { "ssao": bool(post["ssao"]), "ssil": bool(post["ssil"]), "sdfgi": bool(post["sdfgi"]),
		"volumetric": bool(vol["enabled"]), "shadows": true }
	_apply_quality()

	lamp_level = float(p.get("lamps", 0.0))
	_apply_lamps()
	for m in _tracked:
		m.set_shader_parameter("sun_dir", sun_dir)


## Issue #46: render features held off from outside, whatever the preset wants:
## AltitudeDetail drops the expensive ones high in the sky ("ssao", "ssil",
## "sdfgi", "volumetric", "shadows"). Pass [] to give them all back.
func set_suppressed(features: Array) -> void:
	var next := {}
	for f in features:
		next[str(f)] = true
	if next == suppressed:
		return
	suppressed = next
	_apply_quality()


## Hold the sun's shadows to `metres` (0 gives the preset's range back). Indoors
## under a low sun the preset's 700-900 m spreads the shadow map so thin that a
## window frame's shadow comes out in stair-steps across the floor; the cruiser
## asks for a short range while you are aboard.
func set_shadow_cap(metres: float) -> void:
	if is_equal_approx(metres, shadow_cap):
		return
	shadow_cap = metres
	_apply_shadow_range()


func _apply_shadow_range() -> void:
	if sun == null or _shadow_distance <= 0.0:
		return
	var d := minf(_shadow_distance, shadow_cap) if shadow_cap > 0.0 else _shadow_distance
	if cut("shadows"):
		d = minf(d, float(low_cfg().get("shadow_m", d)))
	sun.directional_shadow_max_distance = d


func _apply_quality() -> void:
	if env == null:
		return
	var low := cut_features()
	var on := func(k: String) -> bool: return bool(_wanted.get(k, true)) and not suppressed.has(k) and not low.has(k)
	var indirect := indirect_level()
	env.ssao_enabled = on.call("ssao")
	env.ssil_enabled = on.call("ssil") and indirect > 0.0
	env.ssil_intensity = indirect
	env.sdfgi_enabled = on.call("sdfgi") and indirect > 0.0
	env.sdfgi_energy = indirect
	env.volumetric_fog_enabled = on.call("volumetric")
	env.glow_enabled = not low.has("glow")
	# Without SDFGI nothing bounces the sand's warmth back up: low graphics mixes
	# a sand colour into the sky's fill instead.
	var bounce := float(low_cfg().get("bounce_share", 0.0)) if cut("fill") else 0.0
	env.ambient_light_sky_contribution = 1.0 - bounce
	env.ambient_light_color = Color.html(str(low_cfg().get("bounce", "#000000"))) if bounce > 0.0 else Color.BLACK
	if sun != null:
		sun.shadow_enabled = on.call("shadows")
		sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if cut("shadows")
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)


## Issue #458: a lamp or glow with a "min_level" meta (HangingLamp) never drops
## below that fraction of full, so it stays on by day and brightens at dusk.
func _apply_lamps() -> void:
	for l in _lamps:
		var level := maxf(lamp_level, float(l.get_meta("min_level", 0.0)))
		l.visible = level > 0.01
		l.light_energy = level * float(l.get_meta("base_energy", 1.0))
	for m in _lamp_mats:
		m.emission_energy_multiplier = 0.15 + maxf(lamp_level, float(m.get_meta("min_level", 0.0))) * 3.0
