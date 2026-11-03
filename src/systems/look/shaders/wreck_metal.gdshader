shader_type spatial;
render_mode cull_disabled;
// Wreck-only finish. No emission, flames or live engine lights.
// Weather is in the cruiser frame, not world Y or each individual plate:
// damage stays coherent across the leaning hull and never recolours the town.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform mat4 wreck_from_world;
// 0 hull, 1 exposed metal, 2 soot, 3 faded marking, 4 nozzle; walkways (their
// tops; sides stay exposed metal): 5 deck plate, 6 grating, 7 ramp, 8 landing pad.
uniform int finish = 0;
// Decks and grating lay out in the wreck's level frame (x, up, stern-ward), so a
// deck's filler strips carry its plates on without a seam; ramps and the pad on
// the plate itself (plate_half: the box's half size).
uniform mat4 level_from_world;
uniform vec3 plate_half = vec3(1.0);
varying vec3 hull_pos;
varying vec3 hull_normal;
varying vec3 plate_pos;
varying vec3 plate_normal;
varying vec3 level_pos;
varying vec3 level_normal;

void vertex() {
	hull_pos = (wreck_from_world * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hull_normal = normalize((wreck_from_world * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	level_pos = (level_from_world * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	level_normal = normalize((level_from_world * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The wreck field is drawn merged (WorldScenery._merge_wreck_plates): each
	// vertex carries its plate's own position and normal.
	plate_pos = CUSTOM0.xyz;
	plate_normal = CUSTOM1.xyz;
}

float grain(vec3 p, float scale) {
	vec3 n = abs(normalize(hull_normal));
	n /= max(n.x + n.y + n.z, 0.001);
	return texture(noise_tex, p.yz * scale).r * n.x
		+ texture(noise_tex, p.xz * scale + 0.31).r * n.y
		+ texture(noise_tex, p.xy * scale + 0.67).r * n.z;
}

// 1 within half-width w of zero, edged over one pixel.
float band(float d, float w) {
	float fw = max(fwidth(d), 1e-4);
	return 1.0 - smoothstep(w - fw, w + fw, abs(d));
}

// A 50/50 square wave of period 1, edged over one pixel.
float square(float x) {
	return clamp((abs(fract(x) - 0.5) - 0.25) / max(fwidth(x), 1e-4) + 0.5, 0.0, 1.0);
}

// How well a pattern of this period (metres) still reads at this pixel; fine
// detail fades to its average with distance instead of shimmering.
float detail(vec2 p, float period) {
	vec2 fw = fwidth(p);
	return 1.0 - smoothstep(0.12, 0.45, max(fw.x, fw.y) / period);
}

// Old safety yellow over black, chipped through to the metal.
vec3 hazard(float x, float wear) {
	vec3 c = mix(vec3(0.045, 0.043, 0.04), vec3(0.6, 0.45, 0.1), square(x));
	return mix(c, vec3(0.3, 0.3, 0.29), wear);
}

// Walkway plate: worn grey paint, plates on a grid, seams and corner bolts.
vec3 walk_plate(vec2 q, vec2 size, float tone) {
	vec2 e = (0.5 - abs(fract(q / size) - 0.5)) * size;
	float seam = band(min(e.x, e.y), 0.03);
	float bolt = 1.0 - smoothstep(0.035, 0.055, length(e - 0.16));
	vec3 c = mix(vec3(0.15, 0.155, 0.155), vec3(0.25, 0.25, 0.24), tone);
	c *= 1.0 - seam * 0.7;
	return mix(c, vec3(0.36, 0.35, 0.33), bolt * detail(q, 0.3));
}

void fragment() {
	vec3 p = hull_pos;
	float broad = grain(p, 0.002);
	float medium = grain(p + 71.0, 0.012);
	float fine = grain(p, 0.14);
	vec3 an = abs(plate_normal);
	vec2 uv = plate_pos.yz;
	if (an.y > an.x && an.y > an.z) { uv = plate_pos.xz; }
	else if (an.z > an.x) { uv = plate_pos.xy; }
	vec2 panel = abs(fract(uv / vec2(7.5, 11.0)) - 0.5);
	float seam = smoothstep(0.478, 0.497, max(panel.x, panel.y));
	float panel_tone = texture(noise_tex, floor(uv / vec2(7.5, 11.0)) * 0.173).r;
	vec3 steel = mix(vec3(0.115, 0.13, 0.15), vec3(0.23, 0.25, 0.27), panel_tone);
	vec3 paint = vec3(0.29, 0.315, 0.33);
	float chips = smoothstep(0.53, 0.70, medium + fine * 0.06 + seam * 0.12);
	vec3 colour = mix(paint, steel, chips);
	// Heat-peeled paint, irregular black impact stains and rust in plate seams.
	float breach = (1.0 - smoothstep(78.0, 140.0, abs(p.z))) * smoothstep(15.0, 40.0, p.x);
	float scorch = smoothstep(0.49, 0.7, broad + medium * 0.08) * 0.65;
	scorch = max(scorch, breach * (0.35 + smoothstep(0.32, 0.64, medium) * 0.60));
	float oxide = smoothstep(0.54, 0.68, medium) * (0.09 + seam * 0.45) * (1.0 - scorch);
	colour = mix(colour, vec3(0.25, 0.12, 0.065), oxide * 0.65);
	colour *= 1.0 - seam * 0.6;
	colour = mix(colour, vec3(0.055, 0.052, 0.05), scorch);
	// Fine scored streaks, kept subtle so the broad forms still read at distance.
	float scores = smoothstep(0.77, 0.9, texture(noise_tex, uv * vec2(2.0, 0.045)).r);
	colour = mix(colour, steel * 1.35, scores * chips * 0.22);
	if (finish == 1) { colour = mix(steel * 1.35, vec3(0.08, 0.075, 0.07), scorch * 0.65); }
	if (finish == 2) { colour = mix(vec3(0.045, 0.042, 0.04), colour, 0.15); }
	if (finish == 3) { colour = mix(vec3(0.25, 0.065, 0.045), steel, chips * 0.65); }
	if (finish == 4) { colour = mix(vec3(0.025, 0.028, 0.033), vec3(0.09, 0.095, 0.10), fine); }
	// Sand only gathers on exposed upward faces, never coats every hull plate.
	float dust = smoothstep(0.5, 0.93, hull_normal.y) * (0.09 + medium * 0.12);
	float metallic = (finish == 4 ? 0.24 : mix(0.2, 0.65, chips)) * (1.0 - scorch * 0.8);
	float rough = clamp(0.72 + scorch * 0.24 + oxide * 0.12 - chips * 0.12, 0.0, 1.0);
	if (finish >= 5) {
		// Walkways: sides are bare edge metal, the walking face carries the finish.
		colour = mix(steel * 1.2, vec3(0.08, 0.075, 0.07), scorch * 0.5);
		bool top = (finish == 7 || finish == 8) ? plate_normal.y > 0.5 : level_normal.y > 0.7;
		dust = 0.0;
		if (top) {
			vec2 q = (finish == 7 || finish == 8) ? plate_pos.xz : level_pos.xz;
			float tone = texture(noise_tex, floor(q / 3.0) * 0.211).r;
			float wear = smoothstep(0.4, 0.8, texture(noise_tex, q * 0.035 + 0.5).r);
			float peel = smoothstep(0.58, 0.72, medium + fine * 0.08);
			vec3 c = walk_plate(q, finish == 7 ? vec2(plate_half.x * 2.0, 2.4) : vec2(3.0, 6.0), tone);
			float shine = 0.0;
			if (finish == 5) {
				// Diamond tread: alternating raised lugs, polished where boots go.
				vec2 t = q / 0.2;
				vec2 f = fract(t) - 0.5;
				float flip = mod(floor(t.x) + floor(t.y), 2.0);
				vec2 o = flip > 0.5 ? vec2(f.x + f.y, f.x - f.y) : vec2(f.x - f.y, f.x + f.y);
				float lug = (1.0 - smoothstep(0.26, 0.32, length(o * vec2(0.55, 2.4)))) * detail(q, 0.2);
				shine = lug * (0.3 + wear * 0.5);
				c = mix(c, vec3(0.43, 0.43, 0.41), shine);
				c *= 1.0 - (1.0 - detail(q, 0.2)) * 0.08;
			} else if (finish == 6) {
				// Open bar grating: dark gaps down into the hold, flat stringers
				// every 2 m and cross beams every 6 m.
				vec2 cell = abs(fract(q / 0.3) - 0.5);
				vec2 fw = fwidth(q / 0.3);
				float bars = smoothstep(0.38 - max(fw.x, fw.y), 0.38 + max(fw.x, fw.y), max(cell.x, cell.y));
				bars = mix(0.45, bars, detail(q, 0.3));
				float beam = max(band(fract(q.y / 2.0 + 0.5) - 0.5, 0.04), band(fract(q.x / 6.0 + 0.5) - 0.5, 0.012));
				bars = max(bars, beam);
				c = mix(vec3(0.018, 0.017, 0.016), mix(c, vec3(0.34, 0.34, 0.32), wear * 0.5), bars);
				shine = bars * wear * 0.4;
			} else if (finish == 7) {
				// Ramp: anti-slip cleats across it, hazard bands down both edges.
				float cleat = band(fract(q.y / 0.45) - 0.5, 0.07) * detail(q, 0.45);
				cleat = max(cleat, (1.0 - detail(q, 0.45)) * 0.3);
				c = mix(c * (1.0 - band(fract(q.y / 0.45) - 0.5, 0.11) * 0.35), vec3(0.42, 0.41, 0.39), cleat);
				float edge = plate_half.x - abs(q.x);
				float stripe = 1.0 - smoothstep(0.65, 0.7, edge);
				c = mix(c, hazard((abs(q.x) + q.y) / 0.9, peel * 0.8 + wear * 0.3), stripe * (1.0 - cleat * 0.6));
				shine = cleat * 0.6;
			} else {
				// Landing pad: a ring and cross ticks, a hazard border, scorched
				// where engines lit off; the paint flaked by sun and blast.
				float r = length(q);
				float big = 0.42 * min(plate_half.x, plate_half.z);
				float paint = band(r - big, 0.3) + band(r - big * 0.62, 0.12);
				float arm = max(abs(q.x), abs(q.y));
				float tick = (band(q.x, 0.25) + band(q.y, 0.25)) * step(big * 0.72, arm) * step(arm, big * 0.92);
				paint = clamp(paint + tick, 0.0, 1.0) * (1.0 - peel * 0.85) * (1.0 - wear * 0.35);
				c = mix(c, vec3(0.6, 0.58, 0.52), paint);
				float edge = min(plate_half.x - abs(q.x), plate_half.z - abs(q.y));
				float border = 1.0 - smoothstep(1.15, 1.2, edge);
				c = mix(c, hazard((q.x + q.y) / 1.6, peel * 0.7), border);
				float burn = (1.0 - smoothstep(big * 0.2, big * 1.25, r)) * (0.55 + fine * 0.45);
				c = mix(c, vec3(0.03, 0.028, 0.026), burn * 0.75);
			}
			// Rust blooms from seams, grime gathers, sand drifts against the edges.
			float rust = smoothstep(0.55, 0.72, medium) * 0.45;
			c = mix(c, vec3(0.29, 0.13, 0.065), rust * (1.0 - shine));
			c = mix(c, vec3(0.06, 0.055, 0.05), smoothstep(0.5, 0.75, broad + medium * 0.1) * 0.45);
			dust = smoothstep(0.62, 0.88, broad * 0.6 + medium * 0.5) * 0.4;
			colour = c;
			metallic = mix(0.18, 0.6, shine);
			rough = clamp(0.82 - shine * 0.35 + rust * 0.1, 0.0, 1.0);
		}
	}
	colour = mix(colour, vec3(0.63, 0.46, 0.27), dust);
	ALBEDO = colour;
	METALLIC = metallic;
	ROUGHNESS = rough;
}
