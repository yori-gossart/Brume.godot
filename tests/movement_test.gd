extends SceneTree
##
## THE MOVEMENT AUDIT — NOMADSLAND 0.2.1 (sections 37 to 44).
##
## Same rule as every other suite in this project: NOTHING HERE INSPECTS A
## NODE. Section 47 of the 0.2.1 brief is explicit that a jump is not proved
## by the existence of a jump_height export, and section 47's ban on false
## passes is the reason every number below is measured off the real
## CharacterBody3D running under the real physics server.
##
## What is measured:
##
##   speed      5 seconds of holding the stick, per tier, on a corridor that
##              was verified clear first (section 37)
##   jump       height, apex time, total airtime, and the tap-versus-hold
##              difference (sections 38, 39)
##   coyote     a jump pressed AFTER walking off a ledge (section 40)
##   buffer     a jump pressed BEFORE touching down (section 40)
##   steps      a 25 cm obstacle must be walked over; an 80 cm one must not
##              (section 14)
##   slopes     a gentle slope is climbed, a cliff is not (section 16)
##   openings   every hole you can see in a building, walked through for real
##              (sections 18 to 21)
##   bridge     crossed, jumped on, and jumped off into the river (section 22)
##   water      entered by jumping, swum, and left on foot (sections 30 to 32)
##   speed+     pickups and interactions at a dead sprint (sections 26, 29)
##
## The obstacles for the step, slope and ledge checks are built BY THIS TEST
## on flat ground, not taken from the world: a 25 cm kerb has to be exactly
## 25 cm for the answer to mean anything, and the world does not contain one.

var world: Node3D
var player: PlayerController
var cfg: PlayerMovementConfig
var rig_root: Node3D                  ## the test's own props live under here

var checks: Array = []
var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	world = (load("res://scenes/testing/ArtPhysicsShowcase.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _i in 5:
		await physics_frame
	player = world.get_node("Player")
	cfg = player.movement
	(world.get_node("UI/MobileHud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	(world.get_node("PlayerCamera") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	rig_root = Node3D.new()
	rig_root.name = "TestRig"
	world.add_child(rig_root)

	print("\n=== MOVEMENT AUDIT — NOMADSLAND 0.2.1 ===\n")

	await _t_config()
	await _t_speed_tiers()
	await _t_jump()
	await _t_variable_jump()
	await _t_coyote()
	await _t_buffer()
	await _t_step_over()
	await _t_slopes()
	await _t_openings()
	await _t_bridge()
	await _t_water()
	await _t_sprint_interaction()
	await _t_doors_at_speed()
	await _t_mobile_ui()

	print("\n=== RESULTS ===")
	for c in checks:
		print("  %-30s %-6s %s" % [c["name"], "PASS" if c["ok"] else "FAIL", c["note"]])
	print("\n%d checks, %d failed\n" % [checks.size(), failures])
	quit(1 if failures > 0 else 0)


func _ok(name: String, cond: bool, note: String) -> void:
	checks.append({"name": name, "ok": cond, "note": note})
	if not cond:
		failures += 1


# ======================================================== harness =========
## Put the player somewhere, at rest, and let the physics settle.
func _place(p: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.move_input = Vector2.ZERO
	player.run_held = false
	player.jump_held = false
	player.global_position = p
	for _i in 8:
		await physics_frame


## Hold the stick along `yaw` for `frames` physics frames.
func _hold(yaw: float, mag: float, run: bool, frames: int) -> void:
	player.camera_yaw = yaw
	player.run_held = run
	player.move_input = Vector2(0, mag)
	for _i in frames:
		await physics_frame
		player.camera_yaw = yaw
	player.move_input = Vector2.ZERO
	player.run_held = false


func _inside_solid(p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = Layers.WORLD_STATIC
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not player.get_world_3d().direct_space_state.intersect_point(q, 1).is_empty()


## A patch of ground flat enough that a jump measured on it means something.
func _flat_spot() -> Vector3:
	var best := Vector3.INF
	var best_var := INF
	for gx in 28:
		for gz in 28:
			var x := lerpf(-55.0, 55.0, gx / 27.0)
			var z := lerpf(-55.0, 55.0, gz / 27.0)
			if not TerrainData.is_walkable(x, z) or TerrainData.is_water(x, z):
				continue
			var h := TerrainData.height_at(x, z)
			var spread := 0.0
			for o: Vector2 in [Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2),
					Vector2(0, -1.2), Vector2(2.4, 0), Vector2(0, 2.4)]:
				spread = maxf(spread, absf(TerrainData.height_at(x + o.x, z + o.y) - h))
			if TerrainData.water_depth_at(x, z) > 0.0:
				continue
			if _inside_solid(Vector3(x, h + 0.9, z)) or _inside_solid(Vector3(x, h + 0.2, z)):
				continue
			if spread < best_var:
				best_var = spread
				best = Vector3(x, h + 0.05, z)
	return best


## A start point and heading with `length` metres of clear, dry, walkable
## ground in front of it. Verified by sampling, not assumed — a five-second
## sprint covers a third of the map and will find a tree if one is there.
func _find_run(length: float) -> Dictionary:
	var best := {}
	var best_slope := INF
	for gx in 22:
		for gz in 22:
			var x := lerpf(-58.0, 58.0, gx / 21.0)
			var z := lerpf(-58.0, 58.0, gz / 21.0)
			for a in 16:
				var yaw := TAU * a / 16.0
				var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
				var ok := true
				var slope := 0.0
				var steps := int(length / 1.5)
				var h0 := TerrainData.height_at(x, z)
				for i in range(steps + 1):
					var p := Vector3(x, 0, z) + dir * (i * 1.5)
					if absf(p.x) > 62.0 or absf(p.z) > 62.0:
						ok = false
						break
					if not TerrainData.is_walkable(p.x, p.z) or TerrainData.is_water(p.x, p.z):
						ok = false
						break
					var h := TerrainData.height_at(p.x, p.z)
					slope = maxf(slope, absf(h - h0) / maxf(i * 1.5, 1.0))
					# Chest height and knee height both have to be clear, or
					# the run meets a wall it can step onto and the distance
					# stops meaning "how fast is the player".
					if _inside_solid(Vector3(p.x, h + 0.9, p.z)) \
							or _inside_solid(Vector3(p.x, h + 0.25, p.z)):
						ok = false
						break
				if not ok:
					continue
				if slope < best_slope:
					best_slope = slope
					best = {"start": Vector3(x, TerrainData.height_at(x, z) + 0.05, z),
						"yaw": yaw, "slope": slope}
	return best


## Build a solid box in the world, for the test's own obstacles.
func _block(centre: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD_STATIC
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.position = centre
	rig_root.add_child(b)
	return b


func _clear_rig() -> void:
	for c in rig_root.get_children():
		rig_root.remove_child(c)
		c.queue_free()
	await physics_frame


# ====================================================== section 36 ========
func _t_config() -> void:
	var bad := cfg.out_of_spec()
	_ok("CONFIG WITHIN SPEC", bad.is_empty(),
		"every movement number inside the brief's bands" if bad.is_empty()
			else "; ".join(bad))
	# Section 36 is about there being ONE place. If the controller still
	# carried its own copies, these would be able to disagree.
	_ok("ONE SOURCE OF TRUTH",
		is_equal_approx(player.walk_speed, cfg.walk_speed)
			and is_equal_approx(player.run_speed, cfg.run_speed)
			and is_equal_approx(player.sprint_speed, cfg.sprint_speed),
		"controller reads walk/run/sprint straight from the config: %.2f / %.2f / %.2f"
			% [player.walk_speed, player.run_speed, player.sprint_speed])


# ================================================== sections 2, 3, 37 =====
func _t_speed_tiers() -> void:
	var run := _find_run(46.0)
	if run.is_empty():
		_ok("SPEED TIERS", false, "no 46 m clear corridor found on the map")
		return
	# 0.2's numbers, for the comparison the brief actually cares about.
	const OLD_WALK := 1.5
	const OLD_RUN := 4.8
	var tiers := [
		{"name": "WALK", "mag": 1.0, "run": false, "want": cfg.walk_speed},
		{"name": "RUN", "mag": 0.85, "run": true, "want": cfg.run_speed},
		{"name": "SPRINT", "mag": 1.0, "run": true, "want": cfg.sprint_speed},
	]
	var measured := {}
	for t: Dictionary in tiers:
		await _place(run["start"])
		var from := player.global_position
		var tier_seen := ""
		# 5 seconds at 60 Hz.
		player.camera_yaw = run["yaw"]
		player.run_held = bool(t["run"])
		player.move_input = Vector2(0, float(t["mag"]))
		var top := 0.0
		for _i in 300:
			await physics_frame
			player.camera_yaw = run["yaw"]
			top = maxf(top, player.horizontal_speed)
			if player.horizontal_speed > 0.5:
				tier_seen = player.tier_name()
		player.move_input = Vector2.ZERO
		player.run_held = false
		var d := Vector2(player.global_position.x - from.x,
			player.global_position.z - from.z).length()
		measured[t["name"]] = d
		var want: float = t["want"]
		# The band allows for the acceleration ramp at the start (about 1.3 m
		# at the top tier) and for the slope penalty on ground that is clear
		# but not billiard-flat.
		var lo := want * 5.0 * 0.82
		var hi := want * 5.0 * 1.06
		_ok("5 s AT %s" % t["name"], d > lo and d < hi,
			"%.1f m in 5 s = %.2f m/s (target %.2f, top %.2f, reported %s)"
				% [d, d / 5.0, want, top, tier_seen])

	_ok("FASTER THAN 0.2",
		float(measured.get("WALK", 0.0)) > OLD_WALK * 5.0 * 1.8
			and float(measured.get("SPRINT", 0.0)) > OLD_RUN * 5.0 * 1.4,
		"walk %.1f m vs 0.2's %.1f m; sprint %.1f m vs 0.2's run %.1f m"
			% [measured.get("WALK", 0.0), OLD_WALK * 5.0,
				measured.get("SPRINT", 0.0), OLD_RUN * 5.0])


# ============================================== sections 9, 11, 38, 39 ====
func _t_jump() -> void:
	var spot := _flat_spot()
	if spot == Vector3.INF:
		_ok("JUMP HEIGHT", false, "no flat ground found")
		return
	var m := await _measure_jump(spot, true)
	_ok("JUMP HEIGHT", m["height"] > 1.05 and m["height"] < 1.45,
		"rose %.2f m from a standing start (spec 1.1 .. 1.4, config %.2f)"
			% [m["height"], cfg.jump_height])
	_ok("JUMP APEX TIME", m["apex"] > 0.32 and m["apex"] < 0.48,
		"%.3f s from leaving the ground to the top (spec 0.35 .. 0.45)" % m["apex"])
	_ok("JUMP AIRTIME", m["air"] > 0.55 and m["air"] < 1.1,
		"%.3f s off the ground in total; fall reported as %.2f m"
			% [m["air"], m["fall"]])
	_ok("JUMP STATES SEEN",
		m["states"].has("JUMP") and m["states"].has("FALL") and m["states"].has("LAND"),
		"air states during one jump: %s" % str(m["states"]))

	# Section 8: a jump must not cost you your speed.
	await _place(spot)
	var run := _find_run(22.0)
	var yaw: float = run["yaw"] if not run.is_empty() else 0.0
	if not run.is_empty():
		await _place(run["start"])
	player.camera_yaw = yaw
	player.run_held = true
	player.move_input = Vector2(0, 1)
	for _i in 90:
		await physics_frame
		player.camera_yaw = yaw
	var before := player.horizontal_speed
	player.press_jump()
	var low := before
	for _i in 40:
		await physics_frame
		player.camera_yaw = yaw
		if not player.is_grounded:
			low = minf(low, player.horizontal_speed)
	player.release_jump()
	player.move_input = Vector2.ZERO
	player.run_held = false
	_ok("JUMP KEEPS MOMENTUM", before > 3.0 and low > before * 0.9,
		"%.2f m/s before take-off, %.2f m/s at the worst point in the air (%.0f%%)"
			% [before, low, low / maxf(before, 0.01) * 100.0])


## One standing jump, fully instrumented.
func _measure_jump(spot: Vector3, hold: bool) -> Dictionary:
	await _place(spot)
	var y0 := player.global_position.y
	var states := []
	player.press_jump()
	var peak := y0
	var airborne_frames := 0
	var apex_frames := 0
	var rising := true
	var left_ground := false
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for i in 180:
		await physics_frame
		if hold:
			player.jump_held = true
		elif i == 4:
			player.release_jump()
		var s := player.air_name()
		if not states.has(s):
			states.append(s)
		if not player.is_grounded:
			left_ground = true
			airborne_frames += 1
			if rising:
				if player.global_position.y > peak:
					peak = player.global_position.y
					apex_frames = airborne_frames
				elif player.velocity.y <= 0.0:
					rising = false
		elif left_ground and airborne_frames > 4:
			break
	player.release_jump()
	return {
		"height": peak - y0,
		"apex": apex_frames * dt,
		"air": airborne_frames * dt,
		"fall": player.last_fall_distance,
		"states": states,
	}


# ====================================================== section 10 ========
func _t_variable_jump() -> void:
	var spot := _flat_spot()
	if spot == Vector3.INF:
		return
	var held := await _measure_jump(spot, true)
	var tapped := await _measure_jump(spot, false)
	_ok("VARIABLE JUMP HEIGHT",
		tapped["height"] < held["height"] * 0.75 and tapped["height"] > 0.12,
		"tap %.2f m vs hold %.2f m (%.0f%% of a full jump)"
			% [tapped["height"], held["height"],
				tapped["height"] / maxf(held["height"], 0.01) * 100.0])


# ====================================================== section 13 ========
## COYOTE TIME. Walk off a ledge, do nothing for 0.08 s, THEN press jump.
## Without coyote time that press does nothing and the player drops; with it,
## the character leaves the ledge climbing.
func _t_coyote() -> void:
	var spot := _flat_spot()
	if spot == Vector3.INF:
		_ok("COYOTE TIME", false, "no flat ground found")
		return
	await _clear_rig()
	# A 2 m high plinth with a clean edge, built for the purpose.
	var top_y := spot.y + 2.0
	_block(Vector3(spot.x, top_y - 1.0, spot.z), Vector3(7.0, 2.0, 7.0))
	await physics_frame

	var results := {}
	for delay: float in [0.08, 0.40]:
		await _place(Vector3(spot.x - 2.6, top_y + 0.25, spot.z))
		var yaw := atan2(-1.0, 0.0)              # heading towards +x
		player.camera_yaw = yaw
		player.move_input = Vector2(0, 1)
		# Walk to the edge and off it.
		var off_at := -1
		var frames := 0
		var y_at_leave := 0.0
		var peak_after := -INF
		var pressed := false
		for _i in 180:
			await physics_frame
			player.camera_yaw = yaw
			frames += 1
			if off_at < 0 and not player.is_grounded:
				off_at = frames
				y_at_leave = player.global_position.y
			if off_at > 0:
				if not pressed and (frames - off_at) >= int(delay * 60.0):
					player.press_jump()
					pressed = true
				if pressed:
					peak_after = maxf(peak_after, player.global_position.y)
				if player.is_grounded and frames - off_at > 12:
					break
		player.release_jump()
		player.move_input = Vector2.ZERO
		results[delay] = peak_after - y_at_leave
	await _clear_rig()

	var inside: float = results[0.08]
	var outside: float = results[0.40]
	_ok("COYOTE TIME", inside > 0.35 and outside < 0.05,
		"press %.0f ms after the ledge climbed %+.2f m; press %.0f ms after it climbed %+.2f m (window %.0f ms)"
			% [80.0, inside, 400.0, outside, cfg.coyote_time * 1000.0])


# ====================================================== section 13 ========
## JUMP BUFFER. Press jump while still falling, shortly before touchdown.
## The press must be remembered and fire on landing.
func _t_buffer() -> void:
	var spot := _flat_spot()
	if spot == Vector3.INF:
		_ok("JUMP BUFFER", false, "no flat ground found")
		return
	var outcomes := {}
	for early: bool in [true, false]:
		await _place(Vector3(spot.x, spot.y + 2.4, spot.z))
		# Fall, and press at a fixed height above the ground.
		var trigger := spot.y + (0.55 if early else 1.9)
		var pressed := false
		var landed_at := -1
		var frames := 0
		var y_min := INF
		var peak_after := -INF
		for _i in 160:
			await physics_frame
			frames += 1
			if not pressed and player.velocity.y < 0.0 and player.global_position.y <= trigger:
				player.press_jump()
				player.release_jump()
				pressed = true
			if landed_at < 0 and player.is_grounded and frames > 4:
				landed_at = frames
				y_min = player.global_position.y
			elif landed_at > 0:
				peak_after = maxf(peak_after, player.global_position.y)
				if frames - landed_at > 45:
					break
		outcomes[early] = peak_after - y_min
	_ok("JUMP BUFFER", float(outcomes[true]) > 0.12 and float(outcomes[false]) < 0.05,
		"press 0.55 m up rebounded %+.2f m; press 1.9 m up rebounded %+.2f m (window %.0f ms)"
			% [outcomes[true], outcomes[false], cfg.jump_buffer_time * 1000.0])


# ================================================== sections 14, 18 =======
func _t_step_over() -> void:
	var spot := _flat_spot()
	if spot == Vector3.INF:
		_ok("STEP OVER SMALL OBSTACLES", false, "no flat ground found")
		return
	# THE OBSTACLE HAS TO BE EXACTLY THE HEIGHT IT CLAIMS TO BE.
	#
	# The first version of this dropped a box of height h on the terrain and
	# called it an h-centimetre step. It is not: "flat" ground still rolls by
	# ten centimetres over the three metres of the run-up, so a 30 cm box
	# presented a 40 cm step to a player approaching from the low side — and
	# a correctly refused 40 cm step was reported as a failed 30 cm one.
	#
	# So the whole rig is built: a plate to walk along, a kerb of exactly h
	# standing on it, and a plate at the top. The terrain underneath stops
	# mattering.
	for probe: Dictionary in [
			{"h": 0.20, "over": true, "label": "20 cm kerb"},
			{"h": 0.30, "over": true, "label": "30 cm step"},
			{"h": 0.80, "over": false, "label": "80 cm wall"}]:
		await _clear_rig()
		var h: float = probe["h"]
		var y0 := spot.y
		_block(Vector3(spot.x + 1.0, y0 - 0.2, spot.z), Vector3(5.2, 0.4, 6.0))
		_block(Vector3(spot.x + 3.6, y0 + h * 0.5, spot.z), Vector3(0.6, h, 6.0))
		_block(Vector3(spot.x + 5.4, y0 + h - 0.2, spot.z), Vector3(3.0, 0.4, 6.0))
		await physics_frame
		await _place(Vector3(spot.x, y0 + 0.12, spot.z))
		var steps_before := player.steps_climbed
		await _hold(atan2(-1.0, 0.0), 1.0, false, 150)
		var crossed := player.global_position.x > spot.x + 4.4
		var rose := player.global_position.y - y0
		var want: bool = probe["over"]
		_ok("%s" % str(probe["label"]).to_upper(), crossed == want,
			"%s at %.2f m; y %+.2f m (kerb top %+.2f); %d step-ups used"
				% ["crossed" if crossed else "blocked", player.global_position.x - spot.x,
					rose, h, player.steps_climbed - steps_before])
	await _clear_rig()


# ====================================================== section 16 ========
func _t_slopes() -> void:
	var spot := _flat_spot()
	if spot == Vector3.INF:
		return
	for probe: Dictionary in [
			{"deg": 25.0, "climb": true},
			{"deg": 70.0, "climb": false}]:
		await _clear_rig()
		var deg: float = probe["deg"]
		# A ramp built as a rotated slab, so the angle is exact. Rotating a
		# slab about +Z by +theta lifts its +x end, so the ramp rises the way
		# the player walks. It is positioned by solving for where its low
		# end's TOP SURFACE lands: 20 cm under the ground at spot.x + 1.2, so
		# the ramp emerges from the terrain with no lip to catch on.
		var th := deg_to_rad(deg)
		var half := 4.5
		var b := _block(Vector3.ZERO, Vector3(half * 2.0, 0.6, 8.0))
		b.rotation.z = th
		b.position = Vector3(
			spot.x + 1.2 + half * cos(th) + 0.3 * sin(th),
			spot.y - 0.20 + half * sin(th) - 0.3 * cos(th),
			spot.z)
		await physics_frame
		await _place(Vector3(spot.x, spot.y + 0.05, spot.z))
		var y0 := player.global_position.y
		# The PEAK, not the finish: a 25 degree ramp nine metres long is
		# climbed in under two seconds and then run off the far end, so
		# judging on where the player is standing at the buzzer measures the
		# drop off the top instead of the climb.
		var peak := 0.0
		var on_slope := 0.0
		player.camera_yaw = atan2(-1.0, 0.0)
		player.run_held = true
		player.move_input = Vector2(0, 1)
		for _i in 180:
			await physics_frame
			player.camera_yaw = atan2(-1.0, 0.0)
			peak = maxf(peak, player.global_position.y - y0)
			on_slope = maxf(on_slope, player.slope_angle)
		player.move_input = Vector2.ZERO
		player.run_held = false
		var climbed := peak > 0.9
		_ok("SLOPE %d DEG" % int(deg), climbed == bool(probe["climb"]),
			"%s: rose %+.2f m at best (limit %.0f deg, steepest ground stood on %.1f deg)"
				% ["climbed" if climbed else "refused", peak,
					cfg.max_slope_deg, on_slope])
	await _clear_rig()


# ================================================== sections 18 to 21 =====
## THE OPENINGS AUDIT.
##
## Section 18 is the whole of 0.2.1 in one line: the player must be blocked
## only where they can SEE an obstacle. So every hole in a building gets
## walked at, and the answer must match what the hole looks like — a doorway
## lets you in, a window does not.
func _t_openings() -> void:
	var cabin: Node3D = world.find_child("ScoutCabin", true, false) as Node3D
	var ruin: Node3D = world.find_child("Ruin", true, false) as Node3D

	if cabin:
		# Open the door first: a shut door blocking you is correct behaviour
		# and is already covered by the 0.2 world-systems suite.
		var d: Door = cabin.get("door")
		if d:
			d.open()
			for _i in 90:
				await physics_frame
		var hd: float = float(cabin.get("depth")) * 0.5
		await _walk_through("CABIN DOORWAY", cabin,
			Vector3(0, 0, hd + 3.2), Vector3(0, 0, -1.2), true)
		# And the wall beside it must still be a wall.
		await _walk_through("CABIN WALL STILL SOLID", cabin,
			Vector3(2.2, 0, hd + 3.2), Vector3(2.2, 0, -1.2), false)
		_ok("CABIN INTERIOR IS HOLLOW", _hollow(cabin, 1.0, 2.0, 1.6),
			"interior sample points free at chest height: %d%%"
				% int(_hollow_ratio(cabin, 1.0, 2.0, 1.6) * 100.0))

	if ruin:
		var d2: Door = ruin.get("door")
		if d2:
			d2.open()
			for _i in 90:
				await physics_frame
		var hw: float = float(ruin.get("width")) * 0.5
		var hd2: float = float(ruin.get("depth")) * 0.5
		# North doorway, at the middle of the north wall.
		await _walk_through("RUIN DOORWAY", ruin,
			Vector3(0, 0, -hd2 - 3.4), Vector3(0, 0, -hd2 + 2.2), true)
		# South breach: the gap runs from 0.33 to 0.55 along a run that goes
		# from +hw to -hw, so it sits at x = lerp(hw, -hw, 0.44).
		var breach_x := lerpf(hw, -hw, 0.44)
		await _walk_through("RUIN SOUTH BREACH", ruin,
			Vector3(breach_x, 0, hd2 + 3.4), Vector3(breach_x, 0, hd2 - 2.2), true)
		# West window: a hole you can SEE but whose sill is chest high. Walking
		# at it must fail — that is the picture and the physics agreeing.
		await _walk_through("RUIN WINDOW BLOCKS", ruin,
			Vector3(-hw - 3.4, 0, 0.0), Vector3(-hw + 2.2, 0, 0.0), false)
		# East wall: the collapsed stretch leaves rubble about half a metre
		# high. That is above the step height and below the jump height, so
		# the coherent answer is "you can see over it, and you hop it": a
		# walk must NOT carry you over, a jump must. Both also assert the
		# thing that matters more than either — that you never end up inside
		# it.
		var col_z := lerpf(-hd2, hd2, 0.65)
		await _walk_through("RUIN RUBBLE BLOCKS A WALK", ruin,
			Vector3(hw + 3.4, 0, col_z), Vector3(hw - 2.2, 0, col_z), false)
		await _jump_through("RUIN RUBBLE YIELDS TO A JUMP", ruin,
			Vector3(hw + 3.4, 0, col_z), Vector3(hw - 2.2, 0, col_z))
		_ok("RUIN INTERIOR IS HOLLOW", _hollow(ruin, 1.0, 4.0, 2.6),
			"interior sample points free at chest height: %d%%"
				% int(_hollow_ratio(ruin, 1.0, 4.0, 2.6) * 100.0))


## Walk from `from_local` towards `to_local` (both in the building's frame)
## and report whether the player got there.
func _walk_through(label: String, building: Node3D, from_local: Vector3,
		to_local: Vector3, want_through: bool) -> void:
	var from: Vector3 = building.global_transform * from_local
	var to: Vector3 = building.global_transform * to_local
	from.y = maxf(TerrainData.height_at(from.x, from.z), building.global_position.y) + 0.25
	await _place(from)
	var dir := (to - from)
	dir.y = 0.0
	var want := dir.length()
	dir = dir.normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var inside_frames := 0
	player.camera_yaw = yaw
	player.move_input = Vector2(0, 1)
	var closest := INF
	for _i in 220:
		await physics_frame
		player.camera_yaw = yaw
		if _inside_solid(player.global_position + Vector3.UP * 0.9):
			inside_frames += 1
		closest = minf(closest, Vector2(player.global_position.x - to.x,
			player.global_position.z - to.z).length())
	player.move_input = Vector2.ZERO
	var through := closest < 0.9
	_ok(label, through == want_through and inside_frames == 0,
		"%s (wanted %s), closest approach %.2f m of %.2f m, inside solid %d frames"
			% ["went through" if through else "was blocked",
				"through" if want_through else "blocked", closest, want, inside_frames])


## The same run-up, but jumping as the obstacle comes into range.
func _jump_through(label: String, building: Node3D, from_local: Vector3,
		to_local: Vector3) -> void:
	var from: Vector3 = building.global_transform * from_local
	var to: Vector3 = building.global_transform * to_local
	from.y = maxf(TerrainData.height_at(from.x, from.z), building.global_position.y) + 0.25
	await _place(from)
	var dir := (to - from)
	dir.y = 0.0
	dir = dir.normalized()
	var yaw := atan2(-dir.x, -dir.z)
	var inside_frames := 0
	var closest := INF
	player.camera_yaw = yaw
	player.run_held = true
	player.move_input = Vector2(0, 1)
	for i in 260:
		await physics_frame
		player.camera_yaw = yaw
		# Jump repeatedly on the approach; the buffer makes the timing
		# forgiving, which is the point of having one.
		if i % 34 == 0:
			player.press_jump()
		elif i % 34 == 14:
			player.release_jump()
		if _inside_solid(player.global_position + Vector3.UP * 0.9):
			inside_frames += 1
		closest = minf(closest, Vector2(player.global_position.x - to.x,
			player.global_position.z - to.z).length())
	player.move_input = Vector2.ZERO
	player.run_held = false
	player.release_jump()
	_ok(label, closest < 1.4 and inside_frames == 0,
		"closest approach %.2f m while jumping, inside solid %d frames"
			% [closest, inside_frames])


## Fraction of a grid of interior points, at chest height, that is NOT inside
## solid geometry. A building wrapped in one big collider scores 0.
func _hollow_ratio(building: Node3D, chest: float, half_x: float, half_z: float) -> float:
	var free := 0
	var total := 0
	for ix in 5:
		for iz in 5:
			var p: Vector3 = building.global_transform * Vector3(
				lerpf(-half_x, half_x, ix / 4.0), chest,
				lerpf(-half_z, half_z, iz / 4.0))
			total += 1
			if not _inside_solid(p):
				free += 1
	return float(free) / maxf(total, 1)


func _hollow(building: Node3D, chest: float, half_x: float, half_z: float) -> bool:
	return _hollow_ratio(building, chest, half_x, half_z) > 0.85


# ====================================================== section 22 ========
func _t_bridge() -> void:
	var bridge: Node3D = world.find_child("Bridge", true, false) as Node3D
	if bridge == null:
		_ok("BRIDGE", false, "no Bridge in the showcase scene")
		return
	var t := bridge.global_transform
	var span: float = float(bridge.get("span")) if bridge.get("span") != null else 16.0
	var clearance: float = float(bridge.get("deck_clearance"))
	# Start on real ground well back from the ramp, not on top of it: a start
	# point dropped inside the approach slab is ejected by the solver and
	# measures nothing.
	var a: Vector3 = t * Vector3(0, 0, -span * 0.5 - 9.0)
	var b: Vector3 = t * Vector3(0, 0, span * 0.5 + 4.0)
	a.y = TerrainData.height_at(a.x, a.z) + 0.3
	await _place(a)
	var dir := (b - a)
	dir.y = 0.0
	var yaw := atan2(-dir.normalized().x, -dir.normalized().z)
	var swam := false
	var below := 0
	var deck_y := t.origin.y + clearance
	var reached := INF
	player.camera_yaw = yaw
	player.run_held = true
	player.move_input = Vector2(0, 1)
	for _i in 420:
		await physics_frame
		player.camera_yaw = yaw
		if player.state == PlayerController.State.SWIM:
			swam = true
		# Over the river, being below the deck means having gone through it.
		var rel: Vector3 = t.affine_inverse() * player.global_position
		if absf(rel.z) < span * 0.4 and player.global_position.y < deck_y - 0.6:
			below += 1
		reached = minf(reached, Vector2(player.global_position.x - b.x,
			player.global_position.z - b.z).length())
	player.move_input = Vector2.ZERO
	player.run_held = false
	var arrived := reached < 3.0
	_ok("BRIDGE CROSSED AT SPEED", arrived and not swam and below == 0,
		"closest to the far bank %.2f m, SWIM %s, frames below the deck %d"
			% [reached, "yes" if swam else "no", below])

	# Jump on the deck: you must come back down onto it, not through it.
	await _place(t * Vector3(0, clearance + 0.45, 0))
	for _i in 20:
		await physics_frame
	var y_deck := player.global_position.y
	player.press_jump()
	var min_y := y_deck
	for _i in 90:
		await physics_frame
		player.jump_held = true
		min_y = minf(min_y, player.global_position.y)
	player.release_jump()
	_ok("JUMP ON THE BRIDGE",
		player.state != PlayerController.State.SWIM
			and absf(player.global_position.y - y_deck) < 0.35 and min_y > y_deck - 0.35,
		"landed back on the deck: y %.2f -> %.2f, lowest %.2f, state %s"
			% [y_deck, player.global_position.y, min_y, player.state_name()])


# ================================================== sections 30 to 32 =====
func _t_water() -> void:
	# SECTION 22 AND SECTION 30 MEET AT THE PARAPET, and they want opposite
	# things from it, which is the whole point:
	#
	#   running into a 0.95 m handrail must not put you in the river — that
	#   is what a handrail is for, and a bridge you fall off by accident is
	#   the "collisions incohérentes" of section 18;
	#
	#   deliberately JUMPING it must, because the rail is chest high and the
	#   player can clear 1.25 m. Making it unjumpable would mean an invisible
	#   ceiling over a waist-high rail, which is the same bug facing the
	#   other way.
	var bridge: Node3D = world.find_child("Bridge", true, false) as Node3D
	if bridge:
		var t := bridge.global_transform
		var clear: float = float(bridge.get("deck_clearance"))
		# Local +X is across the deck, so this heads straight at the rail.
		var side: Vector3 = t.basis.x.normalized()
		var yaw := atan2(-side.x, -side.z)
		for probe: Dictionary in [{"jump": false, "wet": false}, {"jump": true, "wet": true}]:
			await _place(t * Vector3(0, clear + 0.45, 0))
			for _i in 15:
				await physics_frame
			player.camera_yaw = yaw
			player.run_held = true
			player.move_input = Vector2(0, 1)
			var ended := "LAND"
			for i in 210:
				await physics_frame
				player.camera_yaw = yaw
				if bool(probe["jump"]):
					if i == 40:
						player.press_jump()
					elif i == 70:
						player.release_jump()
				ended = player.state_name()
			player.move_input = Vector2.ZERO
			player.run_held = false
			player.release_jump()
			var wet := ended != "LAND"
			_ok("BRIDGE PARAPET %s" % ("YIELDS TO A JUMP" if probe["jump"] else "HOLDS A SPRINT"),
				wet == bool(probe["wet"]),
				"%s the rail: ended %s at y %.2f (deck top %.2f)"
					% ["jumped" if probe["jump"] else "ran into",
						ended, player.global_position.y, t.origin.y + clear + 0.11])

	# Section 30: jumping off a bank into deep water ends in a swim — not
	# standing on the surface, and not falling through the world.
	var jump_deep := _deep_water()
	if jump_deep != Vector3.INF:
		var bank0 := _nearest_bank(jump_deep)
		var toward := (jump_deep - bank0)
		toward.y = 0.0
		toward = toward.normalized()
		var launch := bank0 - toward * 5.0
		launch.y = TerrainData.height_at(launch.x, launch.z) + 0.2
		await _place(launch)
		var jyaw := atan2(-toward.x, -toward.z)
		player.camera_yaw = jyaw
		player.run_held = true
		player.move_input = Vector2(0, 1)
		var jumped_at := -1
		var ended := ""
		for i in 240:
			await physics_frame
			player.camera_yaw = jyaw
			# Jump as the bank runs out.
			if jumped_at < 0 and TerrainData.water_depth_at(
					player.global_position.x, player.global_position.z) > 0.05:
				player.press_jump()
				jumped_at = i
			if jumped_at >= 0 and i == jumped_at + 20:
				player.release_jump()
			ended = player.state_name()
		player.move_input = Vector2.ZERO
		player.run_held = false
		player.release_jump()
		_ok("JUMP FROM THE BANK INTO THE RIVER", ended == "SWIM",
			"ended in state %s at y %.2f, depth %.2f m (water level %.2f)"
				% [ended, player.global_position.y, player.water_depth,
					TerrainData.WATER_LEVEL])

	# Section 32: swimming speed, measured.
	var deep := _deep_water()
	if deep != Vector3.INF:
		await _place(deep)
		for _i in 60:
			await physics_frame
		var yaw := 0.0
		# Head along the river, not at the bank.
		player.camera_yaw = yaw
		player.run_held = true
		player.move_input = Vector2(0, 1)
		var peak := 0.0
		for _i in 150:
			await physics_frame
			player.camera_yaw = yaw
			if player.state == PlayerController.State.SWIM:
				peak = maxf(peak, player.horizontal_speed)
		player.move_input = Vector2.ZERO
		player.run_held = false
		_ok("SWIM SPEED", peak > 2.4 and peak < 3.6,
			"%.2f m/s at a full stroke (spec 2.5 .. 3.5, config %.2f)"
				% [peak, cfg.swim_fast_speed])

		# Section 31: and you can get out again, on foot.
		await _place(deep)
		for _i in 40:
			await physics_frame
		var bank := _nearest_bank(deep)
		var d := (bank - player.global_position)
		d.y = 0.0
		var byaw := atan2(-d.normalized().x, -d.normalized().z)
		player.camera_yaw = byaw
		player.run_held = true
		player.move_input = Vector2(0, 1)
		var got_out := false
		for _i in 420:
			await physics_frame
			player.camera_yaw = byaw
			if player.state == PlayerController.State.LAND and player.is_grounded:
				got_out = true
				break
		player.move_input = Vector2.ZERO
		player.run_held = false
		_ok("LEAVE THE WATER ON FOOT", got_out,
			"state %s, depth %.2f m, y %.2f after swimming for the bank"
				% [player.state_name(), player.water_depth, player.global_position.y])


func _deep_water() -> Vector3:
	var best := Vector3.INF
	var best_d := 0.0
	for gz in 40:
		var z := lerpf(-50.0, 50.0, gz / 39.0)
		var x := TerrainData.river_center_x(z)
		var d := TerrainData.water_depth_at(x, z)
		if d > best_d:
			best_d = d
			best = Vector3(x, TerrainData.WATER_LEVEL - 0.4, z)
	return best


func _nearest_bank(from: Vector3) -> Vector3:
	for step in range(2, 40):
		for s: float in [1.0, -1.0]:
			var x := from.x + s * step * 0.8
			if not TerrainData.is_water(x, from.z) and TerrainData.is_walkable(x, from.z):
				return Vector3(x, TerrainData.height_at(x, from.z), from.z)
	return from + Vector3(12, 0, 0)


# ================================================= sections 26, 29, 44 ====
func _t_sprint_interaction() -> void:
	# One pickup PER TIER. Taking a pickup frees it, so re-using the same
	# target for the second run would be asking a freed node where it is.
	var pickups := _open_pickups()
	if pickups.size() < 3:
		_ok("PICKUP AT SPEED", false,
			"need three pickups on open ground, found %d" % pickups.size())
		return

	var inter: Interactor = player.get_node("Interactor")
	# SECTION 44, and the report's three rows: the same run-up at each tier,
	# because "interacting does not cost you your speed" is a claim about all
	# three, not just the slow one.
	var tiers := [
		{"name": "WALK", "mag": 1.0, "run": false, "floor": 2.5},
		{"name": "RUN", "mag": 0.85, "run": true, "floor": 4.5},
		{"name": "SPRINT", "mag": 1.0, "run": true, "floor": 6.0},
	]
	for ti in tiers.size():
		var t: Dictionary = tiers[ti]
		var target: Node3D = pickups[ti]
		var approach := Vector3(1, 0, 0.3).normalized()
		var start := target.global_position - approach * 13.0
		start.y = TerrainData.height_at(start.x, start.z) + 0.2
		await _place(start)
		var yaw := atan2(-approach.x, -approach.z)
		player.camera_yaw = yaw
		player.run_held = bool(t["run"])
		player.move_input = Vector2(0, float(t["mag"]))
		var before := 0.0
		var after := 0.0
		var heading_before := 0.0
		var heading_after := 0.0
		var took := false
		var seen := ""
		for _i in 260:
			await physics_frame
			player.camera_yaw = yaw
			if not took and inter.has_candidate():
				before = player.horizontal_speed
				seen = player.tier_name()
				heading_before = atan2(player.velocity.x, player.velocity.z)
				took = inter.interact()
				if took:
					await physics_frame
					after = player.horizontal_speed
					heading_after = atan2(player.velocity.x, player.velocity.z)
		player.move_input = Vector2.ZERO
		player.run_held = false
		var drift := absf(wrapf(heading_after - heading_before, -PI, PI))
		_ok("%s PICKUP" % t["name"],
			took and after > before * 0.9 and drift < 0.05 and before > float(t["floor"]),
			"took at %.2f m/s (%s) -> %.2f m/s (%.0f%% kept), heading drift %.4f rad"
				% [before, seen, after, after / maxf(before, 0.01) * 100.0, drift])

	# Section 27: mechanisms need a stance. A pickup does not.
	var d: Door = world.find_child("CabinDoor", true, false) as Door
	if d == null:
		d = world.find_child("RuinDoor", true, false) as Door
	if d:
		var near := d.global_position + Vector3(0, 0, 1.2)
		near.y = maxf(TerrainData.height_at(near.x, near.z), d.global_position.y) + 0.2
		await _place(near)
		for _i in 30:
			await physics_frame
		var offered_grounded := inter.has_candidate()
		player.press_jump()
		var offered_airborne := true
		for _i in 22:
			await physics_frame
			player.jump_held = true
			if not player.is_grounded:
				offered_airborne = inter.has_candidate()
		player.release_jump()
		for _i in 40:
			await physics_frame
		_ok("NO MECHANISMS MID-AIR", offered_grounded and not offered_airborne,
			"door offered on the ground: %s; offered in the air: %s"
				% [offered_grounded, offered_airborne])


# ================================================== sections 41, 43 =======
## A shut door must stop a sprint, and stopping it must not mean letting the
## player through it for one frame first. Section 43 names the door among the
## things a sprint is thrown at; the collision audit already covers the tree,
## the rock and the wall at the same speed.
func _t_doors_at_speed() -> void:
	var d: Door = world.find_child("CabinDoor", true, false) as Door
	if d == null:
		d = world.find_child("RuinDoor", true, false) as Door
	if d == null:
		_ok("SPRINT INTO A CLOSED DOOR", false, "no door in the scene")
		return
	d.close()
	for _i in 90:
		await physics_frame
	var leaf := d.global_position
	# Approach along the door's own forward, from outside.
	var face: Vector3 = d.global_transform.basis.z.normalized()
	var start := leaf + face * 9.0
	start.y = maxf(TerrainData.height_at(start.x, start.z), leaf.y) + 0.25
	await _place(start)
	var yaw := atan2(face.x, face.z)          # heading back towards the door
	var inside := 0
	var closest := INF
	player.camera_yaw = yaw
	player.run_held = true
	player.move_input = Vector2(0, 1)
	for _i in 200:
		await physics_frame
		player.camera_yaw = yaw
		if _inside_solid(player.global_position + Vector3.UP * 0.9):
			inside += 1
		closest = minf(closest, Vector2(player.global_position.x - leaf.x,
			player.global_position.z - leaf.z).length())
	player.move_input = Vector2.ZERO
	player.run_held = false
	# "Through" means on the far SIDE of the door's plane, not near its
	# hinge: standing hard against a shut door is the correct outcome and
	# puts you well inside any radius you would care to pick.
	var side := face.dot(player.global_position - leaf)
	var through := side < -0.25
	_ok("SPRINT INTO A CLOSED DOOR", not through and inside == 0 and closest < 3.0,
		"stopped %.2f m in front of the leaf (closest %.2f m), %s, inside solid %d frames"
			% [side, closest, "WENT THROUGH" if through else "held", inside])
	d.close()
	for _i in 60:
		await physics_frame


# ====================================================== section 12 ========
## THE TOUCH INTERFACE, driven by synthesised touches through the real
## dispatcher. Not "does the button exist" — does a finger on it do the
## thing, and does a SECOND finger on it leave the first one alone. That
## last part is the one that breaks (section 13 of the 0.2 brief), and it is
## the whole reason MobileHud dispatches touches by index by hand.
func _t_mobile_ui() -> void:
	var hud: MobileHud = world.get_node_or_null("UI/MobileHud") as MobileHud
	if hud == null:
		_ok("TOUCH JOYSTICK", false, "no MobileHud in the scene")
		return
	var spot := _flat_spot()
	if spot != Vector3.INF:
		await _place(spot)
	hud.process_mode = Node.PROCESS_MODE_INHERIT
	hud.call("_layout")
	await physics_frame

	var stick_c: Vector2 = hud.get("_stick_c")
	var stick_r: float = hud.get("_stick_r")
	var jump_c: Vector2 = hud.get("_jump_c")
	var run_c: Vector2 = hud.get("_run_c")

	# --- joystick ---------------------------------------------------------
	_touch(hud, 0, stick_c, true)
	_drag(hud, 0, stick_c + Vector2(0, -stick_r))       # screen up = forward
	await physics_frame
	var pushed := player.move_input
	# --- a second finger must not kill the first --------------------------
	# Read the counter first: the jump fires on the very next physics frame,
	# so sampling it after the press measures nothing.
	var jumps_before := player.jumps_made
	_touch(hud, 1, jump_c, true)
	await physics_frame
	var still := player.move_input
	for _i in 12:
		await physics_frame
	_touch(hud, 1, jump_c, false)
	var jumped_ok := player.jumps_made > jumps_before
	_touch(hud, 0, stick_c, false)
	await physics_frame
	var released := player.move_input

	_ok("TOUCH JOYSTICK",
		pushed.y > 0.9 and absf(pushed.x) < 0.1 and released == Vector2.ZERO,
		"stick up gives %s, release gives %s" % [str(pushed), str(released)])
	_ok("STICK SURVIVES A SECOND THUMB", still.y > 0.9,
		"input while SAUTER is also held: %s" % str(still))
	_ok("TOUCH JUMP BUTTON", jumped_ok,
		"a tap on SAUTER produced %d jump(s)" % (player.jumps_made - jumps_before))

	# --- run: tap to latch, tap again to let go ---------------------------
	_touch(hud, 2, run_c, true)
	_touch(hud, 2, run_c, false)
	await physics_frame
	var latched := player.run_held
	_touch(hud, 2, run_c, true)
	_touch(hud, 2, run_c, false)
	await physics_frame
	var unlatched := player.run_held
	_ok("TOUCH SPRINT LATCH", latched and not unlatched,
		"tap latches RUN (%s), second tap releases it (%s)" % [latched, unlatched])

	# --- interact ---------------------------------------------------------
	var inter: Interactor = player.get_node("Interactor")
	var had := false
	var before_n := 0
	var after_n := 0
	for pick: Node3D in _open_pickups():
		var at := pick.global_position + Vector3(1.2, 0, 0)
		at.y = TerrainData.height_at(at.x, at.z) + 0.2
		await _place(at)
		# Standing still, the interactor takes its heading from where the
		# MODEL is pointing, and the model is still pointing wherever the
		# last test left it. Aim it at the pickup, or a target 1.2 m away is
		# legitimately rejected for being behind the player.
		var to := pick.global_position - player.global_position
		player.model_pivot.rotation.y = atan2(to.x, to.z)
		player.camera_yaw = atan2(-to.normalized().x, -to.normalized().z)
		for _i in 20:
			await physics_frame
		had = inter.has_candidate()
		if not had:
			continue
		before_n = inter.total_of(&"BOIS") + inter.total_of(&"CRISTAL")
		var act_c: Vector2 = hud.get("_act_c")
		_touch(hud, 3, act_c, true)
		await physics_frame
		_touch(hud, 3, act_c, false)
		await physics_frame
		after_n = inter.total_of(&"BOIS") + inter.total_of(&"CRISTAL")
		break
	_ok("TOUCH INTERACT BUTTON", had and after_n > before_n,
		"prompt offered %s, carried %d -> %d" % [had, before_n, after_n])
	hud.process_mode = Node.PROCESS_MODE_DISABLED


## Every pickup still in the world that stands on dry, walkable ground with
## room for a run-up.
func _open_pickups() -> Array:
	var out := []
	for n in _all(world):
		if not (n is Pickup) or not (n as Node3D).visible:
			continue
		var gp: Vector3 = (n as Node3D).global_position
		if not TerrainData.is_walkable(gp.x, gp.z) or TerrainData.is_water(gp.x, gp.z):
			continue
		out.append(n)
	return out


func _touch(hud: Node, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	hud.call("_input", e)


func _drag(hud: Node, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	hud.call("_input", e)


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
