extends SceneTree
# Measure the stride axis across the whole walk cycle, and which direction
# the swing foot travels during its forward phase.
func _init() -> void:
	var n: Node3D = (load("res://assets/characters/player_hooded_scout.glb") as PackedScene).instantiate()
	root.add_child(n)
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	var bi := sk.find_bone("toes.l")
	var hi := sk.find_bone("hips")
	var anim := ap.get_animation("Walking_A")
	ap.play("Walking_A")
	var xs := []
	var zs := []
	var lift_forward := Vector3.ZERO
	var prev := Vector3.ZERO
	for s in 61:
		ap.seek(anim.length * float(s) / 60.0, true)
		sk.force_update_all_bone_transforms()
		var t := sk.get_bone_global_pose(bi).origin
		xs.append(t.x); zs.append(t.z)
		# While the foot is high it is swinging forward.
		if s > 0 and t.y > 0.09:
			lift_forward += t - prev
		prev = t
	var xr: float = xs.max() - xs.min()
	var zr: float = zs.max() - zs.min()
	print("toes.l travel range over the cycle:  x=%.3f  z=%.3f" % [xr, zr])
	print("swing-phase net displacement: %s" % str(lift_forward))
	print("=> stride axis is %s ; the swing foot moves towards %s" % [
		"X" if xr > zr else "Z",
		("+Z" if lift_forward.z > 0.0 else "-Z") if zr > xr else ("+X" if lift_forward.x > 0.0 else "-X")])
	n.queue_free()
	quit()
