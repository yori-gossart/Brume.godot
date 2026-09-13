extends SceneTree
##
## Render the benchmark scene to PNGs with a real renderer.
##
## --headless uses Godot's dummy rendering server, which never compiles a
## shader and never draws a triangle, so it cannot tell you whether the
## Brume actually looks like anything. This runs the scene under a software
## Vulkan device instead and saves frames, which is the only way to check the
## shaders compile and the world reads correctly without a phone in hand.
##
##   godot --path . --rendering-method mobile --resolution 720x1280 \
##     --script tools/shoot.gd
##
## On a headless Linux box with no GPU, put it behind a virtual display and a
## software Vulkan device (Mesa lavapipe):
##
##   xvfb-run -s "-screen 0 760x1360x24" godot --path . \
##     --rendering-driver vulkan --rendering-method mobile \
##     --resolution 720x1280 --script tools/shoot.gd
## Where the PNGs land. `user://` resolves to the Godot user data folder,
## which exists on a phone as well as on a desktop.
var out_dir := "user://shots"
var world: Node3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(720, 1280)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = (load("res://scenes/BenchmarkWorld.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _i in 12:
		await process_frame
	var player: PlayerController = world.get_node("Player")
	var cam: Node3D = world.get_node("PlayerCamera")
	var dbg: Node = world.get_node("UI/DebugHud")
	var hud: Node = world.get_node("UI/MobileHud")
	var tower: Node3D = world.get_node("BeaconTower")
	var cabin: Node3D = world.get_node("ScoutCabin")

	# Look AT something, rather than guessing a yaw. `look` is a world point.
	var shots := [
		{"name": "01_spawn_toward_fog", "pos": Vector3(8, 0, 40), "look": Vector3(2, 14, 130), "pitch": -4.0, "hud": true},
		{"name": "02_fog_close", "pos": Vector3(6, 0, 74), "look": Vector3(0, 12, 120), "pitch": 2.0, "hud": false},
		{"name": "03_fog_flank", "pos": Vector3(-58, 0, 66), "look": Vector3(10, 10, 118), "pitch": -2.0, "hud": false},
		{"name": "04_beacon_ridge", "pos": Vector3(-42, 0, -44), "look": tower.global_position + Vector3(0, 8, 0), "pitch": 0.0, "hud": false},
		{"name": "05_water_shore", "pos": Vector3(-16, 0, 18), "look": Vector3(-18, -1, 40), "pitch": -12.0, "hud": false},
		{"name": "06_cabin", "pos": Vector3(40, 0, 36), "look": cabin.global_position + Vector3(0, 2, 0), "pitch": -6.0, "hud": false},
		{"name": "07_forest", "pos": Vector3(64, 0, -6), "look": Vector3(30, 6, -30), "pitch": -4.0, "hud": false},
		{"name": "08_pond", "pos": Vector3(-2, 0, -34), "look": Vector3(-14, -1, -58), "pitch": -10.0, "hud": false},
		{"name": "09_hud_full", "pos": Vector3(8, 0, 40), "look": Vector3(40, 8, 90), "pitch": -8.0, "hud": true},
	]
	for s in shots:
		var p: Vector3 = s["pos"]
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(p.x, TerrainData.height_at(p.x, p.z) + 0.1, p.z)
		dbg.set("visible", s["hud"])
		hud.set("debug_visible", s["hud"])
		var to: Vector3 = (s["look"] as Vector3) - player.global_position
		cam.call("face", Vector3(to.x, 0.0, to.z).normalized())
		cam.set("_pitch", deg_to_rad(s["pitch"]))
		cam.global_position = player.global_position + Vector3.UP * 1.45
		for _i in 26:
			await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, s["name"]])
		print("saved ", s["name"], "  ", img.get_width(), "x", img.get_height())
	print("FPS at end: ", Engine.get_frames_per_second())
	print(world.call("build_report"))
	quit()
