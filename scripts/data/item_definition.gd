extends Resource
class_name ItemDefinition
##
## An item, described as data (section 31).
##
## The point is that adding a new collectable is a .tres file, not a new
## script and not a new branch in someone's match statement. The pickup in
## the world reads its weight, its name, its prompt and its icon from here.
##
## Nothing in 0.2 consumes `stack_limit` or `usable` yet — the real bag and
## weight system is 0.3 (section 74). They are defined now so that the data
## does not have to be re-authored when it arrives.

enum Category { RESOURCE, FOOD, TOOL, QUEST, CRYSTAL, EQUIPMENT }
enum Rarity { COMMON, UNCOMMON, RARE, UNIQUE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.RESOURCE
@export var weight_kg: float = 0.5
@export var rarity: Rarity = Rarity.COMMON
@export var stack_limit: int = 20
@export var icon: Texture2D
## Scene spawned to represent this item lying in the world.
@export var world_scene: PackedScene
## Verb shown on the interaction button. Kept per-item because "PRENDRE" is
## wrong for some things and right for most.
@export var interaction_text: String = "PRENDRE"
@export var usable: bool = false
@export var tags: PackedStringArray = PackedStringArray()


func category_name() -> String:
	return ["RESOURCE", "FOOD", "TOOL", "QUEST", "CRYSTAL", "EQUIPMENT"][category]


func has_tag(t: String) -> bool:
	return tags.has(t)
