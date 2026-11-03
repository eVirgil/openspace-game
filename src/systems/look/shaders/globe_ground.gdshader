// The ground under the F11 Map page's globe (GlobeView, GlobeTerrain): each pixel
// of the ball is turned back into a direction from the planet's centre, looked up
// in the baked latitude/longitude texture, tinted by height and rock and lit from
// the screen's top left by its slopes, so the light stays put as the globe turns.
// Zoomed in far enough that the texels show, the light fades and only the height's
// tint is left (bilinear slopes draw a crest as a staircase).
// Off the ball it is clear. Colours and strength: content/look/map.json "terrain".
shader_type canvas_item;

uniform sampler2D ground : filter_linear_mipmap, repeat_enable;
uniform vec2 centre;                       // the ball's centre (px, local)
uniform float radius_px = 100.0;           // the ball's radius on screen
uniform mat3 view;                         // map frame -> screen frame (GlobeView.view())
uniform float slope_max = 0.6;             // GlobeTerrain.SLOPE
uniform float relief = 4.0;                // how much the slopes are lifted for the light
uniform float shade = 0.06;                // how bright the lit side of a slope gets
uniform float texel_px = 1.0;              // a texel's width on screen at the ball's centre
uniform vec2 fade_px = vec2(4.0, 12.0);    // the light fades out as texels grow this big (blocky crests)
uniform vec4 low : source_color;
uniform vec4 high : source_color;
uniform vec4 rock : source_color;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 q = (local - centre) / radius_px;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 s = vec3(q.x, -q.y, sqrt(1.0 - r2));          // screen: x right, y up, z out
		vec3 d = normalize(transpose(view) * s);           // the map frame (view is a rotation)
		float lon = atan(d.x, d.z);
		float lat = asin(clamp(d.y, -1.0, 1.0));
		vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
		// the seam where longitude wraps would read as a huge step: take it out
		vec2 ux = dFdx(uv);
		vec2 uy = dFdy(uv);
		ux.x -= round(ux.x);
		uy.x -= round(uy.x);
		vec4 g = textureGrad(ground, uv, ux, uy);
		vec3 east = vec3(cos(lon), 0.0, -sin(lon));
		vec3 north = vec3(-sin(lat) * sin(lon), cos(lat), -sin(lat) * cos(lon));
		vec2 slope = (g.rg * 2.0 - 1.0) * slope_max;
		vec3 n = normalize(d - (east * slope.x + north * slope.y) * relief);
		vec3 light = normalize(vec3(-1.0, 1.0, 1.2));
		float lit = dot(view * n, light) - dot(s, light);  // the slope's light, not the ball's
		vec3 c = mix(low.rgb, high.rgb, g.b);
		c = mix(c, rock.rgb, g.a * rock.a);
		COLOR = vec4(max(c + lit * shade * (1.0 - smoothstep(fade_px.x, fade_px.y, texel_px)), vec3(0.0)), 1.0);
	}
}
