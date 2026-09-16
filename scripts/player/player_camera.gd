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
@export var height: float = 1.95
## Portrait is tall and narrow, so the camera sits further back than a
## landscape third-person camera would to frame the same amount of world.
## `height` is also above the character's head rather than at its chest, which
## drops the character into the lower third of a tall screen and leaves the
## top two thirds for the thing the player is actually walking towards.
##
## SECTION 6 — the camera has to keep up with 7.5 m/s. Three things change
## with speed, all of them lerped off the player's actual ground speed rather
## than off which button is held:
##
##   distance   6.9 -> 8.3 m   so a sprinting character does not fill the frame
##   fov        70  -> 82 deg  the single cheapest "this is fast" cue there is
##   height     x1  -> x1.08   a slightly higher eye sees further ahead
##
## Held still, the camera sits closer than 0.2 did: at 1.5 m/s the old 7.4 m
## was a satellite view of a man ambling.
@export var distance: float = 6.9
@export var sprint_distance: float = 8.3
@export var fov: float = 70.0
@export var sprint_fov: float = 82.0
## How quickly the speed-driven framing catches up, per second. Deliberately
## much slower than the follow, so stopping does not snap the frame.
@export var zoom_speed: float = 2.6
## 0.2 used 9.0, which visibly lagged at the new speeds.
@export var follow_speed: float = 12.0
@export var min_pitch_deg: float = -38.0
@export var max_pitch_deg: float = 22.0
@export var look_sensitivity: float = 0.006
## The camera drifts back behind the player while they run, so a one-thumb
## player never has to touch the look control at all. Faster than 0.2's 0.9:
## at sprint the old rate took four seconds to come round, by which time the
## player had crossed a third of the map sideways-on.
@export var auto_align: float = 1.7
## Vertical damping. The camera follows a jump, but not one-for-one: taking
## the vertical at about half rate keeps the horizon steady and stops a 1.25 m
## hop from throwing the whole frame.
@export var vertical_follow: float = 0.55

@onready var pitch_node: Node3D = $Pitch
@onready var spring: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D

var _target: PlayerController
var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-13.0)
var _manual_hold: float = 0.0
## 0 = standing, 1 = sprinting. Drives distance, fov and eye height together.
var _rush: float = 0.0


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
	camera.fov = fov
	_apply()


func _process(delta: float) -> void:
	if _target == null:
		return
	# How much of the framing is "rushing". Measured against the sprint speed,
	# so the tiers below it land at sensible fractions rather than saturating.
	var rush_now := clampf(
		(_target.horizontal_speed - _target.walk_speed)
		/ maxf(_target.sprint_speed - _target.walk_speed, 0.01), 0.0, 1.0)
	_rush = lerpf(_rush, rush_now, clampf(zoom_speed * delta, 0.0, 1.0))

	var want := _target.global_position + Vector3.UP * (height * lerpf(1.0, 1.08, _rush))
	# Horizontal follow is tight; vertical is deliberately loose (see
	# vertical_follow) so a jump moves the frame less than it moves the player.
	var k := clampf(follow_speed * delta, 0.0, 1.0)
	var next := global_position.lerp(want, k)
	next.y = lerpf(global_position.y, want.y, clampf(follow_speed * vertical_follow * delta, 0.0, 1.0))
	global_position = next

	spring.spring_length = lerpf(spring.spring_length,
		lerpf(distance, sprint_distance, _rush), clampf(zoom_speed * delta, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, lerpf(fov, sprint_fov, _rush),
		clampf(zoom_speed * delta, 0.0, 1.0))

	_manual_hold = maxf(0.0, _manual_hold - delta)
	if _manual_hold <= 0.0 and auto_align > 0.0 and _target.horizontal_speed > 1.2:
		# Rig yaw whose forward (-Z) points along the player's velocity.
		var want_yaw := atan2(-_target.velocity.x, -_target.velocity.z)
		_yaw = rotate_toward(_yaw, want_yaw, auto_align * delta
			* clampf(_target.horizontal_speed / maxf(_target.sprint_speed, 0.01), 0.0, 1.0))

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
