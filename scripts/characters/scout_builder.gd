extends RefCounted
class_name ScoutBuilder
##
## THE NOMADSLAND SCOUT — first Quaternius composition (0.2.2).
##
## Three files, one skeleton. Verified before writing a line of this: the
## base character, the Ranger outfit and the UAL1 animation library all use
## the SAME 65-joint rig, same names, same order (root, pelvis, spine_01 ...).
## So there is no retargeting to do — the outfit meshes are reparented onto
## the base skeleton and the animation library is bound to it as it is.
##
## COMPOSITION, and why this one:
##
##   base  Superhero_Male_FullBody   body AND head, one single mesh
##   +     Eyes, Eyebrows            from the same file
##   +     Male_Ranger (all 9 parts) clothing, boots, hood, bracers, belts
##
## The Ranger set has no face: its only head piece is `Head_Hood`. The base
## body is a single mesh, so the head cannot be taken from it on its own.
## Layering the outfit over the whole base body is therefore the only
## composition that is not headless — and it is also how Quaternius' modular
## sets are meant to be worn. The base body ends up hidden under the
## clothing; that costs vertices, not pixels.
##
## NOT USED, on purpose: UAL1_Standard_RM (root motion). Movement in this
## game is driven by the controller and validated in 0.2.1b; root motion
## would fight it.

const BASE := "res://assets/quaternius/characters/Superhero_Male_FullBody.gltf"
const OUTFIT := "res://assets/quaternius/outfits/Male_Ranger.gltf"
const ANIMS := "res://assets/quaternius/animations/UAL1_Standard.glb"



## Builds the scout under `parent`, removing whatever model was there.
## Returns the model root, or null if an asset is missing.
static func build(parent: Node3D) -> Node3D:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()

	var base_scene := load(BASE) as PackedScene
	var outfit_scene := load(OUTFIT) as PackedScene
	var anim_scene := load(ANIMS) as PackedScene
	if base_scene == null or outfit_scene == null or anim_scene == null:
		push_error("ScoutBuilder: missing Quaternius asset")
		return null

	var model := base_scene.instantiate() as Node3D
	model.name = "NomadScout"
	parent.add_child(model)

	var skel := model.find_child("*Skeleton3D*", true, false) as Skeleton3D
	if skel == null:
		for n in _all(model):
			if n is Skeleton3D:
				skel = n
				break
	if skel == null:
		push_error("ScoutBuilder: no Skeleton3D in the base character")
		return model

	_shrink_base_body(model)
	_wear(outfit_scene, skel)
	_bind_animations(anim_scene, model, skel)
	return model


## Push the base body a centimetre inside the clothing.
##
## The outfit is modelled to sit ON the regular male body; worn over the
## slightly different superhero body it pokes through at the chest, the abs
## and the thighs. Rather than edit meshes, the body material grows along
## its normals by a NEGATIVE amount, which is the standard fix and costs
## nothing at runtime. The head shrinks by the same centimetre, which is not
## visible.
static func _shrink_base_body(model: Node3D) -> void:
	for n in _all(model):
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			if not str(sm.resource_name).contains("Superhero"):
				continue
			sm.grow = true
			sm.grow_amount = -0.012
			mi.set_surface_override_material(i, sm)


## Move an outfit's meshes onto the base skeleton and throw the rest away.
##
## The meshes keep their own Skin: Godot resolves a skin's binds by BONE NAME
## when the glTF importer wrote bind names, which it does. Identical rigs, so
## every bind finds its bone.
static func _wear(outfit_scene: PackedScene, skel: Skeleton3D) -> void:
	var outfit := outfit_scene.instantiate() as Node3D
	var pieces: Array[MeshInstance3D] = []
	for n in _all(outfit):
		if n is MeshInstance3D:
			pieces.append(n)
	for m in pieces:
		# Clear the owner first or Godot warns about an inconsistent scene.
		m.owner = null
		m.get_parent().remove_child(m)
		skel.add_child(m)
		# A MeshInstance3D parented to a Skeleton3D points at it with "..".
		m.skeleton = NodePath("..")
		# One character, one shadow caster set: the base body underneath is
		# hidden by the clothing but would still cast into the shadow map.
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	outfit.queue_free()


## Bind the UAL1 library to the composed model.
##
## The tracks address bones by NODE PATH, not by bone name — "Armature/
## Skeleton3D:pelvis" as the library ships. That path is relative to the
## AnimationPlayer's root, so it only resolves if the composed model happens
## to put its skeleton at the same place. Rather than hope, the prefix is
## rewritten to wherever the base character actually keeps its skeleton.
## Tracks addressing anything else — the library ships a Mannequin mesh —
## are dropped rather than left to warn every frame.
static func _bind_animations(anim_scene: PackedScene, model: Node3D,
		skel: Skeleton3D) -> void:
	var src := anim_scene.instantiate() as Node3D
	var src_player: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
	if src_player == null:
		push_error("ScoutBuilder: no AnimationPlayer in the animation library")
		src.queue_free()
		return

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	model.add_child(player)
	player.root_node = NodePath("..")

	var src_skel: Skeleton3D = src.find_child("Skeleton3D", true, false)
	if src_skel == null:
		for n in _all(src):
			if n is Skeleton3D:
				src_skel = n
				break
	var from_prefix := str(src.get_path_to(src_skel)) + ":"
	var to_prefix := str(model.get_path_to(skel)) + ":"

	for lib_name in src_player.get_animation_library_list():
		var lib: AnimationLibrary = src_player.get_animation_library(lib_name)
		var out := AnimationLibrary.new()
		for clip in lib.get_animation_list():
			var a: Animation = lib.get_animation(clip).duplicate(true)
			for t in range(a.get_track_count() - 1, -1, -1):
				var path := str(a.track_get_path(t))
				if not path.begins_with(from_prefix):
					a.remove_track(t)
					continue
				if from_prefix != to_prefix:
					a.track_set_path(t, NodePath(to_prefix + path.substr(from_prefix.length())))
			if a.get_track_count() > 0:
				out.add_animation(clip, a)
		player.add_animation_library(lib_name, out)
	src.queue_free()


static func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
