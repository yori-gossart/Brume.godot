shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
//
// Fog Nomad benchmark — soft wisp billboard for the Brume's GPUParticles3D.
//
// A procedural soft disc: no texture at all, so the particle budget costs
// bandwidth for nothing but the blend. Particle COLOR carries lifetime alpha
// from the ParticleProcessMaterial's alpha curve.

uniform vec3 wisp_color : source_color = vec3(0.478, 0.439, 0.561);
uniform float softness : hint_range(0.05, 1.0) = 0.85;
uniform float strength : hint_range(0.0, 2.0) = 0.5;

void vertex() {
	// Billboard towards the camera, keeping world up so wisps stay upright.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		MODEL_MATRIX[1],
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, MODEL_MATRIX[1].xyz)), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, r);
	a *= a;
	ALBEDO = wisp_color;
	ALPHA = clamp(a * strength * COLOR.a, 0.0, 1.0);
}
