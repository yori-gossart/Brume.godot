shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
//
// Fog Nomad benchmark — the Brume, ground layer ("nappes basses").
//
// A near-horizontal sheet that follows the terrain a little above it. Its job
// is section 31: make the Brume look like it is EATING the ground rather than
// standing on it. It does that by being densest exactly where the curtain
// meets the terrain, and by darkening what is underneath instead of only
// adding light on top.

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform vec3 sheet_color : source_color = vec3(0.294, 0.259, 0.373);
uniform vec3 dark_color  : source_color = vec3(0.071, 0.063, 0.106);

// Same calibration note as fog_wall.gdshader: the noise map means 0.455, so
// `density` has to be above 1 for the erosion threshold to bite at all.
uniform float density     : hint_range(0.0, 4.0) = 1.55;
uniform float erosion     : hint_range(0.0, 1.0) = 0.42;
uniform float uv_scale    = 0.021;
uniform float scroll      = 0.0055;
uniform float darkening   : hint_range(0.0, 1.0) = 0.6;
uniform float front_world_z = 0.0;   // set by FogWall: where the curtain front is
uniform float reach         = 46.0;  // how far the sheet creeps out from it
uniform float view_fade     = 2.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * uv_scale;
	float t = TIME * scroll;
	float a = texture(noise_tex, uv + vec2(t, t * 0.4)).r;
	float b = texture(noise_tex, uv * 2.9 - vec2(t * 1.7, t * 0.9)).r;
	float c = texture(noise_tex, uv * 0.47 + vec2(t * 0.3, -t * 0.6)).r;
	// Weighted towards the two coarse octaves, then stretched away from the
	// mean: a flat 0.45-ish field makes the sheet read as a painted slab
	// lying across the landscape instead of as fog.
	float d = a * 0.44 + b * 0.24 + c * 0.32;
	d = clamp((d - 0.455) * 1.75 + 0.455, 0.0, 1.0);

	// Thickest against the curtain, thinning as it creeps into open ground.
	float toward = clamp((world_pos.z - front_world_z) / reach + 1.0, 0.0, 1.0);
	float creep = smoothstep(0.0, 1.0, toward);

	float alpha = smoothstep(erosion, erosion + 0.45, d * density * creep);

	// Looking along the sheet gives a thicker optical path than looking
	// straight down at it — cheap, and it is what sells a low-lying layer.
	vec3 vdir = normalize(world_pos - CAMERA_POSITION_WORLD);
	float grazing = 1.0 - clamp(abs(vdir.y), 0.0, 1.0);
	alpha *= mix(0.35, 1.0, pow(grazing, view_fade));

	vec3 col = mix(sheet_color, dark_color, smoothstep(0.35, 0.9, b) * darkening);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
