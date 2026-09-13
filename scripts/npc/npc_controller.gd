extends CharacterBody3D
class_name NpcController
##
## A nomad who is not the player.
##
## Model: KayKit Adventurers "Barbarian" — a different body, a different
## silhouette, a different texture. Section 24 asks for a character that is
## visibly not the player, and section 48 says a distinct model that is never
## actually on screen is a FAIL, so this one walks a loop through the middle
## of the map, on the path, in plain view of the spawn point.
##
## Navigation is a real NavigationAgent3D over the NavigationRegion3D built by
## NavBuilder, which has trunks and boulders carved out of it. The NPC
## therefore walks AROUND a tree rather than through it (section 26).
##
## Facing is taken from the actual travel direction, never from the target,
## so the NPC never moonwalks towards a waypoint behind it.

enum State { IDLE, WALK, ARRIVE }

## Inside Walking_A's honest rate band (see LocomotionRig).
@export var walk_speed: float = 1.4
@export var accel: float = 7.0
@export var turn_speed: float = 6.5
@export var idle_time: Vector2 = Vector2(1.6, 4.2)
@export var min_travel: float = 16.0
@export var max_travel: float = 62.0
@export var nav_builder_path: NodePath

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model_pivot: Node3D = $ModelPivot

var state: int = State.IDLE
var _rig: LocomotionRig
var _nav: NavBuilder
var _rng := RandomNumberGenerator.new()
var _wait := 1.0
var _facing := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)
var _stuck := 0.0

var horizontal_speed: float = 0.0


func _ready() -> void:
	_rng.seed = 0x4E504331     # fixed so the NPC's route is the same every run
	var model: Node3D = model_pivot.get_child(0)
	LocomotionRig.hide_weapons(model)
	_rig = LocomotionRig.new()
	_rig.setup(model)
	_nav = get_node_or_null(nav_builder_path) as NavBuilder
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 1.1
	agent.path_max_distance = 6.0
	agent.avoidance_enabled = false
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.5
	_facing = model_pivot.rotation.y
	global_position.y = TerrainData.height_at(global_position.x, global_position.z) + 0.05
	# One frame for the NavigationServer to register the region.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_pick_destination()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	match state:
		State.IDLE:
			_brake(delta)
			_wait -= delta
			if _wait <= 0.0:
				_pick_destination()
		State.WALK:
			_follow_path(delta)
		State.ARRIVE:
			_brake(delta)
			if velocity.length() < 0.15:
				state = State.IDLE
				_wait = _rng.randf_range(idle_time.x, idle_time.y)

	move_and_slide()
	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if _rig:
		_rig.set_blend_speed(horizontal_speed)


func _brake(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, accel * 1.6 * delta)
	velocity.x = flat.x
	velocity.z = flat.z


func _follow_path(delta: float) -> void:
	if agent.is_navigation_finished():
		state = State.ARRIVE
		return
	var next := agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.001:
		state = State.ARRIVE
		return
	_steer(delta, to.normalized(), walk_speed)

	# If the agent is wedged against something the navmesh did not know
	# about, give up on this destination rather than grinding into it.
	if Vector2(velocity.x, velocity.z).length() < 0.25:
		_stuck += delta
		if _stuck > 1.6:
			_stuck = 0.0
			_pick_destination()
	else:
		_stuck = 0.0


## Steering, not strafing.
##
## The NPC turns towards where it wants to go and then walks along the way it
## is FACING — it never accelerates sideways or backwards towards a waypoint.
## That is the difference between a character walking and a character sliding
## to its destination, and it is what stops the reversal at the end of each
## leg from reading as a moonwalk (sections 25 and 48).
##
## Speed falls away as the misalignment grows, so a hard about-turn becomes a
## pause-and-pivot instead of a skid.
func _steer(delta: float, want_dir: Vector3, speed: float) -> void:
	# NOTE: the KayKit Adventurers rig faces +Z, not Godot's usual -Z.
	# Measured, not assumed — tools/measure_facing.gd tracks the swing foot
	# across a walk cycle and it travels towards +Z.
	var want_yaw := atan2(want_dir.x, want_dir.z)
	_facing = rotate_toward(_facing, want_yaw, turn_speed * delta)
	model_pivot.rotation.y = _facing
	var forward := Vector3(sin(_facing), 0.0, cos(_facing))
	var align := clampf(forward.dot(want_dir), 0.0, 1.0)
	var target := forward * speed * lerpf(0.12, 1.0, align * align)
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z


func _pick_destination() -> void:
	if _nav == null:
		state = State.IDLE
		_wait = 2.0
		return
	var p := _nav.random_point(_rng, global_position, min_travel, max_travel)
	agent.target_position = p
	state = State.WALK
	_stuck = 0.0


func state_name() -> String:
	match state:
		State.WALK: return "WALK"
		State.ARRIVE: return "ARRIVE"
		_: return "IDLE"
