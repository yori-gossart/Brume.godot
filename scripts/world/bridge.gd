extends Node3D
class_name Bridge
##
## A crossing (section 26).
##
## The large Brume-traversal system is later work, but a bridge that exists
## in the world now has to be a bridge now: a deck you can actually walk on,
## parapets that stop you falling off, piers in the water, and approaches at
## both ends that meet the ground instead of hanging half a metre above it.
##
## The deck is tagged WOOD, so the surface system reports planks underfoot
## the moment you step on — which is the cheapest possible proof that the
## surface system is reading real colliders (section 33).

@export var span: float = 16.0
@export var deck_width: float = 3.0
@export var deck_thickness: float = 0.22
@export var rail_height: float = 0.95
## Deck height above the water line.
@export var deck_clearance: float = 1.5

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x42524447
	var body := StaticBody3D.new()
	body.name = "BridgeCollision"
	body.collision_layer = Layers.WORLD_STATIC
	body.collision_mask = 0
	SurfaceType.tag(body, SurfaceType.Kind.WOOD)
	add_child(body)

	var plank := BuildKit.material(Color(0.435, 0.337, 0.227), 0.86)
	var beam := BuildKit.material(Color(0.318, 0.239, 0.165), 0.9)
	var rope := BuildKit.material(Color(0.51, 0.443, 0.318), 0.95)

	var y := deck_clearance

	# --- deck, as separate planks so it reads as boards, one collider -----
	var plank_count := int(span / 0.42)
	for i in plank_count:
		var t := (float(i) + 0.5) / float(plank_count)
		var z := lerpf(-span * 0.5, span * 0.5, t)
		BuildKit.box(self, null, plank, Vector3(0, y, z),
			Vector3(deck_width, deck_thickness, 0.36),
			Vector3(0, 0, _rng.randf_range(-0.008, 0.008)), false)
	# One box for the whole walking surface: many thin colliders in a row is
	# how a character catches on a seam.
	var deck_shape := BoxShape3D.new()
	deck_shape.size = Vector3(deck_width, deck_thickness, span)
	var deck_cs := CollisionShape3D.new()
	deck_cs.name = "DeckCollision"
	deck_cs.shape = deck_shape
	deck_cs.position = Vector3(0, y, 0)
	body.add_child(deck_cs)

	# --- longitudinal beams under the deck --------------------------------
	for s: float in [-1.0, 1.0]:
		BuildKit.box(self, null, beam,
			Vector3(s * (deck_width * 0.5 - 0.18), y - deck_thickness, 0),
			Vector3(0.22, 0.26, span), Vector3.ZERO, false)

	# --- parapets: solid, so you are stopped rather than nudged -----------
	for s: float in [-1.0, 1.0]:
		var posts := int(span / 2.2)
		for i in posts + 1:
			var z := lerpf(-span * 0.5 + 0.3, span * 0.5 - 0.3, float(i) / float(posts))
			BuildKit.box(self, null, beam,
				Vector3(s * (deck_width * 0.5 - 0.1), y + rail_height * 0.5, z),
				Vector3(0.12, rail_height, 0.12), Vector3.ZERO, false)
		# The rail itself carries the collision for the whole side.
		BuildKit.box(self, body, rope,
			Vector3(s * (deck_width * 0.5 - 0.1), y + rail_height, 0),
			Vector3(0.14, 0.14, span - 0.4))
		BuildKit.box(self, body, rope,
			Vector3(s * (deck_width * 0.5 - 0.1), y + rail_height * 0.52, 0),
			Vector3(0.1, 0.1, span - 0.4))

	# --- piers ------------------------------------------------------------
	for s: float in [-1.0, 1.0]:
		for zs: float in [-1.0, 1.0]:
			BuildKit.cylinder(self, body, beam,
				Vector3(s * (deck_width * 0.5 - 0.3), y * 0.5 - 0.4, zs * span * 0.26),
				0.17, y + 0.8, Vector3.ZERO, true, 6)

	# --- approaches: ramps that meet the ground ---------------------------
	# Without these the bridge is a step, and a step at deck height is a wall.
	for zs: float in [-1.0, 1.0]:
		var end_z: float = zs * (span * 0.5)
		# Sample the terrain at the end of the deck IN WORLD SPACE: the
		# bridge is usually rotated to cross the river, so offsetting the
		# node's position along Z would sample the wrong bank entirely.
		var world_end := global_transform * Vector3(0.0, 0.0, end_z)
		var ground := TerrainData.height_at(world_end.x, world_end.z) - global_position.y
		var drop := y - ground
		if drop <= 0.05:
			continue
		var ramp_len := maxf(drop * 2.6, 1.5)
		var steps := 5
		for i in steps:
			var f := (float(i) + 0.5) / float(steps)
			BuildKit.box(self, body, plank,
				Vector3(0, lerpf(y, ground + 0.08, f), end_z + zs * ramp_len * f),
				Vector3(deck_width * 0.96, deck_thickness + 0.16, ramp_len / float(steps) + 0.12))

	BuildKit.merge_by_material(self, [])
