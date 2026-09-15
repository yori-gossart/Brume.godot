extends CharacterBody3D
class_name PlayerController
##
## The player: a CharacterBody3D moved with move_and_slide(), never by writing
## to `position` (section 8 of the 0.1 brief; still true in 0.2.1 — the
## step-up in _try_step() moves through move_and_collide(), which is the
## physics engine, not a teleport).
##
## THREE LOCOMOTION MEDIA, all driven by the same physics body:
##
##   State.LAND   normal ground movement, slope-aware
##   State.WATER  wading — still on the floor, but slowed in proportion to depth
##   State.SWIM   floating — gravity replaced by buoyancy, provisional animation
##
## AND, ORTHOGONAL TO THAT, FOUR AIR STATES (section 12):
##
##   Air.GROUNDED  feet on something
##   Air.JUMP      rising, under rise gravity
##   Air.FALL      descending, under the heavier fall gravity
##   Air.LAND      the brief recovery window after touching down
##
## Note the collision of vocabulary: State.LAND means "on land rather than in
## water", Air.LAND means "has just landed". They are different enums and the
## brief names both, so both names are kept.
##
## WHAT CHANGED IN 0.2.1
##
## 0.2 walked at 1.5 m/s and ran at 4.8, with no jump at all. The verdict was
## that the player crawls. Every speed, acceleration and rotation number now
## lives in PlayerMovementConfig and nowhere else (section 36); the tiers are
## 3.4 / 5.5 / 7.5; there is a real jump with coyote time, an input buffer and
## variable height; and obstacles up to 30 cm are walked over instead of
## stopping the player dead.

signal state_changed(state: int)
## Emitted when the ground underfoot changes kind. Footstep audio, VFX and
## track-leaving all hang off this later (section 34); the debug HUD is the
## consumer today and the test suite is the judge.
signal surface_changed(surface: int)
## Emitted when the air state changes (section 12).
signal air_state_changed(air: int)
## Emitted the frame a jump leaves the ground.
signal jumped()
## Emitted on touchdown, with how far the player fell (section 12). Nothing
## consumes the distance yet; it is the datum a landing roll, a stagger or
## fall damage would be built from.
signal landed(fall_distance: float)

enum State { LAND, WATER, SWIM }
enum Air { GROUNDED, JUMP, FALL, LAND }
## Section 3: the analogue tiers. Reported, not commanded — the tier is read
## off the speed the stick is actually asking for, so there is no knife edge
## between two of them.
enum Tier { WALK, RUN, SPRINT }

## Every number that decides how moving feels (section 36). Never duplicate
## one of these into another script; read it from here. The initialiser runs
## per instance, so a Player dropped into a scene without a .tres still has a
## complete, valid config rather than a null.
@export var movement: PlayerMovementConfig = PlayerMovementConfig.new()

## The prone attitude used while swimming. Presentation only, so it stays here
## rather than in the movement config — it changes nothing physical. POSITIVE
## tips the model's up-axis towards its facing (+Z), which is a front crawl:
## body along the direction of travel, head leading and clear of the water.
@export var swim_pitch_deg: float = 66.0
## How far the model is lifted while prone, so the body lies ON the surface
## rather than under it.
@export var swim_lift: float = 0.86

## Who the player looks like. Left null, a default scout is built —
## ocre, not green (section 7 of the 0.2 brief).
@export var appearance: CharacterAppearance

@onready var model_pivot: Node3D = $ModelPivot
@onready var interactor: Node = $Interactor

var state: int = State.LAND
var air: int = Air.GROUNDED
var move_input: Vector2 = Vector2.ZERO   ## written by the touch UI, x = right, y = forward
var run_held: bool = false
## Held state of the JUMP button. Releasing it on the way up cuts the jump
## short (section 10), so this has to be a held flag, not an edge.
var jump_held: bool = false
var camera_yaw: float = 0.0              ## written by PlayerCamera each frame

var water_depth: float = 0.0
var in_water_volume: bool = false
var horizontal_speed: float = 0.0
## What the stick is asking for right now, before acceleration. The debug HUD
## shows this next to the actual speed so a mismatch is visible (section 35).
var target_speed: float = 0.0
var speed_tier: int = Tier.WALK
## Angle of the ground underfoot, in degrees. 0 on the flat.
var slope_angle: float = 0.0
## How far the player has descended since the last time they were grounded.
var fall_distance: float = 0.0
## The value `fall_distance` had at the last touchdown.
var last_fall_distance: float = 0.0
## Counters the tests and the HUD read. Not gameplay.
var steps_climbed: int = 0
var jumps_made: int = 0

## SurfaceType.Kind of the ground underfoot, read from the collider the
## player is actually standing on (section 33 of the 0.2 brief).
var current_surface: int = SurfaceType.Kind.UNKNOWN
## The node that surface came from, for debugging a wrong answer.
var surface_source: Node = null

var _rig: LocomotionRig
var _facing: float = 0.0
var _model_base_y: float = 0.0
var _pitch: float = 0.0
var _bob: float = 0.0

var _grounded: bool = true               ## is_on_floor() as of the last move
var _coyote: float = 0.0                 ## time left in which a jump still works
var _buffer: float = 0.0                 ## time left on a buffered jump press
var _land_timer: float = 0.0
var _jump_active: bool = false           ## a jump is rising and may still be cut
var _apex_y: float = 0.0                 ## highest point reached since leaving the ground


func _ready() -> void:
	if movement == null:
		movement = PlayerMovementConfig.new()
	_model_base_y = model_pivot.position.y
	if appearance == null:
		appearance = CharacterAppearance.make_default()
	var model := CharacterBuilder.build(model_pivot, appearance)
	if model == null:
		model = model_pivot.get_child(0)
	_rig = LocomotionRig.new()
	_rig.setup(model)
	SoftBodyAvoidance.register(self)
	floor_max_angle = deg_to_rad(movement.max_slope_deg)
	floor_snap_length = movement.floor_snap_length
	floor_stop_on_slope = true
	slide_on_ceiling = true
	up_direction = Vector3.UP
	_facing = model_pivot.rotation.y
	# Start standing on the ground rather than falling into it.
	global_position.y = TerrainData.height_at(global_position.x, global_position.z) + 0.05
	_apex_y = global_position.y


func _physics_process(delta: float) -> void:
	# is_on_floor() describes the result of the PREVIOUS move_and_slide, which
	# is exactly the ground contact this frame's decisions should be based on.
	_grounded = is_on_floor()
	_tick_air(delta)
	_update_water(delta)

	var wish := _wish_direction()
	var target := _target_speed(wish)

	if state == State.SWIM:
		_swim(delta, wish, target)
	else:
		_walk(delta, wish, target)

	# Deflect around other characters without ever slowing down (section 60 of
	# the 0.2 brief).
	var push := SoftBodyAvoidance.push_for(self, Vector3(velocity.x, 0.0, velocity.z))
	velocity.x += push.x
	velocity.z += push.z

	var before := global_position
	# The speed we ASKED for, kept before move_and_slide gets to zero it
	# against a wall. _try_step needs the intent, not the outcome: reading
	# velocity after the slide says "you are going nowhere", which is the
	# answer, not the question.
	var intent := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_try_step(wish, delta, before, intent)
	_settle_ground()

	_resolve_surface()
	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	_update_facing(delta, wish)
	_update_model(delta)
	_update_animation()


# ------------------------------------------------------------- input ------
## Joystick input, rotated into the camera's frame. This is what makes "up on
## the stick" mean "away from the camera" no matter which way it is pointing
## (section 11 of the 0.1 brief).
func _wish_direction() -> Vector3:
	var raw := move_input
	if raw.length() > 1.0:
		raw = raw.normalized()
	if raw.length() < 0.06:
		return Vector3.ZERO
	# The camera rig sits BEHIND the player along its local +Z and looks down
	# its own -Z, so the direction "away from the camera" is -Z of the rig.
	# Getting this sign wrong makes pushing the stick up run the character
	# straight at the camera. Verified against the live camera by
	# tools/benchmark_tests.gd, not by inspection.
	var forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
	return (right * raw.x + forward * raw.y).limit_length(1.0)


## THE SPEED THE STICK IS ASKING FOR (sections 2, 3, 15, 19).
##
## The stick is analogue all the way through: its magnitude is the fraction of
## the current CEILING being asked for, so a half-pushed stick genuinely walks
## and a stick at the rim genuinely sprints. The RUN button does not set a
## speed, it raises the ceiling — and with RUN held the ceiling itself rises
## from RUN to SPRINT as the thumb reaches the rim.
##
## The consequence worth stating: there is no threshold at which the speed
## jumps. Push harder, go faster, continuously. The named tiers exist for the
## HUD and the tests; they are read back OFF the resulting speed rather than
## being the thing that produced it.
func _target_speed(wish: Vector3) -> float:
	var mag := wish.length()
	if mag < 0.06:
		target_speed = 0.0
		speed_tier = Tier.WALK
		return 0.0

	var base: float
	if state == State.SWIM:
		base = movement.swim_fast_speed if run_held else movement.swim_speed
	else:
		base = _ground_ceiling(mag)
		# Wading: the deeper you are, the more the water holds you back.
		# Section 19 — walking through water must not feel like walking.
		if state == State.WATER:
			var t := clampf(water_depth / movement.swim_enter_depth, 0.0, 1.0)
			base *= lerpf(movement.wade_drag_shallow, movement.wade_drag_deep, t)
		# Slope: uphill costs speed, downhill gives a little back.
		if _grounded:
			var n := get_floor_normal()
			var horiz := Vector3(n.x, 0.0, n.z)
			if horiz.length() > 0.001:
				var grade := -wish.normalized().dot(horiz.normalized()) \
					* (horiz.length() / maxf(n.y, 0.001))
				# The downhill bonus is capped at 1.10 rather than 0.2's 1.18 for
				# a concrete reason: sprint x 1.18 is 8.85 m/s, which is past
				# the 8.28 m/s ceiling of the run clip's honest playback band,
				# so a downhill sprint would clamp the rate and slide. 1.10
				# puts the worst case at 8.25 m/s, inside the band.
				base *= clampf(1.0 - grade * movement.slope_penalty, 0.48, 1.10)

	target_speed = base * mag
	speed_tier = _tier_of(target_speed)
	return target_speed


## The ceiling the stick is scaled against, on land.
func _ground_ceiling(mag: float) -> float:
	if not run_held:
		return movement.walk_speed
	# With RUN held, the last fifth of stick travel is the sprint. smoothstep
	# rather than a linear ramp so the transition has no corner in it.
	var t := smoothstep(movement.sprint_stick_threshold - 0.22,
		minf(movement.sprint_stick_threshold + 0.06, 1.0), mag)
	var ceiling := lerpf(movement.run_speed, movement.sprint_speed, t)
	# No sprinting through a river.
	if state == State.WATER:
		ceiling = minf(ceiling, movement.run_speed)
	return ceiling


## Which named tier a speed belongs to. Boundaries sit halfway between the
## tier speeds, so the label matches what the player would call it.
func _tier_of(speed: float) -> int:
	if speed > (movement.run_speed + movement.sprint_speed) * 0.5:
		return Tier.SPRINT
	if speed > (movement.walk_speed + movement.run_speed) * 0.5:
		return Tier.RUN
	return Tier.WALK


func tier_name() -> String:
	match speed_tier:
		Tier.SPRINT: return "SPRINT"
		Tier.RUN: return "RUN"
		_: return "WALK"


# -------------------------------------------------------------- jump ------
## Called by the touch JUMP button and by the desktop key. Always buffers:
## whether the jump fires now or in 0.12 s is decided in _tick_air (section 13).
func press_jump() -> void:
	jump_held = true
	_buffer = movement.jump_buffer_time


func release_jump() -> void:
	jump_held = false


## Can a jump start at all right now? Swimming cannot be jumped out of;
## standing in shallow water can (section 30).
func can_jump() -> bool:
	if state == State.SWIM:
		return false
	if state == State.WATER and water_depth > movement.max_jump_depth:
		return false
	return _grounded or _coyote > 0.0


## Coyote time, jump buffering, the air state machine and the fall counter —
## everything that is a function of ground contact rather than of input.
func _tick_air(delta: float) -> void:
	if _grounded:
		_coyote = movement.coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_buffer = maxf(0.0, _buffer - delta)
	_land_timer = maxf(0.0, _land_timer - delta)

	# Touchdown. Detected here rather than in _walk so it is true for every
	# way of arriving on the ground, including being pushed onto it.
	if _grounded and (air == Air.JUMP or air == Air.FALL):
		last_fall_distance = maxf(0.0, _apex_y - global_position.y)
		fall_distance = 0.0
		_jump_active = false
		_land_timer = movement.land_recovery_time
		_set_air(Air.LAND)
		landed.emit(last_fall_distance)

	if _grounded:
		_apex_y = global_position.y
		fall_distance = 0.0
		if air == Air.LAND and _land_timer <= 0.0:
			_set_air(Air.GROUNDED)
	else:
		_apex_y = maxf(_apex_y, global_position.y)
		fall_distance = maxf(0.0, _apex_y - global_position.y)

	# A buffered press fires the moment it legally can.
	if _buffer > 0.0 and can_jump():
		_start_jump()


func _start_jump() -> void:
	velocity.y = movement.jump_velocity()
	_coyote = 0.0
	_buffer = 0.0
	_jump_active = true
	_apex_y = global_position.y
	fall_distance = 0.0
	jumps_made += 1
	_set_air(Air.JUMP)
	jumped.emit()


func _set_air(a: int) -> void:
	if air == a:
		return
	air = a
	air_state_changed.emit(a)


## Which locomotion clip the rig is actually playing — "idle", "walk" or
## "run". Reported by the rig rather than inferred from the speed, so a test
## can judge foot slide against the floor of the clip that is really running.
func gait_name() -> String:
	return _rig.gait_name() if _rig else "?"


func air_name() -> String:
	match air:
		Air.JUMP: return "JUMP"
		Air.FALL: return "FALL"
		Air.LAND: return "LAND"
		_: return "GROUNDED"


# ---------------------------------------------------------- locomotion ----
func _walk(delta: float, wish: Vector3, target: float) -> void:
	var want := wish.normalized() * target if target > 0.0 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if not _grounded:
		rate = movement.air_accel
	elif state == State.WATER:
		rate = movement.water_accel
	elif target > 0.0:
		rate = movement.ground_accel
	else:
		rate = movement.ground_decel
	flat = flat.move_toward(want, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	if _grounded and not _jump_active:
		velocity.y = 0.0
		# Snapping keeps the body glued over crests and down steps.
		floor_snap_length = movement.floor_snap_length
	else:
		# Section 10: letting go on the way up cuts the jump short. Applied
		# once, the frame the button comes up, so holding it again does not
		# re-inflate the jump.
		if _jump_active and not jump_held and velocity.y > 0.0:
			velocity.y *= movement.jump_release_multiplier
			_jump_active = false
		# Rising is lighter than falling. Same height, less float.
		var g := movement.rise_gravity() if velocity.y > 0.0 else movement.fall_gravity()
		velocity.y = maxf(velocity.y - g * delta, -movement.max_fall_speed)
		# Snapping while moving away from the floor would cancel the jump.
		floor_snap_length = 0.0
		if velocity.y <= 0.0 and air != Air.FALL and air != Air.LAND:
			_set_air(Air.FALL)


func _swim(delta: float, wish: Vector3, target: float) -> void:
	var want := wish.normalized() * target if target > 0.0 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(want, movement.water_accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	# Buoyancy instead of gravity: a critically damped pull towards the
	# floating waterline, so the body settles instead of bobbing forever.
	var target_y := TerrainData.WATER_LEVEL - movement.float_depth
	var err := target_y - global_position.y
	velocity.y = move_toward(velocity.y, err * movement.buoyancy, 22.0 * delta)
	velocity.y = clampf(velocity.y, -4.0, 4.0)
	# Snapping to the floor while swimming would drag the player under.
	floor_snap_length = 0.0
	_jump_active = false


# --------------------------------------------------------- step over ------
## WALKING OVER SMALL THINGS (section 14).
##
## Godot's CharacterBody3D has no step-up: a 12 cm kerb stops a character
## dead, which is the single most common source of "the world feels like it
## is made of glue". Section 18 puts it as a rule — the player must be
## blocked only where they can SEE an obstacle — and a doorstep is not one.
##
## The classic three-probe move, done entirely through the physics engine so
## nothing is ever teleported into geometry:
##
##     1. is there headroom to rise by step_height?
##     2. from up there, is the way forward clear?
##     3. is there ground to come back down onto within step_height?
##
## All three are test_move() first. Only if all three answer yes is the move
## committed, with three move_and_collide() calls. If any answers no, the
## obstacle is a real wall and the player stays stopped by it — which is the
## other half of section 18.
##
## FUTURE VAULT (section 17): a vault is this same probe with a taller rise,
## a longer reach and an animation gate, which is why the probe is factored
## out into _probe_traverse(). 0.2.1 deliberately does not implement one —
## section 17 asks for the structure, not the feature.
##
## The probe is deliberately CONSERVATIVE about what counts as a step: see
## STEP_CLEARANCE. A step-up that gets you 30 cm up the side of something is
## not a step, it is the first move of a climb.
func _try_step(wish: Vector3, delta: float, before: Vector3, intent: Vector3) -> void:
	if movement.step_height <= 0.0 or state == State.SWIM:
		return
	if not is_on_floor() or _jump_active:
		return
	var want := intent
	if want.length() < 0.2 or wish.length() < 0.06:
		return
	# Did we actually get stopped by a WALL? is_on_wall() is the engine's own
	# answer to "the last move hit something steeper than floor_max_angle",
	# which is exactly the question — and, unlike a distance comparison on its
	# own, it cannot be fooled by a slope. Sliding up a 30 degree hill costs
	# a quarter of the horizontal distance asked for, so a bare
	# moved-versus-asked test fires every frame on a hillside and turns the
	# step probe into a ratchet up the mountain.
	if not is_on_wall():
		return
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var asked := want.length() * delta
	if asked <= 0.0001 or moved >= asked * 0.9:
		return
	var reach := maxf(asked, 0.05) + 0.07
	if _probe_traverse(want.normalized(), movement.step_height, reach, STEP_CLEARANCE):
		steps_climbed += 1
		# Give the speed back. move_and_slide killed it against the kerb, and
		# a step that costs the player all their momentum is barely better
		# than the kerb stopping them: they arrive at the top standing still
		# and have to accelerate again. Section 18's "blocked only where you
		# see an obstacle" means the 20 cm one should not even register.
		velocity.x = intent.x
		velocity.z = intent.z


## How much clear passage there must be at the raised height before a step is
## allowed. The step itself only commits a few centimetres, but probing only
## that far turns the sonde into a climbing aid: on a two-metre boulder every
## 30 cm lift finds another patch of rock shallow enough to stand on, so a
## player who walks into it is ratcheted up onto the top without pressing
## anything. Requiring half a metre of clear space beyond the lip separates
## "a kerb with open ground after it" from "the first 30 cm of a big rock".
const STEP_CLEARANCE := 0.5

## Rise, cross, settle. Returns true if the body was actually moved.
## `clearance` is how far ahead must be free at the raised height; `reach` is
## how far the body actually commits.
func _probe_traverse(dir: Vector3, rise: float, reach: float,
		clearance: float) -> bool:
	# Lift a few centimetres PAST the step height, not exactly to it. A kerb
	# that is precisely step_height tall leaves the raised capsule coplanar
	# with its top, and a forward probe along that plane reports a collision
	# against the very surface it is meant to land on. The practical ceiling
	# is therefore about 0.34 m at the default 0.30 — still inside the
	# brief's 0.20 .. 0.35 band.
	var lift := rise + 0.045
	var here := global_transform
	if test_move(here, Vector3.UP * lift):
		return false                                  # no headroom
	var raised := here
	raised.origin += Vector3.UP * lift
	if test_move(raised, dir * maxf(reach, clearance)):
		return false                                  # still a wall up there
	var across := raised
	across.origin += dir * reach
	var drop := lift + 0.04
	var touch := KinematicCollision3D.new()
	if not test_move(across, Vector3.DOWN * drop, touch):
		return false                                  # nothing to land on
	# AND THE LANDING HAS TO BE WALKABLE. Without this the probe turns every
	# cliff into a staircase: on a 60 degree face the way forward at +30 cm is
	# always clear, so the body would ratchet up it a step per frame and
	# section 16's slope limit would mean nothing. Measured against the same
	# angle move_and_slide uses to decide what counts as a floor.
	if touch.get_normal().y < cos(deg_to_rad(movement.max_slope_deg)):
		return false
	move_and_collide(Vector3.UP * lift)
	move_and_collide(dir * reach)
	move_and_collide(Vector3.DOWN * drop)
	return true


## After the step-up the body may be hanging a couple of centimetres proud of
## the floor, which reads as a one-frame hop. A snap puts it back down without
## touching velocity.
func _settle_ground() -> void:
	if state != State.SWIM and not _jump_active and velocity.y <= 0.0:
		apply_floor_snap()
	if is_on_floor():
		var n := get_floor_normal()
		slope_angle = rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))
	else:
		slope_angle = 0.0


# -------------------------------------------------------------- water -----
func _update_water(delta: float) -> void:
	water_depth = TerrainData.water_depth_at(global_position.x, global_position.z)
	# How far the feet are below the surface. Negative means above it.
	var feet_under := TerrainData.WATER_LEVEL - global_position.y
	# Being ABOVE the waterline means not being in the water, however deep
	# the river is underneath. 0.1 got away with keying the state off depth
	# alone because there was nothing to stand on over water; the bridge
	# broke that immediately — crossing it reported SWIM. Jumping off the
	# bridge breaks it a second way, and the same check covers both.
	var submerged := feet_under > -0.02
	var was := state
	if state == State.SWIM:
		if not submerged or water_depth < movement.swim_enter_depth - movement.swim_exit_margin:
			state = State.WATER if (submerged and water_depth > 0.05) else State.LAND
	else:
		if submerged and water_depth >= movement.swim_enter_depth:
			state = State.SWIM
		elif submerged and water_depth > 0.05:
			state = State.WATER
		else:
			state = State.LAND
	if was != state:
		# Entering the water ends whatever the body was doing in the air
		# (section 30): you land in the river, you do not keep falling in it.
		if state == State.SWIM:
			_jump_active = false
			_set_air(Air.GROUNDED)
		state_changed.emit(state)
	_bob += delta


# --------------------------------------------------------- presentation ---
## The character always faces where it is actually going. It never turns to
## face the camera, and it never plays a forward cycle while travelling
## backwards (section 10 of the 0.1 brief).
##
## Section 5: the rate is interpolated with speed. A standing turn is nearly
## instant; a sprint turn has an arc, because a body doing 7.5 m/s that can
## reverse in one frame reads as weightless.
func _update_facing(delta: float, wish: Vector3) -> void:
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() < 0.25:
		dir = wish
	if dir.length() < 0.05:
		return
	# NOTE: the KayKit Adventurers rig faces +Z, not Godot's usual -Z.
	# Measured, not assumed — tools/measure_facing.gd tracks the swing foot
	# across a walk cycle and it travels towards +Z. So atan2(x, z) with no
	# PI correction is the right angle here.
	var want := atan2(dir.x, dir.z)
	_facing = rotate_toward(_facing, want, movement.turn_speed_at(horizontal_speed) * delta)
	model_pivot.rotation.y = _facing


func _update_model(delta: float) -> void:
	var want_pitch := 0.0
	var want_y := _model_base_y
	if state == State.SWIM:
		# SWIM ANIMATION PROVISIONAL: no swim clip exists in the KayKit
		# Adventurers pack, so the model is pitched into a prone attitude and
		# sunk to the waterline while the walk cycle plays as a paddle.
		want_pitch = deg_to_rad(swim_pitch_deg)
		want_y = _model_base_y + swim_lift + sin(_bob * 2.1) * 0.05
	elif state == State.WATER:
		want_y = _model_base_y - minf(water_depth, 0.35) * 0.12
	_pitch = lerpf(_pitch, want_pitch, minf(1.0, delta * 7.0))
	model_pivot.rotation.x = _pitch
	model_pivot.position.y = lerpf(model_pivot.position.y, want_y, minf(1.0, delta * 8.0))

	# Plant the feet: lean the model with the ground so it does not stand
	# plumb on a hillside (section 17 of the 0.2 brief). Airborne, there is no
	# ground to lean against, so the lean unwinds.
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
		_rig.set_swim_effort(clampf(horizontal_speed / maxf(movement.swim_fast_speed, 0.01), 0.0, 1.0))
	else:
		# Section 34: the animation follows the character, never the other way
		# round. The rig is told the speed the body is ACTUALLY going and
		# picks and rate-scales a clip to match it; nothing here slows the
		# player down to suit a clip.
		_rig.set_blend_speed(horizontal_speed)
		# Section 12: the jump has real clips (KayKit ships Jump_Start,
		# Jump_Idle and Jump_Land), so the air states drive them directly.
		match air:
			Air.JUMP:
				_rig.set_air_phase("start" if velocity.y > movement.jump_velocity() * 0.45
					else "hang")
			Air.FALL:
				_rig.set_air_phase("hang")
			Air.LAND:
				_rig.set_air_phase("land")
			_:
				_rig.set_mode_ground(true)


## Called by the interactor when a resource is actually taken. Deliberately
## an upper-body-only gesture: the legs keep whatever they were doing, so a
## pickup at a dead run neither stops the player nor turns them.
func play_pickup_gesture() -> void:
	if _rig:
		_rig.play_pickup()


## Re-dress the player from a (possibly edited) appearance. Used by the
## customisation screen; rebuilds the model and re-binds the animation rig.
func apply_appearance(a: CharacterAppearance) -> void:
	appearance = a
	var model := CharacterBuilder.build(model_pivot, appearance)
	if model == null:
		return
	_rig = LocomotionRig.new()
	_rig.setup(model)
	_pitch = 0.0
	model_pivot.rotation = Vector3(0.0, _facing, 0.0)


func state_name() -> String:
	match state:
		State.SWIM: return "SWIM"
		State.WATER: return "WATER"
		_: return "LAND"


# ------------------------------------------------------------ surface -----
## What am I standing on?
##
## Water first, because depth is the thing a collider cannot express and
## TerrainData already knows it exactly. Otherwise a single short ray
## straight down, and the answer comes from the COLLIDER it hits — its
## `surface` metadata or its `surface_*` group, walked up through its
## ancestors so a whole building can be tagged once.
##
## Section 33 of the 0.2 brief rules out reading the terrain texture, and
## rightly: the ground material blends four colours by slope, height and
## noise, so recovering an authored category from the rendered pixel would be
## guesswork that breaks the first time someone retunes the shader.
##
## The path is the one analytic override. It is a property of the terrain
## formula, not of a separate collider, so there is nothing to tag.
func _resolve_surface() -> void:
	var found := SurfaceType.Kind.UNKNOWN
	var src: Node = null

	if state == State.SWIM:
		found = SurfaceType.Kind.WATER_DEEP
	elif state == State.WATER:
		found = SurfaceType.Kind.WATER_SHALLOW
	else:
		var space := get_world_3d().direct_space_state
		var from := global_position + Vector3.UP * 0.45
		var to := global_position + Vector3.DOWN * 0.9
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = Layers.WORLD_STATIC
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			src = hit.get("collider")
			found = SurfaceType.of_collider(src)
		if found == SurfaceType.Kind.GRASS or found == SurfaceType.Kind.UNKNOWN:
			# Trodden earth, straight from the terrain formula.
			if TerrainData.path_influence(global_position.x, global_position.z) > 0.45:
				found = SurfaceType.Kind.DIRT
			elif found == SurfaceType.Kind.GRASS:
				# Bare rock shows through on the steep ground.
				if TerrainData.normal_at(global_position.x, global_position.z).y < 0.82:
					found = SurfaceType.Kind.ROCK

	surface_source = src
	if found != current_surface:
		current_surface = found
		surface_changed.emit(found)


func surface_name() -> String:
	return SurfaceType.name_of(current_surface)


func _on_water_volume_entered(_b: Node3D) -> void:
	in_water_volume = true


func _on_water_volume_exited(_b: Node3D) -> void:
	in_water_volume = false


# --------------------------------------------------- compatibility --------
## Read-through accessors so that everything which already asked the player
## "how fast do you walk?" keeps working, while the answer lives in exactly
## one place (section 36). These are NOT settable — set movement.* instead.
var walk_speed: float:
	get: return movement.walk_speed
var run_speed: float:
	get: return movement.run_speed
var sprint_speed: float:
	get: return movement.sprint_speed
var swim_speed: float:
	get: return movement.swim_speed
var swim_fast_speed: float:
	get: return movement.swim_fast_speed
var swim_enter_depth: float:
	get: return movement.swim_enter_depth
var float_depth: float:
	get: return movement.float_depth
var step_height: float:
	get: return movement.step_height
var jump_height: float:
	get: return movement.jump_height
var coyote_left: float:
	get: return _coyote
var jump_buffer_left: float:
	get: return _buffer
var is_grounded: bool:
	get: return _grounded
