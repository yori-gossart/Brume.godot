extends NavigationRegion3D
class_name NavBuilder
##
## Builds the navigation mesh for the NPC and the animal.
##
## It is assembled as explicit polygons instead of being baked. Baking a
## NavigationMesh from a 39 000-triangle terrain takes seconds and a worker
## thread; on a phone, in an editor session, that is exactly the kind of wait
## the brief tells us to avoid (section 49). Building a grid of triangles
## straight from TerrainData is deterministic, takes a few milliseconds, and
## carves obstacles exactly where the collision shapes actually are.
##
## A cell is walkable when TerrainData says the ground there is land, gentle
## enough, and outside every obstacle circle grown by the agent radius.

@export var cell_size: float = 2.5
@export var agent_radius: float = 0.65
## Navigation is restricted to this square, which is smaller than the terrain:
## the outer ring is scenery, and the fog eats the far side anyway.
@export var extent: float = 118.0

var polygon_count: int = 0
var build_ms: float = 0.0
var _walkable_centres: PackedVector3Array = PackedVector3Array()


func build(obstacles: Array[Vector3]) -> void:
	var t0 := Time.get_ticks_usec()
	var cells := int(round((extent * 2.0) / cell_size))
	var n := cells + 1

	# --- which cells are walkable ----------------------------------------
	var ok := []
	ok.resize(cells * cells)
	for j in cells:
		for i in cells:
			var x := -extent + (float(i) + 0.5) * cell_size
			var z := -extent + (float(j) + 0.5) * cell_size
			var good := TerrainData.is_walkable(x, z)
			if good:
				for o in obstacles:
					var r := o.z + agent_radius
					if Vector2(x - o.x, z - o.y).length_squared() < r * r:
						good = false
						break
			ok[j * cells + i] = good

	# --- vertices, shared between neighbouring cells ----------------------
	var verts := PackedVector3Array()
	var vindex := {}
	var nav := NavigationMesh.new()

	var polys: Array[PackedInt32Array] = []
	for j in cells:
		for i in cells:
			if not ok[j * cells + i]:
				continue
			var a := _vid(vindex, verts, i, j, n)
			var b := _vid(vindex, verts, i + 1, j, n)
			var c := _vid(vindex, verts, i + 1, j + 1, n)
			var d := _vid(vindex, verts, i, j + 1, n)
			# Counter-clockwise seen from above (+Y looking down -Y).
			polys.push_back(PackedInt32Array([a, d, c]))
			polys.push_back(PackedInt32Array([a, c, b]))

	nav.vertices = verts
	for p in polys:
		nav.add_polygon(p)
	nav.agent_radius = 0.0   # obstacles are already carved, do not shrink twice
	nav.agent_height = 1.8
	nav.agent_max_slope = 50.0
	polygon_count = polys.size()

	# Cache the centre of every walkable cell: the NPC and the animal pick
	# their wander targets from this instead of guessing and re-sampling.
	_walkable_centres = PackedVector3Array()
	for j in cells:
		for i in cells:
			if ok[j * cells + i]:
				var x := -extent + (float(i) + 0.5) * cell_size
				var z := -extent + (float(j) + 0.5) * cell_size
				_walkable_centres.push_back(Vector3(x, TerrainData.height_at(x, z), z))

	navigation_mesh = nav
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _vid(vindex: Dictionary, verts: PackedVector3Array, i: int, j: int, n: int) -> int:
	var key := j * n + i
	if vindex.has(key):
		return vindex[key]
	var x := -extent + float(i) * cell_size
	var z := -extent + float(j) * cell_size
	var id := verts.size()
	verts.push_back(Vector3(x, TerrainData.height_at(x, z) + 0.05, z))
	vindex[key] = id
	return id


## A reachable point on the navigation mesh, at least `min_dist` away from
## `from`. Returns `from` unchanged if the mesh is empty.
func random_point(rng: RandomNumberGenerator, from: Vector3, min_dist: float,
		max_dist: float = 1e9) -> Vector3:
	if _walkable_centres.is_empty():
		return from
	for _i in 48:
		var p := _walkable_centres[rng.randi() % _walkable_centres.size()]
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d >= min_dist and d <= max_dist:
			return p
	return _walkable_centres[rng.randi() % _walkable_centres.size()]


func walkable_point_count() -> int:
	return _walkable_centres.size()
