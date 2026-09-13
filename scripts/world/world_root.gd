extends Node3D
class_name WorldRoot
##
## Orchestrates the benchmark scene.
##
## Build order matters and is explicit here rather than left to _ready()
## ordering: terrain and water build themselves as children (children are
## ready first), then this script places the structures, tells the scatterer
## where it may not put a tree, builds the navigation mesh out of what the
## scatterer actually placed, and only then spawns the actors.
##
## Landmark positions are written as intent — "the tower is on the western
## ridge" — and then SNAPPED to a spot the terrain actually supports, so
## retuning TerrainData can never leave a building hanging in the air.

@export var terrain_path: NodePath
@export var water_path: NodePath
@export var scatter_path: NodePath
@export var nav_path: NodePath
@export var fog_path: NodePath
@export var player_path: NodePath
@export var npc_path: NodePath
@export var animal_path: NodePath
@export var hud_path: NodePath
@export var debug_path: NodePath
@export var sun_path: NodePath
@export var props_parent: NodePath

const PICKUP_SCENE := "res://scenes/world/Pickup.tscn"

## Where things want to be. Each is nudged to the nearest spot that is dry,
## walkable and flat enough before anything is built there.
const TOWER_WISH := Vector2(-58.0, -62.0)
const CABIN_WISH := Vector2(31.0, 25.0)
const PLAYER_WISH := Vector2(8.0, 42.0)
const NPC_WISH := Vector2(20.0, 33.0)
const ANIMAL_WISH := Vector2(44.0, 9.0)

var terrain: TerrainBuilder
var water: WaterBody
var scatter: Scatter
var nav: NavBuilder
var fog: FogWall
var player: PlayerController
var npc: NpcController
var animal: AnimalPlaceholder

var tower: BeaconTower
var cabin: ScoutCabin

var _pickups := 0
var _props := 0
var _total_ms := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	_rng.seed = 0x57524C44

	terrain = get_node_or_null(terrain_path) as TerrainBuilder
	water = get_node_or_null(water_path) as WaterBody
	scatter = get_node_or_null(scatter_path) as Scatter
	nav = get_node_or_null(nav_path) as NavBuilder
	fog = get_node_or_null(fog_path) as FogWall
	player = get_node_or_null(player_path) as PlayerController
	npc = get_node_or_null(npc_path) as NpcController
	animal = get_node_or_null(animal_path) as AnimalPlaceholder

	var reserved: Array[Vector3] = []

	# --- structures -------------------------------------------------------
	var tower_at := _settle(TOWER_WISH, 26.0, 0.86)
	tower = BeaconTower.new()
	tower.name = "BeaconTower"
	tower.position = Vector3(tower_at.x, TerrainData.height_at(tower_at.x, tower_at.y) - 0.5, tower_at.y)
	add_child(tower)
	reserved.append(Vector3(tower_at.x, tower_at.y, tower.footprint_radius + 2.5))

	var cabin_at := _settle(CABIN_WISH, 22.0, 0.93)
	cabin = ScoutCabin.new()
	cabin.name = "ScoutCabin"
	cabin.position = Vector3(cabin_at.x, TerrainData.height_at(cabin_at.x, cabin_at.y) - 0.18, cabin_at.y)
	cabin.rotation.y = _rng.randf_range(-0.6, 0.6)
	add_child(cabin)
	reserved.append(Vector3(cabin_at.x, cabin_at.y, cabin.footprint_radius + 2.0))

	# Keep the spawn area and the NPC's start clear of trees.
	var spawn := _settle(PLAYER_WISH, 14.0, 0.9)
	reserved.append(Vector3(spawn.x, spawn.y, 5.0))

	# --- vegetation, then navigation over what was actually placed --------
	if scatter:
		scatter.build(reserved)
	if nav:
		var obstacles := scatter.obstacle_circles() if scatter else ([] as Array[Vector3])
		obstacles.append(Vector3(tower_at.x, tower_at.y, tower.footprint_radius))
		obstacles.append(Vector3(cabin_at.x, cabin_at.y, cabin.footprint_radius))
		nav.build(obstacles)

	# --- props, pickups, actors -------------------------------------------
	_place_props(reserved)
	_place_pickups(spawn, tower_at, cabin_at)
	_place_actors(spawn)
	_wire()

	_total_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Find a spot near `wish` that is dry, walkable and flat enough to build on.
func _settle(wish: Vector2, search: float, min_flat: float) -> Vector2:
	if _buildable(wish, min_flat):
		return wish
	var step := 2.5
	var r := step
	while r <= search:
		for i in 16:
			var a := TAU * float(i) / 16.0
			var p := wish + Vector2(cos(a), sin(a)) * r
			if _buildable(p, min_flat):
				return p
		r += step
	push_warning("WorldRoot: no buildable ground near %s, using it anyway" % str(wish))
	return wish


func _buildable(p: Vector2, min_flat: float) -> bool:
	if TerrainData.height_at(p.x, p.y) < TerrainData.WATER_LEVEL + 1.2:
		return false
	if not TerrainData.is_walkable(p.x, p.y):
		return false
	return TerrainData.normal_at(p.x, p.y, 3.0).y >= min_flat


func _parent_for_props() -> Node3D:
	var n := get_node_or_null(props_parent) as Node3D
	return n if n else self


## Lanterns, fencing and worn path tiles. Small in number and hand-placed
## along the path, because a camp reads as a camp through arrangement, not
## through density.
func _place_props(reserved: Array[Vector3]) -> void:
	var parent := _parent_for_props()
	var struct_mat: Material = load("res://assets/materials/mat_atlas_structures.tres")

	# Worn tiles along the path.
	var tiles: Array[Mesh] = []
	for n in ["path_A", "path_B", "path_C", "path_D"]:
		var m := _mesh_of("res://assets/environment/structures/%s.gltf" % n)
		if m: tiles.append(m)
	if not tiles.is_empty():
		var per: Array[Array] = []
		for i in tiles.size():
			per.append([])
		var x := -TerrainData.SIZE + 10.0
		while x < TerrainData.SIZE - 10.0:
			var z := TerrainData.path_center_z(x) + _rng.randf_range(-1.5, 1.5)
			if TerrainData.height_at(x, z) > TerrainData.WATER_LEVEL + 0.25:
				var k := _rng.randi() % tiles.size()
				var b := Basis.IDENTITY.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
				b = b.scaled(Vector3.ONE * _rng.randf_range(0.95, 1.25))
				per[k].append(Transform3D(b, Vector3(x, TerrainData.height_at(x, z) - 0.055, z)))
				_props += 1
			x += _rng.randf_range(1.5, 2.6)
		for i in tiles.size():
			_multimesh(parent, "PathTiles%d" % i, tiles[i], per[i], struct_mat, false)

	# Lanterns marking the path where it passes the cabin, and the camp fence.
	var lantern := _mesh_of("res://assets/environment/structures/post_lantern.gltf")
	var fence := _mesh_of("res://assets/environment/structures/fence.gltf")
	var fence_broken := _mesh_of("res://assets/environment/structures/fence_broken.gltf")
	var bench := _mesh_of("res://assets/environment/structures/bench.gltf")

	var lantern_ts: Array[Transform3D] = []
	var lx := -70.0
	while lx <= 70.0:
		var lz := TerrainData.path_center_z(lx) + (3.4 if int(lx / 28.0) % 2 == 0 else -3.4)
		if TerrainData.height_at(lx, lz) > TerrainData.WATER_LEVEL + 0.6:
			lantern_ts.append(Transform3D(
				Basis.IDENTITY.rotated(Vector3.UP, _rng.randf_range(0.0, TAU)),
				Vector3(lx, TerrainData.height_at(lx, lz) + 1.25, lz)))
			_props += 1
		lx += 28.0
	if lantern:
		_multimesh(parent, "Lanterns", lantern, lantern_ts, struct_mat, true)
		# A small warm light at each lantern; cheap, and it gives the path
		# somewhere to read at dusk.
		for t in lantern_ts:
			var l := OmniLight3D.new()
			l.position = t.origin + Vector3(0, 1.55, 0)
			l.light_color = Color(1.0, 0.79, 0.5)
			l.light_energy = 1.35
			l.omni_range = 9.0
			l.shadow_enabled = false
			parent.add_child(l)

	# Fencing around the cabin yard.
	if fence and cabin:
		var ts: Array[Transform3D] = []
		var c := Vector2(cabin.position.x, cabin.position.z)
		for i in 9:
			var a := TAU * float(i) / 9.0 + 0.4
			var r := cabin.footprint_radius + 3.2
			var p := c + Vector2(cos(a), sin(a)) * r
			if TerrainData.height_at(p.x, p.y) < TerrainData.WATER_LEVEL + 0.4:
				continue
			ts.append(Transform3D(Basis.IDENTITY.rotated(Vector3.UP, -a),
				Vector3(p.x, TerrainData.height_at(p.x, p.y) - 0.1, p.y)))
			_props += 1
		var half := ts.size() / 2
		_multimesh(parent, "Fence", fence, ts.slice(0, half), struct_mat, true)
		if fence_broken:
			_multimesh(parent, "FenceBroken", fence_broken, ts.slice(half), struct_mat, true)
		if bench:
			var bp := c + Vector2(cos(1.1), sin(1.1)) * (cabin.footprint_radius + 1.4)
			_multimesh(parent, "Bench", bench, [Transform3D(
				Basis.IDENTITY.rotated(Vector3.UP, 1.1 + PI * 0.5),
				Vector3(bp.x, TerrainData.height_at(bp.x, bp.y), bp.y))] as Array[Transform3D],
				struct_mat, true)
			_props += 1


func _mesh_of(path: String) -> Mesh:
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var root := ps.instantiate()
	var m := _find_mesh(root)
	root.queue_free()
	return m


func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m: return m
	return null


func _multimesh(parent: Node3D, name: String, mesh: Mesh, ts: Array,
		mat: Material, shadows: bool) -> void:
	if ts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = ts.size()
	for i in ts.size():
		mm.set_instance_transform(i, ts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mmi)


## BOIS strewn along the route the player will actually run, plus a couple of
## CRISTAL at the beacon. Section 39: one resource is enough, two is plenty.
func _place_pickups(spawn: Vector2, tower_at: Vector2, cabin_at: Vector2) -> void:
	var scene: PackedScene = load(PICKUP_SCENE)
	if scene == null:
		push_error("WorldRoot: missing %s" % PICKUP_SCENE)
		return
	var parent := _parent_for_props()

	# Wood: a trail of it along the path, deliberately spaced so that the
	# natural way to collect them is to keep running.
	var placed := 0
	var x := spawn.x - 42.0
	while x < spawn.x + 76.0 and placed < 18:
		var z := TerrainData.path_center_z(x) + _rng.randf_range(-3.2, 3.2)
		if TerrainData.height_at(x, z) > TerrainData.WATER_LEVEL + 0.4:
			_spawn_pickup(scene, parent, Vector2(x, z), "BOIS")
			placed += 1
		x += _rng.randf_range(7.0, 12.0)

	# A few more in the woods, so picking up is not only a corridor trick.
	for _i in 8:
		for _try in 30:
			var p := Vector2(_rng.randf_range(-90.0, 90.0), _rng.randf_range(-90.0, 90.0))
			if TerrainData.is_walkable(p.x, p.y) and TerrainData.height_at(p.x, p.y) > TerrainData.WATER_LEVEL + 0.8:
				_spawn_pickup(scene, parent, p, "BOIS")
				break

	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var p := tower_at + Vector2(cos(a), sin(a)) * 6.5
		if TerrainData.is_walkable(p.x, p.y):
			_spawn_pickup(scene, parent, p, "CRISTAL")

	for i in 2:
		var p := cabin_at + Vector2(cos(float(i) * 2.1), sin(float(i) * 2.1)) * 4.6
		if TerrainData.is_walkable(p.x, p.y):
			_spawn_pickup(scene, parent, p, "BOIS")


func _spawn_pickup(scene: PackedScene, parent: Node3D, p: Vector2, kind: String) -> void:
	var n := scene.instantiate()
	n.set("kind", kind)
	parent.add_child(n)
	(n as Node3D).global_position = Vector3(p.x, TerrainData.height_at(p.x, p.y) + 0.45, p.y)
	(n as Node3D).rotation.y = _rng.randf_range(0.0, TAU)
	_pickups += 1


func _place_actors(spawn: Vector2) -> void:
	if player:
		player.global_position = Vector3(spawn.x, TerrainData.height_at(spawn.x, spawn.y) + 0.1, spawn.y)
	if npc:
		var p := _settle(NPC_WISH, 18.0, 0.86)
		npc.global_position = Vector3(p.x, TerrainData.height_at(p.x, p.y) + 0.1, p.y)
	if animal:
		var p := _settle(ANIMAL_WISH, 22.0, 0.86)
		animal.global_position = Vector3(p.x, TerrainData.height_at(p.x, p.y) + 0.1, p.y)


func _wire() -> void:
	if water and player:
		water.body_entered.connect(func(b): if b == player: player.in_water_volume = true)
		water.body_exited.connect(func(b): if b == player: player.in_water_volume = false)
	var hud := get_node_or_null(hud_path) as MobileHud
	var dbg := get_node_or_null(debug_path) as DebugHud
	if hud and dbg:
		hud.debug_toggle_pressed.connect(func():
			dbg.toggle()
			hud.debug_visible = dbg.visible)
	# Shadow distance follows the quality preset.
	Quality.changed.connect(_apply_quality)
	_apply_quality(Quality.level)


func _apply_quality(_l: int) -> void:
	var sun := get_node_or_null(sun_path) as DirectionalLight3D
	if sun:
		sun.directional_shadow_max_distance = Quality.shadow_distance()
		sun.shadow_enabled = Quality.shadows_enabled()


## Shown in the debug panel, and quoted in docs/BENCHMARK_REPORT.md.
func build_report() -> String:
	var lines := PackedStringArray()
	if terrain:
		lines.append("terrain  %d tris   %.0f ms" % [terrain.triangle_count, terrain.build_ms])
	if water:
		lines.append("water    %d tris" % water.triangle_count)
	if scatter:
		lines.append("scatter  %d instances  %d colliders  %.0f ms" % [
			scatter.instance_count, scatter.collider_count, scatter.build_ms])
	if nav:
		lines.append("navmesh  %d polys   %.0f ms" % [nav.polygon_count, nav.build_ms])
	lines.append("props %d   pickups %d   world build %.0f ms" % [_props, _pickups, _total_ms])
	return "\n".join(lines)
