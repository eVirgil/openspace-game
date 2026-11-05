shader_type spatial;
// Issue #193: the Remnant star cruiser, clean. One shader for every surface it is
// made of, picked by `finish`; the meshes are in the cruiser's own frame (x to
// starboard, y up, z bow to stern), so panels and window rows line up with the ship.
//   0 hull     light grey armour plates, seams, a little tone per plate, and rows
//              of small lit windows along the flanks (they make its size legible)
//   1 trim     dark grey bands, frames, turrets
//   2 deck     dark deck plates on a 2 m grid with lit seams near the edges
//   3 wall     panelled bulkheads: a pipe run and a dim light line on every
//              deck's height, kick vents, now and then a lit wall panel
//   4 grate    walkway grating
//   5 ramp     treads of chequer plate, a lit nosing on every step, hazard
//              stripes down both edges (the ramp shaft's flights, pit steps)
//   6 cargo    crates, stencilled, in drab colours
//   7 console  computers: gunmetal casings with vent slots; keyboards of lit keys
//              on top; racks of drive bays with blinking lights on the sides
//   8 rail     dark rails, a hazard band along them and a lit strip on top
//   9 bridge   polished dark floor with inlaid light lines
//  10 pad      a landing pad: welded steel (pad_metal.gdshaderinc) under a
//              painted ring and cross, edge lights (plate_half)
//  11 beacon   a red light that blinks
//  12 screen   a live display, one of four per screen: scrolling readouts, a
//              bar chart, a radar sweep, a trace (a face of the box is the screen)
//  13 turret   the dorsal gun houses: riveted gunmetal panels, grimed low, a
//              red accent line under the roof

uniform int finish = 0;
uniform vec4 hull_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
uniform vec4 trim_color : source_color = vec4(0.22, 0.23, 0.25, 1.0);
uniform vec4 deck_color : source_color = vec4(0.17, 0.18, 0.20, 1.0);
uniform vec4 wall_color : source_color = vec4(0.40, 0.42, 0.45, 1.0);
uniform vec4 accent : source_color = vec4(0.62, 0.10, 0.08, 1.0);
uniform vec4 window_light : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform vec4 strip_light : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 paint : source_color = vec4(0.95, 0.78, 0.22, 1.0);
uniform vec3 plate_half = vec3(10.0, 0.05, 10.0);
uniform float window_energy = 2.2;
uniform float screen_energy = 1.6;
// The gun houses (13): the deck's height under them and the accent line's above it.
uniform float turret_foot = 43.8;
uniform float turret_band = 2.35;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

#include "res://src/systems/look/shaders/pad_metal.gdshaderinc"

varying vec3 lpos;
varying vec3 lnorm;
varying vec2 fuv;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	fuv = UV;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The two coordinates across the face (cheap triplanar on the local normal).
vec2 face_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > a.y && a.x > a.z) return p.zy;
	if (a.z > a.y) return p.xy;
	return p.xz;
}

float seam(vec2 uv, vec2 size, float w) {
	vec2 g = abs(fract(uv / size) - 0.5) * size;
	vec2 e = size * 0.5 - g;
	return 1.0 - smoothstep(0.0, w, min(e.x, e.y));
}


// Where on its face a fragment is, 0..1 both ways: a BoxMesh lays its six faces
// out on a 3 x 2 grid of its UVs.
vec2 face01(vec2 uv) {
	return fract(uv * vec2(3.0, 2.0));
}

float stripes(float x, float w) {
	return step(0.5, fract(x / w));
}

// A screen's picture at face point f (0..1), kind 0..3, seed h.
vec3 screen_image(vec2 f, float kind, float h, vec3 c1, vec3 c2) {
	vec2 q = f;
	float frame_ = step(0.04, q.x) * step(q.x, 0.96) * step(0.06, q.y) * step(q.y, 0.94);
	vec3 col = vec3(0.01, 0.04, 0.06);
	float scan = 0.85 + 0.15 * sin(q.y * 220.0);
	if (kind < 1.0) {
		// Readouts: rows of text-like dashes scrolling up.
		float row = floor((q.y + TIME * 0.06 * (0.5 + h)) * 18.0);
		float cell = floor(q.x * 28.0);
		float on = step(0.35, hash2(vec2(cell, row) + h * 31.0)) * step(cell, 4.0 + hash2(vec2(row, h)) * 24.0);
		float gap = step(0.2, fract((q.y + TIME * 0.06 * (0.5 + h)) * 18.0)) * step(0.15, fract(q.x * 28.0));
		col += c1 * on * gap * 0.9;
		col += c2 * step(0.92, hash2(vec2(row, 3.0 + h))) * gap * 0.6;
	} else if (kind < 2.0) {
		// A bar chart, its bars breathing.
		float b = floor(q.x * 12.0);
		float tall = 0.2 + 0.6 * hash2(vec2(b, h)) + 0.12 * sin(TIME * (1.0 + hash2(vec2(h, b)) * 2.0) + b);
		float bar = step(q.y, tall) * step(0.2, fract(q.x * 12.0)) * step(fract(q.x * 12.0), 0.85);
		col += mix(c1, c2, step(0.7, tall)) * bar * 0.8;
		col += c1 * 0.25 * (1.0 - smoothstep(0.0, 0.01, abs(fract(q.y * 5.0) - 0.5) - 0.48));
	} else if (kind < 3.0) {
		// A radar: rings, a sweep and a few contacts.
		vec2 p = (q - 0.5) * vec2(1.6, 1.0);
		float r = length(p);
		float ring = 1.0 - smoothstep(0.0, 0.012, abs(fract(r * 6.0) - 0.5) * 0.17 - 0.07);
		float ang = mod(atan(p.y, p.x) - TIME * 1.4, 6.28318);
		float sweep = exp(-ang * 2.2) * step(r, 0.48);
		col += c1 * (ring * 0.25 * step(r, 0.48) + sweep * 0.8);
		for (int i = 0; i < 4; i++) {
			vec2 dot_ = vec2(hash2(vec2(h, float(i))) - 0.5, hash2(vec2(float(i), h)) - 0.5) * 0.7;
			col += c2 * (1.0 - smoothstep(0.012, 0.025, length(p - dot_)));
		}
	} else {
		// A trace running across, over a grid.
		float y = 0.5 + 0.28 * sin(q.x * 18.0 + TIME * 3.0 + h * 9.0) * sin(q.x * 5.0 - TIME * 0.7);
		float line = 1.0 - smoothstep(0.004, 0.018, abs(q.y - y));
		float gridl = (1.0 - smoothstep(0.0, 0.006, abs(fract(q.x * 8.0) - 0.5) * 0.125 - 0.06))
			+ (1.0 - smoothstep(0.0, 0.006, abs(fract(q.y * 5.0) - 0.5) * 0.2 - 0.096));
		col += c1 * line + c1 * 0.12 * clamp(gridl, 0.0, 1.0);
		col += c2 * step(0.95, fract(q.x * 3.0 - TIME * 0.5)) * 0.25;
	}
	return col * scan * frame_;
}

void fragment() {
	vec2 uv = face_uv(lpos, lnorm);
	float n = texture(noise_tex, uv * 0.013).r;
	vec3 col = hull_color.rgb;
	float rough = 0.55;
	float metal = 0.55;
	vec3 emit = vec3(0.0);
	if (finish == 0) {
		// Staggered armour plates, each its own tone, seams between them.
		vec2 size = vec2(6.0, 3.2);
		vec2 st = uv;
		st.x += step(0.5, fract(st.y / (size.y * 2.0))) * size.x * 0.5;
		vec2 cell = floor(st / size);
		float tone = hash2(cell);
		col = hull_color.rgb * (0.86 + tone * 0.2) * (0.92 + n * 0.14);
		col *= 1.0 - 0.55 * seam(st, size, 0.07);
		// Trenches every 24 m along the keel.
		float trench = 1.0 - smoothstep(0.0, 0.35, (0.5 - abs(fract(lpos.z / 24.0) - 0.5)) * 24.0);
		col *= 1.0 - 0.35 * trench;
		rough = 0.5 + tone * 0.15;
		// A few rows of small windows along the flanks and shoulders, some lit: in
		// bands of three decks with plain armour between, so from afar they read as
		// lines of light, not grit.
		if (abs(lnorm.x) > 0.55 && abs(lnorm.y) < 0.8) {
			vec2 w = vec2(lpos.z, lpos.y);
			vec2 wsize = vec2(3.5, 3.6);
			vec2 wc = floor(w / wsize);
			vec2 wf = fract(w / wsize);
			float pane = step(0.25, wf.x) * step(wf.x, 0.6) * step(0.4, wf.y) * step(wf.y, 0.62);
			float lit = step(0.6, hash2(wc + vec2(lnorm.x > 0.0 ? 3.0 : 7.0, 1.0)));
			float band = step(fract(wc.y / 7.0), 0.4) * step(0.12, fract(wc.x / 9.0));
			emit = window_light.rgb * pane * lit * band * window_energy;
			col = mix(col, vec3(0.05, 0.06, 0.07), pane * band * (1.0 - lit));
		}
	} else if (finish == 1) {
		col = trim_color.rgb * (0.85 + n * 0.25);
		col *= 1.0 - 0.4 * seam(uv, vec2(4.0, 2.0), 0.05);
		rough = 0.45;
		metal = 0.7;
	} else if (finish == 2) {
		vec2 g = lpos.xz;
		col = deck_color.rgb * (0.9 + n * 0.2) * (0.92 + hash2(floor(g / 2.0)) * 0.12);
		col *= 1.0 - 0.45 * seam(g, vec2(2.0), 0.04);
		// Scuffs where boots go, darker in streaks.
		col *= 0.9 + 0.1 * smoothstep(0.3, 0.7, texture(noise_tex, g * vec2(0.02, 0.15)).r);
		rough = 0.7;
		metal = 0.4;
		if (lnorm.y < 0.5) {
			col = trim_color.rgb * 0.8;
		}
	} else if (finish == 5) {
		// A flight of the ramp shaft: chequer-plate treads, each with a lit nosing,
		// and hazard stripes down both edges.
		vec2 f = face01(fuv);
		vec2 g = lpos.xz;
		float rise = lpos.y * 2.6;
		float tread = fract(rise);
		vec2 d = fract(g * 7.0);
		float bump = step(0.45, abs(d.x - d.y)) * step(abs(d.x + d.y - 1.0), 0.25);
		col = vec3(0.24, 0.25, 0.27) * (0.85 + n * 0.25) + bump * 0.06;
		col *= 1.0 - 0.5 * (1.0 - smoothstep(0.0, 0.06, tread)) ;
		float nose = 1.0 - smoothstep(0.0, 0.035, abs(tread - 0.08));
		emit = strip_light.rgb * nose * 1.4 * step(0.08, f.x) * step(f.x, 0.92);
		float edge = 1.0 - step(0.07, f.x) * step(f.x, 0.93);
		float hz = stripes(lpos.x + lpos.y + lpos.z, 0.7);
		col = mix(col, mix(vec3(0.05), paint.rgb * 0.85, hz), edge);
		rough = 0.55 - bump * 0.15;
		metal = 0.65;
		if (lnorm.y < 0.4) {
			col = trim_color.rgb * 0.8;
			emit = vec3(0.0);
		}	} else if (finish == 3) {
		col = wall_color.rgb * (0.9 + n * 0.15);
		col *= 1.0 - 0.45 * seam(uv, vec2(3.0, 2.4), 0.04);
		rough = 0.6;
		metal = 0.45;
		// Every 12 m of height (a deck, a flight of the shaft): a pipe run, a light
		// line, kick vents at the foot and now and then a lit wall panel.
		float h = mod(lpos.y + 14.0, 12.0);
		float along = abs(lnorm.x) > abs(lnorm.z) ? lpos.z : lpos.x;
		if (abs(lnorm.y) < 0.5) {
			float pipe = step(2.5, h) * step(h, 3.0);
			float pr = abs(fract((h - 2.5) / 0.25) - 0.5) * 2.0;
			col = mix(col, vec3(0.16, 0.17, 0.18) * (1.2 - pr * 0.6), pipe);
			metal = mix(metal, 0.85, pipe);
			rough = mix(rough, 0.35, pipe);
			col = mix(col, vec3(0.05), step(h, 0.45) * stripes(along, 0.18) * 0.8);
			float line = step(7.6, h) * step(h, 7.72);
			emit += strip_light.rgb * line * 0.9;
			float pc = floor(along / 6.0);
			vec2 pf = vec2(fract(along / 6.0), (h - 1.1) / 1.0);
			float panel = step(0.62, hash2(vec2(pc, floor((lpos.y + 14.0) / 12.0))))
				* step(0.3, pf.x) * step(pf.x, 0.55) * step(0.0, pf.y) * step(pf.y, 1.0);
			if (panel > 0.5) {
				col = vec3(0.02);
				emit += screen_image(vec2((pf.x - 0.3) / 0.25, pf.y), floor(hash2(vec2(pc, 5.0)) * 4.0),
					hash2(vec2(pc, 9.0)), strip_light.rgb, accent.rgb * 2.0) * 1.2;
			}
		}	} else if (finish == 4) {
		vec2 g = lpos.xz;
		float slat = step(0.55, fract(g.x * 3.0)) + step(0.55, fract(g.y * 3.0));
		col = mix(vec3(0.12, 0.13, 0.14), vec3(0.30, 0.31, 0.33), clamp(slat, 0.0, 1.0));
		rough = 0.6;
		metal = 0.7;
	} else if (finish == 6) {
		vec3 c = floor(lpos / 3.0);
		float h = hash2(c.xz + c.y);
		col = mix(vec3(0.30, 0.32, 0.26), vec3(0.42, 0.40, 0.36), h) * (0.85 + n * 0.25);
		col *= 1.0 - 0.5 * seam(uv, vec2(1.2, 1.2), 0.04);
		float stencil = step(0.8, fract(uv.x * 0.7 + h)) * step(0.5, fract(uv.y * 0.9));
		col = mix(col, paint.rgb * 0.7, stencil * 0.35);
		rough = 0.8;
		metal = 0.2;
	} else if (finish == 7) {
		// Computers. On top a keyboard of small keys, some lit, and a row of status
		// lights; down the sides rows of drive bays with lights blinking at their
		// own rates and vent slots; seams round the panels.
		vec2 f = face01(fuv);
		col = vec3(0.085, 0.09, 0.1) * (0.9 + n * 0.2);
		col *= 1.0 - 0.5 * seam(uv, vec2(1.2, 0.8), 0.02);
		rough = 0.5;
		metal = 0.55;
		if (lnorm.y > 0.5) {
			vec2 k = uv * vec2(7.0, 9.0);
			vec2 kc = floor(k);
			vec2 kf = fract(k);
			float key = step(0.12, kf.x) * step(kf.x, 0.88) * step(0.15, kf.y) * step(kf.y, 0.85);
			col = mix(col, vec3(0.16, 0.17, 0.19), key);
			float lit = step(0.8, hash2(kc)) * key;
			emit = mix(strip_light.rgb, accent.rgb * 2.0, step(0.6, hash2(kc + 9.0))) * lit * 1.4;
			emit *= 0.6 + 0.4 * step(0.3, fract(TIME * (0.2 + hash2(kc + 2.0)) + hash2(kc)));
		} else if (lnorm.y > -0.5) {
			float bay_h = 0.22;
			float row = floor(lpos.y / bay_h);
			float bf = fract(lpos.y / bay_h);
			float col_i = floor(uv.x / 0.5);
			float cf = fract(uv.x / 0.5);
			float bay = step(0.1, bf) * step(bf, 0.85) * step(0.06, cf) * step(cf, 0.94);
			col = mix(col, vec3(0.06, 0.065, 0.075), bay * 0.6);
			metal = 0.25;            // a mirror finish shows the desert sky in here
			rough = 0.6;
			float slot = stripes(lpos.y, 0.05) * step(0.5, cf) * step(cf, 0.88) * bay;
			col *= 1.0 - slot * 0.5;
			vec2 id_ = vec2(row, col_i) + floor(lpos.xz);
			float led = (1.0 - smoothstep(0.02, 0.05, length(vec2(cf - 0.16, bf - 0.47) * vec2(0.5, bay_h) / 0.04)));
			float blink = step(0.45, fract(TIME * (0.4 + hash2(id_) * 3.0) + hash2(id_ + 4.0)));
			vec3 lc = hash2(id_ + 7.0) > 0.85 ? accent.rgb * 2.5 : (hash2(id_ + 8.0) > 0.5 ? vec3(0.3, 1.0, 0.45) : strip_light.rgb);
			emit = lc * led * blink * 2.0 * bay;
			emit += strip_light.rgb * 0.5 * (1.0 - smoothstep(0.0, 0.015, abs(f.y - 0.04))) ;
		}
	} else if (finish == 8) {
		vec2 f = face01(fuv);
		col = trim_color.rgb * 0.75 * (0.9 + n * 0.2);
		rough = 0.4;
		metal = 0.8;
		if (lnorm.y > 0.6) {
			// The handrail's top: a lit strip down its middle.
			emit = strip_light.rgb * (1.0 - smoothstep(0.15, 0.3, abs(f.x - 0.5))) * 0.9;
		} else {
			float band = step(0.55, f.y) * step(f.y, 0.85);
			float hz = stripes(lpos.x + lpos.y + lpos.z, 0.5);
			col = mix(col, mix(vec3(0.04), paint.rgb * 0.8, hz), band);
		}	} else if (finish == 9) {
		vec2 g = lpos.xz;
		col = vec3(0.10, 0.105, 0.115) * (0.9 + n * 0.15);
		col *= 1.0 - 0.3 * seam(g, vec2(3.0), 0.03);
		float line = 1.0 - smoothstep(0.04, 0.12, (0.5 - abs(fract(g.x / 7.0) - 0.5)) * 7.0);
		emit = strip_light.rgb * line * 1.2 * step(0.5, lnorm.y);    // the floor's top only, not a slab's edge
		rough = 0.42;
		metal = 0.3;
	} else if (finish == 10) {
		vec2 p = lpos.xz;
		float r = length(p);
		float edge = min(plate_half.x, plate_half.z);
		vec2 slope;
		pad_metal(p, edge, wall_color.rgb * 1.1, deck_color.rgb, 0.45, vec3(0.0), 0.0, col, rough, metal, slope);
		if (lnorm.y > 0.5) {
			NORMAL = pad_metal_normal(slope, MODEL_MATRIX, VIEW_MATRIX);
		}
		// Paint over the steel, scuffed thin in places.
		float ring = step(abs(r - edge * 0.78), 0.45);
		float cross_ = (step(abs(p.x), 0.4) + step(abs(p.y), 0.4)) * step(r, edge * 0.55);
		float painted = clamp(ring + cross_, 0.0, 1.0) * (0.7 + 0.25 * smoothstep(0.3, 0.6, n));
		col = mix(col, paint.rgb, painted);
		rough = mix(rough, 0.7, painted);
		metal = mix(metal, 0.1, painted);
		// Lights round the rim, every 30 degrees.
		float ang = atan(p.y, p.x);
		float dots = step(0.9, fract(ang / 6.2831 * 12.0)) * step(abs(r - edge * 0.93), 0.35);
		emit = strip_light.rgb * dots * 3.0;
	} else if (finish == 13) {
		// A gun house: gunmetal armour in small riveted panels, each its own tone,
		// grimed toward its foot, a thin accent line round it under the roof.
		vec2 size = vec2(1.6, 0.9);
		vec2 cell = floor(uv / size);
		float tone = hash2(cell + 17.0);
		col = mix(trim_color.rgb, hull_color.rgb, 0.55) * (0.88 + tone * 0.16) * (0.9 + n * 0.18);
		col *= 1.0 - 0.5 * seam(uv, size, 0.035);
		vec2 rf = fract(uv / size);
		float rivet = 1.0 - smoothstep(0.03, 0.06, min(length((rf - vec2(0.08, 0.15)) * size), length((rf - vec2(0.92, 0.15)) * size)));
		col *= 1.0 - 0.3 * rivet;
		float h = lpos.y - turret_foot;
		col *= mix(0.72, 1.0, smoothstep(0.0, 1.4, h));
		if (abs(lnorm.y) < 0.6) {
			col = mix(col, accent.rgb * 0.9, step(abs(h - turret_band), 0.09));
		}
		rough = 0.42 + tone * 0.12;
		metal = 0.68;
	} else if (finish == 11) {
		col = accent.rgb;
		emit = vec3(1.0, 0.12, 0.08) * step(0.82, fract(TIME * 0.6)) * 8.0 + vec3(0.4, 0.04, 0.03);
	} else if (finish == 12) {
		// A display: the box's biggest faces are the glass, its edges a bezel.
		vec2 f = face01(fuv);
		vec3 cell = floor(lpos * 0.7);
		float h = hash2(cell.xz + cell.y * 1.7);
		col = vec3(0.02, 0.025, 0.03);
		rough = 0.15;
		metal = 0.2;
		emit = screen_image(f, floor(h * 4.0), h, strip_light.rgb, mix(accent.rgb * 2.2, paint.rgb, step(0.5, h)))
			* screen_energy;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
