extends Area3D
class_name Interactor
##
## Proximity interaction (section 13).
##
## The three.js build required the player to very nearly stop before an
## object would accept a pickup. That is the behaviour this is built to
## reject, so the rules here are deliberately blunt:
##
##   * the candidate is chosen from an Area3D overlap, never from a raycast
##     that needs the player to be aiming at anything;
##   * collecting does NOT touch velocity, does NOT touch the facing angle
##     and does NOT change the movement state;
##   * the confirming animation is filtered to the upper body, so the legs
##     keep running through it;
##   * there is no cooldown that would make a second pickup on the same run
##     fail silently.
##
## The player can hold the stick, keep running and tap RAMASSER as they go
## past. That is the test.

signal candidate_changed(pickup: Node)
signal collected(kind: String, amount: int, total: int)

## A little forward bias, so that when two resources are in range the one you
## are running towards wins.
@export var forward_bias: float = 1.4

var _candidates: Array[Node] = []
var current: Node = null
var totals: Dictionary = {}

@onready var _player: PlayerController = get_parent() as PlayerController


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	monitoring = true


func _on_area_entered(a: Area3D) -> void:
	if a.has_method("can_collect") and not _candidates.has(a):
		_candidates.append(a)
		_refresh()


func _on_area_exited(a: Area3D) -> void:
	if _candidates.has(a):
		_candidates.erase(a)
		_refresh()


func _physics_process(_d: float) -> void:
	# The best candidate changes as the player runs past things, so it is
	# re-scored every tick rather than only on enter/exit.
	if _candidates.size() > 1:
		_refresh()


func _refresh() -> void:
	var best: Node = null
	var best_score := -INF
	var origin := _player.global_position
	var heading := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if heading.length() < 0.2:
		heading = -_player.model_pivot.global_transform.basis.z
	heading = heading.normalized()
	for c in _candidates:
		if not is_instance_valid(c) or not c.call("can_collect"):
			continue
		var to: Vector3 = (c as Node3D).global_position - origin
		var dist := to.length()
		var score := -dist
		if dist > 0.01:
			score += heading.dot(to / dist) * forward_bias
		if score > best_score:
			best_score = score
			best = c
	if best != current:
		current = best
		candidate_changed.emit(current)


func has_candidate() -> bool:
	return current != null and is_instance_valid(current)


func prompt() -> String:
	if not has_candidate():
		return ""
	return str(current.call("prompt_text"))


## Take the current candidate. Returns true if something was collected.
## Note what this function does NOT do: it never writes to the player's
## velocity, rotation or state.
func interact() -> bool:
	if not has_candidate():
		return false
	var node := current
	var kind := str(node.call("resource_kind"))
	var amount := int(node.call("resource_amount"))
	if not node.call("collect", _player):
		return false
	totals[kind] = int(totals.get(kind, 0)) + amount
	_player.play_pickup_gesture()
	_candidates.erase(node)
	current = null
	collected.emit(kind, amount, int(totals[kind]))
	_refresh()
	return true


func total_of(kind: String) -> int:
	return int(totals.get(kind, 0))
