shader_type canvas_item;
// Issue #537: the art bible's small vignette. One full-screen rect over the 3D,
// under the HUD; LookEnvironment sets strength from the preset's post.vignette.
uniform float strength = 0.25;
uniform float inner = 0.4;      // where the darkening starts (0 centre, ~1 the corners)

void fragment() {
	vec2 d = (SCREEN_UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0) * 2.0;
	float v = smoothstep(inner, 1.6, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, v * v * strength);
}
