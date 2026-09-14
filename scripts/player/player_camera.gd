extends Node3D
class_name PlayerCamera
##
## Third-person follow camera, built for a thumb rather than a mouse.
##
## It is `top_level`, so it does not inherit the player's transform and does
## not inherit the player's jitter either: it lerps towards the player every
## frame, which is what keeps a 60 Hz physics body looking smooth on a 60 Hz
## screen.
##
## The SpringArm3D does the work of not putting a tree trunk between the
## camera and the character.

@export var target_path: NodePath
@export var height: float = 2.0
## Portrait is tall and narrow, so the camera sits further back than a
## landscape third-person camera would to frame the same amount of world.
## `height` is also above the character's head rather than at its chest, which
## drops the character into the lower third of a tall screen and leaves the
## top two thirds for the thing the player is actually walking towards.
@export var distance: float = 7.4
@export var follow_speed: float = 9.0
@export var min_pitch_deg: float = -38.0
@export var max_pitch_deg: float = 22.0
@export var look_sensitivity: float = 0.006
## The camera drifts back behind the player while they run, so a one-thumb
## player never has to touch the look control at all.
@export var auto_align: float = 0.9

@onready var pitch_node: Node3D = $Pitch
@onready var spring: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D

var _target: PlayerController
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-13.0)
var _manual_hold: float = 0.0


func _ready() -> void:
	top_level = true
	_target = get_node_or_null(target_path) as PlayerController
	if _target:
		global_position = _target.global_position + Vector3.UP * height
		_yaw = _target.rotation.y
	spring.spring_length = distance
	# The spring arm dodges level geometry only — never characters, water,
	# pickups or interaction volumes.
	spring.collision_mask = Layers.WORLD_STATIC
	spring.margin = 0.25
	_apply()


func _process(delta: float) -> void:
	if _target == null:
		return
	var want := _target.global_position + Vector3.UP * height
	global_position = global_position.lerp(want, clampf(follow_speed * delta, 0.0, 1.0))

	_manual_hold = maxf(0.0, _manual_hold - delta)
	if _manual_hold <= 0.0 and auto_align > 0.0 and _target.horizontal_speed > 1.2:
		# Rig yaw whose forward (-Z) points along the player's velocity.
		var want_yaw := atan2(-_target.velocity.x, -_target.velocity.z)
		_yaw = rotate_toward(_yaw, want_yaw, auto_align * delta
			* clampf(_target.horizontal_speed / maxf(_target.run_speed, 0.01), 0.0, 1.0))

	_apply()
	_target.camera_yaw = _yaw


func _apply() -> void:
	rotation.y = _yaw
	pitch_node.rotation.x = _pitch


## Called by the touch look-zone (and by the mouse on desktop).
func look(delta_px: Vector2) -> void:
	_yaw -= delta_px.x * look_sensitivity
	_pitch = clampf(_pitch - delta_px.y * look_sensitivity,
		deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	_manual_hold = 1.6
	_apply()


func yaw() -> float:
	return _yaw


## The horizontal direction the camera is looking. The player's "forward"
## must agree with this.
func forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


## Point the camera so that it looks along `dir`.
func face(dir: Vector3) -> void:
	_yaw = atan2(-dir.x, -dir.z)
	_apply()
