extends InteractableComponent
class_name Pickup
##
## A collectable lying in the world.
##
## It is an InteractableComponent like everything else interactive, so the
## player's scanner does not need to know pickups exist as a special case —
## which is what it needed in 0.1.
##
## What it *is* comes from an ItemDefinition resource (section 31): name,
## weight, category, rarity, prompt verb. Adding a resource type is a .tres
## file, not a branch in this script.

@export var item: ItemDefinition
@export var amount: int = 1
## Fallback used when no ItemDefinition is assigned, and by WorldRoot when it
## spawns pickups by name.
@export_enum("BOIS", "CRISTAL") var kind: String = "BOIS"
@export var spin_speed: float = 0.9
@export var bob_height: float = 0.09
@export var bob_speed: float = 1.7

var _taken := false
var _t := 0.0
var _base_y := 0.0

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	_build_visual()
	_base_y = _visual.position.y
	_t = randf() * TAU
	# PICKUP is a sensor layer, not an obstacle layer: no character's
	# movement mask includes it, so a collectable can never block anyone.
	collision_layer = Layers.PICKUP
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(&"interactable")
	add_to_group(&"pickup")
	action = InteractableComponent.Action.TAKE
	noun = item.display_name if item else kind.capitalize()
	# Generous compared with a door: you are meant to grab this at a run,
	# not line up with it.
	interact_range = 2.6
	interact_priority = 0
	# A twig on the far side of a wall is not worth a raycast argument; but
	# it is still scored on angle, so you cannot take what is behind you.
	requires_line_of_sight = false


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_visual.rotate_y(spin_speed * delta)
	_visual.position.y = _base_y + sin(_t * bob_speed) * bob_height


## The visual is built here rather than shipped as two scenes, so that one
## Pickup.tscn covers both resources and the `kind` export is the only thing
## that differs between them.
func _build_visual() -> void:
	for c in _visual.get_children():
		c.queue_free()
	if kind == "CRISTAL":
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.36, 0.78, 0.80)
		mat.roughness = 0.15
		mat.metallic_specular = 0.85
		mat.emission_enabled = true
		mat.emission = Color(0.42, 0.88, 0.86)
		mat.emission_energy_multiplier = 1.9
		for i in 3:
			var m := SphereMesh.new()
			m.radius = 0.11 - float(i) * 0.022
			m.height = 0.42 - float(i) * 0.09
			m.radial_segments = 5
			m.rings = 2
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = mat
			var a := TAU * float(i) / 3.0
			mi.position = Vector3(cos(a) * 0.09, 0.16 - float(i) * 0.03, sin(a) * 0.09)
			mi.rotation = Vector3(cos(a) * 0.35, a, sin(a) * 0.35)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_visual.add_child(mi)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.45, 0.9, 0.88)
		glow.light_energy = 1.1
		glow.omni_range = 3.4
		glow.shadow_enabled = false
		glow.position = Vector3(0, 0.2, 0)
		_visual.add_child(glow)
	else:
		# BOIS: a small bundle of cut branches.
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color(0.353, 0.255, 0.169)
		bark.roughness = 0.93
		var cut := StandardMaterial3D.new()
		cut.albedo_color = Color(0.667, 0.545, 0.365)
		cut.roughness = 0.85
		var offsets := [
			Vector3(0.0, 0.06, 0.0), Vector3(0.085, 0.06, 0.05),
			Vector3(-0.07, 0.06, 0.06), Vector3(0.02, 0.155, 0.03)]
		for i in offsets.size():
			var m := CylinderMesh.new()
			m.top_radius = 0.048
			m.bottom_radius = 0.052
			m.height = 0.56
			m.radial_segments = 6
			m.rings = 1
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = bark if i < 3 else cut
			mi.position = offsets[i]
			mi.rotation = Vector3(deg_to_rad(90.0), float(i) * 0.42, deg_to_rad(4.0 * i))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_visual.add_child(mi)


	# Four cylinders (or three shards) per pickup, times two dozen pickups,
	# is a lot of draw calls for a twig. Merge each one down to one per
	# material.
	BuildKit.merge_by_material(_visual)


## Called by WorldRoot after `kind` is assigned.
func set_kind_visual(k: String) -> void:
	kind = k
	item = null
	noun = _definition().display_name if _definition() else k.capitalize()
	if is_inside_tree():
		_build_visual()


func can_interact(_actor: Node3D) -> bool:
	return enabled and not _taken


func item_id() -> StringName:
	return item.id if item else StringName(kind)


## Taken. The object flies to the collector and disappears.
##
## Read what this does NOT do to the collector: nothing. No velocity change,
## no rotation, no state change. That is the whole of section 28, and it is
## why it works at a dead run.
func perform(actor: Node3D) -> bool:
	if _taken:
		return false
	_taken = true
	set_state(&"TAKEN")
	monitorable = false
	set_deferred("monitoring", false)
	var inter := actor.get_node_or_null("Interactor")
	if inter and inter.has_method("register_item"):
		inter.call("register_item", _definition(), amount)
	interacted.emit(actor)
	_fly_to(actor)
	return true


## The ItemDefinition for this pickup, loading the shared one by name when
## the scene did not assign it directly.
func _definition() -> ItemDefinition:
	if item:
		return item
	var path := "res://assets/data/items/%s.tres" % ("wood" if kind == "BOIS" else "crystal")
	if ResourceLoader.exists(path):
		item = load(path)
	return item


func _fly_to(collector: Node3D) -> bool:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position",
		collector.global_position + Vector3.UP * 1.0, 0.28).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_visual, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
	return true
