extends SceneTree
##
## Render the 0.2 showcase scene under the MOBILE renderer.
##
##   xvfb-run -s "-screen 0 760x1360x24" godot --path . \
##     --rendering-driver vulkan --rendering-method mobile \
##     --resolution 720x1280 --script tools/shoot_showcase.gd
var out_dir := "user://shots02"
var world: Node3D

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.content_scale_size = Vector2i(720, 1280)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	world = (load("res://scenes/testing/ArtPhysicsShowcase.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for _i in 14:
		await process_frame

	var player: PlayerController = world.get_node("Player")
	var cam: Node3D = world.get_node("PlayerCamera")
	var dbg: Node = world.get_node("UI/DebugHud")
	var hud: Node = world.get_node("UI/MobileHud")
	var appear: Node = world.get_node("UI/AppearanceScreen")
	var ruin: Node3D = world.get_node("Ruin")
	var door: Door = world.find_child("RuinDoor", true, false)
	var fire: Node3D = world.get_node("Campfire")
	var bridge: Node3D = world.get_node("Bridge")
	var npcs: Array = world.get("npcs")

	door.open()
	fire.call("_set_state", 1)   # LIT, for the picture
	for _i in 120:
		await process_frame

	var shots := [
		{"n": "01_nomads", "at": _near(npcs[0], 7.0), "look": npcs[1].global_position + Vector3(0, 1.2, 0), "pitch": -6.0, "hud": true},
		{"n": "02_ruin_door", "at": _front_of(door, 8.0), "look": door.global_position + Vector3(0, 1.3, 0), "pitch": -4.0, "hud": false},
		{"n": "03_ruin_inside", "at": ruin.global_position + Vector3(2.0, 0, 1.0), "look": ruin.global_position + Vector3(0, 2.2, 0.6), "pitch": 2.0, "hud": false},
		{"n": "04_campfire", "at": fire.global_position + Vector3(4.5, 0, 3.0), "look": fire.global_position + Vector3(0, 0.6, 0), "pitch": -12.0, "hud": false},
		{"n": "05_bridge", "at": bridge.global_position + Vector3(0, 0, -14.0), "look": bridge.global_position + Vector3(0, 2.0, 0), "pitch": -4.0, "hud": false},
		{"n": "06_forest", "at": Vector3(56, 0, -4), "look": Vector3(20, 6, -34), "pitch": -4.0, "hud": false},
		{"n": "07_hud", "at": _near(npcs[2], 6.0), "look": npcs[2].global_position + Vector3(0, 1.2, 0), "pitch": -6.0, "hud": true},
	]
	for s in shots:
		var p: Vector3 = s["at"]
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(p.x, maxf(TerrainData.height_at(p.x, p.z) + 0.15,
			TerrainData.WATER_LEVEL + 0.15), p.z)
		dbg.set("visible", s["hud"])
		hud.set("debug_visible", s["hud"])
		var to: Vector3 = (s["look"] as Vector3) - player.global_position
		cam.call("face", Vector3(to.x, 0.0, to.z).normalized())
		cam.set("_pitch", deg_to_rad(s["pitch"]))
		cam.global_position = player.global_position + Vector3.UP * 2.0
		for _i in 26:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, s["n"]])
		print("saved ", s["n"])

	# The customisation screen, with a recoloured player behind it.
	dbg.set("visible", false)
	hud.set("debug_visible", false)
	appear.call("open")
	for _i in 30:
		await process_frame
	root.get_texture().get_image().save_png("%s/08_appearance.png" % out_dir)
	print("saved 08_appearance")
	print(world.call("build_report"))
	quit()


func _near(n: Node3D, d: float) -> Vector3:
	return n.global_position + Vector3(d, 0, d * 0.4)


func _front_of(door: Door, d: float) -> Vector3:
	var axis := door.global_transform.basis.z.normalized()
	var ruin: Node3D = door.get_parent()
	var to_c := ruin.global_position - door.global_position
	var out_dir := axis if axis.dot(to_c) < 0.0 else -axis
	return door.global_position + out_dir * d
