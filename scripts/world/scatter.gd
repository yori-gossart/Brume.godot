extends Node3D
class_name Scatter
##
## Places the vegetation and the loose rock, and gives the massive ones real
## collision.
##
## Rendering uses one MultiMeshInstance3D per species: ninety trees cost about
## a dozen draw calls instead of ninety, which is the difference between
## comfortable and marginal on a mid-range phone.
##
## Collision is separate and deliberately coarse (section 14): an upright
## cylinder for a trunk, a simplified convex hull for a rock. Nobody needs
## triangle-accurate collision against a pine canopy, and on a phone nobody
## can afford it.
##
## QUALITY AND COLLISION ARE INDEPENDENT (section 65).
##
## 0.1 hid the tail of each MultiMesh at LOW and disabled the matching
## collision shapes with it. That kept picture and physics in step, but it
## made a tree traversable purely because the player had turned the quality
## down — which 0.2 forbids outright.
##
## The fix is not to keep invisible trunks solid (that is just as bad from
## the other side). It is that LOW no longer touches anything solid at all:
## every tree and every boulder is drawn and collidable at both quality
## levels, and LOW economises on the DECORATION instead — scrub, pebbles,
## water plants — none of which has a collider in the first place.
##
## So the collision world is byte-identical at HIGH and LOW, and
## tests/collision_world_test.gd runs its whole traversal battery at both.

const COL_TRUNK := 0   ## upright cylinder, sized to the trunk only
const COL_HULL := 1    ## simplified convex hull of the whole mesh
const COL_NONE := 2    ## decoration, walk straight through it

## Species table. Kept as plain data at the top of the file so it can be
## retuned from the Godot Android editor without reading the code below.
const SPECIES := [
	# --- real-scale conifers and dead wood (KayKit Halloween Bits) --------
	{ "id": "pine_large",  "path": "res://assets/environment/structures/tree_pine_orange_large.gltf",
	  "count": 26, "scale": [0.85, 1.15], "spacing": 7.5, "col": COL_TRUNK, "where": "grove",
	  "radius": 0.55, "height": 6.0, "atlas": "structures", "tilt": 0.05 },
	{ "id": "pine_medium", "path": "res://assets/environment/structures/tree_pine_orange_medium.gltf",
	  "count": 24, "scale": [0.85, 1.2], "spacing": 6.0, "col": COL_TRUNK, "where": "grove",
	  "radius": 0.45, "height": 5.0, "atlas": "structures", "tilt": 0.06 },
	{ "id": "pine_yellow", "path": "res://assets/environment/structures/tree_pine_yellow_large.gltf",
	  "count": 16, "scale": [0.8, 1.1], "spacing": 8.0, "col": COL_TRUNK, "where": "edge",
	  "radius": 0.55, "height": 6.0, "atlas": "structures", "tilt": 0.05 },
	{ "id": "dead_large",  "path": "res://assets/environment/structures/tree_dead_large.gltf",
	  "count": 10, "scale": [0.9, 1.25], "spacing": 14.0, "col": COL_TRUNK, "where": "isolated",
	  "radius": 0.4, "height": 4.5, "atlas": "structures", "tilt": 0.13 },
	{ "id": "dead_medium", "path": "res://assets/environment/structures/tree_dead_medium.gltf",
	  "count": 10, "scale": [0.9, 1.2], "spacing": 9.0, "col": COL_TRUNK, "where": "edge",
	  "radius": 0.35, "height": 3.6, "atlas": "structures", "tilt": 0.15 },
	# --- rounded broadleaf silhouettes (KayKit Medieval Hexagon) ----------
	# These models are authored at hexagon-tile scale (~1.2 units tall), so
	# they are scaled up to forest size here.
	{ "id": "broadleaf_A", "path": "res://assets/environment/nature/tree_single_A.gltf",
	  "count": 22, "scale": [4.0, 5.4], "spacing": 6.5, "col": COL_TRUNK, "where": "grove",
	  "radius": 0.5, "height": 4.4, "atlas": "nature", "tilt": 0.07 },
	{ "id": "broadleaf_B", "path": "res://assets/environment/nature/tree_single_B.gltf",
	  "count": 18, "scale": [4.0, 5.6], "spacing": 7.0, "col": COL_TRUNK, "where": "edge",
	  "radius": 0.5, "height": 4.4, "atlas": "nature", "tilt": 0.07 },
	# --- rock ------------------------------------------------------------
	{ "id": "rock_big_A",  "path": "res://assets/environment/nature/rock_single_E.gltf",
	  "count": 13, "scale": [7.0, 11.0], "spacing": 7.0, "col": COL_HULL, "where": "rocky",
	  "atlas": "nature", "tilt": 0.25, "yaw_free": true },
	{ "id": "rock_big_B",  "path": "res://assets/environment/nature/rock_single_C.gltf",
	  "count": 12, "scale": [7.0, 12.0], "spacing": 7.0, "col": COL_HULL, "where": "rocky",
	  "atlas": "nature", "tilt": 0.25, "yaw_free": true },
	{ "id": "rock_mid",    "path": "res://assets/environment/nature/rock_single_D.gltf",
	  "count": 16, "scale": [4.5, 7.0], "spacing": 4.5, "col": COL_HULL, "where": "rocky",
	  "atlas": "nature", "tilt": 0.3, "yaw_free": true },
	{ "id": "rock_small",  "path": "res://assets/environment/nature/rock_single_B.gltf",
	  "count": 30, "scale": [2.0, 4.0], "spacing": 3.0, "col": COL_NONE, "where": "rocky",
	  "atlas": "nature", "tilt": 0.4, "yaw_free": true, "small": true },
	{ "id": "pebble",      "path": "res://assets/environment/nature/rock_single_A.gltf",
	  "count": 34, "scale": [1.5, 3.0], "spacing": 2.5, "col": COL_NONE, "where": "rocky",
	  "atlas": "nature", "tilt": 0.5, "yaw_free": true, "small": true },
	# --- undergrowth: clusters used as bushes, no collision ---------------
	{ "id": "bush_A",      "path": "res://assets/environment/nature/trees_A_medium.gltf",
	  "count": 40, "scale": [1.0, 1.7], "spacing": 3.6, "col": COL_NONE, "where": "undergrowth",
	  "atlas": "nature", "tilt": 0.08, "small": true },
	# The verge: the path has to look cut THROUGH something, not painted on.
	{ "id": "verge_tree",  "path": "res://assets/environment/nature/tree_single_B.gltf",
	  "count": 14, "scale": [3.4, 4.6], "spacing": 9.0, "col": COL_TRUNK,
	  "where": "roadside", "radius": 0.45, "height": 3.8, "atlas": "nature", "tilt": 0.09 },
	{ "id": "verge_scrub", "path": "res://assets/environment/nature/trees_A_medium.gltf",
	  "count": 22, "scale": [0.9, 1.5], "spacing": 4.0, "col": COL_NONE,
	  "where": "roadside", "atlas": "nature", "tilt": 0.08, "small": true },
	{ "id": "bush_B",      "path": "res://assets/environment/nature/trees_B_medium.gltf",
	  "count": 34, "scale": [1.0, 1.6], "spacing": 3.6, "col": COL_NONE, "where": "edge",
	  "atlas": "nature", "tilt": 0.08, "small": true },
]

## Species that live in shallow water instead of on dry land.
const WATER_SPECIES := [
	{ "id": "lily_A",   "path": "res://assets/environment/nature/waterlily_A.gltf",
	  "count": 26, "scale": [4.0, 7.0], "spacing": 2.5, "depth": [0.15, 1.1], "atlas": "nature" },
	{ "id": "lily_B",   "path": "res://assets/environment/nature/waterlily_B.gltf",
	  "count": 20, "scale": [4.0, 7.0], "spacing": 2.5, "depth": [0.2, 1.3], "atlas": "nature" },
	{ "id": "reed_B",   "path": "res://assets/environment/nature/waterplant_B.gltf",
	  "count": 34, "scale": [3.5, 6.5], "spacing": 2.2, "depth": [0.05, 0.7], "atlas": "nature" },
	{ "id": "reed_C",   "path": "res://assets/environment/nature/waterplant_C.gltf",
	  "count": 28, "scale": [3.5, 6.0], "spacing": 2.2, "depth": [0.05, 0.6], "atlas": "nature" },
]

## Fixed layout seed. This is NOT a world-generation seed (section 37 forbids
## that): it is here so the hand-tuned layout is byte-identical on every
## device and every run, which is what makes a benchmark comparable.
const LAYOUT_SEED := 0x0F06_0A17

@export var nature_material: Material
@export var structures_material: Material

var _rng := RandomNumberGenerator.new()
var composition: ForestComposition
var _taken: Array[Vector3] = []          ## every placement: x, z, spacing
var _blocking: Array[Vector3] = []       ## only the ones with real collision
var _reserved: Array[Vector3] = []
var _entries: Array[Dictionary] = []     ## per species: multimesh + shapes
var instance_count: int = 0
var collider_count: int = 0
var build_ms: float = 0.0


## Call once, after the terrain exists and the structures have claimed their
## ground. `reserved` is a list of Vector3(x, z, radius) keep-out circles.
func build(reserved: Array[Vector3]) -> void:
	var t0 := Time.get_ticks_usec()
	_reserved = reserved
	_rng.seed = LAYOUT_SEED
	# Lay out the wood first — stands, glades, boulder fields — then let each
	# species find its place inside that structure.
	composition = ForestComposition.new(_rng)
	composition.compose(reserved)
	for s in SPECIES:
		_build_species(s)
	for s in WATER_SPECIES:
		_build_water_species(s)
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	Quality.changed.connect(_on_quality_changed)
	_on_quality_changed(Quality.level)


func _material_for(atlas: String) -> Material:
	return structures_material if atlas == "structures" else nature_material


func _load_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Scatter: cannot load %s" % path)
		return null
	var root := packed.instantiate()
	var found := _first_mesh(root)
	root.queue_free()
	return found


func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _free_spot(spacing: float, max_tries: int, policy: int,
		water: bool = false, depth_range: Array = []) -> Vector3:
	var lim := TerrainData.SIZE - 8.0
	for _i in max_tries:
		var x := 0.0
		var z := 0.0
		if water:
			x = _rng.randf_range(-lim, lim)
			z = _rng.randf_range(-lim, lim)
			var d := TerrainData.water_depth_at(x, z)
			if d < depth_range[0] or d > depth_range[1]:
				continue
		else:
			# The composition proposes, the terrain disposes.
			var cand := composition.propose(policy)
			if cand == Vector2.INF:
				continue
			x = cand.x
			z = cand.y
			if absf(x) > lim or absf(z) > lim:
				continue
			if not TerrainData.is_walkable(x, z):
				continue
			# Leave the trodden path trodden.
			if TerrainData.path_influence(x, z) > 0.3:
				continue
			# Keep a dry margin so trees do not stand in the river.
			if TerrainData.height_at(x, z) < TerrainData.WATER_LEVEL + 0.7:
				continue
			if not composition.accepts(policy, Vector2(x, z)):
				continue
		var ok := true
		for r in _reserved:
			if Vector2(x - r.x, z - r.y).length() < r.z:
				ok = false
				break
		if not ok:
			continue
		for t in _taken:
			if Vector2(x - t.x, z - t.y).length() < maxf(spacing, t.z):
				ok = false
				break
		if not ok:
			continue
		_taken.push_back(Vector3(x, z, spacing))
		return Vector3(x, 0.0, z)
	return Vector3.INF


func _build_species(s: Dictionary) -> void:
	var mesh := _load_mesh(s["path"])
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	var count: int = s["count"]
	var policy := ForestComposition.policy_from_name(str(s.get("where", "grove")))
	for _i in count:
		var spot := _free_spot(s["spacing"], 90, policy)
		if spot == Vector3.INF:
			continue
		var sc := _rng.randf_range(s["scale"][0], s["scale"][1])
		var basis := Basis.IDENTITY.scaled(Vector3(sc, sc, sc))
		basis = basis.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
		var tilt: float = s.get("tilt", 0.0)
		if tilt > 0.0:
			# Lean with the ground a little; trees on a slope that stand
			# perfectly plumb are one of the tells of a cheap scatter.
			var n := TerrainData.normal_at(spot.x, spot.z)
			var lean: Vector3 = Vector3.UP.lerp(n, tilt * 4.0).normalized()
			var axis := Vector3.UP.cross(lean)
			if axis.length() > 0.0001:
				basis = Basis(axis.normalized(), Vector3.UP.angle_to(lean)) * basis
			basis = basis.rotated(Vector3(1, 0, 0), _rng.randf_range(-tilt, tilt))
			basis = basis.rotated(Vector3(0, 0, 1), _rng.randf_range(-tilt, tilt))
		var y := TerrainData.height_at(spot.x, spot.z) - 0.08 * sc
		transforms.push_back(Transform3D(basis, Vector3(spot.x, y, spot.z)))

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + str(s["id"])
	mmi.multimesh = mm
	mmi.material_override = _material_for(s["atlas"])
	mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if s.get("small", false)
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	instance_count += transforms.size()

	var shapes: Array[CollisionShape3D] = []
	var col: int = s["col"]
	if col != COL_NONE:
		var body := StaticBody3D.new()
		body.name = "Col_" + str(s["id"])
		# Solid level geometry. Characters collide with this and nothing else.
		body.collision_layer = Layers.WORLD_STATIC
		body.collision_mask = 0
		SurfaceType.tag(body, SurfaceType.Kind.WOOD if col == COL_TRUNK else SurfaceType.Kind.ROCK)
		add_child(body)
		var hull: ConvexPolygonShape3D = null
		var hull_r := 0.0
		if col == COL_HULL:
			hull = mesh.create_convex_shape(true, true)
			for p in hull.points:
				hull_r = maxf(hull_r, Vector2(p.x, p.z).length())
		for i in transforms.size():
			var cs := CollisionShape3D.new()
			var t := transforms[i]
			var sc: float = t.basis.get_scale().x
			if col == COL_TRUNK:
				# The trunk proxy is expressed for a mid-range specimen, then
				# scaled with the instance so a small pine gets a small trunk.
				var mid: float = (s["scale"][0] + s["scale"][1]) * 0.5
				var k: float = sc / maxf(mid, 0.0001)
				var cyl := CylinderShape3D.new()
				cyl.radius = s["radius"] * k
				cyl.height = s["height"] * k
				cs.shape = cyl
				# Upright, regardless of how far the tree leans: a leaning
				# trunk proxy makes the player slide off the base.
				cs.position = t.origin + Vector3(0.0, cyl.height * 0.5, 0.0)
			else:
				cs.shape = _scaled_hull(hull, sc)
				cs.transform = Transform3D(
					Basis(t.basis.get_rotation_quaternion()), t.origin)
			body.add_child(cs)
			shapes.push_back(cs)
			collider_count += 1
			# Radius the navigation mesh must route around.
			var block_r: float = (s["radius"] * (sc / maxf((s["scale"][0] + s["scale"][1]) * 0.5, 0.0001))
				if col == COL_TRUNK else hull_r * sc * 0.85)
			_blocking.push_back(Vector3(t.origin.x, t.origin.z, maxf(block_r, 0.4)))

	_entries.push_back({ "mmi": mmi, "shapes": shapes, "total": transforms.size(),
		"decorative": col == COL_NONE })


func _scaled_hull(src: ConvexPolygonShape3D, sc: float) -> ConvexPolygonShape3D:
	var out := ConvexPolygonShape3D.new()
	var pts := src.points.duplicate()
	for i in pts.size():
		pts[i] = pts[i] * sc
	out.points = pts
	return out


func _build_water_species(s: Dictionary) -> void:
	var mesh := _load_mesh(s["path"])
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	for _i in int(s["count"]):
		var spot := _free_spot(s["spacing"], 70, ForestComposition.Policy.SHORE,
			true, s["depth"])
		if spot == Vector3.INF:
			continue
		var sc := _rng.randf_range(s["scale"][0], s["scale"][1])
		var basis := Basis.IDENTITY.scaled(Vector3(sc, sc, sc)).rotated(
			Vector3.UP, _rng.randf_range(0.0, TAU))
		# Lilies float; reeds are rooted in the bed and stick out of it.
		var y: float = TerrainData.WATER_LEVEL - 0.02
		if str(s["id"]).begins_with("reed"):
			y = TerrainData.height_at(spot.x, spot.z)
		transforms.push_back(Transform3D(basis, Vector3(spot.x, y, spot.z)))
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + str(s["id"])
	mmi.multimesh = mm
	mmi.material_override = _material_for(s["atlas"])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	instance_count += transforms.size()
	_entries.push_back({ "mmi": mmi, "shapes": [] as Array[CollisionShape3D],
		"total": transforms.size(), "decorative": true })


## LOW economises on DECORATION only.
##
## Nothing with a collider is touched here — not its visibility, not its
## shapes. That is section 65: the collision world must be identical at both
## quality levels, and a tree must not become traversable because the player
## turned the quality down. It also means LOW can never produce the opposite
## bug, an invisible trunk you walk into.
##
## What LOW actually saves: scrub, pebbles, small rocks, water plants. In
## this scene that is the clear majority of the instances and all of the
## overdraw, and none of it is solid.
func _on_quality_changed(_level: int) -> void:
	var ratio := Quality.vegetation_ratio()
	for e in _entries:
		var total: int = e["total"]
		var mmi: MultiMeshInstance3D = e["mmi"]
		if not e["decorative"]:
			# Solid species: always fully drawn, always fully collidable.
			mmi.multimesh.visible_instance_count = total
			mmi.visible = true
			continue
		# Decoration thins out; it never disappears entirely, or LOW stops
		# looking like the same wood.
		var n := int(ceil(total * ratio))
		mmi.multimesh.visible_instance_count = n
		mmi.visible = n > 0


## Keep-out circles — Vector3(x, z, radius) — for the solid things this
## scatterer placed. The navigation mesh carves these out so the NPC walks
## around trunks and boulders instead of into them (section 26).
func obstacle_circles() -> Array[Vector3]:
	return _blocking.duplicate()
