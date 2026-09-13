extends SceneTree
##
## Find the ground speed each in-place locomotion clip is authored for.
##
## Method: move a virtual body forward at a known speed V while playing the
## clip at playback rate k, and track the PLANTED foot in world space. The
## planted foot is stationary exactly when k * A == V, where A is the clip's
## authored speed. So sweep k, find the minimum, and read A = V / k.
##
## This is the number LocomotionRig.WALK_REF / RUN_REF must hold. Re-run it
## if the character model is ever changed.
##
##   godot --headless --path . --script tools/calibrate_stride.gd

func _init() -> void:
	var n: Node3D = (load("res://assets/characters/player_hooded_scout.glb") as PackedScene).instantiate()
	root.add_child(n)
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	var lt := sk.find_bone("toes.l")
	var rt := sk.find_bone("toes.r")

	for pair in [["Walking_A", 2.0], ["Running_A", 5.0], ["Walking_B", 2.0], ["Running_B", 5.0]]:
		var clip: String = pair[0]
		var v: float = pair[1]
		var best_k := 0.0
		var best_slide := 1e9
		var line := PackedStringArray()
		var k := 0.30
		while k <= 3.51:
			var slide := _slide(ap, sk, lt, rt, clip, v, k)
			line.append("%.2f:%.2f" % [k, slide])
			if slide < best_slide:
				best_slide = slide
				best_k = k
			k += 0.05
		print("%s  V=%.1f m/s" % [clip, v])
		print("   best rate k=%.2f  residual planted-foot speed %.3f m/s (%.1f%% of body)"
			% [best_k, best_slide, 100.0 * best_slide / v])
		print("   => authored speed A = V/k = %.3f m/s" % (v / best_k))
	n.queue_free()
	quit()


## Median world-space speed of the planted foot over one cycle.
func _slide(ap: AnimationPlayer, sk: Skeleton3D, lt: int, rt: int,
		clip: String, v: float, k: float) -> float:
	var anim := ap.get_animation(clip)
	# Sample at exactly the rate the in-game check uses (60 Hz over ~2 s), so
	# the floor reported here is directly comparable with the number
	# tools/benchmark_tests.gd measures. Sampling finer than the game runs
	# would report an optimistic floor the game could never reach.
	var dt := 1.0 / 60.0
	var steps := 120
	var samples := []
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	ap.play(clip)
	for s in steps + 1:
		var t: float = float(s) * dt
		ap.seek(fmod(t * k, anim.length), true)
		sk.force_update_all_bone_transforms()
		# The body advances at V; in-place bone poses ride on top of it.
		var carry := Vector3(0, 0, v * t)
		var wl := sk.get_bone_global_pose(lt).origin + carry
		var wr := sk.get_bone_global_pose(rt).origin + carry
		if s > 0:
			samples.append(minf(
				Vector2(wl.x - prev_l.x, wl.z - prev_l.z).length() / dt,
				Vector2(wr.x - prev_r.x, wr.z - prev_r.z).length() / dt))
		prev_l = wl
		prev_r = wr
	samples.sort()
	return samples[samples.size() / 2]
