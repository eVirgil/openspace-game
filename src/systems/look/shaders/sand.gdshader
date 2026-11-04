shader_type spatial;
// Sand: two scales of wind ripples in the normal, warm (not grey) shadow sides,
// slope tint and a soft glitter close to the camera. Journey is the reference.
//
// Issue #77: on a ball (planet_radius > 0) the broad colour is laid out in map
// coordinates (distance and direction along the ground from the port); the fine
// patterns (ripples, blowing sand, glitter) are triplanar on the world position,
// the three planes picked by the ground's up, so they keep their size all round
// the ball (map coordinates stretch sideways far from the port). On a flat world
// only the top-down plane is used. A layer of sand sinks out of the way wherever
// the finer layer inside it covers (hole_*: that layer's square, per instance).
//
// Ripples (issue #93), the usual cheap tricks rather than any sand simulation:
// two scales (~0.9 m and ~0.25 m) plus a faint 4 m swell, a lopsided profile (long
// windward slope, short steep lee), lines bent and broken by noise, faded on steep
// faces and toward the distance, darker troughs and lighter crests. Blowing sand:
// thin wisps scrolling downwind over the surface (wind_strength, 0 = still air).

uniform vec4 sand_light : source_color = vec4(0.91, 0.77, 0.56, 1.0);
uniform vec4 sand_mid : source_color = vec4(0.79, 0.58, 0.35, 1.0);
uniform vec4 sand_shadow : source_color = vec4(0.48, 0.35, 0.29, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform float ripple_strength = 0.22;
uniform float glitter = 0.25;              // was 1.0: from a distance it read as sparks
uniform float wind_strength = 1.0;         // blowing sand sheets; 0 = still air
uniform vec4 drift_color : source_color = vec4(0.97, 0.86, 0.68, 1.0);
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;          // 0 = flat ground
uniform float hole_sink = 6.0;
// Wide twilight (issue #77): one real sun lights the ball, and where it has set the
// sand glows a dim dusk instead of going black.
uniform vec4 dusk_color : source_color = vec4(0.42, 0.30, 0.30, 1.0);
uniform float dusk_strength = 0.35;
// The home ball seen from a neighbour's sky (space_travel.gd): a smooth sphere
// with its dunes as a flat print (tools/planets/bake_relief.gd): RGB the ground's
// normal (world axes), A its height. relief > 0 turns it on; relief_tilt
// steepens the slopes so the dunes still read from kilometres away.
uniform samplerCube relief_tex : filter_linear_mipmap;
uniform float relief = 0.0;
uniform float relief_tilt = 1.0;
uniform float relief_crest = 0.12;          // crests lighter, troughs darker (by height)
instance uniform vec4 hole_origin = vec4(0.0, 0.0, 0.0, 0.0);   // xyz, w = half size (0 = none)
instance uniform vec3 hole_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hole_z = vec3(0.0, 0.0, 1.0);

varying vec3 wpos;
varying vec3 wnorm;
varying vec2 mpos;
varying vec3 wup;

vec2 to_map(vec3 w) {
	if (planet_radius <= 0.0) {
		return w.xz;
	}
	vec3 d = normalize(w - planet_center);
	float hl = length(d.xz);
	if (hl < 1e-6) {
		return vec2(0.0);
	}
	return d.xz / hl * atan(hl, d.y) * planet_radius;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
	if (hole_origin.w > 0.0) {
		vec3 rel = wpos - hole_origin.xyz;
		float edge = max(abs(dot(rel, hole_x)), abs(dot(rel, hole_z)));
		// Fully sunk well inside the inner square, back level just past its edge.
		float k = 1.0 - smoothstep(hole_origin.w * 0.92, hole_origin.w * 1.02, edge);
		if (k > 0.0) {
			wpos -= wup * hole_sink * k;
			VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
		}
	}
	mpos = to_map(wpos);
}

// One ripple field in a plane, at 2D point q (metres): its height (0..1, for
// shading) and its slope (d height / d q, for the normal).
float ripple_h(float ph) {
	// Lopsided: rises over 80% of a wavelength, falls over the last 20%.
	float t = fract(ph / 6.28318);
	return smoothstep(0.0, 0.8, t) * (1.0 - smoothstep(0.8, 1.0, t));
}

vec3 ripples(vec2 q, vec2 wd, float fade_near, float fade_mid) {
	// Noise bends the crest lines (and breaks them where it changes fast).
	float n1 = texture(noise_tex, q * 0.019).r;
	float n2 = texture(noise_tex, q * 0.083 + vec2(0.31, 0.77)).r;
	float warp = n1 * 9.0 + n2 * 2.2;
	vec2 wd2 = normalize(vec2(wd.x + 0.3, wd.y - 0.25));
	float k1 = 7.0;     // ~0.9 m
	float k2 = 25.0;    // ~0.25 m
	float k3 = 1.55;    // ~4 m swell
	float p1 = dot(q, wd) * k1 + warp * 3.0;
	float p2 = dot(q, wd2) * k2 + warp * 6.0 + n2 * 4.0;
	float p3 = dot(q, wd) * k3 + warp;
	// Ripple fields come in patches (about half the sand), with smooth sand
	// between: a slow noise decides where, so whole stretches are bare.
	float field = texture(noise_tex, q * 0.011 + vec2(0.57, 0.11)).r;
	float patchy = smoothstep(0.48, 0.6, field * 0.75 + n1 * 0.25);
	float e = 0.15;
	float h1 = ripple_h(p1);
	float h2 = ripple_h(p2);
	float d1 = (ripple_h(p1 + e) - h1) / e * k1;
	float d2 = (ripple_h(p2 + e) - h2) / e * k2;
	float d3 = cos(p3) * k3;
	float a1 = 0.012 * fade_mid * patchy;
	float a2 = 0.006 * fade_near * patchy;
	float a3 = 0.018 * fade_mid;
	vec2 grad = wd * d1 * a1 + wd2 * d2 * a2 + wd * d3 * a3;
	float h = (h1 - 0.5) * fade_mid * patchy + (h2 - 0.5) * 0.3 * fade_near * patchy;
	return vec3(grad, h);
}

// Thin wisps of sand blowing downwind (0..1).
float drift(vec2 q, vec2 wd, float t) {
	vec2 along = wd * t;
	float a = texture(noise_tex, q * 0.012 - along * 0.010).r;
	float b = texture(noise_tex, vec2(dot(q, wd) * 0.05, dot(q, vec2(-wd.y, wd.x)) * 0.35) - vec2(t * 0.55, 0.0)).r;
	return smoothstep(0.55, 0.8, a) * smoothstep(0.45, 0.85, b);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n_big = texture(noise_tex, mpos * 0.0021).r;
	float n_mid = texture(noise_tex, mpos * 0.019).r;
	float n_fine = texture(noise_tex, mpos * 0.11).r;

	vec3 up = normalize(wup);
	vec3 base_n = wnorm;
	float crest = 0.0;
	if (relief > 0.0) {
		vec4 rt = texture(relief_tex, up);
		vec3 rn = normalize(rt.rgb * 2.0 - 1.0);
		base_n = normalize(up + (rn - up * dot(rn, up)) * relief_tilt);
		crest = (rt.a - 0.35) * relief;
	}
	vec3 alb = mix(sand_mid.rgb, sand_light.rgb, smoothstep(0.25, 0.85, n_big * 0.6 + n_mid * 0.4));
	float slope = 1.0 - clamp(dot(base_n, up), 0.0, 1.0);
	alb = mix(alb, sand_shadow.rgb, smoothstep(0.15, 0.55, slope) * 0.45);

	// Triplanar weights from the ground's up (not the dune's own slope, so a dune
	// face does not swap planes); sharp, so blends are short.
	vec3 aw = pow(abs(up), vec3(8.0));
	aw /= (aw.x + aw.y + aw.z);
	vec2 wd = normalize(wind_dir);
	float fade_near = 1.0 - smoothstep(6.0, 40.0, dist);
	float fade_mid = 1.0 - smoothstep(20.0, 160.0, dist);
	// Flat ground ripples more than steep dune faces (sand slides there).
	float flat_k = smoothstep(0.18, 0.03, slope);   // only the flatter sand ripples
	vec3 g3 = vec3(0.0);
	float rh = 0.0;
	float dr = 0.0;
	float t = TIME * wind_strength;
	// The existing fades are exactly zero at these endpoints. Avoid sampling
	// procedural fields once their contribution cannot reach the final material.
	bool ripple_active = dist < 160.0 && flat_k > 0.0;
	bool drift_active = dist < 250.0 && wind_strength > 0.0;
	if (aw.y > 0.01) {
		if (ripple_active) {
			vec3 r = ripples(wpos.xz, wd, fade_near, fade_mid);
			g3 += vec3(r.x, 0.0, r.y) * aw.y;
			rh += r.z * aw.y;
		}
		if (drift_active) {
			dr += drift(wpos.xz, wd, t) * aw.y;
		}
	}
	if (aw.x > 0.01) {
		if (ripple_active) {
			vec3 r = ripples(wpos.zy, wd, fade_near, fade_mid);
			g3 += vec3(0.0, r.y, r.x) * aw.x;
			rh += r.z * aw.x;
		}
		if (drift_active) {
			dr += drift(wpos.zy, wd, t) * aw.x;
		}
	}
	if (aw.z > 0.01) {
		if (ripple_active) {
			vec3 r = ripples(wpos.xy, wd, fade_near, fade_mid);
			g3 += vec3(r.x, r.y, 0.0) * aw.z;
			rh += r.z * aw.z;
		}
		if (drift_active) {
			dr += drift(wpos.xy, wd, t) * aw.z;
		}
	}
	g3 *= flat_k * ripple_strength / 0.16;
	g3 -= up * dot(g3, up);                     // along the ground only
	vec3 nw = normalize(base_n - g3);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// Troughs hold darker, coarser grains; crests catch the light.
	alb *= 1.0 + rh * 0.07 * flat_k;
	alb *= 0.94 + 0.12 * n_fine;
	alb *= 1.0 + crest * relief_crest * 2.0;
	// Blowing sand: brighter wisps over the surface, out to ~250 m, stronger on
	// open flats than in the lee of steep faces.
	float drift_flat = smoothstep(0.35, 0.05, slope);
	float dk = dr * wind_strength * (1.0 - smoothstep(60.0, 250.0, dist)) * (0.4 + 0.6 * drift_flat);
	alb = mix(alb, drift_color.rgb, dk * 0.35);
	ALBEDO = alb;
	// A little sheen at grazing angles (fine sand is not chalk).
	ROUGHNESS = 0.88;
	SPECULAR = 0.35;

	// Glitter: a few cells per metre catch the sun, only near the camera.
	EMISSION = vec3(0.0);
	if (dist < 40.0 && glitter > 0.0) {
		vec2 cell = floor((aw.y >= max(aw.x, aw.z) ? wpos.xz : (aw.x >= aw.z ? wpos.zy : wpos.xy)) * 14.0);
		float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
		float flick = fract(hsh * 37.0 + dot(v, vec3(3.1, 1.7, 2.3)) * 3.0);
		float sunlit = clamp(dot(nw, normalize(sun_dir)) * 3.0, 0.0, 1.0);
		EMISSION = vec3(1.0, 0.88, 0.7) * step(0.9985, flick) * fade_near * sunlit * glitter * 2.0;
	}
	float sun_up = dot(up, normalize(sun_dir));
	if (planet_radius > 0.0) {
		EMISSION += alb * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, sun_up);
	}
}
