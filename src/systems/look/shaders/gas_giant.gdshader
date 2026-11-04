shader_type spatial;
// The ringed giant as a real ball (content/core/planets/ringed_giant.json): the
// painting's bands (desert_sky.gdshader), bent by slow turbulence so they flow
// like gas (gas_bands.gdshaderinc). Unfogged like the sky; in daylight it fades
// toward the sky behind it by `visibility` (the painting's planet_visibility,
// set every frame by SpaceTravel). Its haze shell (gas_haze.gdshader) lies over it.
//
// Close up (the giant's own scene draws its cloud tops with this too) the bands
// give way to soft billows of the fog's own colour, `fog_color`, within about
// `fog_near` metres of the eye: the ground under the station is fog, not a plain.
render_mode unshaded, fog_disabled, cull_back;

#include "res://src/systems/look/shaders/gas_bands.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec4 color_a : source_color = vec4(0.85, 0.77, 0.69, 1.0);
uniform vec4 color_b : source_color = vec4(0.54, 0.44, 0.41, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.69, 0.44, 1.0);
uniform vec3 ring_normal = vec3(0.25, 0.95, 0.2);
uniform float bands = 22.0;
uniform float visibility = 1.0;
uniform vec4 haze : source_color = vec4(0.6, 0.65, 0.75, 1.0);
uniform vec4 fog_color : source_color = vec4(0.92, 0.84, 0.80, 1.0);
uniform vec4 night_color : source_color = vec4(0.27, 0.21, 0.32, 1.0);
uniform float radius_m = 3380.0;          // the cloud tops' radius, metres (the billows' scale)
uniform float fog_near = 1600.0;          // within this many metres the cloud tops are fog

varying vec3 n_world;

void vertex() {
	n_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(n_world);
	vec3 s = normalize(sun_dir);
	vec3 rn = normalize(ring_normal);
	vec3 albedo = gas_albedo(n, rn, bands, color_a.rgb, color_b.rgb, TIME);
	float lit_k = gas_light(n, s);
	vec3 to_eye = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float rim = pow(1.0 - max(dot(n, to_eye), 0.0), 3.0);
	vec3 night = night_color.rgb * mix(vec3(1.0), albedo / max(color_a.rgb, vec3(0.05)), 0.3);
	vec3 lit = mix(night, albedo * 1.15, lit_k) + glow.rgb * rim * lit_k * 0.4;

	// Nearer: cloud masses a few hundred metres across, lit and shadowed, so the
	// ball breaks into heaps of gas well before you reach it.
	float d = length(VERTEX);
	float mid_k = 1.0 - smoothstep(4000.0, 14000.0, d);
	if (mid_k > 0.001) {
		vec3 q = gas_turn(n, rn, TIME * 0.002) * radius_m / 520.0;
		float heap = gas_fbm(q + vec3(0.0, 0.0, TIME * 0.01), 4);
		float shade = gas_fbm(q + s * 0.35, 4);       // a little toward the sun: the heaps' lit sides
		float relief = clamp(0.75 + (heap - 0.5) * 0.9 + (heap - shade) * 1.6, 0.4, 1.3);
		lit *= mix(1.0, relief, mid_k);
	}

	// Close up: billows of fog drifting over the cloud tops, in the fog's colour.
	float near_k = 1.0 - smoothstep(fog_near * 0.35, fog_near, d);
	if (near_k > 0.001) {
		vec3 p = n * radius_m;
		vec3 drift = vec3(TIME * 1.6, TIME * 0.25, TIME * 0.9);
		float billow = gas_fbm(p / 140.0 + drift / 140.0, 4);
		float fine = gas_fbm(p / 28.0 + drift / 40.0, 3);
		float puff = smoothstep(0.25, 0.85, billow * 0.75 + fine * 0.35);
		vec3 fog_lit = mix(night_color.rgb * 1.3, fog_color.rgb, lit_k);
		vec3 close = fog_lit * (0.82 + 0.26 * puff);
		lit = mix(lit, close, near_k);
	}
	ALBEDO = mix(haze.rgb, lit, clamp(visibility, 0.0, 1.0));
}
