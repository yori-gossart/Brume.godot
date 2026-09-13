shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
//
// Fog Nomad benchmark — river and pond surface.
//
// Constraint that shapes the whole shader: the Godot MOBILE renderer has no
// screen texture and no depth texture, so the usual "read the depth buffer to
// find water depth" trick is unavailable. Instead the mesh builder bakes the
// real water depth (from TerrainData) into COLOR.r at every vertex, which is
// strictly more accurate than a depth-buffer reconstruction and costs nothing
// at runtime. Shore fade, foam and colour gradient all read from it.
//
// Reflection is an analytic sky gradient rather than a probe or SSR: on a
// phone that is the difference between "water" and "a slideshow".

// A baked tangent-space normal map (assets/materials/noise_water.tres), so
// the ripple normal is two samples rather than six finite differences.
uniform sampler2D wave_tex : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 shallow_col : source_color = vec3(0.259, 0.404, 0.361);
uniform vec3 deep_col    : source_color = vec3(0.055, 0.145, 0.176);
uniform vec3 sky_horizon : source_color = vec3(0.506, 0.557, 0.588);
uniform vec3 sky_zenith  : source_color = vec3(0.286, 0.404, 0.522);
uniform vec3 foam_col    : source_color = vec3(0.796, 0.827, 0.804);

uniform float wave_height   = 0.055;
uniform float wave_speed    = 0.45;
uniform float normal_scale  = 0.09;
uniform float normal_speed  = 0.035;
uniform float depth_falloff = 1.9;
uniform float foam_width    = 0.34;
uniform float alpha_min     = 0.55;
uniform float alpha_max     = 0.93;
uniform float flow_dir      = 1.0;

varying float depth_m;
varying vec3 world_pos;

void vertex() {
	depth_m = COLOR.r;
	// Flatten the swell towards the bank so the mesh never pokes out of the
	// water and leaves a hard seam against the shore.
	float shore = clamp(depth_m / 0.6, 0.0, 1.0);
	float t = TIME * wave_speed;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h =
		  sin(wp.x * 0.55 + t * 1.30) * 0.55
		+ sin(wp.z * 0.47 - t * 1.05) * 0.45
		+ sin((wp.x + wp.z) * 0.23 + t * 0.65) * 0.75
		+ sin((wp.x - wp.z * 1.7) * 0.13 - t * 0.4) * 0.9;
	VERTEX.y += h * wave_height * shore;
	world_pos = wp;
}

void fragment() {
	vec2 uv = world_pos.xz * normal_scale;
	float t = TIME * normal_speed;
	// Two layers drifting at different speeds and angles: one carried
	// downstream, one crosswise. The beat between them is what stops the
	// surface reading as a looping texture.
	vec3 n1 = texture(wave_tex, uv + vec2(t * 1.9 * flow_dir, t * 0.7)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_tex, uv * 2.3 - vec2(t * 1.1, t * 2.4 * flow_dir)).rgb * 2.0 - 1.0;
	// Tangent-space .xy are the surface gradients; the water plane's tangent
	// frame is world XZ, so they drop straight into a world-space normal.
	vec2 grad = (n1.xy * 1.15 + n2.xy * 0.75) * mix(0.35, 1.0, clamp(depth_m / 0.5, 0.0, 1.0));
	vec3 nrm = normalize(vec3(grad.x, 1.0, grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	// --- depth-graded body colour, from the baked depth
	float d = clamp(depth_m / depth_falloff, 0.0, 1.0);
	vec3 body = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, d));

	// --- analytic sky reflection, fresnel-weighted
	vec3 vdir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 refl = reflect(vdir, nrm);
	vec3 sky = mix(sky_horizon, sky_zenith, clamp(refl.y * 1.3, 0.0, 1.0));
	float fres = pow(1.0 - clamp(dot(nrm, -vdir), 0.0, 1.0), 3.0);
	fres = clamp(fres, 0.04, 0.85);
	vec3 col = mix(body, sky, fres);

	// --- foam at the waterline and over anything that nearly breaks surface
	float ripple = texture(wave_tex, uv * 4.1 + vec2(TIME * 0.05, TIME * -0.037)).r;
	// Kept to a narrow line at the waterline. A wide foam band reads as a
	// sand beach, not as water meeting a bank.
	float foam = smoothstep(foam_width, 0.0, depth_m) * (0.25 + ripple * 0.65);
	foam = clamp(foam, 0.0, 1.0);
	col = mix(col, foam_col, foam * 0.6);

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.28, foam);
	SPECULAR = 0.7;
	METALLIC = 0.0;

	// Shallow water is near-transparent so the silt shows through; deep water
	// closes up. Foam is opaque.
	float a = mix(alpha_min, alpha_max, smoothstep(0.0, 1.0, d));
	a = mix(a, 0.0, smoothstep(0.06, 0.0, depth_m));
	ALPHA = clamp(max(a, foam * 0.7), 0.0, 1.0);
}
