extends SceneTree

func _init() -> void:
	var S := TerrainData.SIZE
	var minh := 1e9
	var maxh := -1e9
	var water := 0
	var swim := 0
	var wade := 0
	var steep := 0
	var total := 0
	var step := 2.0
	var x := -S
	while x <= S:
		var z := -S
		while z <= S:
			var h := TerrainData.height_at(x, z)
			minh = minf(minh, h); maxh = maxf(maxh, h)
			total += 1
			var d := TerrainData.water_depth_at(x, z)
			if d > 0.0:
				water += 1
				if d >= TerrainData.SWIM_DEPTH: swim += 1
				else: wade += 1
			elif TerrainData.normal_at(x, z).y < TerrainData.MAX_WALK_DOT:
				steep += 1
			z += step
		x += step
	print("samples=%d  height min=%.2f max=%.2f" % [total, minh, maxh])
	print("water cells=%d (%.1f%%)  wading=%d  swimmable=%d" % [water, 100.0*water/total, wade, swim])
	print("steep land cells=%d (%.1f%%)" % [steep, 100.0*steep/total])
	# Spawn point and a few landmarks
	for p in [Vector2(0,110), Vector2(-58,-62), Vector2(62,48), Vector2(-10,34), Vector2(-26,-52)]:
		print("  at (%.0f,%.0f) h=%.2f depth=%.2f walkable=%s" % [p.x, p.y,
			TerrainData.height_at(p.x,p.y), TerrainData.water_depth_at(p.x,p.y),
			str(TerrainData.is_walkable(p.x,p.y))])
	# Where does the path ford the river?
	var fx := -140.0
	while fx <= 140.0:
		var pz := TerrainData.path_center_z(fx)
		var d2 := TerrainData.water_depth_at(fx, pz)
		if d2 > 0.05:
			print("  path ford at x=%.0f z=%.1f depth=%.2f" % [fx, pz, d2])
		fx += 6.0
	quit()
