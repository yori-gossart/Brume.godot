extends Resource
class_name PlayerMovementConfig
##
## EVERY NUMBER THAT DECIDES HOW MOVING FEELS (section 36).
##
## In 0.2 these values were @export vars scattered across the controller, the
## camera and the animation rig, and tuning the game meant editing three
## files and hoping they still agreed. That is exactly what section 36
## forbids: "ne pas disperser les nombres dans plusieurs scripts".
##
## So this is the single source of truth. The controller, the camera, the
## touch HUD and the test suites all read it. Nothing else defines a speed.
##
## It is a Resource rather than a constants file on purpose: it can be saved
## as a .tres, duplicated into a variant, and edited from the Godot Editor
## for Android with the inspector sliders, on the phone, without a rebuild.
##
## JUMP MATHS — the two numbers a designer actually has opinions about are
## how HIGH the jump goes and how LONG it hangs. Gravity and launch speed are
## then not free parameters; they are consequences:
##
##     v0 = 2 * height / apex_time
##     g  = 2 * height / apex_time^2
##
## Authoring it the other way round (pick a gravity, pick an impulse, measure
## what you got) is how you end up with a 2.4 m moon-hop. Sections 9 and 11
## specify the height and the apex, so those are the inputs here.

# ---------------------------------------------------------------- speed ---
@export_group("Speed")
## Sections 2 and 3. The three tiers. WALK is what a full stick with no RUN
## button gives you; RUN is the button; SPRINT is the button with the stick
## pushed to the rim.
##
## 0.2 shipped 1.5 / 4.8 and the brief's verdict was "le joueur se traîne".
## 1.5 m/s is a slow amble — a real walk is about 1.4 and a jog 3.0 — and at
## this world's scale (a 160 m map, a river 18 m across) it meant a minute of
## nothing to get anywhere. These are deliberately faster than realistic.
##
## 0.2.1b, after the first real run on the Galaxy A55: 3.4 and 5.5 were
## close but the walk still dragged a little and the run wanted more bite.
## 3.8 and 5.8. SPRINT was right and is untouched.
##
## 3.8 m/s is also, by luck rather than design, almost exactly the speed
## Running_A was authored for (3.85 m/s), so the default gait now plays at
## 0.99x — the most honest playback rate in the whole locomotion set.
@export var walk_speed: float = 3.8
@export var run_speed: float = 5.8
@export var sprint_speed: float = 7.5
## How far the stick has to be pushed, with RUN held, before WALK becomes
## SPRINT. Below this, RUN held gives RUN.
@export_range(0.5, 1.0, 0.01) var sprint_stick_threshold: float = 0.92
## Section 32: swimming must not be slower than a crawl. 2.5 .. 3.5 m/s.
@export var swim_speed: float = 2.6
@export var swim_fast_speed: float = 3.3

# --------------------------------------------------------- acceleration ---
@export_group("Acceleration")
## Section 4: 18-26 accel, 22-32 decel. High enough that the stick feels
## connected, low enough that the character has mass. At 22 m/s^2 a standing
## start reaches WALK in 0.15 s and SPRINT in 0.34 s.
@export var ground_accel: float = 22.0
@export var ground_decel: float = 28.0
## Air control. 0.2 used 3.5, which with a real jump would mean committing to
## a heading at take-off and being unable to correct. Enough to steer, not
## enough to turn a jump into flight.
@export var air_accel: float = 11.0
@export var water_accel: float = 9.0

# ------------------------------------------------------------- rotation ---
@export_group("Rotation")
## Section 5. Turning is interpolated, and how fast depends on how fast you
## are going: a standing turn is near-instant, a sprint turn has an arc. One
## fixed rate cannot be both, and the fixed 11.0 rad/s of 0.2 read as skating
## at low speed and as a handbrake turn at high speed.
@export var turn_speed_slow: float = 17.0
@export var turn_speed_fast: float = 8.5
## The speed at which turn_speed_fast is reached.
@export var turn_speed_ref: float = 7.5

# ----------------------------------------------------------------- jump ---
@export_group("Jump")
## Section 9: 1.1 .. 1.4 m. Measured from the feet, on flat ground, from a
## standing start.
@export var jump_height: float = 1.25
## Section 11: 0.35 .. 0.45 s from leaving the ground to the top.
@export var jump_apex_time: float = 0.40
## Falling is faster than rising. This is the single cheapest trick in
## platformer feel: a symmetric parabola feels floaty, a fall 40-50% heavier
## than the rise feels deliberate. It does not change the jump height.
@export var fall_gravity_multiplier: float = 1.45
## Section 10, variable height: releasing the button on the way up keeps this
## fraction of the remaining upward speed. 0.42 gives a minimum hop of about
## 0.22 m for a tap.
@export_range(0.0, 1.0, 0.01) var jump_release_multiplier: float = 0.42
## Section 13. Jumping in the 0.12 s after walking off a ledge still works.
@export var coyote_time: float = 0.12
## Section 13. Pressing jump in the 0.12 s before landing fires on landing.
@export var jump_buffer_time: float = 0.12
## Terminal velocity, so a long fall does not accelerate into tunnelling.
@export var max_fall_speed: float = 38.0
## How long the landing state is held. Purely a signal for animation and the
## HUD; it never takes control away from the player (section 34).
@export var land_recovery_time: float = 0.18

# ------------------------------------------------------- ground contact ---
@export_group("Ground")
## Section 14: obstacles up to this high are walked over, not jumped over.
## 0.30 m is a kerb, a doorstep, a fallen branch, the lip of a ruin's floor.
@export_range(0.0, 0.6, 0.01) var step_height: float = 0.30
## Section 16. Past this the ground is a wall and you slide down it.
@export var max_slope_deg: float = 52.0
## How much an uphill costs. 0.2 used 0.62, which at the new speeds turned
## every hill into a wall of treacle.
@export var slope_penalty: float = 0.40
## Keeps the body glued to the ground over bumps and crests. Too short and
## you launch off every rise; too long and step-downs feel magnetic.
@export var floor_snap_length: float = 0.40

# ---------------------------------------------------------------- water ---
@export_group("Water")
@export var swim_enter_depth: float = 1.35
@export var swim_exit_margin: float = 0.28
## How far the body origin (the feet) floats below the surface when swimming.
@export var float_depth: float = 0.88
@export var buoyancy: float = 6.0
## Wading drag, from ankle-deep to swim-deep. The 0.2 floor of 0.30 was a
## crawl; at the new speeds 0.45 still reads as heavy water without stopping
## the player dead.
@export var wade_drag_shallow: float = 0.80
@export var wade_drag_deep: float = 0.45
## Section 30: you can jump out of shallow water, but not out of a swim.
@export var max_jump_depth: float = 0.75


# ------------------------------------------------------------ derived -----
## Launch speed that produces `jump_height` under `rise_gravity()`.
func jump_velocity() -> float:
	return 2.0 * jump_height / maxf(jump_apex_time, 0.01)


## Gravity while going up. Derived, never authored.
func rise_gravity() -> float:
	var t: float = maxf(jump_apex_time, 0.01)
	return 2.0 * jump_height / (t * t)


## Gravity while going down.
func fall_gravity() -> float:
	return rise_gravity() * fall_gravity_multiplier


## Ceiling speed for a tier. `tier` is PlayerController.Tier.
func tier_speed(tier: int) -> float:
	match tier:
		2: return sprint_speed
		1: return run_speed
		_: return walk_speed


## How fast the character turns at a given ground speed.
func turn_speed_at(speed: float) -> float:
	var t: float = clampf(speed / maxf(turn_speed_ref, 0.01), 0.0, 1.0)
	return lerpf(turn_speed_slow, turn_speed_fast, t)


## Self-check against the bands the brief actually specifies, so a bad edit
## from a phone inspector is caught by the test suite instead of by feel.
## Returns an empty array when everything is inside its band.
func out_of_spec() -> PackedStringArray:
	var bad := PackedStringArray()
	if walk_speed < 3.2 or walk_speed > 4.0:
		bad.append("walk_speed %.2f outside 3.2..4.0 (0.2.1b section 1)" % walk_speed)
	if run_speed < 5.2 or run_speed > 6.2:
		bad.append("run_speed %.2f outside 5.2..6.2 (0.2.1b section 1)" % run_speed)
	if sprint_speed < 7.0 or sprint_speed > 8.0:
		bad.append("sprint_speed %.2f outside 7.0..8.0 (section 2)" % sprint_speed)
	if not (walk_speed < run_speed and run_speed < sprint_speed):
		bad.append("speed tiers are not strictly increasing")
	if ground_accel < 18.0 or ground_accel > 26.0:
		bad.append("ground_accel %.1f outside 18..26 (section 4)" % ground_accel)
	if ground_decel < 22.0 or ground_decel > 32.0:
		bad.append("ground_decel %.1f outside 22..32 (section 4)" % ground_decel)
	if jump_height < 1.1 or jump_height > 1.4:
		bad.append("jump_height %.2f outside 1.1..1.4 (section 9)" % jump_height)
	if jump_apex_time < 0.35 or jump_apex_time > 0.45:
		bad.append("jump_apex_time %.2f outside 0.35..0.45 (section 11)" % jump_apex_time)
	if coyote_time < 0.10 or coyote_time > 0.15:
		bad.append("coyote_time %.3f outside 0.10..0.15 (section 13)" % coyote_time)
	if jump_buffer_time < 0.10 or jump_buffer_time > 0.15:
		bad.append("jump_buffer_time %.3f outside 0.10..0.15 (section 13)" % jump_buffer_time)
	if step_height < 0.20 or step_height > 0.35:
		bad.append("step_height %.2f outside 0.20..0.35 (section 14)" % step_height)
	if swim_speed < 2.5 or swim_fast_speed > 3.5 or swim_speed > swim_fast_speed:
		bad.append("swim speeds %.2f/%.2f outside 2.5..3.5 (section 32)"
			% [swim_speed, swim_fast_speed])
	return bad
