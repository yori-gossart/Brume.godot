shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
//
// Fog Nomad benchmark — the Brume, curtain layer.
//
// Everything here exists to answer one objection from the three.js version:
// "technically more complex but visually the same". The fix is that the
// irregularity lives at FOUR different scales, and no single one of them can
// be switched off and leave a rectangle behind:
//
//   1. the curtain's plan-view meander        (mesh, FogWall builder)
//   2. the ragged top edge of the mesh         (mesh, per-vertex)
//   3. per-vertex silhouette bite              (COLOR.r, read here)
//   4. two-octave scrolling noise erosion      (this shader)
//
// Plus a cheap 3-step parallax march along the view ray, which is what makes
// it read as a VOLUME you are looking into rather than a printed curtain.
//
// MOBILE CONSTRAINTS HONOURED:
//   * no SCREEN_TEXTURE, no DEPTH_TEXTURE   (unsupported by the mobile renderer)
//   * no volumetric fog                     (Forward+ only)
//   * unshaded: the Brume lights itself, so it costs no light loops
//   * 5 texture samples per pixel, worst case

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform vec3 core_color  : source_color = vec3(0.239, 0.200, 0.325);
uniform vec3 edge_color  : source_color = vec3(0.478, 0.447, 0.549);
uniform vec3 deep_color  : source_color = vec3(0.071, 0.055, 0.114);

// CALIBRATION. The noise map's red channel has mean 0.455 (measured, see
// tools/measure_noise.gd). The per-vertex bite averages 0.62. So the raw
// density term lands around 0.28, and `density` has to lift that into a
// range the erosion threshold can actually cut — which is why it is well
// above 1. Tuned by eye against real renders, not guessed.
uniform float density        : hint_range(0.0, 6.0) = 2.4;
uniform float erosion        : hint_range(0.0, 1.0) = 0.42;
uniform float edge_soft      : hint_range(0.05, 1.0) = 0.50;
uniform float top_falloff    : hint_range(0.1, 4.0) = 1.35;
uniform float base_solid     : hint_range(0.0, 1.0) = 0.42;
uniform float scroll_a       = 0.0130;
uniform float scroll_b       = -0.0072;
uniform float uv_scale_a     = 1.0;
uniform float uv_scale_b     = 2.7;
uniform float layer_phase    = 0.0;
uniform float parallax       : hint_range(0.0, 0.5) = 0.13;
uniform float interior_dark  : hint_range(0.0, 1.0) = 0.55;
uniform float rim_light      : hint_range(0.0, 2.0) = 0.3;
uniform float fade_near      = 3.0;
uniform float fade_far       = 190.0;

varying vec3 world_pos;
varying vec3 local_pos;
varying float vbite;

float fog_noise(vec2 uv) {
	float a = texture(noise_tex, uv * uv_scale_a + vec2(TIME * scroll_a, TIME * scroll_a * 0.31 + layer_phase)).r;
	float b = texture(noise_tex, uv * uv_scale_b + vec2(TIME * scroll_b - layer_phase, TIME * scroll_b * 0.7)).r;
	return a * 0.66 + b * 0.34;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
	vbite = COLOR.r;
}

void fragment() {
	// View ray in tangent-ish space. The curtain is roughly vertical, so
	// offsetting UV by the view's horizontal component is a good enough
	// parallax for three steps.
	vec3 vdir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec2 off = vec2(vdir.x, vdir.z) * parallax;

	float d = 0.0;
	d += fog_noise(UV) * 0.50;
	d += fog_noise(UV + off * 0.55) * 0.31;
	d += fog_noise(UV + off * 1.15) * 0.19;

	// Height profile: solid at the ground, feathering out at the top.
	float hgt = clamp(UV.y, 0.0, 1.0);
	float profile = 1.0 - pow(hgt, top_falloff);

	// Per-vertex silhouette bite, baked by the builder. This is what keeps
	// the front from ever being a straight line.
	float bite = clamp(vbite, 0.0, 1.0);
	// ...except right at the ground, where the Brume is solid whatever the
	// silhouette is doing above it (section 31).
	float ground = 1.0 - smoothstep(0.0, 0.22, hgt);
	bite = mix(bite, 1.0, ground * base_solid);

	// Erode: threshold the density field, then remap. That turns a soft
	// gradient into torn, wispy edges instead of an airbrushed band.
	float alpha = smoothstep(erosion, erosion + edge_soft, d * bite * profile * density);

	// --- colour: bright where thin, dark and cold in the depths
	float thin = 1.0 - clamp(d * 1.25, 0.0, 1.0);
	vec3 col = mix(core_color, edge_color, thin * 0.85);
	// Interior darkening: a slow, low-frequency band that drifts sideways.
	// Occasionally it condenses enough to read as *something* in there,
	// which is as far as the brief wants this to go (section 32).
	float inner = texture(noise_tex, UV * 0.33 + vec2(TIME * 0.0041, TIME * -0.0016)).r;
	float shade = smoothstep(0.42, 0.86, inner);
	col = mix(col, deep_color, shade * interior_dark * clamp(d * 1.4, 0.0, 1.0));

	// A faint bloom along the torn edge, so the silhouette stays legible
	// against a dark sky on a small portrait screen.
	col += edge_color * rim_light * pow(clamp(1.0 - alpha, 0.0, 1.0), 4.0) * alpha;

	// Do not slap the camera in the face, and do not pop in at the far plane.
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	alpha *= smoothstep(0.0, fade_near, dist);
	alpha *= 1.0 - smoothstep(fade_far * 0.75, fade_far, dist);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
