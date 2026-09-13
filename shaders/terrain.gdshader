shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
//
// Fog Nomad benchmark — terrain surface.
//
// Deliberately texture-light: one small tiling noise map drives every break-up
// pattern, and the rest is analytic. On a Mobile-renderer phone this is far
// cheaper than a four-layer splat map, and it avoids shipping 4K textures the
// brief explicitly said we do not need (section 16).
//
// It reads NO screen texture and NO depth texture, because the Godot Mobile
// renderer does not support screen-reading shaders. Everything here is
// forward-safe.
//
// Vertex colours are baked by scripts/world/terrain_builder.gd:
//   COLOR.r = path influence   (1 on the trodden path)
//   COLOR.g = shore wetness    (1 right at the waterline, 0 inland)
//   COLOR.b = macro variation  (slow large-scale colour drift)

uniform sampler2D noise_tex : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform vec3 grass_a    : source_color = vec3(0.208, 0.290, 0.157);
uniform vec3 grass_b    : source_color = vec3(0.298, 0.365, 0.192);
uniform vec3 dry_grass  : source_color = vec3(0.396, 0.404, 0.216);
uniform vec3 dirt_col   : source_color = vec3(0.278, 0.224, 0.157);
uniform vec3 path_col   : source_color = vec3(0.345, 0.294, 0.216);
uniform vec3 rock_col   : source_color = vec3(0.322, 0.318, 0.310);
uniform vec3 silt_col   : source_color = vec3(0.243, 0.239, 0.184);

// The noise map (assets/materials/noise_soft.tres) was measured, not assumed:
// red channel min 0.00, MEAN 0.455, max 0.93. Every threshold below sits
// inside that range on purpose. Thresholds picked for an idealised 0..1
// uniform noise sit above the mean and produce a flat green field.
uniform float macro_scale  = 0.011;
uniform float detail_scale = 0.135;
uniform float fine_scale   = 0.42;
uniform float slope_start  = 0.72;
uniform float slope_end    = 0.93;
uniform float rough_grass  = 0.95;
uniform float rough_rock   = 0.68;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float macro  = texture(noise_tex, world_pos.xz * macro_scale).r;
	float detail = texture(noise_tex, world_pos.xz * detail_scale).r;
	float fine   = texture(noise_tex, world_pos.xz * fine_scale + vec2(0.37, 0.81)).r;

	// --- base grass, broken up at two scales so it never reads as flat paint
	float mix_a = smoothstep(0.26, 0.70, macro * 0.6 + detail * 0.4)
		* 0.75 + COLOR.b * 0.25;
	vec3 albedo = mix(grass_a, grass_b, clamp(mix_a, 0.0, 1.0));

	// --- broad sun-bleached patches, at the largest scale only
	albedo = mix(albedo, dry_grass, smoothstep(0.48, 0.80, macro) * 0.9);

	// --- bare earth showing through where the cover thins out
	albedo = mix(albedo, dirt_col,
		smoothstep(0.34, 0.10, detail * 0.6 + fine * 0.4) * 0.65);

	// --- rock takes over on slope
	float slope = 1.0 - clamp(world_nrm.y, 0.0, 1.0);
	float rockiness = smoothstep(1.0 - slope_end, 1.0 - slope_start, slope);
	vec3 rock = mix(rock_col, rock_col * 0.78, fine);
	albedo = mix(albedo, rock, rockiness);

	// --- the trodden path
	float path = clamp(COLOR.r * (0.72 + detail * 0.55), 0.0, 1.0);
	albedo = mix(albedo, path_col * (0.85 + fine * 0.3), path * 0.88);

	// --- shore: silt, then darker and wetter right at the waterline
	float shore = clamp(COLOR.g, 0.0, 1.0);
	albedo = mix(albedo, silt_col, smoothstep(0.25, 0.85, shore));
	float wet = smoothstep(0.62, 1.0, shore);
	albedo *= mix(1.0, 0.62, wet);

	ALBEDO = albedo;
	ROUGHNESS = mix(mix(rough_grass, rough_rock, rockiness), 0.35, wet);
	SPECULAR = mix(0.18, 0.45, wet);

	// A touch of macro ambient occlusion in the hollows, so the relief reads
	// on a small portrait screen even when the sun is low.
	AO = clamp(0.70 + macro * 0.55, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.55;
}
