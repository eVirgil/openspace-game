// The ringed giant's gas, shared by its ball (gas_giant.gdshader) and its haze
// shell (gas_haze.gdshader): smooth 3D noise, and the banded colour of the gas
// at a direction from the ball's centre. The bands are the sky painting's
// (desert_sky.gdshader), bent by slow turbulence so they read as flowing gas,
// not stripes painted on a ball.

float gas_hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float gas_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gas_hash3(i), gas_hash3(i + vec3(1, 0, 0)), f.x),
			mix(gas_hash3(i + vec3(0, 1, 0)), gas_hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(gas_hash3(i + vec3(0, 0, 1)), gas_hash3(i + vec3(1, 0, 1)), f.x),
			mix(gas_hash3(i + vec3(0, 1, 1)), gas_hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float gas_fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * gas_noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// `n` turned round the axis `k` by `a` radians.
vec3 gas_turn(vec3 n, vec3 k, float a) {
	return n * cos(a) + cross(k, n) * sin(a) + k * dot(k, n) * (1.0 - cos(a));
}

// The gas's colour at direction `n` (unit, from the centre). `rn`: the ring's
// plane normal (the bands run round it). `t`: seconds; each band drifts at its
// own speed, so the turbulence slowly shears.
vec3 gas_albedo(vec3 n, vec3 rn, float bands, vec3 ca, vec3 cb, float t) {
	float lat = dot(n, rn);
	vec3 m = gas_turn(n, rn, t * (0.004 + 0.003 * sin(lat * 9.0)));
	float w = gas_fbm(m * 3.2, 4) - 0.5;
	float lat_w = lat + w * 0.07 + (gas_fbm(m * 11.0 + w * 3.0, 3) - 0.5) * 0.025;
	float band = sin(lat_w * bands + sin(lat_w * 7.0) * 1.6) * 0.5 + 0.5;
	float stripe = gas_fbm(vec3(lat_w * 30.0, 0.5, 0.5), 2);
	band = mix(band, stripe, 0.25);
	vec3 albedo = mix(cb * 0.85, ca * 1.04, band);
	return albedo * (0.9 + 0.2 * gas_fbm(m * 24.0, 3));
}

// Sunlight on the gas: soft (it wraps past the terminator, as light does in a
// thick atmosphere), and never black on the far side.
float gas_light(vec3 n, vec3 s) {
	return clamp((dot(n, s) + 0.35) / 1.35, 0.0, 1.0);
}
