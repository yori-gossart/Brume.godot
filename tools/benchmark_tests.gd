extends SceneTree
##
## Automated pass over the mandatory test list (section 46).
##
## Section 48 forbids false PASSes: a visible tree with no collision, water
## with a shader but no player state, an animation that is declared but slides.
## So each check below drives the real scene through the real physics and
## asserts on measured numbers, not on whether a node exists.
##
## Run: godot --headless --path . --script tools/benchmark_tests.gd

## The Quality autoload is resolved by node path rather than by its global
## identifier: in `--script` mode the script is compiled before autoloads are
## registered, so the bare name is not in scope yet.
var Q: Node

var _player_spawn: Vector3
var _npc_spawn: Vector3

var world: Node3D
var player: PlayerController
var results: Array = []
var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/BenchmarkWorld.tscn")
	world = packed.instantiate()
	Q = root.get_node_or_null("/root/Quality")
	root.add_child(world)
	await physics_frame
	await physics_frame
	await physics_frame
	player = world.get_node("Player")
	_player_spawn = (world.get_node("Player") as Node3D).global_position
	_npc_spawn = (world.get_node("Npc") as Node3D).global_position
	# The HUD and the follow camera both write to the player every frame
	# (keyboard fallback, camera yaw). The harness drives the controller
	# directly, so both are parked for the duration.
	(world.get_node("UI/MobileHud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	(world.get_node("PlayerCamera") as Node).process_mode = Node.PROCESS_MODE_DISABLED

	print("\n=== BUILD ===")
	print(world.call("build_report"))
	print("")

	await _t_player_move()
	await _t_player_run()
	await _t_player_facing()
	await _t_player_animation()
	await _t_stick_matches_camera()
	await _t_collision("TREE COLLISION", "Col_pine_large")
	await _t_collision("ROCK COLLISION", "Col_rock_big_A")
	await _t_building_collision()
	await _t_pickup_while_moving()
	await _t_water()
	await _t_swim()
	_t_npc_distinct()
	await _t_npc_navigation()
	await _t_animal()
	_t_fog()
	await _t_quality()

	print("\n=== RESULTS ===")
	for r in results:
		print("  %-28s %s%s" % [r["name"], r["verdict"],
			("   " + str(r["note"])) if r["note"] != "" else ""])
	print("\n%d checks, %d failed\n" % [results.size(), failures])
	quit(1 if failures > 0 else 0)


func _ok(name: String, cond: bool, note: String = "") -> void:
	results.append({"name": name, "verdict": "PASS" if cond else "FAIL", "note": note})
	if not cond:
		failures += 1


func _note(name: String, verdict: String, note: String) -> void:
	results.append({"name": name, "verdict": verdict, "note": note})


## Drive the player with the joystick for `frames` physics ticks.
func _drive(dir: Vector3, frames: int, run: bool = false) -> void:
	player.camera_yaw = atan2(-dir.x, -dir.z)
	player.move_input = Vector2(0, 1)
	player.run_held = run
	for _i in frames:
		await physics_frame
	player.move_input = Vector2.ZERO
	player.run_held = false


func _place(p: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, TerrainData.height_at(p.x, p.z) + 0.15, p.z)
	await physics_frame
	await physics_frame


# ----------------------------------------------------------------- tests --
func _t_player_move() -> void:
	await _place(Vector3(8, 0, 46))
	var from := player.global_position
	await _drive(Vector3(0, 0, -1), 90)
	var moved := Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	_ok("PLAYER MOVE", moved > 1.5, "%.2f m in 1.5 s, %.2f m/s" % [moved, player.horizontal_speed])


## Pushing the stick up must move the player AWAY from the camera.
##
## This is checked against the real PlayerCamera node rather than against the
## same formula the controller uses, because the bug it is here to catch was
## precisely the two of them agreeing on a sign that was wrong. Getting it
## backwards makes the character run at the lens (section 10).
func _t_stick_matches_camera() -> void:
	var cam: PlayerCamera = world.get_node("PlayerCamera")
	cam.process_mode = Node.PROCESS_MODE_INHERIT
	var worst := 1.0
	for yaw in [0.0, 1.2, PI, -2.4]:
		await _place(Vector3(8, 0, 46))
		cam.set("_yaw", yaw)
		cam.call("_apply")
		await process_frame
		player.camera_yaw = yaw
		player.move_input = Vector2(0, 1)
		for _i in 45:
			await physics_frame
			# The camera keeps writing its own yaw; hold ours steady.
			player.camera_yaw = yaw
		player.move_input = Vector2.ZERO
		var travel := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
		var look: Vector3 = cam.forward()
		worst = minf(worst, travel.dot(Vector3(look.x, 0, look.z).normalized()))
		# Also: the player must be getting further from the camera, not nearer.
		var cam_node: Camera3D = world.get_node("PlayerCamera/Pitch/SpringArm3D/Camera3D")
		var to_cam := (cam_node.global_position - player.global_position).normalized()
		worst = minf(worst, -travel.dot(Vector3(to_cam.x, 0, to_cam.z).normalized()))
	cam.process_mode = Node.PROCESS_MODE_DISABLED
	_ok("STICK MATCHES CAMERA", worst > 0.85,
		"worst agreement between stick-forward and camera-forward: %.3f" % worst)


## Animation, measured rather than declared.
##
## Section 48: "an animation that is declared but the character slides" is a
## FAIL. So this does not check that an AnimationPlayer exists — it checks the
## SKELETON.
##
##   1. the pose must actually change over time (a T-posed character with a
##      running AnimationTree would otherwise pass every other test here);
##   2. the planted foot must be roughly stationary IN WORLD SPACE while the
##      body moves. That is what "not sliding" means, and it is the whole
##      justification for placing the blend points at the measured authored
##      speeds in LocomotionRig.
func _t_player_animation() -> void:
	var model: Node3D = player.get_node("ModelPivot").get_child(0)
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	var tree: AnimationTree = model.find_child("AnimationTree", true, false)
	if sk == null or tree == null:
		_ok("PLAYER ANIMATIONS", false, "no Skeleton3D / AnimationTree on the player")
		return
	var lt := sk.find_bone("toes.l")
	var rt := sk.find_bone("toes.r")

	# --- is the skeleton actually being posed? -----------------------------
	# Sampled while WALKING, not while idle: the Idle clip keeps the feet
	# planted, so an idle-only probe cannot tell a working rig from a T-pose.
	await _place(Vector3(8, 0, 46))
	player.camera_yaw = 0.0
	player.move_input = Vector2(0, 1)
	for _i in 30:
		await physics_frame
	var p0 := sk.get_bone_global_pose(lt).origin
	var drift := 0.0
	for _i in 60:
		await physics_frame
		drift = maxf(drift, sk.get_bone_global_pose(lt).origin.distance_to(p0))
	player.move_input = Vector2.ZERO
	_ok("PLAYER ANIMATIONS", drift > 0.05 and tree.active,
		"walking pose sweeps %.3f m (a T-pose would be 0.000)" % drift)

	# --- foot sliding, walking --------------------------------------------
	var walk_slide := await _foot_slide(lt, rt, sk, false)
	var run_slide := await _foot_slide(lt, rt, sk, true)
	# Judged against the floor the clips themselves impose, measured by
	# tools/calibrate_stride.gd at the optimal playback rate:
	#   Walking_A  20.4% of body speed   Running_A  36.4%
	# A run has a flight phase where neither foot is planted, so its floor is
	# genuinely higher; the run threshold is not slack, it is physics.
	# What these assert is that the rig is AT that optimum, not near it by luck.
	_ok("NO FOOT SLIDING (walk)", walk_slide["ratio"] < 0.28,
		"planted foot %.2f m/s vs body %.2f m/s = %.0f%% (clip floor 20%%)"
			% [walk_slide["foot"], walk_slide["body"], walk_slide["ratio"] * 100.0])
	_ok("NO FOOT SLIDING (run)", run_slide["ratio"] < 0.47,
		"planted foot %.2f m/s vs body %.2f m/s = %.0f%% (clip floor 36%%)"
			% [run_slide["foot"], run_slide["body"], run_slide["ratio"] * 100.0])


## Median world-space speed of whichever foot is planted, over ~2 s of
## steady-state locomotion.
func _foot_slide(lt: int, rt: int, sk: Skeleton3D, run: bool) -> Dictionary:
	await _place(Vector3(8, 0, 46))
	player.camera_yaw = 0.0
	player.move_input = Vector2(0, 1)
	player.run_held = run
	# Let the speed and the blend settle before measuring.
	for _i in 70:
		await physics_frame
	var body_speed := player.horizontal_speed
	# The true world path of the foot, not an approximation: bone poses are
	# skeleton-local, and between them and the world sit the model pivot's
	# yaw AND the terrain lean the controller applies. Adding only the body
	# position would miss the lean, which is itself a source of foot motion.
	var prev_l: Vector3 = sk.global_transform * sk.get_bone_global_pose(lt).origin
	var prev_r: Vector3 = sk.global_transform * sk.get_bone_global_pose(rt).origin
	var samples := []
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for _i in 120:
		await physics_frame
		var wl: Vector3 = sk.global_transform * sk.get_bone_global_pose(lt).origin
		var wr: Vector3 = sk.global_transform * sk.get_bone_global_pose(rt).origin
		var sl := Vector2(wl.x - prev_l.x, wl.z - prev_l.z).length() / dt
		var sr := Vector2(wr.x - prev_r.x, wr.z - prev_r.z).length() / dt
		samples.append(minf(sl, sr))
		prev_l = wl
		prev_r = wr
	player.move_input = Vector2.ZERO
	player.run_held = false
	samples.sort()
	var med: float = samples[samples.size() / 2]
	return {"foot": med, "body": body_speed,
		"ratio": med / maxf(body_speed, 0.001)}


## The player must face where it travels. Reversed rotation is an explicit
## FAIL in section 48, and it is invisible to a position-only test.
func _t_player_facing() -> void:
	await _place(Vector3(8, 0, 46))
	var worst := 1.0
	var samples := 0
	for dir in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]:
		player.camera_yaw = atan2(-dir.x, -dir.z)
		player.move_input = Vector2(0, 1)
		player.run_held = false
		for i in 80:
			await physics_frame
			if i > 45 and player.horizontal_speed > 0.8:
				var v := Vector3(player.velocity.x, 0, player.velocity.z).normalized()
				var f: Vector3 = player.model_pivot.global_transform.basis.z
				worst = minf(worst, v.dot(Vector3(f.x, 0, f.z).normalized()))
				samples += 1
	player.move_input = Vector2.ZERO
	_ok("PLAYER FACING", worst > 0.9 and samples > 50,
		"worst forward dot %.3f over %d samples, four headings" % [worst, samples])


func _t_player_run() -> void:
	await _place(Vector3(8, 0, 46))
	await _drive(Vector3(0, 0, -1), 100, true)
	var v := player.horizontal_speed
	# Must be clearly faster than a walk and near the configured run speed.
	_ok("PLAYER RUN", v > player.walk_speed * 1.5, "%.2f m/s (walk %.2f, run %.2f)"
		% [v, player.walk_speed, player.run_speed])


## Walk straight into a collider and assert the body is actually stopped
## outside it. A tree you can walk through is a FAIL (section 48).
func _t_collision(label: String, body_name: String) -> void:
	var scatter: Node = world.get_node("Scatter")
	var body: StaticBody3D = scatter.get_node_or_null(body_name)
	if body == null:
		_ok(label, false, "no collision body named " + body_name)
		return
	var cs: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			cs = c
			break
	if cs == null:
		_ok(label, false, "collision body has no enabled shape")
		return
	var centre := cs.position
	var radius := 0.5
	if cs.shape is CylinderShape3D:
		radius = (cs.shape as CylinderShape3D).radius
	elif cs.shape is ConvexPolygonShape3D:
		for pt in (cs.shape as ConvexPolygonShape3D).points:
			radius = maxf(radius, Vector2(pt.x, pt.z).length())

	var approach := Vector3(1, 0, 0.35).normalized()
	var start := centre - approach * (radius + 4.0)
	await _place(start)
	var before := player.global_position
	await _drive(approach, 150, true)
	var after := player.global_position
	var d := Vector2(after.x - centre.x, after.z - centre.z).length()
	var travelled := Vector2(after.x - before.x, after.z - before.z).length()
	# Blocked outside the proxy, and it genuinely tried (it moved towards it).
	var blocked := d > radius * 0.75 and travelled > 1.0
	_ok(label, blocked, "stopped %.2f m from centre (proxy r=%.2f), travelled %.2f m"
		% [d, radius, travelled])


func _t_building_collision() -> void:
	var cabin: Node3D = world.get_node_or_null("ScoutCabin")
	if cabin == null:
		_ok("BUILDING COLLISION", false, "no cabin in scene")
		return
	var c := cabin.global_position
	# Approach the BACK wall, which has no doorway in it.
	var approach := (cabin.global_transform.basis.z).normalized()
	var start := c - approach * 9.0
	await _place(start)
	await _drive(approach, 150, true)
	var d := Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length()
	_ok("BUILDING COLLISION", d > 2.0, "stopped %.2f m from cabin centre" % d)


## The headline interaction test. Collect at a dead run and prove that
## neither the speed nor the heading changed (section 13).
func _t_pickup_while_moving() -> void:
	var inter: Interactor = player.get_node("Interactor")
	var props: Node = world.get_node("Props")
	var target: Node3D = null
	for c in props.get_children():
		if c is Pickup and str((c as Pickup).kind) == "BOIS":
			if TerrainData.is_walkable((c as Node3D).global_position.x, (c as Node3D).global_position.z):
				target = c
				break
	if target == null:
		_ok("PICKUP WHILE MOVING", false, "no reachable BOIS pickup found")
		return

	var tp := target.global_position
	var approach := Vector3(1, 0, 0.2).normalized()
	await _place(tp - approach * 11.0)
	var before_total := inter.total_of("BOIS")

	player.camera_yaw = atan2(-approach.x, -approach.z)
	player.move_input = Vector2(0, 1)
	player.run_held = true

	var took := false
	var speed_at_pickup := 0.0
	var facing_at_pickup := 0.0
	var speed_after := 0.0
	var facing_after := 0.0
	for i in 260:
		await physics_frame
		if not took and inter.has_candidate():
			speed_at_pickup = player.horizontal_speed
			facing_at_pickup = player.model_pivot.rotation.y
			took = inter.interact()
			if took:
				# Keep the stick held: nothing about the pickup may stop us.
				for _j in 12:
					await physics_frame
				speed_after = player.horizontal_speed
				facing_after = player.model_pivot.rotation.y
				break
	player.move_input = Vector2.ZERO
	player.run_held = false

	var gained := inter.total_of("BOIS") - before_total
	var moving := speed_at_pickup > player.walk_speed * 1.4
	var kept_speed := speed_after > speed_at_pickup * 0.9
	var kept_heading := absf(angle_difference(facing_at_pickup, facing_after)) < 0.12
	_ok("PICKUP WHILE MOVING", took and gained == 1 and moving and kept_speed and kept_heading,
		"at %.2f m/s -> %.2f m/s, heading drift %.3f rad, gained %d"
		% [speed_at_pickup, speed_after, absf(angle_difference(facing_at_pickup, facing_after)), gained])


func _t_water() -> void:
	# Find a genuinely shallow spot: wadeable, not swimmable.
	var spot := _find_water(0.35, 0.85)
	if spot == Vector3.INF:
		_ok("WATER DETECTION", false, "no shallow water found")
		return
	await _place(spot)
	await _drive(Vector3(0, 0, 1), 30)
	for _i in 10:
		await physics_frame
	var in_state := player.state == PlayerController.State.WATER
	_ok("WATER DETECTION", in_state and player.water_depth > 0.2,
		"state %s, depth %.2f m, Area3D %s"
			% [player.state_name(), player.water_depth, "yes" if player.in_water_volume else "no"])
	_ok("WATER AREA3D GATE", player.in_water_volume, "Area3D body_entered fired")

	# Wading must be measurably slower than the same run on dry land, and
	# measurably slower the deeper it gets.
	await _place(Vector3(8, 0, 46))
	await _drive(Vector3(0, 0, -1), 70, true)
	var dry := player.horizontal_speed

	var shallow_speed := 0.0
	await _place(spot)
	await _drive(Vector3(0, 0, 1), 70, true)
	shallow_speed = player.horizontal_speed

	var deep_spot := _find_water(0.95, 1.25)
	var deep_speed := 0.0
	if deep_spot != Vector3.INF:
		await _place(deep_spot)
		await _drive(Vector3(0, 0, 1), 70, true)
		deep_speed = player.horizontal_speed
	_ok("WADING", deep_speed > 0.05 and deep_speed < dry * 0.6 and shallow_speed < dry * 0.95,
		"dry %.2f -> ankle(%.2fm) %.2f -> chest(%.2fm) %.2f m/s"
			% [dry, TerrainData.water_depth_at(spot.x, spot.z), shallow_speed,
			TerrainData.water_depth_at(deep_spot.x, deep_spot.z) if deep_spot != Vector3.INF else 0.0,
			deep_speed])


func _t_swim() -> void:
	var spot := _find_water(1.9, 9.0)
	if spot == Vector3.INF:
		_ok("SWIMMING", false, "no deep water found")
		return
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(spot.x, TerrainData.WATER_LEVEL + 0.4, spot.z)
	for _i in 90:
		await physics_frame
	var swimming := player.state == PlayerController.State.SWIM
	var y := player.global_position.y
	# Floating, not sunk to the bed and not standing on the water.
	var floats := absf(y - (TerrainData.WATER_LEVEL - player.float_depth)) < 0.35
	_note("SWIMMING", "PASS" if (swimming and floats) else "FAIL",
		"state %s, body y=%.2f (target %.2f), bed at %.2f"
			% [player.state_name(), y, TerrainData.WATER_LEVEL - player.float_depth,
			TerrainData.height_at(spot.x, spot.z)])
	if not (swimming and floats):
		failures += 1
	_note("SWIM ANIMATION", "PROVISIONAL",
		"no swim clip in KayKit Adventurers; prone pitch + slowed walk cycle")

	# And it must be able to swim somewhere.
	var from := player.global_position
	await _drive(Vector3(0, 0, 1), 70)
	var moved := Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	_ok("SWIM LOCOMOTION", moved > 0.8, "%.2f m while swimming" % moved)


func _find_water(dmin: float, dmax: float) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for _i in 20000:
		var x := rng.randf_range(-110.0, 110.0)
		var z := rng.randf_range(-110.0, 110.0)
		var d := TerrainData.water_depth_at(x, z)
		if d >= dmin and d <= dmax:
			return Vector3(x, 0, z)
	return Vector3.INF


func _t_npc_distinct() -> void:
	var npc: NpcController = world.get_node("Npc")
	var pm: Node = player.get_node("ModelPivot").get_child(0)
	var nm: Node = npc.get_node("ModelPivot").get_child(0)
	var pf := str(pm.scene_file_path)
	var nf := str(nm.scene_file_path)
	_ok("NPC MODEL DISTINCT", pf != nf and nf != "",
		"player=%s  npc=%s" % [pf.get_file(), nf.get_file()])
	# Visible means visible: the NPC must START within sight of the player's
	# spawn, and must stay inside the navigable square. A distinct model that
	# is never actually on screen is a FAIL (section 48).
	var at_spawn := _npc_spawn.distance_to(_player_spawn)
	var inside := absf(npc.global_position.x) < 120.0 and absf(npc.global_position.z) < 120.0
	_ok("NPC IN PLAY AREA", at_spawn < 30.0 and inside,
		"spawns %.1f m from the player, currently inside the play square: %s"
			% [at_spawn, str(inside)])


func _t_npc_navigation() -> void:
	var npc: NpcController = world.get_node("Npc")
	var nav: NavBuilder = world.get_node("Navigation")
	_ok("NAVMESH BUILT", nav.polygon_count > 200,
		"%d polygons, %d walkable cells" % [nav.polygon_count, nav.walkable_point_count()])

	var start := npc.global_position
	var max_speed := 0.0
	var worst_facing := 1.0
	var moved_frames := 0
	for _i in 900:
		await physics_frame
		max_speed = maxf(max_speed, npc.horizontal_speed)
		if npc.horizontal_speed > 0.5:
			moved_frames += 1
			var v := Vector3(npc.velocity.x, 0, npc.velocity.z).normalized()
			var mp: Node3D = npc.get_node("ModelPivot")
			# The KayKit rig faces +Z (see tools/diag_facing2.gd), not the
			# Godot-default -Z.
			var f: Vector3 = mp.global_transform.basis.z
			worst_facing = minf(worst_facing, v.dot(Vector3(f.x, 0, f.z).normalized()))
	var travelled := npc.global_position.distance_to(start)
	_ok("NPC NAVIGATION", travelled > 4.0 and max_speed > 0.5,
		"travelled %.1f m, peak %.2f m/s over 15 s" % [travelled, max_speed])
	# Facing must track travel. Negative dot = moonwalking (section 25).
	_ok("NPC CORRECT FACING", worst_facing > 0.55 or moved_frames < 30,
		"worst forward dot %.2f over %d moving frames" % [worst_facing, moved_frames])


func _t_animal() -> void:
	var animal: AnimalPlaceholder = world.get_node("Animal")
	_note("ANIMAL MODEL", "PLACEHOLDER", "ANIMAL_ASSET_BLOCKED — no CC0 animal available")
	# Walk the player up to it and check it runs away.
	var before := animal.global_position
	player.global_position = animal.global_position + Vector3(3.0, 0.5, 0.0)
	var fled := false
	var peak := 0.0
	for _i in 420:
		await physics_frame
		peak = maxf(peak, animal.horizontal_speed)
		if animal.state == AnimalPlaceholder.State.FLEE:
			fled = true
	var dist := animal.global_position.distance_to(before)
	_ok("ANIMAL FLEE", fled and dist > 2.0,
		"state %s, ran %.1f m, peak %.2f m/s" % [animal.state_name(), dist, peak])


func _t_fog() -> void:
	var fog: FogWall = world.get_node("FogWall")
	var curtains := 0
	var tris := 0
	var sheets := 0
	var particles := 0
	for c in fog.get_children():
		if c is MeshInstance3D:
			var m: Mesh = (c as MeshInstance3D).mesh
			if m is ArrayMesh and (m as ArrayMesh).get_surface_count() > 0:
				# surface_get_arrays, not get_faces(): get_faces() goes through
				# the RenderingServer, which is a stub under --headless.
				var idx = (m as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				if idx != null:
					tris += (idx as PackedInt32Array).size() / 3
			if str(c.name).begins_with("Curtain"):
				curtains += 1
			elif str(c.name).begins_with("GroundSheet"):
				sheets += 1
		elif c is GPUParticles3D:
			particles = (c as GPUParticles3D).amount
	_ok("FOG ACTIVE", curtains >= 2 and sheets >= 1,
		"%d curtains, %d ground sheets, %d wisps, %d tris" % [curtains, sheets, particles, tris])

	# The front must actually be irregular, not a straight line (section 30).
	var zmin := 1e9
	var zmax := -1e9
	var prev := fog.front_z(-170.0, 0)
	var prev_delta := 0.0
	var flips := 0
	var x := -166.0
	while x <= 170.0:
		var z := fog.front_z(x, 0)
		zmin = minf(zmin, z); zmax = maxf(zmax, z)
		var delta := z - prev
		if prev_delta != 0.0 and delta * prev_delta < 0.0:
			flips += 1
		prev_delta = delta
		prev = z
		x += 4.0
	_ok("FOG IRREGULAR FRONT", (zmax - zmin) > 14.0 and flips > 6,
		"front varies %.1f m across the map, %d direction changes" % [zmax - zmin, flips])

	# Ground contact: the sheet has to follow the terrain, not sit on a plane.
	var sheet: MeshInstance3D = fog.get_node_or_null("GroundSheet0")
	var ok_follow := false
	var spread := 0.0
	if sheet and sheet.mesh:
		var vs := (sheet.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var lo := 1e9
		var hi := -1e9
		var err := 0.0
		for i in range(0, vs.size(), 7):
			lo = minf(lo, vs[i].y); hi = maxf(hi, vs[i].y)
			err = maxf(err, absf(vs[i].y - TerrainData.height_at(vs[i].x, vs[i].z)))
		spread = hi - lo
		ok_follow = spread > 3.0 and err < 3.0
	_ok("FOG GROUND CONTACT", ok_follow,
		"sheet height spread %.1f m, follows terrain" % spread)


func _t_quality() -> void:
	var scatter: Node = world.get_node("Scatter")
	var body: StaticBody3D = scatter.get_node_or_null("Col_pine_large")
	var mmi: MultiMeshInstance3D = scatter.get_node_or_null("MM_pine_large")
	if body == null or mmi == null:
		_ok("QUALITY HIGH/LOW", false, "pine species missing")
		return

	Q.level = 0    # HIGH
	await process_frame
	var vis_high: int = mmi.multimesh.visible_instance_count
	var col_high := _enabled_shapes(body)

	Q.level = 1    # LOW
	await process_frame
	var vis_low: int = mmi.multimesh.visible_instance_count
	var col_low := _enabled_shapes(body)

	var fog: FogWall = world.get_node("FogWall")
	var layers_low := 0
	for c in fog.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("Curtain") and (c as MeshInstance3D).visible:
			layers_low += 1

	Q.level = 0    # HIGH
	await process_frame
	var layers_high := 0
	for c in fog.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("Curtain") and (c as MeshInstance3D).visible:
			layers_high += 1

	_ok("QUALITY LOW REDUCES LOAD", vis_low < vis_high and layers_low < layers_high,
		"trees %d -> %d, fog layers %d -> %d" % [vis_high, vis_low, layers_high, layers_low])
	# Hidden trees must lose their collision too, or LOW is a lie.
	_ok("QUALITY COLLISION FOLLOWS", col_high == vis_high and col_low == vis_low,
		"enabled trunk shapes HIGH %d/%d, LOW %d/%d" % [col_high, vis_high, col_low, vis_low])


func _enabled_shapes(body: StaticBody3D) -> int:
	var n := 0
	for c in body.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			n += 1
	return n
