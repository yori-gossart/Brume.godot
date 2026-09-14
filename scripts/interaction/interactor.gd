extends Area3D
class_name Interactor
##
## The player's interaction scanner (sections 28, 29, 30, 73).
##
## Two properties matter more than anything else here.
##
## 1. IT NEVER TOUCHES LOCOMOTION. Interacting does not zero the velocity,
##    does not rotate the body, does not change the movement state and has
##    no cooldown. Section 28 is explicit and section 29 measures it: speed
##    after must be at least 90% of speed before, heading essentially
##    unchanged. The only thing an interaction plays on the player is an
##    upper-body gesture, and even that is filtered off the legs.
##
## 2. IT PICKS ONE TARGET, AND THE RIGHT ONE. "I picked up the thing behind
##    me" is called out in section 30. Candidates are scored on distance,
##    on how far ahead of the player they are, and on priority, and anything
##    behind a wall is rejected by a line-of-sight ray.

signal candidate_changed(component: InteractableComponent)
signal interacted(component: InteractableComponent, actor: Node3D)
signal collected(item: ItemDefinition, amount: int, total: int)

## Weight of "is it in front of me" against "is it close to me". Raising it
## makes the scanner more directional.
@export var forward_weight: float = 2.2
## Candidates more than this far off the heading are rejected outright.
@export var max_angle_deg: float = 110.0
## Height above the body origin the line-of-sight ray starts from.
@export var eye_height: float = 1.15

var current: InteractableComponent = null
var totals: Dictionary = {}          ## StringName id -> count
var carried_weight: float = 0.0

var _candidates: Array[InteractableComponent] = []
@onready var _actor: Node3D = get_parent() as Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.SENSOR_MASK
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(a: Area3D) -> void:
	if a is InteractableComponent and not _candidates.has(a):
		_candidates.append(a)


func _on_area_exited(a: Area3D) -> void:
	if a is InteractableComponent and _candidates.has(a):
		_candidates.erase(a)
		if current == a:
			_set_current(null)


func _physics_process(_d: float) -> void:
	_rescore()


## Heading used for the "in front of me" term: where the body is actually
## travelling, falling back to where it is facing when standing still.
func _heading() -> Vector3:
	var v := Vector3.ZERO
	if _actor is CharacterBody3D:
		var cb := _actor as CharacterBody3D
		v = Vector3(cb.velocity.x, 0.0, cb.velocity.z)
	if v.length() < 0.2 and _actor.has_node("ModelPivot"):
		var pivot: Node3D = _actor.get_node("ModelPivot")
		v = pivot.global_transform.basis.z    # KayKit rigs face +Z
	if v.length() < 0.01:
		return Vector3.FORWARD
	return v.normalized()


func _rescore() -> void:
	var best: InteractableComponent = null
	var best_score := -INF
	var origin := _actor.global_position
	var heading := _heading()
	var cos_limit := cos(deg_to_rad(max_angle_deg))

	for c in _candidates:
		if not is_instance_valid(c) or not c.can_interact(_actor):
			continue
		var to: Vector3 = c.focus_point() - origin
		var flat := Vector3(to.x, 0.0, to.z)
		var dist := to.length()
		# Each object declares its own reach (section 73).
		if dist > c.interact_range:
			continue
		var facing := 1.0
		if flat.length() > 0.05:
			facing = heading.dot(flat.normalized())
			if facing < cos_limit:
				continue    # behind the player
		if c.requires_line_of_sight and not _has_line_of_sight(c):
			continue
		var score := float(c.interact_priority) * 10.0
		score += facing * forward_weight
		score -= dist
		if score > best_score:
			best_score = score
			best = c

	if best != current:
		_set_current(best)


## Is there level geometry between the player's chest and the object?
func _has_line_of_sight(c: InteractableComponent) -> bool:
	var space := _actor.get_world_3d().direct_space_state
	var from := _actor.global_position + Vector3.UP * eye_height
	var to := c.focus_point()
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# Only walls block sight. Characters, water and other sensors do not.
	q.collision_mask = Layers.WORLD_STATIC
	q.hit_from_inside = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	# A hit almost at the target is the object's own solid body, not a wall.
	var d_hit: float = (hit["position"] as Vector3).distance_to(from)
	return d_hit >= from.distance_to(to) - 0.45


func _set_current(c: InteractableComponent) -> void:
	current = c
	candidate_changed.emit(c)


func has_candidate() -> bool:
	return current != null and is_instance_valid(current)


func prompt() -> String:
	return current.prompt() if has_candidate() else ""


## Use the current target.
##
## Note what is absent: no velocity write, no rotation write, no state
## change, no cooldown. That absence is the feature.
func interact() -> bool:
	if not has_candidate():
		return false
	var c := current
	if not c.perform(_actor):
		return false
	interacted.emit(c, _actor)
	if _actor.has_method("play_pickup_gesture"):
		_actor.call("play_pickup_gesture")
	_rescore()
	return true


## Called by a pickup once it has actually been taken.
func register_item(item: ItemDefinition, amount: int) -> void:
	if item == null:
		return
	totals[item.id] = int(totals.get(item.id, 0)) + amount
	carried_weight += item.weight_kg * amount
	collected.emit(item, amount, int(totals[item.id]))


func total_of(id: StringName) -> int:
	return int(totals.get(id, 0))


## Spend items. Returns false and changes nothing if there are not enough —
## callers rely on that to refuse an interaction cleanly.
func consume_item(id: StringName, amount: int) -> bool:
	var have := int(totals.get(id, 0))
	if have < amount:
		return false
	totals[id] = have - amount
	var def := _definition_for(id)
	if def:
		carried_weight = maxf(0.0, carried_weight - def.weight_kg * amount)
	return true


func _definition_for(id: StringName) -> ItemDefinition:
	var path := "res://assets/data/items/%s.tres" % ("wood" if id == &"BOIS" else "crystal")
	return load(path) if ResourceLoader.exists(path) else null
