extends RefCounted
class_name SurfaceType
##
## What the player is standing on (section 33).
##
## The surface is read from the COLLIDER: either a `surface` entry in the
## collider's node metadata, or its membership of a `surface_*` group.
## Never from the texture. Sampling the albedo of a shaded, tinted, blended
## terrain material and hoping to recover an authored category is guesswork
## that breaks the moment an artist changes a colour.
##
## Water is the one case resolved analytically instead, because water depth
## already comes from TerrainData and a collider cannot express "how deep".

enum Kind { GRASS, DIRT, ROCK, WOOD, WATER_SHALLOW, WATER_DEEP, UNKNOWN }

const NAMES := {
	Kind.GRASS: "GRASS",
	Kind.DIRT: "DIRT",
	Kind.ROCK: "ROCK",
	Kind.WOOD: "WOOD",
	Kind.WATER_SHALLOW: "WATER_SHALLOW",
	Kind.WATER_DEEP: "WATER_DEEP",
	Kind.UNKNOWN: "UNKNOWN",
}

## Metadata key a collider (or any ancestor) may carry to declare itself.
const META_KEY := "surface"

## Group prefix, as an alternative to metadata: `surface_wood`, etc.
const GROUP_PREFIX := "surface_"


static func name_of(kind: int) -> String:
	return NAMES.get(kind, "UNKNOWN")


static func from_string(s: String) -> int:
	match s.strip_edges().to_upper():
		"GRASS": return Kind.GRASS
		"DIRT", "PATH": return Kind.DIRT
		"ROCK", "STONE": return Kind.ROCK
		"WOOD", "PLANK", "TIMBER": return Kind.WOOD
		"WATER_SHALLOW": return Kind.WATER_SHALLOW
		"WATER_DEEP": return Kind.WATER_DEEP
		_: return Kind.UNKNOWN


## Resolve the surface of a collider node, walking up to its ancestors so a
## whole building can be tagged once instead of every plank.
static func of_collider(node: Node) -> int:
	var n := node
	var hops := 0
	while n != null and hops < 6:
		if n.has_meta(META_KEY):
			var k := from_string(str(n.get_meta(META_KEY)))
			if k != Kind.UNKNOWN:
				return k
		for g in n.get_groups():
			var gs := str(g)
			if gs.begins_with(GROUP_PREFIX):
				var k2 := from_string(gs.substr(GROUP_PREFIX.length()))
				if k2 != Kind.UNKNOWN:
					return k2
		n = n.get_parent()
		hops += 1
	return Kind.UNKNOWN


## Tag a node (and therefore everything under it) as a surface.
static func tag(node: Node, kind: int) -> void:
	node.set_meta(META_KEY, name_of(kind))
