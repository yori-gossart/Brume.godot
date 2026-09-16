extends RefCounted
class_name StickShaping
##
## THE FORWARD STEERING CORRIDOR (0.2.1b, section 2).
##
## Reported from the Galaxy A55: trying to run straight ahead, the smallest
## sideways drift of the thumb immediately curves the character off line. A
## virtual stick has no notch at twelve o'clock and no spring pulling back to
## it, so "straight ahead" is a single exact angle out of 360 that a thumb
## resting on glass cannot hold.
##
## The fix is a corridor around the forward axis in which the accidental
## lateral component is removed, followed by a short band in which it fades
## back in. Outside it, nothing is touched: hard turns, diagonals, strafing
## and backing up all keep the full analogue range, because the point is to
## stop a 4 degree wobble becoming a curve, NOT to turn the stick into eight
## directions.
##
## THE AXIS IS A PARAMETER, NOT A CONSTANT.
##
## This file never assumes which way "forward" points. The stick works in
## screen space (Y down), the controller works in an input space where +Y is
## away from the camera, and the world works in metres — three conventions,
## and an angle hardcoded against the wrong one is a bug that looks like it
## works until someone turns around. The caller passes the forward axis it
## actually uses, and everything here is computed relative to it.
##
## MAGNITUDE IS PRESERVED EXACTLY.
##
## Zeroing the lateral part of a unit vector leaves a vector shorter than
## one: at 10 degrees off forward that is a 1.5% speed cut, which would mean
## the corridor quietly slowed the player down. So the corrected vector is
## rescaled to the length it came in with. The corridor changes DIRECTION
## and nothing else — section 4's test G measures exactly that.

## Half-width of the corridor: inside this angle from forward, the lateral
## component is removed entirely. 15 degrees each side = a 30 degree corridor.
const CORRIDOR_DEG := 15.0
## How far past the corridor the lateral component takes to come fully back.
## Without it the corridor edge is a cliff the player can feel.
const BLEND_DEG := 9.0


## Shape a stick vector so that near-forward input reads as forward.
##
## `v`       the raw stick vector, in whatever space the caller uses
## `forward` that same space's forward axis (need not be normalised)
##
## Returns a vector with the same length as `v` and a direction that has been
## straightened if it was near forward.
static func forward_corridor(v: Vector2, forward: Vector2,
		corridor_deg: float = CORRIDOR_DEG,
		blend_deg: float = BLEND_DEG) -> Vector2:
	var mag := v.length()
	if mag < 0.0001 or forward.length_squared() < 0.0001 or corridor_deg <= 0.0:
		return v

	var f := forward.normalized()
	# Left-hand perpendicular of the forward axis. Which of the two
	# perpendiculars it is does not matter: the lateral component is measured
	# and rebuilt along the same one, so the sign cancels.
	var side := Vector2(-f.y, f.x)
	var along := v.dot(f)
	var lateral := v.dot(side)

	# Only the forward half of the stick has a corridor. Pulling back is a
	# deliberate act with no "straight ahead" to snap to, and section 2 is
	# explicit that backing up must keep working exactly as it does now.
	if along <= 0.0:
		return v

	var angle := rad_to_deg(atan2(absf(lateral), along))
	var keep := 1.0
	if angle <= corridor_deg:
		keep = 0.0
	elif blend_deg > 0.0 and angle < corridor_deg + blend_deg:
		# smoothstep, so the lateral component reappears with no corner: its
		# rate of change is zero at both ends of the band.
		keep = smoothstep(corridor_deg, corridor_deg + blend_deg, angle)

	if is_equal_approx(keep, 1.0):
		return v

	var shaped := f * along + side * (lateral * keep)
	if shaped.length_squared() < 0.0000001:
		return v
	# Same intensity in, same intensity out.
	return shaped.normalized() * mag


## The angle, in degrees, between `v` and `forward`. Signed, positive towards
## the left-hand perpendicular. Used by the tests to say what the stick asked
## for and what came out.
static func angle_from(v: Vector2, forward: Vector2) -> float:
	if v.length_squared() < 0.0000001 or forward.length_squared() < 0.0000001:
		return 0.0
	var f := forward.normalized()
	return rad_to_deg(atan2(v.dot(Vector2(-f.y, f.x)), v.dot(f)))
