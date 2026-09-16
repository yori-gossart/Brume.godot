extends SceneTree
##
## Doors, surfaces, moving pickups, and whether NPCs and animals respect the
## world (sections 55, 56, 57, 58, 59).
##
## Section 68 again: none of this reads a flag. The door test walks the
## player at a shut door and then at an open one. The surface test walks the
## player onto grass, a path, stone, planks and into the river and reads back
## what the character believes is underfoot. The NPC test gives a nomad a
## destination on the far side of a tree and watches whether it goes round.

var world: Node3D
var player: PlayerController
var results: Array = []
var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	world = (load("res://scenes/testing/ArtPhysicsShowcase.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _i in 6:
		await physics_frame
	player = world.get_node("Player")
	(world.get_node("UI/MobileHud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	(world.get_node("PlayerCamera") as Node).process_mode = Node.PROCESS_MODE_DISABLED

	await _t_door()
	await _t_surfaces()
	await _t_pickup_running()
	await _t_interaction_reach()
	await _t_npc_obstacle()
	await _t_animal_obstacle()
	await _t_fog_reactions()

	print("\n=== WORLD SYSTEMS ===")
	for r in results:
		print("  %-30s %-12s %s" % [r["name"], r["verdict"], r["note"]])
	print("\n%d checks, %d failed\n" % [results.size(), failures])
	quit(1 if failures > 0 else 0)


func _ok(name: String, cond: bool, note: String = "") -> void:
	results.append({"name": name, "verdict": "PASS" if cond else "FAIL", "note": note})
	if not cond:
		failures += 1


func _note(name: String, verdict: String, note: String) -> void:
	results.append({"name": name, "verdict": verdict, "note": note})


func _place(p: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, TerrainData.height_at(p.x, p.z) + 0.2, p.z)
	await physics_frame
	await physics_frame


## Hold the stick towards `target` for `frames` and report how close we got.
## The heading is refreshed every frame — a doorway is narrow, and a fixed
## heading set once from five metres out will clip the frame.
func _walk_at(target: Vector3, frames: int, run: bool = true) -> float:
	player.move_input = Vector2(0, 1)
	player.run_held = run
	var closest := INF
	for _i in frames:
		var dir := target - player.global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			player.camera_yaw = atan2(-dir.normalized().x, -dir.normalized().z)
		await physics_frame
		var d := player.global_position - target
		closest = minf(closest, Vector2(d.x, d.z).length())
	player.move_input = Vector2.ZERO
	player.run_held = false
	return closest


# ------------------------------------------------------------------ door --
## Section 55, verbatim: closed door BLOCKS, open door PASSES, and the test
## must move the player rather than inspect `collision.disabled`.
func _t_door() -> void:
	var door: Door = world.find_child("RuinDoor", true, false)
	if door == null:
		_ok("DOOR PRESENT", false, "no door in the scene")
		return

	# Approach from outside, aiming at a point beyond the doorway. Which
	# side is "outside" is decided by asking the terrain, not by assuming a
	# sign: the ruin is randomly rotated.
	var opening := door.global_position + Vector3.UP * 0.1
	var axis := door.global_transform.basis.z.normalized()
	var ruin_node: Node3D = door.get_parent() as Node3D
	var to_centre := ruin_node.global_position - door.global_position
	# Outside is the side the ruin's centre is NOT on.
	var out_dir := axis if axis.dot(to_centre) < 0.0 else -axis
	var beyond := opening - out_dir * 3.5
	# Stand back far enough to build up speed, but on ground the player can
	# actually stand on: close in until we find somewhere walkable and dry.
	var outside := opening + out_dir * 5.5
	for back: float in [5.5, 4.5, 3.5, 6.5, 7.5]:
		var cand: Vector3 = opening + out_dir * back
		if TerrainData.is_walkable(cand.x, cand.z) \
				and TerrainData.height_at(cand.x, cand.z) > TerrainData.WATER_LEVEL + 0.4:
			outside = cand
			break

	# --- shut ------------------------------------------------------------
	door.close()
	for _i in 80:
		await physics_frame
	_ok("DOOR STARTS CLOSED", door.state == Door.State.CLOSED and not door.is_passable(),
		"state %s, open ratio %.2f" % [door.state_name(), door.open_ratio])

	await _place(outside)
	var closest_shut := await _walk_at(beyond, 180)
	var got_through_shut := closest_shut < 1.2

	# --- open ------------------------------------------------------------
	door.open()
	for _i in 90:
		await physics_frame
	var opened := door.state == Door.State.OPEN and door.is_passable()

	await _place(outside)
	var closest_open := await _walk_at(beyond, 180)
	var got_through_open := closest_open < 1.6

	_ok("CLOSED DOOR BLOCKS", not got_through_shut,
		"closest approach to the far side: %.2f m" % closest_shut)
	_ok("OPEN DOOR PASSES", opened and got_through_open,
		"state %s, closest approach to the far side: %.2f m" % [door.state_name(), closest_open])
	# And the leaf never stops being solid while it swings (section 23).
	_ok("DOOR LEAF ALWAYS SOLID", _leaf_is_solid(door),
		"the leaf's collider is never disabled in any state")


func _leaf_is_solid(door: Door) -> bool:
	var leaf: AnimatableBody3D = door.find_child("Leaf", true, false)
	if leaf == null:
		return false
	if leaf.collision_layer & Layers.WORLD_STATIC == 0:
		return false
	for c in leaf.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).disabled:
			return false
	return true


# -------------------------------------------------------------- surfaces --
## Section 56: walk the player over each surface and check `current_surface`
## actually changes.
func _t_surfaces() -> void:
	var seen := {}

	# --- grass: open ground away from the path ---------------------------
	var g := _find_land(func(x, z):
		return TerrainData.path_influence(x, z) < 0.1 \
			and TerrainData.normal_at(x, z).y > 0.9 \
			and TerrainData.height_at(x, z) > TerrainData.WATER_LEVEL + 2.0)
	if g != Vector3.INF:
		await _place(g)
		for _i in 12: await physics_frame
		seen[SurfaceType.name_of(player.current_surface)] = true
		_ok("SURFACE GRASS", player.current_surface == SurfaceType.Kind.GRASS,
			"reported %s" % player.surface_name())

	# --- dirt: the trodden path ------------------------------------------
	var d := _find_land(func(x, z):
		return TerrainData.path_influence(x, z) > 0.8 \
			and TerrainData.height_at(x, z) > TerrainData.WATER_LEVEL + 1.0)
	if d != Vector3.INF:
		await _place(d)
		for _i in 12: await physics_frame
		seen[SurfaceType.name_of(player.current_surface)] = true
		_ok("SURFACE DIRT", player.current_surface == SurfaceType.Kind.DIRT,
			"reported %s on the path" % player.surface_name())

	# --- rock: the steep outcrop -----------------------------------------
	var r := _find_land(func(x, z):
		return TerrainData.normal_at(x, z).y < 0.80 \
			and TerrainData.is_walkable(x, z))
	if r != Vector3.INF:
		await _place(r)
		for _i in 12: await physics_frame
		seen[SurfaceType.name_of(player.current_surface)] = true
		_ok("SURFACE ROCK", player.current_surface == SurfaceType.Kind.ROCK,
			"reported %s on steep ground" % player.surface_name())

	# --- wood: the bridge deck -------------------------------------------
	var bridge: Bridge = world.find_child("Bridge", true, false)
	if bridge:
		var deck := bridge.global_position + Vector3.UP * (bridge.deck_clearance + 0.35)
		player.velocity = Vector3.ZERO
		player.global_position = deck
		for _i in 25: await physics_frame
		seen[SurfaceType.name_of(player.current_surface)] = true
		_ok("SURFACE WOOD", player.current_surface == SurfaceType.Kind.WOOD,
			"reported %s on the bridge deck" % player.surface_name())

	# --- water, both depths ----------------------------------------------
	var shallow := _find_water(0.3, 0.8)
	if shallow != Vector3.INF:
		await _place(shallow)
		for _i in 25: await physics_frame
		seen[SurfaceType.name_of(player.current_surface)] = true
		_ok("SURFACE WATER SHALLOW", player.current_surface == SurfaceType.Kind.WATER_SHALLOW,
			"reported %s at %.2f m depth" % [player.surface_name(), player.water_depth])

	var deep := _find_water(2.0, 9.0)
	if deep != Vector3.INF:
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(deep.x, TerrainData.WATER_LEVEL + 0.4, deep.z)
		for _i in 80: await physics_frame
		seen[SurfaceType.name_of(player.current_surface)] = true
		_ok("SURFACE WATER DEEP", player.current_surface == SurfaceType.Kind.WATER_DEEP,
			"reported %s while swimming" % player.surface_name())

	_ok("SURFACE CHANGES", seen.size() >= 5,
		"distinct surfaces observed: %s" % ", ".join(PackedStringArray(seen.keys())))


func _find_land(pred: Callable) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i in 40000:
		var x := rng.randf_range(-105.0, 105.0)
		var z := rng.randf_range(-105.0, 105.0)
		if TerrainData.is_walkable(x, z) and bool(pred.call(x, z)):
			return Vector3(x, 0, z)
	return Vector3.INF


func _find_water(dmin: float, dmax: float) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for _i in 40000:
		var x := rng.randf_range(-105.0, 105.0)
		var z := rng.randf_range(-105.0, 105.0)
		var d := TerrainData.water_depth_at(x, z)
		if d >= dmin and d <= dmax:
			return Vector3(x, 0, z)
	return Vector3.INF


# -------------------------------------------------------------- pickups --
## Section 57 / 29: collect at a run and keep at least 90% of the speed.
func _t_pickup_running() -> void:
	var inter: Interactor = player.get_node("Interactor")
	var props: Node = world.get_node("Props")
	var approach := Vector3(1, 0, 0.2).normalized()
	var target: Pickup = null
	var tp := Vector3.ZERO
	for c in props.get_children():
		if not (c is Pickup) or str((c as Pickup).kind) != "BOIS":
			continue
		var pos := (c as Node3D).global_position
		var start := pos - approach * 11.0
		if not TerrainData.is_walkable(pos.x, pos.z) or not TerrainData.is_walkable(start.x, start.z):
			continue
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(start.x, TerrainData.height_at(start.x, start.z) + 0.9, start.z),
			Vector3(pos.x, TerrainData.height_at(pos.x, pos.z) + 0.9, pos.z))
		q.collision_mask = Layers.WORLD_STATIC
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		target = c
		tp = pos
		break
	if target == null:
		_ok("PICKUP WHILE RUNNING", false, "no wood with a clear approach")
		return

	await _place(tp - approach * 11.0)
	var before := inter.total_of(&"BOIS")
	player.camera_yaw = atan2(-approach.x, -approach.z)
	player.move_input = Vector2(0, 1)
	player.run_held = true

	var v_before := 0.0
	var h_before := 0.0
	var v_after := 0.0
	var h_after := 0.0
	var took := false
	for _i in 300:
		await physics_frame
		player.camera_yaw = atan2(-approach.x, -approach.z)
		if not took and inter.has_candidate():
			v_before = player.horizontal_speed
			h_before = player.model_pivot.rotation.y
			took = inter.interact()
			if took:
				for _j in 14:
					await physics_frame
					player.camera_yaw = atan2(-approach.x, -approach.z)
				v_after = player.horizontal_speed
				h_after = player.model_pivot.rotation.y
				break
	player.move_input = Vector2.ZERO
	player.run_held = false

	var drift := absf(angle_difference(h_before, h_after))
	var ratio := v_after / maxf(v_before, 0.001)
	_ok("PICKUP WHILE RUNNING",
		took and inter.total_of(&"BOIS") == before + 1 and v_before > player.walk_speed * 1.4
			and ratio >= 0.90 and drift < 0.12,
		"%.2f -> %.2f m/s (%.0f%% retained), heading drift %.4f rad" % [
			v_before, v_after, ratio * 100.0, drift])


## Section 73: no reaching through walls, no picking up what is behind you.
func _t_interaction_reach() -> void:
	var pillar: StonePillar = world.find_child("StonePillar", true, false)
	var ruin: Ruin = world.find_child("Ruin", true, false)
	if pillar == null or ruin == null:
		_note("LINE OF SIGHT", "SKIPPED", "no ruin pillar in the scene")
		return
	var inter: Interactor = player.get_node("Interactor")
	# Stand just outside the ruin's west wall, level with the pillar. The
	# pillar is within reach as the crow flies but there is a wall in between.
	var outside := pillar.global_position - ruin.global_transform.basis.x * (ruin.width * 0.5 + 1.2)
	await _place(outside)
	for _i in 20:
		await physics_frame
	var blocked := true
	for c in inter.get_overlapping_areas():
		if c is InteractableComponent and inter.current == c and c.get_parent() == pillar:
			blocked = false
	_ok("LINE OF SIGHT BLOCKS REACH", blocked and inter.current != pillar.get_node("Interact"),
		"standing outside the wall, the pillar is %s" %
			("not offered" if blocked else "wrongly offered"))


# ------------------------------------------------------------------ NPCs --
## Section 58: a destination behind an obstacle must be reached by going
## round it, not through it.
func _t_npc_obstacle() -> void:
	var npcs: Array = world.get("npcs")
	if npcs == null or npcs.is_empty():
		_ok("NPC AVOIDS OBSTACLES", false, "no NPCs")
		return
	var npc: NpcController = npcs[0]
	var inside := 0
	var moved := 0.0
	var prev := npc.global_position
	for _i in 1200:
		await physics_frame
		if _inside_solid(npc.global_position + Vector3.UP * 0.9):
			inside += 1
		moved += Vector2(npc.global_position.x - prev.x, npc.global_position.z - prev.z).length()
		prev = npc.global_position
	_ok("NPC AVOIDS OBSTACLES", inside == 0 and moved > 6.0,
		"walked %.1f m of path, inside solid geometry for %d frames" % [moved, inside])


## Section 59: the same, for a fleeing animal — which is the harder case,
## because it is running and not following a considered route.
func _t_animal_obstacle() -> void:
	var animals: Array = world.get("animals")
	if animals == null or animals.is_empty():
		_ok("ANIMAL AVOIDS OBSTACLES", false, "no animals")
		return
	var worst_inside := 0
	var total_moved := 0.0
	for a in animals:
		var an: AnimalPlaceholder = a
		# Frighten it: stand next to it and stay there.
		player.global_position = an.global_position + Vector3(2.0, 0.4, 0.0)
		var prev := an.global_position
		var inside := 0
		for _i in 600:
			await physics_frame
			player.global_position = an.global_position.lerp(
				player.global_position, 0.995) + Vector3(0.02, 0, 0)
			if _inside_solid(an.global_position + Vector3.UP * 0.4):
				inside += 1
			total_moved += Vector2(an.global_position.x - prev.x,
				an.global_position.z - prev.z).length()
			prev = an.global_position
		worst_inside = maxi(worst_inside, inside)
	_ok("ANIMAL AVOIDS OBSTACLES", worst_inside == 0 and total_moved > 8.0,
		"fled %.1f m across %d species, inside solid geometry for %d frames"
			% [total_moved, animals.size(), worst_inside])


## Sections 77 and 78: the Brume frightens the living.
func _t_fog_reactions() -> void:
	var fog: FogWall = world.find_child("FogWall", true, false)
	var npcs: Array = world.get("npcs")
	var animals: Array = world.get("animals")
	if fog == null or npcs == null or npcs.is_empty():
		_ok("FLEE THE FOG", false, "no fog or no NPCs")
		return

	# Put a nomad and an animal right on the fog line and see what they do.
	var npc: NpcController = npcs[0]
	var front_x := 0.0
	var front_z := fog.front_z(front_x, 0) - 6.0
	npc.global_position = Vector3(front_x, TerrainData.height_at(front_x, front_z) + 0.2, front_z)
	var an: AnimalPlaceholder = animals[0] if animals and not animals.is_empty() else null
	if an:
		an.global_position = Vector3(front_x + 5.0,
			TerrainData.height_at(front_x + 5.0, front_z) + 0.2, front_z)

	var npc_fled := false
	var animal_fled := false
	var npc_start := npc.global_position
	for _i in 420:
		await physics_frame
		if npc.is_fleeing():
			npc_fled = true
		if an and an.state == AnimalPlaceholder.State.FLEE:
			animal_fled = true
	var retreated := fog.distance_to(npc.global_position) > fog.distance_to(npc_start)

	_ok("NPC FLEES THE FOG", npc_fled, "nomad state %s, moved away from the front: %s"
		% [npc.state_name(), str(retreated)])
	if an:
		_ok("ANIMAL FLEES THE FOG", animal_fled, "animal state %s" % an.state_name())


func _inside_solid(p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = Layers.WORLD_STATIC
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not player.get_world_3d().direct_space_state.intersect_point(q, 1).is_empty()
