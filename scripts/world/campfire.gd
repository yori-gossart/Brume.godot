extends Node3D
class_name Campfire
##
## A campfire with two honest states (section 46).
##
## It burns WOOD. It does not burn crystal, and lighting it is not the same
## verb as activating a beacon — section 46 is explicit that fire and crystal
## must not converge into one concept. Fire is warmth, rest, cooking and a
## moment's respite; the crystal is ancient machinery. They stay apart here
## by taking different fuel and by reading differently.

signal lit
signal extinguished

enum State { UNLIT, LIT }

@export var required_item: StringName = &"BOIS"
@export var fuel_cost: int = 1
@export var start_lit: bool = false
## Debug/testing hook: light it without carrying wood.
@export var allow_free_lighting: bool = false

var state: int = State.UNLIT

var _component: InteractableComponent
var _light: OmniLight3D
var _flames: GPUParticles3D
var _embers: GPUParticles3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "FireRingCollision"
	body.collision_layer = Layers.WORLD_STATIC
	body.collision_mask = 0
	SurfaceType.tag(body, SurfaceType.Kind.ROCK)
	add_child(body)

	var stone := BuildKit.material(Color(0.318, 0.31, 0.298), 0.94)
	var charred := BuildKit.material(Color(0.114, 0.102, 0.094), 0.96)
	var wood := BuildKit.material(Color(0.325, 0.239, 0.161), 0.9)

	# Ring of stones — low, so it is a kerb you step over, not a wall.
	for i in 9:
		var a := TAU * float(i) / 9.0
		BuildKit.box(self, body, stone,
			Vector3(cos(a) * 0.62, 0.09, sin(a) * 0.62),
			Vector3(0.26, 0.19, 0.22), Vector3(0.12, a, 0.1))
	BuildKit.cylinder(self, null, charred, Vector3(0, 0.03, 0), 0.55, 0.06,
		Vector3.ZERO, false, 10)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.5
		BuildKit.cylinder(self, null, wood,
			Vector3(cos(a) * 0.1, 0.2, sin(a) * 0.1), 0.055, 0.7,
			Vector3(cos(a) * 0.55, -a, sin(a) * 0.55), false, 5)

	_glow_mat = BuildKit.material(Color(0.35, 0.16, 0.07), 0.9, 0.0,
		Color(1.0, 0.55, 0.18), 0.0)
	_glow = BuildKit.cylinder(self, null, _glow_mat, Vector3(0, 0.06, 0), 0.34, 0.05,
		Vector3.ZERO, false, 8)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.position = Vector3(0, 0.55, 0)
	_light.light_color = Color(1.0, 0.63, 0.31)
	_light.light_energy = 0.0
	_light.omni_range = 11.0
	_light.shadow_enabled = false
	add_child(_light)

	_flames = _make_particles(Color(1.0, 0.55, 0.16), 0.55, 1.6, 26, 0.9)
	_embers = _make_particles(Color(1.0, 0.78, 0.42), 0.12, 3.2, 14, 2.4)

	_component = InteractableComponent.new()
	_component.name = "Interact"
	_component.action = InteractableComponent.Action.LIGHT
	_component.noun = "Feu"
	_component.interact_range = 2.1
	_component.interact_priority = 2
	_component.requires_line_of_sight = false
	var sh := SphereShape3D.new()
	sh.radius = 1.9
	var cs := CollisionShape3D.new()
	cs.shape = sh
	_component.add_child(cs)
	_component.position = Vector3(0, 0.5, 0)
	add_child(_component)
	_component.interacted.connect(_on_interacted)
	_component.condition_target = self

	var def := WorldObjectDefinition.new()
	def.id = &"campfire"
	def.display_name = "Feu de camp"
	def.category = WorldObjectDefinition.Category.STATIC_INTERACTABLE
	def.solid = true
	def.interactable = true
	def.surface_type = SurfaceType.Kind.ROCK
	def.interaction_type = "light_fire"
	def.collision_profile = WorldObjectDefinition.CollisionProfile.COMPOUND
	_component.definition = def

	if start_lit:
		_set_state(State.LIT)
	else:
		_set_state(State.UNLIT)


func _make_particles(col: Color, size: float, life: float, amount: int, rise: float) -> GPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog_particle.gdshader")
	mat.set_shader_parameter("wisp_color", Vector3(col.r, col.g, col.b))
	mat.set_shader_parameter("strength", 1.0)
	mat.set_shader_parameter("softness", 0.9)

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.18
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 14.0
	proc.initial_velocity_min = rise * 0.4
	proc.initial_velocity_max = rise
	proc.gravity = Vector3(0.1, 0.35, 0.0)
	proc.scale_min = 0.5
	proc.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.18, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	proc.alpha_curve = ct

	var p := GPUParticles3D.new()
	p.draw_pass_1 = quad
	p.material_override = mat
	p.process_material = proc
	p.amount = amount
	p.lifetime = life
	p.position = Vector3(0, 0.18, 0)
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 5, 3))
	add_child(p)
	return p


func _on_interacted(actor: Node3D) -> void:
	if state == State.LIT:
		_set_state(State.UNLIT)
		return
	if not allow_free_lighting:
		var inter := actor.get_node_or_null("Interactor")
		if inter == null or not inter.has_method("consume_item"):
			return
		if not bool(inter.call("consume_item", required_item, fuel_cost)):
			return
	_set_state(State.LIT)


## Can it be lit right now? Drives whether the prompt is offered at all.
func can_be_used_by(actor: Node3D) -> bool:
	if state == State.LIT:
		return true
	if allow_free_lighting:
		return true
	var inter := actor.get_node_or_null("Interactor")
	if inter == null or not inter.has_method("total_of"):
		return false
	return int(inter.call("total_of", required_item)) >= fuel_cost


func _set_state(s: int) -> void:
	state = s
	var on := s == State.LIT
	_flames.emitting = on
	_embers.emitting = on
	_glow_mat.emission_energy_multiplier = 2.6 if on else 0.0
	_component.action = (InteractableComponent.Action.EXTINGUISH if on
		else InteractableComponent.Action.LIGHT)
	_component.set_state(&"LIT" if on else &"UNLIT")
	set_process(on)
	if on:
		lit.emit()
	else:
		_light.light_energy = 0.0
		extinguished.emit()


func _process(delta: float) -> void:
	_t += delta
	# Flicker on two beats so it never looks like a sine wave.
	var f := 0.72 + 0.2 * sin(_t * 7.3) + 0.12 * sin(_t * 17.1 + 1.3)
	_light.light_energy = 3.1 * f
	_light.omni_range = lerpf(10.0, 12.0, f)


func state_name() -> String:
	return "LIT" if state == State.LIT else "UNLIT"
