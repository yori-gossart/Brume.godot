extends SceneTree
##
## THE COLLISION AUDIT (sections 17, 20, 54, 68).
##
## Section 68 is blunt about what does not count:
##
##     "Tree has CollisionShape3D -> PASS"   NON.
##     Le player doit réellement essayer de le traverser.
##
## So nothing here inspects a node. Every check takes the real
## CharacterBody3D, puts it a few metres from a real obstacle, holds the
## stick down, and runs the real physics until it either stops or does not.
##
## THE VERDICT IS TAKEN FROM THE PHYSICS ENGINE, NOT FROM GEOMETRY.
##
## The first version of this test asked "did the body get past the
## obstacle's centre plane?". That is wrong twice over: walking round the
## END of a four-metre wall gets you past its centre plane legitimately, and
## so does grazing a boulder at 75 degrees. It reported both as tunnelling.
##
## What actually matters is simpler and shape-agnostic: WAS THE BODY EVER
## INSIDE SOLID GEOMETRY? Every physics frame, a point query at chest height
## against WORLD_STATIC answers exactly that, for a cylinder, a convex hull
## and a box alike. One frame inside is a failure.
##
## Head-on approaches are additionally required to have been STOPPED. The
## grazing approach is not — sliding past is the correct outcome there, and
## demanding otherwise would be testing the wrong thing.
##
## Six approaches per obstacle (section 20): frontal walk, frontal run,
## 30 degrees, 45 degrees, diagonal, and a lateral graze. Run at BOTH
## quality levels, because section 65 says the collision world must not
## depend on the quality preset.

const APPROACHES := [
	{"name": "walk frontal",  "angle": 0.0,   "run": false, "headon": true},
	{"name": "run frontal",   "angle": 0.0,   "run": true,  "headon": true},
	{"name": "run 30 deg",    "angle": 30.0,  "run": true,  "headon": true},
	{"name": "run 45 deg",    "angle": 45.0,  "run": true,  "headon": true},
	{"name": "run diagonal",  "angle": 20.0,  "run": true,  "headon": true, "diagonal": true},
	# A graze. Sliding past is the CORRECT outcome; the only failure here is
	# ending up inside.
	{"name": "run lateral",   "angle": 75.0,  "run": true,  "headon": false},
]

var world: Node3D
var player: PlayerController
var results: Array = []
var failures := 0
var Q: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	world = (load("res://scenes/testing/ArtPhysicsShowcase.tscn") as PackedScene).instantiate()
	Q = root.get_node_or_null("/root/Quality")
	root.add_child(world)
	for _i in 5:
		await physics_frame
	player = world.get_node("Player")
	(world.get_node("UI/MobileHud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	(world.get_node("PlayerCamera") as Node).process_mode = Node.PROCESS_MODE_DISABLED

	var targets := _gather_targets()
	print("\n=== COLLISION AUDIT — %d obstacles x %d approaches x 2 quality levels ===\n"
		% [targets.size(), APPROACHES.size()])

	for level in [0, 1]:
		Q.level = level
		await process_frame
		var label := "HIGH" if level == 0 else "LOW"
		for t in targets:
			await _audit(t, label)

	print("\n=== RESULTS ===")
	var by_target := {}
	var skipped := 0
	for r in results:
		var k: String = r["target"]
		if not by_target.has(k):
			by_target[k] = {"pass": 0, "fail": 0, "skip": 0, "worst": ""}
		if r.get("skipped", false):
			by_target[k]["skip"] += 1
			skipped += 1
		elif r["ok"]:
			by_target[k]["pass"] += 1
		else:
			by_target[k]["fail"] += 1
			by_target[k]["worst"] = r["note"]
	for k in by_target:
		var b = by_target[k]
		print("  %-26s %2d pass  %2d FAIL  %d skip  %s"
			% [k, b["pass"], b["fail"], b["skip"], b["worst"]])
	print("  (%d run-ups skipped for want of clear ground)" % skipped)
	print("\n%d runs, %d failed\n" % [results.size(), failures])
	quit(1 if failures > 0 else 0)


## Collect every obstacle the audit should try to walk through, with a
## centre and a radius derived from its ACTUAL collision shape.
func _gather_targets() -> Array:
	var out := []
	var scatter: Node = world.get_node_or_null("Scatter")
	if scatter:
		# Five different tree species and five rocks — not five instances of
		# one tree, which would only prove one shape works.
		for id in ["pine_large", "pine_medium", "pine_yellow", "dead_large", "broadleaf_A"]:
			var t := _from_multimesh_body(scatter, "Col_" + id, "tree " + id)
			if t: out.append(t)
		for id in ["rock_big_A", "rock_big_B", "rock_mid"]:
			var t := _from_multimesh_body(scatter, "Col_" + id, "rock " + id)
			if t: out.append(t)
	for spec in [
			{"node": "ScoutCabin", "label": "cabin wall", "shrink": 0.55},
			{"node": "BeaconTower", "label": "tower", "shrink": 0.5},
			{"node": "Ruin", "label": "ruin wall", "shrink": 0.5},
			{"node": "StonePillar", "label": "pillar", "shrink": 0.8},
		]:
		# find_child so the ruin's pillar is found where it actually lives —
		# as a child of the ruin, not at the world root.
		var n: Node3D = world.find_child(str(spec["node"]), true, false) as Node3D
		if n == null:
			continue
		var info := _from_structure(n, str(spec["label"]), float(spec["shrink"]))
		if info: out.append(info)
	return out


func _from_multimesh_body(scatter: Node, body_name: String, label: String) -> Dictionary:
	var body: StaticBody3D = scatter.get_node_or_null(body_name)
	if body == null:
		return {}
	for c in body.get_children():
		if not (c is CollisionShape3D) or (c as CollisionShape3D).disabled:
			continue
		var cs := c as CollisionShape3D
		# Only pick one standing on ground the player can actually reach.
		var p := cs.global_position
		if not TerrainData.is_walkable(p.x + 6.0, p.z) or not TerrainData.is_walkable(p.x - 6.0, p.z):
			continue
		var r := 0.5
		if cs.shape is CylinderShape3D:
			r = (cs.shape as CylinderShape3D).radius
		elif cs.shape is ConvexPolygonShape3D:
			for pt in (cs.shape as ConvexPolygonShape3D).points:
				r = maxf(r, Vector2(pt.x, pt.z).length())
		# Trunks and boulders are roughly circular, so their radius is a
		# meaningful "you should have been stopped this far out".
		return {"label": label, "centre": Vector3(p.x, 0.0, p.z), "radius": r, "circular": true}
	return {}


## For a hand-built structure, aim at the centre of its largest solid piece.
func _from_structure(n: Node3D, label: String, shrink: float) -> Dictionary:
	var body: StaticBody3D = null
	for c in _all(n):
		if c is StaticBody3D:
			body = c
			break
	if body == null:
		return {}
	var best_vol := 0.0
	var best := Vector3.ZERO
	var best_r := 1.0
	for c in body.get_children():
		if not (c is CollisionShape3D):
			continue
		var cs := c as CollisionShape3D
		if cs.shape is BoxShape3D:
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			var vol := sz.x * sz.y * sz.z
			# Ignore floors and roofs; we want something upright to walk into.
			if sz.y < 1.0:
				continue
			if vol > best_vol:
				best_vol = vol
				best = cs.global_position
				best_r = maxf(sz.x, sz.z) * 0.5 * shrink
		elif cs.shape is CylinderShape3D:
			var cy := cs.shape as CylinderShape3D
			if cy.height < 1.0:
				continue
			var vol2 := PI * cy.radius * cy.radius * cy.height
			if vol2 > best_vol:
				best_vol = vol2
				best = cs.global_position
				best_r = cy.radius * shrink
	if best_vol <= 0.0:
		return {}
	# A wall is a long thin box. Its "radius" is only a run-up distance, not
	# a keep-out circle: standing with your nose against a nine-metre wall
	# puts you well inside any circle that encloses it, and correctly so.
	return {"label": label, "centre": Vector3(best.x, 0.0, best.z), "radius": best_r,
		"circular": false}


func _audit(t: Dictionary, quality: String) -> void:
	for a in APPROACHES:
		var base := Vector3(1, 0, 0.35).normalized().rotated(Vector3.UP, deg_to_rad(a["angle"]))
		if a.get("diagonal", false):
			base = Vector3(1, 0, 1).normalized().rotated(Vector3.UP, deg_to_rad(a["angle"]))
		var r: float = t["radius"]
		var centre: Vector3 = t["centre"]

		# Find a start that is not itself buried in something. The world has
		# ruins and buildings in it now; a run-up that begins inside a wall
		# tests nothing.
		var start := Vector3.INF
		for back: float in [4.5, 6.5, 9.0, 3.0]:
			var cand: Vector3 = centre - base * (r + back)
			var y := TerrainData.height_at(cand.x, cand.z)
			if not TerrainData.is_walkable(cand.x, cand.z):
				continue
			if _inside_solid(Vector3(cand.x, y + 0.9, cand.z)):
				continue
			# And the first stretch of the run-up must be clear. A start
			# point inside the cabin passes the "not in a wall" test and
			# then walks half a metre into the opposite wall, which tests
			# the wrong obstacle entirely.
			if not _clear_ahead(Vector3(cand.x, y + 0.9, cand.z), base, minf(back - 0.6, 3.5)):
				continue
			start = Vector3(cand.x, y + 0.2, cand.z)
			break
		if start == Vector3.INF:
			results.append({"target": "%s [%s]" % [t["label"], quality], "ok": true,
				"note": "%s: SKIPPED — no clear run-up" % a["name"], "skipped": true})
			continue

		player.velocity = Vector3.ZERO
		player.global_position = start
		await physics_frame
		await physics_frame

		player.camera_yaw = atan2(-base.x, -base.z)
		player.move_input = Vector2(0, 1)
		player.run_held = a["run"]

		var inside_frames := 0
		var min_dist := INF
		var from := player.global_position
		for _i in 150:
			await physics_frame
			player.camera_yaw = atan2(-base.x, -base.z)
			# The question that matters, asked of the physics server.
			if _inside_solid(player.global_position + Vector3.UP * 0.9):
				inside_frames += 1
			var rel := player.global_position - centre
			min_dist = minf(min_dist, Vector2(rel.x, rel.z).length())
		player.move_input = Vector2.ZERO
		player.run_held = false

		var travelled := Vector2(player.global_position.x - from.x,
			player.global_position.z - from.z).length()
		var rel_end := player.global_position - centre
		var dist_end := Vector2(rel_end.x, rel_end.z).length()

		var tried := travelled > 1.0
		var penetrated := inside_frames > 0
		# Only meaningful for roughly circular obstacles — see _from_structure.
		var stopped := dist_end > r * 0.55
		var ok := tried and not penetrated
		if a["headon"] and bool(t.get("circular", false)):
			ok = ok and stopped

		var why := "ok"
		if penetrated:
			why = "INSIDE SOLID for %d frames" % inside_frames
		elif not tried:
			why = "never moved"
		elif a["headon"] and bool(t.get("circular", false)) and not stopped:
			why = "ended inside the proxy radius"

		results.append({
			"target": "%s [%s]" % [t["label"], quality],
			"ok": ok,
			"note": "%s: %s (closest %.2f, r=%.2f, ended %.2f, moved %.2f)" % [
				a["name"], why, min_dist, r, dist_end, travelled],
		})
		if not ok:
			failures += 1


## Is the first `dist` metres of the run-up free of level geometry?
func _clear_ahead(from: Vector3, dir: Vector3, dist: float) -> bool:
	if dist <= 0.1:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.collision_mask = Layers.WORLD_STATIC
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Is this world-space point inside level geometry? Shape-agnostic: the
## physics server answers for cylinders, convex hulls and boxes alike.
func _inside_solid(p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = Layers.WORLD_STATIC
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return not player.get_world_3d().direct_space_state.intersect_point(q, 1).is_empty()


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
