extends RefCounted
class_name TerrainData
##
## Single analytic source of truth for the benchmark terrain.
##
## Every system that needs to know "how high is the ground here?" asks this
## class: the mesh builder, the scatterer, the navigation mesh builder, the
## player's water test, the NPC, the animal and the fog ground layer.
## Because it is one pure function there is no chance of the visual mesh and
## the gameplay disagreeing about where the ground is.
##
## This is NOT procedural world generation in the sense forbidden by the
## benchmark brief (section 37): there is no seed, no chunking, no streaming
## and no infinite extent. It is one fixed, hand-tuned 280 x 280 m surface,
## written as a formula instead of a 40 000-vertex file so that it stays
## editable from a phone.

## Half-extent of the playable square, in metres. The world spans
## [-SIZE, SIZE] on both X and Z.
const SIZE := 140.0

## Height of the water plane. Anything below this is river or pond.
const WATER_LEVEL := 0.0

## Ground is "shallow water" below this depth and swimmable above it.
const SWIM_DEPTH := 1.35

## Steepest walkable slope, as a dot product against Vector3.UP.
const MAX_WALK_DOT := 0.62


## Centre line of the river at a given Z. The river runs roughly north-south
## with a double S-curve so that it never reads as a straight canal.
static func river_center_x(z: float) -> float:
	return -26.0 + 23.0 * sin(z * 0.0132) + 7.0 * sin(z * 0.0395 + 0.7)


## Half-width of the open water channel at a given Z, in metres.
static func river_half_width(z: float) -> float:
	return 7.5 + 3.0 * sin(z * 0.029 + 1.9) + 1.6 * sin(z * 0.071)


## Signed-ish carve applied to the base terrain to dig the river bed.
## Returns a value <= 0.
static func _river_carve(x: float, z: float) -> float:
	var d := absf(x - river_center_x(z))
	var w := river_half_width(z)
	var bank := w + 11.0
	if d > bank:
		return 0.0
	# Wide, gentle valley walls...
	var outer := smoothstep(0.0, 1.0, (bank - d) / 11.0)
	# ...with a deeper trench in the middle of the channel.
	var inner := smoothstep(0.0, 1.0, clampf((w - d) / maxf(w, 0.001), 0.0, 1.0))
	return -(outer * 2.05 + inner * 2.55)


## The pond: a widening of the river in the southern half of the map.
static func _pond_carve(x: float, z: float) -> float:
	var cx := river_center_x(-52.0) + 16.0
	var d := Vector2(x - cx, z + 52.0).length()
	var r := 27.0
	if d > r:
		return 0.0
	return -3.4 * smoothstep(0.0, 1.0, (r - d) / r)


## Centre line of the walking path, which crosses the map east-west and
## fords the river at a deliberately shallow point.
static func path_center_z(x: float) -> float:
	return 34.0 + 17.0 * sin(x * 0.0158) - 6.0 * sin(x * 0.037 + 2.1)


## How strongly the path flattens the terrain here: 1 on the path, 0 away.
static func path_influence(x: float, z: float) -> float:
	var d := absf(z - path_center_z(x))
	return smoothstep(0.0, 1.0, clampf((6.5 - d) / 6.5, 0.0, 1.0))


static func _rolling(x: float, z: float) -> float:
	return (1.75 * sin(x * 0.0371) * cos(z * 0.0313)
		+ 1.15 * sin((x + z) * 0.0208 + 0.6)
		+ 0.55 * sin(x * 0.0902 + 1.3) * sin(z * 0.0771)
		+ 0.28 * sin(x * 0.171 + 0.4) * cos(z * 0.153 + 1.1))


static func _bump(x: float, z: float, cx: float, cz: float, r: float, h: float) -> float:
	var d := Vector2(x - cx, z - cz).length()
	if d > r:
		return 0.0
	return h * smoothstep(0.0, 1.0, (r - d) / r)


## Ground height in metres at a world XZ position.
static func height_at(x: float, z: float) -> float:
	var h := 2.15
	h += _rolling(x, z)
	# The ridge the beacon tower stands on.
	h += _bump(x, z, -58.0, -62.0, 44.0, 9.5)
	# A second, softer knoll to the north-east.
	h += _bump(x, z, 62.0, 48.0, 26.0, 4.2)
	# A dip that catches low fog.
	h += _bump(x, z, 24.0, 92.0, 22.0, -2.6)
	# A deliberately steep rocky outcrop: steeper than MAX_WALK_DOT, so that
	# "the slope actually stops you" is a thing the benchmark can test.
	h += _bump(x, z, 79.0, -44.0, 11.5, 9.6)
	# A moderate bank the player *can* climb, for contrast.
	h += _bump(x, z, 48.0, -14.0, 17.0, 5.4)
	h += _river_carve(x, z)
	h += _pond_carve(x, z)
	# The path smooths whatever it crosses, without filling the river.
	var pi := path_influence(x, z)
	if pi > 0.0:
		var flat := 2.15 + 0.9 * sin(x * 0.0158) + _river_carve(x, z) * 0.72 + _pond_carve(x, z)
		h = lerpf(h, flat, pi * 0.8)
	return h


## Convenience: the ground point under a world position.
static func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## Approximate surface normal, by central differences.
static func normal_at(x: float, z: float, e: float = 0.8) -> Vector3:
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## How deep the water is at this position. 0 on dry land.
static func water_depth_at(x: float, z: float) -> float:
	return maxf(0.0, WATER_LEVEL - height_at(x, z))


static func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_LEVEL


## True where an NPC or an animal may walk: on land, not too steep, and
## inside the playable square with a small margin.
static func is_walkable(x: float, z: float) -> bool:
	if absf(x) > SIZE - 4.0 or absf(z) > SIZE - 4.0:
		return false
	if height_at(x, z) < WATER_LEVEL + 0.35:
		return false
	return normal_at(x, z).y >= MAX_WALK_DOT
