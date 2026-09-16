extends Node3D
class_name Door
##
## A door that is actually a door (sections 23, 55).
##
## THE IMPORTANT DECISION: the leaf's collision is never disabled. Not when
## open, not while swinging, not ever.
##
## The obvious implementation is to turn the collider off once the door is
## "open". Section 23 warns against the early version of that bug — do not
## disable collision before the leaf has swung far enough — but disabling it
## at all is the wrong shape. It means that at some instant a solid object
## stops being solid, and that instant is a bug waiting to be found by a
## player standing in the doorway.
##
## Here the leaf is an AnimatableBody3D on WORLD_STATIC for its whole life.
## It swings on a hinge, and the doorway becomes passable for exactly one
## reason: the leaf is no longer in it. That is also why it pushes a player
## who is standing in the way instead of sweeping through them —
## AnimatableBody3D with sync_to_physics is the node built for this.
##
## `tests/door_test.gd` walks the player at the closed door (must be blocked)
## and at the open door (must pass through), rather than reading a flag.

signal state_changed(state: int)

enum State { CLOSED, OPENING, OPEN, CLOSING }

@export var leaf_width: float = 1.05
@export var leaf_height: float = 2.05
@export var leaf_thickness: float = 0.12
## Positive swings the leaf one way, negative the other.
@export var open_angle_deg: float = 95.0
@export var swing_time: float = 0.85
## Build the surrounding frame. Off when the door sits in a wall that
## already has its own posts.
@export var build_frame: bool = true
@export var start_open: bool = false

var state: int = State.CLOSED
## 0 = shut, 1 = fully open.
var open_ratio: float = 0.0

var _hinge: Node3D
var _leaf: AnimatableBody3D
var _component: InteractableComponent
var _wood := BuildKit.material(Color(0.412, 0.306, 0.208), 0.85)
var _iron := BuildKit.material(Color(0.204, 0.212, 0.227), 0.45, 0.8)


func _ready() -> void:
	_build()
	if start_open:
		open_ratio = 1.0
		state = State.OPEN
		_apply_swing()
	_refresh_prompt()


func _build() -> void:
	var frame_body: StaticBody3D = null
	if build_frame:
		frame_body = StaticBody3D.new()
		frame_body.name = "DoorFrame"
		frame_body.collision_layer = Layers.WORLD_STATIC
		frame_body.collision_mask = 0
		SurfaceType.tag(frame_body, SurfaceType.Kind.WOOD)
		add_child(frame_body)
		var post := 0.14
		for s in [-1.0, 1.0]:
			BuildKit.box(self, frame_body, _wood,
				Vector3(s * (leaf_width * 0.5 + post * 0.5), leaf_height * 0.5, 0.0),
				Vector3(post, leaf_height + 0.12, leaf_thickness * 2.2))
		BuildKit.box(self, frame_body, _wood,
			Vector3(0.0, leaf_height + 0.08, 0.0),
			Vector3(leaf_width + post * 2.2, 0.16, leaf_thickness * 2.2))

	# --- the leaf, which IS the hinge ------------------------------------
	# The body is placed at the hinge line and rotated directly; the mesh and
	# the collider are offset half a leaf-width inside it.
	#
	# The obvious structure — a Node3D hinge with the body parented to it —
	# does not work, and fails silently in the worst possible way. An
	# AnimatableBody3D with sync_to_physics follows its OWN transform being
	# set; rotating a parent moves the visual leaf while the physics body
	# stays where it was last placed. The door then looks open and is still
	# solid across the doorway. Rotating the body itself is the fix.
	_leaf = AnimatableBody3D.new()
	_leaf.name = "Leaf"
	_leaf.position = Vector3(-leaf_width * 0.5, 0.0, 0.0)
	_leaf.collision_layer = Layers.WORLD_STATIC
	_leaf.collision_mask = 0
	# Move characters out of the way rather than sweeping through them.
	_leaf.sync_to_physics = true
	SurfaceType.tag(_leaf, SurfaceType.Kind.WOOD)
	add_child(_leaf)
	_hinge = _leaf

	var mesh := BoxMesh.new()
	mesh.size = Vector3(leaf_width, leaf_height, leaf_thickness)
	var mi := MeshInstance3D.new()
	mi.name = "LeafMesh"
	mi.mesh = mesh
	mi.material_override = _wood
	mi.position = Vector3(leaf_width * 0.5, leaf_height * 0.5, 0.0)
	_leaf.add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var cs := CollisionShape3D.new()
	cs.name = "LeafCollision"
	cs.shape = shape
	cs.position = mi.position
	_leaf.add_child(cs)

	# Planks and a handle, so it reads as a door at a glance.
	for i in 3:
		var plank := BoxMesh.new()
		plank.size = Vector3(leaf_width * 0.92, 0.1, leaf_thickness * 1.35)
		var pm := MeshInstance3D.new()
		pm.mesh = plank
		pm.material_override = _iron
		pm.position = Vector3(leaf_width * 0.5, 0.35 + float(i) * 0.7, 0.0)
		_leaf.add_child(pm)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.045
	handle.bottom_radius = 0.045
	handle.height = 0.22
	handle.radial_segments = 6
	var hm := MeshInstance3D.new()
	hm.mesh = handle
	hm.material_override = _iron
	hm.position = Vector3(leaf_width * 0.87, leaf_height * 0.5, leaf_thickness * 0.9)
	hm.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	_leaf.add_child(hm)

	# --- the sensor, at the handle, not at the hinge ----------------------
	_component = InteractableComponent.new()
	_component.name = "Interact"
	_component.action = InteractableComponent.Action.OPEN
	_component.noun = "Porte"
	_component.interact_range = 2.0
	_component.interact_priority = 2
	_component.requires_line_of_sight = true
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	var scs := CollisionShape3D.new()
	scs.shape = sphere
	_component.add_child(scs)
	_component.position = Vector3(0.0, leaf_height * 0.5, 0.0)
	add_child(_component)
	_component.interacted.connect(_on_interacted)

	var def := WorldObjectDefinition.new()
	def.id = &"door"
	def.display_name = "Porte"
	def.category = WorldObjectDefinition.Category.STATIC_INTERACTABLE
	def.solid = true
	def.interactable = true
	def.surface_type = SurfaceType.Kind.WOOD
	def.interaction_type = "door"
	def.collision_profile = WorldObjectDefinition.CollisionProfile.BOX
	_component.definition = def


func _physics_process(delta: float) -> void:
	if state != State.OPENING and state != State.CLOSING:
		return
	var step := delta / maxf(swing_time, 0.05)
	if state == State.OPENING:
		open_ratio = minf(1.0, open_ratio + step)
		if is_equal_approx(open_ratio, 1.0):
			_set_state(State.OPEN)
	else:
		open_ratio = maxf(0.0, open_ratio - step)
		if is_zero_approx(open_ratio):
			_set_state(State.CLOSED)
	_apply_swing()


func _apply_swing() -> void:
	# Ease so the leaf settles instead of stopping dead.
	var t := open_ratio * open_ratio * (3.0 - 2.0 * open_ratio)
	_leaf.rotation.y = deg_to_rad(open_angle_deg) * t


func _on_interacted(_actor: Node3D) -> void:
	toggle()


func toggle() -> void:
	if state == State.CLOSED or state == State.CLOSING:
		open()
	elif state == State.OPEN or state == State.OPENING:
		close()


func open() -> void:
	if state == State.OPEN or state == State.OPENING:
		return
	_set_state(State.OPENING)


func close() -> void:
	if state == State.CLOSED or state == State.CLOSING:
		return
	_set_state(State.CLOSING)


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	# No interacting mid-swing: it produces a door that stutters between
	# states and a prompt that flickers.
	_component.enabled = (s == State.OPEN or s == State.CLOSED)
	_refresh_prompt()
	state_changed.emit(s)


func _refresh_prompt() -> void:
	if _component == null:
		return
	_component.action = (InteractableComponent.Action.CLOSE
		if (state == State.OPEN or state == State.OPENING)
		else InteractableComponent.Action.OPEN)
	_component.set_state(StringName(state_name()))


## Wide enough to walk through? Used by the navigation rebuild and by tests.
func is_passable() -> bool:
	return open_ratio > 0.62


func state_name() -> String:
	return ["CLOSED", "OPENING", "OPEN", "CLOSING"][state]


## The centre of the opening, in world space — where a test should aim.
func opening_centre() -> Vector3:
	return global_position + global_transform.basis.y * (leaf_height * 0.5)
