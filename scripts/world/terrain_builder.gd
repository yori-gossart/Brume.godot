extends StaticBody3D
class_name TerrainBuilder
##
## Builds the benchmark terrain: one welded mesh plus one matching collision
## shape, both derived from the same TerrainData formula, so what you see is
## exactly what you walk on.
##
## Why build it in code instead of shipping a .tscn full of vertices:
##   * a 40 000-vertex mesh resource is not something you can open, read or
##     fix from a phone, and the whole point of this benchmark is whether the
##     phone workflow holds up;
##   * the scatterer, the navmesh, the water and the player all need the same
##     height function anyway, so the mesh may as well come from it too.
##
## This is a FIXED surface. No seed, no chunks, no streaming (section 37).

## Metres between terrain vertices. 2.0 gives 141 x 141 vertices over the
## 280 m square: ~39 200 triangles in a single draw call.
@export var cell_size: float = 2.0

@export var terrain_material: Material

var _cells: int
var _verts_per_side: int
var _heights: PackedFloat32Array
var build_ms: float = 0.0
var triangle_count: int = 0


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	_build()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _build() -> void:
	var size := TerrainData.SIZE
	_cells = int(round((size * 2.0) / cell_size))
	_verts_per_side = _cells + 1
	var n := _verts_per_side

	# --- pass 1: sample the height field once per vertex ------------------
	_heights = PackedFloat32Array()
	_heights.resize(n * n)
	for j in n:
		var z := -size + float(j) * cell_size
		for i in n:
			var x := -size + float(i) * cell_size
			_heights[j * n + i] = TerrainData.height_at(x, z)

	# --- pass 2: vertices, normals and the baked shading attributes -------
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	var uvs := PackedVector2Array(); uvs.resize(n * n)

	for j in n:
		var z := -size + float(j) * cell_size
		for i in n:
			var idx := j * n + i
			var x := -size + float(i) * cell_size
			var h := _heights[idx]
			verts[idx] = Vector3(x, h, z)
			norms[idx] = _grid_normal(i, j)
			uvs[idx] = Vector2(x, z) * 0.02
			# r = path, g = shore wetness, b = macro colour drift
			var path := TerrainData.path_influence(x, z)
			var above := h - TerrainData.WATER_LEVEL
			var shore := clampf(1.0 - above / 1.6, 0.0, 1.0)
			if above < 0.0:
				shore = 1.0
			var macro := 0.5 + 0.5 * sin(x * 0.0163 + 1.1) * cos(z * 0.0139 - 0.4)
			cols[idx] = Color(path, shore, macro, 1.0)

	# --- pass 3: indices --------------------------------------------------
	var idxs := PackedInt32Array()
	idxs.resize(_cells * _cells * 6)
	var w := 0
	for j in _cells:
		for i in _cells:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Winding matters twice over: it decides which way the surface
			# is culled when drawn, AND which way ConcavePolygonShape3D
			# thinks the ground faces. Getting it backwards gives an
			# invisible terrain you also fall through. The order below is
			# the one Godot's own PlaneMesh uses for an upward surface
			# (verified in tools/measure_winding.gd).
			idxs[w] = a; idxs[w + 1] = b; idxs[w + 2] = c; w += 3
			idxs[w] = b; idxs[w + 1] = d; idxs[w + 2] = c; w += 3

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

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	if terrain_material:
		mi.material_override = terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The terrain is one huge AABB; without this Godot re-sorts it oddly
	# against the transparent water and fog.
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)

	# --- collision: the same triangles, nothing approximated --------------
	var faces := PackedVector3Array()
	faces.resize(idxs.size())
	for k in idxs.size():
		faces[k] = verts[idxs[k]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "TerrainCollision"
	cs.shape = shape
	add_child(cs)
	# The ground's default surface. The path and the water override it
	# analytically in PlayerController.current_surface(), because a single
	# terrain collider cannot express "this bit is a trodden path".
	SurfaceType.tag(self, SurfaceType.Kind.GRASS)


func _grid_normal(i: int, j: int) -> Vector3:
	var n := _verts_per_side
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, n - 1)
	var jd := maxi(j - 1, 0)
	var ju := mini(j + 1, n - 1)
	var dx := (ir - il) * cell_size
	var dz := (ju - jd) * cell_size
	var hl := _heights[j * n + il]
	var hr := _heights[j * n + ir]
	var hd := _heights[jd * n + i]
	var hu := _heights[ju * n + i]
	return Vector3((hl - hr) * dz, dx * dz, (hd - hu) * dx).normalized()
