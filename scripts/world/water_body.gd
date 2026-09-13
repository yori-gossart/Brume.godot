extends Area3D
class_name WaterBody
##
## The river and the pond: one surface mesh plus one physical volume.
##
## Two things are deliberately separated here.
##
##   * The Area3D is the PHYSICAL gate. The player, the NPC and the animal
##     learn "I am in water" by body_entered / body_exited, exactly as the
##     brief asks (section 18). Its box spans everything below WATER_LEVEL,
##     so a body is inside it precisely when part of it is under the surface.
##
##   * The exact depth comes from TerrainData.water_depth_at(). That is what
##     decides wading vs swimming, and it is the same function the mesh was
##     built from, so the number can never disagree with the picture.
##
## The mesh bakes real depth into COLOR.r per vertex. shaders/water.gdshader
## reads it for shoreline fade, foam and the colour gradient — which is how
## this gets depth-aware water on the mobile renderer, where there is no
## depth texture to sample.

@export var cell_size: float = 1.5
@export var water_material: Material
## Surface mesh is pushed this far below WATER_LEVEL so the analytic waterline
## (depth = 0) lands just inside the bank instead of hovering over it.
@export var surface_bias: float = -0.02

var triangle_count: int = 0

@onready var _mesh_instance := MeshInstance3D.new()


func _ready() -> void:
	_build_volume()
	_build_surface()


func _build_volume() -> void:
	var s := TerrainData.SIZE
	var box := BoxShape3D.new()
	var depth := 12.0
	box.size = Vector3(s * 2.0, depth, s * 2.0)
	var cs := CollisionShape3D.new()
	cs.name = "WaterVolume"
	cs.shape = box
	# Top face sits exactly on the waterline.
	cs.position = Vector3(0.0, TerrainData.WATER_LEVEL - depth * 0.5, 0.0)
	add_child(cs)
	monitoring = true
	monitorable = true


func _build_surface() -> void:
	var size := TerrainData.SIZE
	var cells := int(round((size * 2.0) / cell_size))
	var n := cells + 1

	var depth_grid := PackedFloat32Array()
	depth_grid.resize(n * n)
	for j in n:
		var z := -size + float(j) * cell_size
		for i in n:
			var x := -size + float(i) * cell_size
			depth_grid[j * n + i] = TerrainData.water_depth_at(x, z)

	# Only emit a quad if any of its corners is actually wet. Everything else
	# is dry land and would just be transparent overdraw.
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index_of := {}
	var idxs := PackedInt32Array()

	var y := TerrainData.WATER_LEVEL + surface_bias

	for j in cells:
		for i in cells:
			var corners := [j * n + i, j * n + i + 1, (j + 1) * n + i, (j + 1) * n + i + 1]
			var wet := false
			for c in corners:
				if depth_grid[c] > 0.0:
					wet = true
					break
			if not wet:
				continue
			var ids := []
			for c in corners:
				if not index_of.has(c):
					var ci: int = c % n
					var cj: int = c / n
					var x := -size + float(ci) * cell_size
					var z := -size + float(cj) * cell_size
					index_of[c] = verts.size()
					verts.push_back(Vector3(x, y, z))
					norms.push_back(Vector3.UP)
					uvs.push_back(Vector2(x, z) * 0.05)
					cols.push_back(Color(depth_grid[c], 0.0, 0.0, 1.0))
				ids.push_back(index_of[c])
			# a = i,j   b = i+1,j   c = i,j+1   d = i+1,j+1
			# Upward winding, same convention as the terrain.
			idxs.push_back(ids[0]); idxs.push_back(ids[1]); idxs.push_back(ids[2])
			idxs.push_back(ids[1]); idxs.push_back(ids[3]); idxs.push_back(ids[2])

	if verts.is_empty():
		push_warning("WaterBody: no wet cells found — check TerrainData.WATER_LEVEL")
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	triangle_count = idxs.size() / 3

	_mesh_instance.name = "WaterSurface"
	_mesh_instance.mesh = mesh
	if water_material:
		_mesh_instance.material_override = water_material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_instance)


## Depth of water under a world position, in metres. 0 means dry.
func depth_at(world_xz: Vector3) -> float:
	return TerrainData.water_depth_at(world_xz.x, world_xz.z)
