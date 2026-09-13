extends CharacterBody3D
class_name PlayerController
##
## The player: a CharacterBody3D moved with move_and_slide(), never by writing
## to `position` (section 8).
##
## Three locomotion states, all driven by the same physics body:
##
##   LAND   normal walking and running, slope-aware
##   WATER  wading — still on the floor, but slowed in proportion to depth
##   SWIM   floating — gravity replaced by buoyancy, different top speed,
##          provisional prone animation
##
## The state comes from TerrainData.water_depth_at(), which is the same
## function the water mesh was built from; the WaterBody Area3D is the
## physical gate that confirms it. They cannot disagree.

signal state_changed(state: int)

enum State { LAND, WATER, SWIM }

@export_group("Speed")
## Both speeds are chosen to sit inside the playback-rate band of the clip
## that covers them (see LocomotionRig): 1.5 m/s plays Walking_A at 1.95x,
## 4.8 m/s plays Running_A at 1.34x. Raising walk_speed much past 1.6 would
## push the walk clip past its rate limit and reintroduce foot sliding.
@export var walk_speed: float = 1.5
@export var run_speed: float = 4.8
@export var swim_speed: float = 1.55
@export var swim_fast_speed: float = 2.25

@export_group("Feel")
@export var ground_accel: float = 16.0
@export var ground_decel: float = 20.0
@export var air_accel: float = 3.5
@export var water_accel: float = 7.0
@export var turn_speed: float = 11.0
@export var slope_penalty: float = 0.62

@export_group("Water")
## Water this deep or deeper makes the player swim.
@export var swim_enter_depth: float = 1.35
## Hysteresis, so standing on the swim boundary does not flicker.
@export var swim_exit_margin: float = 0.28
## How far the body origin (the feet) floats below the surface when swimming.
@export var float_depth: float = 0.88
@export var buoyancy: float = 6.0
## Rotation about X that lays the model out prone. POSITIVE tips the model's
## up-axis towards its facing (+Z), which is a front crawl: body along the
## direction of travel, head leading and clear of the water. Negative values
## recline it instead, which put the character's face under the surface.
## SWIM ANIMATION PROVISIONAL.
@export var swim_pitch_deg: float = 66.0
## How far the model is lifted while prone, so the body lies ON the surface
## rather than under it.
@export var swim_lift: float = 0.86

@onready var model_pivot: Node3D = $ModelPivot
@onready var interactor: Node = $Interactor

var state: int = State.LAND
var move_input: Vector2 = Vector2.ZERO   ## written by the touch UI, x = right, y = forward
var run_held: bool = false
var camera_yaw: float = 0.0              ## written by PlayerCamera each frame

var water_depth: float = 0.0
var in_water_volume: bool = false
var horizontal_speed: float = 0.0

var _rig: LocomotionRig
var _facing: float = 0.0
var _model_base_y: float = 0.0
var _pitch: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)
var _bob: float = 0.0


func _ready() -> void:
	_model_base_y = model_pivot.position.y
	var model: Node3D = model_pivot.get_child(0)
	LocomotionRig.hide_weapons(model)
	_rig = LocomotionRig.new()
	_rig.setup(model)
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	slide_on_ceiling = true
	up_direction = Vector3.UP
	_facing = model_pivot.rotation.y
	# Start standing on the ground rather than falling into it.
	global_position.y = TerrainData.height_at(global_position.x, global_position.z) + 0.05


func _physics_process(delta: float) -> void:
	_update_water(delta)

	var wish := _wish_direction()
	var target := _target_speed(wish)

	if state == State.SWIM:
		_swim(delta, wish, target)
	else:
		_walk(delta, wish, target)

	move_and_slide()

	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	_update_facing(delta, wish)
	_update_model(delta)
	_update_animation()


## Joystick input, rotated into the camera's frame. This is what makes "up on
## the stick" mean "away from the camera" no matter which way it is pointing
## (section 11).
func _wish_direction() -> Vector3:
	var raw := move_input
	if raw.length() > 1.0:
		raw = raw.normalized()
	if raw.length() < 0.06:
		return Vector3.ZERO
	# The camera rig sits BEHIND the player along its local +Z and looks down
	# its own -Z, so the direction "away from the camera" is -Z of the rig.
	# Getting this sign wrong makes pushing the stick up run the character
	# straight at the camera, which is the "unintended reverse walk" the
	# brief calls out (section 10). Verified against the live camera by
	# tools/benchmark_tests.gd, not by inspection.
	var forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
	return (right * raw.x + forward * raw.y).limit_length(1.0)


func _target_speed(wish: Vector3) -> float:
	var mag := wish.length()
	if mag < 0.06:
		return 0.0
	var base: float
	if state == State.SWIM:
		base = swim_fast_speed if run_held else swim_speed
	else:
		base = run_speed if run_held else walk_speed
		# Wading: the deeper you are, the more the water holds you back.
		if state == State.WATER:
			var t := clampf(water_depth / swim_enter_depth, 0.0, 1.0)
			# Ankle-deep already drags noticeably; chest-deep is a crawl.
			# Section 19: walking through water must not feel like walking.
			base *= lerpf(0.82, 0.30, t)
		# Slope: uphill costs speed, downhill gives a little back.
		if is_on_floor():
			var n := get_floor_normal()
			var horiz := Vector3(n.x, 0.0, n.z)
			if horiz.length() > 0.001:
				var grade := -wish.normalized().dot(horiz.normalized()) * (horiz.length() / maxf(n.y, 0.001))
				base *= clampf(1.0 - grade * slope_penalty, 0.42, 1.18)
	# An analogue stick held half way should walk, not run.
	return base * mag


func _walk(delta: float, wish: Vector3, target: float) -> void:
	var want := wish.normalized() * target if target > 0.0 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if not is_on_floor():
		rate = air_accel
	elif state == State.WATER:
		rate = water_accel
	elif target > 0.0:
		rate = ground_accel
	else:
		rate = ground_decel
	flat = flat.move_toward(want, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	floor_snap_length = 0.45


func _swim(delta: float, wish: Vector3, target: float) -> void:
	var want := wish.normalized() * target if target > 0.0 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(want, water_accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	# Buoyancy instead of gravity: a critically damped pull towards the
	# floating waterline, so the body settles instead of bobbing forever.
	var target_y := TerrainData.WATER_LEVEL - float_depth
	var err := target_y - global_position.y
	velocity.y = move_toward(velocity.y, err * buoyancy, 22.0 * delta)
	velocity.y = clampf(velocity.y, -4.0, 4.0)
	# Snapping to the floor while swimming would drag the player under.
	floor_snap_length = 0.0


func _update_water(delta: float) -> void:
	water_depth = TerrainData.water_depth_at(global_position.x, global_position.z)
	var feet_under := TerrainData.WATER_LEVEL - global_position.y
	var was := state
	if state == State.SWIM:
		if water_depth < swim_enter_depth - swim_exit_margin:
			state = State.WATER if water_depth > 0.05 else State.LAND
	else:
		if water_depth >= swim_enter_depth:
			state = State.SWIM
		elif water_depth > 0.05 and feet_under > -0.02:
			state = State.WATER
		else:
			state = State.LAND
	if was != state:
		state_changed.emit(state)
	_bob += delta


## The character always faces where it is actually going. It never turns to
## face the camera, and it never plays a forward cycle while travelling
## backwards (section 10).
func _update_facing(delta: float, wish: Vector3) -> void:
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() < 0.25:
		dir = wish
	if dir.length() < 0.05:
		return
	# NOTE: the KayKit Adventurers rig faces +Z, not Godot's usual -Z.
	# Measured, not assumed — tools/measure_facing.gd tracks the swing foot
	# across a walk cycle and it travels towards +Z. So atan2(x, z) with no
	# PI correction is the right angle here; adding one would give the
	# "character moonwalks" bug the brief calls out (section 10).
	var want := atan2(dir.x, dir.z)
	_facing = rotate_toward(_facing, want, turn_speed * delta)
	model_pivot.rotation.y = _facing


func _update_model(delta: float) -> void:
	var want_pitch := 0.0
	var want_y := _model_base_y
	if state == State.SWIM:
		# SWIM ANIMATION PROVISIONAL: no swim clip exists in the KayKit
		# Adventurers pack, so the model is pitched into a prone attitude and
		# sunk to the waterline while the walk cycle plays slowly as a paddle.
		want_pitch = deg_to_rad(swim_pitch_deg)
		want_y = _model_base_y + swim_lift + sin(_bob * 2.1) * 0.05
	elif state == State.WATER:
		want_y = _model_base_y - minf(water_depth, 0.35) * 0.12
	_pitch = lerpf(_pitch, want_pitch, minf(1.0, delta * 7.0))
	model_pivot.rotation.x = _pitch
	model_pivot.position.y = lerpf(model_pivot.position.y, want_y, minf(1.0, delta * 8.0))

	# Plant the feet: lean the model with the ground so it does not stand
	# plumb on a hillside (section 17).
	if state != State.SWIM and is_on_floor():
		var n := get_floor_normal()
		var lean := Vector3.UP.lerp(n, 0.35).normalized()
		var axis := Vector3.UP.cross(lean)
		var want_roll := 0.0
		var want_tip := 0.0
		if axis.length() > 0.0001:
			var local := model_pivot.global_transform.basis.inverse() * (lean - Vector3.UP)
			want_tip = clampf(-local.z * 0.55, -0.22, 0.22)
			want_roll = clampf(local.x * 0.55, -0.22, 0.22)
		model_pivot.rotation.x = lerpf(model_pivot.rotation.x, want_tip + _pitch, minf(1.0, delta * 6.0))
		model_pivot.rotation.z = lerpf(model_pivot.rotation.z, want_roll, minf(1.0, delta * 6.0))
	else:
		model_pivot.rotation.z = lerpf(model_pivot.rotation.z, 0.0, minf(1.0, delta * 6.0))


func _update_animation() -> void:
	if _rig == null or _rig.tree == null:
		return
	if state == State.SWIM:
		_rig.set_mode_ground(false)
		_rig.set_swim_effort(clampf(horizontal_speed / maxf(swim_fast_speed, 0.01), 0.0, 1.0))
	else:
		_rig.set_mode_ground(true)
		_rig.set_blend_speed(horizontal_speed)


## Called by the interactor when a resource is actually taken. Deliberately
## an upper-body-only gesture: the legs keep whatever they were doing, so a
## pickup at a dead run neither stops the player nor turns them.
func play_pickup_gesture() -> void:
	if _rig:
		_rig.play_pickup()


func state_name() -> String:
	match state:
		State.SWIM: return "SWIM"
		State.WATER: return "WATER"
		_: return "LAND"


## Surface the feet are on. Extended later into footstep sounds (section 17).
func surface_name() -> String:
	if state == State.SWIM:
		return "water/deep"
	if state == State.WATER:
		return "water/shallow"
	if TerrainData.path_influence(global_position.x, global_position.z) > 0.45:
		return "path"
	return "ground"


func _on_water_volume_entered(_b: Node3D) -> void:
	in_water_volume = true


func _on_water_volume_exited(_b: Node3D) -> void:
	in_water_volume = false
