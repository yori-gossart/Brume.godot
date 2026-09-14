extends RefCounted
class_name ForestComposition
##
## Where things grow (section 16).
##
## The 0.1 scatterer was honest about what it was: rejection sampling with a
## minimum spacing. That gives an even, poissonish field — which reads as
## "random tree every X metres" from the first clearing you stand in, and is
## exactly what section 16 rules out.
##
## Real woodland is not evenly spaced. It is stands and gaps: dense groves,
## open glades between them, a thinned edge where the light gets in, isolated
## veterans out in the open, scrub that only grows under a canopy, and rock
## that brings its own little community of lichen and low growth.
##
## So placement here is POLICY-driven. Each species declares where it belongs
## and the sampler respects it:
##
##   GROVE        clustered into stands, denser towards the middle
##   EDGE         the thinned rim of a stand, where a grove meets open ground
##   ISOLATED     out in the open, deliberately far from any stand
##   ROADSIDE     following the path, on the verge but never on it
##   ROCKY        around the boulder fields
##   UNDERGROWTH  only beneath an existing canopy
##   SHORE        the damp margin near water
##
## Stands and glades are generated once from the fixed layout seed and then
## used by every species, so the composition is one coherent wood rather than
## seven independent scatters that happen to overlap.

enum Policy { GROVE, EDGE, ISOLATED, ROADSIDE, ROCKY, UNDERGROWTH, SHORE }

## A stand of trees: centre, radius, and how tightly it clumps.
class Stand extends RefCounted:
	var centre: Vector2
	var radius: float
	var density: float
	func _init(c: Vector2, r: float, d: float) -> void:
		centre = c; radius = r; density = d

var stands: Array[Stand] = []
var glades: Array[Vector3] = []      ## x, z, radius — kept clear of canopy
var rock_fields: Array[Vector3] = [] ## x, z, radius

var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Lay out the stands, the glades between them and the boulder fields.
## `reserved` are the keep-out circles of the buildings and the spawn.
func compose(reserved: Array[Vector3]) -> void:
	var lim := TerrainData.SIZE - 26.0

	# --- stands ----------------------------------------------------------
	# Deliberately uneven: a few big dense woods, several medium stands, and
	# a handful of small thickets. Equal-sized stands read as wallpaper.
	var wanted := [
		{"r": [30.0, 38.0], "d": [0.85, 1.0], "n": 3},
		{"r": [18.0, 26.0], "d": [0.6, 0.85], "n": 5},
		{"r": [10.0, 15.0], "d": [0.45, 0.7], "n": 6},
	]
	for w in wanted:
		for _i in int(w["n"]):
			for _try in 80:
				var p := Vector2(_rng.randf_range(-lim, lim), _rng.randf_range(-lim, lim))
				if not TerrainData.is_walkable(p.x, p.y):
					continue
				if TerrainData.height_at(p.x, p.y) < TerrainData.WATER_LEVEL + 1.5:
					continue
				# Stands do not sit on the path — the path is how you see the wood.
				if TerrainData.path_influence(p.x, p.y) > 0.15:
					continue
				var r := _rng.randf_range(w["r"][0], w["r"][1])
				if _clashes(p, r * 0.55, reserved):
					continue
				if _too_close_to_stands(p, r * 0.5):
					continue
				stands.append(Stand.new(p, r, _rng.randf_range(w["d"][0], w["d"][1])))
				break

	# --- glades: openings punched inside the larger stands ----------------
	for s in stands:
		if s.radius < 20.0:
			continue
		for _i in (2 if s.radius > 30.0 else 1):
			var a := _rng.randf_range(0.0, TAU)
			var d := _rng.randf_range(0.15, 0.55) * s.radius
			var g := s.centre + Vector2(cos(a), sin(a)) * d
			glades.append(Vector3(g.x, g.y, _rng.randf_range(6.0, 11.0)))

	# --- rock fields ------------------------------------------------------
	for _i in 5:
		for _try in 80:
			var p := Vector2(_rng.randf_range(-lim, lim), _rng.randf_range(-lim, lim))
			if not TerrainData.is_walkable(p.x, p.y):
				continue
			if TerrainData.height_at(p.x, p.y) < TerrainData.WATER_LEVEL + 1.0:
				continue
			if _clashes(p, 10.0, reserved):
				continue
			rock_fields.append(Vector3(p.x, p.y, _rng.randf_range(11.0, 20.0)))
			break
	# The steep outcrop is a rock field by definition.
	rock_fields.append(Vector3(79.0, -44.0, 16.0))


func _clashes(p: Vector2, r: float, reserved: Array[Vector3]) -> bool:
	for c in reserved:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + r:
			return true
	return false


func _too_close_to_stands(p: Vector2, r: float) -> bool:
	for s in stands:
		if p.distance_to(s.centre) < (s.radius + r) * 0.72:
			return true
	return false


## How much canopy covers this point: 1 deep inside a stand, 0 in the open.
## Glades punch holes in it.
func canopy_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for s in stands:
		var d := p.distance_to(s.centre)
		if d < s.radius:
			best = maxf(best, s.density * (1.0 - smoothstep(0.55, 1.0, d / s.radius)))
	for g in glades:
		var d := p.distance_to(Vector2(g.x, g.y))
		if d < g.z:
			best *= smoothstep(0.0, 1.0, d / g.z)
	return clampf(best, 0.0, 1.0)


func rock_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 0.0
	for f in rock_fields:
		var d := p.distance_to(Vector2(f.x, f.y))
		if d < f.z:
			best = maxf(best, 1.0 - smoothstep(0.4, 1.0, d / f.z))
	return best


## Propose a candidate position for a species with the given policy.
## Returns Vector2.INF when the policy has nowhere to put it this attempt.
func propose(policy: int) -> Vector2:
	var lim := TerrainData.SIZE - 8.0
	match policy:
		Policy.GROVE, Policy.EDGE, Policy.UNDERGROWTH:
			if stands.is_empty():
				return Vector2.INF
			var s: Stand = stands[_rng.randi() % stands.size()]
			var a := _rng.randf_range(0.0, TAU)
			var t: float
			if policy == Policy.EDGE:
				# Out at the rim, where a stand thins into open ground.
				t = _rng.randf_range(0.72, 1.05)
			else:
				# sqrt keeps the disc evenly filled, then bias inwards so the
				# middle of a stand is genuinely denser than its edge.
				t = sqrt(_rng.randf())
				t = lerpf(t, t * t, 0.55)
			return s.centre + Vector2(cos(a), sin(a)) * (s.radius * t)
		Policy.ROCKY:
			if rock_fields.is_empty():
				return Vector2.INF
			var f: Vector3 = rock_fields[_rng.randi() % rock_fields.size()]
			var a2 := _rng.randf_range(0.0, TAU)
			return Vector2(f.x, f.y) + Vector2(cos(a2), sin(a2)) * (f.z * sqrt(_rng.randf()))
		Policy.ROADSIDE:
			var x := _rng.randf_range(-lim, lim)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var off := _rng.randf_range(7.0, 15.0) * side
			return Vector2(x, TerrainData.path_center_z(x) + off)
		Policy.SHORE:
			for _i in 30:
				var p := Vector2(_rng.randf_range(-lim, lim), _rng.randf_range(-lim, lim))
				var h := TerrainData.height_at(p.x, p.y)
				if h > TerrainData.WATER_LEVEL + 0.15 and h < TerrainData.WATER_LEVEL + 1.4:
					return p
			return Vector2.INF
		_:
			return Vector2(_rng.randf_range(-lim, lim), _rng.randf_range(-lim, lim))


## Does this candidate satisfy its policy's context requirement?
func accepts(policy: int, p: Vector2) -> bool:
	match policy:
		Policy.ISOLATED:
			# A lone tree has to actually be alone, or it is just a grove tree.
			return canopy_at(p.x, p.y) < 0.12
		Policy.UNDERGROWTH:
			return canopy_at(p.x, p.y) > 0.35
		Policy.GROVE:
			return canopy_at(p.x, p.y) > 0.08
		Policy.EDGE:
			var c := canopy_at(p.x, p.y)
			return c > 0.02 and c < 0.45
		Policy.ROCKY:
			return rock_at(p.x, p.y) > 0.15
		_:
			return true


static func policy_from_name(n: String) -> int:
	match n:
		"grove": return Policy.GROVE
		"edge": return Policy.EDGE
		"isolated": return Policy.ISOLATED
		"roadside": return Policy.ROADSIDE
		"rocky": return Policy.ROCKY
		"undergrowth": return Policy.UNDERGROWTH
		"shore": return Policy.SHORE
		_: return Policy.GROVE
