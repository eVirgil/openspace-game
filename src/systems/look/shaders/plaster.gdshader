shader_type spatial;
// Sun-bleached plaster: dirt rising from the ground, bleached tops, patchy repairs,
// and an optional painted band (the dyed-cloth accent on buildings).

uniform vec4 plaster : source_color = vec4(0.85, 0.76, 0.63, 1.0);
uniform vec4 dirt : source_color = vec4(0.55, 0.42, 0.32, 1.0);
uniform vec4 band_color : source_color = vec4(0.12, 0.48, 0.47, 1.0);
uniform float band_y = -1000.0;          // world height of the painted band; off by default
uniform float band_width = 0.5;
uniform float ground_y = 8.0;
uniform float dirt_height = 1.8;
uniform float tile_size = 0.0;
uniform float metallic_amount = 0.0;    // issue #45: town styles (metal walls)
uniform float surface_roughness = 0.9;          // > 0: stone slabs on upward faces (paving)
uniform float relief = 0.06;            // issue #537: metres of relief the noise stands for (0: flat)
uniform vec4 sand_drift : source_color = vec4(0.79, 0.58, 0.35, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 side_uv = vec2(wpos.x + wpos.z, wpos.y);
	float n = texture(noise_tex, side_uv * 0.09).r;
	float blot = texture(noise_tex, side_uv * 0.021 + vec2(0.3, 0.1)).r;
	float streak = texture(noise_tex, vec2(side_uv.x * 0.35, side_uv.y * 0.03)).r;

	vec3 alb = plaster.rgb * (0.9 + 0.16 * n);
	alb = mix(alb, alb * vec3(0.93, 0.88, 0.82), smoothstep(0.55, 0.75, blot));  // old patches
	alb *= 1.0 - 0.07 * smoothstep(0.5, 0.8, streak) * (1.0 - wnorm.y);         // wind streaks
	float h = wpos.y - ground_y;
	float dirt_k = 1.0 - smoothstep(0.0, dirt_height * (0.7 + 0.6 * n), h);
	alb = mix(alb, dirt.rgb, dirt_k * 0.75);
	alb = mix(alb, alb * 1.08, smoothstep(0.6, 0.95, wnorm.y));                   // bleached tops
	float in_band = step(abs(wpos.y - band_y), band_width) * (1.0 - smoothstep(0.62, 0.8, blot));
	alb = mix(alb, band_color.rgb * (0.85 + 0.2 * n), in_band);

	if (tile_size > 0.0 && wnorm.y > 0.9) {
		vec2 cell = floor(wpos.xz / tile_size + vec2(0.0, floor(wpos.x / tile_size) * 0.5));
		vec2 g = abs(fract(wpos.xz / tile_size + vec2(0.0, floor(wpos.x / tile_size) * 0.5)) - 0.5);
		float seam = smoothstep(0.465, 0.495, max(g.x, g.y));
		float tile_var = texture(noise_tex, cell * 0.173).r;
		alb *= (0.9 + 0.16 * tile_var) * (1.0 - seam * 0.22);
		float drift = smoothstep(0.55, 0.8, texture(noise_tex, wpos.xz * 0.012).r * 0.7 + n * 0.3);
		alb = mix(alb, sand_drift.rgb, drift * 0.85);
	}
	ALBEDO = alb;
	// Issue #537: relief, so a raking sun catches the walls instead of lighting a
	// flat card. The normal tilts by the slope of the noise already sampled
	// (screen-space derivatives, no new reads), on walls only (the noise runs
	// along the wall, so on floors and roofs it would streak), fading out with
	// distance; the roughness follows the same noise and the dirt.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(n) * r1 + dFdy(n) * r2);
	float near_k = (1.0 - smoothstep(25.0, 70.0, -VERTEX.z)) * (1.0 - smoothstep(0.3, 0.6, abs(wnorm.y)));
	NORMAL = normalize(abs(det) * NORMAL - relief * near_k * grad);
	ROUGHNESS = clamp(surface_roughness - 0.1 + 0.2 * n + 0.08 * dirt_k, 0.0, 1.0);
	METALLIC = metallic_amount;
	SPECULAR = 0.3;
}
