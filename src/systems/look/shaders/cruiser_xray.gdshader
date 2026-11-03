// The F11 map's cruiser cutaway (CruiserMapView): the hull, the walls and the trim
// drawn as light, not as metal, so the decks, ramps and rooms inside show through.
// Added on, never hiding anything: a faint fill where a plate faces you, brighter
// where it turns edge-on, which outlines the hull and every wall.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.6, 0.3, 1.0);
uniform float fill = 0.05;                 // a plate seen face on
uniform float rim = 0.55;                  // a plate seen edge on

void fragment() {
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint.rgb * (fill + rim * pow(edge, 3.0));
}
