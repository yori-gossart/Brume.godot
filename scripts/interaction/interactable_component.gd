extends Area3D
class_name InteractableComponent
##
## One component, every interaction (section 27).
##
## In 0.1 the only interactive thing was a pickup, and the player's scanner
## knew it by duck-typing (`has_method("can_collect")`). That does not
## survive contact with doors, campfires, pillars and chests.
##
## Here, anything interactive gets one of these as a child Area3D on the
## INTERACTABLE layer. It carries the verb, the noun, the reach, a priority
## and a state, and it answers one question: can this actor use me right now,
## and what should the button say?
##
## IT IS A SENSOR, NEVER AN OBSTACLE. The solid part of a door lives on a
## separate StaticBody3D on WORLD_STATIC. Mixing the two gives either a door
## you walk through or an invisible wall three metres wide.

signal interacted(actor: Node3D)
signal state_changed(new_state: StringName)

enum Action { TAKE, OPEN, CLOSE, LIGHT, EXTINGUISH, INSPECT, ACTIVATE, USE, INSERT }

const ACTION_TEXT := {
	Action.TAKE: "PRENDRE",
	Action.OPEN: "OUVRIR",
	Action.CLOSE: "FERMER",
	Action.LIGHT: "ALLUMER",
	Action.EXTINGUISH: "ÉTEINDRE",
	Action.INSPECT: "INSPECTER",
	Action.ACTIVATE: "ACTIVER",
	Action.USE: "UTILISER",
	Action.INSERT: "INSÉRER",
}

@export var action: Action = Action.USE
## The noun shown after the verb: "OUVRIR — Porte".
@export var noun: String = ""
## Maximum distance from the actor. Deliberately per-object: a door is
## reachable from arm's length, a beacon from a couple of metres.
@export var interact_range: float = 2.2
## Ties are broken by this before distance. Higher wins.
## NOT named `priority`: Area3D already has a member by that name in 4.3.
@export var interact_priority: int = 0
@export var enabled: bool = true
## Require an unobstructed line from the actor's chest. Stops the player
## activating a pillar through a wall (section 73).
@export var requires_line_of_sight: bool = true
## Optional: the object this component belongs to, for the audit.
@export var definition: WorldObjectDefinition
## Optional gate. If set and it has `can_be_used_by(actor) -> bool`, that
## decides whether the prompt is offered at all. A campfire with no wood in
## your pack should not put a button on screen you cannot press.
@export var condition_target: Node

var state: StringName = &"READY"


func _ready() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = 0
	monitoring = false      # it is scanned, it does not scan
	monitorable = true
	add_to_group(&"interactable")


## Can this actor use it right now? Subclasses narrow this.
func can_interact(actor: Node3D) -> bool:
	if not enabled:
		return false
	if condition_target and condition_target.has_method("can_be_used_by"):
		return bool(condition_target.call("can_be_used_by", actor))
	return true


## The button label. "OUVRIR — Porte".
func prompt() -> String:
	var verb := str(ACTION_TEXT.get(action, "UTILISER"))
	return verb if noun.is_empty() else "%s — %s" % [verb, noun]


## Do the thing. Subclasses override this; the default just announces.
## Returning false means "not now" and the interactor keeps the prompt up.
func perform(actor: Node3D) -> bool:
	if not can_interact(actor):
		return false
	interacted.emit(actor)
	return true


func set_state(s: StringName) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


## Where the actor should be judged to be reaching for. Overridable so a big
## object can present its handle rather than its centre of mass.
func focus_point() -> Vector3:
	return global_position
