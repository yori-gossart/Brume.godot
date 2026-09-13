extends SceneTree
func _init() -> void: _run.call_deferred()
func _run() -> void:
	for p in ["res://assets/materials/noise_soft.tres", "res://assets/materials/noise_water.tres"]:
		var t: NoiseTexture2D = load(p)
		print(p, "  w=", t.width, " h=", t.height, " seamless=", t.seamless, " normal=", t.as_normal_map)
		# NoiseTexture2D bakes on a worker thread; wait for it.
		for _i in 240:
			await process_frame
			if t.get_image() != null:
				break
		var img := t.get_image()
		if img == null:
			print("   IMAGE IS NULL — never generated")
			continue
		var lo := 2.0; var hi := -2.0; var sum := 0.0; var n := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var v := img.get_pixel(x, y).r
				lo = minf(lo, v); hi = maxf(hi, v); sum += v; n += 1
		print("   red channel: min=%.3f mean=%.3f max=%.3f  format=%d" % [lo, sum / n, hi, img.get_format()])
	# And confirm which renderer the project actually asks for.
	print("rendering_method = ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("rendering_method.mobile = ", ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"))
	quit()
