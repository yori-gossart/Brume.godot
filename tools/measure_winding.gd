extends SceneTree
# Ask Godot itself which winding an upward-facing surface uses, instead of
# guessing: read the index order out of a PlaneMesh (which faces +Y) and
# compute the same face normal the physics server would.
func _init() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var a := pm.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	print("PlaneMesh verts: ", v)
	print("PlaneMesh normal[0]: ", n[0])
	print("PlaneMesh indices: ", idx)
	for t in range(0, idx.size(), 3):
		var p0 := v[idx[t]]
		var p1 := v[idx[t + 1]]
		var p2 := v[idx[t + 2]]
		# Godot's Plane(p1,p2,p3): normal = (p1 - p3).cross(p1 - p2)
		var phys := (p0 - p2).cross(p0 - p1).normalized()
		print("  tri %d: %s %s %s  -> physics normal %s" % [t / 3, str(p0), str(p1), str(p2), str(phys)])
	quit()
