extends SceneTree
## DIAGNOSTIC — where are the holes, really?
##
## Section 18 of the 0.2.1 brief asks for the player to be blocked only where
## an obstacle is visible. Answering that starts with knowing where the
## COLLIDERS actually have gaps, which is not the same question as where the
## source code says it put them: this tool found that the ruin's west window
## had no hole in it at all (the wall was built solid and the window boxes
## were stacked on top of it) and that the bridge's near approach ramp
## finished in the river.
##
## It prints, per ruin wall, a knee-height and a chest-height solidity strip
## sampled with point queries against the real physics world — "#" is solid,
## "." is open — and the height of whatever is solid along the bridge.
##
## Note the one thing it cannot see: the terrain is a concave trimesh, and
## intersect_point never reports a hit inside one of those. So "nothing here"
## in this tool means "no convex geometry here", not "no ground".
##
## Run: godot --headless --path . --script tools/probe_openings.gd

func _init() -> void:
	_run.call_deferred()

func _solid(w: Node, p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = Layers.WORLD_STATIC
	return not w.get_world_3d().direct_space_state.intersect_point(q, 1).is_empty()

func _run() -> void:
	var world: Node3D = (load("res://scenes/testing/ArtPhysicsShowcase.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _i in 6:
		await physics_frame
	var ruin: Node3D = world.find_child("Ruin", true, false)
	print("ruin at ", ruin.global_position, " yaw ", rad_to_deg(ruin.rotation.y),
		" w ", ruin.get("width"), " d ", ruin.get("depth"))
	var hw: float = float(ruin.get("width")) * 0.5
	var hd: float = float(ruin.get("depth")) * 0.5
	for wall: Dictionary in [
			{"n": "north z=-hd", "a": Vector3(-hw, 0, -hd), "b": Vector3(hw, 0, -hd)},
			{"n": "south z=+hd", "a": Vector3(hw, 0, hd), "b": Vector3(-hw, 0, hd)},
			{"n": "east  x=+hw", "a": Vector3(hw, 0, -hd), "b": Vector3(hw, 0, hd)},
			{"n": "west  x=-hw", "a": Vector3(-hw, 0, hd), "b": Vector3(-hw, 0, -hd)}]:
		var knee := ""
		var chest := ""
		for i in 27:
			var t := i / 26.0
			var lp: Vector3 = (wall["a"] as Vector3).lerp(wall["b"] as Vector3, t)
			var gp: Vector3 = ruin.global_transform * Vector3(lp.x, 0.0, lp.z)
			knee += "." if not _solid(world, gp + Vector3.UP * 0.35) else "#"
			chest += "." if not _solid(world, gp + Vector3.UP * 1.20) else "#"
		print("%s  knee %s" % [wall["n"], knee])
		print("%s  chst %s" % ["          ", chest])

	var bridge: Node3D = world.find_child("Bridge", true, false)
	print("\nbridge origin ", bridge.global_position, " yaw ",
		rad_to_deg(bridge.rotation.y), " span ", bridge.get("span"),
		" clearance ", bridge.get("deck_clearance"))
	var span: float = float(bridge.get("span"))
	var prof := ""
	for i in 31:
		var z := lerpf(-span * 0.5 - 6.0, span * 0.5 + 6.0, i / 30.0)
		var gp: Vector3 = bridge.global_transform * Vector3(0, 0, z)
		# Where is the top of whatever is solid here?
		var top := -99.0
		for k in 40:
			var y := lerpf(-2.0, 4.0, k / 39.0)
			if _solid(world, Vector3(gp.x, bridge.global_position.y + y, gp.z)):
				top = y
		prof += "%.2f " % top
	print("deck top profile (local y, along the span): ", prof)
	quit(0)
