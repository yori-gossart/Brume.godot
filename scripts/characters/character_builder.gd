extends RefCounted
class_name CharacterBuilder
##
## Turn a CharacterAppearance into an actual model under a pivot.
##
## Shared by the player and every NPC, so a nomad and the person playing as
## one are assembled by identical code. That is section 5's requirement
## restated as an implementation detail: they must obviously belong to the
## same species and the same world, and the cheapest way to guarantee that
## is to give them no separate code path in which to drift apart.


## Replace whatever is under `pivot` with the body this appearance names.
## Returns the new model root, or null if the body scene is missing.
static func build(pivot: Node3D, appearance: CharacterAppearance) -> Node3D:
	if pivot == null:
		return null
	if appearance == null:
		appearance = CharacterAppearance.make_default()

	var path := appearance.body_scene_path()
	if not ResourceLoader.exists(path):
		push_error("CharacterBuilder: missing body scene %s" % path)
		return null

	for c in pivot.get_children():
		pivot.remove_child(c)
		c.queue_free()

	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.name = "Model"
	pivot.add_child(model)

	# Fog Nomad has no combat; the Adventurers pack ships weapons regardless.
	LocomotionRig.hide_weapons(model)
	# Then paint. Order matters: the appearance also decides which
	# accessories are visible, and it must not un-hide a crossbow.
	appearance.apply_to(model)
	return model
