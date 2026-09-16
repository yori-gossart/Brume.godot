extends Node3D
class_name StonePillar
##
## An ancient beacon pillar with an empty crystal socket (sections 25, 47).
##
## This is where the CRYSTAL is defined by what it does, rather than by a
## label. Section 47 asks that the crystal not be coded as "magic fire": so
## the pillar accepts ONLY a crystal, the campfire accepts ONLY wood, and
## neither will take the other's fuel. They are different technologies that
## happen to both emit light.
##
## Solid: the shaft is a cylinder on WORLD_STATIC. You cannot walk through
## an ancient pillar (section 25).

signal activated

@export var height: float = 3.4
@export var radius: float = 0.42
@export var required_item: StringName = &"CRISTAL"

var is_active := false

var _component: InteractableComponent
var _gem: MeshInstance3D
var _gem_mat: ShaderMaterial
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "PillarCollision"
	body.collision_layer = Layers.WORLD_STATIC
	body.collision_mask = 0
	SurfaceType.tag(body, SurfaceType.Kind.ROCK)
	add_child(body)

	var stone := BuildKit.material(Color(0.353, 0.341, 0.322), 0.93)
	var stone_dark := BuildKit.material(Color(0.251, 0.243, 0.231), 0.95)

	BuildKit.box(self, body, stone_dark, Vector3(0, 0.14, 0), Vector3(1.5, 0.28, 1.5))
	BuildKit.cylinder(self, body, stone, Vector3(0, height * 0.5 + 0.2, 0),
		radius, height, Vector3.ZERO, true, 8)
	# A broken crown, so it reads as ancient rather than as a bollard.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		BuildKit.box(self, null, stone_dark,
			Vector3(cos(a) * radius * 1.1, height + 0.28, sin(a) * radius * 1.1),
			Vector3(0.2, 0.34 + 0.16 * sin(float(i) * 2.1), 0.2),
			Vector3(0.1, a, 0.08), false)

	# The socket, empty.
	_gem_mat = ShaderMaterial.new()
	_gem_mat.shader = load("res://shaders/crystal.gdshader")
	_gem_mat.set_shader_parameter("pulse", 0.0)
	var gm := SphereMesh.new()
	gm.radius = 0.2
	gm.height = 0.55
	gm.radial_segments = 6
	gm.rings = 3
	_gem = MeshInstance3D.new()
	_gem.name = "Socket"
	_gem.mesh = gm
	_gem.material_override = _gem_mat
	_gem.position = Vector3(0, height + 0.12, 0)
	_gem.visible = false
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_gem)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, height + 0.12, 0)
	_light.light_color = Color(0.51, 0.92, 0.88)
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	add_child(_light)

	_component = InteractableComponent.new()
	_component.name = "Interact"
	_component.action = InteractableComponent.Action.INSERT
	_component.noun = "Pilier"
	_component.interact_range = 2.2
	_component.interact_priority = 3
	_component.requires_line_of_sight = true
	var sh := SphereShape3D.new()
	sh.radius = 2.0
	var cs := CollisionShape3D.new()
	cs.shape = sh
	_component.add_child(cs)
	_component.position = Vector3(0, height * 0.6, 0)
	add_child(_component)
	_component.interacted.connect(_on_interacted)
	_component.condition_target = self

	var def := WorldObjectDefinition.new()
	def.id = &"stone_pillar"
	def.display_name = "Pilier ancien"
	def.category = WorldObjectDefinition.Category.STATIC_INTERACTABLE
	def.solid = true
	def.interactable = true
	def.surface_type = SurfaceType.Kind.ROCK
	def.interaction_type = "insert_crystal"
	def.collision_profile = WorldObjectDefinition.CollisionProfile.COMPOUND
	_component.definition = def
	set_process(false)


## Only offered when the actor is actually carrying a crystal. A prompt you
## cannot satisfy is worse than no prompt.
func _has_crystal(actor: Node3D) -> bool:
	var inter := actor.get_node_or_null("Interactor")
	if inter == null or not inter.has_method("total_of"):
		return false
	return int(inter.call("total_of", required_item)) > 0


## Offered only to an actor carrying a crystal, and only while empty.
func can_be_used_by(actor: Node3D) -> bool:
	return not is_active and _has_crystal(actor)


func _on_interacted(actor: Node3D) -> void:
	if is_active or not _has_crystal(actor):
		return
	var inter := actor.get_node_or_null("Interactor")
	if inter and inter.has_method("consume_item"):
		if not bool(inter.call("consume_item", required_item, 1)):
			return
	is_active = true
	_gem.visible = true
	_component.enabled = false
	_component.set_state(&"ACTIVE")
	set_process(true)
	activated.emit()


func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.5 + 0.42 * sin(_t * 1.7) + 0.08 * sin(_t * 5.3)
	pulse = clampf(pulse, 0.0, 1.0)
	_gem_mat.set_shader_parameter("pulse", pulse)
	_light.light_energy = lerpf(1.4, 4.2, pulse)
	_gem.rotate_y(delta * 0.7)
