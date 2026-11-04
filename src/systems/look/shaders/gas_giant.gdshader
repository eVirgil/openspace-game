shader_type spatial;
// The ringed giant as a real ball (content/core/planets/ringed_giant.json): the
// same bands, sun and rim as the painting in desert_sky.gdshader, so swapping the
// painting for the ball looks the same from the port. Unfogged like the sky; in
// daylight it fades toward the sky behind it by `visibility` (the painting's
// planet_visibility, set every frame by SpaceTravel).
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec4 color_a : source_color = vec4(0.85, 0.77, 0.69, 1.0);
uniform vec4 color_b : source_color = vec4(0.54, 0.44, 0.41, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.69, 0.44, 1.0);
uniform vec3 ring_normal = vec3(0.25, 0.95, 0.2);
uniform float bands = 22.0;
uniform float visibility = 1.0;
uniform vec4 haze : source_color = vec4(0.6, 0.65, 0.75, 1.0);

varying vec3 n_world;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	n_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(n_world);
	float lat = dot(n, normalize(ring_normal));
	float band = sin(lat * bands + sin(lat * 7.0) * 1.6) * 0.5 + 0.5;
	band = mix(band, hash(floor(lat * 30.0)), 0.25);
	vec3 albedo = mix(color_b.rgb, color_a.rgb, band);
	vec3 s = normalize(sun_dir);
	float lambert = smoothstep(-0.15, 0.6, dot(n, s));
	vec3 to_eye = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float rim = pow(1.0 - max(dot(n, to_eye), 0.0), 3.0);
	vec3 lit = albedo * (lambert * 1.15 + 0.06) + glow.rgb * rim * lambert * 0.4;
	ALBEDO = mix(haze.rgb, lit, clamp(visibility, 0.0, 1.0));
}
