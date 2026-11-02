extends SceneTree
## Builds the export icon (assets/icon/openspace_icon.png) from a bust render
## (tools/look/icon_bust.gd): a near-black cloudy sky, faint blue and red glows at
## the sides where the blades would be, the bust on top, all inside the rounded
## tile (62..962 px, corner radius 198, transparent outside).
##   godot --headless --path . -s res://tools/look/icon_compose.gd -- bust=/tmp/bust.png out=res://assets/icon/openspace_icon.png [glow=0.16] [seed=9]

const N := 1024
const LO := 62.0
const HI := 962.0
const R := 198.0
const BLUE := Color("#3aa8ff")
const RED := Color("#ff2a2a")
const SKY_LOW := Color("#040405")   ## thin cloud
const SKY_HIGH := Color("#121315")  ## thick cloud
const CLOUD_TOP := Color("#a9acb3")

func _initialize() -> void:
	var bust_path := ""
	var out_path := ""
	var gs := 0.16
	var cloud_seed := 9
	for a in OS.get_cmdline_user_args():
		if a.begins_with("bust="):
			bust_path = a.substr(5)
		elif a.begins_with("out="):
			out_path = a.substr(4)
		elif a.begins_with("glow="):
			gs = float(a.substr(5))
		elif a.begins_with("seed="):
			cloud_seed = int(a.substr(5))
	var bust := Image.load_from_file(bust_path)
	bust.convert(Image.FORMAT_RGBAF)
	var clouds := FastNoiseLite.new()
	clouds.seed = cloud_seed
	clouds.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clouds.fractal_type = FastNoiseLite.FRACTAL_FBM
	clouds.fractal_octaves = 4
	clouds.frequency = 0.0034
	var warp := FastNoiseLite.new()
	warp.seed = cloud_seed + 3
	warp.frequency = 0.003
	var out := Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var cov := _coverage(x + 0.5, y + 0.5)
			if cov <= 0.0:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var w := warp.get_noise_2d(x, y) * 90.0
			# Cloud density 0..1, stretched a little sideways like a low overcast.
			var d := clampf(clouds.get_noise_2d((x + w) * 0.8, y + w * 0.5) * 1.1 + 0.5, 0.0, 1.0)
			d = smoothstep(0.2, 0.8, d)
			var col := SKY_LOW.lerp(SKY_HIGH, d)
			# Lit tops on the thick cloud, so it reads as billows, not smoke.
			var top := clampf(d - clampf(clouds.get_noise_2d((x + w) * 0.8, y + w * 0.5 - 14.0) * 1.1 + 0.5, 0.0, 1.0), 0.0, 1.0)
			col += CLOUD_TOP * top * 0.12
			col = col * (1.05 - 0.18 * (y / float(N)))   # lighter up top
			# The two glows light the air and, more, the cloud close to them.
			var gb := exp(-Vector2(x, y).distance_squared_to(Vector2(150, 600)) / (2.0 * 230.0 * 230.0))
			var gr := exp(-Vector2(x, y).distance_squared_to(Vector2(874, 600)) / (2.0 * 230.0 * 230.0))
			col += BLUE * gb * (0.35 + 0.65 * d) * 0.75 * gs
			col += RED * gr * (0.35 + 0.65 * d) * 0.75 * gs
			var v := Vector2(x - 512.0, y - 512.0).length() / 620.0
			col = col * (1.0 - 0.18 * v * v)   # soft vignette
			var h := bust.get_pixel(x, y)
			col = Color(col.r, col.g, col.b).lerp(Color(h.r, h.g, h.b), h.a)
			out.set_pixel(x, y, Color(clampf(col.r, 0, 1), clampf(col.g, 0, 1), clampf(col.b, 0, 1), cov))
	out.save_png(ProjectSettings.globalize_path(out_path))
	print("icon_compose: wrote ", out_path)
	quit()

## Anti-aliased coverage of the rounded tile at a pixel centre.
func _coverage(x: float, y: float) -> float:
	if x < LO or x > HI or y < LO or y > HI:
		return 0.0
	var cx := clampf(x, LO + R, HI - R)
	var cy := clampf(y, LO + R, HI - R)
	return clampf(0.5 - (Vector2(x - cx, y - cy).length() - R), 0.0, 1.0)
