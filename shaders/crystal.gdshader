shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
//
// Fog Nomad benchmark — the beacon crystal.
//
// A lit, faceted, self-emitting solid. The pulse is driven from GDScript
// (scripts/world/beacon_tower.gd) through `pulse`, so the crystal, the
// OmniLight3D and the ring glow all breathe on exactly the same clock.

uniform vec3 body_color  : source_color = vec3(0.259, 0.694, 0.694);
uniform vec3 glow_color  : source_color = vec3(0.549, 0.949, 0.878);
uniform float pulse      : hint_range(0.0, 1.0) = 0.5;
uniform float emission_lo = 1.1;
uniform float emission_hi = 3.6;
uniform float fresnel_pow = 2.2;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_pow);
	vec3 col = mix(body_color, glow_color, fres * 0.8 + pulse * 0.25);
	ALBEDO = col;
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = 1.0;
	EMISSION = mix(body_color, glow_color, 0.6) * mix(emission_lo, emission_hi, pulse) * (0.55 + fres * 0.75);
}
