extends RefCounted
class_name BuildKit
##
## Small helper for assembling the hand-built structures (the scout cabin and
## the beacon tower) out of Godot primitives with matching collision.
##
## These two buildings are NOT imported models. KayKit's packs have no cabin
## and no tower, and section 22 says the benchmark does not need final
## architecture — what it needs is walls, a material read, a door you walk
## through and collision that stops you. Building them from boxes keeps the
## licence story trivial and keeps the whole thing editable from a phone.

## Add a box with a matching BoxShape3D on `body`. `size` is full extent.
static func box(parent: Node3D, body: StaticBody3D, mat: Material,
		pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO,
		solid: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if solid and body != null:
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos
		cs.rotation = rot
		body.add_child(cs)
	return mi


static func cylinder(parent: Node3D, body: StaticBody3D, mat: Material,
		pos: Vector3, radius: float, height: float, rot: Vector3 = Vector3.ZERO,
		solid: bool = true, segments: int = 10, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if solid and body != null:
		var shape := CylinderShape3D.new()
		shape.radius = maxf(radius, mesh.top_radius)
		shape.height = height
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos
		cs.rotation = rot
		body.add_child(cs)
	return mi


static func prism(parent: Node3D, mat: Material, pos: Vector3, size: Vector3,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Collapse a hand-built structure into one MeshInstance3D per material.
##
## The cabin is about thirty boxes and the tower about forty beams. Drawn
## individually that is seventy draw calls before shadows, and the shadow
## passes multiply it. Merged, each becomes four or five — which on a phone
## is the difference between the buildings being free and the buildings being
## the frame budget.
##
## Collision is untouched: the StaticBody3D keeps its individual shapes,
## which is what you want anyway (many small convex shapes beat one enormous
## merged trimesh).
##
## `skip` lists nodes whose subtrees must stay separate — anything the script
## animates at runtime, like the tower's rotating crown.
## Returns the number of MeshInstance3D nodes removed.
static func merge_by_material(root: Node3D, skip: Array = []) -> int:
	var groups := {}
	var sources: Array[MeshInstance3D] = []
	_collect(root, skip, sources)
	for mi in sources:
		var mat := mi.material_override if mi.material_override else mi.get_active_material(0)
		if mat == null or mi.mesh == null:
			continue
		var key := mat.get_instance_id()
		if not groups.has(key):
			groups[key] = {"mat": mat, "items": [], "shadow": mi.cast_shadow}
		(groups[key]["items"] as Array).append(mi)

	var removed := 0
	var inv := root.global_transform.affine_inverse()
	for key in groups:
		var items: Array = groups[key]["items"]
		if items.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in items:
			var m: MeshInstance3D = mi
			for surf in m.mesh.get_surface_count():
				st.append_from(m.mesh, surf, inv * m.global_transform)
		var merged := MeshInstance3D.new()
		merged.name = "Merged_%d" % key
		merged.mesh = st.commit()
		merged.material_override = groups[key]["mat"]
		merged.cast_shadow = groups[key]["shadow"]
		merged.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(merged)
		for mi in items:
			(mi as Node).queue_free()
			removed += 1
	return removed


static func _collect(n: Node, skip: Array, out: Array[MeshInstance3D]) -> void:
	for c in n.get_children():
		if skip.has(c):
			continue
		if c is MeshInstance3D:
			out.append(c)
		if c is Node3D:
			_collect(c, skip, out)


static func material(color: Color, roughness: float, metallic: float = 0.0,
		emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.metallic_specular = 0.5
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m
