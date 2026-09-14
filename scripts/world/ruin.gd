extends Node3D
class_name Ruin
##
## A small explorable ruin (sections 24, 43).
##
## Section 24 names the failure mode precisely: do not wrap the whole ruin in
## one big collider that blocks the passages you can see. So walls here are
## built as RUNS WITH GAPS. A run is a line with a height; a gap is a stretch
## of that line where no segment — and therefore no collider — is emitted.
##
## The consequence is that the physics and the picture come from the same
## description. A hole you can see is a hole you can walk through, because
## the hole is the absence of a wall segment rather than a decision someone
## remembered to make twice.
##
## Contains, per section 43: an entrance with a real door, a collapsed
## breach you can climb through, an interior you can stand in, an
## interactive pillar, and a crystal to find.

@export var width: float = 13.0
@export var depth: float = 9.5
@export var wall_height: float = 3.2
@export var wall_thickness: float = 0.55

var door: Door
var pillar: StonePillar

var _body: StaticBody3D
var _stone: StandardMaterial3D
var _stone_dark: StandardMaterial3D
var _rubble: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

var footprint_radius: float:
	get: return maxf(width, depth) * 0.78


func _ready() -> void:
	_rng.seed = 0x5255494E
	_stone = BuildKit.material(Color(0.376, 0.365, 0.345), 0.94)
	_stone_dark = BuildKit.material(Color(0.267, 0.259, 0.247), 0.95)
	_rubble = BuildKit.material(Color(0.31, 0.298, 0.278), 0.96)

	_body = StaticBody3D.new()
	_body.name = "RuinCollision"
	_body.collision_layer = Layers.WORLD_STATIC
	_body.collision_mask = 0
	SurfaceType.tag(_body, SurfaceType.Kind.ROCK)
	add_child(_body)

	var hw := width * 0.5
	var hd := depth * 0.5

	# --- floor: sunken flagstones, walkable ------------------------------
	BuildKit.box(self, _body, _stone_dark, Vector3(0, -0.12, 0),
		Vector3(width + 0.6, 0.3, depth + 0.6))

	# --- north wall: the entrance, with a doorway gap ---------------------
	# The gap is 1.25 wide and the door leaf fills it.
	_wall_run(Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), wall_height,
		[Vector2(0.44, 0.56)], 1.0)

	# --- east wall: intact for half, then collapsed to a low stub ---------
	_wall_run(Vector3(hw, 0, -hd), Vector3(hw, 0, hd), wall_height,
		[Vector2(0.52, 0.78)], 1.0)
	# The collapsed stretch survives as knee-high rubble you step over: it
	# is still solid, it is just not a wall any more.
	_wall_run(Vector3(hw, 0, -hd), Vector3(hw, 0, hd), 0.55,
		[Vector2(0.0, 0.52), Vector2(0.78, 1.0)], 1.0)

	# --- south wall: a breach wide enough to walk through -----------------
	_wall_run(Vector3(hw, 0, hd), Vector3(-hw, 0, hd), wall_height * 0.82,
		[Vector2(0.33, 0.55)], 1.0)

	# --- west wall: intact, with a window too high to climb ---------------
	_wall_run(Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd), wall_height,
		[], 1.0)
	# Window: a gap in the UPPER half only, so the wall below stays solid.
	_window(Vector3(-hw, 0, 0.0), Vector3(0, 0, 1), 1.6, 1.05, 1.5)

	# --- corner buttresses, broken to different heights -------------------
	var corners := [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	var heights := [wall_height + 0.7, wall_height + 0.2, 1.1, wall_height * 0.6]
	for i in corners.size():
		var c: Vector2 = corners[i]
		var h: float = heights[i]
		BuildKit.box(self, _body, _stone, Vector3(c.x, h * 0.5, c.y),
			Vector3(wall_thickness * 1.7, h, wall_thickness * 1.7))

	# --- the door in the north gap ----------------------------------------
	door = Door.new()
	door.name = "RuinDoor"
	door.leaf_width = 1.2
	door.leaf_height = 2.3
	door.build_frame = true
	door.position = Vector3(width * (0.5 - 0.5) + (0.5 - 0.5) * width, 0.0, -hd)
	door.position = Vector3(lerpf(-hw, hw, 0.5), 0.0, -hd)
	add_child(door)

	# --- the pillar at the heart of it ------------------------------------
	pillar = StonePillar.new()
	pillar.name = "StonePillar"
	pillar.position = Vector3(0.0, 0.0, 0.6)
	add_child(pillar)

	# --- fallen blocks: solid, and scattered so they read as collapse -----
	for _i in 7:
		var p := Vector3(_rng.randf_range(-hw + 1.2, hw - 1.2), 0.0,
			_rng.randf_range(-hd + 1.2, hd - 1.2))
		if Vector2(p.x, p.z).length() < 2.2:
			continue
		var sz := Vector3(_rng.randf_range(0.5, 1.1), _rng.randf_range(0.35, 0.8),
			_rng.randf_range(0.5, 1.1))
		BuildKit.box(self, _body, _stone, Vector3(p.x, sz.y * 0.5, p.z), sz,
			Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(0.0, TAU),
				_rng.randf_range(-0.1, 0.1)))

	# --- rubble: decoration, deliberately NOT solid -----------------------
	# Section 17's exception. Small debris you scuff through, not obstacles.
	for _i in 22:
		var p := Vector3(_rng.randf_range(-hw, hw), 0.0, _rng.randf_range(-hd, hd))
		var sz := _rng.randf_range(0.12, 0.3)
		BuildKit.box(self, null, _rubble, Vector3(p.x, sz * 0.35, p.z),
			Vector3(sz, sz * 0.7, sz * 1.2),
			Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0), false)

	# Merge the static stonework; the door and pillar animate, so they stay out.
	BuildKit.merge_by_material(self, [door, pillar])


## Build a wall along a line, skipping the stretches listed in `gaps`
## (normalised 0..1 along the run). Each emitted stretch is its own box and
## its own collider, which is what makes the gaps genuinely walkable.
func _wall_run(from: Vector3, to: Vector3, height: float, gaps: Array,
		_thick_scale: float) -> void:
	var span := to - from
	var length := span.length()
	if length < 0.01 or height <= 0.0:
		return
	var dir := span / length
	var yaw := atan2(dir.x, dir.z)

	# Turn the gap list into the complementary list of solid stretches.
	var cuts := gaps.duplicate()
	cuts.sort_custom(func(a, b): return a.x < b.x)
	var solids: Array[Vector2] = []
	var cursor := 0.0
	for g in cuts:
		var gv: Vector2 = g
		if gv.x > cursor:
			solids.append(Vector2(cursor, gv.x))
		cursor = maxf(cursor, gv.y)
	if cursor < 1.0:
		solids.append(Vector2(cursor, 1.0))

	for sspan in solids:
		var seg_len := (sspan.y - sspan.x) * length
		if seg_len < 0.12:
			continue
		var mid_t := (sspan.x + sspan.y) * 0.5
		var centre := from + dir * (mid_t * length)
		# Break the top edge so it reads as ruined rather than as demolished
		# to a neat line.
		var h := height * _rng.randf_range(0.82, 1.0)
		BuildKit.box(self, _body, _stone,
			Vector3(centre.x, h * 0.5, centre.z),
			Vector3(seg_len, h, wall_thickness),
			Vector3(0.0, yaw + PI * 0.5, 0.0))
		# A few loose stones on the crest.
		for _i in int(seg_len / 1.6):
			var t := _rng.randf()
			var p := from + dir * lerpf(sspan.x, sspan.y, t) * length
			BuildKit.box(self, null, _stone_dark,
				Vector3(p.x, h + 0.1, p.z),
				Vector3(0.3, 0.2, wall_thickness * 0.9),
				Vector3(0.0, yaw + PI * 0.5 + _rng.randf_range(-0.3, 0.3), 0.0), false)


## A wall with an opening in its upper half: solid below, open above.
## You can see through it and shoot light through it; you cannot walk
## through it, and the collider says the same thing the picture does.
func _window(centre: Vector3, dir: Vector3, opening_width: float,
		sill_height: float, opening_height: float) -> void:
	var yaw := atan2(dir.x, dir.z)
	# Below the sill: solid.
	BuildKit.box(self, _body, _stone,
		Vector3(centre.x, sill_height * 0.5, centre.z),
		Vector3(opening_width, sill_height, wall_thickness),
		Vector3(0.0, yaw + PI * 0.5, 0.0))
	# Above the opening: solid lintel.
	var top := sill_height + opening_height
	BuildKit.box(self, _body, _stone,
		Vector3(centre.x, top + (wall_height - top) * 0.5, centre.z),
		Vector3(opening_width, maxf(wall_height - top, 0.1), wall_thickness),
		Vector3(0.0, yaw + PI * 0.5, 0.0))
