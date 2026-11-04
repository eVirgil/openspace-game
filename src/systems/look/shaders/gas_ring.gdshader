shader_type spatial;
// The ringed giant's ring as a real flat band (a PlaneMesh in the ring's plane),
// with the painting's bands, gap, edges and the planet's shadow
// (desert_sky.gdshader). Not solid: a look only.
render_mode unshaded, fog_disabled, cull_disabled, blend_mix, depth_draw_never;

uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec4 ring_color : source_color = vec4(0.9, 0.82, 0.72, 1.0);
uniform vec3 center = vec3(0.0);
uniform float radius = 1000.0;
uniform float inner = 1.35;
uniform float outer = 2.5;
uniform float visibility = 1.0;

varying vec3 local;
varying vec3 wpos;

void vertex() {
	local = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(local.xz) / radius;
	if (dist < inner || dist > outer) {
		discard;
	}
	float k = (dist - inner) / (outer - inner);
	float bands = 0.55 + 0.45 * sin(k * 60.0) * sin(k * 17.0 + 1.3);
	float gap = smoothstep(0.02, 0.05, abs(k - 0.62));
	float edge = smoothstep(0.0, 0.06, k) * smoothstep(1.0, 0.85, k);
	vec3 s = normalize(sun_dir);
	float bs = dot(s, center - wpos);
	float shadow = 1.0;
	if (bs > 0.0) {
		float dd = length(center - wpos - s * bs);
		shadow = smoothstep(radius * 0.9, radius * 1.05, dd);
	}
	ALBEDO = ring_color.rgb * (0.25 + 0.85 * shadow);
	ALPHA = bands * gap * edge * 0.8 * clamp(visibility, 0.0, 1.0);
}
