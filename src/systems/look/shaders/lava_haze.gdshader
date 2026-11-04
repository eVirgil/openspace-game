shader_type spatial;
// Heat shimmer (issue #272): a sheet of hot air a little above the lava, round the
// camera (LavaHaze moves it). It shows what is behind it, wobbled by a slow rising
// noise, strongest a few metres out and gone at its rim, near the camera, high up
// and over the station. Bent onto the ball: every vertex sits on one shell.
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled, world_vertex_coords;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 planet_center = vec3(0.0, -1500.0, 0.0);
uniform float shell_radius = 1500.0;   // the ball's radius + lava level + the sheet's height
uniform float strength = 0.004;        // screen fraction at full shimmer
uniform float reach = 90.0;            // metres from the camera where it is gone
uniform float fade = 1.0;              // 0..1 from the camera's height (LavaHaze)
uniform vec3 safe_center = vec3(0.0);
uniform float safe_radius = 0.0;

varying vec3 wpos;

void vertex() {
	vec3 d = normalize(VERTEX - planet_center);
	VERTEX = planet_center + d * shell_radius;
	wpos = VERTEX;
}

void fragment() {
	float dc = length(wpos - CAMERA_POSITION_WORLD);
	float k = (1.0 - smoothstep(reach * 0.4, reach, dc)) * smoothstep(3.0, 12.0, dc) * fade;
	if (safe_radius > 0.0) {
		k *= smoothstep(safe_radius, safe_radius + 40.0, length(wpos - safe_center));
	}
	vec2 n = vec2(
		texture(noise_tex, SCREEN_UV * vec2(3.0, 1.6) + vec2(0.0, TIME * 0.55)).r,
		texture(noise_tex, SCREEN_UV * vec2(2.2, 1.3) + vec2(0.37, TIME * 0.4)).r) - 0.5;
	ALBEDO = texture(screen_tex, SCREEN_UV + n * strength * k).rgb;
	ALPHA = clamp(k, 0.0, 1.0);
}
