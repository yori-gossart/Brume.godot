extends SceneTree
## One close-up of the player, front and back, to check the composition:
## a head, one body, no obvious clipping. Software Vulkan, see tools/shoot.gd.
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var world: Node3D = (load("res://scenes/testing/ArtPhysicsShowcase.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _i in 30: await process_frame
	var player: Node3D = world.get_node("Player")
	(world.get_node("PlayerCamera") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.current = true
	var focus: Vector3 = player.global_position + Vector3.UP * 0.95
	var shots := {"front": Vector3(0, 0.25, 1), "back": Vector3(0, 0.25, -1),
		"side": Vector3(1, 0.25, 0.2)}
	# Hold a walk so the pose is not a T-pose.
	player.set("camera_yaw", 0.0)
	player.set("move_input", Vector2(0, 1))
	for _i in 40: await process_frame
	player.set("move_input", Vector2.ZERO)
	for name in shots:
		focus = player.global_position + Vector3.UP * 0.95
		cam.global_position = focus + (shots[name] as Vector3).normalized() * 3.2
		cam.look_at(focus, Vector3.UP)
		for _i in 4: await process_frame
		await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png("res://docs/screenshots022/scout_%s.png" % name)
	print("shots written")
	quit(0)
