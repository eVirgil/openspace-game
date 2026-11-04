shader_type spatial;
// Lava rock (issue #272): the lava moon's ground, all the way round its ball. The
// moon rock's blocky cells and layering (planet_center/radius, the per-instance
// hole that sinks an outer layer under the inner one, the wide twilight) in dark
// basalt, and the low ground molten: everything under lava_level (metres above
// the bare ball, AsteroidSphere.lava_level) is lava, lifted flat to that level so
// the pools read as liquid, flowing and glowing. No lava within safe_radius of the
// port (the station). The rock just above the lava catches its light. The same
// height is where the lava kills (AsteroidSphere.in_lava).

uniform vec4 rock_light : source_color = vec4(0.23, 0.2, 0.2, 1.0);
uniform vec4 rock_mid : source_color = vec4(0.14, 0.12, 0.12, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.35, 0.08, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform vec4 crust_color : source_color = vec4(0.06, 0.02, 0.01, 1.0);
uniform float glow_energy = 2.5;
uniform float lava_level = -2.0;
uniform float flow_speed = 0.35;
uniform vec3 safe_center = vec3(0.0);
uniform float safe_radius = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;
uniform float hole_sink = 6.0;
uniform float block_size = 3.5;
uniform vec4 dusk_color : source_color = vec4(0.22, 0.12, 0.1, 1.0);
uniform float dusk_strength = 0.25;
instance uniform vec4 hole_origin = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec3 hole_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hole_z = vec3(0.0, 0.0, 1.0);

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 wup;
varying float h_raw;            // the ground's own height, before the lava or a sink moves it

float clear_of_station(vec3 p) {
	return safe_radius > 0.0 ? smoothstep(safe_radius, safe_radius + 40.0, length(p - safe_center)) : 1.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
	h_raw = planet_radius > 0.0 ? length(wpos - planet_center) - planet_radius : wpos.y;
	bool moved = false;
	float clear = clear_of_station(wpos);
	if (h_raw < lava_level && clear > 0.0) {
		// The pools are liquid: flat at the lava level (the look only).
		wpos += wup * (lava_level - h_raw) * clear;
		wnorm = normalize(mix(wnorm, wup, clear));
		NORMAL = normalize((inverse(MODEL_MATRIX) * vec4(wnorm, 0.0)).xyz);
		moved = true;
	}
	if (hole_origin.w > 0.0) {
		vec3 rel = wpos - hole_origin.xyz;
		float edge = max(abs(dot(rel, hole_x)), abs(dot(rel, hole_z)));
		float k = 1.0 - smoothstep(hole_origin.w * 0.92, hole_origin.w * 1.02, edge);
		if (k > 0.0) {
			wpos -= wup * hole_sink * k;
			moved = true;
		}
	}
	if (moved) {
		VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
	}
}

float tri(vec3 p, vec3 w, float s) {
	return texture(noise_tex, p.zy * s).r * w.x + texture(noise_tex, p.xz * s).r * w.y + texture(noise_tex, p.xy * s).r * w.z;
}

float blocks(vec3 p, vec3 w, float size) {
	vec3 bend = vec3(tri(p, w, 0.05), tri(p + vec3(37.0), w, 0.05), tri(p + vec3(71.0), w, 0.05)) - 0.5;
	vec3 q = floor((p + bend * size * 1.6) / size) * size;
	return tri(q, w, 0.013);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	vec3 up = normalize(wup);
	vec3 aw = pow(abs(up), vec3(8.0));
	aw /= (aw.x + aw.y + aw.z);
	float h = h_raw;
	float big = tri(wpos, aw, 0.0016);
	float blk = blocks(wpos, aw, block_size);
	float blk2 = blocks(wpos + vec3(1.7), aw, block_size * 4.0);
	float fine = tri(wpos, aw, 0.21);
	float near_k = 1.0 - smoothstep(80.0, 600.0, dist);
	float clear = clear_of_station(wpos);

	// Basalt.
	vec3 alb = mix(rock_mid.rgb, rock_light.rgb, smoothstep(0.3, 0.8, big * 0.5 + blk2 * 0.5));
	alb *= mix(1.0, 0.85 + 0.3 * blk, near_k);
	float slope = 1.0 - clamp(dot(wnorm, up), 0.0, 1.0);
	alb = mix(alb, rock_dark.rgb, smoothstep(0.12, 0.5, slope) * 0.75);
	alb *= 0.9 + 0.2 * fine;
	float rough = 0.95;
	// The lava's light on the rock just above it (no real lights: cheap).
	float bounce = (1.0 - smoothstep(lava_level, lava_level + 1.8, h)) * clear;
	vec3 emit = glow.rgb * alb * 6.0 * bounce * (0.8 + 0.4 * sin(TIME * 1.3 + fine * 6.0));

	// The lava: flowing noise, hotter in the deep middle, a darker rind at the edge.
	float edge_soft = 0.25 + dist * 0.002;
	float molten = (1.0 - smoothstep(lava_level - edge_soft, lava_level + edge_soft, h)) * clear;
	if (molten > 0.0) {
		vec2 fl = vec2(TIME * flow_speed, TIME * flow_speed * 0.6);
		float n1 = tri(wpos + vec3(fl.x, 0.0, fl.y) * 4.0, aw, 0.045);
		float n2 = tri(wpos - vec3(fl.y, 0.0, fl.x) * 2.5 + vec3(13.0), aw, 0.11);
		float n3 = tri(wpos + vec3(fl.x * 1.5, 0.0, -fl.y) + vec3(5.0), aw, 0.012);
		float swirl = n1 * 0.55 + n2 * 0.3 + n3 * 0.15;
		float depth = clamp((lava_level - h) / 2.0, 0.0, 1.0);
		vec3 lava_e = mix(glow.rgb, hot.rgb, smoothstep(0.6, 0.9, swirl) * (0.3 + 0.7 * depth));
		float heat = 0.25 + 0.8 * smoothstep(0.3, 0.8, swirl) + 0.35 * depth;
		heat *= 0.35 + 0.65 * smoothstep(0.0, 0.6, (lava_level - h) / edge_soft);
		alb = mix(alb, crust_color.rgb, molten);
		emit = mix(emit, lava_e * glow_energy * heat, molten);
		rough = mix(rough, 0.55, molten);
	}

	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	vec3 dusk = vec3(0.0);
	if (planet_radius > 0.0) {
		float sun_up = dot(up, normalize(sun_dir));
		dusk = alb * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, sun_up);
	}
	EMISSION = emit + dusk;
}
