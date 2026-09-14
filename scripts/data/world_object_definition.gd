extends Resource
class_name WorldObjectDefinition
##
## What a thing in the world IS (sections 32, 53).
##
## Every placed object declares one of five categories, and the category
## decides its physics. That is the whole point: a tree, a door and a flower
## should not each be a bespoke special case with its own hand-written
## collision setup, because that is how one of them ends up with none.
##
## `tests/collision_world_test.gd` fails on any object left in AMBIGUOUS.

enum Category {
	## Collision, no interaction. Trunk, boulder, wall, pillar.
	STATIC_SOLID,
	## Collision AND interaction. Door, chest, campfire, crystal pillar.
	STATIC_INTERACTABLE,
	## Interaction, no obstruction. Wood, crystal.
	PICKUP,
	## Neither. Grass, flower, pebble, lily.
	DECORATIVE,
	## A CharacterBody3D. Player, NPC, animal.
	CHARACTER,
	## Not classified — a bug, and the audit says so.
	AMBIGUOUS,
}

enum CollisionProfile { NONE, TRUNK_CYLINDER, CONVEX_HULL, BOX, COMPOUND, CAPSULE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.AMBIGUOUS
@export var solid: bool = false
@export var interactable: bool = false
## SurfaceType.Kind the player hears and feels when standing on this.
@export var surface_type: int = SurfaceType.Kind.UNKNOWN
@export var interaction_type: String = ""
@export var collision_profile: CollisionProfile = CollisionProfile.NONE
@export var tags: PackedStringArray = PackedStringArray()


func category_name() -> String:
	return ["STATIC_SOLID", "STATIC_INTERACTABLE", "PICKUP", "DECORATIVE",
		"CHARACTER", "AMBIGUOUS"][category]


## The category and the flags must agree. Disagreement means somebody edited
## one and not the other, which is exactly how a door loses its collision.
func is_consistent() -> bool:
	match category:
		Category.STATIC_SOLID: return solid and not interactable
		Category.STATIC_INTERACTABLE: return solid and interactable
		Category.PICKUP: return not solid and interactable
		Category.DECORATIVE: return not solid and not interactable
		Category.CHARACTER: return solid
		_: return false
