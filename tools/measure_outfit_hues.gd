extends SceneTree
##
## Which pixels does each mesh of a character actually use?
##
## Clustering the whole atlas tells you what colours EXIST in it; it does not
## tell you which mesh wears which. This walks each mesh's UVs, samples the
## atlas there, and reports the dominant hue per mesh — which is the number
## the recolour band actually needs.
func _init() -> void: _run.call_deferred()

func _run() -> void:
	for path in ["res://assets/characters/player_hooded_scout.glb",
			"res://assets/characters/npc_sturdy.glb",
			"res://assets/characters/npc_tall.glb",
			"res://assets/characters/npc_burdened.glb"]:
		var n: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(n)
		var img: Image = null
		for c in _all(n):
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				var m := (c as MeshInstance3D).mesh.surface_get_material(0)
				if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
					img = (m as BaseMaterial3D).albedo_texture.get_image()
					break
		if img == null:
			print("no atlas for ", path); n.free(); continue
		if img.is_compressed():
			img.decompress()
		print("=== ", path.get_file())
		for c in _all(n):
			if not (c is MeshInstance3D): continue
			var mi := c as MeshInstance3D
			if mi.mesh == null: continue
			var low := str(mi.name).to_lower()
			if low.contains("crossbow") or low.contains("knife") or low.contains("throwable") \
				or low.contains("axe") or low.contains("shield") or low.contains("mug"):
				continue
			var hist := {}
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				if uvs == null: continue
				for i in range(0, uvs.size(), 3):
					var uv := uvs[i]
					var x := clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1)
					var y := clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1)
					var col := img.get_pixel(x, y)
					if col.s < 0.28: continue
					var bucket := int(col.h * 36.0)
					if not hist.has(bucket): hist[bucket] = [0, col]
					hist[bucket][0] += 1
			var keys: Array = hist.keys()
			keys.sort_custom(func(a, b): return hist[a][0] > hist[b][0])
			var top := ""
			for k in keys.slice(0, 2):
				var col: Color = hist[k][1]
				top += " H=%.0f(S%.2f V%.2f)x%d" % [col.h * 360.0, col.s, col.v, hist[k][0]]
			print("   %-26s %s" % [mi.name, top if top != "" else "(no saturated pixels)"])
		n.free()
	quit()

func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children(): out.append_array(_all(c))
	return out
