shader_type spatial;
// The ringed giant's air: a shell round the ball (SpaceTravel.make_haze) that
// marches the view ray through a haze thickening toward the cloud tops. Two
// layers, each thinning with height: a thin high one that gives the ball a soft
// glowing edge from space (so it reads as gas from far off), and a dense low one
// a few hundred metres deep that turns the cloud tops to fog as you come down.
// From the station you look down into fog; skimming the clouds you fly in it.
//
// Drawn back faces only and with no depth test, so it works from inside the
// shell too; the ray stops at the cloud tops and at anything solid in front
// (the depth texture: the station, your ship). Settings: the type's body.haze
// in content/core/planets/types.json.
render_mode unshaded, fog_disabled, cull_front, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 center = vec3(0.0);
uniform float cloud_r = 3380.0;           // the cloud tops' radius
uniform float top = 3000.0;               // the shell: this far over the cloud tops
uniform float low_density = 0.004;        // per metre at the cloud tops (the fog)
uniform float low_height = 140.0;         // metres for it to fall to 1/e
uniform float high_density = 0.0002;      // the glow round the ball
uniform float high_height = 520.0;
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec4 day_color : source_color = vec4(0.92, 0.84, 0.80, 1.0);
uniform vec4 night_color : source_color = vec4(0.27, 0.21, 0.32, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.69, 0.44, 1.0);
uniform float visibility = 1.0;

const int STEPS = 14;                     // per half of the ray (down to, and up from, its lowest point)

// Entry and exit distances of a ray through a sphere (x > y when it misses).
vec2 sphere_hit(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(1.0, -1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

float density(float h) {
	h = max(h, 0.0);
	return low_density * exp(-h / low_height) + high_density * exp(-h / high_height);
}

// March [a, b] along the ray, samples bunched toward `toward_end` ? b : a (the
// low end, where the haze is thickest), adding light into col and taking from trans.
void march(vec3 ro, vec3 rd, float a, float b, bool toward_end, vec3 s, inout vec3 col, inout float trans) {
	float len = b - a;
	if (len <= 0.01) {
		return;
	}
	float mie = pow(max(dot(rd, s), 0.0), 6.0) * 0.35;
	float prev = 0.0;
	for (int i = 1; i <= STEPS; i++) {
		float u = float(i) / float(STEPS);
		float f = toward_end ? 1.0 - (1.0 - u) * (1.0 - u) : u * u;
		float um = (float(i) - 0.5) / float(STEPS);
		float fm = toward_end ? 1.0 - (1.0 - um) * (1.0 - um) : um * um;
		vec3 p = ro + rd * (a + len * fm);
		float r = length(p);
		float dt = len * (f - prev);
		prev = f;
		float rho = density(r - cloud_r);
		float k = 1.0 - exp(-rho * dt);
		float sun_k = smoothstep(-0.3, 0.4, dot(p / r, s));
		vec3 c = mix(night_color.rgb, day_color.rgb, sun_k) + glow.rgb * mie * sun_k;
		col += trans * k * c;
		trans *= 1.0 - k;
	}
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(wp - cam);
	vec3 ro = cam - center;
	vec2 outer = sphere_hit(ro, rd, cloud_r + top);
	float t0 = max(outer.x, 0.0);
	float t1 = outer.y;
	vec2 inner = sphere_hit(ro, rd, cloud_r);
	if (inner.x <= inner.y && inner.y > 0.0) {
		t1 = min(t1, max(inner.x, 0.0));    // stops at the cloud tops
	}
	float depth = texture(depth_tex, SCREEN_UV).r;
	if (depth > 0.0000001) {
		vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		t1 = min(t1, length(v.xyz / v.w));  // and at anything solid in front
	}
	if (t1 <= t0) {
		discard;
	}
	vec3 s = normalize(sun_dir);
	// The ray's lowest point: down to it the haze thickens, after it thins.
	float tm = clamp(-dot(ro, rd), t0, t1);
	vec3 col = vec3(0.0);
	float trans = 1.0;
	march(ro, rd, t0, tm, true, s, col, trans);
	march(ro, rd, tm, t1, false, s, col, trans);
	float a = 1.0 - trans;
	if (a < 0.002) {
		discard;
	}
	ALBEDO = col / a;
	ALPHA = a * clamp(visibility, 0.0, 1.0);
}
