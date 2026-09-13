extends Node3D
class_name FogWall
##
## The Brume (sections 29-32). This is the main visual test.
##
## Constraint first: the MOBILE renderer has no volumetric fog (Forward+
## only), no screen texture and no depth texture. So none of the usual
## answers are available, and the Brume has to be built out of geometry,
## alpha and a noise texture.
##
## It is assembled from four things that fail differently, so that no single
## one of them can collapse it back into "a purple plane":
##
##   1. CURTAIN LAYERS. Three (two on LOW) generated mesh curtains at
##      different distances, each following a different meander and scrolling
##      at a different rate. Parallax between them is what gives depth.
##   2. A RAGGED SILHOUETTE at three scales: the curtain's plan-view meander,
##      the height of its top edge, and a per-vertex "bite" in COLOR.r that
##      the shader erodes against. Section 30 asks for exactly this.
##   3. GROUND SHEETS that follow the terrain height, densest at the contact
##      line, darkening what is under them — so the Brume reads as eating the
##      ground rather than standing on it (section 31).
##   4. WISPS: a modest GPUParticles3D emitter along the contact line.
##
## Everything scales with the Quality preset.

signal front_moved(base_z: float)

@export var base_z: float = 92.0
@export var half_length: float = 172.0
@export var segments: int = 150
@export var layer_spacing: float = 7.0
@export var wall_height: float = 27.0
@export var sink: float = 2.5
@export var noise: Texture2D
@export var wisp_amount_high: int = 90

var _layers: Array[MeshInstance3D] = []
var _sheets: Array[MeshInstance3D] = []
var _particles: GPUParticles3D


func _ready() -> void:
	for i in 3:
		_layers.append(_make_layer(i))
	_sheets.append(_make_sheet(0))
	_sheets.append(_make_sheet(1))
	_make_wisps()
	Quality.changed.connect(_on_quality)
	_on_quality(Quality.level)
	front_moved.emit(base_z)


## Plan-view meander of the front. Three frequencies so no single sine is
## recognisable, plus a per-layer phase so the layers never line up.
func front_z(x: float, layer: int = 0) -> float:
	var ph := float(layer) * 0.7
	return (base_z
		+ float(layer) * layer_spacing
		+ 14.0 * sin(x * 0.0171 + ph)
		+ 7.0 * sin(x * 0.0413 + 1.3 + ph * 1.7)
		+ 3.2 * sin(x * 0.0907 + 0.4 - ph))


func _top_height(x: float, layer: int) -> float:
	var ph := float(layer) * 1.9
	return wall_height * (1.0
		+ 0.30 * sin(x * 0.0504 + ph)
		+ 0.15 * sin(x * 0.1310 + 2.1 - ph)
		+ 0.08 * sin(x * 0.2700 + 0.9))


func _bite(x: float, layer: int) -> float:
	var ph := float(layer) * 2.7
	var b := (0.62
		+ 0.24 * sin(x * 0.0630 + ph)
		+ 0.14 * sin(x * 0.1490 + 1.7 + ph)
		+ 0.09 * sin(x * 0.3310 + 0.3))
	return clampf(b, 0.12, 1.0)


func _make_layer(layer: int) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	var run := 0.0
	var prev := Vector2.ZERO

	for i in segments + 1:
		var t := float(i) / float(segments)
		var x := lerpf(-half_length, half_length, t)
		var z := front_z(x, layer)
		if i > 0:
			run += Vector2(x, z).distance_to(prev)
		prev = Vector2(x, z)
		var g := TerrainData.height_at(x, z)
		var top := g + _top_height(x, layer)
		var u := run / 46.0
		verts.push_back(Vector3(x, g - sink, z))
		uvs.push_back(Vector2(u, 0.0))
		cols.push_back(Color(_bite(x, layer), 0, 0, 1))
		verts.push_back(Vector3(x, top, z))
		uvs.push_back(Vector2(u, 1.0))
		cols.push_back(Color(_bite(x, layer), 0, 0, 1))

	for i in segments:
		var a := i * 2
		idxs.push_back(a); idxs.push_back(a + 1); idxs.push_back(a + 2)
		idxs.push_back(a + 2); idxs.push_back(a + 1); idxs.push_back(a + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog_wall.gdshader")
	mat.set_shader_parameter("noise_tex", noise)
	# Each layer is tuned apart: the near one is thin and fast and lets the
	# far ones show through, the far ones are dense, slow and darker.
	var near := 1.0 - float(layer) / 2.0
	mat.set_shader_parameter("density", lerpf(3.1, 2.15, near))
	mat.set_shader_parameter("erosion", lerpf(0.34, 0.46, near))
	mat.set_shader_parameter("edge_soft", lerpf(0.40, 0.56, near))
	mat.set_shader_parameter("uv_scale_a", lerpf(0.85, 1.25, near))
	mat.set_shader_parameter("uv_scale_b", lerpf(2.1, 3.4, near))
	mat.set_shader_parameter("scroll_a", 0.0092 + 0.0055 * near)
	mat.set_shader_parameter("scroll_b", -0.0048 - 0.0041 * near)
	mat.set_shader_parameter("layer_phase", float(layer) * 0.37)
	mat.set_shader_parameter("parallax", 0.07 + 0.07 * near)
	mat.set_shader_parameter("top_falloff", lerpf(1.15, 1.6, near))
	mat.set_shader_parameter("interior_dark", lerpf(0.82, 0.55, near))
	mat.set_shader_parameter("rim_light", lerpf(0.14, 0.38, near))
	mat.set_shader_parameter("core_color", Color(0.239, 0.200, 0.325).lerp(Color(0.145, 0.125, 0.220), 1.0 - near))

	var mi := MeshInstance3D.new()
	mi.name = "Curtain%d" % layer
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Far layers draw first, so the alpha stacks in the right order without
	# any depth sorting help.
	mi.sorting_offset = -float(layer) * 2.0
	add_child(mi)
	return mi


## A sheet that follows the terrain a little above it. `band` 0 hugs the
## contact line; band 1 creeps further out into open ground.
func _make_sheet(band: int) -> MeshInstance3D:
	var cell := 6.0
	var z_from := base_z - (44.0 if band == 0 else 14.0)
	var z_to := base_z + (34.0 if band == 0 else 26.0)
	var lift := 0.35 if band == 0 else 1.5
	var nx := int((half_length * 2.0) / cell)
	var nz := int((z_to - z_from) / cell)

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idxs := PackedInt32Array()
	for j in nz + 1:
		var z := z_from + float(j) * cell
		for i in nx + 1:
			var x := -half_length + float(i) * cell
			var y := TerrainData.height_at(x, z) + lift + sin(x * 0.07 + z * 0.05) * 0.35
			verts.push_back(Vector3(x, y, z))
			uvs.push_back(Vector2(x, z) * 0.01)
	var w := nx + 1
	for j in nz:
		for i in nx:
			var a := j * w + i
			# cull_disabled makes this cosmetic, but keep one convention.
			idxs.push_back(a); idxs.push_back(a + 1); idxs.push_back(a + w)
			idxs.push_back(a + 1); idxs.push_back(a + w + 1); idxs.push_back(a + w)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog_ground.gdshader")
	mat.set_shader_parameter("noise_tex", noise)
	mat.set_shader_parameter("front_world_z", base_z)
	mat.set_shader_parameter("density", 1.55 if band == 0 else 1.05)
	mat.set_shader_parameter("erosion", 0.46 if band == 0 else 0.52)
	mat.set_shader_parameter("reach", 46.0 if band == 0 else 30.0)
	mat.set_shader_parameter("uv_scale", 0.021 if band == 0 else 0.014)
	mat.set_shader_parameter("scroll", 0.0055 if band == 0 else 0.0034)
	mat.set_shader_parameter("darkening", 0.78 if band == 0 else 0.55)

	var mi := MeshInstance3D.new()
	mi.name = "GroundSheet%d" % band
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.sorting_offset = 3.0 - float(band)
	add_child(mi)
	return mi


## Small wisps rising off the contact line. Kept modest on purpose: particles
## are the first thing to cost frames on a phone, and the brief asks for
## "GPUParticles3D raisonnables".
func _make_wisps() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(5.5, 4.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog_particle.gdshader")
	mat.set_shader_parameter("strength", 0.42)

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(half_length * 0.92, 1.2, 18.0)
	proc.direction = Vector3(0, 1, -0.25)
	proc.spread = 24.0
	proc.initial_velocity_min = 0.25
	proc.initial_velocity_max = 1.1
	proc.gravity = Vector3(0.35, 0.12, 0.0)
	proc.damping_min = 0.1
	proc.damping_max = 0.4
	proc.scale_min = 0.7
	proc.scale_max = 2.4
	proc.angle_min = -25.0
	proc.angle_max = 25.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	proc.alpha_curve = ct

	_particles = GPUParticles3D.new()
	_particles.name = "Wisps"
	_particles.draw_pass_1 = quad
	_particles.material_override = mat
	_particles.process_material = proc
	_particles.amount = wisp_amount_high
	_particles.lifetime = 9.0
	_particles.preprocess = 6.0
	_particles.position = Vector3(0, 0, base_z - 6.0)
	# The emitter box is huge; tell Godot so it does not cull the whole thing
	# the moment its origin leaves the frustum.
	_particles.visibility_aabb = AABB(
		Vector3(-half_length, -8.0, -40.0), Vector3(half_length * 2.0, 42.0, 80.0))
	add_child(_particles)
	# Sit the emitter on the terrain along the front.
	_particles.position.y = TerrainData.height_at(0.0, base_z)


func _on_quality(_level: int) -> void:
	var want := Quality.fog_layers()
	for i in _layers.size():
		_layers[i].visible = i < want
	_sheets[1].visible = not Quality.is_low()
	var amount := int(wisp_amount_high * Quality.particle_ratio())
	if _particles.amount != amount:
		_particles.amount = maxi(amount, 8)
		_particles.restart()


## Signed distance from a world point to the fog front, in metres.
## Positive = still in the clear. Negative = inside the Brume.
func distance_to(point: Vector3) -> float:
	return front_z(point.x, 0) - point.z


func is_inside(point: Vector3) -> bool:
	return distance_to(point) <= 0.0
