extends Node3D
class_name ScoutCabin
##
## The scout post (section 22): four log walls, a plank floor, a doorway you
## can walk through, a gabled roof, a covered interior, and collision that
## actually stops you.
##
## Three distinct materials meet here on purpose — log, sawn plank and stone
## footing — because "a real material system" (section 12/16) is one of the
## things being compared, and a single-material hut would prove nothing.

@export var width: float = 6.2
@export var depth: float = 5.0
@export var wall_height: float = 2.5
@export var door_width: float = 1.5

var merged_away: int = 0
var door: Door

var footprint_radius: float:
	get: return maxf(width, depth) * 0.72


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "CabinCollision"
	body.collision_layer = Layers.WORLD_STATIC
	body.collision_mask = 0
	# Everything under here is planks and logs underfoot.
	SurfaceType.tag(body, SurfaceType.Kind.WOOD)
	add_child(body)

	var log_mat := BuildKit.material(Color(0.396, 0.290, 0.196), 0.88)
	var plank := BuildKit.material(Color(0.478, 0.376, 0.259), 0.82)
	var stone := BuildKit.material(Color(0.361, 0.353, 0.341), 0.93)
	var roof := BuildKit.material(Color(0.263, 0.235, 0.212), 0.85)
	var dark := BuildKit.material(Color(0.145, 0.122, 0.106), 0.95)

	var hw := width * 0.5
	var hd := depth * 0.5
	var t := 0.22

	# --- stone footing, so the cabin is not floating on a hillside --------
	BuildKit.box(self, body, stone, Vector3(0, -0.28, 0),
		Vector3(width + 0.5, 0.62, depth + 0.5))
	# --- floor ------------------------------------------------------------
	BuildKit.box(self, body, plank, Vector3(0, 0.06, 0), Vector3(width, 0.14, depth))

	# --- back and side walls ---------------------------------------------
	BuildKit.box(self, body, log_mat, Vector3(0, wall_height * 0.5, -hd + t * 0.5),
		Vector3(width, wall_height, t))
	BuildKit.box(self, body, log_mat, Vector3(-hw + t * 0.5, wall_height * 0.5, 0),
		Vector3(t, wall_height, depth))
	BuildKit.box(self, body, log_mat, Vector3(hw - t * 0.5, wall_height * 0.5, 0),
		Vector3(t, wall_height, depth))

	# --- front wall, split around the doorway -----------------------------
	var side := (width - door_width) * 0.5
	BuildKit.box(self, body, log_mat, Vector3(-(door_width * 0.5 + side * 0.5), wall_height * 0.5, hd - t * 0.5),
		Vector3(side, wall_height, t))
	BuildKit.box(self, body, log_mat, Vector3(door_width * 0.5 + side * 0.5, wall_height * 0.5, hd - t * 0.5),
		Vector3(side, wall_height, t))
	# Lintel above the opening: high enough to walk under, low enough to read
	# as a door rather than a gap in the wall.
	BuildKit.box(self, body, log_mat, Vector3(0, wall_height - 0.28, hd - t * 0.5),
		Vector3(door_width, 0.56, t))
	# Door posts
	for s in [-1.0, 1.0]:
		BuildKit.box(self, body, plank, Vector3(s * door_width * 0.5, (wall_height - 0.56) * 0.5, hd - t * 0.5),
			Vector3(0.12, wall_height - 0.56, t * 1.2))

	# --- corner posts, for the silhouette ---------------------------------
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			BuildKit.cylinder(self, body, log_mat,
				Vector3(sx * (hw - 0.12), wall_height * 0.5 + 0.12, sz * (hd - 0.12)),
				0.17, wall_height + 0.24, Vector3.ZERO, true, 8)

	# --- gabled roof ------------------------------------------------------
	var pitch := 0.42
	for s in [-1.0, 1.0]:
		BuildKit.box(self, body, roof,
			Vector3(s * (hw * 0.53), wall_height + hw * 0.5 * pitch * 0.5 + 0.12, 0),
			Vector3(hw * 1.16, 0.16, depth + 0.85),
			Vector3(0, 0, s * -pitch))
	# Gable ends close the triangle so the interior is genuinely covered.
	for s in [-1.0, 1.0]:
		BuildKit.prism(self, dark, Vector3(0, wall_height + 0.02, s * (hd - 0.02)),
			Vector3(width, hw * pitch, 0.12))
	# Ridge beam
	BuildKit.box(self, null, log_mat, Vector3(0, wall_height + hw * pitch * 0.5 + 0.1, 0),
		Vector3(0.2, 0.2, depth + 0.9), Vector3.ZERO, false)

	# --- interior: a bunk and a crate, so the inside is not an empty box --
	BuildKit.box(self, body, plank, Vector3(-hw + 1.0, 0.42, -hd + 1.0),
		Vector3(1.8, 0.5, 0.9))
	BuildKit.box(self, null, dark, Vector3(-hw + 1.0, 0.70, -hd + 1.0),
		Vector3(1.7, 0.14, 0.8), Vector3.ZERO, false)
	BuildKit.box(self, body, plank, Vector3(hw - 0.8, 0.38, -hd + 0.9),
		Vector3(0.8, 0.7, 0.8), Vector3(0, 0.3, 0))

	# --- a real door in the opening ---------------------------------------
	# 0.1 left a hole in the wall. A doorway with nothing in it is not a
	# door, and section 22 wants a building that behaves like a building.
	door = Door.new()
	door.name = "CabinDoor"
	door.leaf_width = door_width - 0.08
	door.leaf_height = wall_height - 0.5
	door.build_frame = false          # the wall already has its posts
	door.open_angle_deg = -100.0      # swings outward, away from the bunk
	door.position = Vector3(0.0, 0.14, hd - t * 0.5)
	add_child(door)

	# --- a warm interior light, which is also what makes the doorway read --
	var lamp := OmniLight3D.new()
	lamp.name = "CabinLamp"
	lamp.position = Vector3(0, wall_height - 0.55, -0.4)
	lamp.light_color = Color(1.0, 0.82, 0.58)
	lamp.light_energy = 1.9
	lamp.omni_range = 7.0
	lamp.shadow_enabled = false
	add_child(lamp)
	var bulb := BuildKit.cylinder(self, null,
		BuildKit.material(Color(1.0, 0.86, 0.6), 0.4, 0.0, Color(1.0, 0.8, 0.5), 2.4),
		Vector3(0, wall_height - 0.5, -0.4), 0.09, 0.16, Vector3.ZERO, false, 6)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Nothing on the cabin moves, so it can all collapse to one mesh per
	# material — about thirty draw calls down to five.
	# The door swings, so it is excluded from the static merge.
	merged_away = BuildKit.merge_by_material(self, [door])
