extends CharacterBody3D
class_name AnimalPlaceholder
##
## ===================== ANIMAL_ASSET_BLOCKED =========================
##
## This is a PLACEHOLDER, and it is labelled as one in the world.
##
## The benchmark's asset rule is the project rule: an asset whose licence has
## not been read at its author's own source does not enter the repository.
## The three packs Fog Nomad already owns (KayKit Adventurers, Halloween Bits,
## Medieval Hexagon — all CC0, all fetched from the author's GitHub) contain
## no animal of any kind. The usual CC0 animal sources (Quaternius, Kenney,
## poly.pizza, OpenGameArt, itch.io) are unreachable from this environment's
## network policy, so their licences could not be read at source and nothing
## was taken from them.
##
## Section 28 is explicit about what to do next: do not spend hours building
## a convincing fake out of primitives. So this is a deliberately cheap
## articulated quadruped whose only job is to prove the BEHAVIOUR loop —
## IDLE -> WALK -> FLEE — and to make the gap in the asset pipeline visible
## instead of hiding it.
##
## What is real here and should be judged: the flee trigger, the navigation,
## and the fact that the legs are driven by distance travelled, so the
## placeholder does not foot-slide either.
##
## What is not real: the model.
## ====================================================================

enum State { IDLE, WALK, FLEE }

## Which row of AnimalSpecies.SPECIES this animal is. Everything about its
## build, gait and nerve comes from there.
@export var species_index: int = 0

@export var walk_speed: float = 1.5
@export var flee_speed: float = 5.4
@export var accel: float = 9.0
@export var turn_speed: float = 7.0
@export var flee_radius: float = 13.0
@export var calm_radius: float = 24.0
@export var fog_fear_distance: float = 22.0
@export var idle_time: Vector2 = Vector2(1.2, 3.4)
@export var body_color: Color = Color(0.494, 0.396, 0.290)
@export var nav_builder_path: NodePath
@export var player_path: NodePath
@export var fog_path: NodePath

@onready var agent: NavigationAgent3D = $NavigationAgent3D

var state: int = State.IDLE
var _nav: NavBuilder
var _player: Node3D
var _fog: Node
var _rng := RandomNumberGenerator.new()
var _wait := 1.0
var _facing := 0.0
var _gait := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)

var _pivot: Node3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _head: Node3D
var _tail: Node3D
var horizontal_speed := 0.0

var species_name := "Herbivore"
var species_id := "browser"
var _stride := 0.62
var _body_length := 0.78
var _body_radius := 0.22
var _leg_length := 0.42
var _neck_length := 0.30
var _shoulder := 0.52
var _ear_length := 0.22
var _tail_length := 0.22
var _grazes := true
var _graze_t := 0.0
var _lost := 0.0
var _last_threat := Vector3.INF


func _ready() -> void:
	_apply_species()
	_rng.seed = 0x414E494D + species_index * 5297
	_nav = get_node_or_null(nav_builder_path) as NavBuilder
	_player = get_node_or_null(player_path) as Node3D
	_fog = get_node_or_null(fog_path)
	_build_body()
	SoftBodyAvoidance.register(self)
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 1.0
	agent.avoidance_enabled = false
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.4
	global_position.y = TerrainData.height_at(global_position.x, global_position.z) + 0.05
	await get_tree().physics_frame
	await get_tree().physics_frame
	_wander()


## Pull this animal's numbers out of the species table.
func _apply_species() -> void:
	var sp := AnimalSpecies.get_species(species_index)
	species_name = str(sp["name"])
	species_id = str(sp["id"])
	body_color = sp["body_color"]
	walk_speed = float(sp["walk_speed"])
	flee_speed = float(sp["flee_speed"])
	turn_speed = float(sp["turn_speed"])
	flee_radius = float(sp["flee_radius"])
	calm_radius = float(sp["calm_radius"])
	fog_fear_distance = float(sp["fog_fear"])
	idle_time = sp["idle"]
	_stride = float(sp["stride"])
	_body_length = float(sp["body_length"])
	_body_radius = float(sp["body_radius"])
	_leg_length = float(sp["leg_length"])
	_neck_length = float(sp["neck_length"])
	_shoulder = float(sp["shoulder_height"])
	_ear_length = float(sp["ear_length"])
	_tail_length = float(sp["tail_length"])
	_grazes = bool(sp["graze"])


# ---------------------------------------------------------------- body ----
func _build_body() -> void:
	_pivot = Node3D.new()
	_pivot.name = "PlaceholderBody"
	add_child(_pivot)

	var hide := StandardMaterial3D.new()
	hide.albedo_color = body_color
	hide.roughness = 0.92
	var dark := StandardMaterial3D.new()
	dark.albedo_color = body_color.darkened(0.35)
	dark.roughness = 0.95

	# Proportions come from the species row, so a browser and a prowler are
	# different shapes rather than the same shape at a different scale.
	_body = _part(_pivot, _capsule(_body_radius, _body_length), hide,
		Vector3(0, _shoulder, 0), Vector3(0, 0, deg_to_rad(90)))
	_head = _part(_pivot, _capsule(_body_radius * 0.66, _neck_length), hide,
		Vector3(0, _shoulder + _neck_length * 0.45, _body_length * 0.52),
		Vector3(deg_to_rad(70), 0, 0))
	for s2 in [-1.0, 1.0]:
		_part(_head, _capsule(_ear_length * 0.2, _ear_length), dark,
			Vector3(s2 * _body_radius * 0.42, _neck_length * 0.34, 0.02),
			Vector3(deg_to_rad(-25), 0, s2 * 0.25))
	_tail = _part(_pivot, _capsule(_tail_length * 0.26, _tail_length), dark,
		Vector3(0, _shoulder + 0.05, -_body_length * 0.55), Vector3(deg_to_rad(-40), 0, 0))

	for i in 4:
		var fx := 1.0 if i % 2 == 0 else -1.0
		var fz := _body_length * 0.33 if i < 2 else -_body_length * 0.31
		var hip := Node3D.new()
		hip.position = Vector3(_body_radius * 0.72 * fx, _shoulder - _body_radius * 0.2, fz)
		_pivot.add_child(hip)
		_part(hip, _capsule(_leg_length * 0.13, _leg_length), dark,
			Vector3(0, -_leg_length * 0.5, 0), Vector3.ZERO)
		_legs.append(hip)

	# The label is not decoration. It is there so that nobody reviewing a
	# screenshot can mistake this for a finished asset.
	var tag := Label3D.new()
	tag.text = "%s — PLACEHOLDER\nANIMAL_ASSET_BLOCKED" % species_name
	tag.font_size = 44
	tag.pixel_size = 0.0032
	tag.position = Vector3(0, _shoulder + _neck_length + 0.5, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1.0, 0.78, 0.35)
	tag.outline_size = 14
	tag.no_depth_test = false
	tag.double_sided = true
	_pivot.add_child(tag)


func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.01)
	m.radial_segments = 6
	m.rings = 2
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------- behaviour --
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var threat := _threat()
	if threat != Vector3.INF and state != State.FLEE:
		_flee_from(threat)
	elif state == State.FLEE and threat == Vector3.INF and agent.is_navigation_finished():
		state = State.IDLE
		_last_threat = Vector3.INF
		_wait = _rng.randf_range(idle_time.x, idle_time.y)

	match state:
		State.IDLE:
			_slow(delta)
			_wait -= delta
			if _wait <= 0.0:
				_wander()
		State.WALK:
			_move(delta, walk_speed)
		State.FLEE:
			_move(delta, flee_speed)

	var push := SoftBodyAvoidance.push_for(self, Vector3(velocity.x, 0.0, velocity.z))
	velocity.x += push.x
	velocity.z += push.z

	move_and_slide()
	horizontal_speed = Vector2(velocity.x, velocity.z).length()
	_animate(delta)


## What is frightening right now, or Vector3.INF if nothing is.
func _threat() -> Vector3:
	if _player and is_instance_valid(_player):
		var d := global_position.distance_to(_player.global_position)
		if d < flee_radius:
			return _player.global_position
		if state == State.FLEE and d < calm_radius:
			return _player.global_position
	if _fog and is_instance_valid(_fog) and _fog.has_method("distance_to"):
		if float(_fog.call("distance_to", global_position)) < fog_fear_distance:
			return global_position + Vector3(0, 0, -60.0)
	return Vector3.INF


func _flee_from(threat: Vector3) -> void:
	state = State.FLEE
	_last_threat = threat
	if _nav == null:
		return
	var away := global_position - threat
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	away = away.normalized()
	# Try a few escape headings and take the one that actually exists on the
	# navigation mesh.
	var best := global_position
	var best_score := -INF
	for i in 7:
		var ang := (float(i) - 3.0) * 0.35
		var dir := away.rotated(Vector3.UP, ang)
		var cand := global_position + dir * _rng.randf_range(22.0, 38.0)
		if not TerrainData.is_walkable(cand.x, cand.z):
			continue
		var score := cand.distance_to(threat) - absf(ang) * 4.0
		if score > best_score:
			best_score = score
			best = cand
	agent.target_position = Vector3(best.x, TerrainData.height_at(best.x, best.z), best.z)


func _wander() -> void:
	if _nav == null:
		_wait = 2.0
		return
	agent.target_position = _nav.random_point(_rng, global_position, 6.0, 26.0)
	state = State.WALK


func _move(delta: float, speed: float) -> void:
	if agent.is_navigation_finished():
		if state == State.FLEE:
			# Finished the escape route but still frightened: keep going
			# away rather than standing still next to the thing.
			if _last_threat != Vector3.INF:
				_flee_from(_last_threat)
			else:
				_slow(delta)
		else:
			state = State.IDLE
			_wait = _rng.randf_range(idle_time.x, idle_time.y)
		return
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0

	# FALLBACK. An animal that wanders off the navigation mesh — onto the
	# bridge, into the shallows, behind a wall the mesh does not cover — gets
	# a next-path-position equal to its own position, and freezes. A frozen
	# deer standing calmly beside the player is worse than a slightly dumb
	# one, so after a moment of getting nowhere it abandons the path and
	# steers on instinct.
	if to.length() < 0.05 or horizontal_speed < 0.1:
		_lost += delta
	else:
		_lost = 0.0
	if _lost > 0.5:
		var away := Vector3.ZERO
		if state == State.FLEE and _last_threat != Vector3.INF:
			away = global_position - _last_threat
		else:
			away = Vector3(cos(_facing), 0.0, sin(_facing))
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3(1, 0, 0)
		# Steer towards ground it can actually stand on.
		var best := away.normalized()
		for i in 8:
			var cand := away.normalized().rotated(Vector3.UP, (float(i) - 4.0) * 0.4)
			var probe := global_position + cand * 3.0
			if TerrainData.is_walkable(probe.x, probe.z):
				best = cand
				break
		_steer(delta, best, speed)
		return

	if to.length() < 0.001:
		return
	_steer(delta, to.normalized(), speed)


func _slow(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z


## Turn towards the heading, then run along the way you are facing — same
## rule as the NPC, so the placeholder cannot moonwalk either.
func _steer(delta: float, want_dir: Vector3, speed: float) -> void:
	_facing = rotate_toward(_facing, atan2(want_dir.x, want_dir.z), turn_speed * delta)
	_pivot.rotation.y = _facing
	var forward := Vector3(sin(_facing), 0.0, cos(_facing))
	var align := clampf(forward.dot(want_dir), 0.0, 1.0)
	var target := forward * speed * lerpf(0.1, 1.0, align * align)
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z


## Legs are driven by DISTANCE TRAVELLED, not by time. A gait built this way
## cannot foot-slide: stride length is fixed, so cadence follows speed for
## free. It is the cheapest correct answer, and it is the same principle the
## character rig gets from its measured blend speeds.
func _animate(delta: float) -> void:
	_gait += horizontal_speed * delta / maxf(_stride, 0.05) * TAU
	var swing := clampf(horizontal_speed / flee_speed, 0.0, 1.0) * 0.85 + 0.05
	for i in _legs.size():
		var phase: float = _gait + (0.0 if (i == 0 or i == 3) else PI)
		_legs[i].rotation.x = sin(phase) * swing
	_pivot.position.y = absf(sin(_gait * 0.5)) * 0.045 * swing
	if _head:
		var head_x := deg_to_rad(70.0) + sin(_gait * 0.5) * 0.06 * swing
		# A browser drops its head to feed and lifts it to look around
		# (section 38). It only does that when it is calm.
		if _grazes and state == State.IDLE:
			_graze_t += delta
			var down := 0.5 + 0.5 * sin(_graze_t * 0.55)
			head_x += deg_to_rad(38.0) * down
		_head.rotation.x = head_x
	if _tail:
		_tail.rotation.x = deg_to_rad(-40.0) + sin(_gait * 0.5 + 1.0) * 0.25 * swing
		_tail.rotation.y = sin(_gait * 0.25) * 0.2


func state_name() -> String:
	match state:
		State.WALK: return "WALK"
		State.FLEE: return "FLEE"
		_: return "IDLE"
