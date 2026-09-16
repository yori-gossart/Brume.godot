extends RefCounted
class_name Layers
##
## The one place physics layers are defined (section 18).
##
## Godot's inspector shows layers as checkboxes with no names unless the
## project declares them, and raw bitmask literals scattered through twenty
## scripts is how a world ends up with a tree that stops the player but not
## the deer. Every body and area in Fog Nomad takes its layer and its mask
## from the constants below, and the names are mirrored into project.godot so
## the checkboxes are labelled in the editor too — including on a phone.
##
## Bit numbering here is the ENGINE's: layer 1 is bit 0 is value 1.
##
## See docs/PHYSICS_CONVENTIONS.md for the rationale and the full matrix.

## Level geometry: terrain, trunks, boulders, walls, beams, closed doors.
## If it is solid, it is here. Nothing else is.
const WORLD_STATIC   := 1 << 0     # 1

## The player's CharacterBody3D.
const PLAYER         := 1 << 1     # 2

## Human NPCs.
const NPC            := 1 << 2     # 4

## Animals and creatures.
const ANIMAL         := 1 << 3     # 8

## Interaction sensors — doors, campfires, pillars, chests. These are
## detection volumes, never obstacles: an InteractableComponent's Area3D
## must NOT be what stops the player. The solid part lives on WORLD_STATIC.
const INTERACTABLE   := 1 << 4     # 16

## Collectables. Separate from INTERACTABLE so a pickup can never be mistaken
## for an obstacle and vice versa.
const PICKUP         := 1 << 5     # 32

## Water volumes.
const WATER          := 1 << 6     # 64

## The Brume. Its own layer so NPCs and animals can sense it without the
## player's movement code ever colliding with it.
const HAZARD_FOG     := 1 << 7     # 128

## Everything that walks.
const ALL_CHARACTERS := PLAYER | NPC | ANIMAL

## What a walking character collides with. Characters do NOT collide with
## each other here — player/NPC separation is handled by soft avoidance
## (see scripts/characters/soft_body_avoidance.gd and section 60), because
## hard character-vs-character collision is how two NPCs wedge in a doorway
## and never move again.
const CHARACTER_MASK := WORLD_STATIC

## What a character's *sensor* area scans for.
const SENSOR_MASK    := INTERACTABLE | PICKUP

## Human-readable name for a single-bit value, for the debug HUD and for
## test failure messages.
static func name_of(bit: int) -> String:
	match bit:
		WORLD_STATIC: return "WORLD_STATIC"
		PLAYER: return "PLAYER"
		NPC: return "NPC"
		ANIMAL: return "ANIMAL"
		INTERACTABLE: return "INTERACTABLE"
		PICKUP: return "PICKUP"
		WATER: return "WATER"
		HAZARD_FOG: return "HAZARD_FOG"
		_: return "LAYER_%d" % bit


## Decompose a mask into names, e.g. "WORLD_STATIC|PICKUP".
static func describe(mask: int) -> String:
	if mask == 0:
		return "none"
	var parts := PackedStringArray()
	for b in 8:
		var bit := 1 << b
		if mask & bit:
			parts.append(name_of(bit))
	return "|".join(parts)
