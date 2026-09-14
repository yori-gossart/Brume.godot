shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
//
// Fog Nomad — character recolouring.
//
// WHY THIS EXISTS. Section 7 says green must stop being the player's default
// colour, and section 8 wants skin tone and two outfit colours to be real,
// stored properties. The imposed Quaternius modular outfits — which would
// give that for free by swapping meshes — could not be downloaded. What we
// do have is a set of CC0 characters that each share one 1024 atlas.
//
// So the recolour happens in the shader, per material instance, by HUE BAND.
// Not a global tint: a global tint stains the skin and the leather along
// with the cloth and makes everyone look dipped in paint.
//
// It works because the atlas is a flat palette with well-separated clusters.
// Measured on player_hooded_scout (see the report):
//
//     skin      H 21-26 deg   S 0.31-0.53   V 0.78-0.97
//     leather   H 12-19 deg   S 0.54-0.65   V 0.49-0.70
//     steel     H ~200 deg    S 0.11
//     HOOD      H 148 deg     S 0.89        V 0.51   <- a lone cluster
//
// Nothing else in the atlas is anywhere near 148 degrees at that saturation,
// so a band centred there repaints the hood and the cape and touches
// nothing else. Skin and leather overlap in hue and are separated by VALUE
// instead, which is why the skin band carries a brightness floor.
//
// Each band keeps the source pixel's shading (its value relative to the
// band's reference) and substitutes the hue and saturation, so folds and
// creases survive the recolour instead of flattening into a silhouette.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;

// --- outfit primary ------------------------------------------------------
uniform vec3  primary_color   : source_color = vec3(0.62, 0.44, 0.22);
uniform float primary_hue     : hint_range(0.0, 1.0) = 0.411;  // 148 deg
uniform float primary_width   : hint_range(0.0, 0.5) = 0.075;
uniform float primary_min_sat : hint_range(0.0, 1.0) = 0.45;
// Brightness floor. Some atlases put the outfit colour at a hue that also
// contains leather; where that happens the two are separated by value, not
// by hue, and this is the knife.
uniform float primary_min_val : hint_range(0.0, 1.0) = 0.0;
uniform float primary_strength: hint_range(0.0, 1.0) = 1.0;

// --- outfit secondary / trim --------------------------------------------
uniform vec3  secondary_color   : source_color = vec3(0.45, 0.40, 0.34);
uniform float secondary_hue     : hint_range(0.0, 1.0) = 0.189;  // 68 deg
uniform float secondary_width   : hint_range(0.0, 0.5) = 0.055;
uniform float secondary_min_sat : hint_range(0.0, 1.0) = 0.40;
uniform float secondary_min_val : hint_range(0.0, 1.0) = 0.0;
uniform float secondary_strength: hint_range(0.0, 1.0) = 1.0;

// --- skin ----------------------------------------------------------------
uniform vec3  skin_color    : source_color = vec3(0.96, 0.75, 0.61);
uniform float skin_hue      : hint_range(0.0, 1.0) = 0.065;   // 23 deg
uniform float skin_width    : hint_range(0.0, 0.5) = 0.035;
uniform float skin_min_val  : hint_range(0.0, 1.0) = 0.72;
uniform float skin_max_sat  : hint_range(0.0, 1.0) = 0.60;
uniform float skin_strength : hint_range(0.0, 1.0) = 1.0;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Shortest distance between two hues on the colour wheel.
float hue_dist(float a, float b) {
	float d = abs(a - b);
	return min(d, 1.0 - d);
}

// Replace a band's hue and saturation while preserving its shading.
// `ref_v` is the band's representative brightness; pixels darker or lighter
// than it stay darker or lighter after the swap.
vec3 remap(vec3 hsv, vec3 target_rgb, float amount, float ref_v) {
	vec3 t = rgb2hsv(target_rgb);
	float shade = hsv.z / max(ref_v, 0.001);
	vec3 out_hsv = vec3(t.x, t.y, clamp(t.z * shade, 0.0, 1.0));
	return mix(hsv2rgb(hsv), hsv2rgb(out_hsv), amount);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 hsv = rgb2hsv(tex.rgb);
	vec3 col = tex.rgb;

	// --- skin: separated from leather by BRIGHTNESS, not hue -------------
	float skin_mask = 1.0 - smoothstep(skin_width * 0.6, skin_width, hue_dist(hsv.x, skin_hue));
	skin_mask *= smoothstep(skin_min_val - 0.06, skin_min_val + 0.04, hsv.z);
	skin_mask *= 1.0 - smoothstep(skin_max_sat, skin_max_sat + 0.12, hsv.y);
	col = mix(col, remap(hsv, skin_color, 1.0, 0.90), skin_mask * skin_strength);

	// --- outfit primary ---------------------------------------------------
	float p_mask = 1.0 - smoothstep(primary_width * 0.6, primary_width, hue_dist(hsv.x, primary_hue));
	p_mask *= smoothstep(primary_min_sat - 0.12, primary_min_sat, hsv.y);
	p_mask *= smoothstep(primary_min_val - 0.08, primary_min_val + 0.02, hsv.z);
	col = mix(col, remap(rgb2hsv(col), primary_color, 1.0, 0.55), p_mask * primary_strength);

	// --- outfit secondary -------------------------------------------------
	float s_mask = 1.0 - smoothstep(secondary_width * 0.6, secondary_width, hue_dist(hsv.x, secondary_hue));
	s_mask *= smoothstep(secondary_min_sat - 0.12, secondary_min_sat, hsv.y);
	s_mask *= smoothstep(secondary_min_val - 0.08, secondary_min_val + 0.02, hsv.z);
	col = mix(col, remap(rgb2hsv(col), secondary_color, 1.0, 0.70), s_mask * secondary_strength);

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
