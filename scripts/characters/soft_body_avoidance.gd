extends RefCounted
class_name SoftBodyAvoidance
##
## Keeping characters out of each other (section 60).
##
## The brief offers two options — light physical collision, or avoidance and
## soft blocking — and one requirement: whatever is chosen, two characters
## must not end up permanently stuck.
##
## This picks avoidance, and the reason is the stuck clause. Two
## CharacterBody3Ds that collide hard will each push the other, each will
## resolve by sliding, and in a doorway or against a wall the two resolutions
## fight: they jam, and neither has any way out because neither has anywhere
## to slide to. It is the single most common way an NPC dies standing up.
##
## So characters are on separate layers and none of their movement masks
## contains another character. Separation is a steering term instead:
##
##   * it pushes LATERALLY, never backwards, so it can never cancel forward
##     motion and never causes the deadlock;
##   * it is capped, so a crowd cannot launch anybody;
##   * it fades in with proximity rather than switching on, so two people
##     walking past each other drift apart instead of bouncing.
##
## The player is therefore not a ghost — walk into an NPC and you are
## deflected around them — but you can never trap them and they can never
## trap you.

const GROUP := &"avoidance_body"

## Below this separation the push is at full strength.
const HARD_RADIUS := 0.62
## Above this there is no push at all.
const SOFT_RADIUS := 1.45
const MAX_PUSH := 2.4


## Register a character so others steer around it.
static func register(body: Node3D) -> void:
	body.add_to_group(GROUP)


## Lateral velocity correction for `body`, given where it is trying to go.
## Add this to the horizontal velocity; do not replace it.
static func push_for(body: Node3D, heading: Vector3) -> Vector3:
	var total := Vector3.ZERO
	var here := body.global_position
	for other in body.get_tree().get_nodes_in_group(GROUP):
		if other == body or not (other is Node3D):
			continue
		var o := other as Node3D
		var away := here - o.global_position
		away.y = 0.0
		var d := away.length()
		if d >= SOFT_RADIUS:
			continue
		if d < 0.001:
			# Exactly co-located: pick a deterministic side so two bodies do
			# not both choose the same escape and stay stacked.
			away = Vector3(1, 0, 0).rotated(Vector3.UP, float(body.get_instance_id() % 628) * 0.01)
			d = 0.001
		var strength := 1.0 - smoothstep(HARD_RADIUS, SOFT_RADIUS, d)
		total += (away / d) * strength

	if total.length() < 0.001:
		return Vector3.ZERO

	# Keep only the component across the direction of travel. Pushing
	# backwards would let a crowd stop someone dead, which is the failure
	# this whole approach exists to avoid.
	var flat_heading := Vector3(heading.x, 0.0, heading.z)
	if flat_heading.length() > 0.01:
		flat_heading = flat_heading.normalized()
		var along := total.dot(flat_heading)
		if along < 0.0:
			total -= flat_heading * along
	return total.limit_length(MAX_PUSH)
