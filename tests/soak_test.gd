extends SceneTree
##
## Long run and restart soak (section 81).
##
## Five full builds of the world, each driven for three simulated minutes of
## play — fifteen minutes in total — while the player cycles between land and
## water, collects, and the NPCs and animals go about their business.
##
## What it is actually watching for is the thing that does not show up in a
## two-minute test: node and object counts that never come back down. Each
## cycle records them after the world is torn down, and the last cycle is
## compared with the first. A world that leaks a few hundred nodes per load
## is fine for a demo and fatal for a game you leave running on a phone.

const CYCLES := 5
const MINUTES_PER_CYCLE := 3.0

var _report: Array = []
var _checks: Array = []
var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var baseline_nodes := 0
	var baseline_objects := 0
	var packed: PackedScene = load("res://scenes/testing/ArtPhysicsShowcase.tscn")

	for cycle in CYCLES:
		var world: Node3D = packed.instantiate()
		root.add_child(world)
		for _i in 6:
			await physics_frame

		var player: PlayerController = world.get_node("Player")
		(world.get_node("UI/MobileHud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(world.get_node("PlayerCamera") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		var inter: Interactor = player.get_node("Interactor")

		var frames := int(MINUTES_PER_CYCLE * 60.0 * 60.0)
		var land := _find_kind(0)
		var shallow := _find_kind(1)
		var deep := _find_kind(2)

		var states := {}
		var surfaces := {}
		var picked := 0
		var leg := 0
		for f in frames:
			# Every ten seconds, throw the player at a different environment:
			# dry land, a ford, deep water. Repeatedly crossing the state
			# boundaries is where a state machine leaks or wedges.
			if f % 600 == 0:
				leg += 1
				var dest: Vector3 = [land, shallow, deep][leg % 3]
				if dest != Vector3.INF:
					player.velocity = Vector3.ZERO
					var y := maxf(TerrainData.height_at(dest.x, dest.z) + 0.3,
						TerrainData.WATER_LEVEL + 0.4)
					player.global_position = Vector3(dest.x, y, dest.z)
				player.camera_yaw = randf() * TAU
				player.move_input = Vector2(0, 1)
				player.run_held = (leg % 2 == 0)
			await physics_frame
			states[player.state_name()] = true
			surfaces[player.surface_name()] = true
			if inter.has_candidate() and inter.interact():
				picked += 1

		var nodes_live := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		world.queue_free()
		# Let the frees actually happen before measuring.
		for _i in 20:
			await process_frame

		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if cycle == 0:
			baseline_nodes = nodes
			baseline_objects = objects

		var line := "cycle %d: %.0f min, states %s, %d surfaces, %d pickups" % [
			cycle + 1, MINUTES_PER_CYCLE, str(states.keys()), surfaces.size(), picked]
		line += "  |  nodes %d live -> %d freed (baseline %d)" % [
			int(nodes_live), nodes, baseline_nodes]
		_report.append(line)

		if cycle == CYCLES - 1:
			var node_growth := nodes - baseline_nodes
			var object_growth := objects - baseline_objects
			# A handful of nodes drifting is noise; hundreds is a leak.
			_check("NO NODE LEAK", absi(node_growth) < 200,
				"after %d builds: %+d nodes, %+d objects against the first cycle"
					% [CYCLES, node_growth, object_growth])
			_check("STATES EXERCISED", states.size() >= 3,
				"player states seen in the last cycle: %s" % str(states.keys()))
			_check("SURFACES EXERCISED", surfaces.size() >= 3,
				"surfaces seen in the last cycle: %s" % str(surfaces.keys()))

	print("\n=== SOAK (%d builds x %.0f simulated minutes) ===" % [CYCLES, MINUTES_PER_CYCLE])
	for l in _report:
		print("  " + str(l))
	print("")
	for l in _checks:
		print("  " + str(l))
	print("\n%d checks, %d failed\n" % [_checks.size(), _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, cond: bool, note: String) -> void:
	_checks.append("%-22s %-5s %s" % [name, "PASS" if cond else "FAIL", note])
	if not cond:
		_failures += 1


## 0 = dry land, 1 = a ford, 2 = swimmable water.
func _find_kind(kind: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + kind
	for _i in 30000:
		var x := rng.randf_range(-100.0, 100.0)
		var z := rng.randf_range(-100.0, 100.0)
		var d := TerrainData.water_depth_at(x, z)
		match kind:
			0:
				if TerrainData.is_walkable(x, z) and TerrainData.height_at(x, z) > TerrainData.WATER_LEVEL + 2.0:
					return Vector3(x, 0, z)
			1:
				if d > 0.3 and d < 0.8:
					return Vector3(x, 0, z)
			_:
				if d > 2.0:
					return Vector3(x, 0, z)
	return Vector3.INF
